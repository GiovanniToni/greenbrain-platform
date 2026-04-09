# Runtime Status Post Update

## Release
2026.04.06-runtime-ml-local-v1

## Current mode
# Client Runtime Mode

## Stato corrente
Il client-runtime è considerato operativo in modalità:

- local demo / local validation
- ML runtime attivo
- ETL reale cliente non configurato
- nessuna schedulazione automatica attiva

## Cosa è validato
- export parquet locale
- train locale
- predict locale
- scrittura forecast su greenhouse_forecast_results_v2
- logging ml_ops
- t_ops_pipeline_monitor
- storage locale

## Cosa non è ancora validato
- sorgente SQL Server reale cliente
- ETL incrementale reale
- nightly end-to-end reale cliente

## Regola operativa
Fino a configurazione di una sorgente cliente reale:
- train manuale
- predict manuale
- export manuale
- ETL bloccato con safe-stop
- nessun cron automatico

## Latest package
/opt/greenbrain-platform/client-runtime/release/package_20260406_190011

## Crontab
crontab vuoto

## Pipeline runs
                run_id                |    job_type    | status  |          started_at           |          finished_at          | rows_processed |                                    notes                                     
--------------------------------------+----------------+---------+-------------------------------+-------------------------------+----------------+------------------------------------------------------------------------------
 1c3491c4-d759-47bc-a79a-7ddc3d8fd3c1 | predict_family | success | 2026-04-06 17:00:26.624405+00 | 2026-04-06 17:00:29.287582+00 |             20 | family=rosa slug=rosa rows_written=20 fallback_used=True
 ce242732-2129-480c-b072-7dba0dee01b7 | train_family   | success | 2026-04-06 17:00:24.45617+00  | 2026-04-06 17:00:26.124682+00 |              1 | family=rosa slug=rosa
 4d687977-d21c-4826-bd24-4f8eada2a28a | predict_family | success | 2026-04-06 16:54:04.081391+00 | 2026-04-06 16:54:07.012866+00 |             20 | family=rosa slug=rosa rows_written=20 fallback_used=True
 115cb0c4-02fd-4155-9c67-1095cb517814 | train_family   | success | 2026-04-06 16:54:01.667551+00 | 2026-04-06 16:54:03.628344+00 |              1 | family=rosa slug=rosa
 246a4094-aba9-43b9-b103-e259c6129d03 | train_family   | success | 2026-04-06 15:35:09.113141+00 | 2026-04-06 15:35:10.746981+00 |              1 | family=ficus elastica slug=ficus-elastica
 17fad79b-d379-4639-8fcb-0a93782e06ff | train_family   | success | 2026-04-06 15:35:06.963133+00 | 2026-04-06 15:35:08.605809+00 |              1 | family=lavanda slug=lavanda
 c76fb302-6aae-4e96-915e-0ba8b17c18ae | train_family   | success | 2026-04-06 15:35:04.839193+00 | 2026-04-06 15:35:06.496226+00 |              1 | family=rosa slug=rosa
 2ac0a96b-1f46-4082-8837-0cfb94f56042 | predict_family | success | 2026-04-06 15:13:26.582583+00 | 2026-04-06 15:13:29.192+00    |             20 | family=ficus elastica slug=ficus-elastica rows_written=20 fallback_used=True
 a4c8a771-89bb-4811-89bb-618838aa2ef1 | predict_family | success | 2026-04-06 15:13:23.602076+00 | 2026-04-06 15:13:26.164079+00 |             20 | family=lavanda slug=lavanda rows_written=20 fallback_used=True
 8b440b05-d89a-4826-9297-bee3253b1c95 | predict_family | success | 2026-04-06 15:13:20.355333+00 | 2026-04-06 15:13:23.159968+00 |             20 | family=rosa slug=rosa rows_written=20 fallback_used=True
(10 rows)


## Family runs
            family_run_id             |           pipeline_run_id            |  family_name   |    job_type    | status  | rows_written |                     artifact_path                      
--------------------------------------+--------------------------------------+----------------+----------------+---------+--------------+--------------------------------------------------------
 5f968240-98f4-41d5-afad-70bc172aaff0 | 1c3491c4-d759-47bc-a79a-7ddc3d8fd3c1 | rosa           | predict_family | success |           20 | 
 4b3f394c-a09f-499e-9717-ed21457903b4 | ce242732-2129-480c-b072-7dba0dee01b7 | rosa           | train_family   | success |            1 | /opt/greenbrain/models_v4/bundle_rosa_v4.pkl
 3777c26d-9c8c-4076-ac73-24cb12b1f28b | 4d687977-d21c-4826-bd24-4f8eada2a28a | rosa           | predict_family | success |           20 | 
 dbf44070-0dfc-4638-8f90-ec6aa97658ad | 115cb0c4-02fd-4155-9c67-1095cb517814 | rosa           | train_family   | success |            1 | /opt/greenbrain/models_v4/bundle_rosa_v4.pkl
 dddbc4aa-a4a8-45d0-aa32-857b5cb4aeb7 | 246a4094-aba9-43b9-b103-e259c6129d03 | ficus elastica | train_family   | success |            1 | /opt/greenbrain/models_v4/bundle_ficus-elastica_v4.pkl
 270091ed-a348-4791-b46b-2ba7b411676f | 17fad79b-d379-4639-8fcb-0a93782e06ff | lavanda        | train_family   | success |            1 | /opt/greenbrain/models_v4/bundle_lavanda_v4.pkl
 15bbdeb8-6344-402e-b2f1-f02cb4afdfa7 | c76fb302-6aae-4e96-915e-0ba8b17c18ae | rosa           | train_family   | success |            1 | /opt/greenbrain/models_v4/bundle_rosa_v4.pkl
 1f3b4ff8-a764-483e-a43c-936e881e134e | 2ac0a96b-1f46-4082-8837-0cfb94f56042 | ficus elastica | predict_family | success |           20 | 
 581b3a90-522b-47b7-9204-aa7f1f5ef19c | a4c8a771-89bb-4811-89bb-618838aa2ef1 | lavanda        | predict_family | success |           20 | 
 a9bb13ca-1ecf-464d-bc34-c7e7d58ff83b | 8b440b05-d89a-4826-9297-bee3253b1c95 | rosa           | predict_family | success |           20 | 
(10 rows)


## Monitor
 id |            snap_ts            | ok 
----+-------------------------------+----
 82 | 2026-04-06 17:00:29.307118+00 | t
 81 | 2026-04-06 17:00:29.287582+00 | f
 80 | 2026-04-06 17:00:26.144031+00 | t
 79 | 2026-04-06 17:00:26.124682+00 | f
 78 | 2026-04-06 16:54:07.032752+00 | t
 77 | 2026-04-06 16:54:07.012866+00 | f
 76 | 2026-04-06 16:54:03.649025+00 | t
 75 | 2026-04-06 16:54:03.628344+00 | f
 74 | 2026-04-06 15:35:10.769192+00 | t
 73 | 2026-04-06 15:35:10.746981+00 | f
(10 rows)

