import numpy as np
import pandas as pd

def build_pos_rate_doy(hist_df: pd.DataFrame, doy_col="doy", y_col="qty_venduta",
                       group_col="fascia_prezzo_iva_inc", smooth_window=15, min_years=3):
    """
    Ritorna dict:
      - "by_fascia": {(fascia, doy)->pos_rate_smoothed}
      - "by_family": {doy->pos_rate_smoothed}
    hist_df deve contenere: data, fascia_prezzo_iva_inc, qty_venduta (o y_col)
    """
    df = hist_df.copy()
    df["data"] = pd.to_datetime(df["data"])
    df["year"] = df["data"].dt.year.astype(int)
    df[doy_col] = df["data"].dt.dayofyear.astype(int)
    y = pd.to_numeric(df[y_col], errors="coerce").fillna(0.0)
    df["_pos"] = (y > 0).astype(int)

    n_years = df["year"].nunique()
    if n_years < min_years:
        return {"by_fascia": {}, "by_family": {}, "n_years": int(n_years)}

    # family-level
    fam = df.groupby(doy_col)["_pos"].mean().reindex(range(1, 366), fill_value=0.0)
    fam_sm = fam.rolling(smooth_window, center=True, min_periods=1).mean()

    # fascia-level
    by_f = {}
    for fascia, g in df.groupby(group_col):
        s = g.groupby(doy_col)["_pos"].mean().reindex(range(1, 366), fill_value=0.0)
        s_sm = s.rolling(smooth_window, center=True, min_periods=1).mean()
        for doy in range(1, 366):
            by_f[(str(fascia), int(doy))] = float(s_sm.loc[doy])

    by_family = {int(d): float(fam_sm.loc[d]) for d in range(1, 366)}
    return {"by_fascia": by_f, "by_family": by_family, "n_years": int(n_years)}

def apply_gate(qty: float, pos_rate: float, mode="soft",
               soft_floor=0.01, soft_mult=0.25, hard_floor=0.003):
    """
    - soft: se pos_rate < soft_floor => qty *= soft_mult
    - hard: se pos_rate < hard_floor => qty = 0
    """
    q = float(max(0.0, qty))
    pr = float(max(0.0, min(1.0, pos_rate)))
    if mode == "hard":
        return 0.0 if pr < hard_floor else q
    # soft
    return q * soft_mult if pr < soft_floor else q
