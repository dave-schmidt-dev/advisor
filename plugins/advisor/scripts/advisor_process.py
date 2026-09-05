#!/usr/bin/env python3
"""Bounded process supervision for Advisor transports."""

from __future__ import annotations

import argparse
import json
import os
import selectors
import signal
import stat
import subprocess
import sys
import time
from collections.abc import Callable, Mapping, Sequence
from typing import Any

MAX_LINE_BYTES = 1_000_000
MAX_MESSAGES = 512
MAX_WRITE_BYTES = 1_000_000
MAX_PACKET_BYTES = 1_000_000
MAX_JSON_DEPTH = 32
HEARTBEAT_SECONDS = 10.0
TERM_GRACE_SECONDS = 2.0


class ProcessUnavailable(RuntimeError):
    """Raised when an owned process cannot satisfy its bounded protocol."""


def _signal_group(process: subprocess.Popen[Any], sig: signal.Signals) -> None:
    """Signal only the process group created for ``process``."""
    try:
        os.killpg(process.pid, sig)
    except ProcessLookupError:
        return
    except PermissionError as exc:
        raise ProcessUnavailable("cannot signal owned process group") from exc


def terminate_owned(process: subprocess.Popen[Any]) -> None:
    """Terminate and reap a process group created with ``start_new_session``."""
    _signal_group(process, signal.SIGTERM)
    try:
        process.wait(timeout=TERM_GRACE_SECONDS)
    except subprocess.TimeoutExpired:
        _signal_group(process, signal.SIGKILL)
        try:
            process.wait(timeout=TERM_GRACE_SECONDS)
        except subprocess.TimeoutExpired as exc:
            raise ProcessUnavailable("owned process could not be reaped") from exc
    finally:
        # The leader may exit before descendants. This group was created by us.
        _signal_group(process, signal.SIGKILL)


class JsonRpcProcess:
    """Bounded newline-delimited JSON-RPC client for one owned app-server."""

    def __init__(
        self,
        argv: Sequence[str],
        *,
        deadline_seconds: float,
        cwd: str | os.PathLike[str] | None = None,
        on_status: Callable[[str], None] | None = None,
        on_close: Callable[[], None] | None = None,
    ) -> None:
        self.deadline = time.monotonic() + deadline_seconds
        self.on_status = on_status
        self.on_close = on_close
        self.next_id = 1
        self._buffer = bytearray()
        self._messages = 0
        self._next_heartbeat = time.monotonic() + HEARTBEAT_SECONDS
        self._closed = False
        try:
            self.process = subprocess.Popen(
                list(argv),
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                cwd=cwd,
                bufsize=0,
                start_new_session=True,
            )
        except OSError as exc:
            if on_close is not None:
                on_close()
            raise ProcessUnavailable("cannot start app-server") from exc
        if self.process.stdin is None or self.process.stdout is None:
            self.close()
            raise ProcessUnavailable("app-server pipes unavailable")
        os.set_blocking(self.process.stdin.fileno(), False)
        os.set_blocking(self.process.stdout.fileno(), False)

    def _remaining(self) -> float:
        remaining = self.deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError("app-server deadline exceeded")
        return remaining

    def _wait_timeout(self) -> float:
        return min(
            self._remaining(),
            max(0.0, self._next_heartbeat - time.monotonic()),
        )

    def _heartbeat(self) -> None:
        now = time.monotonic()
        if now >= self._next_heartbeat:
            if self.on_status is not None:
                self.on_status("waiting for app-server response")
            self._next_heartbeat = now + HEARTBEAT_SECONDS

    def _send(self, value: Mapping[str, Any]) -> None:
        encoded = (json.dumps(value, separators=(",", ":")) + "\n").encode("utf-8")
        if len(encoded) > MAX_WRITE_BYTES:
            raise ProcessUnavailable("app-server request too large")
        view = memoryview(encoded)
        selector = selectors.DefaultSelector()
        selector.register(self.process.stdin, selectors.EVENT_WRITE)
        try:
            while view:
                events = selector.select(self._wait_timeout())
                self._heartbeat()
                if not events:
                    continue
                try:
                    written = os.write(self.process.stdin.fileno(), view)
                except (BrokenPipeError, OSError) as exc:
                    raise ProcessUnavailable("app-server write failed") from exc
                if written <= 0:
                    raise ProcessUnavailable("app-server write failed")
                view = view[written:]
        finally:
            selector.close()

    def notify(self, method: str, params: Mapping[str, Any]) -> None:
        """Send one JSON-RPC notification within the shared deadline."""
        self._send({"jsonrpc": "2.0", "method": method, "params": params})

    def _read_message(self, selector: selectors.BaseSelector) -> Mapping[str, Any]:
        while True:
            newline = self._buffer.find(b"\n")
            if newline >= 0:
                raw = bytes(self._buffer[:newline])
                del self._buffer[: newline + 1]
                if not raw:
                    raise ProcessUnavailable("malformed app-server JSON")
                self._messages += 1
                if self._messages > MAX_MESSAGES:
                    raise ProcessUnavailable("app-server message limit exceeded")
                try:
                    message = json.loads(raw)
                except (UnicodeDecodeError, json.JSONDecodeError) as exc:
                    raise ProcessUnavailable("malformed app-server JSON") from exc
                if not isinstance(message, dict):
                    raise ProcessUnavailable("malformed app-server response")
                return message

            if len(self._buffer) >= MAX_LINE_BYTES:
                raise ProcessUnavailable("app-server response too large")
            events = selector.select(self._wait_timeout())
            self._heartbeat()
            if not events:
                continue
            try:
                chunk = os.read(
                    self.process.stdout.fileno(),
                    min(65536, MAX_LINE_BYTES + 1),
                )
            except OSError as exc:
                raise ProcessUnavailable("app-server read failed") from exc
            if not chunk:
                raise ProcessUnavailable("app-server exited")
            self._buffer.extend(chunk)

    def request(self, method: str, params: Mapping[str, Any]) -> Any:
        """Send one request and return its matching result."""
        request_id = self.next_id
        self.next_id += 1
        self._send(
            {"jsonrpc": "2.0", "id": request_id, "method": method, "params": params}
        )
        selector = selectors.DefaultSelector()
        selector.register(self.process.stdout, selectors.EVENT_READ)
        try:
            while True:
                message = self._read_message(selector)
                # Codex app-server responses may omit this optional member.
                if "jsonrpc" in message and message["jsonrpc"] != "2.0":
                    raise ProcessUnavailable("malformed app-server response")
                if "method" in message and "id" in message:
                    raise ProcessUnavailable("unexpected app-server request")
                if "method" in message:
                    continue
                if message.get("id") != request_id:
                    continue
                if "error" in message:
                    raise ProcessUnavailable("app-server returned an error")
                allowed = {"id", "result", "jsonrpc"}
                if "result" not in message or set(message) - allowed:
                    raise ProcessUnavailable("malformed app-server response")
                return message["result"]
        finally:
            selector.close()

    def close(self) -> None:
        """Terminate this connection and remove its private working directory."""
        if self._closed:
            return
        self._closed = True
        try:
            terminate_owned(self.process)
        finally:
            if self.on_close is not None:
                self.on_close()


def run_owned(argv: Sequence[str], *, deadline_at: float) -> int:
    """Run one child group until the shared monotonic deadline or a signal."""
    try:
        process = subprocess.Popen(list(argv), start_new_session=True)
    except OSError as exc:
        raise ProcessUnavailable("cannot start owned process") from exc

    interrupted: int | None = None

    def handle_signal(signum: int, _frame: Any) -> None:
        nonlocal interrupted
        interrupted = signum
        terminate_owned(process)

    previous = {
        sig: signal.signal(sig, handle_signal)
        for sig in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM)
    }
    try:
        next_heartbeat = time.monotonic() + HEARTBEAT_SECONDS
        while True:
            if interrupted is not None:
                return 128 + interrupted
            result = process.poll()
            if result is not None:
                # Remove descendants that outlived the process-group leader.
                _signal_group(process, signal.SIGKILL)
                return result
            now = time.monotonic()
            if now >= deadline_at:
                terminate_owned(process)
                return 124
            if now >= next_heartbeat:
                print(
                    "ADVISOR TRANSPORT: owned child invocation still running",
                    file=sys.stderr,
                    flush=True,
                )
                next_heartbeat = now + HEARTBEAT_SECONDS
            time.sleep(min(0.1, max(0.0, deadline_at - now)))
    finally:
        for sig, handler in previous.items():
            signal.signal(sig, handler)
        if process.poll() is None:
            terminate_owned(process)


def capture_stdin(path: str, *, deadline_at: float) -> int:
    """Capture bounded stdin bytes without allowing a partial line to hang."""
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    try:
        output = os.open(path, flags, 0o600)
    except OSError as exc:
        raise ProcessUnavailable("cannot create packet capture") from exc
    total = 0
    input_is_regular = stat.S_ISREG(os.fstat(sys.stdin.fileno()).st_mode)
    selector = selectors.DefaultSelector()
    if not input_is_regular:
        selector.register(sys.stdin.buffer, selectors.EVENT_READ)
    next_heartbeat = time.monotonic() + HEARTBEAT_SECONDS
    try:
        os.set_blocking(sys.stdin.fileno(), False)
        while True:
            now = time.monotonic()
            if now >= deadline_at:
                return 124
            events = (
                [True]
                if input_is_regular
                else selector.select(
                    min(deadline_at - now, max(0.0, next_heartbeat - now))
                )
            )
            now = time.monotonic()
            if now >= next_heartbeat:
                print(
                    "ADVISOR TRANSPORT: waiting for decision packet",
                    file=sys.stderr,
                    flush=True,
                )
                next_heartbeat = now + HEARTBEAT_SECONDS
            if not events:
                continue
            while True:
                try:
                    chunk = os.read(sys.stdin.fileno(), 65536)
                except BlockingIOError:
                    break
                if not chunk:
                    return 0
                total += len(chunk)
                if total > MAX_PACKET_BYTES:
                    raise ProcessUnavailable("decision packet exceeds byte limit")
                os.write(output, chunk)
                if input_is_regular:
                    break
    finally:
        selector.close()
        os.close(output)


def _json_depth(value: Any, depth: int = 0) -> int:
    if depth > MAX_JSON_DEPTH:
        raise ProcessUnavailable("usage evidence nesting limit exceeded")
    if isinstance(value, dict):
        return max(
            (_json_depth(item, depth + 1) for item in value.values()), default=depth
        )
    if isinstance(value, list):
        return max((_json_depth(item, depth + 1) for item in value), default=depth)
    return depth


def usage_from_events(path: str, *, duration_ms: int) -> dict[str, Any]:
    """Extract only documented token counters from bounded structured events."""
    aliases = {
        "input": ("input_tokens", "input"),
        "cached_input": ("cached_input_tokens", "cached_input"),
        "output": ("output_tokens", "output"),
        "reasoning": ("reasoning_output_tokens", "reasoning_tokens", "reasoning"),
    }
    counters: dict[str, int | None] = {name: None for name in aliases}
    reasons = {name: "counter_absent" for name in counters}
    evidence: dict[int, list[dict[str, int | None]]] = {1: [], 2: []}
    try:
        info = os.stat(path)
        if info.st_size > MAX_PACKET_BYTES:
            raise ProcessUnavailable("usage evidence exceeds byte limit")
        with open(path, "rb") as handle:
            for raw in handle:
                if len(raw) > MAX_LINE_BYTES:
                    raise ProcessUnavailable("usage evidence line exceeds byte limit")
                try:
                    event = json.loads(raw)
                except (UnicodeDecodeError, json.JSONDecodeError) as exc:
                    raise ProcessUnavailable("malformed usage evidence") from exc
                _json_depth(event)
                if not isinstance(event, dict):
                    continue
                payload = event.get("payload")
                info_value = payload.get("info") if isinstance(payload, dict) else None
                retained = (
                    info_value.get("total_token_usage")
                    if isinstance(info_value, dict)
                    else None
                )
                completed = (
                    event.get("usage")
                    if event.get("type") == "turn.completed"
                    else None
                )
                for priority, usage in ((1, retained), (2, completed)):
                    if usage is None:
                        continue
                    if not isinstance(usage, dict):
                        raise ProcessUnavailable("malformed usage evidence")
                    row: dict[str, int | None] = {}
                    for target, names in aliases.items():
                        values = [usage[name] for name in names if name in usage]
                        if any(
                            not isinstance(value, int)
                            or isinstance(value, bool)
                            or value < 0
                            for value in values
                        ):
                            raise ProcessUnavailable("malformed usage evidence")
                        if len(set(values)) > 1:
                            raise ProcessUnavailable("conflicting usage evidence")
                        row[target] = values[0] if values else None
                    evidence[priority].append(row)
    except OSError as exc:
        raise ProcessUnavailable("usage evidence unavailable") from exc
    rows = evidence[2] or evidence[1]
    for target in aliases:
        values = [row[target] for row in rows if row[target] is not None]
        if len(set(values)) > 1:
            raise ProcessUnavailable("conflicting usage evidence")
        if values:
            counters[target] = values[0]
            reasons[target] = "available"
    return {
        "duration_ms": max(0, duration_ms),
        "usage": counters,
        "availability": reasons,
    }


def usage_main(argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(prog="advisor_process.py usage")
    parser.add_argument("--events", required=True)
    parser.add_argument("--duration-ms", type=int, required=True)
    args = parser.parse_args(argv)
    if args.duration_ms < 0:
        parser.error("--duration-ms must be non-negative")
    print(
        json.dumps(
            usage_from_events(args.events, duration_ms=args.duration_ms),
            sort_keys=True,
            separators=(",", ":"),
        )
    )
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    """Run the process-supervisor command-line interface."""
    argv = list(sys.argv[1:] if argv is None else argv)
    if argv and argv[0] == "usage":
        try:
            return usage_main(argv[1:])
        except ProcessUnavailable as exc:
            print(f"ADVISOR TRANSPORT: unavailable ({exc})", file=sys.stderr)
            return 1
    parser = argparse.ArgumentParser(prog="advisor_process.py")
    parser.add_argument("--deadline-at", type=float, required=True)
    parser.add_argument("--capture-to")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    command = list(args.command)
    while command and command[0] == "--":
        command.pop(0)
    if args.capture_to and command:
        parser.error("--capture-to cannot be combined with COMMAND")
    if not args.capture_to and not command:
        parser.error("expected -- COMMAND")
    try:
        if args.capture_to:
            return capture_stdin(args.capture_to, deadline_at=args.deadline_at)
        return run_owned(command, deadline_at=args.deadline_at)
    except ProcessUnavailable as exc:
        print(f"ADVISOR TRANSPORT: unavailable ({exc})", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
