#!/usr/bin/env python3
"""
model_control.py — Strumento di governance per l'assegnazione dei modelli forecast.

Azioni ufficiali:
  assign-model-to-family    --family <nome> --model <code> [--lock] [--reason <testo>] [--force]
                            [--dry-run] [--run-now]
  assign-model-to-class     --class <demand_class> --model <code> [--lock] [--reason <testo>]
                            [--force] [--dry-run] [--run-now]
  assign-model-to-all       --model <code> [--lock] [--reason <testo>] [--force] [--dry-run] [--yes]
  apply-best-suggested-model --family <nome> [--dry-run] [--force]

Flag comuni:
  --dry-run   Mostra cosa succederebbe senza eseguire nulla.
  --run-now   Dopo il commit, esegue subito train + predict per le famiglie cambiate.
  --yes       Salta la conferma interattiva (solo assign-model-to-all).
  --force     Ignora il flag is_locked sulla famiglia.

Regole di sicurezza:
  - Le famiglie con is_locked=TRUE vengono saltate, a meno che non si usi --force.
  - Ogni cambio viene scritto in family_model_assignment_log_v1 (log immutabile).
  - Ogni cambio imposta needs_retrain=TRUE e needs_predict=TRUE in family_model_state_v1.
  - execution_engine NON viene salvato in family_model_assignment_v1:
    viene sempre derivato tramite model_engine_map_v1.
"""
from __future__ import annotations

import os
import sys
import argparse
import subprocess

import sqlalchemy as sa
from sqlalchemy.engine import URL
from dotenv import load_dotenv

load_dotenv("/opt/greenhouse/.env")

REPO_DIR = os.getenv("GH_REPO_DIR", "/opt/greenbrain-platform/apps/ml-worker")
sys.path.insert(0, REPO_DIR)


# ──────────────────────────────────────────────
# DB
# ──────────────────────────────────────────────

def _get_engine():
    dburl = os.getenv("DATABASE_URL")
    if dburl:
        return sa.create_engine(dburl, pool_pre_ping=True)
    url = URL.create(
        "postgresql+psycopg",
        username=os.getenv("PG_USER"),
        password=os.getenv("PG_PASSWORD"),
        host=os.getenv("PG_HOST"),
        port=int(os.getenv("PG_PORT", "5432")),
        database=os.getenv("PG_DB", "postgres"),
        query={"sslmode": os.getenv("PG_SSLMODE", "require")},
    )
    return sa.create_engine(url, pool_pre_ping=True)


# ──────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────

def _validate_model_code(conn, model_code: str) -> bool:
    row = conn.execute(
        sa.text("SELECT 1 FROM ml_forecast.model_catalog_v1 WHERE model_code = :mc"),
        {"mc": model_code},
    ).first()
    return row is not None


def _upsert_assignment(
    conn,
    family_name: str,
    model_code: str,
    is_locked: bool,
    assigned_by: str,
    reason: str | None,
    notes: str | None,
    force: bool = False,
) -> dict:
    """
    Upsert dell'assignment per una famiglia singola.
    Restituisce un dict con l'azione eseguita.
    Salta famiglie locked a meno che force=True.
    """
    current = conn.execute(
        sa.text("""
            SELECT model_code, is_locked
            FROM ml_forecast.family_model_assignment_v1
            WHERE family_name = :fn
        """),
        {"fn": family_name},
    ).mappings().first()

    if current and current["is_locked"] and not force:
        return {"family": family_name, "action": "skipped_locked"}

    old_model_code = current["model_code"] if current else None
    old_is_locked  = current["is_locked"]  if current else None

    if (
        current
        and current["model_code"] == model_code
        and current["is_locked"] == is_locked
    ):
        return {"family": family_name, "action": "no_change"}

    conn.execute(
        sa.text("""
            INSERT INTO ml_forecast.family_model_assignment_v1 (
                family_name, model_code, is_locked,
                assigned_by, assigned_at, assignment_reason, notes
            ) VALUES (
                :fn, :mc, :locked,
                :by, now(), :reason, :notes
            )
            ON CONFLICT (family_name) DO UPDATE SET
                model_code        = EXCLUDED.model_code,
                is_locked         = EXCLUDED.is_locked,
                assigned_by       = EXCLUDED.assigned_by,
                assigned_at       = EXCLUDED.assigned_at,
                assignment_reason = EXCLUDED.assignment_reason,
                notes             = EXCLUDED.notes
        """),
        {
            "fn": family_name, "mc": model_code, "locked": is_locked,
            "by": assigned_by, "reason": reason, "notes": notes,
        },
    )

    conn.execute(
        sa.text("""
            INSERT INTO ml_forecast.family_model_assignment_log_v1 (
                family_name, old_model_code, new_model_code,
                old_is_locked, new_is_locked, changed_by, reason
            ) VALUES (
                :fn, :old_mc, :new_mc,
                :old_locked, :new_locked, :by, :reason
            )
        """),
        {
            "fn": family_name,
            "old_mc": old_model_code, "new_mc": model_code,
            "old_locked": old_is_locked, "new_locked": is_locked,
            "by": assigned_by, "reason": reason,
        },
    )

    conn.execute(
        sa.text("""
            UPDATE ml_forecast.family_model_state_v1
            SET needs_retrain = TRUE,
                needs_predict  = TRUE
            WHERE family_name = :fn
        """),
        {"fn": family_name},
    )

    action = "updated" if current else "inserted"
    return {
        "family": family_name,
        "action": action,
        "old_model": old_model_code,
        "new_model": model_code,
        "is_locked": is_locked,
    }


def _resolve_family_name(conn, raw: str) -> str | None:
    row = conn.execute(
        sa.text("""
            SELECT family_name
            FROM ml_forecast.family_model_registry_v2
            WHERE lower(trim(family_name)) = lower(trim(:fn))
        """),
        {"fn": raw},
    ).first()
    return row[0] if row else None


def _preview_assignment(
    conn,
    family_name: str,
    model_code: str,
    is_locked: bool,
    force: bool = False,
) -> dict:
    """Calcola cosa farebbe _upsert_assignment senza scrivere nulla."""
    current = conn.execute(
        sa.text("""
            SELECT model_code, is_locked
            FROM ml_forecast.family_model_assignment_v1
            WHERE family_name = :fn
        """),
        {"fn": family_name},
    ).mappings().first()

    if current and current["is_locked"] and not force:
        return {"action": "skipped_locked", "old_model": current["model_code"]}
    if current and current["model_code"] == model_code and current["is_locked"] == is_locked:
        return {"action": "no_change",      "old_model": current["model_code"]}
    action = "updated" if current else "inserted"
    return {"action": action, "old_model": current["model_code"] if current else None}


def _run_train_predict(family_name: str) -> tuple[int, int]:
    """
    Esegue train + predict per una famiglia come sottoprocesso.
    Restituisce (train_rc, predict_rc). predict_rc=-1 se train fallisce.
    """
    repo = os.getenv("GH_REPO_DIR", "/opt/greenbrain-platform/apps/ml-worker")
    py   = sys.executable

    print(f"  [run-now] train   '{family_name}'")
    t_rc = subprocess.run(
        [py, os.path.join(repo, "jobs/train_family_router.py"), "--family", family_name],
        cwd=repo,
    ).returncode
    if t_rc != 0:
        print(f"  [run-now] WARN train fallito rc={t_rc}", file=sys.stderr)
        return t_rc, -1

    print(f"  [run-now] predict '{family_name}'")
    p_rc = subprocess.run(
        [py, os.path.join(repo, "jobs/predict_family_router.py"),
         "--family", family_name, "--write_db", "1"],
        cwd=repo,
    ).returncode
    if p_rc != 0:
        print(f"  [run-now] WARN predict fallito rc={p_rc}", file=sys.stderr)
    return t_rc, p_rc


# ──────────────────────────────────────────────
# Azioni
# ──────────────────────────────────────────────

def action_assign_to_family(conn, args) -> tuple[int, list[str]]:
    if not _validate_model_code(conn, args.model):
        print(f"ERROR: model_code '{args.model}' non esiste in model_catalog_v1", file=sys.stderr)
        return 1, []

    family_name = _resolve_family_name(conn, args.family)
    if not family_name:
        print(f"ERROR: famiglia '{args.family}' non trovata in family_model_registry_v2", file=sys.stderr)
        return 1, []

    is_dry  = getattr(args, "dry_run", False)
    is_lock = getattr(args, "lock",    False)
    force   = getattr(args, "force",   False)

    if is_dry:
        p = _preview_assignment(conn, family_name, args.model, is_lock, force)
        print(f"DRY_RUN | {family_name} | action={p['action']} | {p['old_model']} → {args.model} | locked={is_lock}")
        return 0, []

    result = _upsert_assignment(
        conn,
        family_name=family_name,
        model_code=args.model,
        is_locked=is_lock,
        assigned_by="manual",
        reason=getattr(args, "reason", None),
        notes=None,
        force=force,
    )

    action  = result["action"]
    changed = []
    if action == "skipped_locked":
        print(f"SKIP (locked) | {family_name} | usa --force per forzare")
    elif action == "no_change":
        print(f"NO_CHANGE | {family_name} | già assegnato {args.model} locked={is_lock}")
    else:
        print(f"{action.upper()} | {family_name} | {result['old_model']} → {args.model} | locked={result['is_locked']}")
        changed = [family_name]
    return 0, changed


def action_assign_to_class(conn, args) -> tuple[int, list[str]]:
    if not _validate_model_code(conn, args.model):
        print(f"ERROR: model_code '{args.model}' non esiste in model_catalog_v1", file=sys.stderr)
        return 1, []

    rows = conn.execute(
        sa.text("""
            SELECT DISTINCT family_name
            FROM ml_forecast.family_model_state_v1
            WHERE demand_class_final = :dc AND is_active = TRUE
            ORDER BY family_name
        """),
        {"dc": args.demand_class},
    ).fetchall()

    if not rows:
        print(f"WARN: nessuna famiglia attiva con demand_class_final='{args.demand_class}'")
        return 0, []

    is_dry  = getattr(args, "dry_run", False)
    is_lock = getattr(args, "lock",    False)
    force   = getattr(args, "force",   False)

    if is_dry:
        previews = [_preview_assignment(conn, fn, args.model, is_lock, force) for (fn,) in rows]
        counts = {}
        for p in previews:
            counts[p["action"]] = counts.get(p["action"], 0) + 1
        print(f"DRY_RUN | class={args.demand_class} model={args.model} | "
              f"{len(rows)} famiglie | " + " ".join(f"{k}={v}" for k, v in sorted(counts.items())))
        return 0, []

    ok = skip = fail = 0
    changed = []
    for (fn,) in rows:
        try:
            result = _upsert_assignment(
                conn,
                family_name=fn,
                model_code=args.model,
                is_locked=is_lock,
                assigned_by="manual_class",
                reason=getattr(args, "reason", None) or f"assign-model-to-class dc={args.demand_class}",
                notes=None,
                force=force,
            )
            if result["action"] == "skipped_locked":
                skip += 1
                print(f"  SKIP (locked) | {fn}")
            elif result["action"] == "no_change":
                ok += 1
                print(f"  NO_CHANGE     | {fn}")
            else:
                ok += 1
                changed.append(fn)
                print(f"  {result['action'].upper():8s} | {fn} | {result['old_model']} → {args.model}")
        except Exception as e:
            fail += 1
            print(f"  ERROR | {fn} | {e}", file=sys.stderr)

    print(f"\nASSIGN_CLASS done | class={args.demand_class} model={args.model} | ok={ok} skip={skip} fail={fail}")
    return 0 if fail == 0 else 1, changed


def action_assign_to_all(conn, args) -> tuple[int, list[str]]:
    if not _validate_model_code(conn, args.model):
        print(f"ERROR: model_code '{args.model}' non esiste in model_catalog_v1", file=sys.stderr)
        return 1, []

    rows = conn.execute(
        sa.text("""
            SELECT family_name
            FROM ml_forecast.family_model_state_v1
            WHERE is_active = TRUE
            ORDER BY family_name
        """),
    ).fetchall()

    if not rows:
        print("WARN: nessuna famiglia attiva trovata")
        return 0, []

    is_dry  = getattr(args, "dry_run", False)
    is_lock = getattr(args, "lock",    False)
    force   = getattr(args, "force",   False)

    if is_dry:
        print(f"DRY_RUN | assign-model-to-all | model={args.model} | "
              f"{len(rows)} famiglie attive | locked={is_lock}")
        return 0, []

    # Conferma esplicita (bypassed con --yes)
    if not getattr(args, "yes", False):
        print(f"ATTENZIONE: questa operazione modificherà fino a {len(rows)} famiglie.")
        try:
            confirm = input("Digita 'CONFIRM' per procedere (Ctrl+C per annullare): ").strip()
        except (KeyboardInterrupt, EOFError):
            print("\nOperazione annullata.")
            return 0, []
        if confirm != "CONFIRM":
            print("Operazione annullata.")
            return 0, []

    ok = skip = fail = 0
    changed = []
    for (fn,) in rows:
        try:
            result = _upsert_assignment(
                conn,
                family_name=fn,
                model_code=args.model,
                is_locked=is_lock,
                assigned_by="manual_all",
                reason=getattr(args, "reason", None) or "assign-model-to-all",
                notes=None,
                force=force,
            )
            if result["action"] == "skipped_locked":
                skip += 1
            elif result["action"] != "no_change":
                ok += 1
                changed.append(fn)
            else:
                ok += 1
        except Exception as e:
            fail += 1
            print(f"  ERROR | {fn} | {e}", file=sys.stderr)

    print(f"ASSIGN_ALL done | model={args.model} | total={len(rows)} changed={len(changed)} skip={skip} fail={fail}")
    return 0 if fail == 0 else 1, changed


def action_apply_best_suggested(conn, args) -> tuple[int, list[str]]:
    family_name = _resolve_family_name(conn, args.family)
    if not family_name:
        print(f"ERROR: famiglia '{args.family}' non trovata", file=sys.stderr)
        return 1, []

    locked_row = conn.execute(
        sa.text("""
            SELECT is_locked
            FROM ml_forecast.family_model_assignment_v1
            WHERE family_name = :fn
        """),
        {"fn": family_name},
    ).first()

    if locked_row and locked_row[0] and not getattr(args, "force", False):
        print(f"SKIP | '{family_name}' è locked. Usa --force per forzare.")
        return 0, []

    row = conn.execute(
        sa.text("""
            SELECT suggestion_id, model_code,
                   error_metric, error_value,
                   competitor_model_code, competitor_error_value,
                   improvement_pct
            FROM ml_forecast.family_model_suggestion_benchmark_v1
            WHERE family_name = :fn
              AND is_applied   = FALSE
            ORDER BY improvement_pct DESC NULLS LAST, suggested_at DESC
            LIMIT 1
        """),
        {"fn": family_name},
    ).mappings().first()

    if not row:
        print(f"WARN: nessuna suggestion disponibile per '{family_name}'")
        return 0, []

    if getattr(args, "dry_run", False):
        print(
            f"DRY_RUN | family={family_name} | "
            f"model={row['model_code']} vs {row['competitor_model_code']} | "
            f"metric={row['error_metric']} improvement={row['improvement_pct']}%"
        )
        return 0, []

    reason = (
        f"benchmark suggestion_id={row['suggestion_id']} "
        f"improvement={row['improvement_pct']}% metric={row['error_metric']}"
    )
    result = _upsert_assignment(
        conn,
        family_name=family_name,
        model_code=row["model_code"],
        is_locked=False,
        assigned_by="benchmark",
        reason=reason,
        notes=None,
        force=getattr(args, "force", False),
    )

    conn.execute(
        sa.text("""
            UPDATE ml_forecast.family_model_suggestion_benchmark_v1
            SET is_applied = TRUE, applied_at = now()
            WHERE suggestion_id = :sid
        """),
        {"sid": row["suggestion_id"]},
    )

    print(
        f"APPLIED | {family_name} | "
        f"{row['competitor_model_code']} → {row['model_code']} | "
        f"metric={row['error_metric']} improvement={row['improvement_pct']}%"
    )
    print(f"  assignment: {result}")
    return 0, [family_name]


# ──────────────────────────────────────────────
# CLI
# ──────────────────────────────────────────────

def main() -> int:
    parser = argparse.ArgumentParser(
        prog="model_control",
        description="Governance control per l'assegnazione dei modelli forecast.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Esempi:
  python jobs/model_control.py assign-model-to-family --family "ciclamino" --model ETS_DAMPED
  python jobs/model_control.py assign-model-to-family --family "ciclamino" --model ETS_DAMPED --lock --reason "test stagionalità"
  python jobs/model_control.py assign-model-to-class  --class intermittent --model CROSTON_SBA
  python jobs/model_control.py assign-model-to-all    --model V4_TWEEDIE_BUNDLE --reason "rollback a bundle"
  python jobs/model_control.py apply-best-suggested-model --family "ciclamino" --dry-run
        """,
    )
    sub = parser.add_subparsers(dest="action", required=True, metavar="ACTION")

    # ── assign-model-to-family ──────────────────
    p1 = sub.add_parser(
        "assign-model-to-family",
        help="Assegna un modello a una famiglia specifica",
    )
    p1.add_argument("--family",   required=True, metavar="NOME",
                    help="Nome della famiglia (es. 'ciclamino')")
    p1.add_argument("--model",    required=True, metavar="CODE",
                    help="model_code da model_catalog_v1")
    p1.add_argument("--lock",     action="store_true", default=False,
                    help="Blocca l'assignment (impedisce modifiche automatiche)")
    p1.add_argument("--reason",   default=None,
                    help="Motivazione dell'assegnazione")
    p1.add_argument("--force",    action="store_true", default=False,
                    help="Forza anche su famiglie locked")
    p1.add_argument("--dry-run",  action="store_true", default=False, dest="dry_run",
                    help="Mostra cosa succederebbe senza eseguire nulla")
    p1.add_argument("--run-now",  action="store_true", default=False, dest="run_now",
                    help="Dopo il commit esegue train + predict per la famiglia cambiata")

    # ── assign-model-to-class ──────────────────
    p2 = sub.add_parser(
        "assign-model-to-class",
        help="Assegna un modello a tutte le famiglie di una demand class",
    )
    p2.add_argument("--class",   dest="demand_class", required=True, metavar="CLASSE",
                    help="Valore di demand_class_final")
    p2.add_argument("--model",   required=True, metavar="CODE",
                    help="model_code da model_catalog_v1")
    p2.add_argument("--lock",    action="store_true", default=False,
                    help="Blocca gli assignment (impedisce modifiche automatiche)")
    p2.add_argument("--reason",  default=None)
    p2.add_argument("--force",   action="store_true", default=False,
                    help="Forza anche su famiglie locked")
    p2.add_argument("--dry-run", action="store_true", default=False, dest="dry_run",
                    help="Mostra cosa succederebbe senza eseguire nulla")
    p2.add_argument("--run-now", action="store_true", default=False, dest="run_now",
                    help="Dopo il commit esegue train + predict per ogni famiglia cambiata")

    # ── assign-model-to-all ────────────────────
    p3 = sub.add_parser(
        "assign-model-to-all",
        help="Assegna un modello a TUTTE le famiglie attive (richiede conferma)",
    )
    p3.add_argument("--model",   required=True, metavar="CODE",
                    help="model_code da model_catalog_v1")
    p3.add_argument("--lock",    action="store_true", default=False,
                    help="Blocca tutti gli assignment")
    p3.add_argument("--reason",  default=None)
    p3.add_argument("--force",   action="store_true", default=False,
                    help="Forza anche su famiglie locked")
    p3.add_argument("--dry-run", action="store_true", default=False, dest="dry_run",
                    help="Mostra cosa succederebbe senza eseguire nulla")
    p3.add_argument("--yes",     action="store_true", default=False,
                    help="Salta la conferma interattiva (per uso in script)")

    # ── apply-best-suggested-model ─────────────
    p4 = sub.add_parser(
        "apply-best-suggested-model",
        help="Applica la miglior suggestion benchmark per una famiglia",
    )
    p4.add_argument("--family",  required=True, metavar="NOME",
                    help="Nome della famiglia")
    p4.add_argument("--dry-run", action="store_true", default=False,
                    help="Mostra l'azione senza eseguirla")
    p4.add_argument("--force",   action="store_true", default=False,
                    help="Forza anche se la famiglia è locked")

    args = parser.parse_args()
    eng = _get_engine()
    changed_families: list[str] = []
    rc = 1
    try:
        with eng.begin() as conn:
            if args.action == "assign-model-to-family":
                rc, changed_families = action_assign_to_family(conn, args)
            elif args.action == "assign-model-to-class":
                rc, changed_families = action_assign_to_class(conn, args)
            elif args.action == "assign-model-to-all":
                rc, changed_families = action_assign_to_all(conn, args)
            elif args.action == "apply-best-suggested-model":
                rc, changed_families = action_apply_best_suggested(conn, args)
            else:
                print(f"Azione non riconosciuta: {args.action}", file=sys.stderr)
                rc = 1
    finally:
        eng.dispose()

    # --run-now: esegue train + predict DOPO il commit della transazione
    if rc == 0 and getattr(args, "run_now", False) and changed_families:
        if len(changed_families) > 10:
            print(f"INFO: --run-now su {len(changed_families)} famiglie — potrebbe richiedere tempo.")
        for fn in changed_families:
            print(f"\n--- run-now: '{fn}' ---")
            t_rc, p_rc = _run_train_predict(fn)
            if t_rc != 0 or p_rc not in (0, -1):
                rc = max(rc, 1)

    return rc


if __name__ == "__main__":
    raise SystemExit(main())
