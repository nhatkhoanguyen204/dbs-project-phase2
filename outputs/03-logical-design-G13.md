# CSMS Logical Database Design & Key Mapping

## 1. Relational Schema Map

```text
User ─< Booking >─ Space ─< SpaceFacility >─ Facility
          │  \                         └─< BookingPolicy
          │   └─< BookingDecision >─ User
          └─0..1 UsageSession >─ User (check-in / check-out)

Space ─< MaintenanceRecord >─ User (reporter / optional assignee)
```

All identifiers are `BIGINT IDENTITY` surrogate keys except the `SpaceFacility` junction, whose composite key prevents duplicate facility assignments. Status, type, purpose, and role values use controlled `NVARCHAR` codes enforced by `CHECK` constraints in the physical design. Times use `DATETIME2(0)` in the school’s operating time zone; application/API boundaries must normalize time-zone handling.

## 2. Table Specifications & Key Mapping (PK, FK, CK)

### User

| Column | Type | Key / nullability | Description |
|---|---|---|---|
| user_id | BIGINT IDENTITY | PK, NOT NULL | University-account surrogate key. |
| full_name | NVARCHAR(150) | NOT NULL | User’s full name. |
| email | NVARCHAR(254) | CK, NOT NULL | Unique university email. |
| phone_number | NVARCHAR(30) | NULL | Contact number. |
| role | NVARCHAR(30) | NOT NULL | Controlled role code. |
| department | NVARCHAR(100) | NOT NULL | Department name/code. |
| account_status | NVARCHAR(20) | NOT NULL | Controlled account-status code. |

### Space

| Column | Type | Key / nullability | Description |
|---|---|---|---|
| space_id | BIGINT IDENTITY | PK, NOT NULL | Space surrogate key. |
| space_code | NVARCHAR(30) | CK, NOT NULL | Unique human-readable code. |
| space_name | NVARCHAR(150) | NOT NULL | Space name. |
| space_type | NVARCHAR(40) | NOT NULL | Controlled type code. |
| building | NVARCHAR(80) | NOT NULL | Location component. |
| floor | NVARCHAR(20) | NOT NULL | Location component. |
| room_number | NVARCHAR(30) | NOT NULL | Location component. |
| capacity | INT | NOT NULL | Positive maximum occupancy. |
| current_status | NVARCHAR(30) | NOT NULL | Controlled availability status. |
| usage_policy | NVARCHAR(1000) | NULL | Human-readable policy notes. |

### Facility and SpaceFacility

| Table | Columns | Keys |
|---|---|---|
| Facility | facility_id BIGINT IDENTITY; facility_name NVARCHAR(100); facility_type NVARCHAR(50); description NVARCHAR(500) NULL | PK: facility_id. CK: (facility_name, facility_type). |
| SpaceFacility | space_id BIGINT; facility_id BIGINT; quantity INT; notes NVARCHAR(500) NULL | PK: (space_id, facility_id). FK: space_id → Space; facility_id → Facility. |

`quantity` is positive. This junction maps the `Space`–`Facility` many-to-many relationship.

### Booking and BookingDecision

| Table | Columns | Keys |
|---|---|---|
| Booking | booking_id BIGINT IDENTITY; requester_user_id BIGINT; space_id BIGINT; requested_start_time DATETIME2(0); requested_end_time DATETIME2(0); purpose NVARCHAR(40); expected_participants INT; booking_status NVARCHAR(20); submitted_at DATETIME2(0); cancelled_at DATETIME2(0) NULL; cancelled_by_user_id BIGINT NULL; cancellation_note NVARCHAR(1000) NULL | PK: booking_id. FKs: requester_user_id → User; space_id → Space; cancelled_by_user_id → User. Candidate key: none; interval uniqueness is not sufficient to prevent overlap. |
| BookingDecision | decision_id BIGINT IDENTITY; booking_id BIGINT; decision_maker_user_id BIGINT; decision_time DATETIME2(0); decision NVARCHAR(20); decision_note NVARCHAR(1000) NULL; rejection_reason NVARCHAR(1000) NULL | PK: decision_id. FKs: booking_id → Booking; decision_maker_user_id → User. Candidate key: (booking_id, decision_time). |

`BookingDecision` is append-only decision history. `Booking` remains the current lifecycle record; its requested end must be after its requested start, and expected participants must be positive and no greater than the selected space’s capacity (enforced by transaction/trigger logic because it crosses tables).

### UsageSession

| Column | Type | Key / nullability | Description |
|---|---|---|---|
| usage_session_id | BIGINT IDENTITY | PK, NOT NULL | Session surrogate key. |
| booking_id | BIGINT | CK, FK, NOT NULL | Unique parent booking. |
| check_in_by_user_id | BIGINT | FK, NOT NULL | Authorized check-in operator. |
| actual_start_time | DATETIME2(0) | NOT NULL | Actual session start. |
| initial_condition | NVARCHAR(1000) | NOT NULL | Condition at check-in. |
| check_out_by_user_id | BIGINT | FK, NULL | Authorized check-out operator. |
| actual_end_time | DATETIME2(0) | NULL | Actual session end. |
| final_condition | NVARCHAR(1000) | NULL | Condition at check-out. |
| usage_notes | NVARCHAR(1000) | NULL | Operational notes. |

FKs reference `User` for both operator columns. `UNIQUE (booking_id)` enforces the conceptual 1:0..1 relationship; end time, if present, must be after start time.

### MaintenanceRecord

| Column | Type | Key / nullability | Description |
|---|---|---|---|
| maintenance_id | BIGINT IDENTITY | PK, NOT NULL | Maintenance surrogate key. |
| space_id | BIGINT | FK, NOT NULL | Affected space. |
| reporter_user_id | BIGINT | FK, NOT NULL | Problem reporter. |
| assigned_staff_user_id | BIGINT | FK, NULL | Staff member assigned to resolve it. |
| problem_description | NVARCHAR(2000) | NOT NULL | Reported issue. |
| start_time | DATETIME2(0) | NOT NULL | Reported or blocking-start time. |
| completion_time | DATETIME2(0) | NULL | Completion time. |
| maintenance_status | NVARCHAR(30) | NOT NULL | Controlled maintenance-state code. |
| result_note | NVARCHAR(2000) | NULL | Completion/result explanation. |

`completion_time`, when present, cannot precede `start_time`. Active maintenance records participate in the same availability validation as approved and checked-in bookings.

### BookingPolicy

| Column | Type | Key / nullability | Description |
|---|---|---|---|
| policy_id | BIGINT IDENTITY | PK, NOT NULL | Policy surrogate key. |
| space_id | BIGINT | FK, NULL | Optional space-specific scope; `NULL` denotes a global policy. |
| applicable_role | NVARCHAR(30) | NULL | Optional role scope. |
| applicable_purpose | NVARCHAR(40) | NULL | Optional purpose scope. |
| minimum_lead_minutes | INT | NOT NULL | Minimum advance notice. |
| cancellation_lead_minutes | INT | NOT NULL | Self-service cancellation deadline. |
| pre_buffer_minutes | INT | NOT NULL | Buffer before booked time. |
| post_buffer_minutes | INT | NOT NULL | Buffer after booked time. |

All policy minute values are non-negative. `policy_id` is the stable key; policy precedence and prevention of ambiguous scopes are enforced by a unique filtered-index/validation rule in the physical design.

## 3. Referential Integrity Rules

| Parent → child relationship | Delete rule | Update rule | Rationale |
|---|---|---|---|
| Space → SpaceFacility; Facility → SpaceFacility | `ON DELETE CASCADE` | `ON UPDATE NO ACTION` | A junction row has no value without both master rows; identity keys are immutable. |
| Booking → UsageSession | `ON DELETE CASCADE` | `ON UPDATE NO ACTION` | `UsageSession` is dependent on its booking; operational deletion and key updates are prohibited. |
| User → Booking / BookingDecision / UsageSession / MaintenanceRecord | `ON DELETE NO ACTION` | `ON UPDATE NO ACTION` | Preserve accountability and history. Accounts are deactivated, not deleted. |
| Space → Booking / MaintenanceRecord | `ON DELETE NO ACTION` | `ON UPDATE NO ACTION` | Preserve booking and maintenance history. Retire a space through status instead of deletion. |
| Booking → BookingDecision | `ON DELETE NO ACTION` | `ON UPDATE NO ACTION` | Preserve approval/rejection audit history. |
| Space → BookingPolicy | `ON DELETE NO ACTION` | `ON UPDATE NO ACTION` | Retain policies until explicitly retired or reassigned. |

Physical enforcement must also serialize approval and maintenance activation transactions. Before approving, it must reject overlapping effective intervals for the same space against `approved`/`checked in` bookings and active maintenance, and reject spaces whose status is under maintenance, temporarily closed, or retired. Status-transition and role-authorization rules require stored procedures or triggers because they span rows and tables.
