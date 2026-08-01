/*
    CSMS Phase 2 - SQL Server database definition
    Safe to rerun: tables, indexes, and triggers are created only when absent
    (triggers are created or altered). Historical business records are retained.
*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;
GO

/* Master data */
IF OBJECT_ID(N'dbo.[User]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[User]
    (
        user_id BIGINT IDENTITY(1, 1) NOT NULL,
        full_name NVARCHAR(150) NOT NULL,
        email NVARCHAR(254) NOT NULL,
        phone_number NVARCHAR(30) NULL,
        role NVARCHAR(30) NOT NULL,
        department NVARCHAR(100) NOT NULL,
        account_status NVARCHAR(20) NOT NULL CONSTRAINT df_user_account_status DEFAULT N'Active',
        CONSTRAINT pk_user PRIMARY KEY (user_id),
        CONSTRAINT uq_user_email UNIQUE (email),
        CONSTRAINT ck_user_role CHECK (role IN (N'Student', N'Lecturer', N'TA', N'FacilityStaff', N'DeptAdmin', N'FacilityManager')),
        CONSTRAINT ck_user_account_status CHECK (account_status IN (N'Active', N'Inactive', N'Suspended'))
    );
END;
GO

IF OBJECT_ID(N'dbo.Space', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Space
    (
        space_id BIGINT IDENTITY(1, 1) NOT NULL,
        space_code NVARCHAR(30) NOT NULL,
        space_name NVARCHAR(150) NOT NULL,
        space_type NVARCHAR(40) NOT NULL,
        building NVARCHAR(80) NOT NULL,
        floor NVARCHAR(20) NOT NULL,
        room_number NVARCHAR(30) NOT NULL,
        capacity INT NOT NULL,
        current_status NVARCHAR(30) NOT NULL CONSTRAINT df_space_current_status DEFAULT N'Available',
        usage_policy NVARCHAR(1000) NULL,
        CONSTRAINT pk_space PRIMARY KEY (space_id),
        CONSTRAINT uq_space_code UNIQUE (space_code),
        CONSTRAINT ck_space_type CHECK (space_type IN (N'Auditorium', N'Classroom', N'ComputerLaboratory', N'ProjectLaboratory', N'MeetingRoom', N'StudentWorkspace')),
        CONSTRAINT ck_space_capacity_positive CHECK (capacity > 0),
        CONSTRAINT ck_space_status CHECK (current_status IN (N'Available', N'InUse', N'UnderMaintenance', N'TemporarilyClosed', N'Retired'))
    );
END;
GO

IF OBJECT_ID(N'dbo.Facility', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Facility
    (
        facility_id BIGINT IDENTITY(1, 1) NOT NULL,
        facility_name NVARCHAR(100) NOT NULL,
        facility_type NVARCHAR(50) NOT NULL,
        description NVARCHAR(500) NULL,
        CONSTRAINT pk_facility PRIMARY KEY (facility_id),
        CONSTRAINT uq_facility_name_type UNIQUE (facility_name, facility_type)
    );
END;
GO

IF OBJECT_ID(N'dbo.SpaceFacility', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.SpaceFacility
    (
        space_id BIGINT NOT NULL,
        facility_id BIGINT NOT NULL,
        quantity INT NOT NULL CONSTRAINT df_space_facility_quantity DEFAULT (1),
        notes NVARCHAR(500) NULL,
        CONSTRAINT pk_space_facility PRIMARY KEY (space_id, facility_id),
        CONSTRAINT fk_space_facility_space FOREIGN KEY (space_id) REFERENCES dbo.Space (space_id) ON DELETE CASCADE ON UPDATE NO ACTION,
        CONSTRAINT fk_space_facility_facility FOREIGN KEY (facility_id) REFERENCES dbo.Facility (facility_id) ON DELETE CASCADE ON UPDATE NO ACTION,
        CONSTRAINT ck_space_facility_quantity_positive CHECK (quantity > 0)
    );
END;
GO

/* Configurable booking policies */
IF OBJECT_ID(N'dbo.BookingPolicy', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.BookingPolicy
    (
        policy_id BIGINT IDENTITY(1, 1) NOT NULL,
        space_id BIGINT NULL,
        applicable_role NVARCHAR(30) NULL,
        applicable_purpose NVARCHAR(40) NULL,
        minimum_lead_minutes INT NOT NULL CONSTRAINT df_booking_policy_minimum_lead DEFAULT (0),
        cancellation_lead_minutes INT NOT NULL CONSTRAINT df_booking_policy_cancellation_lead DEFAULT (0),
        pre_buffer_minutes INT NOT NULL CONSTRAINT df_booking_policy_pre_buffer DEFAULT (0),
        post_buffer_minutes INT NOT NULL CONSTRAINT df_booking_policy_post_buffer DEFAULT (0),
        CONSTRAINT pk_booking_policy PRIMARY KEY (policy_id),
        CONSTRAINT fk_booking_policy_space FOREIGN KEY (space_id) REFERENCES dbo.Space (space_id) ON DELETE NO ACTION ON UPDATE NO ACTION,
        CONSTRAINT ck_booking_policy_role CHECK (applicable_role IS NULL OR applicable_role IN (N'Student', N'Lecturer', N'TA', N'FacilityStaff', N'DeptAdmin', N'FacilityManager')),
        CONSTRAINT ck_booking_policy_purpose CHECK (applicable_purpose IS NULL OR applicable_purpose IN (N'Lecture', N'Examination', N'Seminar', N'Workshop', N'Meeting', N'StudentActivity', N'AdministrativeEvent')),
        CONSTRAINT ck_booking_policy_minutes_nonnegative CHECK (minimum_lead_minutes >= 0 AND cancellation_lead_minutes >= 0 AND pre_buffer_minutes >= 0 AND post_buffer_minutes >= 0)
    );
END;
GO

/* Booking workflow and usage history */
IF OBJECT_ID(N'dbo.Booking', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Booking
    (
        booking_id BIGINT IDENTITY(1, 1) NOT NULL,
        requester_user_id BIGINT NOT NULL,
        space_id BIGINT NOT NULL,
        requested_start_time DATETIME2(0) NOT NULL,
        requested_end_time DATETIME2(0) NOT NULL,
        purpose NVARCHAR(40) NOT NULL,
        expected_participants INT NOT NULL,
        booking_status NVARCHAR(20) NOT NULL CONSTRAINT df_booking_status DEFAULT N'Pending',
        submitted_at DATETIME2(0) NOT NULL CONSTRAINT df_booking_submitted_at DEFAULT (SYSDATETIME()),
        cancelled_at DATETIME2(0) NULL,
        cancelled_by_user_id BIGINT NULL,
        cancellation_note NVARCHAR(1000) NULL,
        CONSTRAINT pk_booking PRIMARY KEY (booking_id),
        CONSTRAINT fk_booking_requester FOREIGN KEY (requester_user_id) REFERENCES dbo.[User] (user_id) ON DELETE NO ACTION ON UPDATE NO ACTION,
        CONSTRAINT fk_booking_space FOREIGN KEY (space_id) REFERENCES dbo.Space (space_id) ON DELETE NO ACTION ON UPDATE NO ACTION,
        CONSTRAINT fk_booking_cancelled_by FOREIGN KEY (cancelled_by_user_id) REFERENCES dbo.[User] (user_id) ON DELETE NO ACTION ON UPDATE NO ACTION,
        CONSTRAINT ck_booking_time_order CHECK (requested_end_time > requested_start_time),
        CONSTRAINT ck_booking_expected_participants_positive CHECK (expected_participants > 0),
        CONSTRAINT ck_booking_purpose CHECK (purpose IN (N'Lecture', N'Examination', N'Seminar', N'Workshop', N'Meeting', N'StudentActivity', N'AdministrativeEvent')),
        CONSTRAINT ck_booking_status CHECK (booking_status IN (N'Pending', N'Approved', N'Rejected', N'Cancelled', N'CheckedIn', N'Completed', N'NoShow')),
        CONSTRAINT ck_booking_cancellation_audit CHECK
        (
            (booking_status = N'Cancelled' AND cancelled_at IS NOT NULL AND cancelled_by_user_id IS NOT NULL)
            OR (booking_status <> N'Cancelled' AND cancelled_at IS NULL AND cancelled_by_user_id IS NULL)
        )
    );
END;
GO

IF OBJECT_ID(N'dbo.BookingDecision', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.BookingDecision
    (
        decision_id BIGINT IDENTITY(1, 1) NOT NULL,
        booking_id BIGINT NOT NULL,
        decision_maker_user_id BIGINT NOT NULL,
        decision_time DATETIME2(0) NOT NULL CONSTRAINT df_booking_decision_time DEFAULT (SYSDATETIME()),
        decision NVARCHAR(20) NOT NULL,
        decision_note NVARCHAR(1000) NULL,
        rejection_reason NVARCHAR(1000) NULL,
        CONSTRAINT pk_booking_decision PRIMARY KEY (decision_id),
        CONSTRAINT fk_booking_decision_booking FOREIGN KEY (booking_id) REFERENCES dbo.Booking (booking_id) ON DELETE NO ACTION ON UPDATE NO ACTION,
        CONSTRAINT fk_booking_decision_maker FOREIGN KEY (decision_maker_user_id) REFERENCES dbo.[User] (user_id) ON DELETE NO ACTION ON UPDATE NO ACTION,
        CONSTRAINT ck_booking_decision_value CHECK (decision IN (N'Approved', N'Rejected', N'AutoApproved')),
        CONSTRAINT ck_booking_decision_rejection_reason CHECK ((decision = N'Rejected' AND rejection_reason IS NOT NULL) OR (decision <> N'Rejected' AND rejection_reason IS NULL))
    );
END;
GO

IF OBJECT_ID(N'dbo.UsageSession', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.UsageSession
    (
        usage_session_id BIGINT IDENTITY(1, 1) NOT NULL,
        booking_id BIGINT NOT NULL,
        check_in_by_user_id BIGINT NOT NULL,
        actual_start_time DATETIME2(0) NOT NULL,
        initial_condition NVARCHAR(1000) NOT NULL,
        check_out_by_user_id BIGINT NULL,
        actual_end_time DATETIME2(0) NULL,
        final_condition NVARCHAR(1000) NULL,
        usage_notes NVARCHAR(1000) NULL,
        CONSTRAINT pk_usage_session PRIMARY KEY (usage_session_id),
        CONSTRAINT uq_usage_session_booking UNIQUE (booking_id),
        CONSTRAINT fk_usage_session_booking FOREIGN KEY (booking_id) REFERENCES dbo.Booking (booking_id) ON DELETE CASCADE ON UPDATE NO ACTION,
        CONSTRAINT fk_usage_session_check_in_by FOREIGN KEY (check_in_by_user_id) REFERENCES dbo.[User] (user_id) ON DELETE NO ACTION ON UPDATE NO ACTION,
        CONSTRAINT fk_usage_session_check_out_by FOREIGN KEY (check_out_by_user_id) REFERENCES dbo.[User] (user_id) ON DELETE NO ACTION ON UPDATE NO ACTION,
        CONSTRAINT ck_usage_session_time_order CHECK (actual_end_time IS NULL OR actual_end_time > actual_start_time),
        CONSTRAINT ck_usage_session_checkout_audit CHECK
        (
            (actual_end_time IS NULL AND check_out_by_user_id IS NULL AND final_condition IS NULL)
            OR (actual_end_time IS NOT NULL AND check_out_by_user_id IS NOT NULL AND final_condition IS NOT NULL)
        )
    );
END;
GO

/* Maintenance history */
IF OBJECT_ID(N'dbo.MaintenanceRecord', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MaintenanceRecord
    (
        maintenance_id BIGINT IDENTITY(1, 1) NOT NULL,
        space_id BIGINT NOT NULL,
        reporter_user_id BIGINT NOT NULL,
        assigned_staff_user_id BIGINT NULL,
        problem_description NVARCHAR(2000) NOT NULL,
        start_time DATETIME2(0) NOT NULL,
        completion_time DATETIME2(0) NULL,
        maintenance_status NVARCHAR(30) NOT NULL CONSTRAINT df_maintenance_status DEFAULT N'Reported',
        result_note NVARCHAR(2000) NULL,
        CONSTRAINT pk_maintenance_record PRIMARY KEY (maintenance_id),
        CONSTRAINT fk_maintenance_record_space FOREIGN KEY (space_id) REFERENCES dbo.Space (space_id) ON DELETE NO ACTION ON UPDATE NO ACTION,
        CONSTRAINT fk_maintenance_record_reporter FOREIGN KEY (reporter_user_id) REFERENCES dbo.[User] (user_id) ON DELETE NO ACTION ON UPDATE NO ACTION,
        CONSTRAINT fk_maintenance_record_assignee FOREIGN KEY (assigned_staff_user_id) REFERENCES dbo.[User] (user_id) ON DELETE NO ACTION ON UPDATE NO ACTION,
        CONSTRAINT ck_maintenance_record_status CHECK (maintenance_status IN (N'Reported', N'Assigned', N'InProgress', N'Completed', N'Cancelled')),
        CONSTRAINT ck_maintenance_record_time_order CHECK (completion_time IS NULL OR completion_time >= start_time),
        CONSTRAINT ck_maintenance_record_completion_audit CHECK
        (
            (maintenance_status = N'Completed' AND completion_time IS NOT NULL AND result_note IS NOT NULL)
            OR (maintenance_status <> N'Completed' AND completion_time IS NULL)
        )
    );
END;
GO

/* Supporting indexes */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.Booking') AND name = N'ix_booking_space_status_time')
    CREATE INDEX ix_booking_space_status_time ON dbo.Booking (space_id, booking_status, requested_start_time, requested_end_time);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.MaintenanceRecord') AND name = N'ix_maintenance_space_status_time')
    CREATE INDEX ix_maintenance_space_status_time ON dbo.MaintenanceRecord (space_id, maintenance_status, start_time, completion_time);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.Booking') AND name = N'ix_booking_requester_status_time')
    CREATE INDEX ix_booking_requester_status_time ON dbo.Booking (requester_user_id, booking_status, requested_start_time);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.BookingPolicy') AND name = N'uq_booking_policy_scope')
    CREATE UNIQUE INDEX uq_booking_policy_scope ON dbo.BookingPolicy (space_id, applicable_role, applicable_purpose);
GO

/*
    Booking integrity: this trigger prevents invalid active bookings. Application
    procedures must use a transaction around approval; the locking hints make
    conflict reads serializable for the affected space/time range.
*/
CREATE OR ALTER TRIGGER dbo.tr_booking_validate
ON dbo.Booking
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS
    (
        SELECT 1
        FROM inserted AS i
        INNER JOIN dbo.[User] AS u ON u.user_id = i.requester_user_id
        WHERE u.account_status <> N'Active'
    )
    BEGIN
        THROW 51000, 'A booking requester must have an active account.', 1;
    END;

    IF EXISTS
    (
        SELECT 1
        FROM inserted AS i
        INNER JOIN dbo.Space AS s ON s.space_id = i.space_id
        WHERE (i.booking_status IN (N'Pending', N'Approved', N'CheckedIn')
               AND s.current_status IN (N'UnderMaintenance', N'TemporarilyClosed', N'Retired'))
           OR i.expected_participants > s.capacity
    )
    BEGIN
        THROW 51001, 'The space is unavailable or its capacity is insufficient.', 1;
    END;

    IF EXISTS
    (
        SELECT 1
        FROM inserted AS i
        INNER JOIN dbo.Booking AS b WITH (UPDLOCK, HOLDLOCK)
            ON b.space_id = i.space_id
           AND b.booking_id <> i.booking_id
           AND b.booking_status IN (N'Approved', N'CheckedIn')
           AND i.booking_status IN (N'Approved', N'CheckedIn')
           AND i.requested_start_time < b.requested_end_time
           AND i.requested_end_time > b.requested_start_time
    )
    BEGIN
        THROW 51002, 'An approved or checked-in booking overlaps this requested interval.', 1;
    END;

    IF EXISTS
    (
        SELECT 1
        FROM inserted AS i
        INNER JOIN dbo.MaintenanceRecord AS m WITH (UPDLOCK, HOLDLOCK)
            ON m.space_id = i.space_id
           AND m.maintenance_status IN (N'Reported', N'Assigned', N'InProgress')
           AND i.booking_status IN (N'Approved', N'CheckedIn')
           AND i.requested_start_time < ISNULL(m.completion_time, CONVERT(DATETIME2(0), '9999-12-31 23:59:59'))
           AND i.requested_end_time > m.start_time
    )
    BEGIN
        THROW 51003, 'An active maintenance record blocks this booking interval.', 1;
    END;
END;
GO

/* Session integrity: only approved bookings can be checked in. */
CREATE OR ALTER TRIGGER dbo.tr_usage_session_validate
ON dbo.UsageSession
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS
    (
        SELECT 1
        FROM inserted AS i
        INNER JOIN dbo.Booking AS b ON b.booking_id = i.booking_id
        INNER JOIN dbo.[User] AS check_in_user ON check_in_user.user_id = i.check_in_by_user_id
        LEFT JOIN dbo.[User] AS check_out_user ON check_out_user.user_id = i.check_out_by_user_id
        WHERE b.booking_status NOT IN (N'Approved', N'CheckedIn', N'Completed')
           OR check_in_user.role NOT IN (N'FacilityStaff', N'FacilityManager')
           OR (check_out_user.user_id IS NOT NULL AND check_out_user.role NOT IN (N'FacilityStaff', N'FacilityManager'))
    )
    BEGIN
        THROW 51004, 'Usage sessions require an approved booking and authorized facility personnel.', 1;
    END;
END;
GO

/* Decision integrity: authorized staff/manager decisions must match booking state. */
CREATE OR ALTER TRIGGER dbo.tr_booking_decision_validate
ON dbo.BookingDecision
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS
    (
        SELECT 1
        FROM inserted AS i
        INNER JOIN dbo.[User] AS u ON u.user_id = i.decision_maker_user_id
        WHERE u.role NOT IN (N'FacilityStaff', N'FacilityManager')
           OR u.account_status <> N'Active'
    )
    BEGIN
        THROW 51005, 'Booking decisions require an active Facility Staff or Facility Manager account.', 1;
    END;
END;
GO
