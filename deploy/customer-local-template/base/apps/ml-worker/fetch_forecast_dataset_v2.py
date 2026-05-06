import os
from datetime import datetime

import pandas as pd
from sqlalchemy import create_engine
from dotenv import load_dotenv


def get_engine():
    base_dir = os.path.dirname(os.path.abspath(__file__))
    load_dotenv(os.path.join(base_dir, ".env"))

    host = os.getenv("PG_HOST")
    port = os.getenv("PG_PORT", "5432")
    db = os.getenv("PG_DB")
    user = os.getenv("PG_USER")
    pwd = os.getenv("PG_PASSWORD")

    if not all([host, db, user, pwd]):
        raise RuntimeError("Variabili PG_* mancanti nel file .env")

    return create_engine(
        f"postgresql+psycopg2://{user}:{pwd}@{host}:{port}/{db}?sslmode=require"
    )


def main():
    engine = get_engine()
    print("Leggo greenhouse_forecast_features_dense da Supabase...")

    # Se vuoi limitare storico: aggiungi WHERE data >= CURRENT_DATE - INTERVAL '5 years'
    query = """
    SELECT
      data,
      famiglia,
      fascia_prezzo_iva_inc,
      qty_venduta,
      imponibile_netto_tot,
      num_articoli,
      fascia_corretta,
      categoria_corretta,
      tmin_c, tmax_c, tavg_c, rain_mm, sun_hours,
      is_holiday, dow, week_num, month_num, year_num,
      qty_lag_1, qty_lag_2, qty_lag_3, qty_lag_7, qty_lag_10, qty_lag_14,
      qty_ma_3, qty_ma_7, qty_ma_10, qty_ma_14, qty_ma_28
    FROM public.greenhouse_forecast_features_dense
    ORDER BY data, famiglia, fascia_prezzo_iva_inc;
    """

    df = pd.read_sql(query, engine)
    engine.dispose()

    print(f"Righe lette: {len(df)}")
    out_name = f"forecast_dataset_v2_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
    df.to_csv(out_name, index=False)
    df.to_csv("forecast_dataset_latest_v2.csv", index=False)
    print("Salvati:", out_name, "e forecast_dataset_latest_v2.csv")


if __name__ == "__main__":
    main()