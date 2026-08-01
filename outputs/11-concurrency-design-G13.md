# CSMS Concurrency Control Design — Group 13

## 1. Protected Invariant

For one space, two bookings in Approved or CheckedIn status must never have overlapping effective occupied intervals. The overlap predicate is:

    new_start < existing_end AND new_end > existing_start

Configured buffers are included in the effective interval. The same atomic operation must also block active out-of-service maintenance and require acknowledgement of all active overlapping advisories.

## 2. Double-Booking Anomaly

Under READ COMMITTED, an availability check followed by a separate update is unsafe.

| Time | Instant approval A | Staff approval B |
|---|---|---|
| T1 | Reads no approved overlap. | |
| T2 | | Reads no approved overlap; A is still pending. |
| T3 | Changes A to Approved and commits. | |
| T4 | | Changes B to Approved and commits. |

Both requests overlap and are now approved. The same check-then-act anomaly applies to two auto-approvals or two manual approvals. A related race is approval reading an advisory while a concurrent transaction escalates it to out-of-service; without shared serialization, approval can commit after the outage change.

A lock on an existing booking row is insufficient: when the first check returns no conflict, there is no row to lock. The design must protect the logical availability resource for the space.

## 3. Isolation and Locking Evaluation

| Mechanism | Benefit | CSMS limitation | Decision |
|---|---|---|---|
| READ COMMITTED | Prevents dirty reads. | Allows phantoms and check-then-act races. | Reject. |
| REPEATABLE READ | Holds rows already read stable. | Does not protect an empty conflict range from a competing insert. | Reject alone. |
| SERIALIZABLE | Range locks can prevent phantoms with suitable indexes. | Correctness depends on every path, predicate, and index shape; can be broad. | Defence in depth. |
| UPDLOCK, HOLDLOCK | SQL Server update/range locks on validation reads. | Does not by itself ensure every application path shares one protocol. | Retain in triggers/procedures. |
| SELECT FOR UPDATE | Familiar row-lock syntax in other DBMSs. | Not SQL Server syntax; use UPDLOCK/HOLDLOCK. | Not applicable. |
| Exclusion constraint | Declarative non-overlap in PostgreSQL. | SQL Server has no equivalent. | Not applicable. |
| sp_getapplock | Locks a logical resource, including empty result cases. | All availability-changing operations must participate. | Selected primary control. |

## 4. Selected Control Strategy

Use one approval procedure for both automatic and staff approval. At the start of its transaction it acquires an exclusive, transaction-owned application lock:

    CSMS:Space:<space_id>

While that lock is held, it locks and re-reads the booking, checks policy/account/capacity, checks approved and checked-in overlap, checks out-of-service maintenance, and validates the complete current advisory set. It inserts acknowledgement evidence, inserts a BookingDecision, and changes Pending to Approved in the same transaction.

The maintenance escalation procedure acquires the identical lock before changing impact level. It then writes MaintenanceImpactHistory and idempotent MaintenanceBookingImpact rows. Therefore, the approval and escalation paths cannot validate conflicting versions of availability.

The current booking and maintenance validation triggers are retained as defence in depth. Procedures supply the shared serialization boundary; triggers reject accidental direct writes.

### Lock and access order

1. Acquire the application lock for the space.
2. Lock/read the target Booking row with UPDLOCK, HOLDLOCK and require Pending.
3. Lock/read MaintenanceRecord and conflicting Booking ranges.
4. Insert acknowledgement rows, then BookingDecision.
5. Execute guarded Booking status update.
6. Commit or roll back.

All approvals, auto-approvals, escalations, downgrades, and relocation operations must use this order.

## 5. Approval Sequence

    BEGIN TRANSACTION
      -> exclusive lock CSMS:Space:<space_id>
      -> require target booking status = Pending
      -> revalidate interval, buffers, policy, account, and capacity
      -> reject if an approved/checked-in overlap exists
      -> reject if out-of-service maintenance overlaps
      -> require acknowledgement for every active overlapping advisory
      -> write decision and guarded status transition
    COMMIT

The guarded transition handles duplicate/replayed requests:

    UPDATE dbo.Booking
    SET booking_status = N'Approved'
    WHERE booking_id = @booking_id
      AND booking_status = N'Pending';

    IF @@ROWCOUNT <> 1
        THROW 51020, 'The booking was changed by another operation.', 1;

Illustrative transaction shell:

    SET XACT_ABORT ON;
    SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
    BEGIN TRANSACTION;
    EXEC @lock_result = sys.sp_getapplock
        @Resource = @space_lock_name,
        @LockMode = N'Exclusive',
        @LockOwner = N'Transaction',
        @LockTimeout = 10000;
    IF @lock_result < 0
        THROW 51021, 'Could not obtain the space availability lock.', 1;
    -- Re-read and validate all booking, maintenance, and acknowledgement facts.
    COMMIT TRANSACTION;

Transaction ownership releases the application lock at commit or rollback. Supporting indexes are:

    Booking(space_id, booking_status, requested_start_time, requested_end_time)
    MaintenanceRecord(space_id, maintenance_status, impact_level, start_time, completion_time)
    BookingMaintenanceAdvisoryAcknowledgement(booking_id, maintenance_id)
    MaintenanceBookingImpact(maintenance_id, booking_id) UNIQUE

## 6. Escalation Sequence

| Step | Transactional action |
|---|---|
| 1 | Read only enough to identify the maintenance record's space; acquire that space's application lock. |
| 2 | Re-read the maintenance row with UPDLOCK, HOLDLOCK; require active status and current level advisory. |
| 3 | Set impact level to out-of-service and insert MaintenanceImpactHistory. |
| 4 | Find overlapping Approved and, operationally, CheckedIn bookings. |
| 5 | Insert one MaintenanceBookingImpact work item per pair; the unique maintenance/booking pair makes retries safe. |
| 6 | Commit. The next approval for the space sees the outage. |

A downgrade follows the same locking protocol, but it never automatically approves previously pending or rejected requests.

## 7. Deadlocks and Mitigation

| Risk | Deadlock cycle | Mitigation |
|---|---|---|
| Two-space relocation | A locks space 101 then 202; B locks 202 then 101. | Acquire all application locks in ascending numeric space_id order. |
| Booking row and application lock | One path locks Booking then requests app lock; another does the reverse. | Mandatory order is app lock, Booking row, range reads, acknowledgement/decision writes. |
| Escalation vs approval | Escalation locks maintenance first; approval holds app lock and needs maintenance. | Obtain the app lock first after locating space_id, then re-read/lock maintenance. |
| Large batches | Batch work locks many spaces while approvals execute. | Sorted bounded batches; reports use read-only snapshot/read-committed access. |

Keep transactions short: do not email users or wait for acknowledgement inside the transaction. Use a finite lock timeout, retry only idempotent commands with jittered backoff, and collect SQL Server deadlock graphs and lock-timeout telemetry. Avoid a global lock because unrelated spaces should continue concurrently.

## 8. Correctness Argument

Let L(s) be the exclusive transaction-owned application lock for space s. Every transition that can create or alter availability for s holds L(s) until commit.

For two such transactions T1 and T2 for the same space, only one owns L(s). If T1 commits an approval, T2 validates afterwards and observes that booking, so it cannot approve an overlap. If T1 commits an escalation, T2 validates afterwards and observes the out-of-service interval, so it cannot approve an overlap. If T1 rolls back, it creates no conflicting committed state. Thus participating operations cannot produce two overlapping approved bookings or an undetected post-escalation approval.

## 9. Acceptance Tests

1. Two concurrent instant requests for one overlapping interval yield exactly one Approved booking.
2. An instant request and manual approval for the same conflict yield exactly one Approved booking.
3. Approvals for different spaces proceed independently.
4. An approval concurrent with escalation either commits before escalation and gets an impact work item, or waits and is rejected; it never commits after escalation without detection.
5. A booking overlapping multiple advisories cannot be approved until it has one acknowledgement row for each advisory.
6. Deadlock monitoring shows no repeated lock-order cycle; a victim retry does not duplicate decisions or impact work items.

