# Agent Skills Definition

## Skill 1: Business Requirements Analysis

* **Description**: Extracts CSMS actors, authorization scopes, entities, attributes, relationship cardinalities, and explicit booking/maintenance rules.
* **Triggers**: Requests to analyze CSMS requirements, business rules, or domain constraints.
* **Inputs**:
    * `requirements_source` (Markdown): Source system specification.
* **Outputs**:
    * Structured business requirements analysis with rule and edge-case coverage.

## Skill 2: Conceptual ERD Design

* **Description**: Converts approved business requirements into a conceptual Mermaid ERD.
* **Triggers**: Requests for an ERD, conceptual data model, entities, or cardinalities.
* **Inputs**:
    * `requirements_analysis` (Markdown): Approved CSMS business-rule analysis.
* **Outputs**:
    * Entity definitions, relationship matrix, and Mermaid `erDiagram` code.

## Skill 3: Logical Database Design

* **Description**: Maps conceptual entities into normalized SQL Server-oriented relations with precise keys, types, and referential rules.
* **Triggers**: Requests for a relational schema, logical model, key mapping, or normalization-ready table design.
* **Inputs**:
    * `requirements_analysis` (Markdown): CSMS requirements and rules.
    * `conceptual_erd` (Markdown): Approved conceptual ERD.
* **Outputs**:
    * Relational schema map, table specifications, and referential-integrity decisions.

## Skill 4: Design Validation & Normalization

* **Description**: Checks business-rule traceability, functional dependencies, 3NF/BCNF compliance, and transaction edge cases.
* **Triggers**: Requests to validate a database design, prove normalization, or assess booking conflicts and maintenance behavior.
* **Inputs**:
    * `requirements_analysis` (Markdown): Business-rule baseline.
    * `logical_design` (Markdown): Proposed relational schema.
* **Outputs**:
    * Traceability matrix, normalization assessment, edge-case analysis, and implementation recommendations.

## Skill 5: SQL Server Database Definition

* **Description**: Produces idempotent Microsoft SQL Server DDL with tables, keys, checks, indexes, and integrity triggers.
* **Triggers**: Requests to create, implement, or validate CSMS SQL Server DDL.
* **Inputs**:
    * `logical_design` (Markdown): Validated relation and key definitions.
    * `validation_report` (Markdown): Enforcement and trade-off recommendations.
* **Outputs**:
    * Standalone `.sql` DDL script and local execution result when SQL Server is available.

## Skill 6: Sample Data Generation

* **Description**: Creates deterministic, idempotent reference and operational seed data for the CSMS schema.
* **Triggers**: Requests for seed data, mock data, test fixtures, or lifecycle examples.
* **Inputs**:
    * `database_definition` (SQL): Tested CSMS DDL.
* **Outputs**:
    * SQL seed script covering pending, approved, rejected, cancelled, checked-in, completed, no-show, and maintenance scenarios.

## Skill 7: Operational Query Design

* **Description**: Builds documented read-only SQL Server queries for availability, utilization, conflicts, requester behavior, maintenance, policy, and audit reporting.
* **Triggers**: Requests for CSMS reports, dashboards, analytics, availability searches, or data-quality queries.
* **Inputs**:
    * `requirements_analysis` (Markdown): Reporting and operational requirements.
    * `database_definition` (SQL): Executable schema.
    * `sample_data` (SQL, optional): Scenario data for query validation.
* **Outputs**:
    * Executable SQL query suite with target user, utility, and expected-insight comments.

## Skill 8: Requirement Change Analysis

* **Description**: Assesses maintenance impact levels, advisory acknowledgements, escalations, and their effects on entities, rules, and reports.
* **Outputs**: Change-impact analysis, updated business rules, and concurrency-risk inventory.

## Skill 9: Updated ERD and Logical Design

* **Description**: Extends the logical model with impact history, acknowledgement evidence, and booking-impact work items; documents functional dependencies and 3NF.
* **Outputs**: Updated ERD, relational schema notation, key/foreign-key constraints, and normalization proof.

## Skill 10: Schema Migration

* **Description**: Produces idempotent, transactional SQL Server migrations that preserve Phase 1 history while adding Phase 2 structures.
* **Outputs**: Executable migration DDL, defaults/checks/FKs, metadata comments, and compatibility handling.

## Skill 11: Concurrency Design

* **Description**: Designs a serializable availability protocol for auto approvals, manual approvals, and maintenance escalation.
* **Outputs**: Anomaly analysis, isolation/lock trade-offs, deadlock-order rules, and acceptance criteria.

## Skill 12: Concurrency Implementation

* **Description**: Implements SQL Server procedures using sp_getapplock, guarded status transitions, advisory acknowledgement, and escalation impact creation.
* **Outputs**: Executable procedures for booking creation, approval, and maintenance impact updates.

## Skill 13: Concurrency Tests

* **Description**: Provides isolated dual-session SQL fixtures for conflict, acknowledgement, escalation, and rollback-only unsafe-baseline demonstrations.
* **Outputs**: Setup/session/verification scripts and an execution README.

## Skill 14: Synthetic Data Generation

* **Description**: Generates 100,000–500,000 constraint-valid bookings across three academic years with lifecycle, maintenance, and acknowledgement distributions.
* **Outputs**: Parameterized SQL generator and execution instructions.

## Skill 15: Index Tuning

* **Description**: Profiles conflict, Room Finder, and reporting query paths with SQL Server STATISTICS IO/TIME and documents index trade-offs.
* **Outputs**: Before/after execution evidence, index DDL, and tuning report.

## Skill 16: Analytical Queries

* **Description**: Implements parameterized semester utilization, usage-distribution, Room Finder, and escalation-impact reports.
* **Outputs**: Read-only SQL Server report suite aligned with Phase 2 Section 1.3.

## Implementation Notes (Codex Execution)

* Skills 1-16 are represented by the completed CSMS outputs from 01-business-req-analysis-G13.md through 16-analytical-queries-G13.sql.
* The runtime target is Microsoft SQL Server 2022 using the repository `docker-compose.yml`; scripts use `DATETIME2`, `NVARCHAR`, `CHECK` constraints, SQL Server triggers, and `GO` batch separators.
* The implementation was validated with idempotent migration reruns, dual-session concurrency tests, a 100,000-row benchmark generator, index measurements, and the required Phase 2 analytical query suite.
