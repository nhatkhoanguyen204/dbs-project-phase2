/*
    Creates isolated test data. Execute after baseline, migration, and concurrency implementation.
*/
SET XACT_ABORT ON;
BEGIN TRANSACTION;

DECLARE @space_code NVARCHAR(30) = N'G13-CONCUR-TEST';
DECLARE @student_id BIGINT = (SELECT TOP (1) user_id FROM dbo.[User] WHERE role = N'Student' AND account_status = N'Active');
DECLARE @staff_id BIGINT = (SELECT TOP (1) user_id FROM dbo.[User] WHERE role = N'FacilityStaff' AND account_status = N'Active');
DECLARE @space_id BIGINT;

IF @student_id IS NULL OR @staff_id IS NULL
    THROW 51100, 'An active Student and FacilityStaff user are required for this test.', 1;

IF OBJECT_ID(N'dbo.ConcurrencyTestRunG13', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ConcurrencyTestRunG13
    (
        test_name NVARCHAR(60) NOT NULL PRIMARY KEY,
        space_id BIGINT NOT NULL,
        session_a_booking_id BIGINT NOT NULL,
        session_b_booking_id BIGINT NOT NULL,
        advisory_booking_id BIGINT NOT NULL,
        advisory_maintenance_id BIGINT NOT NULL,
        requester_user_id BIGINT NOT NULL,
        approver_user_id BIGINT NOT NULL,
        created_at DATETIME2(0) NOT NULL CONSTRAINT df_concurrency_test_run_created_at DEFAULT (SYSDATETIME())
    );
END;

SELECT @space_id = space_id FROM dbo.Space WHERE space_code = @space_code;

IF @space_id IS NOT NULL
BEGIN
    DELETE mbi
    FROM dbo.MaintenanceBookingImpact AS mbi
    INNER JOIN dbo.MaintenanceRecord AS m ON m.maintenance_id = mbi.maintenance_id
    WHERE m.space_id = @space_id;

    DELETE a
    FROM dbo.BookingMaintenanceAdvisoryAcknowledgement AS a
    INNER JOIN dbo.Booking AS b ON b.booking_id = a.booking_id
    WHERE b.space_id = @space_id;

    DELETE d
    FROM dbo.BookingDecision AS d
    INNER JOIN dbo.Booking AS b ON b.booking_id = d.booking_id
    WHERE b.space_id = @space_id;

    DELETE FROM dbo.Booking WHERE space_id = @space_id;
    DELETE FROM dbo.MaintenanceImpactHistory WHERE maintenance_id IN (SELECT maintenance_id FROM dbo.MaintenanceRecord WHERE space_id = @space_id);
    DELETE FROM dbo.MaintenanceRecord WHERE space_id = @space_id;
    DELETE FROM dbo.Space WHERE space_id = @space_id;
END;

DELETE FROM dbo.ConcurrencyTestRunG13 WHERE test_name = N'G13 locking test';

INSERT INTO dbo.Space
(
    space_code, space_name, space_type, building, floor, room_number,
    capacity, current_status, usage_policy
)
VALUES
(
    @space_code, N'Group 13 Concurrency Test Space', N'MeetingRoom', N'Test Building', N'1', N'T01',
    20, N'Available', N'Isolated automated concurrency test space.'
);

SET @space_id = CONVERT(BIGINT, SCOPE_IDENTITY());

DECLARE @session_a_booking_id BIGINT;
DECLARE @session_b_booking_id BIGINT;
DECLARE @advisory_booking_id BIGINT;
DECLARE @advisory_maintenance_id BIGINT;

EXEC dbo.usp_CreateBooking
    @requester_user_id = @student_id,
    @space_id = @space_id,
    @requested_start_time = '2030-01-15 09:00:00',
    @requested_end_time = '2030-01-15 11:00:00',
    @purpose = N'Meeting',
    @expected_participants = 10,
    @booking_id = @session_a_booking_id OUTPUT;

EXEC dbo.usp_CreateBooking
    @requester_user_id = @student_id,
    @space_id = @space_id,
    @requested_start_time = '2030-01-15 10:00:00',
    @requested_end_time = '2030-01-15 12:00:00',
    @purpose = N'Meeting',
    @expected_participants = 10,
    @booking_id = @session_b_booking_id OUTPUT;

INSERT INTO dbo.MaintenanceRecord
(
    space_id, reporter_user_id, assigned_staff_user_id, problem_description,
    start_time, completion_time, maintenance_status, impact_level, result_note
)
VALUES
(
    @space_id, @staff_id, @staff_id, N'Advisory test: projector lamp is degraded.',
    '2030-01-16 09:00:00', NULL, N'InProgress', N'advisory', NULL
);

SET @advisory_maintenance_id = CONVERT(BIGINT, SCOPE_IDENTITY());

EXEC dbo.usp_CreateBooking
    @requester_user_id = @student_id,
    @space_id = @space_id,
    @requested_start_time = '2030-01-16 10:00:00',
    @requested_end_time = '2030-01-16 11:00:00',
    @purpose = N'Meeting',
    @expected_participants = 10,
    @booking_id = @advisory_booking_id OUTPUT;

INSERT INTO dbo.ConcurrencyTestRunG13
(
    test_name, space_id, session_a_booking_id, session_b_booking_id,
    advisory_booking_id, advisory_maintenance_id, requester_user_id, approver_user_id
)
VALUES
(
    N'G13 locking test', @space_id, @session_a_booking_id, @session_b_booking_id,
    @advisory_booking_id, @advisory_maintenance_id, @student_id, @staff_id
);

COMMIT TRANSACTION;

SELECT * FROM dbo.ConcurrencyTestRunG13 WHERE test_name = N'G13 locking test';
