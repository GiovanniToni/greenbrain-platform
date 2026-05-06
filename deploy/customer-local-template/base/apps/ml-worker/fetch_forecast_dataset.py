import os
from datetime import datetime

import pandas as pd
from sqlalchemy import create_engine
from dotenv import load_dotenv


def get_engine():
    base_dir = os.path.dirname(os.path.abspath(__file__))
    env_path = os.path.join(base_dir, ".env")
    load_dotenv(env_path)

    PG_HOST = os.getenv("PG_HOST")
    PG_PORT = os.getenv("PG_PORT", "5432")
    PG_DB = os.getenv("PG_DB")
    PG_USER = os.getenv("PG_USER")
    PG_PASSWORD = os.getenv("PG_PASSWORD")

    if not all([PG_HOST, PG_DB, PG_USER, PG_PASSWORD]):
        raise RuntimeError("Variabili PG_* mancanti nel file .env")

    conn_str = (
        f"postgresql+psycopg2://{PG_USER}:{PG_PASSWORD}"
        f"@{PG_HOST}:{PG_PORT}/{PG_DB}?sslmode=require"
    )
    return create_engine(conn_str)


def main():
    print("Leggo greenhouse_forecast_dataset da Supabase...")
    engine = get_engine()

    query = """
    SELECT
        data,
        famiglia,
        fascia_prezzo_iva_inc,
        pot_size,
        qty_venduta,
        imponibile_netto_tot,
        num_articoli,
        fascia_corretta,
        categoria_corretta,
        articoli_inclusi
    FROM greenhouse_forecast_dataset
    ORDER BY data, famiglia, fascia_prezzo_iva_inc, pot_size;
    """

    df = pd.read_sql(query, engine)
    engine.dispose()

    print(f"Righe lette: {len(df)}")
    out_name = f"forecast_dataset_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
    df.to_csv(out_name, index=False)
    print(f"Salvato CSV: {out_name}")

    # Salviamo anche un "ultimo" più comodo
    df.to_csv("forecast_dataset_latest.csv", index=False)
    print("Salvato anche forecast_dataset_latest.csv")


if __name__ == "__main__":
    main()
