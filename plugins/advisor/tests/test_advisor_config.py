"""Behavior tests for the local Advisor configuration foundation."""

from __future__ import annotations

import importlib.util
import io
import json
import os
import signal
import stat
import subprocess
import tempfile
import threading
import time
import unittest
from contextlib import redirect_stderr
from pathlib import Path


MODULE = Path(__file__).resolve().parents[1] / "scripts" / "advisor_config.py"
SPEC = importlib.util.spec_from_file_location("advisor_config", MODULE)
assert SPEC and SPEC.loader
config = importlib.util.module_from_spec(SPEC)
import sys

sys.modules[SPEC.name] = config
SPEC.loader.exec_module(config)


class AdvisorConfigTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.codex_home = Path(self.tmp.name) / "codex"
        self.codex_home.mkdir(mode=0o700)
        self.paths = config.state_paths(self.codex_home)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_defaults_are_read_only_and_do_not_initialize_state(self) -> None:
        self.assertEqual(
            config.load_settings(self.paths)["selections"]["standard"],
            {"model": "gpt-5.6-terra", "effort": "high"},
        )
        self.assertFalse(self.paths.root.exists())

    def test_invalid_json_duplicate_and_unknown_settings_fail_closed(self) -> None:
        self.paths.root.mkdir(mode=0o700)
        self.paths.settings.write_text(
            '{"schema_version":1,"schema_version":1}', encoding="utf-8"
        )
        os.chmod(self.paths.settings, 0o600)
        with self.assertRaises(config.ConfigError):
            config.load_settings(self.paths)
        bad = config.baseline_settings()
        bad["unexpected"] = True
        with self.assertRaises(config.ConfigError):
            config.validate_settings(bad)

    def test_json_null_and_boolean_schema_version_do_not_become_defaults(self) -> None:
        self.paths.root.mkdir(mode=0o700)
        self.paths.settings.write_text("null\n", encoding="utf-8")
        os.chmod(self.paths.settings, 0o600)
        with self.assertRaises(config.ConfigError):
            config.load_settings(self.paths)
        boolean = config.baseline_settings()
        boolean["schema_version"] = True
        with self.assertRaises(config.ConfigError):
            config.validate_settings(boolean)

    def test_symlink_and_permissive_paths_are_rejected(self) -> None:
        self.paths.root.mkdir(mode=0o700)
        target = Path(self.tmp.name) / "target.json"
        target.write_text("{}", encoding="utf-8")
        os.chmod(target, 0o600)
        self.paths.settings.symlink_to(target)
        with self.assertRaises(config.ConfigError):
            config.load_settings(self.paths)
        self.paths.settings.unlink()
        os.chmod(self.paths.root, 0o755)
        with self.assertRaises(config.ConfigError):
            config.load_catalog(self.paths)

    def test_revision_guards_concurrent_writers(self) -> None:
        initial = config.baseline_settings()
        first = config.save_settings(initial, expected_revision=0, paths=self.paths)
        self.assertEqual(first["revision"], 1)
        outcomes: list[object] = []

        def writer() -> None:
            try:
                outcomes.append(
                    config.save_settings(first, expected_revision=1, paths=self.paths)[
                        "revision"
                    ]
                )
            except Exception as exc:  # expected for one writer
                outcomes.append(exc)

        threads = [threading.Thread(target=writer) for _ in range(2)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        self.assertEqual(sum(item == 2 for item in outcomes), 1)
        self.assertEqual(
            sum(isinstance(item, config.RevisionConflict) for item in outcomes), 1
        )
        self.assertEqual(stat.S_IMODE(self.paths.root.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(self.paths.settings.stat().st_mode), 0o600)

    def test_future_selector_is_a_candidate_not_a_tier_or_compatibility(self) -> None:
        future = "future/provider-model_2049:beta"
        catalog = config.add_manual_candidate(future, paths=self.paths)
        item = catalog["candidates"][0]
        self.assertEqual(item["model"], future)
        self.assertEqual(item["provenance"], "manual")
        self.assertEqual(catalog["compatibility"], [])

    def test_compatibility_binds_pair_and_transport_not_cli_provenance(self) -> None:
        version = "codex-cli 0.153.2"
        receipt = config.validate_compatibility(
            {
                "model": "future/x",
                "effort": "high",
                "codex_version": version,
                "transport_contract_version": "1.4",
                "verified_at": "1",
            }
        )
        self.assertTrue(
            config.compatibility_is_current(
                receipt, model="future/x", effort="high"
            )
        )
        self.assertFalse(
            config.compatibility_is_current(
                receipt, model="future/x", effort="medium"
            )
        )
        self.assertTrue(
            config.shipped_default_launch_eligible(
                tier="standard", model="gpt-5.6-terra", effort="high"
            )
        )
        self.assertFalse(
            config.shipped_default_launch_eligible(
                tier="standard", model="gpt-6-astra", effort="high"
            )
        )

    def test_pristine_defaults_resolve_without_cli_probe_or_state(self) -> None:
        original = config.current_codex_version
        config.current_codex_version = lambda: (_ for _ in ()).throw(AssertionError())
        try:
            standard = config.resolve_selection("standard", paths=self.paths)
            specialist = config.resolve_selection("specialist", paths=self.paths)
        finally:
            config.current_codex_version = original
        self.assertEqual(
            (standard["model"], standard["effort"]), ("gpt-5.6-terra", "high")
        )
        self.assertEqual(
            (specialist["model"], specialist["effort"]), ("gpt-5.6-sol", "high")
        )
        self.assertFalse(self.paths.root.exists())

    def test_shipped_catalog_rejects_malformed_defaults_and_baselines(self) -> None:
        shipped = config.load_shipped_models()
        malformed = json.loads(json.dumps(shipped))
        malformed["defaults"]["standard"]["model"] = "gpt-6-astra"
        with self.assertRaises(config.ConfigError):
            config.validate_shipped_models(malformed)
        malformed = json.loads(json.dumps(shipped))
        malformed["models"].append(dict(malformed["models"][0]))
        with self.assertRaises(config.ConfigError):
            config.validate_shipped_models(malformed)
        malformed = json.loads(json.dumps(shipped))
        malformed["models"][0]["compatibility_baseline"]["efforts"] = [["high"]]
        with self.assertRaises(config.ConfigError):
            config.validate_shipped_models(malformed)

    def test_explicit_routes_fail_closed_when_transport_evidence_stales(self) -> None:
        pair = {"model": "future/model", "effort": "high"}
        config.add_manual_candidate(pair["model"], paths=self.paths)
        config.record_compatibility(
            pair, codex_version="codex-cli 0.153.2", paths=self.paths
        )
        config.set_selection("standard", pair, paths=self.paths)
        config.save_preset("future", pair, paths=self.paths)
        catalog = config.load_catalog(self.paths)
        catalog["compatibility"][0]["transport_contract_version"] = "1.3"
        self.paths.catalog.write_text(json.dumps(catalog) + "\n", encoding="utf-8")
        os.chmod(self.paths.catalog, 0o600)
        resolved = config.resolve_selection("standard", paths=self.paths)
        self.assertEqual(
            resolved["model"], "gpt-5.6-terra",
            "normal tiers must ignore stale saved selections",
        )
        with self.assertRaises(config.ConfigError):
            config.resolve_selection("standard", preset="future", paths=self.paths)

    def test_live_config_requires_exact_safe_toml_and_accepts_future_selector(self) -> None:
        original = config.live_config_path
        candidate = Path(self.tmp.name) / "advisor.toml"
        config.live_config_path = lambda: candidate
        try:
            candidate.write_text(
                "[standard]\nmodel = \"future/provider-2049\"\neffort = \"max\"\n"
                "[specialist]\nmodel = \"gpt-6-astra\"\neffort = \"high\"\n"
            )
            live = config.load_live_config()
            self.assertEqual(live["pairs"]["standard"], {"model": "future/provider-2049", "effort": "max"})
            self.assertTrue(live["source_revision"].startswith("sha256:"))
            candidate.write_text("[standard]\nmodel = \"a\"\neffort = \"high\"\n")
            with self.assertRaisesRegex(config.ConfigError, "advisor.toml"):
                config.load_live_config()
            candidate.write_text(
                "[standard]\nmodel = \"a\"\neffort = \"bad\"\n"
                "[specialist]\nmodel = \"b\"\neffort = \"high\"\n"
            )
            with self.assertRaisesRegex(config.ConfigError, "advisor.toml"):
                config.load_live_config()
            candidate.unlink()
            candidate.symlink_to(Path(self.tmp.name) / "target")
            with self.assertRaisesRegex(config.ConfigError, "advisor.toml"):
                config.load_live_config()
        finally:
            config.live_config_path = original

    def test_live_config_opens_nofollow_and_rejects_nonregular_files_without_blocking(self) -> None:
        original_path = config.live_config_path
        original_open = config.os.open
        candidate = Path(self.tmp.name) / "advisor.toml"
        target = Path(self.tmp.name) / "target.toml"
        target.write_text(
            '[standard]\nmodel = "gpt-5.6-terra"\neffort = "high"\n'
            '[specialist]\nmodel = "gpt-5.6-sol"\neffort = "high"\n',
            encoding="utf-8",
        )
        candidate.write_bytes(target.read_bytes())
        config.live_config_path = lambda: candidate

        def replace_before_open(path: Path, flags: int) -> int:
            candidate.unlink()
            candidate.symlink_to(target)
            config.os.open = original_open
            return original_open(path, flags)

        try:
            config.os.open = replace_before_open
            with self.assertRaisesRegex(config.ConfigError, "advisor.toml"):
                config.load_live_config()
            candidate.unlink()
            os.mkfifo(candidate)
            started = time.monotonic()
            with self.assertRaisesRegex(config.ConfigError, "regular file"):
                config.load_live_config()
            self.assertLess(time.monotonic() - started, 1.0)
        finally:
            config.os.open = original_open
            config.live_config_path = original_path

    def test_live_config_caps_a_file_that_grows_after_open(self) -> None:
        original_path = config.live_config_path
        original_read = config.os.read
        candidate = Path(self.tmp.name) / "advisor.toml"
        candidate.write_text(
            '[standard]\nmodel = "gpt-5.6-terra"\neffort = "high"\n'
            '[specialist]\nmodel = "gpt-5.6-sol"\neffort = "high"\n',
            encoding="utf-8",
        )
        config.live_config_path = lambda: candidate
        delivered = 0

        def growing_read(descriptor: int, count: int) -> bytes:
            nonlocal delivered
            self.assertLessEqual(count, config.MAX_LIVE_CONFIG_BYTES + 1 - delivered)
            chunk = b"x" * count
            delivered += len(chunk)
            return chunk

        try:
            config.os.read = growing_read
            with self.assertRaisesRegex(config.ConfigError, "too large"):
                config.load_live_config()
            self.assertEqual(delivered, config.MAX_LIVE_CONFIG_BYTES + 1)
        finally:
            config.os.read = original_read
            config.live_config_path = original_path

    def test_reset_only_restores_selections(self) -> None:
        settings = config.baseline_settings()
        settings["selections"]["standard"] = {"model": "custom/future", "effort": "max"}
        settings["presets"] = {"one": {"model": "custom/future", "effort": "max"}}
        settings["deadline_seconds"] = 120
        config.save_settings(settings, expected_revision=0, paths=self.paths)
        reset = config.reset_selections(paths=self.paths)
        self.assertEqual(reset["selections"], config.baseline_settings()["selections"])
        self.assertEqual(reset["presets"]["one"]["model"], "custom/future")
        self.assertEqual(reset["deadline_seconds"], 120)

    def test_settings_mutations_keep_one_explicit_prior_revision(self) -> None:
        initial = config.save_settings(
            config.baseline_settings(), expected_revision=0, paths=self.paths
        )
        updated = config.set_deadline(120, paths=self.paths)
        self.assertEqual(updated["deadline_seconds"], 120)
        prior = config.validate_settings(config.read_json(self.paths.prior_settings))
        self.assertEqual(prior["revision"], initial["revision"])
        self.assertEqual(prior["deadline_seconds"], 300)
        restored = config.restore_prior_settings(paths=self.paths)
        self.assertEqual(restored["deadline_seconds"], 300)
        self.assertGreater(restored["revision"], updated["revision"])

    def test_failed_settings_write_preserves_active_and_distinct_prior_bytes(
        self,
    ) -> None:
        initial = config.save_settings(
            config.baseline_settings(), expected_revision=0, paths=self.paths
        )
        config.set_deadline(120, paths=self.paths)
        active_bytes = self.paths.settings.read_bytes()
        prior_bytes = self.paths.prior_settings.read_bytes()
        self.assertNotEqual(active_bytes, prior_bytes)
        original = config._atomic_write

        def fail_settings(path: Path, value: object) -> None:
            if path == self.paths.settings:
                raise OSError("simulated write failure")
            original(path, value)

        config._atomic_write = fail_settings
        try:
            with self.assertRaises(OSError):
                config.set_deadline(120, paths=self.paths)
        finally:
            config._atomic_write = original
        self.assertEqual(self.paths.settings.read_bytes(), active_bytes)
        self.assertEqual(self.paths.prior_settings.read_bytes(), prior_bytes)
        self.assertFalse(list(self.paths.root.glob(".*.tmp")))

    def test_explicit_restore_recovers_invalid_active_and_preserves_its_bytes(
        self,
    ) -> None:
        initial = config.save_settings(
            config.baseline_settings(), expected_revision=0, paths=self.paths
        )
        config.set_deadline(120, paths=self.paths)
        malformed = b'{"schema_version":1,"nested":' + b"[" * 1000
        self.paths.settings.write_bytes(malformed)
        os.chmod(self.paths.settings, 0o600)
        restored = config.restore_prior_settings(paths=self.paths)
        self.assertEqual(restored["deadline_seconds"], initial["deadline_seconds"])
        self.assertEqual(restored["revision"], initial["revision"] + 1)
        self.assertEqual(self.paths.invalid_settings.read_bytes(), malformed)
        self.assertEqual(stat.S_IMODE(self.paths.invalid_settings.stat().st_mode), 0o600)

    def test_restore_refuses_invalid_or_unsafe_backup(self) -> None:
        config.save_settings(config.baseline_settings(), expected_revision=0, paths=self.paths)
        self.paths.settings.write_text("null\n", encoding="utf-8")
        self.paths.prior_settings.write_text("null\n", encoding="utf-8")
        with self.assertRaises(config.ConfigError):
            config.restore_prior_settings(paths=self.paths)
        self.paths.prior_settings.unlink()
        target = Path(self.tmp.name) / "prior-target"
        target.write_text("{}\n", encoding="utf-8")
        self.paths.prior_settings.symlink_to(target)
        with self.assertRaises(config.ConfigError):
            config.restore_prior_settings(paths=self.paths)

    def test_restore_refuses_to_downgrade_a_newer_settings_schema(self) -> None:
        config.save_settings(config.baseline_settings(), expected_revision=0, paths=self.paths)
        prior_bytes = self.paths.prior_settings.read_bytes()
        future = {"schema_version": 2, "revision": 9, "future": {"setting": True}}
        future_bytes = (json.dumps(future) + "\n").encode()
        self.paths.settings.write_bytes(future_bytes)
        os.chmod(self.paths.settings, 0o600)
        with self.assertRaisesRegex(config.ConfigError, "refuses to downgrade"):
            config.restore_prior_settings(paths=self.paths)
        self.assertEqual(self.paths.settings.read_bytes(), future_bytes)
        self.assertEqual(self.paths.prior_settings.read_bytes(), prior_bytes)
        self.assertFalse(self.paths.invalid_settings.exists())

    def test_canary_supervisor_cancellation_reaps_owned_group_only(self) -> None:
        wrapper = Path(self.tmp.name) / "canary-wrapper.sh"
        child_marker = Path(self.tmp.name) / "canary-child"
        terminated = Path(self.tmp.name) / "canary-terminated"
        wrapper.write_text(
            "#!/bin/sh\n"
            "trap 'printf terminated > \"$2\"; exit 143' TERM\n"
            "sleep 20 &\n"
            "printf '%s' \"$!\" > \"$1\"\n"
            "wait\n",
            encoding="utf-8",
        )
        wrapper.chmod(0o700)
        unrelated = subprocess.Popen(["sleep", "20"])
        timer = threading.Timer(1.0, os.kill, args=(os.getpid(), signal.SIGTERM))
        try:
            timer.start()
            with self.assertRaises(config.ConfigError):
                config._run_compatibility_wrapper(
                    [str(wrapper), str(child_marker), str(terminated)],
                    deadline_seconds=30,
                    on_status=None,
                )
            self.assertTrue(child_marker.exists())
            self.assertTrue(terminated.exists())
            self.assertIsNone(unrelated.poll())
        finally:
            timer.cancel()
            unrelated.terminate()
            unrelated.wait(timeout=3)

    def test_paginated_discovery_uses_model_not_id_and_keeps_hidden_rows(self) -> None:
        model = lambda ident, dispatch, hidden=False: {
            "id": ident,
            "model": dispatch,
            "displayName": ident,
            "description": "model",
            "hidden": hidden,
            "isDefault": False,
            "defaultReasoningEffort": "high",
            "supportedReasoningEfforts": [
                {"reasoningEffort": "high", "description": ""}
            ],
        }
        pages = [
            {"data": [model("marketing-name", "dispatch/one")], "nextCursor": "next"},
            {"data": [model("hidden-name", "dispatch/two", True)], "nextCursor": None},
        ]
        rows = config.normalize_discovery_pages(pages, now=lambda: 42)
        self.assertEqual(rows[0]["id"], "marketing-name")
        self.assertEqual(rows[0]["model"], "dispatch/one")
        self.assertFalse(rows[1]["visible"])
        self.assertEqual(rows[1]["model"], "dispatch/two")

    def test_discovery_requires_schema_fields_and_ignores_optional_metadata(
        self,
    ) -> None:
        model = {
            "id": "friendly",
            "model": "dispatch/model",
            "displayName": "Friendly",
            "description": "model",
            "hidden": False,
            "isDefault": True,
            "defaultReasoningEffort": "high",
            "supportedReasoningEfforts": [
                {"reasoningEffort": "high", "description": "default", "extra": 1}
            ],
            "serviceTiers": [],
        }
        rows = config.normalize_discovery_pages(
            [{"data": [model], "nextCursor": None, "optional": True}]
        )
        self.assertEqual(rows[0]["model"], "dispatch/model")
        del model["description"]
        with self.assertRaises(config.DiscoveryError):
            config.normalize_discovery_pages([{"data": [model], "nextCursor": None}])

    def test_models_lists_shipped_catalog_and_local_candidates(self) -> None:
        config.add_manual_candidate("future/model", paths=self.paths)
        env = {**os.environ, "CODEX_HOME": str(self.codex_home)}
        result = subprocess.run(
            [str(MODULE.parent / "advisor-config.sh"), "--json", "models"],
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )
        payload = json.loads(result.stdout)
        self.assertEqual(result.returncode, 0)
        self.assertIn(
            "gpt-6-astra", [item["model"] for item in payload["shipped"]["models"]]
        )
        self.assertEqual(payload["catalog"]["candidates"][0]["model"], "future/model")

    def test_discovery_rejects_loop_and_malformed_pages(self) -> None:
        with self.assertRaises(config.DiscoveryError):
            config.normalize_discovery_pages(
                [
                    {"data": [], "nextCursor": "again"},
                    {"data": [], "nextCursor": "again"},
                ]
            )
        with self.assertRaises(config.DiscoveryError):
            config.normalize_discovery_pages(
                [{"data": [{"id": "only-id"}], "nextCursor": None}]
            )

    def test_refresh_preserves_manual_and_marks_missing_discovery_hidden(self) -> None:
        config.add_manual_candidate("manual/future", paths=self.paths)
        model = {
            "id": "old",
            "model": "server/old",
            "displayName": "Old",
            "description": "model",
            "hidden": False,
            "isDefault": False,
            "defaultReasoningEffort": "high",
            "supportedReasoningEfforts": [
                {"reasoningEffort": "high", "description": ""}
            ],
        }
        config.refresh_catalog(
            lambda: [{"data": [model], "nextCursor": None}],
            paths=self.paths,
            now=lambda: 10,
        )
        updated = config.refresh_catalog(
            lambda: [{"data": [], "nextCursor": None}], paths=self.paths, now=lambda: 20
        )
        self.assertEqual(updated["candidates"][0]["model"], "manual/future")
        old = next(row for row in updated["candidates"] if row["model"] == "server/old")
        self.assertFalse(old["visible"])

    def test_offline_adapter_is_closed_and_does_not_mutate_catalog(self) -> None:
        before = config.load_catalog(self.paths)
        with self.assertRaises(config.DiscoveryUnavailable):
            config.AppServerDiscovery(
                lambda: (_ for _ in ()).throw(config.ProcessUnavailable("offline"))
            ).pages()
        self.assertEqual(config.load_catalog(self.paths), before)

    def test_adapter_paginates_and_closes_its_owned_connection(self) -> None:
        class Connection:
            def __init__(self) -> None:
                self.calls, self.closed = [], False

            def request(self, method, payload):
                self.calls.append((method, payload))
                if method == "initialize":
                    return {"serverInfo": {}}
                model = lambda ident: {
                    "id": ident,
                    "model": ident,
                    "displayName": ident,
                    "description": "model",
                    "hidden": False,
                    "isDefault": False,
                    "defaultReasoningEffort": "high",
                    "supportedReasoningEfforts": [
                        {"reasoningEffort": "high", "description": ""}
                    ],
                }
                return (
                    {"data": [model("a")], "nextCursor": "c"}
                    if "cursor" not in payload
                    else {"data": [model("b")], "nextCursor": None}
                )

            def notify(self, method, payload):
                self.calls.append((method, payload))

            def close(self):
                self.closed = True

        connection = Connection()
        pages = config.AppServerDiscovery(lambda: connection).pages()
        self.assertEqual(len(pages), 2)
        self.assertTrue(connection.closed)
        self.assertEqual(connection.calls[0][0], "initialize")
        self.assertEqual(connection.calls[0][1]["clientInfo"]["name"], "codex-advisor")
        self.assertEqual(connection.calls[1][0], "initialized")

    def test_cli_refresh_emits_progress_and_never_invokes_inference(self) -> None:
        fake_bin = Path(self.tmp.name) / "bin"
        fake_bin.mkdir()
        fake = fake_bin / "codex"
        fake.write_text("#!/bin/sh\nexit 1\n", encoding="utf-8")
        fake.chmod(0o700)
        env = {
            **os.environ,
            "CODEX_HOME": str(self.codex_home),
            "PATH": f"{fake_bin}:{os.environ['PATH']}",
        }
        result = subprocess.run(
            [str(MODULE.parent / "advisor-config.sh"), "--json", "models", "refresh"],
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("discovery started", result.stderr)
        self.assertEqual(json.loads(result.stdout)["status"], "unavailable")
        self.assertFalse(
            self.paths.root.exists(), "a failed read-only refresh must not create state"
        )


if __name__ == "__main__":
    unittest.main()
