/*
    CSMS Phase 2 required analytical queries — Group 13
    Each batch is read-only and independently executable in SQL Server.
*/

/*
    Query 01: Total approved booking hours by space for a semester.
    Set a half-open semester range. Approved-derived lifecycle states are included
    because Completed, CheckedIn, and NoShow can only follow an approval.
*/
DECLARE @semester_start_01 DATETIME2(0) = '2024-01-01 00:00:00';
DECLARE @semester_end_01 DATETIME2(0) = '2024-06-01 00:00:00';

SELECT
    s.space_code,
    s.space_name,
    s.space_type,
    CAST
    (
        COALESCE
        (
            SUM
            (
                CASE
                    WHEN b.requested_start_time >= @semester_start_01
                     AND b.requested_start_time < @semester_end_01
                    THEN DATEDIFF(MINUTE, b.requested_start_time, b.requested_end_time)
                    ELSE 0
                END
            ),
            0
        ) / 60.0
        AS DECIMAL(12, 2)
    ) AS approved_booking_hours,
    COUNT
    (
        CASE
            WHEN b.requested_start_time >= @semester_start_01
             AND b.requested_start_time < @semester_end_01
            THEN b.booking_id
        END
    ) AS approved_booking_count
FROM dbo.Space AS s
LEFT JOIN dbo.Booking AS b
    ON b.space_id = s.space_id
   AND b.booking_status IN (N'Approved', N'CheckedIn', N'Completed', N'NoShow')
GROUP BY
    s.space_code,
    s.space_name,
    s.space_type
ORDER BY
    approved_booking_hours DESC,
    s.space_code;
GO

/*
    Query 02: Usage distribution by weekday and start hour for a semester.
    DATEPART weekday depends on SET DATEFIRST; the query fixes Monday as day 1
    for reproducible output and derives the weekday label from the date.
*/
SET DATEFIRST 1;

DECLARE @semester_start_02 DATETIME2(0) = '2024-01-01 00:00:00';
DECLARE @semester_end_02 DATETIME2(0) = '2024-06-01 00:00:00';

SELECT
    DATEPART(WEEKDAY, b.requested_start_time) AS weekday_number_monday_first,
    DATENAME(WEEKDAY, b.requested_start_time) AS weekday_name,
    DATEPART(HOUR, b.requested_start_time) AS start_hour,
    COUNT(*) AS approved_booking_count
FROM dbo.Booking AS b
WHERE b.booking_status IN (N'Approved', N'CheckedIn', N'Completed', N'NoShow')
  AND b.requested_start_time >= @semester_start_02
  AND b.requested_start_time < @semester_end_02
GROUP BY
    DATEPART(WEEKDAY, b.requested_start_time),
    DATENAME(WEEKDAY, b.requested_start_time),
    DATEPART(HOUR, b.requested_start_time)
ORDER BY
    weekday_number_monday_first,
    start_hour;
GO

/*
    Query 03: Room Finder.
    Add one row per required facility to @required_facilities. A room qualifies
    only if it has every listed facility, sufficient capacity, no active
    approved/checked-in booking overlap, and no active out-of-service overlap.
    Advisories deliberately do not block the room; a portal should display them
    before proceeding to acknowledgement.
*/
DECLARE @requested_start_03 DATETIME2(0) = '2024-03-04 09:00:00';
DECLARE @requested_end_03 DATETIME2(0) = '2024-03-04 11:00:00';
DECLARE @required_capacity_03 INT = 30;

IF @requested_end_03 <= @requested_start_03
    THROW 51300, 'Room Finder requires an end time later than the start time.', 1;

DECLARE @required_facilities_03 TABLE
(
    facility_name NVARCHAR(100) NOT NULL,
    facility_type NVARCHAR(50) NOT NULL,
    PRIMARY KEY (facility_name, facility_type)
);

INSERT INTO @required_facilities_03 (facility_name, facility_type)
VALUES
    (N'Benchmark Projector', N'Projector');
-- Replace the example row(s) above with the requested facility list.

SELECT
    s.space_id,
    s.space_code,
    s.space_name,
    s.space_type,
    s.capacity,
    s.building,
    s.floor,
    s.room_number,
    advisory_summary.active_advisory_count,
    advisory_summary.active_advisories
FROM dbo.Space AS s
OUTER APPLY
(
    SELECT
        COUNT(*) AS active_advisory_count,
        STRING_AGG(CONVERT(NVARCHAR(MAX), m.problem_description), N'; ') AS active_advisories
    FROM dbo.MaintenanceRecord AS m
    WHERE m.space_id = s.space_id
      AND m.maintenance_status IN (N'Reported', N'Assigned', N'InProgress')
      AND m.impact_level = N'advisory'
      AND @requested_start_03 < ISNULL(m.completion_time, CONVERT(DATETIME2(0), '9999-12-31 23:59:59'))
      AND @requested_end_03 > m.start_time
) AS advisory_summary
WHERE s.current_status IN (N'Available', N'InUse')
  AND s.capacity >= @required_capacity_03
  AND NOT EXISTS
  (
      SELECT 1
      FROM @required_facilities_03 AS required_facility
      WHERE NOT EXISTS
      (
          SELECT 1
          FROM dbo.SpaceFacility AS sf
          INNER JOIN dbo.Facility AS f ON f.facility_id = sf.facility_id
          WHERE sf.space_id = s.space_id
            AND f.facility_name = required_facility.facility_name
            AND f.facility_type = required_facility.facility_type
      )
  )
  AND NOT EXISTS
  (
      SELECT 1
      FROM dbo.Booking AS b
      WHERE b.space_id = s.space_id
        AND b.booking_status IN (N'Approved', N'CheckedIn')
        AND @requested_start_03 < b.requested_end_time
        AND @requested_end_03 > b.requested_start_time
  )
  AND NOT EXISTS
  (
      SELECT 1
      FROM dbo.MaintenanceRecord AS m
      WHERE m.space_id = s.space_id
        AND m.maintenance_status IN (N'Reported', N'Assigned', N'InProgress')
        AND m.impact_level = N'out-of-service'
        AND @requested_start_03 < ISNULL(m.completion_time, CONVERT(DATETIME2(0), '9999-12-31 23:59:59'))
        AND @requested_end_03 > m.start_time
  )
ORDER BY
    s.capacity,
    s.space_code;
GO

/*
    Query 04: Maintenance Impact Analysis.
    MaintenanceBookingImpact is written transactionally when an advisory is
    escalated to out-of-service. It is therefore the authoritative affected-
    booking list, even if the booking was subsequently rescheduled/cancelled.
    Set @maintenance_id_04 to restrict to one escalation, or leave it NULL.
*/
DECLARE @maintenance_id_04 BIGINT = NULL;

SELECT
    m.maintenance_id,
    s.space_code,
    s.space_name,
    m.problem_description,
    m.start_time AS maintenance_start_time,
    m.completion_time AS maintenance_end_time,
    impact.identified_at AS escalation_identified_at,
    identified_by.full_name AS escalation_recorded_by,
    b.booking_id,
    b.booking_status AS current_booking_status,
    b.requested_start_time,
    b.requested_end_time,
    requester.full_name AS requester_name,
    requester.email AS requester_email,
    requester.phone_number AS requester_phone,
    impact.contact_status,
    impact.contacted_at,
    impact.resolution,
    impact.resolved_at,
    resolved_by.full_name AS resolved_by,
    impact.resolution_note
FROM dbo.MaintenanceBookingImpact AS impact
INNER JOIN dbo.MaintenanceRecord AS m ON m.maintenance_id = impact.maintenance_id
INNER JOIN dbo.Space AS s ON s.space_id = m.space_id
INNER JOIN dbo.Booking AS b ON b.booking_id = impact.booking_id
INNER JOIN dbo.[User] AS requester ON requester.user_id = b.requester_user_id
INNER JOIN dbo.[User] AS identified_by ON identified_by.user_id = impact.identified_by_user_id
LEFT JOIN dbo.[User] AS resolved_by ON resolved_by.user_id = impact.resolved_by_user_id
WHERE @maintenance_id_04 IS NULL
   OR impact.maintenance_id = @maintenance_id_04
ORDER BY
    impact.identified_at DESC,
    s.space_code,
    b.requested_start_time;
GO

