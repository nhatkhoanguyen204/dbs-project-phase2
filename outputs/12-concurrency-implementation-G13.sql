/*
    CSMS Phase 2 - Concurrency-safe booking workflow
    Group: G13
    Execute after 05-db-definition-G13.sql and 10-schema-migration-G13.sql.
*/

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;
GO

/*
    Creates a pending booking. When @auto_approve = 1, the request is immediately
    passed to dbo.usp_ApproveBooking, which owns the per-space availability lock.
*/
CREATE OR ALTER PROCEDURE dbo.usp_CreateBooking
    @requester_user_id BIGINT,
    @space_id BIGINT,
    @requested_start_time DATETIME2(0),
    @requested_end_time DATETIME2(0),
    @purpose NVARCHAR(40),
    @expected_participants INT,
    @auto_approve BIT = 0,
    @decision_maker_user_id BIGINT = NULL,
    @acknowledge_current_advisories BIT = 0,
    @booking_id BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @requested_end_time <= @requested_start_time
        THROW 51030, 'The booking end time must be later than its start time.', 1;

    IF @expected_participants <= 0
        THROW 51031, 'Expected participants must be positive.', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.[User]
        WHERE user_id = @requester_user_id
          AND account_status = N'Active'
    )
        THROW 51032, 'The requester must have an active account.', 1;

    IF @auto_approve = 1 AND @decision_maker_user_id IS NULL
        THROW 51033, 'Auto-approval requires an auditable system/service decision-maker account.', 1;

    INSERT INTO dbo.Booking
    (
        requester_user_id,
        space_id,
        requested_start_time,
        requested_end_time,
        purpose,
        expected_participants,
        booking_status
    )
    VALUES
    (
        @requester_user_id,
        @space_id,
        @requested_start_time,
        @requested_end_time,
        @purpose,
        @expected_participants,
        N'Pending'
    );

    SET @booking_id = CONVERT(BIGINT, SCOPE_IDENTITY());

    IF @auto_approve = 1
    BEGIN
        EXEC dbo.usp_ApproveBooking
            @booking_id = @booking_id,
            @decision_maker_user_id = @decision_maker_user_id,
            @is_auto_approval = 1,
            @acknowledge_current_advisories = @acknowledge_current_advisories;
    END;
END;
GO

/*
    The sole approval path for instant and manual approvals. It serializes
    availability changes for one space with a transaction-owned application lock.
*/
CREATE OR ALTER PROCEDURE dbo.usp_ApproveBooking
    @booking_id BIGINT,
    @decision_maker_user_id BIGINT,
    @is_auto_approval BIT = 0,
    @acknowledge_current_advisories BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @space_id BIGINT,
        @requester_user_id BIGINT,
        @requested_start_time DATETIME2(0),
        @requested_end_time DATETIME2(0),
        @purpose NVARCHAR(40),
        @expected_participants INT,
        @booking_status NVARCHAR(20),
        @pre_buffer_minutes INT = 0,
        @post_buffer_minutes INT = 0,
        @effective_start_time DATETIME2(0),
        @effective_end_time DATETIME2(0),
        @lock_result INT,
        @lock_resource NVARCHAR(255),
        @decision NVARCHAR(20);

    BEGIN TRY
        SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
        BEGIN TRANSACTION;

        /* Lock the booking briefly to obtain its space, then serialize the space. */
        SELECT
            @space_id = b.space_id
        FROM dbo.Booking AS b WITH (UPDLOCK, HOLDLOCK)
        WHERE b.booking_id = @booking_id;

        IF @space_id IS NULL
            THROW 51034, 'The booking does not exist.', 1;

        SET @lock_resource = N'CSMS:Space:' + CONVERT(NVARCHAR(30), @space_id);

        EXEC @lock_result = sys.sp_getapplock
            @Resource = @lock_resource,
            @LockMode = N'Exclusive',
            @LockOwner = N'Transaction',
            @LockTimeout = 10000;

        IF @lock_result < 0
            THROW 51035, 'Could not obtain the space availability lock.', 1;

        /* Re-read under the shared space lock; only a pending request may advance. */
        SELECT
            @requester_user_id = b.requester_user_id,
            @requested_start_time = b.requested_start_time,
            @requested_end_time = b.requested_end_time,
            @purpose = b.purpose,
            @expected_participants = b.expected_participants,
            @booking_status = b.booking_status
        FROM dbo.Booking AS b WITH (UPDLOCK, HOLDLOCK)
        WHERE b.booking_id = @booking_id
          AND b.space_id = @space_id;

        IF @booking_status <> N'Pending'
            THROW 51036, 'Only a pending booking can be approved.', 1;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.[User] AS u
            WHERE u.user_id = @decision_maker_user_id
              AND u.account_status = N'Active'
              AND u.role IN (N'FacilityStaff', N'FacilityManager')
        )
            THROW 51037, 'Approval requires an active Facility Staff or Facility Manager account.', 1;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.[User] AS u
            WHERE u.user_id = @requester_user_id
              AND u.account_status = N'Active'
        )
            THROW 51038, 'The requester account is no longer active.', 1;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.Space AS s WITH (UPDLOCK, HOLDLOCK)
            WHERE s.space_id = @space_id
              AND s.current_status IN (N'Available', N'InUse')
              AND s.capacity >= @expected_participants
        )
            THROW 51039, 'The space is unavailable or has insufficient capacity.', 1;

        /* Choose the most specific applicable policy for buffers and auto-approval. */
        SELECT TOP (1)
            @pre_buffer_minutes = p.pre_buffer_minutes,
            @post_buffer_minutes = p.post_buffer_minutes
        FROM dbo.BookingPolicy AS p WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.[User] AS r ON r.user_id = @requester_user_id
        WHERE (p.space_id = @space_id OR p.space_id IS NULL)
          AND (p.applicable_role = r.role OR p.applicable_role IS NULL)
          AND (p.applicable_purpose = @purpose OR p.applicable_purpose IS NULL)
        ORDER BY
            CASE WHEN p.space_id = @space_id THEN 1 ELSE 0 END DESC,
            CASE WHEN p.applicable_role = r.role THEN 1 ELSE 0 END DESC,
            CASE WHEN p.applicable_purpose = @purpose THEN 1 ELSE 0 END DESC,
            p.policy_id DESC;

        SET @effective_start_time = DATEADD(MINUTE, -@pre_buffer_minutes, @requested_start_time);
        SET @effective_end_time = DATEADD(MINUTE, @post_buffer_minutes, @requested_end_time);

        IF @is_auto_approval = 1
           AND NOT EXISTS
           (
               SELECT 1
               FROM dbo.BookingPolicy AS p
               INNER JOIN dbo.[User] AS r ON r.user_id = @requester_user_id
               WHERE p.auto_approval_enabled = 1
                 AND (p.space_id = @space_id OR p.space_id IS NULL)
                 AND (p.applicable_role = r.role OR p.applicable_role IS NULL)
                 AND (p.applicable_purpose = @purpose OR p.applicable_purpose IS NULL)
           )
            THROW 51040, 'No matching policy authorizes automatic approval.', 1;

        IF EXISTS
        (
            SELECT 1
            FROM dbo.Booking AS b WITH (UPDLOCK, HOLDLOCK, INDEX(ix_booking_space_status_time))
            WHERE b.space_id = @space_id
              AND b.booking_id <> @booking_id
              AND b.booking_status IN (N'Approved', N'CheckedIn')
              AND @effective_start_time < b.requested_end_time
              AND @effective_end_time > b.requested_start_time
        )
            THROW 51041, 'An approved or checked-in booking overlaps this effective interval.', 1;

        IF EXISTS
        (
            SELECT 1
            FROM dbo.MaintenanceRecord AS m WITH (UPDLOCK, HOLDLOCK, INDEX(ix_maintenance_space_impact_time))
            WHERE m.space_id = @space_id
              AND m.maintenance_status IN (N'Reported', N'Assigned', N'InProgress')
              AND m.impact_level = N'out-of-service'
              AND @requested_start_time < ISNULL(m.completion_time, CONVERT(DATETIME2(0), '9999-12-31 23:59:59'))
              AND @requested_end_time > m.start_time
        )
            THROW 51042, 'An active out-of-service maintenance record overlaps this booking.', 1;

        IF EXISTS
        (
            SELECT 1
            FROM dbo.MaintenanceRecord AS m WITH (UPDLOCK, HOLDLOCK, INDEX(ix_maintenance_space_impact_time))
            WHERE m.space_id = @space_id
              AND m.maintenance_status IN (N'Reported', N'Assigned', N'InProgress')
              AND m.impact_level = N'advisory'
              AND @requested_start_time < ISNULL(m.completion_time, CONVERT(DATETIME2(0), '9999-12-31 23:59:59'))
              AND @requested_end_time > m.start_time
        )
        BEGIN
            IF @acknowledge_current_advisories = 0
                THROW 51043, 'Active advisories require requester acknowledgement before approval.', 1;

            INSERT INTO dbo.BookingMaintenanceAdvisoryAcknowledgement
            (
                booking_id,
                maintenance_id,
                acknowledged_at,
                advisory_summary_at_acknowledgement
            )
            SELECT
                @booking_id,
                m.maintenance_id,
                SYSDATETIME(),
                m.problem_description
            FROM dbo.MaintenanceRecord AS m WITH (UPDLOCK, HOLDLOCK, INDEX(ix_maintenance_space_impact_time))
            WHERE m.space_id = @space_id
              AND m.maintenance_status IN (N'Reported', N'Assigned', N'InProgress')
              AND m.impact_level = N'advisory'
              AND @requested_start_time < ISNULL(m.completion_time, CONVERT(DATETIME2(0), '9999-12-31 23:59:59'))
              AND @requested_end_time > m.start_time
              AND NOT EXISTS
              (
                  SELECT 1
                  FROM dbo.BookingMaintenanceAdvisoryAcknowledgement AS a WITH (UPDLOCK, HOLDLOCK)
                  WHERE a.booking_id = @booking_id
                    AND a.maintenance_id = m.maintenance_id
              );

            UPDATE dbo.Booking
            SET advisories_presented_at = COALESCE(advisories_presented_at, SYSDATETIME()),
                advisory_acknowledged_at = SYSDATETIME()
            WHERE booking_id = @booking_id;
        END;

        SET @decision = CASE WHEN @is_auto_approval = 1 THEN N'AutoApproved' ELSE N'Approved' END;

        INSERT INTO dbo.BookingDecision
        (
            booking_id,
            decision_maker_user_id,
            decision_time,
            decision,
            decision_note,
            rejection_reason
        )
        VALUES
        (
            @booking_id,
            @decision_maker_user_id,
            SYSDATETIME(),
            @decision,
            CASE WHEN @is_auto_approval = 1 THEN N'Automatic approval after transactional availability validation.' ELSE N'Manual approval after transactional availability validation.' END,
            NULL
        );

        UPDATE dbo.Booking
        SET booking_status = N'Approved'
        WHERE booking_id = @booking_id
          AND booking_status = N'Pending';

        IF @@ROWCOUNT <> 1
            THROW 51044, 'Booking status changed during approval.', 1;

        COMMIT TRANSACTION;

        SELECT
            @booking_id AS booking_id,
            N'Approved' AS result_status,
            @decision AS decision;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

/*
    Escalates an active advisory. It uses the same per-space lock as approval,
    records the change, and creates idempotent impact work items.
*/
CREATE OR ALTER PROCEDURE dbo.usp_SetMaintenanceImpactLevel
    @maintenance_id BIGINT,
    @new_impact_level NVARCHAR(20),
    @changed_by_user_id BIGINT,
    @change_note NVARCHAR(1000)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @space_id BIGINT,
        @prior_impact_level NVARCHAR(20),
        @lock_result INT,
        @lock_resource NVARCHAR(255);

    IF @new_impact_level NOT IN (N'advisory', N'out-of-service')
        THROW 51045, 'Impact level must be advisory or out-of-service.', 1;

    BEGIN TRY
        SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
        BEGIN TRANSACTION;

        SELECT @space_id = m.space_id
        FROM dbo.MaintenanceRecord AS m WITH (UPDLOCK, HOLDLOCK)
        WHERE m.maintenance_id = @maintenance_id;

        IF @space_id IS NULL
            THROW 51046, 'Maintenance record does not exist.', 1;

        SET @lock_resource = N'CSMS:Space:' + CONVERT(NVARCHAR(30), @space_id);

        EXEC @lock_result = sys.sp_getapplock
            @Resource = @lock_resource,
            @LockMode = N'Exclusive',
            @LockOwner = N'Transaction',
            @LockTimeout = 10000;

        IF @lock_result < 0
            THROW 51047, 'Could not obtain the space maintenance lock.', 1;

        SELECT @prior_impact_level = m.impact_level
        FROM dbo.MaintenanceRecord AS m WITH (UPDLOCK, HOLDLOCK)
        WHERE m.maintenance_id = @maintenance_id
          AND m.maintenance_status IN (N'Reported', N'Assigned', N'InProgress');

        IF @prior_impact_level IS NULL
            THROW 51048, 'Only active maintenance can change impact level.', 1;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.[User] AS u
            WHERE u.user_id = @changed_by_user_id
              AND u.account_status = N'Active'
              AND u.role IN (N'FacilityStaff', N'FacilityManager')
        )
            THROW 51049, 'Impact-level changes require active facility personnel.', 1;

        IF @prior_impact_level <> @new_impact_level
        BEGIN
            UPDATE dbo.MaintenanceRecord
            SET impact_level = @new_impact_level
            WHERE maintenance_id = @maintenance_id;

            INSERT INTO dbo.MaintenanceImpactHistory
            (
                maintenance_id,
                prior_impact_level,
                new_impact_level,
                changed_by_user_id,
                changed_at,
                change_note
            )
            VALUES
            (
                @maintenance_id,
                @prior_impact_level,
                @new_impact_level,
                @changed_by_user_id,
                SYSDATETIME(),
                @change_note
            );

            IF @prior_impact_level = N'advisory'
               AND @new_impact_level = N'out-of-service'
            BEGIN
                INSERT INTO dbo.MaintenanceBookingImpact
                (
                    maintenance_id,
                    booking_id,
                    identified_at,
                    identified_by_user_id,
                    contact_status
                )
                SELECT
                    @maintenance_id,
                    b.booking_id,
                    SYSDATETIME(),
                    @changed_by_user_id,
                    N'PendingContact'
                FROM dbo.Booking AS b WITH (UPDLOCK, HOLDLOCK, INDEX(ix_booking_space_status_time))
                INNER JOIN dbo.MaintenanceRecord AS m
                    ON m.maintenance_id = @maintenance_id
                   AND m.space_id = b.space_id
                WHERE b.booking_status IN (N'Approved', N'CheckedIn')
                  AND b.requested_start_time < ISNULL(m.completion_time, CONVERT(DATETIME2(0), '9999-12-31 23:59:59'))
                  AND b.requested_end_time > m.start_time
                  AND NOT EXISTS
                  (
                      SELECT 1
                      FROM dbo.MaintenanceBookingImpact AS mbi WITH (UPDLOCK, HOLDLOCK)
                      WHERE mbi.maintenance_id = @maintenance_id
                        AND mbi.booking_id = b.booking_id
                  );
            END;
        END;

        COMMIT TRANSACTION;

        SELECT
            @maintenance_id AS maintenance_id,
            @prior_impact_level AS prior_impact_level,
            @new_impact_level AS new_impact_level;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

