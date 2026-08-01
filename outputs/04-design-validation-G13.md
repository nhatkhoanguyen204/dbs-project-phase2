# CSMS Database Design Validation & Normalization Report

## 1. Business Rule Traceability Matrix

| Business rule | Logical design element | Enforcement level | Result |
|---|---|---|---|
| Active university account and role-based access | `User.account_status`, `User.role`; actor FKs | Application/service procedure | Covered; authorization is cross-row logic. |
| Unique user and space identity | `User.email`; `Space.space_code` candidate keys | `UNIQUE` constraints | Covered. |
| Bookable space details, capacity, and controlled status | `Space` attributes | `NOT NULL`, `CHECK` | Covered. |
| Facilities per space | `Facility`, `SpaceFacility` composite PK | PK/FKs/quantity check | Covered. |
| Valid booking request and interval | `Booking` required FKs and attributes | `NOT NULL`, `CHECK (end > start)` | Covered. |
| Participant count cannot exceed capacity | Booking participant count + Space capacity | Transaction trigger/procedure | Covered; cross-table constraint. |
| No overlapping approved or checked-in bookings | `Booking` interval/status columns | Serialized approval procedure/trigger | Covered; an index supports the lookup but cannot alone express interval exclusion in SQL Server. |
| Closed, retired, or maintenance space is non-bookable | `Space.current_status`; `MaintenanceRecord` | Serialized approval procedure/trigger | Covered. |
| Pending request revalidated on approval | `Booking.booking_status` | Approval procedure | Covered. |
| Approval/rejection accountability and reason | `BookingDecision` actor/time/note/reason columns | FK plus transition procedure | Covered; rejection reason required when decision is rejected. |
| Auto-approval policy and lead/buffer rules | `BookingPolicy` | Policy-selection procedure | Covered; effective interval includes configured buffers. |
| Lifecycle transitions and cancellation history | `Booking` status and cancellation fields | Transition procedure | Covered; records are not deleted. |
| Check-in/out and actual condition history | `UsageSession`, unique `booking_id` | FK, unique key, checks, transition procedure | Covered; supports partial session before check-out. |
| No-show reporting | `Booking.booking_status` | Transition procedure | Covered. |
| Maintenance reporting, assignment, completion | `MaintenanceRecord` reporter/assignee/status/times | FKs, checks, transition procedure | Covered. |
| Maintenance against pending/approved bookings | Booking and maintenance intervals by `space_id` | Serialized maintenance procedure | Covered; preserve and flag affected historical bookings. |
| Required history and operational reports | Retained Booking, BookingDecision, UsageSession, MaintenanceRecord data | `NO ACTION` FKs; report queries | Covered. |

## 2. Functional Dependency & Normalization Analysis (3NF / BCNF)

The determinant shown for each relation is its declared primary key unless noted. Attributes are atomic; derived values (durations, display location, effective occupancy) are not stored.

| Relation | Material functional dependencies | 3NF / BCNF assessment |
|---|---|---|
| User | `user_id →` all non-key attributes; `email →` all non-key attributes | BCNF: both determinants are candidate keys. |
| Space | `space_id →` all non-key attributes; `space_code →` all non-key attributes | BCNF: both determinants are candidate keys. |
| Facility | `facility_id →` all non-key attributes; `(facility_name, facility_type) →` description | BCNF if the listed composite candidate key is enforced. |
| SpaceFacility | `(space_id, facility_id) → quantity, notes` | BCNF: the composite determinant is the key. |
| Booking | `booking_id →` all non-key attributes | BCNF. `space_id` and times do not determine a booking because valid adjacent/historical bookings may share values. |
| BookingDecision | `decision_id →` all non-key attributes | BCNF. Do **not** assume `(booking_id, decision_time)` is a candidate key: two decisions could share a timestamp unless a unique constraint makes it one. |
| UsageSession | `usage_session_id →` all non-key attributes; `booking_id →` all non-key attributes | BCNF because both declared determinants are candidate keys (`booking_id` is unique). |
| MaintenanceRecord | `maintenance_id →` all non-key attributes | BCNF. |
| BookingPolicy | `policy_id →` all non-key attributes | BCNF. Scope fields are not asserted as a candidate key because global and scoped policies need explicit precedence rules. |

No partial dependency exists in `SpaceFacility`, the only composite-key relation. No non-key attribute determines another non-key attribute in the stated relations, so no transitive dependency violates 3NF. Controlled codes remain columns rather than lookup tables; that is intentional because the Phase 1 controlled lists are small and static. If management needs names, translations, or lifecycle metadata for codes, decompose them into reference tables before deployment.

## 3. Operational Edge-Case Analysis

| Scenario | Required behavior | Design response |
|---|---|---|
| Two staff approve overlapping pending requests concurrently | At most one becomes approved. | Run the conflict search and status update in one transaction using serializable/range locking (or an equivalent application lock) on the affected space and effective time range. The second transaction rechecks after the first commits and fails. |
| Maintenance starts during a pending booking | Keep the request but prevent its approval. | Insert/update maintenance and flag overlapping pending bookings; approval validation sees active maintenance and rejects approval. |
| Maintenance starts during an approved booking | Do not silently create an impossible schedule. | Preserve both records, flag the booking for a documented cancellation, reschedule, or relocation decision, and block any further conflicting approval. |
| Approved booking is not used | Preserve it as a no-show. | Authorized transition `approved → no-show`; no `UsageSession` is created. The booking remains reportable. |
| Check-in occurs but check-out has not happened | Represent a partial, active session. | `UsageSession` has mandatory check-in fields and nullable check-out fields; Booking is `checked in`. Check-out completes only after a later valid end time. |
| Check-out precedes check-in or has no operator | Reject invalid session completion. | `CHECK` requires end after start when supplied; procedure requires `check_out_by_user_id` and final-condition data for completion. |
| Boundary-adjacent bookings | Allow when buffers do not overlap. | Approval compares effective half-open intervals `[start - pre_buffer, end + post_buffer)`; equality at endpoints is not an overlap. |
| Space is retired or account is disabled after history exists | Preserve records, prevent future operations. | Status/account checks block new operations; `NO ACTION` FKs prevent destructive deletion. |

## 4. Summary of Architecture Trade-offs & Recommendations

The design passes 3NF and BCNF subject to the declared candidate keys. It deliberately stores the current booking status alongside append-only decisions: this is a controlled denormalization that makes upcoming-booking and no-show reporting inexpensive while retaining the underlying decision audit trail. The status must be changed only by the same stored procedures that write decision/session data.

Recommendations for the DDL stage:

1. Implement `CHECK` constraints for every controlled code, positive numeric value, time ordering, and rejected-decision reason.
2. Do not create `UNIQUE (booking_id, decision_time)` merely because it appears in the logical design; retain `decision_id` as the key unless the business explicitly requires that timestamp uniqueness.
3. Create indexes beginning with `Booking(space_id, booking_status, requested_start_time, requested_end_time)` and `MaintenanceRecord(space_id, maintenance_status, start_time, completion_time)` for conflict validation.
4. Enforce status transitions, role authorization, capacity, policy choice, and overlap/maintenance checks in transactional stored procedures or triggers. Use `SERIALIZABLE` isolation (or `sp_getapplock`) during approval and maintenance activation.
5. Prefer deactivation/retirement over physical deletes. If code lists become administratively managed, normalize `role`, status, type, and purpose codes into reference tables in a future iteration.
6. Use `ON UPDATE NO ACTION` for all foreign keys in SQL Server. The identity primary keys are immutable, and this avoids SQL Server's multiple-cascade-path restriction where one user is referenced in several business roles.
