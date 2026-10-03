"""Advisor live configuration and owner-only settings revisions."""

from __future__ import annotations

import copy
import hashlib
import os
import stat
import tomllib
from collections.abc import Callable, Mapping
from pathlib import Path
from typing import Any

from advisor_catalog import (
    _pair_is_compatible,
    load_catalog,
    load_shipped_models,
)
from advisor_state import (
    DEFAULT_DEADLINE_SECONDS,
    MAX_DEADLINE_SECONDS,
    MAX_LIVE_CONFIG_BYTES,
    MIN_DEADLINE_SECONDS,
    PRESET_RE,
    SCHEMA_VERSION,
    TIERS,
    TRANSPORT_CONTRACT_VERSION,
    ConfigError,
    RevisionConflict,
    StatePaths,
    _MISSING,
    _atomic_write,
    _atomic_write_bytes,
    _read_safe_bytes,
    _require_keys,
    _safe_directory,
    read_json,
    state_lock,
    state_paths,
    validate_pair,
)

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


def _update_settings(
    paths: StatePaths, mutate: Callable[[dict[str, Any]], None]
) -> dict[str, Any]:
    """Apply one locked, revision-bumping change and retain the prior revision.

    `mutate` edits a deep copy of the current settings in place and may raise
    to abort. The result is validated before `_write_settings_revision`.
    """
    with state_lock(paths):
        current = load_settings(paths)
        settings = copy.deepcopy(current)
        mutate(settings)
        settings["revision"] += 1
        settings = validate_settings(settings)
        _write_settings_revision(paths, current=current, replacement=settings)
        return settings


def set_usage_journal(
    enabled: bool, *, paths: StatePaths | None = None
) -> dict[str, Any]:
    """Toggle the optional content-free local usage journal."""
    return _update_settings(
        paths or state_paths(),
        lambda settings: settings.update(usage_journal_enabled=enabled),
    )


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
    return _update_settings(
        paths or state_paths(),
        lambda settings: settings.update(deadline_seconds=seconds),
    )


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

    def mutate(settings: dict[str, Any]) -> None:
        if not _pair_is_compatible(pair, load_catalog(paths)):
            raise ConfigError("preset model and effort are not currently compatible")
        settings["presets"][name] = pair

    return _update_settings(paths, mutate)


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
