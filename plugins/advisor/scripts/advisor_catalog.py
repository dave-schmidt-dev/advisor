"""Advisor shipped-model and compatibility catalog validation."""

from __future__ import annotations

import json
import stat
import time
from collections.abc import Mapping
from pathlib import Path
from typing import Any

from advisor_state import (
    EFFORTS,
    MAX_JSON_BYTES,
    MAX_MODELS,
    PRESET_RE,
    SCHEMA_VERSION,
    TIERS,
    TRANSPORT_CONTRACT_VERSION,
    ConfigError,
    StatePaths,
    _MISSING,
    _atomic_write,
    _duplicate_key,
    _require_keys,
    _safe_directory,
    _validate_effort,
    _validate_selector,
    read_json,
    state_lock,
    state_paths,
    validate_pair,
)

def _validate_candidate(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ConfigError("invalid catalog candidate")
    required = {"id", "model", "display_name", "provenance", "visible"}
    if not required.issubset(value) or not set(value).issubset(
        required | {"last_seen_at", "advertised_efforts", "default_effort"}
    ):
        raise ConfigError("invalid catalog candidate keys")
    candidate = {key: value[key] for key in required}
    candidate["id"] = _validate_selector(candidate["id"], label="candidate id")
    candidate["model"] = _validate_selector(candidate["model"])
    if (
        not isinstance(candidate["display_name"], str)
        or not candidate["display_name"].strip()
    ):
        raise ConfigError("invalid candidate display name")
    if candidate["provenance"] not in {"manual", "discovery"} or not isinstance(
        candidate["visible"], bool
    ):
        raise ConfigError("invalid catalog candidate")
    if "last_seen_at" in value:
        if not isinstance(value["last_seen_at"], str):
            raise ConfigError("invalid candidate timestamp")
        candidate["last_seen_at"] = value["last_seen_at"]
    has_runtime = "advertised_efforts" in value or "default_effort" in value
    if candidate["provenance"] == "discovery" and not has_runtime:
        raise ConfigError("discovery candidate lacks runtime efforts")
    if has_runtime:
        efforts = value.get("advertised_efforts")
        if (
            not isinstance(efforts, list)
            or not efforts
            or len(efforts) > len(EFFORTS)
            or len(set(efforts)) != len(efforts)
        ):
            raise ConfigError("invalid advertised efforts")
        candidate["advertised_efforts"] = [_validate_effort(item) for item in efforts]
        candidate["default_effort"] = _validate_effort(value.get("default_effort"))
        if candidate["default_effort"] not in candidate["advertised_efforts"]:
            raise ConfigError("default effort is not advertised")
    return candidate


def _empty_catalog() -> dict[str, Any]:
    return {
        "schema_version": SCHEMA_VERSION,
        "revision": 0,
        "candidates": [],
        "compatibility": [],
        "last_successful_refresh": None,
    }


def validate_compatibility(value: Any) -> dict[str, str]:
    value = _require_keys(
        value,
        {
            "model",
            "effort",
            "codex_version",
            "transport_contract_version",
            "verified_at",
        },
        label="compatibility record",
    )
    pair = validate_pair({"model": value["model"], "effort": value["effort"]})
    for name in ("codex_version", "transport_contract_version", "verified_at"):
        if not isinstance(value[name], str) or not value[name]:
            raise ConfigError(f"invalid compatibility {name}")
    return {
        **pair,
        **{
            name: value[name]
            for name in ("codex_version", "transport_contract_version", "verified_at")
        },
    }


def validate_catalog(value: Any) -> dict[str, Any]:
    value = _require_keys(
        value,
        {
            "schema_version",
            "revision",
            "candidates",
            "compatibility",
            "last_successful_refresh",
        },
        label="catalog",
    )
    if (
        value["schema_version"] != SCHEMA_VERSION
        or not isinstance(value["revision"], int)
        or isinstance(value["revision"], bool)
        or value["revision"] < 0
    ):
        raise ConfigError("invalid catalog header")
    if (
        not isinstance(value["candidates"], list)
        or len(value["candidates"]) > MAX_MODELS
    ):
        raise ConfigError("invalid catalog candidates")
    candidates = [_validate_candidate(item) for item in value["candidates"]]
    if len(
        {(item["id"], item["model"], item["provenance"]) for item in candidates}
    ) != len(candidates):
        raise ConfigError("duplicate catalog candidate")
    if (
        not isinstance(value["compatibility"], list)
        or len(value["compatibility"]) > MAX_MODELS
    ):
        raise ConfigError("invalid compatibility records")
    compatibility = [validate_compatibility(item) for item in value["compatibility"]]
    if value["last_successful_refresh"] is not None and not isinstance(
        value["last_successful_refresh"], str
    ):
        raise ConfigError("invalid catalog refresh timestamp")
    return {
        "schema_version": SCHEMA_VERSION,
        "revision": value["revision"],
        "candidates": candidates,
        "compatibility": compatibility,
        "last_successful_refresh": value["last_successful_refresh"],
    }


def compatibility_is_current(
    record: Mapping[str, str],
    *,
    model: str,
    effort: str,
    transport_contract_version: str = TRANSPORT_CONTRACT_VERSION,
) -> bool:
    """Return whether an exact canary still proves this transport pair.

    The recorded CLI version is provenance, not an eligibility constraint. A
    runtime inspection remains the authority for each actual child launch.
    """
    return (
        record.get("model") == model
        and record.get("effort") == effort
        and record.get("transport_contract_version") == transport_contract_version
    )


def shipped_default_launch_eligible(
    *,
    tier: str,
    model: str,
    effort: str,
    transport_contract_version: str = TRANSPORT_CONTRACT_VERSION,
) -> bool:
    """Permit one shipped default pair to be attempted for its own tier.

    This is deliberately not compatibility proof. The real child still has to
    pass the exact post-run identity and transport inspection before acceptance.
    """
    if tier not in TIERS or transport_contract_version != TRANSPORT_CONTRACT_VERSION:
        return False
    default = load_shipped_models()["defaults"][tier]
    return default == {"model": model, "effort": effort}


def load_catalog(paths: StatePaths | None = None) -> dict[str, Any]:
    paths = paths or state_paths()
    if not paths.root.exists() and not paths.root.is_symlink():
        return _empty_catalog()
    _safe_directory(paths.root, create=False)
    stored = read_json(paths.catalog, missing=_MISSING)
    return _empty_catalog() if stored is _MISSING else validate_catalog(stored)


def load_shipped_models() -> dict[str, Any]:
    """Load the bounded, immutable catalog shipped beside this helper."""
    path = Path(__file__).resolve().parent.parent / "models.json"
    try:
        info = path.lstat()
    except FileNotFoundError as exc:
        raise ConfigError("shipped model catalog is unavailable") from exc
    if (
        not stat.S_ISREG(info.st_mode)
        or stat.S_ISLNK(info.st_mode)
        or info.st_size > MAX_JSON_BYTES
    ):
        raise ConfigError("shipped model catalog is unsafe")
    try:
        with path.open("r", encoding="utf-8") as handle:
            value = json.load(handle, object_pairs_hook=_duplicate_key)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, RecursionError) as exc:
        raise ConfigError("shipped model catalog is invalid") from exc
    return validate_shipped_models(value)


def validate_shipped_models(value: Any) -> dict[str, Any]:
    """Validate every shipped default and baseline without inferring support."""
    value = _require_keys(
        value,
        {
            "schema_version",
            "transport_contract_version",
            "tested_codex_cli",
            "defaults",
            "models",
        },
        label="shipped model catalog",
    )
    if (
        value["schema_version"] != SCHEMA_VERSION
        or value["transport_contract_version"] != TRANSPORT_CONTRACT_VERSION
        or not isinstance(value["tested_codex_cli"], str)
        or not value["tested_codex_cli"].strip()
        or not isinstance(value["models"], list)
        or not 1 <= len(value["models"]) <= MAX_MODELS
    ):
        raise ConfigError("shipped model catalog is invalid")
    defaults_raw = _require_keys(value["defaults"], set(TIERS), label="shipped defaults")
    defaults = {tier: validate_pair(defaults_raw[tier]) for tier in TIERS}
    models: list[dict[str, Any]] = []
    for item in value["models"]:
        item = _require_keys(
            item,
            {"id", "model", "display_name", "tiers", "compatibility_baseline"},
            label="shipped model",
        )
        if (
            not isinstance(item["id"], str)
            or not PRESET_RE.fullmatch(item["id"])
            or not isinstance(item["display_name"], str)
            or not item["display_name"].strip()
            or not isinstance(item["tiers"], list)
            or any(not isinstance(tier, str) for tier in item["tiers"])
            or len(set(item["tiers"])) != len(item["tiers"])
            or any(tier not in TIERS for tier in item["tiers"])
        ):
            raise ConfigError("shipped model catalog is invalid")
        baseline = item["compatibility_baseline"]
        if baseline is not None:
            baseline = _require_keys(
                baseline,
                {"efforts", "transport_contract_version"},
                label="shipped compatibility baseline",
            )
            if (
                not item["tiers"]
                or baseline["transport_contract_version"] != TRANSPORT_CONTRACT_VERSION
                or not isinstance(baseline["efforts"], list)
                or not baseline["efforts"]
                or any(not isinstance(effort, str) for effort in baseline["efforts"])
                or len(set(baseline["efforts"])) != len(baseline["efforts"])
            ):
                raise ConfigError("shipped model catalog is invalid")
            baseline = {
                "efforts": [_validate_effort(effort) for effort in baseline["efforts"]],
                "transport_contract_version": TRANSPORT_CONTRACT_VERSION,
            }
        elif item["tiers"]:
            raise ConfigError("shipped model catalog is invalid")
        models.append(
            {
                "id": item["id"],
                "model": _validate_selector(item["model"]),
                "display_name": item["display_name"],
                "tiers": list(item["tiers"]),
                "compatibility_baseline": baseline,
            }
        )
    if len({item["id"] for item in models}) != len(models) or len(
        {item["model"] for item in models}
    ) != len(models):
        raise ConfigError("shipped model catalog is invalid")
    for tier, pair in defaults.items():
        matching = next(
            (
                item
                for item in models
                if item["model"] == pair["model"] and tier in item["tiers"]
            ),
            None,
        )
        if (
            matching is None
            or matching["compatibility_baseline"] is None
            or pair["effort"] not in matching["compatibility_baseline"]["efforts"]
        ):
            raise ConfigError("shipped model catalog is invalid")
    return {
        "schema_version": SCHEMA_VERSION,
        "transport_contract_version": TRANSPORT_CONTRACT_VERSION,
        "tested_codex_cli": value["tested_codex_cli"],
        "defaults": {tier: defaults[tier] for tier in sorted(TIERS)},
        "models": models,
    }


def add_manual_candidate(
    model: str,
    *,
    candidate_id: str | None = None,
    display_name: str | None = None,
    paths: StatePaths | None = None,
) -> dict[str, Any]:
    model = _validate_selector(model)
    candidate_id = _validate_selector(candidate_id or model, label="candidate id")
    if (
        not isinstance(display_name or model, str)
        or not (display_name or model).strip()
    ):
        raise ConfigError("invalid candidate display name")
    paths = paths or state_paths()
    with state_lock(paths):
        catalog = load_catalog(paths)
        candidate = {
            "id": candidate_id,
            "model": model,
            "display_name": display_name or model,
            "provenance": "manual",
            "visible": True,
        }
        catalog["candidates"] = [
            item
            for item in catalog["candidates"]
            if not (
                item["id"] == candidate_id
                and item["model"] == model
                and item["provenance"] == "manual"
            )
        ] + [candidate]
        catalog["revision"] += 1
        _atomic_write(paths.catalog, validate_catalog(catalog))
        return catalog


def _pair_is_compatible(pair: Mapping[str, str], catalog: Mapping[str, Any]) -> bool:
    """Require a current exact canary for any explicit model/preset route."""
    return any(
        compatibility_is_current(item, **pair)
        for item in catalog["compatibility"]
    )


def _pair_is_listed(pair: Mapping[str, str], catalog: Mapping[str, Any]) -> bool:
    shipped = load_shipped_models()["models"]
    for item in shipped:
        if isinstance(item, dict) and item.get("model") == pair["model"]:
            return True
    for item in catalog["candidates"]:
        if item["model"] != pair["model"]:
            continue
        efforts = item.get("advertised_efforts")
        return efforts is None or pair["effort"] in efforts
    return False


def record_compatibility(
    pair: Mapping[str, str], *, codex_version: str, paths: StatePaths | None = None
) -> dict[str, Any]:
    """Record a successful exact transport canary without selecting the pair."""
    pair = validate_pair(pair)
    paths = paths or state_paths()
    receipt = validate_compatibility(
        {
            **pair,
            "codex_version": codex_version,
            "transport_contract_version": TRANSPORT_CONTRACT_VERSION,
            "verified_at": str(int(time.time())),
        }
    )
    with state_lock(paths):
        catalog = load_catalog(paths)
        catalog["compatibility"] = [
            item
            for item in catalog["compatibility"]
            if not (item["model"] == pair["model"] and item["effort"] == pair["effort"])
        ] + [receipt]
        catalog["revision"] += 1
        _atomic_write(paths.catalog, validate_catalog(catalog))
        return catalog
