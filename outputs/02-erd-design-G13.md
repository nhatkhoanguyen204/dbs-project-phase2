# CSMS Conceptual Database Design (ERD)

## 1. Entity Set Definitions

| Entity set | Key attributes | Conceptual notes |
|---|---|---|
| User | UserID, Email | University-account holder; Role and AccountStatus control authorization. |
| Space | SpaceID, SpaceCode | Bookable physical space with location, capacity, status, and usage policy. Location comprises Building, Floor, and RoomNumber. |
| Facility | FacilityID | Reusable facility/equipment type, such as a projector or whiteboard. |
| SpaceFacility | SpaceID, FacilityID | Associative entity recording a facility type and optional quantity/notes in a space. |
| Booking | BookingID | Request for one space and interval; holds purpose, expected participants, lifecycle status, and submitted time. Duration is derived. |
| BookingDecision | DecisionID | Immutable approval/rejection decision history, including decision maker, time, note, and rejection reason. |
| UsageSession | UsageSessionID | Optional weak/dependent record for an actual check-in/out; actual duration is derived. |
| MaintenanceRecord | MaintenanceID | Reported problem, active interval, optional assignee, completion, status, and result note for one space. |
| BookingPolicy | PolicyID | Configurable lead time, cancellation deadline, and pre/post buffers applicable to a space and/or role/purpose. |

`Booking` and `MaintenanceRecord` are historical transaction entities. `UsageSession` is existence-dependent on `Booking`; a booking may have at most one usage session. Controlled attributes include roles, account status, space type/status, booking purpose/status, and maintenance status.

## 2. Relationship & Participation Constraints Matrix

| Relationship | Cardinality and participation | Meaning |
|---|---|---|
| User submits Booking | User 0..N — Booking 1..1 | Every booking has exactly one requester; a user may make no bookings. |
| Space is reserved by Booking | Space 0..N — Booking 1..1 | Every booking selects exactly one space. |
| Booking has BookingDecision | Booking 0..N — Decision 1..1 | A pending request has no decision; every decision belongs to one booking. |
| User makes BookingDecision | User 0..N — Decision 1..1 | Each decision records one authorized actor. |
| Booking produces UsageSession | Booking 0..1 — UsageSession 1..1 | A session occurs only after check-in. |
| User checks in/out UsageSession | User 0..N — UsageSession 1..1 per action | Check-in and check-out actors are retained independently and may differ. |
| Space contains Facility | Space 0..N — Facility 0..N via SpaceFacility | Equipment inventory is many-to-many. |
| Space is subject to MaintenanceRecord | Space 0..N — MaintenanceRecord 1..1 | Each maintenance record affects exactly one space. |
| User reports/receives MaintenanceRecord | User 0..N — Record 1..1 reporter; User 0..N — Record 0..1 assignee | Reporting is mandatory; assignment is optional until staff is allocated. |
| BookingPolicy governs Space | Policy 0..N — Space 0..N | Policies can be global (no space), space-specific, or parameterized by role/purpose. |

## 3. Conceptual Entity-Relationship Diagram

```mermaid
erDiagram
    USER {
        int UserID PK
        string FullName
        string Email UK
        string PhoneNumber
        string Role
        string Department
        string AccountStatus
    }
    SPACE {
        int SpaceID PK
        string SpaceCode UK
        string SpaceName
        string SpaceType
        string Building
        string Floor
        string RoomNumber
        int Capacity
        string CurrentStatus
        string UsagePolicy
    }
    FACILITY {
        int FacilityID PK
        string FacilityName
        string FacilityType
        string Description
    }
    SPACE_FACILITY {
        int SpaceID PK, FK
        int FacilityID PK, FK
        int Quantity
        string Notes
    }
    BOOKING {
        int BookingID PK
        int RequesterUserID FK
        int SpaceID FK
        datetime RequestedStartTime
        datetime RequestedEndTime
        string Purpose
        int ExpectedParticipants
        string BookingStatus
        datetime SubmittedAt
    }
    BOOKING_DECISION {
        int DecisionID PK
        int BookingID FK
        int DecisionMakerUserID FK
        datetime DecisionTime
        string Decision
        string DecisionNote
        string RejectionReason
    }
    USAGE_SESSION {
        int UsageSessionID PK
        int BookingID FK, UK
        int CheckInByUserID FK
        datetime ActualStartTime
        string InitialCondition
        int CheckOutByUserID FK
        datetime ActualEndTime
        string FinalCondition
        string UsageNotes
    }
    MAINTENANCE_RECORD {
        int MaintenanceID PK
        int SpaceID FK
        int ReporterUserID FK
        int AssignedStaffUserID FK
        string ProblemDescription
        datetime StartTime
        datetime CompletionTime
        string MaintenanceStatus
        string ResultNote
    }
    BOOKING_POLICY {
        int PolicyID PK
        int SpaceID FK
        string ApplicableRole
        string ApplicablePurpose
        int MinimumLeadMinutes
        int CancellationLeadMinutes
        int PreBufferMinutes
        int PostBufferMinutes
    }

    USER ||--o{ BOOKING : submits
    SPACE ||--o{ BOOKING : reserved_for
    BOOKING ||--o{ BOOKING_DECISION : has
    USER ||--o{ BOOKING_DECISION : makes
    BOOKING ||--o| USAGE_SESSION : produces
    USER ||--o{ USAGE_SESSION : checks_in
    USER ||--o{ USAGE_SESSION : checks_out
    SPACE ||--o{ SPACE_FACILITY : contains
    FACILITY ||--o{ SPACE_FACILITY : assigned_as
    SPACE ||--o{ MAINTENANCE_RECORD : subject_to
    USER ||--o{ MAINTENANCE_RECORD : reports
    USER o|--o{ MAINTENANCE_RECORD : assigned_to
    SPACE o|--o{ BOOKING_POLICY : governed_by
```

The diagram uses `||` for mandatory one, `o|` for optional one, and `o{` for zero or many. Availability is a cross-entity business constraint: an approved/checked-in booking cannot overlap another approved/checked-in booking or active maintenance for the same space; closed, maintenance, and retired spaces are non-bookable.
