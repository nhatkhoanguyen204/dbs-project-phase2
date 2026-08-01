# Group 13 Synthetic Benchmark Data Generator

Run generate_dataset.sql after the base DDL, Phase 2 migration, and concurrency implementation. Use a clean disposable benchmark database: the generator refuses to run if an earlier G13-BENCH dataset exists.

The default variable creates 100,000 bookings across the 2023-2025 academic years. Change only the first variable to 500000 for the largest required benchmark:

    DECLARE @booking_count INT = 500000;

The generated data includes:

- 80 to 417 dedicated benchmark spaces, depending on scale;
- 1,000 active requester and facility accounts;
- academic-day, peak-hour, non-overlapping booking intervals;
- Approved, Completed, Pending, Rejected, Cancelled, and NoShow lifecycle distributions;
- decision and cancellation audit data;
- completed out-of-service maintenance history;
- active advisory maintenance plus corresponding acknowledgement rows.

Distribution: bookings occur only in January-May and August-December, on weekdays, with two peak starts per academic day (09:00 and 13:00). At default scale, the status mix is 70% Approved, 10% Completed, 5% NoShow, 8% Cancelled, 5% Rejected, and 2% Pending.

Example:

    /opt/mssql-tools/bin/sqlcmd -S localhost,1433 -U sa -P '<password>' -C -d CSMSBenchmark -b -i outputs/14-data-generator-G13/generate_dataset.sql

The script is intentionally not rerunnable against the same benchmark dataset; this prevents accidental duplication. Create a new benchmark database for a new scale/run. After generation, run the count queries printed by the script. The 500,000-row option is intended for the indexing benchmarks in later deliverables.
