import os
from pathlib import Path

import numpy as np
import pandas as pd
import sqlalchemy as sa
from dotenv import load_dotenv

load_dotenv("/opt/greenbrain-platform/client-runtime/etl/.env.ml.runtime")

OUT_DIR = Path("/opt/greenbrain-platform/runtime-reports/diagnostics")
OUT_DIR.mkdir(parents=True, exist_ok=True)

engine = sa.create_engine(os.environ["DATABASE_URL"], pool_pre_ping=True)

q = """
with base as (
    select
        lower(trim(famiglia)) as family_name,
        data::date as data,
        sum(coalesce(qty_venduta,0))::float as qty
    from public.greenhouse_forecast_features_dense
    where famiglia is not null
      and trim(famiglia) <> ''
      and data >= date '2009-01-01'
    group by 1,2
)
select *
from base
order by family_name, data
"""

df = pd.read_sql(q, engine)
engine.dispose()

rows = []

for fam, g in df.groupby("family_name"):
    g = g.sort_values("data").copy()
    qty = g["qty"].fillna(0).to_numpy()
    dates = pd.to_datetime(g["data"])
    pos = qty[qty > 0]

    days_total = len(g)
    pos_days = int((qty > 0).sum())
    zero_days = int((qty == 0).sum())
    zero_rate = float(zero_days / days_total) if days_total else np.nan
    pos_rate = float(pos_days / days_total) if days_total else np.nan
    qty_total = float(np.sum(qty))
    qty_avg_all_days = float(np.mean(qty)) if days_total else np.nan
    qty_avg_pos_days = float(np.mean(pos)) if len(pos) else np.nan
    qty_std_pos_days = float(np.std(pos, ddof=1)) if len(pos) > 1 else np.nan

    years_count = int(dates.dt.year.nunique()) if len(dates) else 0
    active_months = int(dates[qty > 0].dt.month.nunique()) if pos_days else 0

    if pos_days > 1:
        pos_idx = np.where(qty > 0)[0]
        intervals = np.diff(pos_idx)
        adi = float(np.mean(intervals)) if len(intervals) else np.nan
    else:
        adi = np.nan

    if len(pos) > 1 and np.mean(pos) > 0:
        cv2 = float((np.std(pos, ddof=1) / np.mean(pos)) ** 2)
    else:
        cv2 = np.nan

    # peak day-of-year
    g2 = g.copy()
    g2["doy"] = pd.to_datetime(g2["data"]).dt.dayofyear
    peak_by_doy = g2.groupby("doy", as_index=False)["qty"].sum()
    if len(peak_by_doy):
        peak_doy = int(peak_by_doy.sort_values(["qty", "doy"], ascending=[False, True]).iloc[0]["doy"])
    else:
        peak_doy = np.nan

    # first sale doy by year
    first_sale_doys = []
    if pos_days:
        g_pos = g2[g2["qty"] > 0].copy()
        for yy, gy in g_pos.groupby(pd.to_datetime(g_pos["data"]).dt.year):
            first_sale_doys.append(int(gy["doy"].min()))

    season_start_p25 = float(np.percentile(first_sale_doys, 25)) if len(first_sale_doys) >= 2 else np.nan
    season_start_p50 = float(np.percentile(first_sale_doys, 50)) if len(first_sale_doys) >= 2 else np.nan
    season_start_p75 = float(np.percentile(first_sale_doys, 75)) if len(first_sale_doys) >= 2 else np.nan

    def classify_demand(adi_val, cv2_val):
        if pd.isna(adi_val) or pd.isna(cv2_val):
            return "insufficient"
        if adi_val < 1.32 and cv2_val < 0.49:
            return "smooth"
        if adi_val >= 1.32 and cv2_val < 0.49:
            return "intermittent"
        if adi_val < 1.32 and cv2_val >= 0.49:
            return "erratic"
        return "lumpy"

    demand_class = classify_demand(adi, cv2)

    rows.append({
        "family_name": fam,
        "days_total": days_total,
        "pos_days": pos_days,
        "zero_days": zero_days,
        "zero_rate": round(zero_rate, 4) if pd.notna(zero_rate) else None,
        "pos_rate": round(pos_rate, 4) if pd.notna(pos_rate) else None,
        "qty_total": round(qty_total, 2),
        "qty_avg_all_days": round(qty_avg_all_days, 4) if pd.notna(qty_avg_all_days) else None,
        "qty_avg_pos_days": round(qty_avg_pos_days, 4) if pd.notna(qty_avg_pos_days) else None,
        "qty_std_pos_days": round(qty_std_pos_days, 4) if pd.notna(qty_std_pos_days) else None,
        "years_count": years_count,
        "active_months": active_months,
        "adi": round(adi, 4) if pd.notna(adi) else None,
        "cv2_pos": round(cv2, 4) if pd.notna(cv2) else None,
        "peak_doy": peak_doy if pd.notna(peak_doy) else None,
        "season_start_p25": round(season_start_p25, 1) if pd.notna(season_start_p25) else None,
        "season_start_p50": round(season_start_p50, 1) if pd.notna(season_start_p50) else None,
        "season_start_p75": round(season_start_p75, 1) if pd.notna(season_start_p75) else None,
        "demand_class": demand_class,
    })

out = pd.DataFrame(rows)

# euristiche utili aggiuntive
out["data_quality_class"] = np.where(
    (out["years_count"] < 2) | (out["pos_days"] < 20),
    "weak",
    np.where(
        (out["years_count"] < 4) | (out["pos_days"] < 60),
        "medium",
        "strong"
    )
)

out["seasonality_class"] = np.where(
    out["active_months"] <= 3, "very_narrow",
    np.where(
        out["active_months"] <= 6, "seasonal",
        np.where(out["active_months"] <= 9, "broad_seasonal", "all_year")
    )
)

csv_path = OUT_DIR / "family_diagnostics.csv"
out.sort_values(
    ["demand_class", "zero_rate", "qty_total"],
    ascending=[True, False, True]
).to_csv(csv_path, index=False)

print(f"OK wrote: {csv_path}")
print()
print(out["demand_class"].value_counts(dropna=False).to_string())
print()
print(out["seasonality_class"].value_counts(dropna=False).to_string())
print()
print(out["data_quality_class"].value_counts(dropna=False).to_string())
print()
print(out.sort_values(['zero_rate', 'qty_total'], ascending=[False, True]).head(30).to_string(index=False))
