import pandas as pd
import sqlalchemy as sa

_REQUIRED_WRITE_COLS = {"data", "famiglia", "fascia_prezzo_iva_inc", "qty_forecast", "created_at"}


def delete_family_forecast_window(
    conn,
    family_name: str,
    start_date,
    end_date,
    table_name: str = "public.greenhouse_forecast_results_v2",
) -> None:
    """
    Delete all forecast rows for one family within [start_date, end_date].

    Parameters
    ----------
    conn : SQLAlchemy connection (active, inside a transaction)
    family_name : str
    start_date : date-like
    end_date : date-like
    table_name : str
        Fully-qualified table name (schema.table).
    """
    stmt = sa.text(
        f"""
        DELETE FROM {table_name}
        WHERE lower(famiglia) = lower(:family_name)
          AND data >= :start_date
          AND data <= :end_date
        """
    )
    conn.execute(stmt, {"family_name": family_name, "start_date": start_date, "end_date": end_date})


def validate_forecast_write_df(df: pd.DataFrame) -> None:
    """
    Validate that df is safe to write as a forecast output.

    Raises
    ------
    ValueError
        - if df is empty
        - if any required column is missing
        - if df contains more than one distinct famiglia value
    """
    if df is None or df.empty:
        raise ValueError("forecast dataframe is empty — nothing to write")

    missing = _REQUIRED_WRITE_COLS - set(df.columns)
    if missing:
        raise ValueError(
            f"forecast dataframe missing required columns: {sorted(missing)}. "
            f"Present: {sorted(df.columns.tolist())}"
        )

    distinct_families = df["famiglia"].dropna().unique()
    if len(distinct_families) > 1:
        raise ValueError(
            f"forecast dataframe contains {len(distinct_families)} distinct famiglia values — "
            f"expected exactly 1. Found: {sorted(str(f) for f in distinct_families)}"
        )


def write_forecast_replace_window(
    conn,
    df: pd.DataFrame,
    family_name: str | None = None,
    table_name: str = "public.greenhouse_forecast_results_v2",
) -> int:
    """
    Atomically replace the forecast window for one family:
      1. Validate df.
      2. Infer family_name from df if not supplied.
      3. Delete existing rows in [min(data), max(data)] for that family.
      4. Insert df rows.

    Parameters
    ----------
    conn : SQLAlchemy connection (active, inside a transaction)
    df : pd.DataFrame
        Must contain: data, famiglia, fascia_prezzo_iva_inc, qty_forecast, created_at.
    family_name : str or None
        If None, inferred from df["famiglia"].iloc[0].
    table_name : str

    Returns
    -------
    int
        Number of rows written.
    """
    validate_forecast_write_df(df)

    resolved_family = family_name if family_name is not None else str(df["famiglia"].iloc[0])

    start_date = df["data"].min()
    end_date = df["data"].max()

    delete_family_forecast_window(
        conn,
        family_name=resolved_family,
        start_date=start_date,
        end_date=end_date,
        table_name=table_name,
    )

    schema, tbl = table_name.split(".", 1) if "." in table_name else ("public", table_name)

    df_to_write = df[sorted(_REQUIRED_WRITE_COLS)].copy()
    df_to_write.to_sql(
        tbl,
        con=conn,
        schema=schema,
        if_exists="append",
        index=False,
        method="multi",
        chunksize=1000,
    )

    return len(df)
