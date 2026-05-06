Parquet exporter per greenhouse_forecast_features_dense.

Output:
- bucket: ml-snapshots
- path: features_dense/v1/year=YYYY/famiglia_slug=<slug>/part.parquet

Aggiorna:
- public.ops_parquet_export_runs
- public.ops_parquet_export_state

Usa il file env del server:
- /opt/greenhouse/.env
