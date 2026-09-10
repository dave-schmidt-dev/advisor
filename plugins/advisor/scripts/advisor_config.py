#!/usr/bin/env python3
"""Safe Advisor selection state and bounded Codex app-server discovery."""

from __future__ import annotations

import argparse
import copy
import datetime as dt
import fcntl
import hashlib
import json
import os
import re
import secrets
import selectors
import signal
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import uuid
import tomllib
from collections.abc import Callable, Iterator, Mapping, Sequence
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Any

_SCRIPT_DIR = str(Path(__file__).resolve().parent)
if _SCRIPT_DIR not in sys.path:
    sys.path.insert(0, _SCRIPT_DIR)
from advisor_process import JsonRpcProcess, ProcessUnavailable, terminate_owned

SCHEMA_VERSION = 1
TRANSPORT_CONTRACT_VERSION = "1.4"
MAX_JSON_BYTES = 1_000_000
MAX_LIVE_CONFIG_BYTES = 64 * 1024
MAX_JOURNAL_RECORDS = 1_024
JOURNAL_RETENTION_SECONDS = 30 * 24 * 60 * 60
JOURNAL_OUTCOMES = frozenset(
    ("accepted", "failed", "timed_out", "cancelled", "retry_exhausted")
)
ATTEMPT_OUTCOMES = frozenset(
    (
        "accepted",
        "rejected_response",
        "launch_failed",
        "runtime_failed",
        "timed_out",
        "cancelled",
    )
)
MAX_PAGES = 64
MAX_EVENTS = 512
MAX_MODELS = 2_000
DEFAULT_DEADLINE_SECONDS = 300
MIN_DEADLINE_SECONDS = 30
MAX_DEADLINE_SECONDS = 900
LOCK_DEADLINE_SECONDS = 5
CANARY_CLEANUP_GRACE_SECONDS = 5
EFFORTS = frozenset(
    ("none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra")
)
TIERS = frozenset(("standard", "specialist"))
JOURNAL_TIERS = frozenset((*TIERS, "compatibility-test", "opt-in"))
SELECTOR_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$")
PRESET_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$")
TOKEN_RE = re.compile(r"^[0-9a-f]{32}$")
_MISSING = object()
_NO_DEFAULT = object()


class ConfigError(ValueError):
    pass


class RevisionConflict(ConfigError):
    pass


class DiscoveryUnavailable(ConfigError):
    pass


class DiscoveryError(ConfigError):
    pass


def _run_bounded_output(
    argv: Sequence[str], *, timeout_seconds: float, max_bytes: int
) -> tuple[int, bytes]:
    """Run a local probe with bounded time, output, and process ownership."""
    try:
        process = subprocess.Popen(
            list(argv),
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError as exc:
        raise ConfigError("local process probe is unavailable") from exc
    if process.stdout is None:
        terminate_owned(process)
        raise ConfigError("local process probe is unavailable")
    os.set_blocking(process.stdout.fileno(), False)
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    deadline = time.monotonic() + timeout_seconds
    output = bytearray()
    reached_eof = False
    try:
        while not reached_eof:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise ConfigError("local process probe is unavailable")
            events = selector.select(remaining)
            if not events:
                raise ConfigError("local process probe is unavailable")
            while True:
                try:
                    chunk = os.read(
                        process.stdout.fileno(), max_bytes + 1 - len(output)
                    )
                except BlockingIOError:
                    break
                if not chunk:
                    reached_eof = True
                    break
                output.extend(chunk)
                if len(output) > max_bytes:
                    raise ConfigError("local process probe exceeded output limit")
        returncode = process.wait(timeout=max(0.01, deadline - time.monotonic()))
        return returncode, bytes(output)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise ConfigError("local process probe is unavailable") from exc
    finally:
        selector.close()
        if process.poll() is None:
            terminate_owned(process)


def _duplicate_key(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ConfigError("duplicate JSON key")
        result[key] = value
    return result


def _safe_directory(path: Path, *, create: bool) -> None:
    if create:
        try:
            parent = path.parent.lstat()
        except FileNotFoundError as exc:
            raise ConfigError("Codex home directory is missing") from exc
        if stat.S_ISLNK(parent.st_mode) or not stat.S_ISDIR(parent.st_mode):
            raise ConfigError("Codex home directory is unsafe")
        try:
            path.mkdir(mode=0o700, exist_ok=True)
        except OSError as exc:
            raise ConfigError("cannot create Advisor state directory") from exc
    # Check the state root and Codex-home ancestor.  Do not reject macOS system
    # aliases above that trusted boundary (for example /var -> /private/var).
    current = path
    for _ in range(2):
        try:
            info = current.lstat()
        except FileNotFoundError as exc:
            raise ConfigError("Advisor state directory is missing") from exc
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
            raise ConfigError("Advisor state directory is unsafe")
        if current == path and (info.st_uid != os.getuid() or info.st_mode & 0o077):
            raise ConfigError("Advisor state directory is not owner-only")
        current = current.parent


def read_json(path: Path, *, missing: Any = _NO_DEFAULT) -> Any:
    try:
        info = path.lstat()
    except FileNotFoundError:
        if missing is _NO_DEFAULT:
            raise ConfigError(f"state file is missing: {path.name}")
        return missing
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        raise ConfigError(f"unsafe state file: {path.name}")
    if info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ConfigError(f"state file is not owner-only: {path.name}")
    if info.st_size > MAX_JSON_BYTES:
        raise ConfigError(f"state file is too large: {path.name}")
    try:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle, object_pairs_hook=_duplicate_key)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, RecursionError) as exc:
        raise ConfigError(f"invalid JSON in {path.name}") from exc


def _require_keys(value: Any, required: set[str], *, label: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != required:
        raise ConfigError(f"invalid {label} keys")
    return value


def _validate_selector(value: Any, *, label: str = "model") -> str:
    if not isinstance(value, str) or not SELECTOR_RE.fullmatch(value):
        raise ConfigError(f"unsafe {label} selector")
    return value


def _validate_effort(value: Any) -> str:
    if not isinstance(value, str) or value not in EFFORTS:
        raise ConfigError("unsupported effort")
    return value


def validate_pair(value: Any) -> dict[str, str]:
    value = _require_keys(value, {"model", "effort"}, label="model pair")
    return {
        "model": _validate_selector(value["model"]),
        "effort": _validate_effort(value["effort"]),
    }


def live_config_path() -> Path:
    """Return the installed, editable configuration bundled with Advisor."""
    return Path(__file__).resolve().parent.parent / "advisor.toml"


def load_live_config() -> dict[str, Any]:
    """Read the exact two-role TOML configuration without consulting local state."""
    path = live_config_path()
    flags = os.O_RDONLY | os.O_CLOEXEC | os.O_NONBLOCK
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        descriptor = os.open(path, flags)
    except OSError as exc:
        raise ConfigError("advisor.toml is missing or unavailable") from exc
    try:
        info = os.fstat(descriptor)
        if not stat.S_ISREG(info.st_mode):
            raise ConfigError("advisor.toml must be a regular file")
        if info.st_size > MAX_LIVE_CONFIG_BYTES:
            raise ConfigError("advisor.toml is too large")
        chunks: list[bytes] = []
        remaining = MAX_LIVE_CONFIG_BYTES + 1
        while remaining:
            chunk = os.read(descriptor, min(16 * 1024, remaining))
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        raw = b"".join(chunks)
        if len(raw) > MAX_LIVE_CONFIG_BYTES:
            raise ConfigError("advisor.toml is too large")
        value = tomllib.loads(raw.decode("utf-8"))
    except (OSError, UnicodeDecodeError, tomllib.TOMLDecodeError, RecursionError) as exc:
        raise ConfigError("advisor.toml is malformed") from exc
    finally:
        os.close(descriptor)
    if not isinstance(value, dict) or set(value) != TIERS:
        raise ConfigError("advisor.toml must contain only standard and specialist tables")
    try:
        pairs = {tier: validate_pair(value[tier]) for tier in sorted(TIERS)}
    except ConfigError as exc:
        raise ConfigError("advisor.toml has invalid role settings") from exc
    return {
        "path": str(path),
        "source_revision": "sha256:" + hashlib.sha256(raw).hexdigest(),
        "pairs": pairs,
    }


def baseline_settings() -> dict[str, Any]:
    defaults = load_shipped_models()["defaults"]
    return {
        "schema_version": SCHEMA_VERSION,
        "revision": 0,
        "selections": copy.deepcopy(defaults),
        "presets": {},
        "deadline_seconds": DEFAULT_DEADLINE_SECONDS,
        "usage_journal_enabled": False,
    }


def validate_settings(value: Any) -> dict[str, Any]:
    value = _require_keys(
        value,
        {
            "schema_version",
            "revision",
            "selections",
            "presets",
            "deadline_seconds",
            "usage_journal_enabled",
        },
        label="settings",
    )
    if (
        not isinstance(value["schema_version"], int)
        or isinstance(value["schema_version"], bool)
        or value["schema_version"] != SCHEMA_VERSION
    ):
        raise ConfigError("unsupported settings schema")
    if (
        not isinstance(value["revision"], int)
        or isinstance(value["revision"], bool)
        or value["revision"] < 0
    ):
        raise ConfigError("invalid settings revision")
    selections = _require_keys(value["selections"], set(TIERS), label="selections")
    if not isinstance(value["presets"], dict):
        raise ConfigError("invalid presets")
    presets = {}
    for name, pair in value["presets"].items():
        if not isinstance(name, str) or not PRESET_RE.fullmatch(name):
            raise ConfigError("unsafe preset name")
        presets[name] = validate_pair(pair)
    deadline = value["deadline_seconds"]
    if (
        not isinstance(deadline, int)
        or isinstance(deadline, bool)
        or not MIN_DEADLINE_SECONDS <= deadline <= MAX_DEADLINE_SECONDS
    ):
        raise ConfigError("invalid deadline")
    if not isinstance(value["usage_journal_enabled"], bool):
        raise ConfigError("invalid usage journal setting")
    return {
        "schema_version": SCHEMA_VERSION,
        "revision": value["revision"],
        "selections": {tier: validate_pair(selections[tier]) for tier in sorted(TIERS)},
        "presets": presets,
        "deadline_seconds": deadline,
        "usage_journal_enabled": value["usage_journal_enabled"],
    }


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


@dataclass(frozen=True)
class StatePaths:
    root: Path

    @property
    def settings(self) -> Path:
        return self.root / "settings.json"

    @property
    def prior_settings(self) -> Path:
        """One owner-only prior revision retained for explicit restoration."""
        return self.root / "settings.previous.json"

    @property
    def invalid_settings(self) -> Path:
        """Most recently preserved malformed settings bytes."""
        return self.root / "settings.invalid.json"

    @property
    def catalog(self) -> Path:
        return self.root / "catalog.json"

    @property
    def lock(self) -> Path:
        return self.root / ".lock"

    @property
    def canaries(self) -> Path:
        return self.root / "canaries"

    @property
    def journal(self) -> Path:
        return self.root / "usage-journal"


def state_paths(codex_home: str | os.PathLike[str] | None = None) -> StatePaths:
    home = Path(codex_home or os.environ.get("CODEX_HOME") or Path.home() / ".codex")
    if not home.is_absolute():
        raise ConfigError("CODEX_HOME must be absolute")
    return StatePaths(home / "advisor")


@contextmanager
def state_lock(
    paths: StatePaths, *, on_status: Callable[[str], None] | None = None
) -> Iterator[None]:
    _safe_directory(paths.root, create=True)
    try:
        fd = os.open(
            paths.lock, os.O_RDWR | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0), 0o600
        )
    except OSError as exc:
        raise ConfigError("cannot open Advisor state lock") from exc
    try:
        info = os.fstat(fd)
        if (
            not stat.S_ISREG(info.st_mode)
            or info.st_uid != os.getuid()
            or info.st_mode & 0o077
        ):
            raise ConfigError("Advisor state lock is unsafe")
        deadline = time.monotonic() + LOCK_DEADLINE_SECONDS
        reported = False
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise ConfigError("Advisor state lock timed out")
                if on_status and not reported:
                    on_status("waiting for local state lock")
                    reported = True
                time.sleep(0.05)
        yield
    finally:
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            os.close(fd)


def _read_safe_bytes(path: Path) -> bytes:
    """Read one bounded owner-only state file without parsing its contents."""
    try:
        info = path.lstat()
    except FileNotFoundError as exc:
        raise ConfigError(f"state file is missing: {path.name}") from exc
    if (
        stat.S_ISLNK(info.st_mode)
        or not stat.S_ISREG(info.st_mode)
        or info.st_uid != os.getuid()
        or info.st_mode & 0o077
    ):
        raise ConfigError(f"unsafe state file: {path.name}")
    if info.st_size > MAX_JSON_BYTES:
        raise ConfigError(f"state file is too large: {path.name}")
    try:
        return path.read_bytes()
    except OSError as exc:
        raise ConfigError(f"state file is unreadable: {path.name}") from exc


def _atomic_write_bytes(path: Path, encoded: bytes) -> None:
    """Atomically replace one owner-only state file with bounded bytes."""
    _safe_directory(path.parent, create=False)
    if len(encoded) > MAX_JSON_BYTES:
        raise ConfigError("state JSON exceeds byte limit")
    if path.exists() or path.is_symlink():
        info = path.lstat()
        if (
            stat.S_ISLNK(info.st_mode)
            or not stat.S_ISREG(info.st_mode)
            or info.st_uid != os.getuid()
            or info.st_mode & 0o077
        ):
            raise ConfigError(f"unsafe state file: {path.name}")
    descriptor, staged_name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=path.parent
    )
    staged = Path(staged_name)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(encoded)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(staged, path)
    except Exception:
        staged.unlink(missing_ok=True)
        raise


def _atomic_write(path: Path, value: Mapping[str, Any]) -> None:
    encoded = (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()
    _atomic_write_bytes(path, encoded)


def load_settings(paths: StatePaths | None = None) -> dict[str, Any]:
    paths = paths or state_paths()
    if not paths.root.exists() and not paths.root.is_symlink():
        return baseline_settings()
    _safe_directory(paths.root, create=False)
    stored = read_json(paths.settings, missing=_MISSING)
    if stored is _MISSING:
        return baseline_settings()
    # The initial 1.4 settings record has no journal choice. It migrates in memory to
    # the privacy-preserving default and is persisted on the next settings write.
    if isinstance(stored, dict) and set(stored) == {
        "schema_version",
        "revision",
        "selections",
        "presets",
        "deadline_seconds",
    }:
        stored = {**stored, "usage_journal_enabled": False}
    return validate_settings(stored)


def set_usage_journal(
    enabled: bool, *, paths: StatePaths | None = None
) -> dict[str, Any]:
    """Toggle the optional content-free local usage journal."""
    paths = paths or state_paths()
    with state_lock(paths):
        current = load_settings(paths)
        settings = dict(current)
        settings["usage_journal_enabled"] = enabled
        settings["revision"] += 1
        settings = validate_settings(settings)
        _write_settings_revision(paths, current=current, replacement=settings)
        return settings


def _validate_usage_count(value: Any) -> int | None:
    if value is None:
        return None
    if not isinstance(value, int) or isinstance(value, bool) or value < 0:
        raise ConfigError("invalid journal usage counter")
    return value


def validate_journal_record(value: Any) -> dict[str, Any]:
    """Validate the deliberately content-free persisted consultation receipt."""
    value = _require_keys(
        value,
        {
            "schema_version",
            "consultation_id",
            "started_at",
            "finished_at",
            "tier",
            "model",
            "effort",
            "outcome",
            "transport_contract_version",
            "total_duration_ms",
            "attempts",
            "totals",
        },
        label="usage journal record",
    )
    if value["schema_version"] != 1 or not isinstance(value["consultation_id"], str):
        raise ConfigError("invalid usage journal record")
    try:
        parsed_id = uuid.UUID(value["consultation_id"])
    except (ValueError, AttributeError) as exc:
        raise ConfigError("invalid usage journal record") from exc
    if parsed_id.version != 4:
        raise ConfigError("invalid usage journal record")
    if value["transport_contract_version"] != TRANSPORT_CONTRACT_VERSION:
        raise ConfigError("invalid usage journal record")

    def timestamp(name: str) -> dt.datetime:
        raw = value[name]
        if not isinstance(raw, str) or len(raw) > 64:
            raise ConfigError("invalid usage journal record")
        try:
            parsed = dt.datetime.fromisoformat(raw.replace("Z", "+00:00"))
        except ValueError as exc:
            raise ConfigError("invalid usage journal record") from exc
        if parsed.tzinfo is None:
            raise ConfigError("invalid usage journal record")
        return parsed.astimezone(dt.timezone.utc)

    started, finished = timestamp("started_at"), timestamp("finished_at")
    if finished < started or finished > started + dt.timedelta(
        seconds=MAX_DEADLINE_SECONDS + 10
    ):
        raise ConfigError("invalid usage journal record")
    if value["outcome"] not in JOURNAL_OUTCOMES:
        raise ConfigError("invalid usage journal record")
    if (
        not isinstance(value["total_duration_ms"], int)
        or isinstance(value["total_duration_ms"], bool)
        or value["total_duration_ms"] < 0
    ):
        raise ConfigError("invalid usage journal record")
    tier = value["tier"]
    if tier not in JOURNAL_TIERS:
        raise ConfigError("invalid usage journal record")
    pair = validate_pair({"model": value["model"], "effort": value["effort"]})
    if not isinstance(value["attempts"], list) or not 1 <= len(value["attempts"]) <= 2:
        raise ConfigError("invalid usage journal record")

    def usage(item: Any) -> dict[str, int | None]:
        item = _require_keys(
            item,
            {"input", "cached_input", "output", "reasoning"},
            label="journal usage",
        )
        return {name: _validate_usage_count(item[name]) for name in item}

    attempts = []
    for item in value["attempts"]:
        item = _require_keys(
            item, {"number", "duration_ms", "outcome", "usage"}, label="journal attempt"
        )
        if (
            not isinstance(item["number"], int)
            or isinstance(item["number"], bool)
            or item["number"] not in (1, 2)
            or not isinstance(item["duration_ms"], int)
            or isinstance(item["duration_ms"], bool)
            or item["duration_ms"] < 0
            or item["outcome"] not in ATTEMPT_OUTCOMES
        ):
            raise ConfigError("invalid usage journal record")
        attempts.append(
            {
                "number": item["number"],
                "duration_ms": item["duration_ms"],
                "outcome": item["outcome"],
                "usage": usage(item["usage"]),
            }
        )
    if [item["number"] for item in attempts] != list(range(1, len(attempts) + 1)):
        raise ConfigError("invalid usage journal record")
    if value["total_duration_ms"] < sum(item["duration_ms"] for item in attempts):
        raise ConfigError("invalid usage journal record")
    final_outcome = attempts[-1]["outcome"]
    compatible_final = {
        "accepted": {"accepted"},
        "failed": {"launch_failed", "runtime_failed"},
        "timed_out": {"timed_out"},
        "cancelled": {"cancelled"},
        "retry_exhausted": {"rejected_response"},
    }
    if final_outcome not in compatible_final[value["outcome"]]:
        raise ConfigError("invalid usage journal record")
    totals = usage(value["totals"])
    for name in totals:
        known = [
            item["usage"][name] for item in attempts if item["usage"][name] is not None
        ]
        expected = sum(known) if known else None
        if totals[name] != expected:
            raise ConfigError("invalid usage journal record")
    return {
        "schema_version": 1,
        "consultation_id": str(parsed_id),
        "started_at": value["started_at"],
        "finished_at": value["finished_at"],
        "tier": tier,
        **pair,
        "outcome": value["outcome"],
        "transport_contract_version": TRANSPORT_CONTRACT_VERSION,
        "total_duration_ms": value["total_duration_ms"],
        "attempts": attempts,
        "totals": totals,
    }


def _prune_usage_journal(
    paths: StatePaths, *, now: float, on_status: Callable[[str], None] | None = None
) -> None:
    if not paths.journal.exists():
        return
    _safe_directory(paths.journal, create=False)
    entries = list(paths.journal.iterdir())
    for index, item in enumerate(entries, 1):
        if on_status and (index == 1 or index == len(entries) or index % 25 == 0):
            on_status(f"usage journal retention checked {index}/{len(entries)} records")
        info = item.lstat()
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
            raise ConfigError("usage journal is unsafe")
        try:
            record = validate_journal_record(read_json(item))
            finished = dt.datetime.fromisoformat(
                record["finished_at"].replace("Z", "+00:00")
            ).timestamp()
        except (ConfigError, OSError, ValueError):
            raise ConfigError("usage journal is unsafe")
        if finished < now - JOURNAL_RETENTION_SECONDS:
            item.unlink()


def write_usage_journal(
    value: Any,
    *,
    paths: StatePaths | None = None,
    on_status: Callable[[str], None] | None = None,
) -> bool:
    """Atomically retain one bounded receipt when the user opted in."""
    clean = validate_journal_record(value)
    paths = paths or state_paths()
    if not paths.root.exists() and not paths.root.is_symlink():
        return False
    with state_lock(paths, on_status=on_status):
        settings = load_settings(paths)
        if not settings["usage_journal_enabled"]:
            return False
        paths.journal.mkdir(mode=0o700, exist_ok=True)
        _safe_directory(paths.journal, create=False)
        _prune_usage_journal(paths, now=time.time(), on_status=on_status)
        records = list(paths.journal.iterdir())
        if len(records) >= MAX_JOURNAL_RECORDS:

            def logical_time(entry: Path) -> float:
                record = validate_journal_record(read_json(entry))
                return dt.datetime.fromisoformat(
                    record["finished_at"].replace("Z", "+00:00")
                ).timestamp()

            for item in sorted(records, key=logical_time)[
                : len(records) - MAX_JOURNAL_RECORDS + 1
            ]:
                item.unlink()
        _atomic_write(paths.journal / f"{clean['consultation_id']}.json", clean)
        return True


def clear_usage_journal(*, paths: StatePaths | None = None) -> int:
    paths = paths or state_paths()
    with state_lock(paths):
        if not paths.journal.exists():
            return 0
        _safe_directory(paths.journal, create=False)
        entries = list(paths.journal.iterdir())
        for item in entries:
            info = item.lstat()
            if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
                raise ConfigError("usage journal is unsafe")
        for item in entries:
            item.unlink()
        return len(entries)


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


def save_settings(
    value: Mapping[str, Any], *, expected_revision: int, paths: StatePaths | None = None
) -> dict[str, Any]:
    paths = paths or state_paths()
    clean = validate_settings(dict(value))
    with state_lock(paths):
        current = load_settings(paths)
        if current["revision"] != expected_revision:
            raise RevisionConflict("settings revision changed")
        clean["revision"] = expected_revision + 1
        _write_settings_revision(paths, current=current, replacement=clean)
        return clean


def _write_settings_revision(
    paths: StatePaths, *, current: Mapping[str, Any], replacement: Mapping[str, Any]
) -> None:
    """Persist a new settings revision while retaining its explicit predecessor.

    Each file replacement is atomic. The active file is replaced first, so a
    failed active write cannot destroy the retained prior revision. Mutation
    callers hold the stable state lock while both replacements complete.
    """
    had_active = paths.settings.exists() and not paths.settings.is_symlink()
    active_bytes = _read_safe_bytes(paths.settings) if had_active else None
    _atomic_write(paths.settings, validate_settings(dict(replacement)))
    try:
        _atomic_write(paths.prior_settings, validate_settings(dict(current)))
    except Exception:
        if active_bytes is None:
            paths.settings.unlink(missing_ok=True)
        else:
            _atomic_write_bytes(paths.settings, active_bytes)
        raise


def save_catalog(
    value: Mapping[str, Any], *, expected_revision: int, paths: StatePaths | None = None
) -> dict[str, Any]:
    paths = paths or state_paths()
    clean = validate_catalog(dict(value))
    with state_lock(paths):
        if load_catalog(paths)["revision"] != expected_revision:
            raise RevisionConflict("catalog revision changed")
        clean["revision"] = expected_revision + 1
        _atomic_write(paths.catalog, clean)
        return clean


def reset_selections(*, paths: StatePaths | None = None) -> dict[str, Any]:
    paths = paths or state_paths()
    with state_lock(paths):
        current = load_settings(paths)
        current["selections"] = baseline_settings()["selections"]
        current["revision"] += 1
        _write_settings_revision(paths, current=load_settings(paths), replacement=current)
        return current


def restore_prior_settings(*, paths: StatePaths | None = None) -> dict[str, Any]:
    """Explicitly restore the retained prior settings revision.

    The revision remains monotonic and the current revision becomes the next
    backup.  No model is selected implicitly by reads, doctor, or recovery.
    """
    paths = paths or state_paths()
    with state_lock(paths):
        prior = validate_settings(read_json(paths.prior_settings))
        try:
            current = load_settings(paths)
        except ConfigError:
            try:
                structured = read_json(paths.settings)
            except ConfigError:
                structured = None
            if (
                isinstance(structured, dict)
                and isinstance(structured.get("schema_version"), int)
                and not isinstance(structured.get("schema_version"), bool)
                and structured["schema_version"] != SCHEMA_VERSION
            ):
                raise ConfigError(
                    "unsupported settings schema; restore refuses to downgrade a newer settings record"
                )
            malformed = _read_safe_bytes(paths.settings)
            restored = dict(prior)
            restored["revision"] = prior["revision"] + 1
            had_invalid = (
                paths.invalid_settings.exists()
                and not paths.invalid_settings.is_symlink()
            )
            prior_invalid = (
                _read_safe_bytes(paths.invalid_settings) if had_invalid else None
            )
            _atomic_write_bytes(paths.invalid_settings, malformed)
            try:
                _atomic_write(paths.settings, validate_settings(restored))
            except Exception:
                if prior_invalid is None:
                    paths.invalid_settings.unlink(missing_ok=True)
                else:
                    _atomic_write_bytes(paths.invalid_settings, prior_invalid)
                raise
            return restored
        restored = dict(prior)
        restored["revision"] = current["revision"] + 1
        _write_settings_revision(paths, current=current, replacement=restored)
        return restored


def set_deadline(seconds: int, *, paths: StatePaths | None = None) -> dict[str, Any]:
    """Persist the total Advisor deadline without changing selections."""
    if isinstance(seconds, bool) or not isinstance(seconds, int):
        raise ConfigError("invalid deadline")
    paths = paths or state_paths()
    with state_lock(paths):
        current = load_settings(paths)
        updated = dict(current)
        updated["deadline_seconds"] = seconds
        updated["revision"] += 1
        updated = validate_settings(updated)
        _write_settings_revision(paths, current=current, replacement=updated)
        return updated


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


def current_codex_version(*, timeout_seconds: float = 5.0) -> str:
    """Return the exact installed CLI version using a bounded local probe."""
    try:
        returncode, output = _run_bounded_output(
            ["codex", "--version"],
            timeout_seconds=timeout_seconds,
            max_bytes=4096,
        )
    except ConfigError as exc:
        raise ConfigError("Codex CLI version is unavailable") from exc
    if returncode != 0:
        raise ConfigError("Codex CLI version is unavailable")
    try:
        version = output.decode("utf-8").strip()
    except UnicodeDecodeError as exc:
        raise ConfigError("Codex CLI version is unavailable") from exc
    if not version or "\n" in version or "\r" in version:
        raise ConfigError("Codex CLI version is unavailable")
    return version


def set_selection(
    tier: str,
    pair: Mapping[str, str],
    *,
    paths: StatePaths | None = None,
) -> dict[str, Any]:
    if tier not in TIERS:
        raise ConfigError("unsupported tier")
    pair = validate_pair(pair)
    paths = paths or state_paths()
    with state_lock(paths):
        settings, catalog = load_settings(paths), load_catalog(paths)
        current = copy.deepcopy(settings)
        settings = copy.deepcopy(settings)
        if not (
            shipped_default_launch_eligible(tier=tier, **pair)
            or _pair_is_compatible(pair, catalog)
        ):
            raise ConfigError("selected model and effort are not currently compatible")
        settings["selections"][tier] = pair
        settings["revision"] += 1
        settings = validate_settings(settings)
        _write_settings_revision(paths, current=current, replacement=settings)
        return settings


def save_preset(
    name: str,
    pair: Mapping[str, str],
    *,
    paths: StatePaths | None = None,
) -> dict[str, Any]:
    if not PRESET_RE.fullmatch(name):
        raise ConfigError("unsafe preset name")
    pair = validate_pair(pair)
    paths = paths or state_paths()
    with state_lock(paths):
        settings, catalog = load_settings(paths), load_catalog(paths)
        current = copy.deepcopy(settings)
        settings = copy.deepcopy(settings)
        if not _pair_is_compatible(pair, catalog):
            raise ConfigError("preset model and effort are not currently compatible")
        settings["presets"][name] = pair
        settings["revision"] += 1
        settings = validate_settings(settings)
        _write_settings_revision(paths, current=current, replacement=settings)
        return settings


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


def resolve_selection(
    tier: str,
    *,
    preset: str | None = None,
    paths: StatePaths | None = None,
) -> dict[str, Any]:
    if tier not in TIERS:
        raise ConfigError("unsupported tier")
    # Normal --tier consultations are defined by the installed live TOML and never
    # read saved selections, catalog evidence, or canary receipts. Presets remain
    # an explicit legacy/advanced route for callers that still ask for one.
    if not preset:
        live = load_live_config()
        deadline_seconds = DEFAULT_DEADLINE_SECONDS
        try:
            deadline_seconds = load_settings(paths)["deadline_seconds"]
        except ConfigError:
            pass
        pair = live["pairs"][tier]
        return {
            "tier": tier,
            "model": pair["model"],
            "effort": pair["effort"],
            "selection_source": "live-config",
            "selection_revision": live["source_revision"],
            "source_revision": live["source_revision"],
            "config_path": live["path"],
            "transport_contract_version": TRANSPORT_CONTRACT_VERSION,
            "deadline_seconds": deadline_seconds,
        }
    settings, catalog = load_settings(paths), load_catalog(paths)
    source = "legacy-preset"
    if not PRESET_RE.fullmatch(preset) or preset not in settings["presets"]:
        raise ConfigError("unknown preset")
    pair = settings["presets"][preset]
    compatible = _pair_is_compatible(pair, catalog)
    if not compatible:
        raise ConfigError("selected model and effort are not currently compatible")
    return {
        "tier": tier,
        "model": pair["model"],
        "effort": pair["effort"],
        "selection_source": source,
        "selection_revision": settings["revision"],
        "source_revision": f"legacy-settings:{settings['revision']}",
        "transport_contract_version": TRANSPORT_CONTRACT_VERSION,
        "deadline_seconds": settings["deadline_seconds"],
    }


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


def _last_journal_failure(paths: StatePaths) -> dict[str, str] | None:
    """Return only the newest content-free failed outcome, if safely readable."""
    if not paths.journal.exists():
        return None
    _safe_directory(paths.journal, create=False)
    failures: list[dict[str, str]] = []
    for path in paths.journal.iterdir():
        record = validate_journal_record(read_json(path))
        if record["outcome"] != "accepted":
            failures.append(
                {"outcome": record["outcome"], "finished_at": record["finished_at"]}
            )
    return max(failures, key=lambda item: item["finished_at"], default=None)


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
