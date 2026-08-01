/*
    WARNING: run only in the disposable test database after 00_setup.sql.
    This intentionally bypasses the booking validation trigger to show the invalid
    state possible with uncoordinated check-then-update logic. It always rolls back.
*/
DECLARE @booking_a BIGINT;
DECLARE @booking_b BIGINT;

SELECT
    @booking_a = session_a_booking_id,
    @booking_b = session_b_booking_id
FROM dbo.ConcurrencyTestRunG13
WHERE test_name = N'G13 locking test';

BEGIN TRY
    BEGIN TRANSACTION;
    DISABLE TRIGGER dbo.tr_booking_validate ON dbo.Booking;

    UPDATE dbo.Booking SET booking_status = N'Approved' WHERE booking_id IN (@booking_a, @booking_b);

    SELECT
        first_booking.booking_id AS first_booking_id,
        second_booking.booking_id AS second_booking_id,
        N'Invalid double-booking state demonstrated; transaction will roll back.' AS result
    FROM dbo.Booking AS first_booking
    INNER JOIN dbo.Booking AS second_booking
        ON second_booking.space_id = first_booking.space_id
       AND second_booking.booking_id > first_booking.booking_id
       AND second_booking.booking_status = N'Approved'
       AND first_booking.requested_start_time < second_booking.requested_end_time
       AND first_booking.requested_end_time > second_booking.requested_start_time
    WHERE first_booking.booking_id = @booking_a
      AND first_booking.booking_status = N'Approved';

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

