# Release Checklist

## Prima del package
- py_compile ok
- export runtime ok
- train runtime ok
- predict runtime ok
- ml_ops log ok
- forecast write ok

## Package
- aggiornare runtime_manifest.txt
- eseguire package_client_runtime.sh
- annotare PACKAGE_DIR
- annotare PACKAGE_TAR
- aggiornare RELEASE_VERSION
- aggiornare RELEASE_NOTES.md

## Update client
- snapshot automatico ok
- apply package ok
- apply SQL ok
- validate_client_runtime.sh ok

## Test post-update
- run_export_runtime.sh
- run_train_runtime.sh "rosa"
- run_predict_runtime.sh "rosa"

## Regola
- .env cliente non va sovrascritto
- ETL reale non si attiva finché la sorgente è placeholder
- nessun cron attivo finché non deciso esplicitamente
