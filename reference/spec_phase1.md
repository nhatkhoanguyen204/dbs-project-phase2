# Phase 1 System Specification

## 1. Business Requirement Description

The School of Computer Science manages several shared physical spaces used for teaching, seminars, examinations, workshops, student projects, research activities, and academic events. These spaces include auditoriums, classrooms, computer laboratories, project laboratories, meeting rooms, and student workspaces.
Currently, requests to use these spaces are handled manually. Lecturers, teaching assistants, students, and staff usually contact the school office or facility staff by email, phone, or in person. Facility staff then check spreadsheets or shared calendars to determine whether a room is available, whether the requester is allowed to use it, whether special equipment is needed, and whether the room is under maintenance.
As the number of classes, student projects, workshops, seminars, and academic events increases, the manual process has become difficult to manage. The School wants to build a database system to manage space booking, approval, usage sessions, maintenance, incident reporting, and facility utilization.
The Facility Manager provides the following requirement summary:

---

### 1.1. User Management and Accounts
* Each user must have a university account.
* The system stores basic user information, including:
  * User ID
  * Full name
  * Email
  * Phone number
  * Role (Student, Lecturer, Teaching Assistant, Facility Staff, Department Administrator, or Facility Manager)
  * Department
  * Account status

---

### 1.2. Space and Facility Management
* The School manages many bookable spaces (auditoriums, classrooms, computer laboratories, project laboratories, meeting rooms, and student workspaces).
* For each space, the system stores:
  * Unique space code
  * Space name
  * Space type
  * Building, floor, and room number
  * Capacity
  * Current status (`available`, `in use`, `under maintenance`, `temporarily closed`, or `retired`)
  * Usage policy
* Each space may have several facilities, such as a projector, whiteboard, microphone, computer, livestreaming equipment, or air conditioner. The system maintains the list of facilities available in each space.

---

### 1.3. Booking Requests and Workflow
* Users can submit booking requests by specifying:
  * Selected space
  * Requested start time
  * Requested end time
  * Purpose of use (lecture, examination, seminar, workshop, meeting, student activity, or administrative event)
  * Expected number of participants
* Each booking request has a status: `pending`, `approved`, `rejected`, `cancelled`, `checked in`, `completed`, or `no-show`.
* **Conflict Prevention:** The system must prevent conflicting bookings. The same space cannot have two approved bookings with overlapping time periods. A space that is under maintenance, closed, or retired cannot be booked.
* **Approval Process:** A booking request may require approval from a facility staff member or manager. When a booking is approved or rejected, the system records:
  * The staff member who made the decision
  * Decision time
  * Decision note
  * Rejection reason (if rejected)

---

### 1.4. Check-in and Usage Sessions
* When the requester arrives, facility staff can check in the booking. The system records:
  * Actual start time
  * The person who checked in the booking
  * Initial condition of the space
* When the session ends, facility staff can complete the booking by recording:
  * Actual end time
  * Final condition of the space
  * Any usage notes

---

### 1.5. Maintenance Management
* The system supports basic maintenance management for problems such as broken projectors, air-conditioning failure, damaged furniture, cleaning issues, or network problems.
* Each maintenance record stores:
  * Related space
  * Reporter
  * Assigned staff member
  * Problem description
  * Start time
  * Completion time
  * Status
  * Result note
* A space under maintenance cannot be booked.

---

### 1.6. History and Reporting
* The system must keep historical records of bookings and maintenance activities.
* Staff must be able to view:
  * Booking history
  * Upcoming bookings
  * Spaces under maintenance
  * No-show bookings

---

### 1.7. Main Goals
The main goal of the system is to help the School manage shared campus spaces fairly, avoid overlapping bookings, prevent the use of unavailable spaces, and preserve usage history.
