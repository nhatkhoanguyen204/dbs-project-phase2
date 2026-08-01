/*
    Correct result: one Approved booking and no Approved/CheckedIn overlap pair.
*/
DECLARE @space_id BIGINT;

SELECT @space_id = space_id
FROM dbo.ConcurrencyTestRunG13
WHERE test_name = N'G13 locking test';

SELECT
    b.booking_id,
    b.booking_status,
    b.requested_start_time,
    b.requested_end_time
FROM dbo.Booking AS b
WHERE b.space_id = @space_id
  AND b.requested_start_time >= '2030-01-15'
  AND b.requested_start_time < '2030-01-16'
ORDER BY b.booking_id;

SELECT COUNT(*) AS approved_booking_count
FROM dbo.Booking AS b
WHERE b.space_id = @space_id
  AND b.booking_status = N'Approved'
  AND b.requested_start_time >= '2030-01-15'
  AND b.requested_start_time < '2030-01-16';

SELECT
    first_booking.booking_id AS first_booking_id,
    second_booking.booking_id AS second_booking_id
FROM dbo.Booking AS first_booking
INNER JOIN dbo.Booking AS second_booking
    ON second_booking.space_id = first_booking.space_id
   AND second_booking.booking_id > first_booking.booking_id
   AND second_booking.booking_status IN (N'Approved', N'CheckedIn')
   AND first_booking.requested_start_time < second_booking.requested_end_time
   AND first_booking.requested_end_time > second_booking.requested_start_time
WHERE first_booking.space_id = @space_id
  AND first_booking.booking_status IN (N'Approved', N'CheckedIn');

