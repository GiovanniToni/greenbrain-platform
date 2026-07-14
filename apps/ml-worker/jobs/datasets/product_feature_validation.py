from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import unicodedata
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Sequence

import numpy as np
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq


PRODUCT_SOURCE_RELATIVE_PATH = Path(
    "raw_extracts/products_normalized/part-00000.parquet"
)

B2_MANIFEST_RELATIVE_PATH = Path(
    "metadata/dense_grid_manifest.json"
)

OUTPUT_ORDER = (
    "product_master_canonical",
    "family_product_features",
    "family_priceband_product_features",
)

OUTPUT_KEYS: dict[
    str,
    tuple[str, ...],
] = {
    "product_master_canonical": (
        "codart",
    ),
    "family_product_features": (
        "famiglia",
    ),
    "family_priceband_product_features": (
        "famiglia",
        "fascia_prezzo_iva_inc",
    ),
}

SOURCE_REQUIRED_COLUMNS = (
    "codart",
    "tipo",
    "fascia",
    "categoria",
    "descrizione",
    "fascia_corretta",
    "categoria_corretta",
    "famiglia",
    "prezzo_iva_esclusa",
    "prezzo_iva_inclusa",
    "fascia_prezzo_iva_inc",
    "pot_size",
    "load_timestamp",
)

ALLOWED_MODES = (
    "plan",
    "candidate",
    "materialized",
)


@dataclass(frozen=True)
class ProductFeatureValidationConfig:
    run_dir: Path
    source_run_dir: Path
    b2_run_dir: Path
    contract_path: Path
    mode: str
    report_path: Path | None = None
    logical_run_dir: Path | None = None
    validate_source_reconciliation: bool = True


@dataclass(frozen=True)
class ProductFeatureDatasetValidation:
    name: str
    ok: bool
    row_count: int
    file_count: int
    bytes: int
    schema_fingerprint: str
    key_fingerprint: str
    content_fingerprint: str
    issues: tuple[str, ...]

    def to_dict(self) -> dict[str, Any]:
        payload = asdict(self)
        payload["issues"] = list(self.issues)
        return payload


@dataclass(frozen=True)
class ProductFeatureValidationResult:
    ok: bool
    decision: str
    mode: str
    run_dir: str
    datasets: tuple[
        ProductFeatureDatasetValidation,
        ...,
    ]
    issues: tuple[str, ...]

    def to_dict(self) -> dict[str, Any]:
        payload = asdict(self)
        payload["datasets"] = [
            item.to_dict()
            for item in self.datasets
        ]
        payload["issues"] = list(self.issues)
        return payload


def _clean_text(
    value: object,
    *,
    lower: bool = False,
) -> str | None:
    if pd.isna(value):
        return None

    text = unicodedata.normalize(
        "NFKC",
        str(value),
    )

    text = text.replace(
        "\u00a0",
        " ",
    )

    text = re.sub(
        r"\s+",
        " ",
        text,
    ).strip()

    if not text:
        return None

    return text.lower() if lower else text


def _safe_mode(
    series: pd.Series,
) -> str | None:
    values = series.dropna().astype(str)

    if values.empty:
        return None

    counts = values.value_counts()
    maximum = counts.max()

    return sorted(
        counts[
            counts == maximum
        ].index.tolist()
    )[0]


def _dominant_share(
    series: pd.Series,
) -> float:
    values = series.dropna().astype(str)

    if values.empty:
        return 0.0

    counts = values.value_counts()

    return float(
        counts.iloc[0]
        / counts.sum()
    )


def _normalized_entropy(
    series: pd.Series,
    *,
    null_when_empty: bool,
) -> float | None:
    values = series.dropna().astype(str)

    if values.empty:
        return (
            None
            if null_when_empty
            else 0.0
        )

    probabilities = (
        values.value_counts(
            normalize=True
        )
        .to_numpy(dtype=float)
    )

    if len(probabilities) <= 1:
        return 0.0

    entropy = float(
        -np.sum(
            probabilities
            * np.log(probabilities)
        )
    )

    return float(
        entropy
        / math.log(
            len(probabilities)
        )
    )


def _parse_priceband(
    value: object,
) -> tuple[
    float | None,
    float | None,
    bool,
]:
    text = _clean_text(value)

    if text is None:
        return None, None, False

    normalized = (
        text.lower()
        .replace("€", "")
        .replace(",", ".")
    )

    numbers = [
        float(number)
        for number in re.findall(
            r"\d+(?:\.\d+)?",
            normalized,
        )
    ]

    if ">" in normalized:
        if numbers:
            return (
                numbers[0],
                math.inf,
                True,
            )

        return None, None, False

    if len(numbers) >= 2:
        return (
            numbers[0],
            numbers[1],
            False,
        )

    if len(numbers) == 1:
        return (
            numbers[0],
            numbers[0],
            False,
        )

    return None, None, False


def _sha256_bytes(
    data: bytes,
) -> str:
    return hashlib.sha256(
        data
    ).hexdigest()


def _sha256_file(
    path: Path,
) -> str:
    return _sha256_bytes(
        path.read_bytes()
    )


def _canonical_json_hash(
    payload: Any,
) -> str:
    return _sha256_bytes(
        json.dumps(
            payload,
            sort_keys=True,
            separators=(",", ":"),
            default=str,
        ).encode("utf-8")
    )


def _schema_fingerprint(
    schema_spec: Sequence[
        dict[str, Any]
    ],
) -> str:
    return _canonical_json_hash(
        list(schema_spec)
    )


def _contract_schema_fingerprint(
    outputs: dict[
        str,
        dict[str, Any],
    ],
) -> str:
    return _canonical_json_hash(
        {
            name: outputs[name]["schema"]
            for name in OUTPUT_ORDER
        }
    )


def _arrow_type(
    type_name: str,
) -> pa.DataType:
    mapping: dict[
        str,
        pa.DataType,
    ] = {
        "string": pa.string(),
        "int64": pa.int64(),
        "float64": pa.float64(),
        "bool": pa.bool_(),
        "date32": pa.date32(),
        "timestamp[us,UTC]": (
            pa.timestamp(
                "us",
                tz="UTC",
            )
        ),
    }

    if type_name not in mapping:
        raise ValueError(
            "unsupported contract type: "
            f"{type_name}"
        )

    return mapping[type_name]


def _arrow_schema(
    schema_spec: Sequence[
        dict[str, Any]
    ],
) -> pa.Schema:
    return pa.schema(
        [
            pa.field(
                item["name"],
                _arrow_type(
                    item["type"]
                ),
                nullable=bool(
                    item["nullable"]
                ),
            )
            for item in schema_spec
        ]
    )


def _table_from_frame(
    frame: pd.DataFrame,
    schema_spec: Sequence[
        dict[str, Any]
    ],
) -> pa.Table:
    schema = _arrow_schema(
        schema_spec
    )

    arrays: list[pa.Array] = []

    for field in schema:
        if field.name not in frame.columns:
            raise ValueError(
                "missing expected column: "
                f"{field.name}"
            )

        series = frame[field.name]

        if pa.types.is_string(
            field.type
        ):
            array = pa.array(
                series,
                type=field.type,
                from_pandas=True,
            )

        elif pa.types.is_int64(
            field.type
        ):
            array = pa.array(
                pd.to_numeric(
                    series,
                    errors="raise",
                ),
                type=field.type,
                from_pandas=True,
            )

        elif pa.types.is_float64(
            field.type
        ):
            array = pa.array(
                pd.to_numeric(
                    series,
                    errors="coerce",
                ),
                type=field.type,
                from_pandas=True,
            )

        elif pa.types.is_boolean(
            field.type
        ):
            array = pa.array(
                series,
                type=field.type,
                from_pandas=True,
            )

        elif pa.types.is_timestamp(
            field.type
        ):
            array = pa.array(
                pd.to_datetime(
                    series,
                    errors="coerce",
                    utc=True,
                ),
                type=field.type,
                from_pandas=True,
            )

        elif pa.types.is_date32(
            field.type
        ):
            array = pa.array(
                pd.to_datetime(
                    series,
                    errors="coerce",
                ).dt.date,
                type=field.type,
                from_pandas=True,
            )

        else:
            raise ValueError(
                "unsupported output type: "
                f"{field.type}"
            )

        if (
            not field.nullable
            and array.null_count
        ):
            raise ValueError(
                "non-nullable field contains "
                f"nulls: {field.name}"
            )

        arrays.append(array)

    return pa.Table.from_arrays(
        arrays,
        schema=schema,
    )


def _canonical_scalar_for_fingerprint(
    value: Any,
) -> Any:
    if value is None:
        return None

    if isinstance(value, bool):
        return value

    if isinstance(value, int):
        return value

    if isinstance(value, float):
        if math.isnan(value):
            return {
                "__float__": "nan",
            }

        if math.isinf(value):
            return {
                "__float__": (
                    "positive_infinity"
                    if value > 0
                    else "negative_infinity"
                ),
            }

        return {
            "__float_hex__": value.hex(),
        }

    if isinstance(value, str):
        return value

    if hasattr(value, "isoformat"):
        return {
            "__temporal__": (
                value.isoformat()
            ),
        }

    return {
        "__type__": (
            type(value).__name__
        ),
        "__repr__": repr(value),
    }


def _table_content_fingerprint(
    table: pa.Table,
) -> str:
    combined = table.combine_chunks()

    payload = {
        "schema": [
            {
                "name": field.name,
                "type": str(field.type),
                "nullable": (
                    field.nullable
                ),
            }
            for field in combined.schema
        ],
        "columns": [
            {
                "name": name,
                "values": [
                    _canonical_scalar_for_fingerprint(
                        value
                    )
                    for value in (
                        combined[name]
                        .combine_chunks()
                        .to_pylist()
                    )
                ],
            }
            for name in (
                combined.schema.names
            )
        ],
    }

    encoded = json.dumps(
        payload,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")

    return _sha256_bytes(
        encoded
    )


def _key_fingerprint(
    table: pa.Table,
    key_columns: Sequence[str],
) -> str:
    return _canonical_json_hash(
        table.select(
            list(key_columns)
        ).to_pydict()
    )


def _read_parquet_dataset(
    root: Path,
) -> tuple[
    pa.Table,
    list[Path],
]:
    files = sorted(
        root.rglob("*.parquet")
    )

    if not files:
        raise FileNotFoundError(
            "no parquet files under "
            f"{root}"
        )

    tables = [
        pq.read_table(path)
        for path in files
    ]

    return (
        pa.concat_tables(
            tables,
            promote_options="default",
        ),
        files,
    )


def _load_contract_bundle(
    contract_path: Path,
) -> tuple[
    dict[str, Any],
    dict[str, Any],
]:
    final_contract = json.loads(
        contract_path.read_text(
            encoding="utf-8"
        )
    )

    if final_contract.get("ok") is not True:
        raise ValueError(
            "final contract is not OK"
        )

    if (
        _contract_schema_fingerprint(
            final_contract["outputs"]
        )
        != final_contract[
            "schema_fingerprint"
        ]
    ):
        raise ValueError(
            "final schema fingerprint "
            "cannot be reproduced"
        )

    static_info = (
        final_contract
        .get("inputs", {})
        .get("static_contract", {})
    )

    static_path = Path(
        str(
            static_info.get(
                "path",
                "",
            )
        )
    ).resolve()

    if not static_path.is_file():
        raise FileNotFoundError(
            "static contract missing: "
            f"{static_path}"
        )

    actual_static_sha = (
        _sha256_file(static_path)
    )

    if (
        actual_static_sha
        != static_info.get("sha256")
    ):
        raise ValueError(
            "static contract SHA mismatch"
        )

    static_contract = json.loads(
        static_path.read_text(
            encoding="utf-8"
        )
    )

    if static_contract.get("ok") is not True:
        raise ValueError(
            "static contract is not OK"
        )

    return (
        final_contract,
        static_contract,
    )


def _load_b2_catalogs(
    b2_run_dir: Path,
) -> tuple[
    dict[str, Any],
    pd.DataFrame,
    pd.DataFrame,
]:
    manifest_path = (
        b2_run_dir.resolve()
        / B2_MANIFEST_RELATIVE_PATH
    )

    manifest = json.loads(
        manifest_path.read_text(
            encoding="utf-8"
        )
    )

    outputs = {
        item["name"]: item
        for item in manifest["outputs"]
    }

    family_table, _ = (
        _read_parquet_dataset(
            b2_run_dir.resolve()
            / outputs[
                "family_activity_catalog"
            ][
                "relative_path"
            ]
        )
    )

    pair_table, _ = (
        _read_parquet_dataset(
            b2_run_dir.resolve()
            / outputs[
                "family_priceband_activity_catalog"
            ][
                "relative_path"
            ]
        )
    )

    return (
        manifest,
        family_table.to_pandas(),
        pair_table.to_pandas(),
    )


def _expected_product_master(
    raw: pd.DataFrame,
) -> pd.DataFrame:
    missing = sorted(
        set(SOURCE_REQUIRED_COLUMNS)
        - set(raw.columns)
    )

    if missing:
        raise ValueError(
            "missing source columns: "
            + ",".join(missing)
        )

    codart = raw["codart"].map(
        _clean_text
    )

    tipo_raw = raw["tipo"].map(
        _clean_text
    )

    fascia_raw = raw["fascia"].map(
        _clean_text
    )

    categoria_raw = raw[
        "categoria"
    ].map(_clean_text)

    descrizione = raw[
        "descrizione"
    ].map(_clean_text)

    fascia_operativa = (
        raw["fascia_corretta"]
        .map(_clean_text)
        .fillna(fascia_raw)
    )

    categoria_normalizzata = (
        raw["categoria_corretta"]
        .map(_clean_text)
        .fillna(categoria_raw)
    )

    famiglia_raw = raw[
        "famiglia"
    ].map(_clean_text)

    famiglia_canonical = raw[
        "famiglia"
    ].map(
        lambda value: _clean_text(
            value,
            lower=True,
        )
    )

    prezzo_iva_esclusa = (
        pd.to_numeric(
            raw[
                "prezzo_iva_esclusa"
            ],
            errors="coerce",
        )
    )

    prezzo_iva_inclusa = (
        pd.to_numeric(
            raw[
                "prezzo_iva_inclusa"
            ],
            errors="coerce",
        )
    )

    fascia_prezzo = raw[
        "fascia_prezzo_iva_inc"
    ].map(_clean_text)

    pot_size = raw[
        "pot_size"
    ].map(_clean_text)

    source_load_timestamp = (
        pd.to_datetime(
            raw["load_timestamp"],
            errors="coerce",
            utc=True,
        )
    )

    bounds = fascia_prezzo.map(
        _parse_priceband
    )

    lower = pd.Series(
        [
            item[0]
            for item in bounds
        ],
        index=raw.index,
        dtype=float,
    )

    upper = pd.Series(
        [
            item[1]
            for item in bounds
        ],
        index=raw.index,
        dtype=float,
    )

    open_ended = pd.Series(
        [
            item[2]
            for item in bounds
        ],
        index=raw.index,
        dtype=bool,
    )

    valid_consistency = (
        prezzo_iva_inclusa.notna()
        & lower.notna()
        & upper.notna()
    )

    consistency = pd.Series(
        pd.NA,
        index=raw.index,
        dtype="boolean",
    )

    consistency.loc[
        valid_consistency
    ] = (
        (
            prezzo_iva_inclusa.loc[
                valid_consistency
            ]
            >= lower.loc[
                valid_consistency
            ]
        )
        & (
            np.isinf(
                upper.loc[
                    valid_consistency
                ]
            )
            | (
                prezzo_iva_inclusa.loc[
                    valid_consistency
                ]
                <= upper.loc[
                    valid_consistency
                ]
            )
        )
    )

    frame = pd.DataFrame(
        {
            "codart": codart,
            "tipo_raw": tipo_raw,
            "fascia_raw": fascia_raw,
            "categoria_raw": categoria_raw,
            "descrizione": descrizione,
            "fascia_operativa": (
                fascia_operativa
            ),
            "categoria_normalizzata": (
                categoria_normalizzata
            ),
            "famiglia_raw": famiglia_raw,
            "famiglia_canonical": (
                famiglia_canonical
            ),
            "prezzo_iva_esclusa": (
                prezzo_iva_esclusa
            ),
            "prezzo_iva_inclusa": (
                prezzo_iva_inclusa
            ),
            "fascia_prezzo_iva_inc": (
                fascia_prezzo
            ),
            "priceband_lower": lower,
            "priceband_upper": upper,
            "priceband_is_open_ended": (
                open_ended
            ),
            "pot_size": pot_size,
            "source_load_timestamp": (
                source_load_timestamp
            ),
            "is_family_known": (
                famiglia_canonical.notna()
            ),
            "is_priceband_known": (
                fascia_prezzo.notna()
            ),
            "is_pot_size_known": (
                pot_size.notna()
            ),
            "is_zero_price": (
                prezzo_iva_inclusa
                .eq(0)
                .fillna(False)
            ),
            "is_priceband_consistent": (
                consistency
            ),
        }
    )

    if frame["codart"].isna().any():
        raise ValueError(
            "codart contains nulls"
        )

    if frame["codart"].duplicated().any():
        raise ValueError(
            "codart contains duplicates"
        )

    if frame[
        "source_load_timestamp"
    ].isna().any():
        raise ValueError(
            "source timestamp contains nulls"
        )

    return (
        frame.sort_values(
            ["codart"],
            kind="mergesort",
        )
        .reset_index(drop=True)
    )


def _expected_family_base(
    master: pd.DataFrame,
) -> pd.DataFrame:
    usable = master.loc[
        master["is_family_known"]
    ].copy()

    rows: list[
        dict[str, Any]
    ] = []

    for family, group in usable.groupby(
        "famiglia_canonical",
        sort=True,
        dropna=False,
    ):
        product_count = int(
            group["codart"].nunique()
        )

        rows.append(
            {
                "famiglia_canonical": family,
                "product_count": (
                    product_count
                ),
                "unique_description_ratio": (
                    float(
                        group[
                            "descrizione"
                        ].nunique(
                            dropna=True
                        )
                        / product_count
                    )
                ),
                "priceband_count": int(
                    group[
                        "fascia_prezzo_iva_inc"
                    ].nunique(
                        dropna=True
                    )
                ),
                "dominant_priceband_share": (
                    _dominant_share(
                        group[
                            "fascia_prezzo_iva_inc"
                        ]
                    )
                ),
                "priceband_entropy": (
                    _normalized_entropy(
                        group[
                            "fascia_prezzo_iva_inc"
                        ],
                        null_when_empty=False,
                    )
                ),
                "pot_size_count": int(
                    group[
                        "pot_size"
                    ].nunique(
                        dropna=True
                    )
                ),
                "pot_size_coverage_ratio": (
                    float(
                        group[
                            "is_pot_size_known"
                        ].sum()
                        / product_count
                    )
                ),
                "pot_size_entropy": (
                    _normalized_entropy(
                        group["pot_size"],
                        null_when_empty=True,
                    )
                ),
                "main_category": (
                    _safe_mode(
                        group[
                            "categoria_normalizzata"
                        ]
                    )
                ),
                "main_operational_band": (
                    _safe_mode(
                        group[
                            "fascia_operativa"
                        ]
                    )
                ),
            }
        )

    return pd.DataFrame(rows)


def _expected_pair_base(
    master: pd.DataFrame,
    family_base: pd.DataFrame,
) -> pd.DataFrame:
    usable = master.loc[
        master["is_family_known"]
        & master["is_priceband_known"]
    ].copy()

    family_totals = (
        family_base
        .set_index(
            "famiglia_canonical"
        )[
            "product_count"
        ]
        .to_dict()
    )

    rows: list[
        dict[str, Any]
    ] = []

    for (
        family,
        priceband,
    ), group in usable.groupby(
        [
            "famiglia_canonical",
            "fascia_prezzo_iva_inc",
        ],
        sort=True,
        dropna=False,
    ):
        product_count = int(
            group["codart"].nunique()
        )

        rows.append(
            {
                "famiglia_canonical": (
                    family
                ),
                "priceband_canonical": (
                    priceband
                ),
                "product_count_in_band": (
                    product_count
                ),
                "product_share_of_family": (
                    float(
                        product_count
                        / int(
                            family_totals[
                                family
                            ]
                        )
                    )
                ),
                "pot_size_count_in_band": int(
                    group[
                        "pot_size"
                    ].nunique(
                        dropna=True
                    )
                ),
                "pot_size_coverage_ratio_in_band": (
                    float(
                        group[
                            "is_pot_size_known"
                        ].sum()
                        / product_count
                    )
                ),
                "pot_size_entropy_in_band": (
                    _normalized_entropy(
                        group["pot_size"],
                        null_when_empty=True,
                    )
                ),
                "main_category_in_band": (
                    _safe_mode(
                        group[
                            "categoria_normalizzata"
                        ]
                    )
                ),
            }
        )

    return pd.DataFrame(rows)


def _align_expected_family(
    catalog: pd.DataFrame,
    family_base: pd.DataFrame,
) -> pd.DataFrame:
    keys = catalog[
        ["famiglia"]
    ].copy()

    keys[
        "famiglia_canonical"
    ] = keys["famiglia"].map(
        lambda value: _clean_text(
            value,
            lower=True,
        )
    )

    frame = keys.merge(
        family_base,
        on="famiglia_canonical",
        how="left",
        validate="many_to_one",
    )

    if frame[
        "product_count"
    ].isna().any():
        raise ValueError(
            "family coverage incomplete"
        )

    return (
        frame.sort_values(
            ["famiglia"],
            kind="mergesort",
        )
        .reset_index(drop=True)
    )


def _align_expected_pair(
    catalog: pd.DataFrame,
    pair_base: pd.DataFrame,
) -> pd.DataFrame:
    keys = catalog[
        [
            "famiglia",
            "fascia_prezzo_iva_inc",
        ]
    ].copy()

    keys[
        "famiglia_canonical"
    ] = keys["famiglia"].map(
        lambda value: _clean_text(
            value,
            lower=True,
        )
    )

    keys[
        "priceband_canonical"
    ] = keys[
        "fascia_prezzo_iva_inc"
    ].map(_clean_text)

    frame = keys.merge(
        pair_base,
        on=[
            "famiglia_canonical",
            "priceband_canonical",
        ],
        how="left",
        validate="many_to_one",
    )

    if frame[
        "product_count_in_band"
    ].isna().any():
        raise ValueError(
            "pair coverage incomplete"
        )

    frame = frame.drop(
        columns=[
            "priceband_canonical"
        ]
    )

    return (
        frame.sort_values(
            [
                "famiglia",
                "fascia_prezzo_iva_inc",
            ],
            kind="mergesort",
        )
        .reset_index(drop=True)
    )


def _prepare_expected_tables(
    config: ProductFeatureValidationConfig,
) -> tuple[
    dict[str, Any],
    dict[str, pa.Table],
]:
    (
        final_contract,
        static_contract,
    ) = _load_contract_bundle(
        config.contract_path.resolve()
    )

    product_path = (
        config.source_run_dir.resolve()
        / PRODUCT_SOURCE_RELATIVE_PATH
    )

    if not product_path.is_file():
        raise FileNotFoundError(
            "product source missing: "
            f"{product_path}"
        )

    actual_source_sha = (
        _sha256_file(product_path)
    )

    expected_source_sha = (
        static_contract[
            "source"
        ][
            "sha256"
        ]
    )

    if (
        actual_source_sha
        != expected_source_sha
    ):
        raise ValueError(
            "product source SHA mismatch"
        )

    (
        b2_manifest,
        family_catalog,
        pair_catalog,
    ) = _load_b2_catalogs(
        config.b2_run_dir.resolve()
    )

    if (
        b2_manifest[
            "output_schema_fingerprint"
        ]
        != static_contract[
            "b2_baseline"
        ][
            "schema_fingerprint"
        ]
    ):
        raise ValueError(
            "B2 schema fingerprint mismatch"
        )

    raw = pq.read_table(
        product_path
    ).to_pandas()

    expected_source_rows = int(
        final_contract[
            "validation_contract"
        ][
            "source_product_rows_exact"
        ]
    )

    if len(raw) != expected_source_rows:
        raise ValueError(
            "source row count mismatch"
        )

    master = _expected_product_master(
        raw
    )

    family_base = (
        _expected_family_base(
            master
        )
    )

    pair_base = (
        _expected_pair_base(
            master,
            family_base,
        )
    )

    family = _align_expected_family(
        family_catalog,
        family_base,
    )

    pair = _align_expected_pair(
        pair_catalog,
        pair_base,
    )

    frames = {
        "product_master_canonical": (
            master
        ),
        "family_product_features": (
            family
        ),
        "family_priceband_product_features": (
            pair
        ),
    }

    tables: dict[
        str,
        pa.Table,
    ] = {}

    for name in OUTPUT_ORDER:
        output_contract = (
            final_contract[
                "outputs"
            ][name]
        )

        table = _table_from_frame(
            frames[name],
            output_contract["schema"],
        )

        if (
            table.num_rows
            != int(
                output_contract[
                    "expected_rows"
                ]
            )
        ):
            raise ValueError(
                f"{name} expected row "
                "count mismatch"
            )

        keys = list(
            OUTPUT_KEYS[name]
        )

        key_frame = (
            table.select(keys)
            .to_pandas()
        )

        if key_frame.duplicated(
            subset=keys
        ).any():
            raise ValueError(
                f"{name} duplicate keys"
            )

        tables[name] = table

    return (
        final_contract,
        tables,
    )


def _parquet_compressions(
    files: Sequence[Path],
) -> set[str]:
    codecs: set[str] = set()

    for path in files:
        metadata = (
            pq.ParquetFile(path)
            .metadata
        )

        for row_group_index in range(
            metadata.num_row_groups
        ):
            row_group = metadata.row_group(
                row_group_index
            )

            for column_index in range(
                row_group.num_columns
            ):
                codecs.add(
                    str(
                        row_group.column(
                            column_index
                        ).compression
                    ).upper()
                )

    return codecs


def _validate_one_dataset(
    *,
    name: str,
    expected: pa.Table,
    output_contract: dict[str, Any],
    config: ProductFeatureValidationConfig,
) -> ProductFeatureDatasetValidation:
    issues: list[str] = []

    expected_schema_fp = (
        _schema_fingerprint(
            output_contract["schema"]
        )
    )

    expected_key_fp = (
        _key_fingerprint(
            expected,
            OUTPUT_KEYS[name],
        )
    )

    expected_content_fp = (
        _table_content_fingerprint(
            expected
        )
    )

    if config.mode == "plan":
        return ProductFeatureDatasetValidation(
            name=name,
            ok=True,
            row_count=expected.num_rows,
            file_count=0,
            bytes=0,
            schema_fingerprint=(
                expected_schema_fp
            ),
            key_fingerprint=(
                expected_key_fp
            ),
            content_fingerprint=(
                expected_content_fp
            ),
            issues=(),
        )

    output_root = (
        config.run_dir.resolve()
        / output_contract[
            "relative_path"
        ]
    )

    try:
        actual, files = (
            _read_parquet_dataset(
                output_root
            )
        )
    except Exception as exc:
        return ProductFeatureDatasetValidation(
            name=name,
            ok=False,
            row_count=0,
            file_count=0,
            bytes=0,
            schema_fingerprint="",
            key_fingerprint="",
            content_fingerprint="",
            issues=(
                f"{type(exc).__name__}: "
                f"{exc}",
            ),
        )

    file_count = len(files)

    total_bytes = sum(
        path.stat().st_size
        for path in files
    )

    if file_count != int(
        output_contract["file_count"]
    ):
        issues.append(
            "file count mismatch: "
            f"expected="
            f"{output_contract['file_count']} "
            f"actual={file_count}"
        )

    expected_schema = _arrow_schema(
        output_contract["schema"]
    )

    if actual.schema != expected_schema:
        issues.append(
            "Arrow schema mismatch"
        )

    if actual.num_rows != expected.num_rows:
        issues.append(
            "row count mismatch: "
            f"expected={expected.num_rows} "
            f"actual={actual.num_rows}"
        )

    actual_columns = actual.schema.names

    expected_columns = (
        expected_schema.names
    )

    if actual_columns != expected_columns:
        issues.append(
            "column order mismatch"
        )

    keys = list(
        OUTPUT_KEYS[name]
    )

    if all(
        key in actual_columns
        for key in keys
    ):
        actual_key_frame = (
            actual.select(keys)
            .to_pandas()
        )

        if actual_key_frame.duplicated(
            subset=keys
        ).any():
            issues.append(
                "duplicate output keys"
            )

        sorted_key_frame = (
            actual_key_frame.sort_values(
                keys,
                kind="mergesort",
            )
            .reset_index(drop=True)
        )

        if not actual_key_frame.reset_index(
            drop=True
        ).equals(sorted_key_frame):
            issues.append(
                "output keys are not "
                "deterministically sorted"
            )

    codecs = _parquet_compressions(
        files
    )

    if codecs != {"ZSTD"}:
        issues.append(
            "unexpected compression codecs: "
            f"{sorted(codecs)}"
        )

    actual_schema_fp = (
        _schema_fingerprint(
            output_contract["schema"]
        )
    )

    actual_key_fp = (
        _key_fingerprint(
            actual,
            OUTPUT_KEYS[name],
        )
    )

    actual_content_fp = (
        _table_content_fingerprint(
            actual
        )
    )

    if actual_key_fp != expected_key_fp:
        issues.append(
            "key fingerprint mismatch"
        )

    if (
        actual_content_fp
        != expected_content_fp
    ):
        issues.append(
            "content fingerprint mismatch"
        )

    return ProductFeatureDatasetValidation(
        name=name,
        ok=not issues,
        row_count=actual.num_rows,
        file_count=file_count,
        bytes=total_bytes,
        schema_fingerprint=(
            actual_schema_fp
        ),
        key_fingerprint=(
            actual_key_fp
        ),
        content_fingerprint=(
            actual_content_fp
        ),
        issues=tuple(issues),
    )


def validate_product_features(
    config: ProductFeatureValidationConfig,
) -> ProductFeatureValidationResult:
    datasets: list[
        ProductFeatureDatasetValidation
    ] = []

    issues: list[str] = []

    try:
        if config.mode not in ALLOWED_MODES:
            raise ValueError(
                "unsupported validation mode: "
                f"{config.mode}"
            )

        if (
            config.mode == "plan"
            and config.run_dir.exists()
        ):
            raise ValueError(
                "plan mode run directory "
                "must not exist"
            )

        (
            final_contract,
            expected_tables,
        ) = _prepare_expected_tables(
            config
        )

        for name in OUTPUT_ORDER:
            result = _validate_one_dataset(
                name=name,
                expected=expected_tables[name],
                output_contract=(
                    final_contract[
                        "outputs"
                    ][name]
                ),
                config=config,
            )

            datasets.append(result)

            if not result.ok:
                issues.extend(
                    f"{name}: {issue}"
                    for issue in result.issues
                )

        if config.mode != "plan":
            temporary_files = sorted(
                str(path)
                for path in (
                    config.run_dir.resolve()
                ).rglob("*")
                if (
                    path.is_file()
                    and (
                        path.name.endswith(
                            ".tmp"
                        )
                        or path.name.endswith(
                            ".partial"
                        )
                        or path.name.startswith(
                            ".part-"
                        )
                    )
                )
            )

            if temporary_files:
                issues.append(
                    "temporary files remain: "
                    + ",".join(
                        temporary_files[:20]
                    )
                )

        decision = (
            "PRODUCT_FEATURE_"
            f"{config.mode.upper()}_"
            "VALIDATION_OK"
            if not issues
            else
            "PRODUCT_FEATURE_"
            f"{config.mode.upper()}_"
            "VALIDATION_FAILED"
        )

        result = (
            ProductFeatureValidationResult(
                ok=not issues,
                decision=decision,
                mode=config.mode,
                run_dir=str(
                    config.run_dir.resolve()
                ),
                datasets=tuple(datasets),
                issues=tuple(issues),
            )
        )

    except Exception as exc:
        result = (
            ProductFeatureValidationResult(
                ok=False,
                decision=(
                    "PRODUCT_FEATURE_"
                    f"{config.mode.upper()}_"
                    "VALIDATION_FAILED"
                ),
                mode=config.mode,
                run_dir=str(
                    config.run_dir.resolve()
                ),
                datasets=tuple(datasets),
                issues=(
                    f"{type(exc).__name__}: "
                    f"{exc}",
                ),
            )
        )

    if config.report_path is not None:
        config.report_path.parent.mkdir(
            parents=True,
            exist_ok=True,
        )

        config.report_path.write_text(
            json.dumps(
                result.to_dict(),
                indent=2,
                sort_keys=True,
            )
            + "\n",
            encoding="utf-8",
        )

    return result


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--run-dir",
        required=True,
        type=Path,
    )

    parser.add_argument(
        "--source-run-dir",
        required=True,
        type=Path,
    )

    parser.add_argument(
        "--b2-run-dir",
        required=True,
        type=Path,
    )

    parser.add_argument(
        "--contract-path",
        required=True,
        type=Path,
    )

    parser.add_argument(
        "--mode",
        required=True,
        choices=ALLOWED_MODES,
    )

    parser.add_argument(
        "--report-path",
        type=Path,
    )

    parser.add_argument(
        "--logical-run-dir",
        type=Path,
    )

    parser.add_argument(
        "--no-source-reconciliation",
        action="store_true",
    )

    return parser.parse_args()


def main() -> int:
    args = _parse_args()

    result = validate_product_features(
        ProductFeatureValidationConfig(
            run_dir=args.run_dir,
            source_run_dir=(
                args.source_run_dir
            ),
            b2_run_dir=(
                args.b2_run_dir
            ),
            contract_path=(
                args.contract_path
            ),
            mode=args.mode,
            report_path=(
                args.report_path
            ),
            logical_run_dir=(
                args.logical_run_dir
            ),
            validate_source_reconciliation=(
                not args.no_source_reconciliation
            ),
        )
    )

    print(
        json.dumps(
            result.to_dict(),
            indent=2,
            sort_keys=True,
        )
    )

    return 0 if result.ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
