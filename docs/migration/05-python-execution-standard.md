# Python execution standard

Rule:
- execute Python jobs from apps/ml-worker root
- use module form: python -m jobs.<module>
- do not execute job files directly with python jobs/file.py

Why:
- ensures root package imports work (`storage`, `jobs`, future shared libs)
- makes monorepo and client-runtime consistent
- avoids PYTHONPATH ambiguity
