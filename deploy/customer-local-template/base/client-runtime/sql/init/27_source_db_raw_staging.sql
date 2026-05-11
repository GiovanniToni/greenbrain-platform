CREATE SCHEMA IF NOT EXISTS source_import;

CREATE TABLE IF NOT EXISTS source_import.sales_raw (
  source_client_code text NOT NULL DEFAULT 'greenhouse',
  progressivo bigint NOT NULL,
  codart text,
  descrizione text,
  tipo text,
  fascia text,
  categoria text,
  quantita numeric,
  imponibilenetto numeric,
  data_movimento timestamp,
  disattivato smallint DEFAULT 0,
  movim_cassa smallint DEFAULT 0,
  load_timestamp timestamp NOT NULL DEFAULT now(),
  raw_payload jsonb,
  PRIMARY KEY (source_client_code, progressivo)
);

CREATE INDEX IF NOT EXISTS ix_sales_raw_data_movimento
  ON source_import.sales_raw (data_movimento);

CREATE INDEX IF NOT EXISTS ix_sales_raw_codart
  ON source_import.sales_raw (codart);
