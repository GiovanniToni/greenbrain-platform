"""Dataset build orchestration package for GreenBrain ML worker.

Initial scope:
- provide a safe dry-run scaffold for the future `gb dataset build-global`
  command;
- do not execute R3A/R3B/R3C/R3D/R3D2 pipeline steps yet;
- do not write to DB, staging tables, final forecast tables, Docker, or systemd.
"""

__all__ = [
    "manifest",
    "validation",
]
