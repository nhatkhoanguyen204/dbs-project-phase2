# CSMS Phase 2 Requirement Change Analysis — Group 13

## 1. Change Summary

Phase 2 replaces the Phase 1 assumption that every active maintenance record blocks its space. Each active `MaintenanceRecord` now has an impact level:

| Impact level | Booking effect | Required user evidence |
|---|---|---|
| `out-of-service` | Blocks a new approval or auto-approval when its interval overlaps the maintenance interval. | No acknowledgement can make the space bookable. |
| `advisory` | Does not block the booking; the space remains bookable if all other rules pass. | The requester must be shown every overlapping active advisory and each advisory must be acknowledged before approval. |

Several active records may exist for one space at the same time. Consequently, availability is not a property of `Space.current_status` alone: it is evaluated per requested interval against all active maintenance records. One overlapping `out-of-service` record blocks the interval even if other records are advisory.

## 2. Affected Entities and Relationship Changes

| Existing entity | Change | Purpose / rule enforced |
|---|---|---|
| `MaintenanceRecord` | Add required `impact_level` (`advisory` or `out-of-service`). | Distinguishes a non-blocking equipment/comfort warning from a blocking outage. It is meaningful for active records and retained historically after completion/cancellation. |
| `MaintenanceRecord` | Audit impact-level changes, preferably with `MaintenanceImpactHistory(impact_history_id, maintenance_id, prior_impact_level, new_impact_level, changed_by_user_id, changed_at, change_note)`. | Makes escalation/downgrade accountable and establishes the exact escalation event used for contact/reporting. If an audit table is not added, equivalent immutable audit data is required. |
| `Booking` | No single boolean is sufficient where multiple advisories overlap. `Booking` remains the parent of acknowledgement records. | A booking can overlap zero, one, or many advisory records. |
| New `BookingMaintenanceAdvisoryAcknowledgement` | Add `(booking_id, maintenance_id)` as the primary key, plus `acknowledged_at` and optionally `advisory_summary_at_acknowledgement`. | Stores that the requester was informed about each specific advisory. The composite key prevents duplicate acknowledgement of the same advisory for the same booking. Both columns are foreign keys to the existing transaction entities. |
| `BookingPolicy` / policy configuration | Add an explicit auto-approval eligibility setting by applicable space, role, purpose, and/or space type. | Defines which otherwise-valid requests may be approved immediately; remaining requests stay `Pending` for staff action. |
| `BookingDecision` | Continue to distinguish `AutoApproved` from staff `Approved`; record system/policy basis in its note or a policy reference. | Retains an auditable approval origin. |
| `Space` | Do not use one enduring `current_status = UnderMaintenance` to represent advisory work. | A space may be operational with one or more advisories. Status remains useful for closure/current operations, but interval-level maintenance determines booking availability. |

### Relationship additions

```text
Booking 1 ──< BookingMaintenanceAdvisoryAcknowledgement >── 1 MaintenanceRecord
MaintenanceRecord 1 ──< MaintenanceImpactHistory >── 1 User (actor)
```

For acknowledgement rows, the booking and advisory must refer to the same space and overlap in time. This cross-table condition needs transactional procedure/trigger validation; it cannot be expressed with foreign keys alone.

## 3. Updated Static Business Rules

1. An active maintenance record is one whose status is `Reported`, `Assigned`, or `InProgress` and whose interval overlaps the booking interval. The open end is treated as infinity until `completion_time` is recorded.
2. Booking intervals use half-open overlap logic: `requested_start_time < maintenance_end` and `requested_end_time > maintenance_start`. End-to-start adjacency is not an overlap.
3. A request may be approved only when no overlapping active `out-of-service` record exists, all normal policy/capacity/account rules pass, and no other approved or checked-in booking conflicts.
4. An overlapping active advisory does not block approval. Before approval, the system must present all such advisories and persist an acknowledgement for every maintenance record returned by the availability check. Missing acknowledgement for even one advisory prevents approval.
5. A newly created advisory or a downgrade from `out-of-service` to `advisory` changes future availability only. It neither cancels nor alters historical bookings.
6. An escalation from `advisory` to `out-of-service` blocks new approvals immediately. It must preserve overlapping approved bookings and create a staff work item/notification; staff must contact the requester and explicitly cancel, relocate, or reschedule the booking. The database must not silently delete or rewrite the booking.
7. A downgrade from `out-of-service` to `advisory` permits future requests subject to acknowledgement. It does not automatically approve previously rejected or pending requests; those requests must be revalidated.
8. Acknowledgements are historical evidence. Completion, cancellation, escalation, or later text changes to maintenance do not erase them. A material advisory change should require a new acknowledgement event or a versioned acknowledgement policy.

## 4. Availability Decision by Maintenance State

| Overlapping active records for a requested interval | Can approval proceed? | Required action |
|---|---:|---|
| None | Yes, if normal availability/policy validation passes. | Normal approval path. |
| One or more advisories; no outage | Yes. | Display every advisory and persist one acknowledgement per record before the approval transition. |
| At least one `out-of-service` record, with or without advisories | No. | Reject/keep pending according to workflow; explain the blocking outage. |
| Advisory is escalated after a booking was approved | No new approval; existing booking remains in history. | Identify affected approved bookings and create an auditable staff-resolution workflow. |

## 5. Concurrency Analysis: Instant Booking and Manual Approval

The static rules above say what is valid; they do not by themselves prevent a race. The risky operations are an auto-approval on submission, a staff approval of a pending request, and an advisory escalation to `out-of-service`. Each changes availability and therefore must serialize with the others for the same space.

| Race | Unsafe interleaving | Required protection |
|---|---|---|
| Two instant bookings | Both sessions find no approved conflict, then both set their bookings to `Approved`. | Lock the affected `space_id` before the conflict read; recheck and update within one transaction. One request commits, the other fails/reverts to pending. |
| Instant booking vs. manual approval | Auto-approval and staff approval each see the other request as pending, then approve it. | Use the same approval procedure and same per-space lock for both paths; never let the client perform a check then a separate status update. |
| Manual approvals by two staff users | Both staff approve overlapping pending requests. | Same serialized approval transition, plus `WHERE booking_status = N'Pending'` / row-state verification. |
| Approval vs. maintenance escalation | Approval sees an advisory while escalation changes it to `out-of-service`; the booking is approved after the outage begins. | Escalation and approval acquire the same per-space lock. The operation that obtains it second rereads current maintenance and either blocks approval or identifies the newly affected booking. |
| Advisory display vs. changed advisories | User acknowledges an old list while an additional advisory is opened/changed before approval. | Capture the advisory list under the same transaction/space lock used for approval; re-query before status change and require acknowledgements for the final list. |

### Required transactional mechanism

Implement a single database procedure (or equivalent service operation) for both auto and manual approval. It should:

1. Begin a transaction with `XACT_ABORT ON`.
2. Acquire an exclusive transaction-owned application lock named from `space_id` (for example, `CSMS:Space:<space_id>`) using `sp_getapplock`, or use a correctly indexed `SERIALIZABLE` range-lock strategy.
3. Read the booking row with an update lock and confirm it is still `Pending` (or follow a separately defined idempotency rule for a repeated submission).
4. Revalidate account, capacity, policy, active `out-of-service` maintenance, overlapping approved/checked-in bookings, and the complete advisory set.
5. Insert/validate acknowledgement rows for all returned advisories, write the `BookingDecision`, and change the booking to `Approved` in the same transaction.
6. Commit; on any failed check, roll back or retain the booking as `Pending`/record a formal rejection as the workflow requires.

The existing `tr_booking_validate` overlap checks and `UPDLOCK, HOLDLOCK` reads are useful defence in depth, but they are not a complete workflow boundary: auto and manual paths must share one transaction and the maintenance-impact update must join that same serialization domain. A per-space application lock is the clearest SQL Server implementation because it also protects the empty-result case and the escalation path.

## 6. Escalation Impact Detection and Resolution

When changing an active maintenance record from `advisory` to `out-of-service`, the update procedure must run under the affected space's transaction-owned lock. It must first verify the previous impact level and active maintenance status, record the impact-history row, change the level, then identify affected bookings before commit.

The core detection condition is:

```sql
SELECT
    b.booking_id,
    b.requester_user_id,
    b.requested_start_time,
    b.requested_end_time,
    m.maintenance_id
FROM dbo.Booking AS b
INNER JOIN dbo.MaintenanceRecord AS m
    ON m.space_id = b.space_id
WHERE m.maintenance_id = @maintenance_id
  AND b.booking_status IN (N'Approved', N'CheckedIn')
  AND b.requested_start_time < ISNULL(m.completion_time, CONVERT(DATETIME2(0), '9999-12-31 23:59:59'))
  AND b.requested_end_time > m.start_time;
```

The required report is specifically about approved bookings; including `CheckedIn` in the operational result is prudent because an active use session can also be affected and needs immediate operational action. If the reporting definition must be literal, filter the final report to `b.booking_status = N'Approved'` and handle checked-in bookings in the incident workflow.

For every returned booking, create an immutable `MaintenanceBookingImpact`/notification-work-item row containing at least the maintenance ID, booking ID, escalation time, identified-by actor, contact status, resolution (`PendingContact`, `Rescheduled`, `Relocated`, `Cancelled`, or `AcceptedRisk` only if policy permits), and resolution note. A unique `(maintenance_id, booking_id)` constraint makes repeated execution idempotent. Staff then contact the requester and record the explicit resolution; the original booking and its advisory acknowledgement remain intact.

## 7. Required Downstream Deliverable Updates

| Deliverable | Required update |
|---|---|
| ERD and logical design | Add `impact_level`, advisory-acknowledgement relationship, impact history, and escalation-impact work item/history. State their cardinalities and same-space/overlap validation. |
| DDL | Add controlled impact-level constraint, acknowledgement and audit/work-item tables, supporting foreign keys/unique constraints, and transactional procedures/triggers for advisory validation, escalation, and approval serialization. |
| Sample data | Include mixed concurrent advisory/outage records, a booking with multiple acknowledgements, an escalation with affected approved booking(s), and a downgrade case. |
| Queries | Change room-finder and availability queries so only `out-of-service` maintenance blocks. Add the required maintenance-impact report driven by escalation/work-item data. |
| Tests | Exercise acknowledgement-required approval, multiple advisories, advisory-to-outage escalation, outage-to-advisory downgrade, simultaneous auto/manual approvals, and approval concurrent with escalation. |

## 8. Analytical Conclusion

The principal model change is not merely a two-value column. `impact_level` changes maintenance from a blanket space status into an interval-specific rule with evidence of requester notification. The acknowledgement must be per booking and per maintenance record to remain correct with concurrent advisories. The principal operational change is a shared serialization boundary: instant approval, staff approval, and outage escalation must all lock and revalidate the same space before committing. This combination preserves booking history, prevents double approval, and gives staff a durable, actionable list when an advisory becomes an outage.
