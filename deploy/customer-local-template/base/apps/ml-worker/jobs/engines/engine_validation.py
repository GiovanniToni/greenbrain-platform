REQUIRED_FORECAST_COLUMNS = {
    "data",
    "famiglia",
    "fascia_prezzo_iva_inc",
    "qty_forecast",
    "created_at",
}


def validate_forecast_df(df) -> None:
    missing = REQUIRED_FORECAST_COLUMNS - set(df.columns)
    if missing:
        raise ValueError(
            f"Forecast dataframe missing required columns: {sorted(missing)}. "
            f"Present: {sorted(df.columns.tolist())}"
        )
