#!/usr/bin/env python3
"""
Extract GreenBrain client-runtime schema DDL from a pg_dump --schema-only file.

Filters OUT Supabase-specific schemas (auth, storage, realtime, vault, graphql, pgbouncer).
Filters IN only the objects the backend actually needs.

Usage:
    python3 extract-schema.py <input.sql> <output_dir/>

Outputs (apply in alphabetical order):
    01_schemas.sql     — CREATE SCHEMA
    02_extensions.sql  — CREATE EXTENSION (pg_trgm, uuid-ossp)
    03_types.sql       — custom types / domains
    04_sequences.sql   — sequences
    05_tables.sql      — CREATE TABLE for all needed tables
    06_views.sql       — CREATE OR REPLACE VIEW
    07_matviews.sql    — CREATE MATERIALIZED VIEW (ml_diag — optional)
    08_functions.sql   — CREATE OR REPLACE FUNCTION
    extraction-report.txt — what was kept, what was skipped
"""

import re
import sys
from pathlib import Path
from collections import defaultdict

# Schemas to include in extraction
INCLUDE_SCHEMAS = {"public", "ml_ops", "etl", "ml_forecast"}
# ml_diag excluded: diagnostic-only materialized views, no backend endpoint uses them,
# and they have unresolvable internal dependencies (intermediate views not in the snapshot)

# Schemas that are Supabase-specific — skip entirely
EXCLUDE_SCHEMAS = {
    "auth", "storage", "realtime", "extensions", "graphql",
    "graphql_public", "pgbouncer", "vault", "_realtime",
}

# Object types to skip unconditionally
SKIP_TYPES = {
    "POLICY",
    "ROW SECURITY",
    "TRIGGER",
    "EVENT TRIGGER",
    "PUBLICATION",
    "SUBSCRIPTION",
    "DEFAULT ACL",
    "ACL",
    "COMMENT",
    "PROCEDURAL LANGUAGE",
    "SERVER",
    "FOREIGN DATA WRAPPER",
    "USER MAPPING",
}

# Extensions we want to keep for client-runtime PostgreSQL
KEEP_EXTENSIONS = {"pg_trgm", "uuid-ossp", "btree_gin", "btree_gist", "pgcrypto"}

# Extensions to skip (Supabase-only)
SKIP_EXTENSIONS = {"pgsodium", "pg_net", "pg_graphql", "supabase_vault", "pgjwt", "pg_stat_monitor", "hypopg"}


def parse_blocks(sql_content: str):
    """
    Split pg_dump output into individual object blocks.
    Each block starts with:
        --
        -- Name: <name>; Type: <TYPE>; Schema: <schema>; Owner: -
        --
    """
    # Split on the separator comment lines
    raw_blocks = re.split(r"\n(?=--\n-- Name: )", sql_content)
    return raw_blocks


def parse_header(block: str):
    """
    Extract (name, obj_type, schema) from a pg_dump block header.
    Returns None if no header found.
    """
    m = re.search(
        r"-- Name:\s*(.+?);\s*Type:\s*(.+?);\s*Schema:\s*(.+?)(?:;|$)",
        block,
        re.MULTILINE,
    )
    if not m:
        return None
    return m.group(1).strip(), m.group(2).strip(), m.group(3).strip()


def classify(name: str, obj_type: str, schema: str):
    """Return the output bucket for this object, or None to skip."""
    # Skip excluded schema objects entirely
    if schema in EXCLUDE_SCHEMAS:
        return None

    # Skip unconditional types
    if obj_type in SKIP_TYPES:
        return None

    # Schemas — only the ones we care about
    if obj_type == "SCHEMA":
        return "schemas" if name in INCLUDE_SCHEMAS else None

    # Extensions — keep only the safe subset
    if obj_type == "EXTENSION":
        if name in KEEP_EXTENSIONS:
            return "extensions"
        return None

    # Tables in included schemas
    if obj_type == "TABLE":
        if schema in INCLUDE_SCHEMAS:
            return "tables"
        return None

    # Views in included schemas
    if obj_type in ("VIEW", "VIEW WITHOUT OID"):
        if schema in INCLUDE_SCHEMAS:
            return "views"
        return None

    # Materialized views in included schemas
    if obj_type == "MATERIALIZED VIEW":
        if schema in INCLUDE_SCHEMAS:
            return "matviews"
        return None

    # Functions and procedures in included schemas
    if obj_type in ("FUNCTION", "PROCEDURE", "AGGREGATE"):
        if schema in INCLUDE_SCHEMAS:
            return "functions"
        return None


    # Sequences in included schemas
    if obj_type == "SEQUENCE":
        if schema in INCLUDE_SCHEMAS:
            return "sequences"
        return None

    # Types and domains in included schemas
    if obj_type in ("TYPE", "DOMAIN", "ENUM"):
        if schema in INCLUDE_SCHEMAS:
            return "types"
        return None

    # Indexes in included schemas — skip for now (tables handle their own PKs)
    if obj_type == "INDEX":
        return None

    # Constraints are part of the table DDL already
    if "CONSTRAINT" in obj_type:
        return None

    # Sequence ownership — skip
    if "OWNED BY" in obj_type or "SEQUENCE SET" in obj_type:
        return None

    return None


def extract(sql_path: Path, out_dir: Path):
    content = sql_path.read_text(encoding="utf-8")
    blocks = parse_blocks(content)

    buckets = defaultdict(list)
    kept = defaultdict(int)
    skipped = defaultdict(int)

    for block in blocks:
        header = parse_header(block)
        if not header:
            continue
        name, obj_type, schema = header
        bucket = classify(name, obj_type, schema)
        if bucket:
            cleaned = strip_rls(block)
            cleaned = sanitise_for_standard_postgres(cleaned)
            # Skip views/functions whose body references an excluded schema
            # or references public materialized views (mv_*) which have
            # unresolvable intermediate dependencies
            if bucket in ("views", "functions", "matviews"):
                refs_excluded = any(
                    f"{excl}." in cleaned
                    for excl in (EXCLUDE_SCHEMAS | {"ml_diag"})
                )
                refs_matview = bool(re.search(r'\bpublic\.mv_\w+', cleaned))
                if refs_excluded or refs_matview:
                    skipped[f"{obj_type}(cross-ref-excluded)"] += 1
                    continue
            buckets[bucket].append((name, schema, cleaned))
            kept[obj_type] += 1
        else:
            skipped[obj_type] += 1

    return buckets, kept, skipped


def strip_rls(block: str) -> str:
    """Remove ALTER TABLE ... ENABLE ROW LEVEL SECURITY lines."""
    lines = block.splitlines()
    out = []
    for line in lines:
        if "ENABLE ROW LEVEL SECURITY" in line:
            continue
        if "FORCE ROW LEVEL SECURITY" in line:
            continue
        out.append(line)
    return "\n".join(out)


def sanitise_for_standard_postgres(block: str) -> str:
    """Fix Supabase-specific patterns that break on standard PostgreSQL."""
    # Supabase puts extensions in a dedicated 'extensions' schema; standard
    # PostgreSQL has no such schema — redirect to public.
    block = block.replace("WITH SCHEMA extensions", "WITH SCHEMA public")
    return block


FILE_MAP = {
    "schemas":    ("01_schemas.sql",    "Schema declarations"),
    "extensions": ("02_extensions.sql", "PostgreSQL extensions"),
    "types":      ("03_types.sql",      "Custom types and domains"),
    "sequences":  ("04_sequences.sql",  "Sequences"),
    "tables":     ("05_tables.sql",     "Table definitions"),
    "matviews":   ("06_matviews.sql",   "Materialized views (optional)"),
    "views":      ("07_views.sql",      "Views"),
    "functions":  ("08_functions.sql",  "Functions and RPCs"),
}

HEADER = """\
-- GreenBrain Client Runtime — {description}
-- Extracted from Supabase/local schema snapshot (sql/schema/current-schema.sql)
-- Wave 7B — DO NOT hand-edit; re-run extract-schema.py to regenerate
--
-- Apply order: 01 → 02 → 03 → 04 → 05 → 06 → 07 → 08
-- (tables before views, views before functions)
--
"""


def write_outputs(buckets, out_dir: Path):
    out_dir.mkdir(parents=True, exist_ok=True)
    summary = []

    for bucket, (filename, description) in FILE_MAP.items():
        items = buckets.get(bucket, [])
        out_path = out_dir / filename
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(HEADER.format(description=description))
            for name, schema, block in items:
                f.write(block.rstrip())
                f.write("\n\n")
        summary.append(f"  {filename}: {len(items):3d} objects — {description}")
        print(f"  {filename}: {len(items)} objects")

    return summary


def write_report(buckets, kept, skipped, out_dir: Path, source: str):
    report_path = out_dir.parent / "extraction-report.txt"
    lines = [
        "GreenBrain Schema Extraction Report",
        f"Source: {source}",
        "",
        "=== KEPT ===",
    ]
    for t, c in sorted(kept.items()):
        lines.append(f"  {c:4d}  {t}")
    lines += ["", "=== SKIPPED (counts only) ==="]
    for t, c in sorted(skipped.items()):
        lines.append(f"  {c:4d}  {t}")
    lines += ["", "=== BUCKET SUMMARY ==="]
    for bucket, (filename, description) in FILE_MAP.items():
        lines.append(f"  {filename}: {len(buckets.get(bucket, []))} objects")

    report_path.write_text("\n".join(lines) + "\n")
    print(f"\nReport written to: {report_path}")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <input.sql> <output_dir/>")
        sys.exit(1)

    sql_path = Path(sys.argv[1])
    out_dir = Path(sys.argv[2])

    if not sql_path.exists():
        print(f"ERROR: input file not found: {sql_path}")
        sys.exit(1)

    print(f"Reading {sql_path.name} ({sql_path.stat().st_size // 1024} KB)...")
    buckets, kept, skipped = extract(sql_path, out_dir)

    print(f"\nWriting to {out_dir}/")
    summary = write_outputs(buckets, out_dir)

    write_report(buckets, kept, skipped, out_dir, str(sql_path))
    print("\nDone.")
