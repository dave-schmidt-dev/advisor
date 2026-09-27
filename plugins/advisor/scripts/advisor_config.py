#!/usr/bin/env python3
"""Safe Advisor selection state and bounded Codex app-server discovery."""

from __future__ import annotations

import argparse
import json
import sys
from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import Any

_SCRIPT_DIR = str(Path(__file__).resolve().parent)
if _SCRIPT_DIR not in sys.path:
    sys.path.insert(0, _SCRIPT_DIR)
from advisor_process import JsonRpcProcess, ProcessUnavailable, terminate_owned
from advisor_state import (
    ATTEMPT_OUTCOMES,
    CANARY_CLEANUP_GRACE_SECONDS,
    DEFAULT_DEADLINE_SECONDS,
    EFFORTS,
    JOURNAL_OUTCOMES,
    JOURNAL_RETENTION_SECONDS,
    JOURNAL_TIERS,
    LOCK_DEADLINE_SECONDS,
    MAX_EVENTS,
    MAX_JOURNAL_RECORDS,
    MAX_JSON_BYTES,
    MAX_LIVE_CONFIG_BYTES,
    MAX_MODELS,
    MAX_PAGES,
    MAX_DEADLINE_SECONDS,
    MIN_DEADLINE_SECONDS,
    PRESET_RE,
    SCHEMA_VERSION,
    SELECTOR_RE,
    TOKEN_RE,
    TRANSPORT_CONTRACT_VERSION,
    TIERS,
    ConfigError,
    DiscoveryError,
    DiscoveryUnavailable,
    RevisionConflict,
    StatePaths,
    _MISSING,
    _NO_DEFAULT,
    _atomic_write,
    _atomic_write_bytes,
    _duplicate_key,
    _read_safe_bytes,
    _require_keys,
    _run_bounded_output,
    _safe_directory,
    _validate_effort,
    _validate_selector,
    current_codex_version,
    read_json,
    state_lock,
    state_paths,
    validate_pair,
)

from advisor_catalog import (
    _empty_catalog,
    _pair_is_compatible,
    _pair_is_listed,
    _validate_candidate,
    add_manual_candidate,
    compatibility_is_current,
    load_catalog,
    load_shipped_models,
    record_compatibility,
    save_catalog,
    shipped_default_launch_eligible,
    validate_catalog,
    validate_compatibility,
    validate_shipped_models,
)

from advisor_settings import (
    _write_settings_revision,
    baseline_settings,
    live_config_path,
    load_live_config,
    load_settings,
    reset_selections,
    resolve_selection,
    restore_prior_settings,
    save_preset,
    save_settings,
    set_deadline,
    set_selection,
    set_usage_journal,
    validate_settings,
)

from advisor_journal import (
    _last_journal_failure,
    _prune_usage_journal,
    _validate_usage_count,
    clear_usage_journal,
    validate_journal_record,
    write_usage_journal,
)

from advisor_discovery import (
    AppServerDiscovery,
    normalize_discovery_pages,
    refresh_catalog,
)

from advisor_canary import (
    _CanaryCancelled,
    _run_compatibility_wrapper,
    _stop_canary_wrapper,
    authorize_canary,
    consume_canary,
    test_compatibility,
)

from advisor_doctor import (
    _catalog_view,
    _compatibility_view,
    _doctor_probe,
    _parent_runtime_report,
    doctor_report,
)

__all__ = [
    "SCHEMA_VERSION", "TRANSPORT_CONTRACT_VERSION", "MAX_JSON_BYTES",
    "MAX_LIVE_CONFIG_BYTES", "MAX_JOURNAL_RECORDS", "JOURNAL_RETENTION_SECONDS",
    "JOURNAL_OUTCOMES", "ATTEMPT_OUTCOMES", "MAX_PAGES", "MAX_EVENTS",
    "MAX_MODELS", "DEFAULT_DEADLINE_SECONDS", "MIN_DEADLINE_SECONDS",
    "MAX_DEADLINE_SECONDS", "LOCK_DEADLINE_SECONDS", "CANARY_CLEANUP_GRACE_SECONDS",
    "EFFORTS", "TIERS", "JOURNAL_TIERS", "SELECTOR_RE", "PRESET_RE",
    "TOKEN_RE", "_MISSING", "_NO_DEFAULT", "ConfigError",
    "RevisionConflict", "DiscoveryUnavailable", "DiscoveryError",
    "_run_bounded_output", "_duplicate_key", "_safe_directory", "read_json",
    "_require_keys", "_validate_selector", "_validate_effort", "validate_pair",
    "StatePaths", "state_paths", "state_lock", "_read_safe_bytes",
    "_atomic_write_bytes", "_atomic_write", "current_codex_version",
    "_validate_candidate", "_empty_catalog", "validate_compatibility",
    "validate_catalog", "compatibility_is_current", "shipped_default_launch_eligible",
    "load_catalog", "load_shipped_models", "validate_shipped_models", "save_catalog",
    "add_manual_candidate", "_pair_is_compatible", "_pair_is_listed",
    "record_compatibility",
    "live_config_path", "load_live_config", "baseline_settings",
    "validate_settings", "load_settings", "set_usage_journal",
    "save_settings", "_write_settings_revision", "reset_selections",
    "restore_prior_settings", "set_deadline", "set_selection",
    "save_preset", "resolve_selection",
    "_validate_usage_count", "validate_journal_record",
    "_prune_usage_journal", "write_usage_journal", "clear_usage_journal",
    "_last_journal_failure",
    "normalize_discovery_pages", "AppServerDiscovery", "refresh_catalog",
    "authorize_canary", "consume_canary", "_CanaryCancelled",
    "_stop_canary_wrapper", "_run_compatibility_wrapper", "test_compatibility",
    "_compatibility_view", "_catalog_view", "_doctor_probe",
    "_parent_runtime_report", "doctor_report",
    "JsonRpcProcess", "ProcessUnavailable", "terminate_owned",
]


def _json_result(value: Mapping[str, Any], *, enabled: bool) -> None:
    # Text remains readable and complete; JSON is one compact object on stdout.
    print(
        json.dumps(value, sort_keys=True, separators=(",", ":"))
        if enabled
        else json.dumps(value, sort_keys=True, indent=2)
    )


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="advisor-config.sh",
        description="Inspect Advisor's live configuration and advanced local state.",
    )
    parser.add_argument("--json", action="store_true", dest="as_json")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("show", help="show the live model pairs, deadline, and journal state")
    sub.add_parser("status", help="alias for show")
    models = sub.add_parser("models", help="list, refresh, add, or test model evidence")
    model_sub = models.add_subparsers(dest="models_command")
    model_sub.add_parser("list", help="list shipped and local model evidence")
    model_sub.add_parser("refresh", help="refresh advertised models without inference")
    add = model_sub.add_parser("add", help="record a manual offline candidate")
    add.add_argument("model")
    add.add_argument("--id", dest="candidate_id")
    add.add_argument("--display-name")
    test = model_sub.add_parser("test", help="run one explicitly authorized synthetic canary")
    test.add_argument("model")
    test.add_argument("--effort", required=True)
    test.add_argument("--authorize-usage", action="store_true")
    test.add_argument("--parent-thread", required=True)
    test.add_argument("--sessions-dir")
    resolve = sub.add_parser("resolve", help="resolve one immutable launch selection")
    resolve.add_argument("--tier", required=True)
    resolve.add_argument("--preset")
    consume = sub.add_parser("_consume-canary", help=argparse.SUPPRESS)
    consume.add_argument("token")
    select = sub.add_parser("set", help="legacy-only saved selection; --tier uses advisor.toml")
    select.add_argument("--tier", required=True)
    select.add_argument("--model", required=True)
    select.add_argument("--effort", required=True)
    preset = sub.add_parser("preset", help="save a currently compatible named pair")
    preset.add_argument("name")
    preset.add_argument("--model", required=True)
    preset.add_argument("--effort", required=True)
    journal = sub.add_parser("journal", help="inspect or control the content-free journal")
    journal_sub = journal.add_subparsers(dest="journal_command", required=True)
    journal_sub.add_parser("status")
    journal_sub.add_parser("enable")
    journal_sub.add_parser("disable")
    journal_sub.add_parser("clear")
    journal_record = sub.add_parser("_journal-record", help=argparse.SUPPRESS)
    journal_record.add_argument("record")
    sub.add_parser("doctor", help="run bounded read-only local diagnostics")
    sub.add_parser("reset", help="legacy-only reset; --tier uses advisor.toml")
    sub.add_parser("restore", help="explicitly restore the retained prior settings")
    deadline = sub.add_parser("deadline", help="show or set the total deadline")
    deadline.add_argument("seconds", type=int, nargs="?")
    args = parser.parse_args(argv)
    try:
        paths = state_paths()
        if args.command in ("show", "status"):
            live = load_live_config()
            try:
                settings = load_settings(paths)
                deadline_seconds = settings["deadline_seconds"]
                journal_enabled = settings["usage_journal_enabled"]
                legacy_settings = "valid"
            except ConfigError:
                deadline_seconds = DEFAULT_DEADLINE_SECONDS
                journal_enabled = False
                legacy_settings = "invalid"
            _json_result(
                {
                    "status": "ok",
                    "live_config": live,
                    "selections": live["pairs"],
                    "selection_revision": live["source_revision"],
                    "deadline_seconds": deadline_seconds,
                    "usage_journal_enabled": journal_enabled,
                    "legacy_settings": legacy_settings,
                    "catalog_present": paths.catalog.exists(),
                    "account_availability": "unobserved",
                    "message": "Advisor live configuration and local non-selection settings",
                },
                enabled=args.as_json,
            )
            return 0
        if args.command == "models" and args.models_command in (None, "list"):
            catalog = load_catalog(paths)
            _json_result(
                {
                    "status": "ok",
                    "models": _catalog_view(catalog),
                    # Retain the established machine interface while the
                    # rendered view adds source/freshness/entitlement context.
                    "shipped": load_shipped_models(),
                    "catalog": catalog,
                    "message": "Advisor shipped, manual, and discovered model evidence",
                },
                enabled=args.as_json,
            )
            return 0
        if args.command == "models" and args.models_command == "add":
            _json_result(
                {
                    "status": "ok",
                    "catalog": add_manual_candidate(
                        args.model,
                        candidate_id=args.candidate_id,
                        display_name=args.display_name,
                        paths=paths,
                    ),
                    "message": "Manual candidate recorded; compatibility is unverified",
                },
                enabled=args.as_json,
            )
            return 0
        if args.command == "models" and args.models_command == "refresh":
            print("ADVISOR CONFIG: discovery started", file=sys.stderr)
            _json_result(
                {
                    "status": "ok",
                    "catalog": refresh_catalog(
                        AppServerDiscovery(
                            on_status=lambda text: print(
                                f"ADVISOR CONFIG: {text}", file=sys.stderr
                            )
                        ).pages,
                        paths=paths,
                    ),
                    "message": "Discovery refreshed",
                },
                enabled=args.as_json,
            )
            return 0
        if args.command == "models" and args.models_command == "test":
            if not args.authorize_usage:
                raise ConfigError("models test requires --authorize-usage")
            result = test_compatibility(
                {"model": args.model, "effort": args.effort},
                parent_thread=args.parent_thread,
                sessions_dir=args.sessions_dir,
                paths=paths,
                on_status=lambda text: print(
                    f"ADVISOR CONFIG: {text}", file=sys.stderr
                ),
            )
            _json_result(
                {
                    "status": "ok",
                    "compatibility": result,
                    "message": "Compatibility canary passed; selection unchanged",
                },
                enabled=args.as_json,
            )
            return 0
        if args.command == "resolve":
            _json_result(
                {
                    "status": "ok",
                    "launch": resolve_selection(
                        args.tier, preset=args.preset, paths=paths
                    ),
                    "message": "Immutable Advisor launch record",
                },
                enabled=True,
            )
            return 0
        if args.command == "_consume-canary":
            _json_result(
                {
                    "status": "ok",
                    "launch": consume_canary(args.token, paths=paths),
                    "message": "Authorized synthetic canary",
                },
                enabled=True,
            )
            return 0
        if args.command == "set":
            raise ConfigError("set is legacy-only; edit the installed advisor.toml for --tier consultations")
        if args.command == "preset":
            _json_result(
                {
                    "status": "ok",
                    "settings": save_preset(
                        args.name,
                        {"model": args.model, "effort": args.effort},
                        paths=paths,
                    ),
                    "message": "Preset saved",
                },
                enabled=args.as_json,
            )
            return 0
        if args.command == "doctor":
            report = doctor_report(
                paths,
                on_status=lambda text: print(
                    f"ADVISOR CONFIG: {text}", file=sys.stderr
                ),
            )
            _json_result({**report, "message": "Local read-only Advisor diagnostics"}, enabled=args.as_json)
            return 0 if report["status"] == "ok" else 2
        if args.command == "reset":
            raise ConfigError("reset is legacy-only; edit the installed advisor.toml for --tier consultations")
        if args.command == "restore":
            try:
                load_settings(paths)
                malformed_recovery = False
            except ConfigError:
                malformed_recovery = True
            _json_result(
                {
                    "status": "ok",
                    "settings": restore_prior_settings(paths=paths),
                    "message": (
                        "Prior settings restored explicitly; malformed settings "
                        "preserved as settings.invalid.json; --tier continues to use advisor.toml"
                        if malformed_recovery
                        else "Prior legacy settings restored; --tier continues to use advisor.toml"
                    ),
                },
                enabled=args.as_json,
            )
            return 0
        if args.command == "deadline":
            settings = (
                load_settings(paths)
                if args.seconds is None
                else set_deadline(args.seconds, paths=paths)
            )
            _json_result(
                {
                    "status": "ok",
                    "deadline_seconds": settings["deadline_seconds"],
                    "selection_revision": settings["revision"],
                    "message": "Advisor total deadline"
                    if args.seconds is None
                    else "Advisor total deadline saved",
                },
                enabled=args.as_json,
            )
            return 0
        if args.command == "journal" and args.journal_command == "status":
            settings = load_settings(paths)
            count = 0
            if paths.journal.exists():
                _safe_directory(paths.journal, create=False)
                count = len(list(paths.journal.iterdir()))
            _json_result(
                {
                    "status": "ok",
                    "enabled": settings["usage_journal_enabled"],
                    "records": count,
                    "message": "Content-free usage journal status",
                },
                enabled=args.as_json,
            )
            return 0
        if args.command == "journal" and args.journal_command in ("enable", "disable"):
            enabled = args.journal_command == "enable"
            _json_result(
                {
                    "status": "ok",
                    "settings": set_usage_journal(enabled, paths=paths),
                    "message": "Usage journal enabled"
                    if enabled
                    else "Usage journal disabled",
                },
                enabled=args.as_json,
            )
            return 0
        if args.command == "journal" and args.journal_command == "clear":
            _json_result(
                {
                    "status": "ok",
                    "cleared": clear_usage_journal(paths=paths),
                    "message": "Usage journal cleared",
                },
                enabled=args.as_json,
            )
            return 0
        if args.command == "_journal-record":
            try:
                record = json.loads(args.record, object_pairs_hook=_duplicate_key)
            except json.JSONDecodeError as exc:
                raise ConfigError("invalid usage journal record") from exc
            _json_result(
                {
                    "status": "ok",
                    "written": write_usage_journal(record, paths=paths),
                    "message": "Usage journal record processed",
                },
                enabled=True,
            )
            return 0
        raise ConfigError("unknown command")
    except (ConfigError, DiscoveryError) as exc:
        message = str(exc)
        if "settings" in message and not message.startswith(
            "unsupported settings schema"
        ):
            message += "; inspect settings.json or run advisor-config.sh restore if the prior backup is valid"
        _json_result(
            {"status": "unavailable", "error": message, "message": message},
            enabled=args.as_json,
        )
        return 2
    except OSError:
        message = "local state update failed; active and prior settings were preserved"
        _json_result(
            {"status": "unavailable", "error": message, "message": message},
            enabled=args.as_json,
        )
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
