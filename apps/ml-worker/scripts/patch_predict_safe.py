import re
from pathlib import Path
from datetime import datetime

TARGET = Path("/opt/greenhouse/repo/predict_v4_single_family_tweedie.py")

txt = TARGET.read_text(encoding="utf-8", errors="ignore")

backup = TARGET.with_suffix(f".py.bak_{datetime.now().strftime('%Y%m%d_%H%M%S')}")
backup.write_text(txt, encoding="utf-8")
print(f"Backup creato: {backup}")

# --- 1) sostituisci truncate_forecast_table con delete_family_window
pattern_truncate = re.compile(
    r"def\s+truncate_forecast_table\s*\(\s*conn\s*\)\s*:\s*\n"
    r"(?:[ \t].*\n)+?\n",
    re.MULTILINE
)

replacement_delete = """def delete_family_window(conn, famiglia: str, start_date, end_date):
    \"""
    Cancella solo i record della stessa famiglia e solo nella finestra forecast.
    start_date/end_date: stringhe 'YYYY-MM-DD' o date.
    \"""
    conn.execute(
        text(f\"\"\"
            DELETE FROM {FORECAST_TABLE}
            WHERE LOWER(famiglia)=LOWER(:famiglia)
              AND data BETWEEN :start_d AND :end_d;
        \"\"\"),
        {"famiglia": famiglia, "start_d": start_date, "end_d": end_date},
    )

"""

if not pattern_truncate.search(txt):
    raise SystemExit("ERRORE: non trovo def truncate_forecast_table(conn) nel file. Patch non applicata.")
txt = pattern_truncate.sub(replacement_delete, txt, count=1)
print("OK: sostituita truncate_forecast_table -> delete_family_window")

# --- 2) sostituisci insert_forecast con upsert_forecast
pattern_insert = re.compile(
    r"def\s+insert_forecast\s*\(\s*conn\s*,\s*df_out\s*:\s*pd\.DataFrame\s*\)\s*->\s*int\s*:\s*\n"
    r"(?:[ \t].*\n)+?\n",
    re.MULTILINE
)

replacement_upsert = """def upsert_forecast(conn, df_out: pd.DataFrame) -> int:
    \"""
    UPSERT (insert/update) per evitare TRUNCATE e supportare run multi-famiglia.
    Richiede UNIQUE(data, famiglia, fascia_prezzo_iva_inc) su Supabase.
    \"""
    if df_out.empty:
        return 0

    insert_sql = text(f\"\"\"
        INSERT INTO {FORECAST_TABLE}
            (data, famiglia, fascia_prezzo_iva_inc, qty_forecast, created_at)
        VALUES
            (:data, :famiglia, :fascia, :qty, now())
        ON CONFLICT (data, famiglia, fascia_prezzo_iva_inc)
        DO UPDATE SET
            qty_forecast = EXCLUDED.qty_forecast,
            created_at = now();
    \"\"\")

    rows = []
    for r in df_out.itertuples(index=False):
        rows.append({
            "data": (r.data.date().isoformat() if hasattr(r.data, "date") else str(r.data)),
            "famiglia": str(r.famiglia),
            "fascia": str(r.fascia_prezzo_iva_inc),
            "qty": float(r.qty_forecast),
        })

    # batch per evitare payload enormi
    B = 2000
    for i in range(0, len(rows), B):
        conn.execute(insert_sql, rows[i:i+B])

    return len(rows)

"""

if not pattern_insert.search(txt):
    raise SystemExit("ERRORE: non trovo def insert_forecast(conn, df_out: pd.DataFrame) -> int nel file. Patch non applicata.")
txt = pattern_insert.sub(replacement_upsert, txt, count=1)
print("OK: sostituita insert_forecast -> upsert_forecast")

# --- 3) rimpiazza la chiamata a truncate_forecast_table(conn) con delete_family_window + upsert
# Cerchiamo il blocco classico:
# with engine.begin() as conn:
#     truncate_forecast_table(conn)
#     written = insert_forecast(conn, df)
pattern_block = re.compile(
    r"with\s+engine\.begin\(\)\s+as\s+conn\s*:\s*\n"
    r"([ \t]+)truncate_forecast_table\(\s*conn\s*\)\s*\n"
    r"([ \t]+)written\s*=\s*insert_forecast\(\s*conn\s*,\s*df\s*\)\s*\n",
    re.MULTILINE
)

replacement_block = (
    "with engine.begin() as conn:\n"
    "    # finestra forecast basata sui dati prodotti\n"
    "    if not df.empty:\n"
    "        start_d = df['data'].min().date().isoformat() if hasattr(df['data'].min(), 'date') else str(df['data'].min())\n"
    "        end_d = df['data'].max().date().isoformat() if hasattr(df['data'].max(), 'date') else str(df['data'].max())\n"
    "        fam_name = str(df['famiglia'].iloc[0])\n"
    "        delete_family_window(conn, fam_name, start_d, end_d)\n"
    "    written = upsert_forecast(conn, df)\n"
)

m = pattern_block.search(txt)
if m:
    txt = pattern_block.sub(replacement_block, txt, count=1)
    print("OK: sostituito blocco DB write (no truncate, sì delete finestra + upsert)")
else:
    # fallback: sostituiamo solo le chiamate singole se il blocco è diverso
    if "truncate_forecast_table(conn)" in txt:
        txt = txt.replace("truncate_forecast_table(conn)", "# [PATCHED] no-truncate: handled below", 1)
        print("WARN: blocco 'with engine.begin() as conn' non trovato esattamente. Ho commentato la chiamata a truncate.")
    if "insert_forecast(conn, df)" in txt:
        txt = txt.replace("insert_forecast(conn, df)", "upsert_forecast(conn, df)", 1)
        print("WARN: ho sostituito insert_forecast(conn, df) -> upsert_forecast(conn, df) (fallback).")

TARGET.write_text(txt, encoding="utf-8")
print("Patch completata con successo.")
