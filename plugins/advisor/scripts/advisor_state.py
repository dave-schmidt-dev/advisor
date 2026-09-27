"""Owner-only Advisor state, validation, and bounded local probes."""

from __future__ import annotations

import fcntl
import json
import os
import re
import selectors
import stat
import subprocess
import tempfile
import time
from collections.abc import Callable, Iterator, Mapping, Sequence
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from advisor_process import terminate_owned

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
