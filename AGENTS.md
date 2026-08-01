# Repository Guidelines

## Project Structure & Deliverables

This repository contains the Phase 2 database design for a Campus Space Management System (CSMS). The source requirements are in `reference/spec_phase1.md`. Task-specific workflow instructions are in `.codex/skills/` and are numbered in dependency order.

Place generated deliverables in `outputs/` using the required names, such as `outputs/01-business-req-analysis-G13.md` and `outputs/05-db-definition-G13.sql`. Create `outputs/` when needed; do not edit the Phase 1 specification to record design decisions. `docker-compose.yml` provides the local SQL Server service.

## Build, Test, and Development Commands

- `docker compose up -d` starts SQL Server 2022 on `localhost:1433`.
- `docker compose ps` confirms that the database container is running.
- `docker compose down` stops the local service after use.
- `sqlcmd -S localhost,1433 -U sa -P '<password>' -i outputs/05-db-definition-G13.sql` applies the DDL once `sqlcmd` is installed.
- Run the sample data script the same way, replacing the `-i` path with `outputs/06-sample-data-G13.sql`.

Do not commit real credentials. Use the Compose configuration only for local development and override secrets through an untracked environment file when appropriate.

## Database Design & SQL Conventions

Follow the numbered workflow: requirements analysis, ERD, logical design, validation, DDL, sample data, then queries. Keep documentation headings aligned with the templates in `.codex/skills/`.

Write SQL Server-compatible, idempotent DDL. Use clear `PascalCase` table names (for example, `BookingRequest`) and descriptive `snake_case` constraint or index names (for example, `ck_booking_end_after_start`). Indent SQL by four spaces, put one column or constraint per line, and use explicit `PRIMARY KEY`, `FOREIGN KEY`, `UNIQUE`, and `CHECK` constraints. Always enforce `end_time > start_time` and model booking conflicts and unavailable-space rules explicitly.

## Validation and Testing

Before submitting, apply DDL to a clean local SQL Server instance, load sample data, and run every query script. Verify foreign keys, status checks, time ordering, and representative edge cases: overlapping approved bookings, bookings during maintenance, rejection, cancellation, check-in/out, and no-shows. SQL scripts should execute in dependency order without manual edits.

## Commits and Pull Requests

Git history is not available in this checkout, so use concise imperative commits scoped to the deliverable, such as `Add normalized booking schema` or `Validate maintenance constraints`. Keep each commit focused. Pull requests should summarize the affected deliverables, explain key rule or schema decisions, list verification commands/results, and include rendered Mermaid screenshots when an ERD changes.
