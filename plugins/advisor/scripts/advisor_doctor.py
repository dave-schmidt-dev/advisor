"""Read-only Advisor diagnostics probes and rendered catalog views."""

from __future__ import annotations

import json
import shutil
import stat
import sys
from collections.abc import Callable, Mapping, Sequence
from pathlib import Path
from typing import Any

from advisor_catalog import (
    compatibility_is_current,
    load_catalog,
    load_shipped_models,
    shipped_default_launch_eligible,
)
from advisor_journal import _last_journal_failure
from advisor_settings import load_live_config, load_settings, validate_settings
from advisor_state import (
    ConfigError,
    StatePaths,
    _duplicate_key,
    _run_bounded_output,
    current_codex_version,
    read_json,
    state_paths,
)


def _compatibility_view(
    catalog: Mapping[str, Any], *, model: str
) -> list[dict[str, Any]]:
    """Render exact pair receipts and whether each is current now."""
    return [
        {
            **receipt,
            "current": compatibility_is_current(
                receipt,
                model=model,
                effort=receipt["effort"],
            ),
        }
        for receipt in catalog["compatibility"]
        if receipt["model"] == model
    ]


def _catalog_view(catalog: Mapping[str, Any]) -> dict[str, Any]:
    """Render catalog evidence without claiming account entitlement."""
    shipped = load_shipped_models()
    try:
        codex_version = current_codex_version()
    except ConfigError:
        codex_version = None
    shipped_rows = []
    for item in shipped["models"]:
        if not isinstance(item, dict):
            continue
        baseline = item.get("compatibility_baseline")
        shipped_rows.append(
            {
                "selector": item.get("model"),
                "id": item.get("id"),
                "source": "shipped",
                "tiers": item.get("tiers", []),
                "advertised_efforts": baseline.get("efforts", [])
                if isinstance(baseline, dict)
                else [],
                # Retain the established compatibility field. Shipped metadata
                # intentionally has no canary receipt, so it cannot claim current
                # compatibility merely because it is launch-eligible.
                "baseline_compatibility": [
                    {"effort": effort, "current": False}
                    for effort in (
                        baseline.get("efforts", [])
                        if isinstance(baseline, dict)
                        else []
                    )
                ],
                "baseline_launch_eligibility": [
                    {
                        "effort": effort,
                        "eligible": any(
                            shipped_default_launch_eligible(
                                tier=tier,
                                model=item.get("model"),
                                effort=effort,
                            )
                            for tier in item.get("tiers", [])
                        ),
                    }
                    for effort in (
                        baseline.get("efforts", [])
                        if isinstance(baseline, dict)
                        else []
                    )
                ],
                "tested_compatibility": _compatibility_view(
                    catalog, model=item.get("model")
                ),
                "account_availability": "unobserved",
            }
        )
    candidates = []
    for item in catalog["candidates"]:
        candidates.append(
            {
                "selector": item["model"],
                "id": item["id"],
                "source": item["provenance"],
                "visible": item["visible"],
                "advertised_efforts": item.get("advertised_efforts", []),
                "freshness": item.get("last_seen_at"),
                "tested_compatibility": _compatibility_view(
                    catalog, model=item["model"]
                ),
                "account_availability": "unobserved",
            }
        )
    return {
        "shipped": shipped_rows,
        "candidates": candidates,
        "compatibility_receipts": catalog["compatibility"],
        "last_successful_refresh": catalog["last_successful_refresh"],
        "installed_codex_version": codex_version,
        "account_availability": "unobserved",
    }


def _doctor_probe(argv: Sequence[str], *, max_bytes: int = 4096) -> dict[str, Any]:
    try:
        returncode, output = _run_bounded_output(
            argv, timeout_seconds=2.0, max_bytes=max_bytes
        )
    except ConfigError:
        return {"status": "unavailable"}
    if returncode != 0:
        return {"status": "unavailable", "returncode": returncode}
    try:
        text = output.decode("utf-8").strip()
    except UnicodeDecodeError:
        return {"status": "unavailable"}
    return {"status": "available", "detail": text}




def _parent_runtime_report(
    *, on_status: Callable[[str], None] | None = None
) -> dict[str, Any]:
    """Run and validate the fixed read-only parent-runtime inspector."""
    helper = Path(__file__).resolve().parent / "inspect-parent-runtime.sh"
    try:
        info = helper.lstat()
    except OSError:
        return {"status": "unavailable", "reason_type": "parent_runtime_unavailable"}
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        return {"status": "unavailable", "reason_type": "parent_runtime_unavailable"}
    if on_status is not None:
        on_status("inspecting parent runtime evidence")
    probe = _doctor_probe(["/bin/sh", str(helper)])
    if probe.get("status") != "available":
        return {"status": "unavailable", "reason_type": "parent_runtime_unavailable"}
    try:
        result = json.loads(probe["detail"], object_pairs_hook=_duplicate_key)
    except (ConfigError, json.JSONDecodeError, RecursionError):
        return {"status": "unavailable", "reason_type": "parent_runtime_unavailable"}
    if not isinstance(result, dict):
        return {"status": "unavailable", "reason_type": "parent_runtime_unavailable"}
    if result.get("status") == "available" and set(result) == {
        "status",
        "thread_id",
        "sandbox_policy_type",
        "permission_profile_type",
    }:
        return result
    return {"status": "unavailable", "reason_type": "parent_runtime_unavailable"}


def doctor_report(
    paths: StatePaths | None = None,
    *,
    on_status: Callable[[str], None] | None = None,
) -> dict[str, Any]:
    """Collect local, read-only diagnostics without inference or credential reads."""
    paths = paths or state_paths()
    errors: list[str] = []
    try:
        live = load_live_config()
    except ConfigError as exc:
        live = None
        errors.append(str(exc))
    try:
        settings = load_settings(paths)
    except ConfigError as exc:
        settings = None
        errors.append(str(exc))
    try:
        catalog = load_catalog(paths)
    except ConfigError as exc:
        catalog = None
        errors.append(str(exc))

    codex_path = shutil.which("codex")
    jq_path = shutil.which("jq")
    python_path = sys.executable if Path(sys.executable).is_file() else None
    if on_status is not None:
        on_status("probing local dependencies")
    cli = _doctor_probe(["codex", "--version"]) if codex_path else {"status": "missing"}
    discovery = {"status": "unavailable"}
    if codex_path:
        help_probe = _doctor_probe(["codex", "app-server", "--help"], max_bytes=200_000)
        flags = help_probe.get("detail", "")
        discovery = {
            "status": "supported"
            if help_probe["status"] == "available"
            and "--ignore-user-config" in flags
            and "--ignore-rules" in flags
            else "unsupported",
        }
    try:
        last_failure = _last_journal_failure(paths)
    except ConfigError as exc:
        last_failure = None
        errors.append(str(exc))
    backup = "absent"
    if paths.prior_settings.exists() or paths.prior_settings.is_symlink():
        try:
            validate_settings(read_json(paths.prior_settings))
            backup = "valid"
        except ConfigError:
            backup = "invalid"
    return {
        "status": "ok" if not errors else "unavailable",
        "dependencies": {
            "python": "available" if python_path else "missing",
            "jq": "available" if jq_path else "missing",
            "codex": cli,
        },
        "discovery_protocol": discovery,
        "parent_runtime": _parent_runtime_report(on_status=on_status),
        "live_config": live,
        "settings": "valid" if settings is not None else "invalid",
        "catalog": "valid" if catalog is not None else "invalid",
        "stale_selections": None,
        "launch_eligibility": None,
        "current_compatibility": None,
        "prior_settings_backup": backup,
        "last_content_free_failure": last_failure,
        "account_availability": "unobserved",
        "errors": errors,
    }
