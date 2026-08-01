# Group 13 Concurrency Tests

## Prerequisites

Run the scripts in this order against a disposable SQL Server database:

1. 05-db-definition-G13.sql
2. 10-schema-migration-G13.sql
3. 12-concurrency-implementation-G13.sql
4. 00_setup.sql

The setup script creates an isolated space named G13-CONCUR-TEST, two pending overlapping bookings, one active advisory, and a test-run row. It removes only earlier rows tagged with the same test space/code.

## Dual-session locking test

Open two sqlcmd terminals connected to the same test database.

1. Run session_A.sql first.
2. During its ten-second delay, run session_B.sql.
3. Session A prints an Approved result and commits.
4. Session B waits for the same CSMS:Space lock, then fails with error 51041: an approved or checked-in booking overlaps the effective interval.
5. Run 03_verify.sql. It must return exactly one approved booking and zero overlap pairs.

The initial lock in Session A is deliberate test instrumentation. It retains the transaction-owned application lock after Session A calls the real approval procedure, making Session B's blocking visible. Production code does not add this delay.

## Advisory and escalation tests

Run 04_advisory_and_escalation.sql after setup. It verifies:

- approval without acknowledgement fails with 51043;
- approval with acknowledgement succeeds and stores acknowledgement evidence;
- changing the advisory to out-of-service creates an impact work item for the already-approved booking.

## Unsafe baseline demonstration

unsafe_baseline_demo.sql is not part of normal verification and must be run only in the disposable test database. It temporarily disables the booking validation trigger inside a transaction, creates the double-booking state that uncoordinated check-then-update logic permits, displays it, and rolls back. It proves why the locking procedure and trigger are necessary without leaving persistent invalid data.

Expected locking test result:

| Check | Expected value |
|---|---|
| Session A | booking is Approved |
| Session B | error 51041 after waiting |
| Approved booking count | 1 |
| Overlap-pair scan | 0 |
| Advisory acknowledgement count | 1 after advisory test |
| Escalation impact count | 1 after escalation test |

