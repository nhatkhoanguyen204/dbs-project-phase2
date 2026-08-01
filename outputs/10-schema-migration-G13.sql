-- Schema Migration Script: Phase 1 to Phase 2
-- Group: G13
-- Description: Migrates CSMS to support maintenance impact levels and advisory acknowledgements.

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    /* Preserve Phase 1 behavior: existing maintenance becomes blocking until explicitly downgraded. */
    IF COL_LENGTH(N'dbo.MaintenanceRecord', N'impact_level') IS NULL
        ALTER TABLE dbo.MaintenanceRecord ADD impact_level NVARCHAR(20) NULL;

    EXEC(N'UPDATE dbo.MaintenanceRecord
          SET impact_level = N''out-of-service''
          WHERE impact_level IS NULL;');

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.default_constraints AS d
        INNER JOIN sys.columns AS c
            ON c.object_id = d.parent_object_id AND c.column_id = d.parent_column_id
        WHERE d.parent_object_id = OBJECT_ID(N'dbo.MaintenanceRecord')
          AND c.name = N'impact_level'
    )
        EXEC(N'ALTER TABLE dbo.MaintenanceRecord
              ADD CONSTRAINT df_maintenance_record_impact_level DEFAULT N''out-of-service'' FOR impact_level;');

    IF EXISTS
    (
        SELECT 1 FROM sys.columns
        WHERE object_id = OBJECT_ID(N'dbo.MaintenanceRecord')
          AND name = N'impact_level' AND is_nullable = 1
    )
        EXEC(N'ALTER TABLE dbo.MaintenanceRecord ALTER COLUMN impact_level NVARCHAR(20) NOT NULL;');

    IF NOT EXISTS
    (
        SELECT 1 FROM sys.check_constraints
        WHERE parent_object_id = OBJECT_ID(N'dbo.MaintenanceRecord')
          AND name = N'ck_maintenance_record_impact_level'
    )
        EXEC(N'ALTER TABLE dbo.MaintenanceRecord WITH CHECK
              ADD CONSTRAINT ck_maintenance_record_impact_level
                  CHECK (impact_level IN (N''advisory'', N''out-of-service''));');

    /* These timestamps record the booking-level disclosure interaction. */
    IF COL_LENGTH(N'dbo.Booking', N'advisories_presented_at') IS NULL
        ALTER TABLE dbo.Booking ADD advisories_presented_at DATETIME2(0) NULL;

    IF COL_LENGTH(N'dbo.Booking', N'advisory_acknowledged_at') IS NULL
        ALTER TABLE dbo.Booking ADD advisory_acknowledged_at DATETIME2(0) NULL;

    IF NOT EXISTS
    (
        SELECT 1 FROM sys.check_constraints
        WHERE parent_object_id = OBJECT_ID(N'dbo.Booking')
          AND name = N'ck_booking_advisory_ack_time'
    )
        EXEC(N'ALTER TABLE dbo.Booking WITH CHECK
              ADD CONSTRAINT ck_booking_advisory_ack_time CHECK
              (
                  advisory_acknowledged_at IS NULL
                  OR (advisories_presented_at IS NOT NULL
                      AND advisory_acknowledged_at >= advisories_presented_at)
              );');

    IF COL_LENGTH(N'dbo.BookingPolicy', N'auto_approval_enabled') IS NULL
        ALTER TABLE dbo.BookingPolicy
            ADD auto_approval_enabled BIT NOT NULL
                CONSTRAINT df_booking_policy_auto_approval_enabled DEFAULT (0);

    /* One row is required for each advisory acknowledged for each booking. */
    IF OBJECT_ID(N'dbo.BookingMaintenanceAdvisoryAcknowledgement', N'U') IS NULL
    BEGIN
        CREATE TABLE dbo.BookingMaintenanceAdvisoryAcknowledgement
        (
            booking_id BIGINT NOT NULL,
            maintenance_id BIGINT NOT NULL,
            acknowledged_at DATETIME2(0) NOT NULL
                CONSTRAINT df_booking_maintenance_advisory_ack_at DEFAULT (SYSDATETIME()),
            advisory_summary_at_acknowledgement NVARCHAR(2000) NULL,
            CONSTRAINT pk_booking_maintenance_advisory_ack PRIMARY KEY (booking_id, maintenance_id),
            CONSTRAINT fk_booking_maintenance_advisory_ack_booking
                FOREIGN KEY (booking_id) REFERENCES dbo.Booking (booking_id)
                ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT fk_booking_maintenance_advisory_ack_maintenance
                FOREIGN KEY (maintenance_id) REFERENCES dbo.MaintenanceRecord (maintenance_id)
                ON DELETE NO ACTION ON UPDATE NO ACTION
        );
    END;

    /* Immutable audit trail for upgrades/downgrades of an active maintenance record. */
    IF OBJECT_ID(N'dbo.MaintenanceImpactHistory', N'U') IS NULL
    BEGIN
        CREATE TABLE dbo.MaintenanceImpactHistory
        (
            impact_history_id BIGINT IDENTITY(1, 1) NOT NULL,
            maintenance_id BIGINT NOT NULL,
            prior_impact_level NVARCHAR(20) NULL,
            new_impact_level NVARCHAR(20) NOT NULL,
            changed_by_user_id BIGINT NOT NULL,
            changed_at DATETIME2(0) NOT NULL
                CONSTRAINT df_maintenance_impact_history_changed_at DEFAULT (SYSDATETIME()),
            change_note NVARCHAR(1000) NOT NULL,
            CONSTRAINT pk_maintenance_impact_history PRIMARY KEY (impact_history_id),
            CONSTRAINT fk_maintenance_impact_history_maintenance
                FOREIGN KEY (maintenance_id) REFERENCES dbo.MaintenanceRecord (maintenance_id)
                ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT fk_maintenance_impact_history_changed_by
                FOREIGN KEY (changed_by_user_id) REFERENCES dbo.[User] (user_id)
                ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT ck_maintenance_impact_history_prior_level
                CHECK (prior_impact_level IS NULL OR prior_impact_level IN (N'advisory', N'out-of-service')),
            CONSTRAINT ck_maintenance_impact_history_new_level
                CHECK (new_impact_level IN (N'advisory', N'out-of-service'))
        );
    END;

    /* One idempotent staff-resolution record for each booking found during an escalation. */
    IF OBJECT_ID(N'dbo.MaintenanceBookingImpact', N'U') IS NULL
    BEGIN
        CREATE TABLE dbo.MaintenanceBookingImpact
        (
            maintenance_booking_impact_id BIGINT IDENTITY(1, 1) NOT NULL,
            maintenance_id BIGINT NOT NULL,
            booking_id BIGINT NOT NULL,
            identified_at DATETIME2(0) NOT NULL
                CONSTRAINT df_maintenance_booking_impact_identified_at DEFAULT (SYSDATETIME()),
            identified_by_user_id BIGINT NOT NULL,
            contact_status NVARCHAR(30) NOT NULL
                CONSTRAINT df_maintenance_booking_impact_contact_status DEFAULT N'PendingContact',
            contacted_at DATETIME2(0) NULL,
            resolved_at DATETIME2(0) NULL,
            resolved_by_user_id BIGINT NULL,
            resolution NVARCHAR(30) NULL,
            resolution_note NVARCHAR(1000) NULL,
            CONSTRAINT pk_maintenance_booking_impact PRIMARY KEY (maintenance_booking_impact_id),
            CONSTRAINT uq_maintenance_booking_impact_pair UNIQUE (maintenance_id, booking_id),
            CONSTRAINT fk_maintenance_booking_impact_maintenance
                FOREIGN KEY (maintenance_id) REFERENCES dbo.MaintenanceRecord (maintenance_id)
                ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT fk_maintenance_booking_impact_booking
                FOREIGN KEY (booking_id) REFERENCES dbo.Booking (booking_id)
                ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT fk_maintenance_booking_impact_identified_by
                FOREIGN KEY (identified_by_user_id) REFERENCES dbo.[User] (user_id)
                ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT fk_maintenance_booking_impact_resolved_by
                FOREIGN KEY (resolved_by_user_id) REFERENCES dbo.[User] (user_id)
                ON DELETE NO ACTION ON UPDATE NO ACTION,
            CONSTRAINT ck_maintenance_booking_impact_contact_status
                CHECK (contact_status IN (N'PendingContact', N'Contacted', N'Resolved')),
            CONSTRAINT ck_maintenance_booking_impact_resolution
                CHECK (resolution IS NULL OR resolution IN (N'Rescheduled', N'Relocated', N'Cancelled', N'AcceptedRisk')),
            CONSTRAINT ck_maintenance_booking_impact_resolution_audit CHECK
            (
                (resolution IS NULL AND resolved_at IS NULL AND resolved_by_user_id IS NULL)
                OR (resolution IS NOT NULL AND resolved_at IS NOT NULL AND resolved_by_user_id IS NOT NULL)
            )
        );
    END;

    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.MaintenanceRecord') AND name = N'ix_maintenance_space_impact_time')
        CREATE INDEX ix_maintenance_space_impact_time
            ON dbo.MaintenanceRecord (space_id, maintenance_status, impact_level, start_time, completion_time);

    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.MaintenanceBookingImpact') AND name = N'ix_maintenance_booking_impact_open')
        CREATE INDEX ix_maintenance_booking_impact_open
            ON dbo.MaintenanceBookingImpact (contact_status, maintenance_id, booking_id);

    /*
    Trigger deployment is intentionally deferred to the post-migration booking
    workflow deployment. SQL Server requires CREATE OR ALTER TRIGGER to begin
    its own batch, which is incompatible with this atomic migration batch.

    Enforce that a per-advisory acknowledgement references the booking's own current advisory.
    CREATE OR ALTER TRIGGER dbo.tr_booking_maintenance_advisory_ack_validate
    ON dbo.BookingMaintenanceAdvisoryAcknowledgement
    AFTER INSERT, UPDATE
    AS
    BEGIN
        SET NOCOUNT ON;

        IF EXISTS
        (
            SELECT 1
            FROM inserted AS a
            INNER JOIN dbo.Booking AS b ON b.booking_id = a.booking_id
            INNER JOIN dbo.MaintenanceRecord AS m ON m.maintenance_id = a.maintenance_id
            WHERE b.space_id <> m.space_id
               OR m.maintenance_status NOT IN (N'Reported', N'Assigned', N'InProgress')
               OR m.impact_level <> N'advisory'
               OR b.requested_start_time >= ISNULL(m.completion_time, CONVERT(DATETIME2(0), '9999-12-31 23:59:59'))
               OR b.requested_end_time <= m.start_time
        )
            THROW 51010, 'An acknowledgement must match an overlapping active advisory for the booking space.', 1;
    END;

    Existing booking integrity is preserved; only out-of-service maintenance blocks Phase 2 approval.
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
            THROW 51000, 'A booking requester must have an active account.', 1;

        IF EXISTS
        (
            SELECT 1
            FROM inserted AS i
            INNER JOIN dbo.Space AS s ON s.space_id = i.space_id
            WHERE (i.booking_status IN (N'Pending', N'Approved', N'CheckedIn')
                   AND s.current_status IN (N'UnderMaintenance', N'TemporarilyClosed', N'Retired'))
               OR i.expected_participants > s.capacity
        )
            THROW 51001, 'The space is unavailable or its capacity is insufficient.', 1;

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
            THROW 51002, 'An approved or checked-in booking overlaps this requested interval.', 1;

        IF EXISTS
        (
            SELECT 1
            FROM inserted AS i
            INNER JOIN dbo.MaintenanceRecord AS m WITH (UPDLOCK, HOLDLOCK)
                ON m.space_id = i.space_id
               AND m.maintenance_status IN (N'Reported', N'Assigned', N'InProgress')
               AND m.impact_level = N'out-of-service'
               AND i.booking_status IN (N'Approved', N'CheckedIn')
               AND i.requested_start_time < ISNULL(m.completion_time, CONVERT(DATETIME2(0), '9999-12-31 23:59:59'))
               AND i.requested_end_time > m.start_time
        )
            THROW 51003, 'An active out-of-service maintenance record blocks this booking interval.', 1;

        IF EXISTS
        (
            SELECT 1
            FROM inserted AS i
            INNER JOIN dbo.MaintenanceRecord AS m
                ON m.space_id = i.space_id
               AND m.maintenance_status IN (N'Reported', N'Assigned', N'InProgress')
               AND m.impact_level = N'advisory'
               AND i.booking_status IN (N'Approved', N'CheckedIn')
               AND i.requested_start_time < ISNULL(m.completion_time, CONVERT(DATETIME2(0), '9999-12-31 23:59:59'))
               AND i.requested_end_time > m.start_time
            LEFT JOIN dbo.BookingMaintenanceAdvisoryAcknowledgement AS a
                ON a.booking_id = i.booking_id
               AND a.maintenance_id = m.maintenance_id
            WHERE a.booking_id IS NULL
        )
            THROW 51011, 'Every overlapping active advisory must be acknowledged before approval.', 1;
    END;

    */

    EXEC sys.sp_executesql N'CREATE OR ALTER TRIGGER dbo.tr_booking_maintenance_advisory_ack_validate
    ON dbo.BookingMaintenanceAdvisoryAcknowledgement
    AFTER INSERT, UPDATE
    AS
    BEGIN
        SET NOCOUNT ON;
        IF EXISTS
        (
            SELECT 1
            FROM inserted AS a
            INNER JOIN dbo.Booking AS b ON b.booking_id = a.booking_id
            INNER JOIN dbo.MaintenanceRecord AS m ON m.maintenance_id = a.maintenance_id
            WHERE b.space_id <> m.space_id
               OR m.maintenance_status NOT IN (N''Reported'', N''Assigned'', N''InProgress'')
               OR m.impact_level <> N''advisory''
               OR b.requested_start_time >= ISNULL(m.completion_time, CONVERT(DATETIME2(0), ''9999-12-31 23:59:59''))
               OR b.requested_end_time <= m.start_time
        )
            THROW 51010, ''An acknowledgement must match an overlapping active advisory for the booking space.'', 1;
    END;';
    
    EXEC sys.sp_executesql N'CREATE OR ALTER TRIGGER dbo.tr_booking_validate
    ON dbo.Booking
    AFTER INSERT, UPDATE
    AS
    BEGIN
        SET NOCOUNT ON;
        IF EXISTS
        (
            SELECT 1 FROM inserted AS i
            INNER JOIN dbo.[User] AS u ON u.user_id = i.requester_user_id
            WHERE u.account_status <> N''Active''
        )
            THROW 51000, ''A booking requester must have an active account.'', 1;
        IF EXISTS
        (
            SELECT 1 FROM inserted AS i
            INNER JOIN dbo.Space AS s ON s.space_id = i.space_id
            WHERE (i.booking_status IN (N''Pending'', N''Approved'', N''CheckedIn'')
                   AND s.current_status IN (N''UnderMaintenance'', N''TemporarilyClosed'', N''Retired''))
               OR i.expected_participants > s.capacity
        )
            THROW 51001, ''The space is unavailable or its capacity is insufficient.'', 1;
        IF EXISTS
        (
            SELECT 1 FROM inserted AS i
            INNER JOIN dbo.Booking AS b WITH (UPDLOCK, HOLDLOCK)
                ON b.space_id = i.space_id
               AND b.booking_id <> i.booking_id
               AND b.booking_status IN (N''Approved'', N''CheckedIn'')
               AND i.booking_status IN (N''Approved'', N''CheckedIn'')
               AND i.requested_start_time < b.requested_end_time
               AND i.requested_end_time > b.requested_start_time
        )
            THROW 51002, ''An approved or checked-in booking overlaps this requested interval.'', 1;
        IF EXISTS
        (
            SELECT 1 FROM inserted AS i
            INNER JOIN dbo.MaintenanceRecord AS m WITH (UPDLOCK, HOLDLOCK)
                ON m.space_id = i.space_id
               AND m.maintenance_status IN (N''Reported'', N''Assigned'', N''InProgress'')
               AND m.impact_level = N''out-of-service''
               AND i.booking_status IN (N''Approved'', N''CheckedIn'')
               AND i.requested_start_time < ISNULL(m.completion_time, CONVERT(DATETIME2(0), ''9999-12-31 23:59:59''))
               AND i.requested_end_time > m.start_time
        )
            THROW 51003, ''An active out-of-service maintenance record blocks this booking interval.'', 1;
        IF EXISTS
        (
            SELECT 1 FROM inserted AS i
            INNER JOIN dbo.MaintenanceRecord AS m
                ON m.space_id = i.space_id
               AND m.maintenance_status IN (N''Reported'', N''Assigned'', N''InProgress'')
               AND m.impact_level = N''advisory''
               AND i.booking_status IN (N''Approved'', N''CheckedIn'')
               AND i.requested_start_time < ISNULL(m.completion_time, CONVERT(DATETIME2(0), ''9999-12-31 23:59:59''))
               AND i.requested_end_time > m.start_time
            LEFT JOIN dbo.BookingMaintenanceAdvisoryAcknowledgement AS a
                ON a.booking_id = i.booking_id AND a.maintenance_id = m.maintenance_id
            WHERE a.booking_id IS NULL
        )
            THROW 51011, ''Every overlapping active advisory must be acknowledged before approval.'', 1;
    END;';

    /* Deployable comments document the Phase 2 rules in the database catalog. */
    IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE major_id = OBJECT_ID(N'dbo.MaintenanceRecord') AND minor_id = 0 AND name = N'MS_Description')
        EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'Maintenance history; its impact level controls interval availability.', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'MaintenanceRecord';
    IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE major_id = OBJECT_ID(N'dbo.MaintenanceRecord') AND minor_id = COLUMNPROPERTY(OBJECT_ID(N'dbo.MaintenanceRecord'), N'impact_level', 'ColumnId') AND name = N'MS_Description')
        EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'advisory requires acknowledgement; out-of-service blocks an overlapping approval.', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'MaintenanceRecord', @level2type = N'COLUMN', @level2name = N'impact_level';
    IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE major_id = OBJECT_ID(N'dbo.BookingMaintenanceAdvisoryAcknowledgement') AND minor_id = 0 AND name = N'MS_Description')
        EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'Per-booking, per-advisory acknowledgement evidence.', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'BookingMaintenanceAdvisoryAcknowledgement';
    IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE major_id = OBJECT_ID(N'dbo.MaintenanceImpactHistory') AND minor_id = 0 AND name = N'MS_Description')
        EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'Immutable audit of maintenance impact-level changes.', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'MaintenanceImpactHistory';
    IF NOT EXISTS (SELECT 1 FROM sys.extended_properties WHERE major_id = OBJECT_ID(N'dbo.MaintenanceBookingImpact') AND minor_id = 0 AND name = N'MS_Description')
        EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'Staff follow-up record for booking disruption caused by escalation.', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'MaintenanceBookingImpact';

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
