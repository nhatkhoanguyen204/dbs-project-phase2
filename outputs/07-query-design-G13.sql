/*
    CSMS Phase 2 - operational and analytical query suite
    Each query is read-only and may be run independently in SQL Server.
*/

/*
    Query 01: Upcoming approved and active bookings
    Target user: Facility Staff
    Utility: Shows the next operational commitments and their requester/contact details.
    Expected insight: Identifies spaces that must be prepared for the next seven days.
*/
DECLARE @as_of_01 DATETIME2(0) = SYSDATETIME();

SELECT
    s.space_code,
    s.space_name,
    b.requested_start_time,
    b.requested_end_time,
    b.purpose,
    b.expected_participants,
    b.booking_status,
    u.full_name AS requester_name,
    u.email AS requester_email
FROM dbo.Booking AS b
INNER JOIN dbo.Space AS s ON s.space_id = b.space_id
INNER JOIN dbo.[User] AS u ON u.user_id = b.requester_user_id
WHERE b.booking_status IN (N'Approved', N'CheckedIn')
  AND b.requested_end_time >= @as_of_01
  AND b.requested_start_time < DATEADD(DAY, 7, @as_of_01)
ORDER BY b.requested_start_time, s.space_code;
GO

/*
    Query 02: Availability search for a requested interval
    Target user: Students, Lecturers, and booking portal
    Utility: Returns spaces that are operationally available for the supplied interval and capacity.
    Expected insight: Excludes unavailable spaces and active booking/maintenance blocks.
*/
DECLARE @requested_start_02 DATETIME2(0) = '2026-08-10 09:00:00';
DECLARE @requested_end_02 DATETIME2(0) = '2026-08-10 11:00:00';
DECLARE @participants_02 INT = 20;

WITH ActiveBookingBlocks AS
(
    SELECT space_id, requested_start_time, requested_end_time
    FROM dbo.Booking
    WHERE booking_status IN (N'Approved', N'CheckedIn')
),
ActiveMaintenanceBlocks AS
(
    SELECT
        space_id,
        start_time,
        ISNULL(completion_time, CONVERT(DATETIME2(0), '9999-12-31 23:59:59')) AS end_time
    FROM dbo.MaintenanceRecord
    WHERE maintenance_status IN (N'Reported', N'Assigned', N'InProgress')
)
SELECT
    s.space_code,
    s.space_name,
    s.space_type,
    s.capacity,
    s.building,
    s.floor,
    s.room_number
FROM dbo.Space AS s
WHERE s.current_status IN (N'Available', N'InUse')
  AND s.capacity >= @participants_02
  AND NOT EXISTS
  (
      SELECT 1
      FROM ActiveBookingBlocks AS b
      WHERE b.space_id = s.space_id
        AND @requested_start_02 < b.requested_end_time
        AND @requested_end_02 > b.requested_start_time
  )
  AND NOT EXISTS
  (
      SELECT 1
      FROM ActiveMaintenanceBlocks AS m
      WHERE m.space_id = s.space_id
        AND @requested_start_02 < m.end_time
        AND @requested_end_02 > m.start_time
  )
ORDER BY s.capacity, s.space_code;
GO

/*
    Query 03: Scheduled utilization by space for the prior 90 days
    Target user: Facility Manager
    Utility: Compares completed and no-show booking hours with a fixed reporting window.
    Expected insight: Highlights underused spaces and lost capacity from no-shows.
*/
DECLARE @window_end_03 DATETIME2(0) = SYSDATETIME();
DECLARE @window_start_03 DATETIME2(0) = DATEADD(DAY, -90, @window_end_03);

WITH BookingHours AS
(
    SELECT
        b.space_id,
        b.booking_status,
        CAST(DATEDIFF(MINUTE, b.requested_start_time, b.requested_end_time) / 60.0 AS DECIMAL(10, 2)) AS scheduled_hours
    FROM dbo.Booking AS b
    WHERE b.requested_start_time >= @window_start_03
      AND b.requested_start_time < @window_end_03
      AND b.booking_status IN (N'Completed', N'NoShow')
)
SELECT
    s.space_code,
    s.space_name,
    COALESCE(SUM(CASE WHEN bh.booking_status = N'Completed' THEN bh.scheduled_hours END), 0) AS completed_hours,
    COALESCE(SUM(CASE WHEN bh.booking_status = N'NoShow' THEN bh.scheduled_hours END), 0) AS no_show_hours,
    CAST(COALESCE(SUM(bh.scheduled_hours), 0) / (90.0 * 12.0) * 100 AS DECIMAL(5, 2)) AS scheduled_utilization_pct
FROM dbo.Space AS s
LEFT JOIN BookingHours AS bh ON bh.space_id = s.space_id
GROUP BY s.space_code, s.space_name
ORDER BY scheduled_utilization_pct DESC, s.space_code;
GO

/*
    Query 04: Peak booking start hours
    Target user: Facility Manager and timetable planners
    Utility: Counts approved/checked-in/completed booking starts by weekday and hour.
    Expected insight: Reveals demand peaks for staffing and cleaning schedules.
*/
WITH Starts AS
(
    SELECT
        DATENAME(WEEKDAY, requested_start_time) AS weekday_name,
        DATEPART(WEEKDAY, requested_start_time) AS weekday_number,
        DATEPART(HOUR, requested_start_time) AS start_hour,
        COUNT(*) AS booking_count
    FROM dbo.Booking
    WHERE booking_status IN (N'Approved', N'CheckedIn', N'Completed')
    GROUP BY
        DATENAME(WEEKDAY, requested_start_time),
        DATEPART(WEEKDAY, requested_start_time),
        DATEPART(HOUR, requested_start_time)
)
SELECT
    weekday_name,
    start_hour,
    booking_count,
    RANK() OVER (ORDER BY booking_count DESC) AS overall_peak_rank
FROM Starts
ORDER BY overall_peak_rank, weekday_number, start_hour;
GO

/*
    Query 05: Capacity-weighted demand ranking
    Target user: Facility Manager
    Utility: Ranks spaces by booked participants relative to their capacity.
    Expected insight: Indicates where demand consistently approaches space capacity.
*/
WITH SpaceDemand AS
(
    SELECT
        s.space_id,
        s.space_code,
        s.space_name,
        s.capacity,
        COUNT(b.booking_id) AS active_or_completed_bookings,
        COALESCE(SUM(b.expected_participants), 0) AS booked_participants
    FROM dbo.Space AS s
    LEFT JOIN dbo.Booking AS b
        ON b.space_id = s.space_id
       AND b.booking_status IN (N'Approved', N'CheckedIn', N'Completed')
    GROUP BY s.space_id, s.space_code, s.space_name, s.capacity
)
SELECT
    space_code,
    space_name,
    capacity,
    active_or_completed_bookings,
    booked_participants,
    CAST(booked_participants * 1.0 / NULLIF(capacity * NULLIF(active_or_completed_bookings, 0), 0) * 100 AS DECIMAL(5, 2)) AS average_capacity_fill_pct,
    RANK() OVER (ORDER BY booked_participants * 1.0 / NULLIF(capacity * NULLIF(active_or_completed_bookings, 0), 0) DESC) AS demand_rank
FROM SpaceDemand
ORDER BY demand_rank, space_code;
GO

/*
    Query 06: Planned versus actual session duration variance
    Target user: Facility Staff
    Utility: Compares recorded session duration to the booked duration.
    Expected insight: Finds late check-outs and sessions with significant timing variance.
*/
SELECT
    b.booking_id,
    s.space_code,
    u.full_name AS requester_name,
    b.requested_start_time,
    b.requested_end_time,
    us.actual_start_time,
    us.actual_end_time,
    DATEDIFF(MINUTE, b.requested_start_time, b.requested_end_time) AS planned_minutes,
    DATEDIFF(MINUTE, us.actual_start_time, us.actual_end_time) AS actual_minutes,
    DATEDIFF(MINUTE, b.requested_end_time, us.actual_end_time) AS checkout_variance_minutes
FROM dbo.UsageSession AS us
INNER JOIN dbo.Booking AS b ON b.booking_id = us.booking_id
INNER JOIN dbo.Space AS s ON s.space_id = b.space_id
INNER JOIN dbo.[User] AS u ON u.user_id = b.requester_user_id
WHERE us.actual_end_time IS NOT NULL
ORDER BY checkout_variance_minutes DESC, b.booking_id;
GO

/*
    Query 07: Data-quality scan for overlapping active bookings
    Target user: Database Administrator
    Utility: Detects any integrity breach among approved or checked-in bookings.
    Expected insight: A correct database returns no rows; rows require immediate remediation.
*/
SELECT
    s.space_code,
    first_booking.booking_id AS first_booking_id,
    second_booking.booking_id AS second_booking_id,
    first_booking.requested_start_time AS first_start,
    first_booking.requested_end_time AS first_end,
    second_booking.requested_start_time AS second_start,
    second_booking.requested_end_time AS second_end
FROM dbo.Booking AS first_booking
INNER JOIN dbo.Booking AS second_booking
    ON second_booking.space_id = first_booking.space_id
   AND second_booking.booking_id > first_booking.booking_id
   AND second_booking.booking_status IN (N'Approved', N'CheckedIn')
   AND first_booking.requested_start_time < second_booking.requested_end_time
   AND first_booking.requested_end_time > second_booking.requested_start_time
INNER JOIN dbo.Space AS s ON s.space_id = first_booking.space_id
WHERE first_booking.booking_status IN (N'Approved', N'CheckedIn')
ORDER BY s.space_code, first_booking.requested_start_time;
GO

/*
    Query 08: Data-quality scan for active booking/maintenance conflicts
    Target user: Facility Manager
    Utility: Finds active reservations that overlap an active maintenance record.
    Expected insight: A correct approval workflow returns no rows; any row needs resolution.
*/
SELECT
    s.space_code,
    b.booking_id,
    b.requested_start_time,
    b.requested_end_time,
    m.maintenance_id,
    m.problem_description,
    m.start_time AS maintenance_start,
    m.completion_time AS maintenance_end
FROM dbo.Booking AS b
INNER JOIN dbo.MaintenanceRecord AS m
    ON m.space_id = b.space_id
   AND b.requested_start_time < ISNULL(m.completion_time, CONVERT(DATETIME2(0), '9999-12-31 23:59:59'))
   AND b.requested_end_time > m.start_time
INNER JOIN dbo.Space AS s ON s.space_id = b.space_id
WHERE b.booking_status IN (N'Approved', N'CheckedIn')
  AND m.maintenance_status IN (N'Reported', N'Assigned', N'InProgress')
ORDER BY s.space_code, b.requested_start_time;
GO

/*
    Query 09: Current unavailable spaces and maintenance responsibility
    Target user: Facility Staff
    Utility: Lists closed/maintenance spaces with open maintenance details and assignees.
    Expected insight: Provides an operational repair queue and highlights unassigned incidents.
*/
SELECT
    s.space_code,
    s.space_name,
    s.current_status,
    m.maintenance_id,
    m.maintenance_status,
    m.start_time,
    m.problem_description,
    COALESCE(assignee.full_name, N'Unassigned') AS assigned_staff,
    DATEDIFF(HOUR, m.start_time, SYSDATETIME()) AS open_hours
FROM dbo.Space AS s
LEFT JOIN dbo.MaintenanceRecord AS m
    ON m.space_id = s.space_id
   AND m.maintenance_status IN (N'Reported', N'Assigned', N'InProgress')
LEFT JOIN dbo.[User] AS assignee ON assignee.user_id = m.assigned_staff_user_id
WHERE s.current_status IN (N'UnderMaintenance', N'TemporarilyClosed', N'Retired')
   OR m.maintenance_id IS NOT NULL
ORDER BY open_hours DESC, s.space_code;
GO

/*
    Query 10: Inter-booking gaps using LAG
    Target user: Facility Manager
    Utility: Calculates time between consecutive active/historical usable bookings per space.
    Expected insight: Identifies turnover windows too short for realistic cleaning or setup.
*/
WITH OrderedBookings AS
(
    SELECT
        s.space_code,
        b.booking_id,
        b.requested_start_time,
        b.requested_end_time,
        LAG(b.requested_end_time) OVER
        (
            PARTITION BY b.space_id
            ORDER BY b.requested_start_time, b.booking_id
        ) AS previous_end_time
    FROM dbo.Booking AS b
    INNER JOIN dbo.Space AS s ON s.space_id = b.space_id
    WHERE b.booking_status IN (N'Approved', N'CheckedIn', N'Completed', N'NoShow')
)
SELECT
    space_code,
    booking_id,
    previous_end_time,
    requested_start_time,
    DATEDIFF(MINUTE, previous_end_time, requested_start_time) AS gap_minutes
FROM OrderedBookings
WHERE previous_end_time IS NOT NULL
ORDER BY gap_minutes, space_code, requested_start_time;
GO

/*
    Query 11: Booking behavior by requester role
    Target user: Department Administrator
    Utility: Summarizes booking volume and outcomes for each university role.
    Expected insight: Shows which roles consume capacity and experience rejection/no-show risk.
*/
SELECT
    u.role,
    COUNT(*) AS total_bookings,
    SUM(CASE WHEN b.booking_status = N'Approved' THEN 1 ELSE 0 END) AS approved_bookings,
    SUM(CASE WHEN b.booking_status = N'Rejected' THEN 1 ELSE 0 END) AS rejected_bookings,
    SUM(CASE WHEN b.booking_status = N'Cancelled' THEN 1 ELSE 0 END) AS cancelled_bookings,
    SUM(CASE WHEN b.booking_status = N'NoShow' THEN 1 ELSE 0 END) AS no_show_bookings
FROM dbo.Booking AS b
INNER JOIN dbo.[User] AS u ON u.user_id = b.requester_user_id
GROUP BY u.role
ORDER BY total_bookings DESC, u.role;
GO

/*
    Query 12: Requester reliability score
    Target user: Facility Manager
    Utility: Calculates cancellation and no-show rates per requester with a minimum booking count.
    Expected insight: Supports policy review for repeat no-shows without hiding low-volume users.
*/
WITH RequesterMetrics AS
(
    SELECT
        u.user_id,
        u.full_name,
        u.email,
        COUNT(*) AS total_bookings,
        SUM(CASE WHEN b.booking_status = N'Cancelled' THEN 1 ELSE 0 END) AS cancelled_bookings,
        SUM(CASE WHEN b.booking_status = N'NoShow' THEN 1 ELSE 0 END) AS no_show_bookings
    FROM dbo.[User] AS u
    INNER JOIN dbo.Booking AS b ON b.requester_user_id = u.user_id
    GROUP BY u.user_id, u.full_name, u.email
)
SELECT
    full_name,
    email,
    total_bookings,
    cancelled_bookings,
    no_show_bookings,
    CAST((cancelled_bookings + no_show_bookings) * 100.0 / total_bookings AS DECIMAL(5, 2)) AS non_use_rate_pct,
    RANK() OVER (ORDER BY (cancelled_bookings + no_show_bookings) * 1.0 / total_bookings DESC) AS non_use_risk_rank
FROM RequesterMetrics
WHERE total_bookings >= 1
ORDER BY non_use_risk_rank, full_name;
GO

/*
    Query 13: Approval and rejection turnaround
    Target user: Facility Manager
    Utility: Measures time from request submission to the first recorded decision.
    Expected insight: Identifies workflow delays by decision type and decision maker.
*/
WITH FirstDecision AS
(
    SELECT
        bd.booking_id,
        bd.decision_maker_user_id,
        bd.decision_time,
        bd.decision,
        ROW_NUMBER() OVER (PARTITION BY bd.booking_id ORDER BY bd.decision_time, bd.decision_id) AS sequence_number
    FROM dbo.BookingDecision AS bd
)
SELECT
    fd.decision,
    decision_maker.full_name AS decision_maker,
    COUNT(*) AS decisions,
    CAST(AVG(CAST(DATEDIFF(MINUTE, b.submitted_at, fd.decision_time) AS DECIMAL(12, 2))) / 60.0 AS DECIMAL(10, 2)) AS average_turnaround_hours,
    MAX(DATEDIFF(HOUR, b.submitted_at, fd.decision_time)) AS longest_turnaround_hours
FROM FirstDecision AS fd
INNER JOIN dbo.Booking AS b ON b.booking_id = fd.booking_id
INNER JOIN dbo.[User] AS decision_maker ON decision_maker.user_id = fd.decision_maker_user_id
WHERE fd.sequence_number = 1
GROUP BY fd.decision, decision_maker.full_name
ORDER BY average_turnaround_hours DESC, decision_maker;
GO

/*
    Query 14: Decision workload by facility personnel
    Target user: Facility Manager
    Utility: Ranks staff and managers by approval/rejection workload per calendar month.
    Expected insight: Exposes uneven decision distribution and potential approval bottlenecks.
*/
WITH MonthlyWorkload AS
(
    SELECT
        u.full_name,
        DATEFROMPARTS(YEAR(bd.decision_time), MONTH(bd.decision_time), 1) AS decision_month,
        COUNT(*) AS decision_count
    FROM dbo.BookingDecision AS bd
    INNER JOIN dbo.[User] AS u ON u.user_id = bd.decision_maker_user_id
    GROUP BY u.full_name, DATEFROMPARTS(YEAR(bd.decision_time), MONTH(bd.decision_time), 1)
)
SELECT
    full_name,
    decision_month,
    decision_count,
    RANK() OVER (PARTITION BY decision_month ORDER BY decision_count DESC) AS monthly_workload_rank
FROM MonthlyWorkload
ORDER BY decision_month, monthly_workload_rank, full_name;
GO

/*
    Query 15: Maintenance turnaround and downtime
    Target user: Facility Manager
    Utility: Measures completed repair duration and age of still-open incidents.
    Expected insight: Highlights slow repairs and backlog requiring escalation.
*/
SELECT
    s.space_code,
    m.maintenance_id,
    m.maintenance_status,
    m.problem_description,
    m.start_time,
    m.completion_time,
    CASE
        WHEN m.completion_time IS NOT NULL THEN DATEDIFF(HOUR, m.start_time, m.completion_time)
        ELSE DATEDIFF(HOUR, m.start_time, SYSDATETIME())
    END AS elapsed_hours,
    CASE
        WHEN m.completion_time IS NULL THEN N'Open'
        ELSE N'Completed'
    END AS turnaround_state
FROM dbo.MaintenanceRecord AS m
INNER JOIN dbo.Space AS s ON s.space_id = m.space_id
ORDER BY elapsed_hours DESC, s.space_code;
GO

/*
    Query 16: Facility inventory and supported booking demand
    Target user: Facility Manager
    Utility: Lists equipment quantities by space together with count of bookings using that space.
    Expected insight: Helps prioritize maintenance or expansion of heavily used equipped spaces.
*/
WITH BookingDemand AS
(
    SELECT space_id, COUNT(*) AS booking_count
    FROM dbo.Booking
    WHERE booking_status IN (N'Approved', N'CheckedIn', N'Completed')
    GROUP BY space_id
)
SELECT
    s.space_code,
    f.facility_name,
    f.facility_type,
    sf.quantity,
    COALESCE(bd.booking_count, 0) AS supported_booking_count,
    RANK() OVER (PARTITION BY f.facility_type ORDER BY COALESCE(bd.booking_count, 0) DESC, s.space_code) AS facility_demand_rank
FROM dbo.SpaceFacility AS sf
INNER JOIN dbo.Space AS s ON s.space_id = sf.space_id
INNER JOIN dbo.Facility AS f ON f.facility_id = sf.facility_id
LEFT JOIN BookingDemand AS bd ON bd.space_id = s.space_id
ORDER BY f.facility_type, facility_demand_rank, s.space_code;
GO

/*
    Query 17: Sessions still checked in
    Target user: Facility Staff
    Utility: Finds usage sessions without a recorded check-out and calculates their elapsed duration.
    Expected insight: Produces a live follow-up list for rooms that may need inspection.
*/
SELECT
    s.space_code,
    b.booking_id,
    u.full_name AS requester_name,
    us.actual_start_time,
    DATEDIFF(MINUTE, us.actual_start_time, SYSDATETIME()) AS open_session_minutes,
    check_in_staff.full_name AS checked_in_by,
    us.initial_condition,
    us.usage_notes
FROM dbo.UsageSession AS us
INNER JOIN dbo.Booking AS b ON b.booking_id = us.booking_id
INNER JOIN dbo.Space AS s ON s.space_id = b.space_id
INNER JOIN dbo.[User] AS u ON u.user_id = b.requester_user_id
INNER JOIN dbo.[User] AS check_in_staff ON check_in_staff.user_id = us.check_in_by_user_id
WHERE us.actual_end_time IS NULL
ORDER BY open_session_minutes DESC, s.space_code;
GO

/*
    Query 18: Capacity-fit exceptions and spare-seat analysis
    Target user: Department Administrator
    Utility: Shows participant load relative to capacity for all non-terminal booking requests.
    Expected insight: Identifies near-capacity sessions and unusually oversized room allocations.
*/
SELECT
    b.booking_id,
    s.space_code,
    b.purpose,
    b.booking_status,
    b.expected_participants,
    s.capacity,
    s.capacity - b.expected_participants AS spare_seats,
    CAST(b.expected_participants * 100.0 / s.capacity AS DECIMAL(5, 2)) AS capacity_fill_pct,
    CASE
        WHEN b.expected_participants * 1.0 / s.capacity >= 0.90 THEN N'Near capacity'
        WHEN b.expected_participants * 1.0 / s.capacity <= 0.30 THEN N'Potentially oversized'
        ELSE N'Appropriate fit'
    END AS fit_assessment
FROM dbo.Booking AS b
INNER JOIN dbo.Space AS s ON s.space_id = b.space_id
WHERE b.booking_status IN (N'Pending', N'Approved', N'CheckedIn')
ORDER BY capacity_fill_pct DESC, b.requested_start_time;
GO

/*
    Query 19: Effective policy selected for each pending request
    Target user: Booking portal and Facility Staff
    Utility: Resolves the most specific available policy (space, role, and purpose) for a pending booking.
    Expected insight: Makes lead-time and buffer policy application auditable before approval.
*/
SELECT
    b.booking_id,
    requester.full_name AS requester_name,
    requester.role AS requester_role,
    s.space_code,
    b.purpose,
    b.requested_start_time,
    policy.policy_id,
    policy.minimum_lead_minutes,
    policy.cancellation_lead_minutes,
    policy.pre_buffer_minutes,
    policy.post_buffer_minutes,
    DATEADD(MINUTE, -policy.pre_buffer_minutes, b.requested_start_time) AS effective_start_time,
    DATEADD(MINUTE, policy.post_buffer_minutes, b.requested_end_time) AS effective_end_time
FROM dbo.Booking AS b
INNER JOIN dbo.[User] AS requester ON requester.user_id = b.requester_user_id
INNER JOIN dbo.Space AS s ON s.space_id = b.space_id
OUTER APPLY
(
    SELECT TOP (1) bp.*
    FROM dbo.BookingPolicy AS bp
    WHERE (bp.space_id = b.space_id OR bp.space_id IS NULL)
      AND (bp.applicable_role = requester.role OR bp.applicable_role IS NULL)
      AND (bp.applicable_purpose = b.purpose OR bp.applicable_purpose IS NULL)
    ORDER BY
        CASE WHEN bp.space_id = b.space_id THEN 1 ELSE 0 END DESC,
        CASE WHEN bp.applicable_role = requester.role THEN 1 ELSE 0 END DESC,
        CASE WHEN bp.applicable_purpose = b.purpose THEN 1 ELSE 0 END DESC,
        bp.policy_id DESC
) AS policy
WHERE b.booking_status = N'Pending'
ORDER BY b.requested_start_time, b.booking_id;
GO

/*
    Query 20: Unified booking audit timeline
    Target user: Facility Manager and auditors
    Utility: Combines submission, decisions, cancellation, check-in, and check-out into chronological events.
    Expected insight: Provides an explainable lifecycle history for each booking and highlights long gaps.
*/
WITH AuditEvents AS
(
    SELECT
        b.booking_id,
        b.submitted_at AS event_time,
        N'Submitted' AS event_type,
        requester.full_name AS actor_name,
        CAST(CONCAT(N'Purpose: ', b.purpose, N'; expected participants: ', b.expected_participants) AS NVARCHAR(1000)) AS event_detail
    FROM dbo.Booking AS b
    INNER JOIN dbo.[User] AS requester ON requester.user_id = b.requester_user_id

    UNION ALL

    SELECT
        bd.booking_id,
        bd.decision_time,
        bd.decision,
        decision_maker.full_name,
        COALESCE(bd.rejection_reason, bd.decision_note)
    FROM dbo.BookingDecision AS bd
    INNER JOIN dbo.[User] AS decision_maker ON decision_maker.user_id = bd.decision_maker_user_id

    UNION ALL

    SELECT
        b.booking_id,
        b.cancelled_at,
        N'Cancelled',
        cancelled_by.full_name,
        b.cancellation_note
    FROM dbo.Booking AS b
    INNER JOIN dbo.[User] AS cancelled_by ON cancelled_by.user_id = b.cancelled_by_user_id
    WHERE b.cancelled_at IS NOT NULL

    UNION ALL

    SELECT
        us.booking_id,
        us.actual_start_time,
        N'CheckedIn',
        check_in_staff.full_name,
        us.initial_condition
    FROM dbo.UsageSession AS us
    INNER JOIN dbo.[User] AS check_in_staff ON check_in_staff.user_id = us.check_in_by_user_id

    UNION ALL

    SELECT
        us.booking_id,
        us.actual_end_time,
        N'CheckedOut',
        check_out_staff.full_name,
        COALESCE(us.final_condition, us.usage_notes)
    FROM dbo.UsageSession AS us
    INNER JOIN dbo.[User] AS check_out_staff ON check_out_staff.user_id = us.check_out_by_user_id
    WHERE us.actual_end_time IS NOT NULL
),
OrderedEvents AS
(
    SELECT
        booking_id,
        event_time,
        event_type,
        actor_name,
        event_detail,
        LAG(event_time) OVER (PARTITION BY booking_id ORDER BY event_time, event_type) AS previous_event_time
    FROM AuditEvents
)
SELECT
    booking_id,
    event_time,
    event_type,
    actor_name,
    event_detail,
    DATEDIFF(MINUTE, previous_event_time, event_time) AS minutes_since_previous_event
FROM OrderedEvents
ORDER BY booking_id, event_time, event_type;
GO
