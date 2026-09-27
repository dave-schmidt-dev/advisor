"""Bounded Advisor app-server model discovery."""

from __future__ import annotations

import os
import shutil
import tempfile
import time
from collections.abc import Callable, Mapping, Sequence
from typing import Any

from advisor_catalog import _validate_candidate, load_catalog, validate_catalog
from advisor_process import JsonRpcProcess, ProcessUnavailable
from advisor_state import (
    DEFAULT_DEADLINE_SECONDS,
    EFFORTS,
    MAX_DEADLINE_SECONDS,
    MAX_MODELS,
    MAX_PAGES,
    MIN_DEADLINE_SECONDS,
    TRANSPORT_CONTRACT_VERSION,
    ConfigError,
    DiscoveryError,
    DiscoveryUnavailable,
    StatePaths,
    _atomic_write,
    _run_bounded_output,
    _validate_effort,
    _validate_selector,
    state_lock,
    state_paths,
)

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
