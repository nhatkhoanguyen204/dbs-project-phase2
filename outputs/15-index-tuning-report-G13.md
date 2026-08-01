# CSMS Index Tuning Report — Group 13

## 1. Test Environment and Method

Measurements were taken on the locally generated 100,000-booking benchmark dataset in SQL Server 2022. The generator produced bookings from 2023-01-02 through 2025-10-13 across 84 dedicated benchmark spaces, with 70,000 Approved records.

SQL Server does not use EXPLAIN ANALYZE syntax. Equivalent evidence was collected with SET STATISTICS IO ON and SET STATISTICS TIME ON on a warm cache. The before run removed only non-constraint query indexes in the disposable database. The after run recreated the conflict/maintenance indexes and added room-finder and reporting indexes.

The four profiled queries were:

1. booking conflict check for one space and interval;
2. room finder with capacity, projector, booking, and maintenance filters;
3. total approved booking hours by space for calendar year 2024;
4. approved booking distribution by weekday and start hour for calendar year 2024.

## 2. Baseline Execution Evidence

> Conflict check before indexing: Booking table scan, 1 scan, 1,675 logical reads, CPU 9 ms, elapsed 8 ms.

> Room Finder before indexing: Booking table scan, 85,070 logical reads; MaintenanceRecord scan, 232 reads; SpaceFacility scan, 3 reads; Facility lookup, 156 reads; elapsed 283 ms. The anti-join repeatedly evaluated booking availability across candidate spaces.

> Total-hours report before indexing: Booking table scan, 1,675 logical reads, hash/group aggregate worktable, CPU 15 ms, elapsed 14 ms.

> Usage-distribution report before indexing: Booking table scan, 1,675 logical reads, aggregate worktable/workfile, CPU 15 ms, elapsed 14 ms.

The conflict predicate is selective by space but non-sargable on both time boundaries as a range-overlap condition. The key optimization is therefore to seek to one space/status partition first, then apply the interval residual predicate to a small set of rows.

## 3. Selected Index Definitions

The following definitions were applied in the after run. The first two are also the production conflict and maintenance indexes; the final three supplement room finding and reporting.

    CREATE INDEX ix_booking_space_status_time
        ON dbo.Booking (space_id, booking_status, requested_start_time, requested_end_time);

    CREATE INDEX ix_maintenance_space_impact_time
        ON dbo.MaintenanceRecord
        (space_id, maintenance_status, impact_level, start_time, completion_time);

    CREATE INDEX ix_space_room_finder_status_capacity
        ON dbo.Space (current_status, capacity, space_id)
        INCLUDE (space_code, space_name, space_type, building, floor, room_number);

    CREATE INDEX ix_space_facility_facility_space
        ON dbo.SpaceFacility (facility_id, space_id);

    CREATE INDEX ix_booking_reporting_status_start_space
        ON dbo.Booking (booking_status, requested_start_time, space_id)
        INCLUDE (requested_end_time);

The Space index filters usable, sufficiently large rooms without a key lookup. The SpaceFacility index starts from the requested facility and supports its semi-join. The reporting index first applies status and semester/date filtering, covers duration, and supplies the grouping space key.

## 4. Before/After Results

| Query | Before plan / reads | Before elapsed | After plan / reads | After elapsed | Result |
|---|---|---:|---|---:|---|
| Booking conflict check | Booking table scan; 1,675 reads | 8 ms | Two index seeks/range probes; 10 reads | 0 ms | 99.4% fewer logical reads |
| Room Finder | Booking scan 85,070 plus MaintenanceRecord scan 232; about 85,467 total reads | 283 ms | Nested-loop anti-seeks: Booking 669, Maintenance 174; about 854 total reads | 4 ms | 99.0% fewer reads; 98.6% less elapsed time |
| Total approved hours | Booking scan; 1,675 reads | 14 ms | Filtered ordered index access; 560 reads | 14 ms | 66.6% fewer reads; elapsed unchanged at this scale |
| Weekday/hour distribution | Booking scan; 1,675 reads | 14 ms | Filtered index access; 560 reads | 13 ms | 66.6% fewer reads; 7.1% lower elapsed time |

Elapsed measurements are single warm-cache observations and should not be treated as a service-level guarantee. Logical-read reductions are more stable evidence that the chosen access path scales better as the data grows.

## 5. After-Index Plan Breakdown

### Booking conflict check

> Actual access pattern: index seek on ix_booking_space_status_time for the requested space/status values, followed by a residual overlap filter. Logical reads dropped from 1,675 to 10.

This is the highest-priority integrity query because it runs inside the serialized approval transaction. The composite key puts equality predicates before time columns and minimizes the duration of range-lock validation.

### Room Finder

> Actual access pattern: seek/scan of eligible Space rows, facility semi-join, then nested-loop anti-seeks into booking and maintenance indexes. Booking reads dropped from 85,070 to 669 and elapsed time dropped from 283 ms to 4 ms.

The overlap inequalities prevent a single perfect B-tree range seek, but the candidate set is reduced to one space at a time before evaluating them. This is the appropriate SQL Server analogue to a range/exclusion design unavailable in this platform.

### Total booking hours

> Actual access pattern: ix_booking_reporting_status_start_space filters approved/checked-in/completed rows by status and 2024 start-time range, then performs the aggregate. Reads fell from 1,675 to 560.

The report still aggregates many qualifying rows, so its CPU time did not materially change at 100,000 rows. The covered filter avoids scanning cancelled, rejected, and pending rows and becomes more valuable at 500,000 rows.

### Usage distribution

> Actual access pattern: the reporting index applies the same status/semester filter, then a stream/hash aggregate computes weekday and hour expressions. Reads fell from 1,675 to 560 and elapsed time from 14 ms to 13 ms.

DATEPART remains a computed grouping expression, so it cannot be fully ordered by this index. If this report becomes latency-critical, add persisted computed weekday/hour columns with a purpose-built index after validating locale and DATEFIRST semantics.

## 6. Trade-offs and Operational Guidance

- Do not remove ix_booking_space_status_time or ix_maintenance_space_impact_time: they support both concurrency validation and user-facing availability.
- The reporting index increases insert/update maintenance for each booking. It is justified for the required semester reports; monitor write cost during peak submission periods.
- Avoid indexing requested_end_time first. The conflict and room-finder predicates first identify a space and status; the start time provides the useful leading range dimension after those equalities.
- Do not add a separate index for every report by default. Reuse ix_booking_reporting_status_start_space for the two measured reporting patterns and revisit only with production plan data.
- Update statistics after large generator loads before timing, and test the 500,000-row scale before committing a final capacity plan.

## 7. Reproduction Summary

1. Build a fresh benchmark database with the base DDL, migration, and 14-data-generator-G13 generator.
2. Run each query with STATISTICS IO and TIME enabled after removing only the listed test indexes.
3. Create the five indexes in Section 3.
4. Rerun the identical parameterized queries on a warm cache.
5. Compare logical reads, elapsed time, and operator shape rather than comparing only elapsed time.

The measured dataset met the minimum size requirement, and the selected indexes materially improve the booking-conflict and Room Finder paths while reducing I/O for both selected analytical reports.

