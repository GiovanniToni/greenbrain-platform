from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import shutil
import unicodedata
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
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


@dataclass(frozen=True)
class ProductFeatureConfig:
    source_run_dir: Path
    b2_run_dir: Path
    run_dir: Path
    contract_path: Path
    build_id: str
    compression: str = "zstd"
    execute: bool = False
    confirm_write_feature_lake: bool = False
    failure_injection_point: str | None = None


@dataclass(frozen=True)
class ProductFeatureOutputResult:
    name: str
    relative_path: str
    row_count: int
    file_count: int
    bytes: int
    schema_fingerprint: str
    key_fingerprint: str
    content_fingerprint: str


@dataclass(frozen=True)
class ProductFeatureBuildResult:
    ok: bool
    decision: str
    mode: str
    run_dir: str
    outputs: tuple[ProductFeatureOutputResult, ...]
    issues: tuple[str, ...]

    def to_dict(self) -> dict[str, Any]:
        payload = asdict(self)
        payload["outputs"] = [
            asdict(item)
            for item in self.outputs
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
    encoded = json.dumps(
        payload,
        sort_keys=True,
        separators=(",", ":"),
        default=str,
    ).encode("utf-8")

    return _sha256_bytes(encoded)


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
            name: outputs[name][
                "schema"
            ]
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
                "missing output column: "
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
            timestamps = pd.to_datetime(
                series,
                errors="coerce",
                utc=True,
            )

            array = pa.array(
                timestamps,
                type=field.type,
                from_pandas=True,
            )

        elif pa.types.is_date32(
            field.type
        ):
            dates = pd.to_datetime(
                series,
                errors="coerce",
            ).dt.date

            array = pa.array(
                dates,
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
                "non-nullable output column "
                "contains nulls: "
                f"{field.name}"
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
) -> pd.DataFrame:
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

    return pa.concat_tables(
        tables,
        promote_options="default",
    ).to_pandas()


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
            "final C2 contract is not OK"
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

    expected_sha = static_info.get(
        "sha256"
    )

    actual_sha = _sha256_file(
        static_path
    )

    if expected_sha != actual_sha:
        raise ValueError(
            "static contract SHA mismatch: "
            f"expected={expected_sha} "
            f"actual={actual_sha}"
        )

    static_contract = json.loads(
        static_path.read_text(
            encoding="utf-8"
        )
    )

    if static_contract.get("ok") is not True:
        raise ValueError(
            "static C2 contract is not OK"
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
        b2_run_dir
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

    family_root = (
        b2_run_dir
        / outputs[
            "family_activity_catalog"
        ][
            "relative_path"
        ]
    )

    pair_root = (
        b2_run_dir
        / outputs[
            "family_priceband_activity_catalog"
        ][
            "relative_path"
        ]
    )

    return (
        manifest,
        _read_parquet_dataset(
            family_root
        ),
        _read_parquet_dataset(
            pair_root
        ),
    )


def _build_product_master(
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

    within_lower = (
        prezzo_iva_inclusa
        >= lower
    )

    within_upper = (
        np.isinf(upper)
        | (
            prezzo_iva_inclusa
            <= upper
        )
    )

    consistency.loc[
        valid_consistency
    ] = (
        within_lower.loc[
            valid_consistency
        ]
        & within_upper.loc[
            valid_consistency
        ]
    )

    master = pd.DataFrame(
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

    if master["codart"].isna().any():
        raise ValueError(
            "codart contains null values"
        )

    if master["codart"].duplicated().any():
        raise ValueError(
            "codart contains duplicate values"
        )

    if master[
        "source_load_timestamp"
    ].isna().any():
        raise ValueError(
            "source_load_timestamp "
            "contains null values"
        )

    return (
        master.sort_values(
            ["codart"],
            kind="mergesort",
        )
        .reset_index(drop=True)
    )


def _build_family_aggregates(
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


def _build_pair_aggregates(
    master: pd.DataFrame,
    family_aggregates: pd.DataFrame,
) -> pd.DataFrame:
    usable = master.loc[
        master["is_family_known"]
        & master["is_priceband_known"]
    ].copy()

    family_totals = (
        family_aggregates
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

        family_total = int(
            family_totals[family]
        )

        rows.append(
            {
                "famiglia_canonical": family,
                "priceband_canonical": (
                    priceband
                ),
                "product_count_in_band": (
                    product_count
                ),
                "product_share_of_family": (
                    float(
                        product_count
                        / family_total
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


def _align_family_to_b2(
    catalog: pd.DataFrame,
    aggregates: pd.DataFrame,
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

    output = keys.merge(
        aggregates,
        on="famiglia_canonical",
        how="left",
        validate="many_to_one",
    )

    if output[
        "product_count"
    ].isna().any():
        missing = (
            output.loc[
                output[
                    "product_count"
                ].isna(),
                "famiglia",
            ]
            .astype(str)
            .head(20)
            .tolist()
        )

        raise ValueError(
            "B2 family coverage "
            "incomplete: "
            + ",".join(missing)
        )

    return (
        output.sort_values(
            ["famiglia"],
            kind="mergesort",
        )
        .reset_index(drop=True)
    )


def _align_pair_to_b2(
    catalog: pd.DataFrame,
    aggregates: pd.DataFrame,
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

    output = keys.merge(
        aggregates,
        on=[
            "famiglia_canonical",
            "priceband_canonical",
        ],
        how="left",
        validate="many_to_one",
    )

    if output[
        "product_count_in_band"
    ].isna().any():
        missing = (
            output.loc[
                output[
                    "product_count_in_band"
                ].isna(),
                [
                    "famiglia",
                    "fascia_prezzo_iva_inc",
                ],
            ]
            .head(20)
            .astype(str)
            .agg("|".join, axis=1)
            .tolist()
        )

        raise ValueError(
            "B2 family-priceband coverage "
            "incomplete: "
            + ",".join(missing)
        )

    output = output.drop(
        columns=[
            "priceband_canonical"
        ]
    )

    return (
        output.sort_values(
            [
                "famiglia",
                "fascia_prezzo_iva_inc",
            ],
            kind="mergesort",
        )
        .reset_index(drop=True)
    )


def _prepare_tables(
    config: ProductFeatureConfig,
) -> tuple[
    dict[str, Any],
    dict[str, pa.Table],
    dict[str, Sequence[str]],
]:
    (
        final_contract,
        static_contract,
    ) = _load_contract_bundle(
        config.contract_path.resolve()
    )

    actual_schema_fingerprint = (
        _contract_schema_fingerprint(
            final_contract["outputs"]
        )
    )

    if (
        actual_schema_fingerprint
        != final_contract[
            "schema_fingerprint"
        ]
    ):
        raise ValueError(
            "final C2 schema fingerprint "
            "cannot be reproduced"
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

    expected_source_sha = (
        static_contract[
            "source"
        ][
            "sha256"
        ]
    )

    actual_source_sha = (
        _sha256_file(product_path)
    )

    if (
        actual_source_sha
        != expected_source_sha
    ):
        raise ValueError(
            "product source SHA mismatch: "
            f"expected={expected_source_sha} "
            f"actual={actual_source_sha}"
        )

    (
        b2_manifest,
        family_catalog,
        pair_catalog,
    ) = _load_b2_catalogs(
        config.b2_run_dir.resolve()
    )

    expected_b2_schema = (
        static_contract[
            "b2_baseline"
        ][
            "schema_fingerprint"
        ]
    )

    actual_b2_schema = (
        b2_manifest[
            "output_schema_fingerprint"
        ]
    )

    if (
        actual_b2_schema
        != expected_b2_schema
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
            "source row count mismatch: "
            f"expected={expected_source_rows} "
            f"actual={len(raw)}"
        )

    master = _build_product_master(
        raw
    )

    family_base = (
        _build_family_aggregates(
            master
        )
    )

    pair_base = (
        _build_pair_aggregates(
            master,
            family_base,
        )
    )

    family = _align_family_to_b2(
        family_catalog,
        family_base,
    )

    pair = _align_pair_to_b2(
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

    keys: dict[
        str,
        Sequence[str],
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
            output_contract[
                "schema"
            ],
        )

        expected_rows = int(
            output_contract[
                "expected_rows"
            ]
        )

        if (
            table.num_rows
            != expected_rows
        ):
            raise ValueError(
                f"{name} row count mismatch: "
                f"expected={expected_rows} "
                f"actual={table.num_rows}"
            )

        tables[name] = table

    return (
        final_contract,
        tables,
        keys,
    )


def _write_json_atomic(
    path: Path,
    payload: Any,
) -> None:
    path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    temporary = path.with_name(
        f".{path.name}.tmp-{os.getpid()}"
    )

    temporary.write_text(
        json.dumps(
            payload,
            indent=2,
            sort_keys=True,
            default=str,
        )
        + "\n",
        encoding="utf-8",
    )

    os.replace(
        temporary,
        path,
    )


def _candidate_run_dir(
    final_run_dir: Path,
    build_id: str,
) -> Path:
    safe_build_id = re.sub(
        r"[^A-Za-z0-9_.-]+",
        "-",
        build_id,
    ).strip(".-")

    if not safe_build_id:
        safe_build_id = "build"

    return (
        final_run_dir.parent
        / (
            f".{final_run_dir.name}"
            f".candidate-{safe_build_id}"
            f"-{os.getpid()}"
        )
    )


def _inject_failure(
    config: ProductFeatureConfig,
    point: str,
) -> None:
    if (
        config.failure_injection_point
        == point
    ):
        raise RuntimeError(
            "injected failure at "
            f"{point}"
        )


def _write_candidate_tables(
    *,
    config: ProductFeatureConfig,
    candidate_run_dir: Path,
    final_contract: dict[str, Any],
    tables: dict[str, pa.Table],
    keys: dict[
        str,
        Sequence[str],
    ],
) -> tuple[
    ProductFeatureOutputResult,
    ...,
]:
    if config.compression.lower() != "zstd":
        raise ValueError(
            "C2 materialization requires "
            "compression=zstd"
        )

    results: list[
        ProductFeatureOutputResult
    ] = []

    failure_points = {
        "product_master_canonical": (
            "after_master_written"
        ),
        "family_product_features": (
            "after_family_written"
        ),
        "family_priceband_product_features": (
            "after_pair_written"
        ),
    }

    for name in OUTPUT_ORDER:
        output_contract = (
            final_contract[
                "outputs"
            ][name]
        )

        output_root = (
            candidate_run_dir
            / output_contract[
                "relative_path"
            ]
        )

        output_root.mkdir(
            parents=True,
            exist_ok=False,
        )

        output_file = (
            output_root
            / "part-00000.parquet"
        )

        table = tables[name].combine_chunks()

        pq.write_table(
            table,
            output_file,
            compression="zstd",
            use_dictionary=True,
            write_statistics=True,
        )

        if not output_file.is_file():
            raise RuntimeError(
                "parquet output was not created: "
                f"{output_file}"
            )

        output_bytes = (
            output_file.stat().st_size
        )

        if output_bytes <= 0:
            raise RuntimeError(
                "empty parquet output: "
                f"{output_file}"
            )

        results.append(
            ProductFeatureOutputResult(
                name=name,
                relative_path=str(
                    output_contract[
                        "relative_path"
                    ]
                ),
                row_count=(
                    table.num_rows
                ),
                file_count=1,
                bytes=output_bytes,
                schema_fingerprint=(
                    _schema_fingerprint(
                        output_contract[
                            "schema"
                        ]
                    )
                ),
                key_fingerprint=(
                    _key_fingerprint(
                        table,
                        keys[name],
                    )
                ),
                content_fingerprint=(
                    _table_content_fingerprint(
                        table
                    )
                ),
            )
        )

        _inject_failure(
            config,
            failure_points[name],
        )

    return tuple(results)


def _build_materialization_manifest(
    *,
    config: ProductFeatureConfig,
    final_contract: dict[str, Any],
    static_contract: dict[str, Any],
    tables: dict[str, pa.Table],
    outputs: Sequence[
        ProductFeatureOutputResult
    ],
    candidate_validation: dict[
        str,
        Any,
    ],
    final_validation: dict[
        str,
        Any,
    ] | None,
) -> dict[str, Any]:
    product_path = (
        config.source_run_dir.resolve()
        / PRODUCT_SOURCE_RELATIVE_PATH
    )

    b2_manifest_path = (
        config.b2_run_dir.resolve()
        / B2_MANIFEST_RELATIVE_PATH
    )

    master = tables[
        "product_master_canonical"
    ].to_pandas()

    output_map = {
        item.name: item
        for item in outputs
    }

    manifest_outputs = []

    for name in OUTPUT_ORDER:
        item = output_map[name]
        contract_output = (
            final_contract[
                "outputs"
            ][name]
        )

        manifest_outputs.append(
            {
                **asdict(item),
                "grain": list(
                    contract_output[
                        "grain"
                    ]
                ),
                "compression": "zstd",
                "sort": list(
                    {
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
                    }[name]
                ),
            }
        )

    quality = {
        "product_rows": int(
            len(master)
        ),
        "unknown_family_rows": int(
            (
                ~master[
                    "is_family_known"
                ]
            ).sum()
        ),
        "unknown_priceband_rows": int(
            (
                ~master[
                    "is_priceband_known"
                ]
            ).sum()
        ),
        "unknown_pot_size_rows": int(
            (
                ~master[
                    "is_pot_size_known"
                ]
            ).sum()
        ),
        "zero_price_rows": int(
            master[
                "is_zero_price"
            ].sum()
        ),
        "priceband_inconsistent_rows": int(
            master[
                "is_priceband_consistent"
            ]
            .eq(False)
            .sum()
        ),
    }

    return {
        "build_id": config.build_id,
        "created_at": (
            datetime.now(
                timezone.utc
            ).isoformat()
        ),
        "mode": "materialized",
        "source": {
            "run_dir": str(
                config.source_run_dir.resolve()
            ),
            "dataset": (
                "raw_extracts/"
                "products_normalized"
            ),
            "path": str(product_path),
            "sha256": (
                _sha256_file(
                    product_path
                )
            ),
            "row_count": int(
                tables[
                    "product_master_canonical"
                ].num_rows
            ),
        },
        "b2_baseline": {
            "run_dir": str(
                config.b2_run_dir.resolve()
            ),
            "manifest_path": str(
                b2_manifest_path
            ),
            "manifest_sha256": (
                _sha256_file(
                    b2_manifest_path
                )
            ),
            "schema_fingerprint": (
                static_contract[
                    "b2_baseline"
                ][
                    "schema_fingerprint"
                ]
            ),
        },
        "contract": {
            "path": str(
                config.contract_path.resolve()
            ),
            "sha256": (
                _sha256_file(
                    config.contract_path.resolve()
                )
            ),
            "version": (
                final_contract[
                    "contract_version"
                ]
            ),
            "schema_fingerprint": (
                final_contract[
                    "schema_fingerprint"
                ]
            ),
        },
        "normalization": (
            static_contract[
                "normalization"
            ]
        ),
        "outputs": manifest_outputs,
        "quality": quality,
        "validation": {
            "candidate": (
                candidate_validation
            ),
            "final": final_validation,
        },
        "safety": {
            "parquet_only": True,
            "atomic_candidate_to_final": (
                True
            ),
            "database_read": False,
            "database_write": False,
            "supabase_access": False,
            "source_write": False,
            "b2_write": False,
            "latest_pointer_update": False,
            "overwrite_existing_final": (
                False
            ),
        },
    }


def build_product_features(
    config: ProductFeatureConfig,
) -> ProductFeatureBuildResult:
    outputs: list[
        ProductFeatureOutputResult
    ] = []

    candidate_run_dir: Path | None = None
    final_run_dir = (
        config.run_dir.resolve()
    )
    promoted = False

    try:
        (
            final_contract,
            tables,
            keys,
        ) = _prepare_tables(config)

        if not config.execute:
            for name in OUTPUT_ORDER:
                output_contract = (
                    final_contract[
                        "outputs"
                    ][name]
                )

                table = tables[name]

                outputs.append(
                    ProductFeatureOutputResult(
                        name=name,
                        relative_path=str(
                            output_contract[
                                "relative_path"
                            ]
                        ),
                        row_count=(
                            table.num_rows
                        ),
                        file_count=0,
                        bytes=0,
                        schema_fingerprint=(
                            _schema_fingerprint(
                                output_contract[
                                    "schema"
                                ]
                            )
                        ),
                        key_fingerprint=(
                            _key_fingerprint(
                                table,
                                keys[name],
                            )
                        ),
                        content_fingerprint=(
                            _table_content_fingerprint(
                                table
                            )
                        ),
                    )
                )

            return ProductFeatureBuildResult(
                ok=True,
                decision=(
                    "PRODUCT_FEATURE_PLAN_OK"
                ),
                mode="plan",
                run_dir=str(
                    final_run_dir
                ),
                outputs=tuple(outputs),
                issues=(),
            )

        if (
            not config
            .confirm_write_feature_lake
        ):
            raise PermissionError(
                "materialization requires "
                "confirm_write_feature_lake=True"
            )

        if final_run_dir.exists():
            raise FileExistsError(
                "final C2 run already exists: "
                f"{final_run_dir}"
            )

        final_run_dir.parent.mkdir(
            parents=True,
            exist_ok=True,
        )

        candidate_run_dir = (
            _candidate_run_dir(
                final_run_dir,
                config.build_id,
            )
        )

        if candidate_run_dir.exists():
            raise FileExistsError(
                "candidate C2 run already exists: "
                f"{candidate_run_dir}"
            )

        candidate_run_dir.mkdir(
            parents=False,
            exist_ok=False,
        )

        _inject_failure(
            config,
            "after_candidate_directory_created",
        )

        written_outputs = (
            _write_candidate_tables(
                config=config,
                candidate_run_dir=(
                    candidate_run_dir
                ),
                final_contract=(
                    final_contract
                ),
                tables=tables,
                keys=keys,
            )
        )

        outputs.extend(
            written_outputs
        )

        from jobs.datasets.product_feature_validation import (
            ProductFeatureValidationConfig,
            validate_product_features,
        )

        candidate_report_path = (
            candidate_run_dir
            / "analysis"
            / (
                "product_feature_"
                "candidate_validation.json"
            )
        )

        candidate_validation = (
            validate_product_features(
                ProductFeatureValidationConfig(
                    run_dir=(
                        candidate_run_dir
                    ),
                    source_run_dir=(
                        config.source_run_dir
                    ),
                    b2_run_dir=(
                        config.b2_run_dir
                    ),
                    contract_path=(
                        config.contract_path
                    ),
                    mode="candidate",
                    report_path=(
                        candidate_report_path
                    ),
                    logical_run_dir=(
                        final_run_dir
                    ),
                    validate_source_reconciliation=True,
                )
            )
        )

        if not candidate_validation.ok:
            raise RuntimeError(
                "candidate validation failed: "
                + "; ".join(
                    candidate_validation.issues
                )
            )

        _inject_failure(
            config,
            "after_candidate_validation",
        )

        (
            _,
            static_contract,
        ) = _load_contract_bundle(
            config.contract_path.resolve()
        )

        manifest_path = (
            candidate_run_dir
            / "metadata"
            / "product_feature_manifest.json"
        )

        manifest = (
            _build_materialization_manifest(
                config=config,
                final_contract=(
                    final_contract
                ),
                static_contract=(
                    static_contract
                ),
                tables=tables,
                outputs=written_outputs,
                candidate_validation=(
                    candidate_validation
                    .to_dict()
                ),
                final_validation=None,
            )
        )

        _write_json_atomic(
            manifest_path,
            manifest,
        )

        _inject_failure(
            config,
            "after_candidate_manifest_written",
        )

        os.replace(
            candidate_run_dir,
            final_run_dir,
        )

        promoted = True

        _inject_failure(
            config,
            "after_atomic_promotion",
        )

        final_report_path = (
            final_run_dir
            / "analysis"
            / (
                "product_feature_"
                "validation.json"
            )
        )

        final_validation = (
            validate_product_features(
                ProductFeatureValidationConfig(
                    run_dir=final_run_dir,
                    source_run_dir=(
                        config.source_run_dir
                    ),
                    b2_run_dir=(
                        config.b2_run_dir
                    ),
                    contract_path=(
                        config.contract_path
                    ),
                    mode="materialized",
                    report_path=(
                        final_report_path
                    ),
                    logical_run_dir=(
                        final_run_dir
                    ),
                    validate_source_reconciliation=True,
                )
            )
        )

        if not final_validation.ok:
            raise RuntimeError(
                "final validation failed: "
                + "; ".join(
                    final_validation.issues
                )
            )

        final_manifest_path = (
            final_run_dir
            / "metadata"
            / "product_feature_manifest.json"
        )

        final_manifest = (
            _build_materialization_manifest(
                config=config,
                final_contract=(
                    final_contract
                ),
                static_contract=(
                    static_contract
                ),
                tables=tables,
                outputs=written_outputs,
                candidate_validation=(
                    candidate_validation
                    .to_dict()
                ),
                final_validation=(
                    final_validation
                    .to_dict()
                ),
            )
        )

        _write_json_atomic(
            final_manifest_path,
            final_manifest,
        )

        return ProductFeatureBuildResult(
            ok=True,
            decision=(
                "PRODUCT_FEATURE_"
                "MATERIALIZATION_OK"
            ),
            mode="materialized",
            run_dir=str(
                final_run_dir
            ),
            outputs=tuple(
                written_outputs
            ),
            issues=(),
        )

    except Exception as exc:
        if (
            candidate_run_dir is not None
            and candidate_run_dir.exists()
        ):
            shutil.rmtree(
                candidate_run_dir
            )

        if (
            promoted
            and final_run_dir.exists()
        ):
            shutil.rmtree(
                final_run_dir
            )

        return ProductFeatureBuildResult(
            ok=False,
            decision=(
                "PRODUCT_FEATURE_BUILD_FAILED"
            ),
            mode=(
                "materialized"
                if config.execute
                else "plan"
            ),
            run_dir=str(
                final_run_dir
            ),
            outputs=tuple(outputs),
            issues=(
                f"{type(exc).__name__}: "
                f"{exc}",
            ),
        )


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()

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
        "--run-dir",
        required=True,
        type=Path,
    )

    parser.add_argument(
        "--contract-path",
        required=True,
        type=Path,
    )

    parser.add_argument(
        "--build-id",
        required=True,
    )

    parser.add_argument(
        "--compression",
        default="zstd",
    )

    parser.add_argument(
        "--execute",
        action="store_true",
    )

    parser.add_argument(
        "--confirm-write-feature-lake",
        action="store_true",
    )

    parser.add_argument(
        "--failure-injection-point",
    )

    return parser.parse_args()


def main() -> int:
    args = _parse_args()

    result = build_product_features(
        ProductFeatureConfig(
            source_run_dir=(
                args.source_run_dir
            ),
            b2_run_dir=(
                args.b2_run_dir
            ),
            run_dir=args.run_dir,
            contract_path=(
                args.contract_path
            ),
            build_id=args.build_id,
            compression=args.compression,
            execute=args.execute,
            confirm_write_feature_lake=(
                args.confirm_write_feature_lake
            ),
            failure_injection_point=(
                args.failure_injection_point
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
