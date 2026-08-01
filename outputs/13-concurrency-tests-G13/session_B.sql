/*
    Start this while Session A is waiting. This call waits on A's application
    lock, then must fail with SQL Server error 51041 after A commits.
*/
SET NOCOUNT ON;
DECLARE @booking_id BIGINT;
DECLARE @approver_id BIGINT;

SELECT
    @booking_id = session_b_booking_id,
    @approver_id = approver_user_id
FROM dbo.ConcurrencyTestRunG13
WHERE test_name = N'G13 locking test';

EXEC dbo.usp_ApproveBooking
    @booking_id = @booking_id,
    @decision_maker_user_id = @approver_id;

