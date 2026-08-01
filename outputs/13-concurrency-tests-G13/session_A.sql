/*
    Start this session first. It deliberately keeps the per-space test lock for
    ten seconds after approving booking A, so Session B visibly waits.
*/
SET NOCOUNT ON;
DECLARE @space_id BIGINT;
DECLARE @booking_id BIGINT;
DECLARE @approver_id BIGINT;
DECLARE @lock_result INT;
DECLARE @lock_resource NVARCHAR(255);

SELECT
    @space_id = space_id,
    @booking_id = session_a_booking_id,
    @approver_id = approver_user_id
FROM dbo.ConcurrencyTestRunG13
WHERE test_name = N'G13 locking test';

BEGIN TRANSACTION;

SET @lock_resource = N'CSMS:Space:' + CONVERT(NVARCHAR(30), @space_id);

EXEC @lock_result = sys.sp_getapplock
    @Resource = @lock_resource,
    @LockMode = N'Exclusive',
    @LockOwner = N'Transaction',
    @LockTimeout = 10000;

IF @lock_result < 0
    THROW 51101, 'Session A could not obtain the test space lock.', 1;

EXEC dbo.usp_ApproveBooking
    @booking_id = @booking_id,
    @decision_maker_user_id = @approver_id;

PRINT N'Session A approved booking A and holds the space lock for 10 seconds.';
WAITFOR DELAY '00:00:10';

COMMIT TRANSACTION;
PRINT N'Session A committed.';
