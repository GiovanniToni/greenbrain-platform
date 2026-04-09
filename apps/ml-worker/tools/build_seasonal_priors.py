import os
#!/usr/bin/env python3

import sys
import glob
import argparse
from pathlib import Path
from datetime import datetime

import pandas as pd
import pyarrow.parquet as pq


REPO_DIR = os.getenv("GH_REPO_DIR", "/opt/greenbrain-platform/apps/ml-worker")
PARQUET_ROOT = os.getenv("GH_PARQUET_CACHE", os.path.join(REPO_DIR, "parquet_cache"))
FEATURES_ROOT = os.path.join(PARQUET_ROOT, "features_dense", "v1")
OUT_DIR = os.getenv("GH_PRIORS_DIR", os.path.join(REPO_DIR, "priors_cache"))

def smooth_doy_priors(df_doy, *, window=7):
    """
    Circular rolling mean smoothing for DOY priors.
    Expects columns: key (int doy), pos_rate, avg_qty, avg_qty_pos, n_days (optional).
    """
    import pandas as pd
    import numpy as np

    if df_doy is None or len(df_doy) == 0:
        return df_doy

    d = df_doy.copy()
    d["key"] = pd.to_numeric(d["key"], errors="coerce").astype(int)
    d = d.sort_values("key")
    # build full index 1..366
    full = pd.DataFrame({"key": np.arange(1, 367, dtype=int)})
    d = full.merge(d, on="key", how="left")
    # circular pad
    pad = int(window)
    d_pad = pd.concat([d.tail(pad), d, d.head(pad)], ignore_index=True)

    for col in ["pos_rate", "avg_qty", "avg_qty_pos"]:
        if col in d_pad.columns:
            d_pad[col] = pd.to_numeric(d_pad[col], errors="coerce")
            d_pad[col] = d_pad[col].rolling(2*pad+1, center=True, min_periods=1).mean()

    d_sm = d_pad.iloc[pad:pad+len(d)].copy()
    # restore only rows where original existed? no: keep full 1..366 (better for lookup)
    return d_sm




def _list_parquets_for_slug(slug: str, year_min: int = None, year_max: int = None):
    pat = os.path.join(FEATURES_ROOT, "year=*", f"famiglia_slug={slug}", "part.parquet")
    paths = sorted(glob.glob(pat))
    out = []
    for p in paths:
        try:
            y = int(Path(p).parts[-3].split("year=")[1])
        except Exception:
            y = None
        if year_min is not None and y is not None and y < year_min:
            continue
        if year_max is not None and y is not None and y > year_max:
            continue
        out.append(p)
    return out


def _read_family_day_total(parquet_paths, *, cols=("data", "qty_venduta", "week_num", "month_num")):
    frames = []
    for p in parquet_paths:
        schema = pq.read_schema(p).names
        use_cols = [c for c in cols if c in schema]
        if "data" not in use_cols or "qty_venduta" not in use_cols:
            raise RuntimeError(f"Missing required columns in {p}. Have: {schema}")

        t = pq.read_table(p, columns=use_cols)
        df = t.to_pandas()
        frames.append(df)

    if not frames:
        return pd.DataFrame(columns=["data", "qty_total", "week_num", "month_num", "pos", "doy"])

    df = pd.concat(frames, ignore_index=True)
    df["data"] = pd.to_datetime(df["data"])

    if "week_num" not in df.columns:
        df["week_num"] = df["data"].dt.isocalendar().week.astype(int)
    if "month_num" not in df.columns:
        df["month_num"] = df["data"].dt.month.astype(int)

    g = df.groupby(["data", "week_num", "month_num"], as_index=False)["qty_venduta"].sum()
    g = g.rename(columns={"qty_venduta": "qty_total"})
    g["pos"] = (g["qty_total"] > 0).astype(int)
    g["doy"] = g["data"].dt.dayofyear.astype(int)
    return g


def _prior_table(g: pd.DataFrame, slug: str, fam_name: str = None) -> pd.DataFrame:
    def agg(df, grain, key):
        n = len(df)
        npos = int(df["pos"].sum()) if n else 0
        pos_rate = float(npos / n) if n else 0.0
        avg_qty = float(df["qty_total"].mean()) if n else 0.0
        avg_qty_pos = float(df.loc[df["pos"] == 1, "qty_total"].mean()) if npos else 0.0
        return {
            "famiglia": fam_name or slug,
            "famiglia_slug": slug,
            "grain": grain,
            "key": int(key),
            "n_days": int(n),
            "n_pos": int(npos),
            "pos_rate": pos_rate,
            "avg_qty": avg_qty,
            "avg_qty_pos": avg_qty_pos,
        }

    rows = [agg(g, "global", 0)]
    for m, dfm in g.groupby("month_num"):
        rows.append(agg(dfm, "month", m))
    for w, dfw in g.groupby("week_num"):
        rows.append(agg(dfw, "week", w))
    for d, dfd in g.groupby("doy"):
        rows.append(agg(dfd, "doy", d))

    out = pd.DataFrame(rows)
    out["updated_at_utc"] = datetime.utcnow().isoformat()
    return out


def _load_slugs_from_file(path: str):
    slugs = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            s = line.strip().lower()
            if s and not s.startswith("#"):
                slugs.append(s)
    return slugs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--slug", action="append", default=[], help="famiglia_slug (ripetibile)")
    ap.add_argument("--slugs-file", default=None, help="file con 1 slug per riga")
    ap.add_argument("--year-min", type=int, default=None)
    ap.add_argument("--year-max", type=int, default=None)
    ap.add_argument("--out", default=os.path.join(OUT_DIR, "priors_v1.parquet"))
    ap.add_argument("--also-per-family", action="store_true", help="scrive anche priors_cache/per_family/priors_<slug>_v1.parquet")
    args = ap.parse_args()

    slugs = [s.strip().lower() for s in (args.slug or []) if s.strip()]
    if args.slugs_file:
        slugs += _load_slugs_from_file(args.slugs_file)

    # unique, preserva ordine
    seen = set()
    slugs2 = []
    for s in slugs:
        if s not in seen:
            slugs2.append(s)
            seen.add(s)
    slugs = slugs2

    if not slugs:
        print("❌ Devi passare almeno uno slug: --slug pothos oppure --slugs-file file.txt", file=sys.stderr)
        raise SystemExit(2)

    os.makedirs(os.path.dirname(args.out), exist_ok=True)

    all_rows = []
    for slug in slugs:
        paths = _list_parquets_for_slug(slug, args.year_min, args.year_max)
        if not paths:
            print(f"⚠️  {slug}: nessun parquet trovato in {FEATURES_ROOT}", flush=True)
            continue

        g = _read_family_day_total(paths)
        pri = _prior_table(g, slug, fam_name=slug)
        all_rows.append(pri)

        print(f"✅ {slug}: days={len(g)} priors_rows={len(pri)} years_files={len(paths)}", flush=True)

        if args.also_per_family:
            perdir = os.path.join(OUT_DIR, "per_family")
            os.makedirs(perdir, exist_ok=True)
            perpath = os.path.join(perdir, f"priors_{slug}_v1.parquet")
            pri.to_parquet(perpath, index=False)
            print(f"   -> wrote {perpath}", flush=True)

    if not all_rows:
        print("❌ nessuna famiglia processata (parquet mancanti?)", file=sys.stderr)
        raise SystemExit(1)

    out = pd.concat(all_rows, ignore_index=True)
    out.to_parquet(args.out, index=False)
    print(f"\n✅ WROTE: {args.out}")

    # --- M2: smooth DOY priors (circular rolling mean) ---

    _w = int(os.getenv("V4_PRIOR_SMOOTH_DOY", "7"))
    if _w > 0:
        _doy = out[out["grain"] == "doy"].copy()
        if len(_doy):
            _doy_sm = smooth_doy_priors(_doy, window=_w)
            _rest = out[out["grain"] != "doy"].copy()
            out = pd.concat([_rest, _doy_sm], ignore_index=True)

    print(out.groupby(["grain"]).size().to_string(), flush=True)


if __name__ == "__main__":
    main()
