#!/usr/bin/env python3
"""Safe Advisor selection state and bounded Codex app-server discovery."""

from __future__ import annotations

import argparse
import json
import os
import secrets
import selectors
import signal
import shutil
import stat
import subprocess
import sys
import tempfile
import time
from collections.abc import Callable, Mapping, Sequence
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
    "JsonRpcProcess", "ProcessUnavailable", "terminate_owned",
]


























def normalize_discovery_pages(
    pages: Sequence[Mapping[str, Any]], *, now: Callable[[], float] = time.time
) -> list[dict[str, Any]]:
    if not isinstance(pages, Sequence) or len(pages) > MAX_PAGES:
        raise DiscoveryError("discovery page limit exceeded")
    candidates = []
    cursors = set()
    for page in pages:
        if (
            not isinstance(page, Mapping)
            or "data" not in page
            or "nextCursor" not in page
        ):
            raise DiscoveryError("malformed discovery response")
        data, cursor = page["data"], page["nextCursor"]
        if not isinstance(data, list) or len(data) > MAX_MODELS:
            raise DiscoveryError("malformed discovery models")
        if cursor is not None:
            if not isinstance(cursor, str) or not cursor or cursor in cursors:
                raise DiscoveryError("discovery cursor loop")
            cursors.add(cursor)
        for raw in data:
            required = {
                "id",
                "model",
                "displayName",
                "description",
                "hidden",
                "isDefault",
                "defaultReasoningEffort",
                "supportedReasoningEfforts",
            }
            if (
                not isinstance(raw, Mapping)
                or not required.issubset(raw)
                or not isinstance(raw["hidden"], bool)
                or not isinstance(raw["isDefault"], bool)
                or not isinstance(raw["description"], str)
            ):
                raise DiscoveryError("malformed discovered model")
            supported = raw["supportedReasoningEfforts"]
            if (
                not isinstance(supported, list)
                or not supported
                or len(supported) > len(EFFORTS)
            ):
                raise DiscoveryError("malformed supported efforts")
            efforts = []
            for item in supported:
                if (
                    not isinstance(item, Mapping)
                    or not {"reasoningEffort", "description"}.issubset(item)
                    or not isinstance(item["description"], str)
                ):
                    raise DiscoveryError("malformed supported effort")
                efforts.append(_validate_effort(item["reasoningEffort"]))
            if len(set(efforts)) != len(efforts):
                raise DiscoveryError("duplicate supported effort")
            try:
                candidate = _validate_candidate(
                    {
                        "id": _validate_selector(raw["id"], label="candidate id"),
                        "model": _validate_selector(raw["model"]),
                        "display_name": raw["displayName"],
                        "provenance": "discovery",
                        "visible": not raw["hidden"],
                        "last_seen_at": str(int(now())),
                        "advertised_efforts": efforts,
                        "default_effort": _validate_effort(
                            raw["defaultReasoningEffort"]
                        ),
                    }
                )
            except (ConfigError, KeyError) as exc:
                raise DiscoveryError("malformed discovered model") from exc
            candidates.append(candidate)
            if len(candidates) > MAX_MODELS:
                raise DiscoveryError("discovery model limit exceeded")
    return candidates


class AppServerDiscovery:
    """Dedicated, inherited-context app-server model-list client."""

    def __init__(
        self,
        connection_factory: Callable[[], Any] | None = None,
        *,
        deadline_seconds: int = DEFAULT_DEADLINE_SECONDS,
        on_status: Callable[[str], None] | None = None,
    ) -> None:
        self.connection_factory = connection_factory or self._connection
        self.deadline_seconds = deadline_seconds
        self.on_status = on_status

    def _connection(self) -> JsonRpcProcess:
        remaining = max(0.1, min(5.0, float(self.deadline_seconds)))
        try:
            returncode, output = _run_bounded_output(
                ["codex", "app-server", "--help"],
                timeout_seconds=remaining,
                max_bytes=200_000,
            )
        except ConfigError as exc:
            raise ProcessUnavailable("app-server capability check failed") from exc
        if (
            returncode != 0
            or b"--ignore-user-config" not in output
            or b"--ignore-rules" not in output
        ):
            raise ProcessUnavailable(
                "app-server cannot safely ignore user configuration"
            )
        scratch = tempfile.mkdtemp(prefix="advisor-discovery-")
        os.chmod(scratch, 0o700)
        return JsonRpcProcess(
            ["codex", "app-server", "--ignore-user-config", "--ignore-rules"],
            deadline_seconds=self.deadline_seconds,
            cwd=scratch,
            on_status=self.on_status,
            on_close=lambda: shutil.rmtree(scratch, ignore_errors=True),
        )

    def pages(self) -> list[dict[str, Any]]:
        if not MIN_DEADLINE_SECONDS <= self.deadline_seconds <= MAX_DEADLINE_SECONDS:
            raise DiscoveryUnavailable("discovery unavailable: invalid deadline")
        try:
            connection = self.connection_factory()
        except (OSError, ProcessUnavailable) as exc:
            raise DiscoveryUnavailable(
                "discovery unavailable: app-server cannot start"
            ) from exc
        pages = []
        cursor = None
        seen = set()
        try:
            connection.request(
                "initialize",
                {
                    "clientInfo": {
                        "name": "codex-advisor",
                        "version": TRANSPORT_CONTRACT_VERSION,
                    }
                },
            )
            connection.notify("initialized", {})
            for _ in range(MAX_PAGES):
                params = {"includeHidden": True}
                if cursor is not None:
                    params["cursor"] = cursor
                response = connection.request("model/list", params)
                if not isinstance(response, Mapping) or set(response) - {
                    "data",
                    "nextCursor",
                }:
                    raise DiscoveryError("malformed discovery response")
                page = {
                    "data": response.get("data"),
                    "nextCursor": response.get("nextCursor"),
                }
                pages.append(page)
                cursor = page["nextCursor"]
                if cursor is None:
                    return pages
                if not isinstance(cursor, str) or not cursor or cursor in seen:
                    raise DiscoveryError("discovery cursor loop")
                seen.add(cursor)
            raise DiscoveryError("discovery page limit exceeded")
        except (ProcessUnavailable, TimeoutError) as exc:
            raise DiscoveryUnavailable(
                "discovery unavailable: app-server request failed"
            ) from exc
        finally:
            close = getattr(connection, "close", None)
            if callable(close):
                close()


def refresh_catalog(
    discovery: Callable[[], Sequence[Mapping[str, Any]]],
    *,
    paths: StatePaths | None = None,
    now: Callable[[], float] = time.time,
) -> dict[str, Any]:
    discovered = normalize_discovery_pages(discovery(), now=now)
    paths = paths or state_paths()
    with state_lock(paths):
        catalog = load_catalog(paths)
        manual = [
            item for item in catalog["candidates"] if item["provenance"] == "manual"
        ]
        prior = {
            (item["id"], item["model"]): item
            for item in catalog["candidates"]
            if item["provenance"] == "discovery"
        }
        keys = {(item["id"], item["model"]) for item in discovered}
        catalog["candidates"] = (
            manual
            + discovered
            + [
                {**item, "visible": False}
                for key, item in prior.items()
                if key not in keys
            ]
        )
        catalog["last_successful_refresh"] = str(int(now()))
        catalog["revision"] += 1
        _atomic_write(paths.catalog, validate_catalog(catalog))
        return catalog






def authorize_canary(
    pair: Mapping[str, str], *, paths: StatePaths | None = None, codex_version: str
) -> str:
    """Create one short-lived, single-use compatibility launch authorization."""
    pair = validate_pair(pair)
    paths = paths or state_paths()
    catalog = load_catalog(paths)
    if not _pair_is_listed(pair, catalog):
        raise ConfigError("model and effort are not listed for compatibility testing")
    token = secrets.token_hex(16)
    with state_lock(paths):
        paths.canaries.mkdir(mode=0o700, exist_ok=True)
        _safe_directory(paths.canaries, create=False)
        path = paths.canaries / f"{token}.json"
        payload = {
            "model": pair["model"],
            "effort": pair["effort"],
            "codex_version": codex_version,
            "transport_contract_version": TRANSPORT_CONTRACT_VERSION,
            "expires_at": int(time.time()) + 300,
        }
        descriptor = os.open(
            path,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0),
            0o600,
        )
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, separators=(",", ":"), sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
    return token


def consume_canary(token: str, *, paths: StatePaths | None = None) -> dict[str, Any]:
    """Consume one private launch authorization and return its frozen record."""
    if not TOKEN_RE.fullmatch(token):
        raise ConfigError("invalid canary authorization")
    paths = paths or state_paths()
    with state_lock(paths):
        _safe_directory(paths.canaries, create=False)
        path = paths.canaries / f"{token}.json"
        value = read_json(path)
        required = {
            "model",
            "effort",
            "codex_version",
            "transport_contract_version",
            "expires_at",
        }
        if not isinstance(value, dict) or set(value) != required:
            raise ConfigError("invalid canary authorization")
        pair = validate_pair({"model": value["model"], "effort": value["effort"]})
        if value["transport_contract_version"] != TRANSPORT_CONTRACT_VERSION:
            raise ConfigError("stale canary authorization")
        if (
            not isinstance(value["expires_at"], int)
            or isinstance(value["expires_at"], bool)
            or value["expires_at"] < time.time()
        ):
            raise ConfigError("expired canary authorization")
        path.unlink()
        return {
            "tier": "compatibility-test",
            **pair,
            "selection_source": "authorized-synthetic-canary",
            "selection_revision": load_catalog(paths)["revision"],
            "transport_contract_version": TRANSPORT_CONTRACT_VERSION,
            "deadline_seconds": load_settings(paths)["deadline_seconds"],
            "codex_version": value["codex_version"],
        }




class _CanaryCancelled(Exception):
    """Private signal-path marker for bounded compatibility supervision."""


def _stop_canary_wrapper(process: subprocess.Popen[bytes]) -> None:
    """Request wrapper cleanup before escalating only its owned process group."""
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        process.wait(timeout=CANARY_CLEANUP_GRACE_SECONDS)
        return
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=CANARY_CLEANUP_GRACE_SECONDS)
    except subprocess.TimeoutExpired as exc:
        raise ConfigError("compatibility canary cleanup failed") from exc


def _run_compatibility_wrapper(
    command: Sequence[str], *, deadline_seconds: int, on_status: Callable[[str], None] | None
) -> bytes:
    """Run the shell wrapper in its own group with output and signal bounds."""
    try:
        process = subprocess.Popen(
            list(command),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=None,
            start_new_session=True,
        )
    except OSError as exc:
        raise ConfigError("compatibility canary failed") from exc
    if process.stdout is None:
        _stop_canary_wrapper(process)
        raise ConfigError("compatibility canary failed")

    prior_handlers: dict[int, Any] = {}

    def cancelled(_signum: int, _frame: Any) -> None:
        raise _CanaryCancelled()

    for signum in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
        try:
            prior_handlers[signum] = signal.getsignal(signum)
            signal.signal(signum, cancelled)
        except (ValueError, OSError):
            # Signal handlers are only available from a process main thread.
            continue

    os.set_blocking(process.stdout.fileno(), False)
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    output = bytearray()
    # The wrapper owns the actual consultation deadline.  The outer supervisor
    # permits it that full interval plus time to run its TERM cleanup trap.
    outer_deadline = time.monotonic() + deadline_seconds + CANARY_CLEANUP_GRACE_SECONDS
    reported_wait = False
    try:
        while True:
            if process.poll() is not None:
                while True:
                    try:
                        chunk = os.read(process.stdout.fileno(), MAX_JSON_BYTES + 1 - len(output))
                    except BlockingIOError:
                        break
                    if not chunk:
                        break
                    output.extend(chunk)
                    if len(output) > MAX_JSON_BYTES:
                        raise ConfigError("compatibility canary exceeded output limit")
                returncode = process.wait()
                if returncode != 0:
                    raise ConfigError("compatibility canary failed")
                return bytes(output)
            remaining = outer_deadline - time.monotonic()
            if remaining <= 0:
                raise ConfigError("compatibility canary timed out")
            if on_status is not None and not reported_wait:
                on_status("compatibility canary is supervised locally")
                reported_wait = True
            events = selector.select(min(remaining, 0.25))
            for _key, _mask in events:
                while True:
                    try:
                        chunk = os.read(process.stdout.fileno(), MAX_JSON_BYTES + 1 - len(output))
                    except BlockingIOError:
                        break
                    if not chunk:
                        break
                    output.extend(chunk)
                    if len(output) > MAX_JSON_BYTES:
                        raise ConfigError("compatibility canary exceeded output limit")
    except _CanaryCancelled as exc:
        raise ConfigError("compatibility canary cancelled") from exc
    finally:
        selector.close()
        try:
            _stop_canary_wrapper(process)
        finally:
            process.stdout.close()
            for signum, previous in prior_handlers.items():
                signal.signal(signum, previous)


def test_compatibility(
    pair: Mapping[str, str],
    *,
    parent_thread: str,
    sessions_dir: str | None,
    paths: StatePaths | None = None,
    on_status: Callable[[str], None] | None = None,
) -> dict[str, Any]:
    """Run the fixed synthetic canary through the installed Advisor transport."""
    pair = validate_pair(pair)
    paths = paths or state_paths()
    version = current_codex_version()
    token = authorize_canary(pair, paths=paths, codex_version=version)
    wrapper = Path(__file__).resolve().parent / "run-advisor.sh"
    info = wrapper.lstat()
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        raise ConfigError("installed Advisor transport is unsafe")
    command = [
        "/bin/sh",
        str(wrapper),
        "--compatibility-canary",
        token,
        "--parent-thread",
        parent_thread,
    ]
    if sessions_dir is not None:
        command.extend(("--sessions-dir", sessions_dir))
    if on_status is not None:
        on_status(
            f"authorized synthetic canary for {pair['model']} / {pair['effort']}; maximum two attempts"
        )
    deadline = load_settings(paths)["deadline_seconds"]
    try:
        completed_stdout = _run_compatibility_wrapper(
            command, deadline_seconds=deadline, on_status=on_status
        )
    finally:
        authorization = paths.canaries / f"{token}.json"
        authorization.unlink(missing_ok=True)
        try:
            paths.canaries.rmdir()
        except (FileNotFoundError, OSError):
            pass
    try:
        result = json.loads(completed_stdout, object_pairs_hook=_duplicate_key)
    except (UnicodeDecodeError, json.JSONDecodeError, RecursionError) as exc:
        raise ConfigError("compatibility canary result is invalid") from exc
    runtime = result.get("runtime") if isinstance(result, dict) else None
    if (
        not isinstance(runtime, dict)
        or runtime.get("model") != pair["model"]
        or runtime.get("effort") != pair["effort"]
    ):
        raise ConfigError("compatibility canary runtime mismatch")
    catalog = record_compatibility(pair, codex_version=version, paths=paths)
    return {
        "pair": dict(pair),
        "codex_version": version,
        "transport_contract_version": TRANSPORT_CONTRACT_VERSION,
        "catalog_revision": catalog["revision"],
        "selected": False,
    }


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
