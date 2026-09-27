"""Advisor compatibility-canary authorization and supervision."""

from __future__ import annotations

import json
import os
import secrets
import selectors
import signal
import stat
import subprocess
import time
from collections.abc import Callable, Mapping, Sequence
from pathlib import Path
from typing import Any

from advisor_catalog import _pair_is_listed, load_catalog, record_compatibility
from advisor_settings import load_settings
from advisor_state import (
    CANARY_CLEANUP_GRACE_SECONDS,
    MAX_JSON_BYTES,
    TOKEN_RE,
    TRANSPORT_CONTRACT_VERSION,
    ConfigError,
    StatePaths,
    _duplicate_key,
    _safe_directory,
    current_codex_version,
    read_json,
    state_lock,
    state_paths,
    validate_pair,
)

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
