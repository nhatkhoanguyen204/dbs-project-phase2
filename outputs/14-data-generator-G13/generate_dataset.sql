/*
    CSMS Phase 2 synthetic benchmark generator — Group 13.
    Requires outputs/05-db-definition-G13.sql and outputs/10-schema-migration-G13.sql.
    Run only in a clean, disposable benchmark database.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @booking_count INT = 100000;       -- Set to 500000 for the full benchmark.
DECLARE @start_date DATE = '2023-01-01';
DECLARE @space_count INT;
DECLARE @requester_count INT = 980;
DECLARE @staff_count INT = 20;

IF @booking_count < 100000 OR @booking_count > 500000
    THROW 51200, 'booking_count must be between 100000 and 500000.', 1;

IF EXISTS (SELECT 1 FROM dbo.Space WHERE space_code LIKE N'G13-BENCH-%')
    THROW 51201, 'A G13 benchmark dataset already exists in this database. Use a clean benchmark database.', 1;

SET @space_count = CASE
    WHEN CEILING(@booking_count / 1200.0) < 80 THEN 80
    ELSE CONVERT(INT, CEILING(@booking_count / 1200.0))
END;

BEGIN TRANSACTION;

/* 1,000 realistic active benchmark accounts: requesters plus facility approvers. */
;WITH N AS
(
    SELECT TOP (@requester_count + @staff_count)
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects AS a
    CROSS JOIN sys.all_objects AS b
)
INSERT INTO dbo.[User] (full_name, email, phone_number, role, department, account_status)
SELECT
    CONCAT(N'Benchmark User ', n),
    CONCAT(N'g13.bench.', RIGHT(CONCAT(N'0000', n), 4), N'@csms.example'),
    CONCAT(N'0908', RIGHT(CONCAT(N'000000', n), 6)),
    CASE
        WHEN n > @requester_count THEN N'FacilityStaff'
        WHEN n % 10 = 0 THEN N'Lecturer'
        WHEN n % 10 = 1 THEN N'TA'
        ELSE N'Student'
    END,
    CASE WHEN n > @requester_count THEN N'Facilities' ELSE N'Computer Science' END,
    N'Active'
FROM N;

/* Dedicated spaces mean benchmark rows never conflict with sample/demo data. */
;WITH N AS
(
    SELECT TOP (@space_count)
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects AS a
    CROSS JOIN sys.all_objects AS b
)
INSERT INTO dbo.Space
(
    space_code, space_name, space_type, building, floor, room_number,
    capacity, current_status, usage_policy
)
SELECT
    CONCAT(N'G13-BENCH-', RIGHT(CONCAT(N'000', n), 3)),
    CONCAT(N'Benchmark Space ', n),
    CASE n % 5
        WHEN 0 THEN N'Classroom'
        WHEN 1 THEN N'MeetingRoom'
        WHEN 2 THEN N'ComputerLaboratory'
        WHEN 3 THEN N'ProjectLaboratory'
        ELSE N'StudentWorkspace'
    END,
    CONCAT(N'Benchmark Block ', ((n - 1) % 8) + 1),
    CONVERT(NVARCHAR(20), ((n - 1) % 6) + 1),
    CONCAT(N'B', RIGHT(CONCAT(N'000', n), 3)),
    20 + ((n * 7) % 181),
    N'Available',
    N'Generated benchmark policy: academic bookings and analysis only.'
FROM N;

/*
    Academic calendar: weekdays in Jan-May and Aug-Dec over the requested three
    years. Two slots per day provide 1,000+ non-overlapping slots per space.
*/
;WITH CalendarSource AS
(
    SELECT TOP (1200) DATEADD(DAY, ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1, @start_date) AS booking_date
    FROM sys.all_objects AS a
    CROSS JOIN sys.all_objects AS b
),
AcademicDays AS
(
    SELECT
        booking_date,
        ROW_NUMBER() OVER (ORDER BY booking_date) - 1 AS academic_day_number
    FROM CalendarSource
    WHERE DATENAME(WEEKDAY, booking_date) NOT IN (N'Saturday', N'Sunday')
      AND MONTH(booking_date) IN (1, 2, 3, 4, 5, 8, 9, 10, 11, 12)
),
BenchmarkSpaces AS
(
    SELECT
        space_id,
        ROW_NUMBER() OVER (ORDER BY space_id) - 1 AS space_number,
        capacity
    FROM dbo.Space
    WHERE space_code LIKE N'G13-BENCH-%'
),
BenchmarkRequesters AS
(
    SELECT
        user_id,
        ROW_NUMBER() OVER (ORDER BY user_id) - 1 AS requester_number
    FROM dbo.[User]
    WHERE email LIKE N'g13.bench.%@csms.example'
      AND role <> N'FacilityStaff'
),
Numbers AS
(
    SELECT TOP (@booking_count)
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n
    FROM sys.all_objects AS a
    CROSS JOIN sys.all_objects AS b
)
INSERT INTO dbo.Booking
(
    requester_user_id, space_id, requested_start_time, requested_end_time,
    purpose, expected_participants, booking_status, submitted_at,
    cancelled_at, cancelled_by_user_id, cancellation_note
)
SELECT
    r.user_id,
    s.space_id,
    DATEADD(HOUR, CASE WHEN (n.n / @space_count) % 2 = 0 THEN 9 ELSE 13 END, CONVERT(DATETIME2(0), d.booking_date)),
    DATEADD(HOUR, CASE WHEN (n.n / @space_count) % 2 = 0 THEN 11 ELSE 15 END, CONVERT(DATETIME2(0), d.booking_date)),
    CASE n.n % 7
        WHEN 0 THEN N'Lecture'
        WHEN 1 THEN N'Examination'
        WHEN 2 THEN N'Seminar'
        WHEN 3 THEN N'Workshop'
        WHEN 4 THEN N'Meeting'
        WHEN 5 THEN N'StudentActivity'
        ELSE N'AdministrativeEvent'
    END,
    CASE WHEN s.capacity < 10 THEN s.capacity ELSE 5 + (n.n % (s.capacity - 4)) END,
    CASE
        WHEN n.n % 100 < 70 THEN N'Approved'
        WHEN n.n % 100 < 80 THEN N'Completed'
        WHEN n.n % 100 < 85 THEN N'NoShow'
        WHEN n.n % 100 < 93 THEN N'Cancelled'
        WHEN n.n % 100 < 98 THEN N'Rejected'
        ELSE N'Pending'
    END,
    DATEADD(DAY, -14 - (n.n % 21), CONVERT(DATETIME2(0), d.booking_date)),
    CASE WHEN n.n % 100 BETWEEN 85 AND 92 THEN DATEADD(DAY, -3, CONVERT(DATETIME2(0), d.booking_date)) END,
    CASE WHEN n.n % 100 BETWEEN 85 AND 92 THEN r.user_id END,
    CASE WHEN n.n % 100 BETWEEN 85 AND 92 THEN N'Generated benchmark cancellation: schedule changed.' END
FROM Numbers AS n
INNER JOIN BenchmarkSpaces AS s
    ON s.space_number = n.n % @space_count
INNER JOIN BenchmarkRequesters AS r
    ON r.requester_number = n.n % @requester_count
INNER JOIN AcademicDays AS d
    ON d.academic_day_number = (n.n / @space_count) / 2;

/* Decision history for every generated approved/completed/no-show/rejected booking. */
DECLARE @approver_id BIGINT =
(
    SELECT TOP (1) user_id
    FROM dbo.[User]
    WHERE email LIKE N'g13.bench.%@csms.example'
      AND role = N'FacilityStaff'
    ORDER BY user_id
);

INSERT INTO dbo.BookingDecision
(
    booking_id, decision_maker_user_id, decision_time, decision, decision_note, rejection_reason
)
SELECT
    b.booking_id,
    @approver_id,
    DATEADD(DAY, 1, b.submitted_at),
    CASE WHEN b.booking_status = N'Rejected' THEN N'Rejected' ELSE N'Approved' END,
    N'Generated benchmark decision.',
    CASE WHEN b.booking_status = N'Rejected' THEN N'Generated benchmark policy rejection.' END
FROM dbo.Booking AS b
INNER JOIN dbo.Space AS s ON s.space_id = b.space_id
WHERE s.space_code LIKE N'G13-BENCH-%'
  AND b.booking_status IN (N'Approved', N'Completed', N'NoShow', N'Rejected');

/* Completed out-of-service history does not affect current booking availability. */
INSERT INTO dbo.MaintenanceRecord
(
    space_id, reporter_user_id, assigned_staff_user_id, problem_description,
    start_time, completion_time, maintenance_status, impact_level, result_note
)
SELECT TOP (@space_count)
    s.space_id,
    @approver_id,
    @approver_id,
    N'Generated completed electrical inspection.',
    DATEADD(DAY, -30, CAST('2022-07-01' AS DATETIME2(0))),
    DATEADD(HOUR, 4, DATEADD(DAY, -30, CAST('2022-07-01' AS DATETIME2(0)))),
    N'Completed',
    N'out-of-service',
    N'Generated inspection completed before benchmark horizon.'
FROM dbo.Space AS s
WHERE s.space_code LIKE N'G13-BENCH-%'
ORDER BY s.space_id;

/*
    The latest approved booking in each benchmark space receives one active
    advisory. Because it is the latest approved booking for that space, the
    open-ended advisory produces exactly one acknowledgement rather than
    unrealistically warning every later historical booking.
*/
;WITH TargetBookings AS
(
    SELECT
        b.booking_id,
        b.space_id,
        b.requested_start_time,
        b.requested_end_time,
        ROW_NUMBER() OVER
        (
            PARTITION BY b.space_id
            ORDER BY b.requested_start_time DESC, b.booking_id DESC
        ) AS sequence_number
    FROM dbo.Booking AS b
    INNER JOIN dbo.Space AS s ON s.space_id = b.space_id
    WHERE s.space_code LIKE N'G13-BENCH-%'
      AND b.booking_status = N'Approved'
)
INSERT INTO dbo.MaintenanceRecord
(
    space_id, reporter_user_id, assigned_staff_user_id, problem_description,
    start_time, completion_time, maintenance_status, impact_level, result_note
)
SELECT
    space_id,
    @approver_id,
    @approver_id,
    CONCAT(N'Generated active advisory for booking ', booking_id, N': projector degradation.'),
    DATEADD(MINUTE, 15, requested_start_time),
    NULL,
    N'InProgress',
    N'advisory',
    NULL
FROM TargetBookings
WHERE sequence_number = 1;

INSERT INTO dbo.BookingMaintenanceAdvisoryAcknowledgement
(
    booking_id, maintenance_id, acknowledged_at, advisory_summary_at_acknowledgement
)
SELECT
    b.booking_id,
    m.maintenance_id,
    DATEADD(MINUTE, -5, b.requested_start_time),
    m.problem_description
FROM dbo.Booking AS b
INNER JOIN dbo.Space AS s ON s.space_id = b.space_id
INNER JOIN dbo.MaintenanceRecord AS m
    ON m.space_id = b.space_id
   AND m.maintenance_status = N'InProgress'
   AND m.impact_level = N'advisory'
   AND b.requested_start_time < ISNULL(m.completion_time, CONVERT(DATETIME2(0), '9999-12-31 23:59:59'))
   AND b.requested_end_time > m.start_time
WHERE s.space_code LIKE N'G13-BENCH-%'
  AND b.booking_status = N'Approved';

UPDATE b
SET advisories_presented_at = DATEADD(MINUTE, -5, b.requested_start_time),
    advisory_acknowledged_at = DATEADD(MINUTE, -4, b.requested_start_time)
FROM dbo.Booking AS b
WHERE EXISTS
(
    SELECT 1
    FROM dbo.BookingMaintenanceAdvisoryAcknowledgement AS a
    WHERE a.booking_id = b.booking_id
);

COMMIT TRANSACTION;

SELECT
    COUNT(*) AS generated_bookings,
    MIN(requested_start_time) AS first_booking,
    MAX(requested_end_time) AS last_booking
FROM dbo.Booking AS b
INNER JOIN dbo.Space AS s ON s.space_id = b.space_id
WHERE s.space_code LIKE N'G13-BENCH-%';

SELECT booking_status, COUNT(*) AS booking_count
FROM dbo.Booking AS b
INNER JOIN dbo.Space AS s ON s.space_id = b.space_id
WHERE s.space_code LIKE N'G13-BENCH-%'
GROUP BY booking_status
ORDER BY booking_status;

SELECT impact_level, maintenance_status, COUNT(*) AS maintenance_count
FROM dbo.MaintenanceRecord AS m
INNER JOIN dbo.Space AS s ON s.space_id = m.space_id
WHERE s.space_code LIKE N'G13-BENCH-%'
GROUP BY impact_level, maintenance_status
ORDER BY impact_level, maintenance_status;
