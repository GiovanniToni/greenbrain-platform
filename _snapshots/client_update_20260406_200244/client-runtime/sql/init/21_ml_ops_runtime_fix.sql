CREATE EXTENSION IF NOT EXISTS pgcrypto;

ALTER TABLE ml_ops.pipeline_run_log_v1
    ALTER COLUMN run_id SET DEFAULT gen_random_uuid()::text;

ALTER TABLE ml_ops.family_run_log_v1
    ALTER COLUMN family_run_id SET DEFAULT gen_random_uuid()::text;

ALTER TABLE ml_ops.pipeline_run_log_v1
    ALTER COLUMN started_at SET DEFAULT now();

ALTER TABLE ml_ops.family_run_log_v1
    ALTER COLUMN started_at SET DEFAULT now();

ALTER TABLE ml_ops.pipeline_run_log_v1
    ADD COLUMN IF NOT EXISTS env_snapshot jsonb;

CREATE TABLE IF NOT EXISTS ml_ops.job_schedule_config_v1 (
    job_type TEXT PRIMARY KEY,
    is_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    cron_expr TEXT,
    notes TEXT
);

INSERT INTO ml_ops.job_schedule_config_v1 (job_type, is_enabled, notes)
VALUES
    ('predict_daily', TRUE, 'default enabled'),
    ('predict_family', TRUE, 'default enabled'),
    ('train_batch', TRUE, 'default enabled'),
    ('train_family', TRUE, 'default enabled'),
    ('parquet_export', TRUE, 'default enabled')
ON CONFLICT (job_type) DO NOTHING;
