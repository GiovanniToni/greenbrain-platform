import argparse, pickle, math
from sklearn.metrics import log_loss, brier_score_loss, precision_recall_fscore_support

def safe_metrics(y, p):
    ll = log_loss(y, p, labels=[0,1])
    br = brier_score_loss(y, p)
    return ll, br

def floor_sweep(y, p, floors=(0.0,0.05,0.10,0.15,0.20,0.25,0.30)):
    out = []
    for f in floors:
        pred = [1 if pi >= f else 0 for pi in p]
        pr, rc, f1, _ = precision_recall_fscore_support(y, pred, average="binary", zero_division=0)
        out.append((f, pr, rc, f1))
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bundle", required=True)
    args = ap.parse_args()

    b = pickle.load(open(args.bundle, "rb"))
    fam = b.get("family_level") or {}
    y = fam.get("pos_valid_y")
    p_raw = fam.get("pos_valid_p_raw")
    cal = fam.get("clf_pos_cal")

    print("BUNDLE:", args.bundle)
    print("family_level has clf_pos_cal:", cal is not None)

    if not y or not p_raw:
        print("❌ missing pos_valid_y / pos_valid_p_raw in bundle. (train patch not applied or old bundle)")
        return

    ll_raw, br_raw = safe_metrics(y, p_raw)
    print(f"\n📌 VALID raw  : logloss={ll_raw:.5f} brier={br_raw:.5f}")

    if cal is not None:
        try:
            p_cal = [float(cal.predict([float(pi)])[0]) for pi in p_raw]
            ll_cal, br_cal = safe_metrics(y, p_cal)
            print(f"📌 VALID cal  : logloss={ll_cal:.5f} brier={br_cal:.5f}")
        except Exception as e:
            print("⚠️ cannot compute calibrated metrics:", e)
            p_cal = None
    else:
        p_cal = None

    use_p = p_cal if p_cal is not None else p_raw
    print("\n🔎 Floor sweep (using cal probs if available):")
    for f, pr, rc, f1 in floor_sweep(y, use_p):
        print(f"  floor={f:>4.2f}  precision={pr:>5.3f}  recall={rc:>5.3f}  f1={f1:>5.3f}")

if __name__ == "__main__":
    main()
