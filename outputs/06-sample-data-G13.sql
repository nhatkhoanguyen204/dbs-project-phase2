/*
    CSMS Phase 2 - deterministic sample data
    Safe to rerun: each row is identified by a stable natural scenario key.
*/

SET XACT_ABORT ON;
GO

BEGIN TRANSACTION;

/* Users: requester, facility operators, and administrator roles. */
INSERT INTO dbo.[User] (full_name, email, phone_number, role, department, account_status)
SELECT source.full_name, source.email, source.phone_number, source.role, source.department, source.account_status
FROM
(
    VALUES
        (N'An Nguyen', N'an.nguyen@csms.edu.vn', N'0901000001', N'Student', N'Computer Science', N'Active'),
        (N'Binh Tran', N'binh.tran@csms.edu.vn', N'0901000002', N'Lecturer', N'Computer Science', N'Active'),
        (N'Chi Le', N'chi.le@csms.edu.vn', N'0901000003', N'TA', N'Computer Science', N'Active'),
        (N'Duc Pham', N'duc.pham@csms.edu.vn', N'0901000004', N'FacilityStaff', N'Facilities', N'Active'),
        (N'Ha Vo', N'ha.vo@csms.edu.vn', N'0901000005', N'FacilityManager', N'Facilities', N'Active'),
        (N'Lan Do', N'lan.do@csms.edu.vn', N'0901000006', N'DeptAdmin', N'Computer Science', N'Active')
) AS source (full_name, email, phone_number, role, department, account_status)
WHERE NOT EXISTS
(
    SELECT 1
    FROM dbo.[User] AS u
    WHERE u.email = source.email
);

/* Spaces and equipment catalogue. */
INSERT INTO dbo.Space (space_code, space_name, space_type, building, floor, room_number, capacity, current_status, usage_policy)
SELECT source.space_code, source.space_name, source.space_type, source.building, source.floor, source.room_number, source.capacity, source.current_status, source.usage_policy
FROM
(
    VALUES
        (N'AUD-A01', N'Innovation Auditorium', N'Auditorium', N'A Block', N'1', N'A01', 180, N'Available', N'Lectures, seminars, and large academic events.'),
        (N'LAB-C201', N'Networking Laboratory', N'ComputerLaboratory', N'C Block', N'2', N'C201', 36, N'UnderMaintenance', N'Computer laboratory; facility approval required.'),
        (N'MR-B305', N'Project Meeting Room', N'MeetingRoom', N'B Block', N'3', N'B305', 18, N'Available', N'Meetings and student project work.'),
        (N'WS-D110', N'Student Collaboration Workspace', N'StudentWorkspace', N'D Block', N'1', N'D110', 24, N'InUse', N'Student group work during staffed hours.')
) AS source (space_code, space_name, space_type, building, floor, room_number, capacity, current_status, usage_policy)
WHERE NOT EXISTS
(
    SELECT 1
    FROM dbo.Space AS s
    WHERE s.space_code = source.space_code
);

INSERT INTO dbo.Facility (facility_name, facility_type, description)
SELECT source.facility_name, source.facility_type, source.description
FROM
(
    VALUES
        (N'Ceiling Projector', N'Projector', N'4K ceiling-mounted projector'),
        (N'Interactive Whiteboard', N'Whiteboard', N'Digital annotation whiteboard'),
        (N'Workstation PC', N'Computer', N'Networked teaching workstation'),
        (N'Conference Microphone', N'Microphone', N'USB conference microphone')
) AS source (facility_name, facility_type, description)
WHERE NOT EXISTS
(
    SELECT 1
    FROM dbo.Facility AS f
    WHERE f.facility_name = source.facility_name
      AND f.facility_type = source.facility_type
);

DECLARE @auditorium_id BIGINT = (SELECT space_id FROM dbo.Space WHERE space_code = N'AUD-A01');
DECLARE @lab_id BIGINT = (SELECT space_id FROM dbo.Space WHERE space_code = N'LAB-C201');
DECLARE @meeting_room_id BIGINT = (SELECT space_id FROM dbo.Space WHERE space_code = N'MR-B305');
DECLARE @workspace_id BIGINT = (SELECT space_id FROM dbo.Space WHERE space_code = N'WS-D110');
DECLARE @student_id BIGINT = (SELECT user_id FROM dbo.[User] WHERE email = N'an.nguyen@csms.edu.vn');
DECLARE @lecturer_id BIGINT = (SELECT user_id FROM dbo.[User] WHERE email = N'binh.tran@csms.edu.vn');
DECLARE @ta_id BIGINT = (SELECT user_id FROM dbo.[User] WHERE email = N'chi.le@csms.edu.vn');
DECLARE @staff_id BIGINT = (SELECT user_id FROM dbo.[User] WHERE email = N'duc.pham@csms.edu.vn');
DECLARE @manager_id BIGINT = (SELECT user_id FROM dbo.[User] WHERE email = N'ha.vo@csms.edu.vn');
DECLARE @admin_id BIGINT = (SELECT user_id FROM dbo.[User] WHERE email = N'lan.do@csms.edu.vn');
DECLARE @projector_id BIGINT = (SELECT facility_id FROM dbo.Facility WHERE facility_name = N'Ceiling Projector' AND facility_type = N'Projector');
DECLARE @whiteboard_id BIGINT = (SELECT facility_id FROM dbo.Facility WHERE facility_name = N'Interactive Whiteboard' AND facility_type = N'Whiteboard');
DECLARE @pc_id BIGINT = (SELECT facility_id FROM dbo.Facility WHERE facility_name = N'Workstation PC' AND facility_type = N'Computer');
DECLARE @microphone_id BIGINT = (SELECT facility_id FROM dbo.Facility WHERE facility_name = N'Conference Microphone' AND facility_type = N'Microphone');

INSERT INTO dbo.SpaceFacility (space_id, facility_id, quantity, notes)
SELECT source.space_id, source.facility_id, source.quantity, source.notes
FROM
(
    VALUES
        (@auditorium_id, @projector_id, 1, N'Installed above stage'),
        (@auditorium_id, @microphone_id, 4, N'Wireless presentation microphones'),
        (@lab_id, @pc_id, 36, N'One workstation per seat'),
        (@meeting_room_id, @whiteboard_id, 1, N'Wall-mounted'),
        (@workspace_id, @whiteboard_id, 1, N'Mobile board')
) AS source (space_id, facility_id, quantity, notes)
WHERE NOT EXISTS
(
    SELECT 1
    FROM dbo.SpaceFacility AS sf
    WHERE sf.space_id = source.space_id
      AND sf.facility_id = source.facility_id
);

/* Global lead time and a space-specific buffer policy. */
IF NOT EXISTS
(
    SELECT 1
    FROM dbo.BookingPolicy
    WHERE space_id IS NULL
      AND applicable_role IS NULL
      AND applicable_purpose IS NULL
)
BEGIN
    INSERT INTO dbo.BookingPolicy
    (
        space_id,
        applicable_role,
        applicable_purpose,
        minimum_lead_minutes,
        cancellation_lead_minutes,
        pre_buffer_minutes,
        post_buffer_minutes
    )
    VALUES
    (
        NULL,
        NULL,
        NULL,
        60,
        120,
        0,
        15
    );
END;

IF NOT EXISTS
(
    SELECT 1
    FROM dbo.BookingPolicy
    WHERE space_id = @auditorium_id
      AND applicable_role IS NULL
      AND applicable_purpose = N'Seminar'
)
BEGIN
    INSERT INTO dbo.BookingPolicy
    (
        space_id,
        applicable_role,
        applicable_purpose,
        minimum_lead_minutes,
        cancellation_lead_minutes,
        pre_buffer_minutes,
        post_buffer_minutes
    )
    VALUES
    (
        @auditorium_id,
        NULL,
        N'Seminar',
        1440,
        1440,
        30,
        30
    );
END;

/* Maintenance: one completed record and one active lockout. */
IF NOT EXISTS
(
    SELECT 1
    FROM dbo.MaintenanceRecord
    WHERE space_id = @auditorium_id
      AND problem_description = N'Annual projector alignment and lamp inspection'
)
BEGIN
    INSERT INTO dbo.MaintenanceRecord
    (
        space_id,
        reporter_user_id,
        assigned_staff_user_id,
        problem_description,
        start_time,
        completion_time,
        maintenance_status,
        result_note
    )
    VALUES
    (
        @auditorium_id,
        @staff_id,
        @staff_id,
        N'Annual projector alignment and lamp inspection',
        '2026-07-20 08:00:00',
        '2026-07-20 10:00:00',
        N'Completed',
        N'Alignment completed; lamp hours remain within specification.'
    );
END;

IF NOT EXISTS
(
    SELECT 1
    FROM dbo.MaintenanceRecord
    WHERE space_id = @lab_id
      AND problem_description = N'Core network switch replacement'
)
BEGIN
    INSERT INTO dbo.MaintenanceRecord
    (
        space_id,
        reporter_user_id,
        assigned_staff_user_id,
        problem_description,
        start_time,
        completion_time,
        maintenance_status,
        result_note
    )
    VALUES
    (
        @lab_id,
        @staff_id,
        @staff_id,
        N'Core network switch replacement',
        '2026-08-01 08:00:00',
        NULL,
        N'InProgress',
        NULL
    );
END;

/* Bookings cover every lifecycle state. Historical outcomes remain valid even if a space is now unavailable. */
IF NOT EXISTS (SELECT 1 FROM dbo.Booking WHERE requester_user_id = @lecturer_id AND requested_start_time = '2026-07-25 13:00:00')
    INSERT INTO dbo.Booking (requester_user_id, space_id, requested_start_time, requested_end_time, purpose, expected_participants, booking_status, submitted_at)
    VALUES (@lecturer_id, @auditorium_id, '2026-07-25 13:00:00', '2026-07-25 17:00:00', N'Seminar', 120, N'Completed', '2026-07-10 09:00:00');

IF NOT EXISTS (SELECT 1 FROM dbo.Booking WHERE requester_user_id = @lecturer_id AND requested_start_time = '2026-08-10 09:00:00')
    INSERT INTO dbo.Booking (requester_user_id, space_id, requested_start_time, requested_end_time, purpose, expected_participants, booking_status, submitted_at)
    VALUES (@lecturer_id, @auditorium_id, '2026-08-10 09:00:00', '2026-08-10 11:00:00', N'Lecture', 150, N'Approved', '2026-07-28 09:00:00');

IF NOT EXISTS (SELECT 1 FROM dbo.Booking WHERE requester_user_id = @student_id AND requested_start_time = '2026-08-12 14:00:00')
    INSERT INTO dbo.Booking (requester_user_id, space_id, requested_start_time, requested_end_time, purpose, expected_participants, booking_status, submitted_at)
    VALUES (@student_id, @meeting_room_id, '2026-08-12 14:00:00', '2026-08-12 16:00:00', N'StudentActivity', 12, N'Pending', '2026-08-01 10:00:00');

IF NOT EXISTS (SELECT 1 FROM dbo.Booking WHERE requester_user_id = @ta_id AND requested_start_time = '2026-08-02 09:00:00')
    INSERT INTO dbo.Booking (requester_user_id, space_id, requested_start_time, requested_end_time, purpose, expected_participants, booking_status, submitted_at)
    VALUES (@ta_id, @workspace_id, '2026-08-02 09:00:00', '2026-08-02 12:00:00', N'Workshop', 20, N'CheckedIn', '2026-07-30 09:00:00');

IF NOT EXISTS (SELECT 1 FROM dbo.Booking WHERE requester_user_id = @student_id AND requested_start_time = '2026-07-29 10:00:00')
    INSERT INTO dbo.Booking (requester_user_id, space_id, requested_start_time, requested_end_time, purpose, expected_participants, booking_status, submitted_at, cancelled_at, cancelled_by_user_id, cancellation_note)
    VALUES (@student_id, @meeting_room_id, '2026-07-29 10:00:00', '2026-07-29 12:00:00', N'Meeting', 8, N'Cancelled', '2026-07-20 10:00:00', '2026-07-27 08:00:00', @student_id, N'Project meeting moved online.');

IF NOT EXISTS (SELECT 1 FROM dbo.Booking WHERE requester_user_id = @ta_id AND requested_start_time = '2026-07-28 13:00:00')
    INSERT INTO dbo.Booking (requester_user_id, space_id, requested_start_time, requested_end_time, purpose, expected_participants, booking_status, submitted_at)
    VALUES (@ta_id, @meeting_room_id, '2026-07-28 13:00:00', '2026-07-28 15:00:00', N'Workshop', 15, N'NoShow', '2026-07-15 09:00:00');

IF NOT EXISTS (SELECT 1 FROM dbo.Booking WHERE requester_user_id = @admin_id AND requested_start_time = '2026-08-05 09:00:00')
    INSERT INTO dbo.Booking (requester_user_id, space_id, requested_start_time, requested_end_time, purpose, expected_participants, booking_status, submitted_at)
    VALUES (@admin_id, @lab_id, '2026-08-05 09:00:00', '2026-08-05 11:00:00', N'AdministrativeEvent', 20, N'Rejected', '2026-07-31 09:00:00');

DECLARE @completed_booking_id BIGINT = (SELECT booking_id FROM dbo.Booking WHERE requester_user_id = @lecturer_id AND requested_start_time = '2026-07-25 13:00:00');
DECLARE @approved_booking_id BIGINT = (SELECT booking_id FROM dbo.Booking WHERE requester_user_id = @lecturer_id AND requested_start_time = '2026-08-10 09:00:00');
DECLARE @checked_in_booking_id BIGINT = (SELECT booking_id FROM dbo.Booking WHERE requester_user_id = @ta_id AND requested_start_time = '2026-08-02 09:00:00');
DECLARE @rejected_booking_id BIGINT = (SELECT booking_id FROM dbo.Booking WHERE requester_user_id = @admin_id AND requested_start_time = '2026-08-05 09:00:00');

/* Approval/rejection audit records. */
IF NOT EXISTS (SELECT 1 FROM dbo.BookingDecision WHERE booking_id = @completed_booking_id AND decision = N'Approved')
    INSERT INTO dbo.BookingDecision (booking_id, decision_maker_user_id, decision_time, decision, decision_note, rejection_reason)
    VALUES (@completed_booking_id, @manager_id, '2026-07-11 09:00:00', N'Approved', N'Large seminar approved.', NULL);

IF NOT EXISTS (SELECT 1 FROM dbo.BookingDecision WHERE booking_id = @approved_booking_id AND decision = N'Approved')
    INSERT INTO dbo.BookingDecision (booking_id, decision_maker_user_id, decision_time, decision, decision_note, rejection_reason)
    VALUES (@approved_booking_id, @staff_id, '2026-07-29 10:00:00', N'Approved', N'Room capacity and schedule confirmed.', NULL);

IF NOT EXISTS (SELECT 1 FROM dbo.BookingDecision WHERE booking_id = @rejected_booking_id AND decision = N'Rejected')
    INSERT INTO dbo.BookingDecision (booking_id, decision_maker_user_id, decision_time, decision, decision_note, rejection_reason)
    VALUES (@rejected_booking_id, @manager_id, '2026-08-01 09:15:00', N'Rejected', N'Network replacement blocks the requested interval.', N'LAB-C201 is under active network-switch maintenance.');

/* Completed session has a late check-out; checked-in session deliberately has no check-out yet. */
IF NOT EXISTS (SELECT 1 FROM dbo.UsageSession WHERE booking_id = @completed_booking_id)
    INSERT INTO dbo.UsageSession
    (
        booking_id,
        check_in_by_user_id,
        actual_start_time,
        initial_condition,
        check_out_by_user_id,
        actual_end_time,
        final_condition,
        usage_notes
    )
    VALUES
    (
        @completed_booking_id,
        @staff_id,
        '2026-07-25 12:50:00',
        N'Projector and seating inspected; good condition.',
        @staff_id,
        '2026-07-25 17:20:00',
        N'Room clean; projector powered down.',
        N'Session finished twenty minutes after the planned end.'
    );

IF NOT EXISTS (SELECT 1 FROM dbo.UsageSession WHERE booking_id = @checked_in_booking_id)
    INSERT INTO dbo.UsageSession
    (
        booking_id,
        check_in_by_user_id,
        actual_start_time,
        initial_condition,
        check_out_by_user_id,
        actual_end_time,
        final_condition,
        usage_notes
    )
    VALUES
    (
        @checked_in_booking_id,
        @staff_id,
        '2026-08-02 08:55:00',
        N'Workspace clean and whiteboard supplied.',
        NULL,
        NULL,
        NULL,
        N'Active workshop; check-out pending.'
    );

COMMIT TRANSACTION;
GO
