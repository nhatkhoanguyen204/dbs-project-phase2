# CSMS Business Requirement Analysis & Business Rules

## 1. System Actors & Permission Scopes

| Actor | Primary responsibilities | Permitted scope | Access limits |
|---|---|---|---|
| Student | Request space for student activities and projects; view own activity. | Create, view, and cancel own booking requests; view bookable-space availability and facilities. | Cannot approve requests, check users in/out, alter spaces or maintenance records, or view other users' private booking details. |
| Lecturer | Request space for teaching, examinations, seminars, research, and events. | Student permissions for own bookings; may view space policies and availability. | Cannot make approval decisions or administer facility/master data unless separately assigned an administrative role. |
| Teaching Assistant (TA) | Request rooms in support of teaching or student activities. | Student permissions for own bookings. | Cannot approve, check in/out, or administer spaces, facilities, or maintenance. |
| Facility Staff | Operate spaces day to day. | View all operational bookings; record approval/rejection when authorized; check bookings in and out; report, receive assignment for, update, and complete maintenance; view relevant space/facility data. | Cannot change user roles or department ownership; approval authority is limited to requests within assigned operational scope. |
| Department Administrator | Coordinate departmental use and administrative events. | Submit and view departmental booking requests; view departmental booking history and availability; manage administrative booking information as authorized. | Does not perform facility check-in/out or maintenance work and does not alter global space/facility master data unless also assigned Facility Manager authority. |
| Facility Manager | Own facility policy, availability, and escalation decisions. | All Facility Staff operational functions; approve/reject any request; manage spaces, facilities, policies, statuses, and maintenance assignment; access all required historical and utilization reports. | Must preserve historical records rather than delete bookings or maintenance records. |

**Role and account rules.** Every person interacting with CSMS has one university account with a unique user ID. A user record includes full name, unique email, phone number, role, department, and account status. Only an active account may submit or manage operational transactions. Role is an authorization attribute; a user may be granted additional authority only through a controlled role assignment, rather than by changing the history of actions already recorded.

## 2. Business Entities & Attributes

| Entity | Purpose and key attributes | Composite / derived attributes |
|---|---|---|
| **Users** | **UserID** (identifier); FullName; Email; PhoneNumber; Role; Department; AccountStatus. | FullName may be captured as a single value or composed from name parts. Account eligibility is derived from AccountStatus and role permissions. |
| **Spaces** | **SpaceID** (surrogate identifier) and unique SpaceCode; SpaceName; SpaceType; Building; Floor; RoomNumber; Capacity; CurrentStatus; UsagePolicy. | Location is the composite of Building, Floor, and RoomNumber. A display location may be derived from those fields. Bookability is derived from CurrentStatus plus conflicting approved/active bookings and maintenance intervals. |
| **Facilities** | **FacilityID**; FacilityName; FacilityType/Description. Stores catalogued resources such as projectors, whiteboards, microphones, computers, livestreaming equipment, and air conditioners. | Availability in a particular space is derived from its assignment to that space and, if tracked later, its service condition. |
| **SpaceFacilities** | Associative entity with **SpaceID + FacilityID** (or a surrogate key); optional Quantity/Notes. | Represents the facilities available in each space. |
| **Bookings** | **BookingID**; RequesterUserID; SpaceID; RequestedStartTime; RequestedEndTime; Purpose; ExpectedParticipants; BookingStatus; SubmittedAt; cancellation details where applicable. | Requested duration is derived from end minus start. Booking validity is derived from time ordering, capacity, account eligibility, space availability, and workflow status. |
| **BookingDecisions** | **DecisionID**; BookingID; DecisionMakerUserID; DecisionTime; Decision; DecisionNote; RejectionReason. | Applies to approval/rejection workflow. The booking's current status reflects the latest valid decision and later lifecycle events. |
| **CheckInsOuts** | **UsageSessionID**; BookingID; CheckInByUserID; ActualStartTime; InitialCondition; CheckOutByUserID; ActualEndTime; FinalCondition; UsageNotes. | Actual duration is derived from actual end minus actual start. A booking is active after check-in and completed after a valid check-out. |
| **MaintenanceRecords** | **MaintenanceID**; SpaceID; ReporterUserID; AssignedStaffUserID; ProblemDescription; StartTime; CompletionTime; MaintenanceStatus; ResultNote. | Maintenance duration is derived when completed. A space is unavailable when it has a maintenance record in an active blocking status covering the requested time. |

**Controlled values.**

- SpaceType is one of auditorium, classroom, computer laboratory, project laboratory, meeting room, or student workspace; the controlled list may be extended by facility management.
- Space CurrentStatus is one of `available`, `in use`, `under maintenance`, `temporarily closed`, or `retired`.
- BookingStatus is one of `pending`, `approved`, `rejected`, `cancelled`, `checked in`, `completed`, or `no-show`.
- Booking Purpose is one of lecture, examination, seminar, workshop, meeting, student activity, or administrative event.
- MaintenanceStatus is managed through a controlled set (at minimum: reported/open, assigned/in progress, completed, and cancelled where a report is invalid). Active maintenance statuses block the space; completed and cancelled records do not.

**Data quality constraints.** SpaceCode and user email must be unique. Capacity and expected participants must be positive numbers, and ExpectedParticipants must not exceed the booked space's Capacity. A booking's requested end must be later than its requested start; a completed maintenance record's CompletionTime must not precede StartTime; and a check-out time must be later than its recorded actual start time.

## 3. Relationships & Cardinalities

| Relationship | Cardinality | Business meaning |
|---|---|---|
| User — Booking (requester) | One User to zero or many Bookings; each Booking to exactly one User | A request must identify its university-account requester. |
| Space — Booking | One Space to zero or many Bookings; each Booking to exactly one Space | A booking reserves one selected space for one requested interval. |
| Booking — BookingDecision | One Booking to zero or many decisions; each decision to exactly one Booking | Pending requests have no decision; approval/rejection actions are retained as history. At most one current effective decision determines the current disposition. |
| User — BookingDecision (decision maker) | One authorized User to zero or many decisions; each decision to exactly one authorized staff/manager | Approval and rejection are accountable actions. |
| Booking — CheckInsOuts | One Booking to zero or one UsageSession; each UsageSession to exactly one Booking | A session exists only when facility staff check in a booking; it contains optional check-out details until completed. |
| User — CheckInsOuts | One Facility Staff user to zero or many check-in/check-out actions | Check-in and check-out operator identities must be retained; they may be different staff users. |
| Space — MaintenanceRecord | One Space to zero or many MaintenanceRecords; each record to exactly one Space | Maintenance history belongs to the affected space. |
| User — MaintenanceRecord (reporter) | One User to zero or many reports; each record to exactly one reporter | A problem report is attributable to its reporter. |
| User — MaintenanceRecord (assignee) | One Facility Staff user to zero or many assignments; each record to zero or one assigned staff user | Assignment can be empty while a report awaits assignment. |
| Space — Facility | Many-to-many through SpaceFacilities | A space can provide several facilities; a facility type can occur in several spaces. |

## 4. Business Rules & Logic Constraints

### 4.1 Booking creation and availability

1. A booking request must reference an active requester account, one existing space, a permitted purpose, a positive expected participant count, and a valid requested interval.
2. A requester may create a booking only for a space whose usage policy permits the requester's role and intended use. Policies may impose additional requirements such as staff supervision or permitted activities.
3. A space with CurrentStatus `under maintenance`, `temporarily closed`, or `retired` cannot accept a booking. `retired` is permanently non-bookable until explicitly reinstated by a Facility Manager.
4. The same space must not have two overlapping **approved or checked-in** bookings. Two intervals overlap when `new_start < existing_end` and `new_end > existing_start`; a booking ending exactly when another starts is not an overlap.
5. Pending, rejected, cancelled, completed, and no-show bookings do not themselves reserve the space. Pending requests must nevertheless be revalidated for availability when a staff member attempts approval.
6. An active maintenance interval blocks new bookings for the affected space. Approval must also fail if the requested interval overlaps active maintenance, even if the space status has not yet been refreshed.
7. When maintenance is opened for a time that overlaps a pending booking, the pending request remains pending but is flagged for staff review and cannot be approved until the conflict is resolved. When it overlaps an already approved booking, the system must preserve the booking history and require staff/manager intervention (for example, cancel, reschedule, or move it); it must not silently approve a conflict.
8. `in use` describes present operational occupancy and must not be used as the sole future-availability rule. It should correspond to a currently checked-in session or another authorized operational condition.

### 4.2 Approval workflow and lifecycle

1. A new request begins as `pending`. The system evaluates policy to determine whether it is eligible for auto-approval or requires a Facility Staff/Facility Manager decision.
2. Auto-approval is allowed only if an explicitly configured policy permits the requester role, purpose, interval, capacity, and space; the same conflict and availability validation applies. Otherwise, staff/manager approval is required.
3. A manual `approved` or `rejected` outcome must store the authorized decision maker, decision time, decision note, and—when rejected—a non-empty rejection reason. Auto-approval must record a system decision timestamp and policy basis for auditability.
4. Only `pending` requests may be approved or rejected. An approval attempt must execute atomically with conflict validation so simultaneous requests cannot both be approved for the same space and interval.
5. Valid normal state changes are: `pending` → `approved` or `rejected` or `cancelled`; `approved` → `cancelled` or `checked in` or `no-show`; `checked in` → `completed`. Terminal outcomes (`rejected`, `cancelled`, `completed`, `no-show`) must not be changed except by an explicitly audited correction process.
6. Only the requester (or an authorized administrator acting for the requester) may cancel an eligible booking. Cancellation must preserve the booking and decision history rather than delete it.
7. A no-show is recorded by authorized staff when an approved booking was not checked in according to the applicable policy. A no-show releases no historical data and remains reportable.

### 4.3 Check-in, check-out, and condition records

1. Only Facility Staff or a Facility Manager can check in an `approved` booking. Check-in records the actual start time, staff member, and initial space condition, then changes status to `checked in`.
2. Check-out is allowed only for a checked-in booking. It records actual end time, final condition, usage notes, and the staff member performing the action, then changes status to `completed`.
3. ActualEndTime must be later than ActualStartTime. A final-condition issue or damage note may trigger a related maintenance record, without erasing the usage-session record.
4. The system retains both requested and actual times so utilization, attendance/no-show, and incident reporting can distinguish planned use from actual use.

### 4.4 Maintenance and space status

1. Any authorized user can report a space problem; the report records the space, reporter, description, and start/report time. Only authorized facility personnel can be assigned to or complete maintenance.
2. A maintenance record may be assigned to zero or one staff member at a time. Completion requires a completion time and result note, and changes the maintenance status to `completed`.
3. Starting or activating maintenance changes the affected space to `under maintenance` where the maintenance is currently blocking use. Completion does not automatically make a space `available`: authorized staff/manager must confirm the appropriate post-maintenance status, accounting for another active maintenance record, scheduled occupancy, or closure.
4. `temporarily closed` and `retired` statuses also block booking regardless of facility inventory. Existing approved bookings in a newly unavailable space require an explicit, auditable resolution.

### 4.5 Policy parameters and audit requirements

1. The Phase 1 specification requires lead times, cancellation policies, and buffer periods to be enforced but does not prescribe their numeric values. CSMS must store these as configurable policy parameters by space and/or purpose/role rather than hard-code values.
2. At request time, RequestedStartTime must meet the applicable minimum lead time. At cancellation time, the applicable cancellation deadline determines whether self-service cancellation is allowed or staff/manager authorization is required.
3. A configured pre-booking and post-booking buffer is treated as part of the occupied interval for conflict checks. Thus, effective occupied time is `[requested_start - pre_buffer, requested_end + post_buffer)`; directly adjacent requests are permitted only when their effective intervals do not overlap.
4. All decision, check-in/out, cancellation, maintenance assignment, completion, and status-change actions must retain the acting user, action time, and relevant notes/reasons. Booking and maintenance history must be retained for reporting rather than physically deleted.
5. Required reports include booking history, upcoming bookings, spaces currently under maintenance, and no-show bookings. The data model must retain statuses and timestamps sufficient to produce them accurately.
