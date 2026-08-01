/*
    First approval must fail with 51043. Continue after that expected error, then
    execute the acknowledgement and escalation portions separately if using sqlcmd -b.
*/
DECLARE @booking_id BIGINT;
DECLARE @maintenance_id BIGINT;
DECLARE @approver_id BIGINT;

SELECT
    @booking_id = advisory_booking_id,
    @maintenance_id = advisory_maintenance_id,
    @approver_id = approver_user_id
FROM dbo.ConcurrencyTestRunG13
WHERE test_name = N'G13 locking test';

PRINT N'Expected error 51043 follows:';
BEGIN TRY
    EXEC dbo.usp_ApproveBooking
        @booking_id = @booking_id,
        @decision_maker_user_id = @approver_id,
        @acknowledge_current_advisories = 0;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS expected_error_number, ERROR_MESSAGE() AS expected_error_message;
END CATCH;

EXEC dbo.usp_ApproveBooking
    @booking_id = @booking_id,
    @decision_maker_user_id = @approver_id,
    @acknowledge_current_advisories = 1;

EXEC dbo.usp_SetMaintenanceImpactLevel
    @maintenance_id = @maintenance_id,
    @new_impact_level = N'out-of-service',
    @changed_by_user_id = @approver_id,
    @change_note = N'Concurrency-test escalation after advisory acknowledgement.';

SELECT COUNT(*) AS advisory_acknowledgement_count
FROM dbo.BookingMaintenanceAdvisoryAcknowledgement
WHERE booking_id = @booking_id
  AND maintenance_id = @maintenance_id;

SELECT
    mbi.maintenance_id,
    mbi.booking_id,
    mbi.contact_status,
    m.impact_level
FROM dbo.MaintenanceBookingImpact AS mbi
INNER JOIN dbo.MaintenanceRecord AS m ON m.maintenance_id = mbi.maintenance_id
WHERE mbi.maintenance_id = @maintenance_id
  AND mbi.booking_id = @booking_id;

