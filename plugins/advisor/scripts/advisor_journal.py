"""Content-free Advisor usage journal validation and persistence."""

from __future__ import annotations

import datetime as dt
import stat
import time
import uuid
from collections.abc import Callable
from pathlib import Path
from typing import Any

from advisor_settings import load_settings
from advisor_state import (
    ATTEMPT_OUTCOMES,
    JOURNAL_OUTCOMES,
    JOURNAL_RETENTION_SECONDS,
    JOURNAL_TIERS,
    MAX_DEADLINE_SECONDS,
    MAX_JOURNAL_RECORDS,
    TRANSPORT_CONTRACT_VERSION,
    ConfigError,
    StatePaths,
    _atomic_write,
    _require_keys,
    _safe_directory,
    read_json,
    state_lock,
    state_paths,
    validate_pair,
)

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
