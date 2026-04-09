# pg_cron fix — wave 1

Disabled duplicate every-minute jobs:
- job 30
- job 38
- job 39

Reason:
- duplicate ETL triggering
- unnecessary Supabase load
- canonical jobs remain active

Date:
- 2026-04-01
