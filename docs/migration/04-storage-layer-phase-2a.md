# Phase 2A - Storage abstraction layer

Created:
- apps/ml-worker/storage/backend.py
- apps/ml-worker/storage/local_backend.py
- apps/ml-worker/storage/s3_backend.py
- apps/ml-worker/storage/supabase_backend.py

Goal:
- unify remote/local storage access
- prepare client-runtime local mode
- decouple ML worker from direct Supabase-only storage usage

Next:
- refactor data_access_v1.py
- refactor export_features_dense.py
- refactor priors upload/download scripts

Phase 2C completed:
- refactored jobs/upload_priors_to_supabase.py
- refactored jobs/download_priors_from_supabase.py
- both now use storage.backend.get_storage_backend()
- local mode test completed for priors upload/download via python -m jobs.*
