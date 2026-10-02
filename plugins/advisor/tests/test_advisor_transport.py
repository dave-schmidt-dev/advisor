"""Black-box coverage for configurable Advisor discovery and consultation transport."""

from __future__ import annotations

import hashlib
import json
import shutil
import signal
import subprocess
import sys
import time
import unittest

if __package__:
    from .advisor_transport_support import (
        FAKE_OLD_PYTHON,
        HELPERS,
        PACKET,
        PARENT,
        AdvisorTransportTestCase,
        config,
    )
else:
    from advisor_transport_support import (
        FAKE_OLD_PYTHON,
        HELPERS,
        PACKET,
        PARENT,
        AdvisorTransportTestCase,
        config,
    )


class AdvisorTransportTests(AdvisorTransportTestCase):

    def test_symlinked_helpers_are_rejected_before_codex_launch(self) -> None:
        for helper in HELPERS:
            with self.subTest(helper=helper):
                helper_path = self.plugin_root / "scripts" / helper
                backup = self.root / helper
                shutil.copy2(helper_path, backup)
                helper_path.unlink()
                try:
                    helper_path.symlink_to(backup)
                    result = self.run_transport("--tier", "standard")
                    self.assertEqual(result.returncode, 1, result.stderr)
                    self.assertIn("installed Advisor helper is unsafe", result.stderr)
                    self.assertEqual(self.rows(), [])
                finally:
                    helper_path.unlink(missing_ok=True)
                    shutil.copy2(backup, helper_path)
                    backup.unlink()

    def test_old_python_is_rejected_before_helpers_capture_or_launch(self) -> None:
        fake_python = self.bin / "python3"
        fake_python.write_text(
            FAKE_OLD_PYTHON.replace("{interpreter}", sys.executable),
            encoding="utf-8",
        )
        fake_python.chmod(0o700)
        python_invocations = self.root / "python-invocations.jsonl"
        result = self.run_transport(
            "--tier",
            "standard",
            env={"FAKE_PYTHON_INVOCATIONS": str(python_invocations)},
        )
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("ADVISOR TRANSPORT: unavailable", result.stderr)
        self.assertIn("Python 3.11+", result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        self.assertEqual(self.rows(), [])
        self.assertFalse((self.home / ".tmp" / "advisor-transport").exists())
        calls = [
            json.loads(line) for line in python_invocations.read_text().splitlines()
        ]
        self.assertEqual(
            len(calls), 1, "the version preflight must be the only python3 call"
        )

    def test_discovery_accepts_protocol_without_jsonrpc_and_ignores_optional_fields(
        self,
    ) -> None:
        result = subprocess.run(
            [str(self.config_wrapper), "--json", "models", "refresh"],
            text=True,
            capture_output=True,
            check=False,
            env=self.env,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        candidate = json.loads(result.stdout)["catalog"]["candidates"][0]
        self.assertEqual(candidate["model"], "provider/model")
        self.assertEqual(candidate["advertised_efforts"], ["high"])

    def test_discovery_is_safely_unavailable_when_cli_cannot_ignore_config(
        self,
    ) -> None:
        result = subprocess.run(
            [str(self.config_wrapper), "--json", "models", "refresh"],
            text=True,
            capture_output=True,
            check=False,
            env={**self.env, "FAKE_DISCOVERY_UNSUPPORTED": "1"},
        )
        self.assertEqual(result.returncode, 2)
        self.assertFalse(self.paths.root.exists())

    def test_live_tiers_ignore_stale_saved_selections_and_legacy_roles_remain_fixed(self) -> None:
        standard = self.run_transport("--tier", "standard")
        specialist = self.run_transport("--tier", "specialist")
        self.assertEqual((standard.returncode, specialist.returncode), (0, 0))
        self.qualify("gpt-6-astra")
        settings = config.load_settings(self.paths)
        settings["selections"]["standard"] = {"model": "gpt-6-astra", "effort": "high"}
        config.save_settings(
            settings, expected_revision=settings["revision"], paths=self.paths
        )
        configured = self.run_transport("--tier", "standard")
        legacy = self.run_transport("--role", "advisor-terra")
        self.assertEqual(configured.returncode, 0, configured.stderr)
        self.assertEqual(legacy.returncode, 0, legacy.stderr)
        self.assertEqual(
            [(row["model"], row["effort"]) for row in self.rows()],
            [
                ("gpt-5.6-terra", "high"),
                ("gpt-6.1-sol", "high"),
                ("gpt-5.6-terra", "high"),
                ("gpt-5.6-terra", "high"),
            ],
        )

    def test_configured_future_model_and_preset_do_not_change_default(self) -> None:
        self.qualify("future/model", "max")
        config.save_preset(
            "future",
            {"model": "future/model", "effort": "max"},
            paths=self.paths,
        )
        result = self.run_transport(
            "--tier", "standard", "--preset", "future",
            env={"FAKE_CODEX_VERSION": "codex-cli 0.154.0"},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        expected_revision = config.load_settings(self.paths)["revision"]
        selection = json.loads(result.stdout)["selection"]
        self.assertEqual(selection["revision"], expected_revision)
        self.assertEqual(selection["source_revision"], f"legacy-settings:{expected_revision}")
        self.assertEqual(
            (self.rows()[0]["model"], self.rows()[0]["effort"]), ("future/model", "max")
        )
        self.assertEqual(
            config.load_settings(self.paths)["selections"]["standard"]["model"],
            "gpt-5.6-terra",
        )
        failed = self.run_transport(
            "--tier", "standard", "--preset", "future", case="wrong-model"
        )
        self.assertNotEqual(failed.returncode, 0)
        failed_selection = json.loads(failed.stdout)["selection"]
        self.assertEqual(failed_selection["revision"], expected_revision)
        self.assertEqual(
            failed_selection["source_revision"], f"legacy-settings:{expected_revision}"
        )

    def test_live_astra_and_independent_effort_launch_without_catalog_or_state(self) -> None:
        with self.live_config(
            {"model": "gpt-6-astra", "effort": "max"},
            {"model": "gpt-6.1-sol", "effort": "low"},
        ):
            standard = self.run_transport("--tier", "standard")
            specialist = self.run_transport("--tier", "specialist")
        self.assertEqual((standard.returncode, specialist.returncode), (0, 0))
        self.assertEqual(
            [(row["model"], row["effort"]) for row in self.rows()],
            [("gpt-6-astra", "max"), ("gpt-6.1-sol", "low")],
        )
        self.assertFalse(self.paths.root.exists(), "live config must not create state")
        selection = json.loads(standard.stdout)["selection"]
        self.assertEqual(selection["source"], "live-config")
        self.assertTrue(selection["source_revision"].startswith("sha256:"))

    def test_live_future_selector_needs_no_catalog_or_canary_and_invalid_toml_launches_nothing(self) -> None:
        with self.live_config(
            {"model": "future/provider-2049", "effort": "ultra"},
            {"model": "gpt-6.1-sol", "effort": "high"},
        ):
            future = self.run_transport("--tier", "standard")
        self.assertEqual(future.returncode, 0, future.stderr)
        self.assertEqual(self.rows()[0]["model"], "future/provider-2049")
        self.live_config_path.write_text(
            "[standard]\nmodel = \"bad\"\neffort = \"high\"\n"
        )
        invalid = self.run_transport("--tier", "standard")
        self.assertNotEqual(invalid.returncode, 0)
        self.assertIn("advisor.toml", invalid.stderr)
        self.assertEqual(len(self.rows()), 1, "invalid config must fail before child launch")
        self.live_config_path.write_text(
            '[standard]\nmodel = "bad selector!"\neffort = "high"\n\n'
            '[specialist]\nmodel = "gpt-6.1-sol"\neffort = "high"\n'
        )
        invalid_selector = self.run_transport("--tier", "standard")
        self.assertNotEqual(invalid_selector.returncode, 0)
        self.assertIn("advisor.toml", invalid_selector.stderr)
        self.assertEqual(len(self.rows()), 1, "invalid selector must fail before child launch")

    def test_saved_selection_is_ignored_and_mixed_route_is_rejected(self) -> None:
        config.add_manual_candidate("future/model", paths=self.paths)
        settings = config.baseline_settings()
        settings["selections"]["standard"] = {"model": "future/model", "effort": "max"}
        config.save_settings(settings, expected_revision=0, paths=self.paths)
        unqualified = self.run_transport("--tier", "standard")
        mixed = self.run_transport("--tier", "standard", "--role", "advisor-terra")
        self.assertEqual(unqualified.returncode, 0, unqualified.stderr)
        self.assertNotEqual(mixed.returncode, 0)
        self.assertEqual(
            [(row["model"], row["effort"]) for row in self.rows()],
            [("gpt-5.6-terra", "high")],
        )

    def test_cli_version_change_does_not_replace_live_tier_before_launch(self) -> None:
        self.qualify("future/model")
        settings = config.load_settings(self.paths)
        settings["selections"]["standard"] = {
            "model": "future/model",
            "effort": "high",
        }
        config.save_settings(
            settings, expected_revision=settings["revision"], paths=self.paths
        )
        result = subprocess.run(
            [
                "/bin/sh",
                str(self.transport),
                "--tier",
                "standard",
                "--parent-thread",
                PARENT,
                "--sessions-dir",
                str(self.home / "sessions"),
            ],
            input=PACKET,
            text=True,
            capture_output=True,
            check=False,
            env={**self.env, "FAKE_CODEX_VERSION": "codex-cli 0.154.0"},
            timeout=5,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            [(row["model"], row["effort"]) for row in self.rows()],
            [("gpt-5.6-terra", "high")],
        )

    def test_pristine_defaults_launch_on_newer_cli_without_state_or_canary(self) -> None:
        result = subprocess.run(
            [
                "/bin/sh",
                str(self.transport),
                "--tier",
                "standard",
                "--parent-thread",
                PARENT,
                "--sessions-dir",
                str(self.home / "sessions"),
            ],
            input=PACKET,
            text=True,
            capture_output=True,
            check=False,
            env={**self.env, "FAKE_CODEX_VERSION": "codex-cli 0.153.4"},
            timeout=5,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.rows()[0]["model"], "gpt-5.6-terra")
        self.assertFalse(self.paths.root.exists())

    def test_default_runtime_mismatch_still_rejects_actual_consultation(self) -> None:
        result = self.run_transport("--tier", "standard", case="wrong-model")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(self.rows()), 1)

    def test_authorized_canary_records_exact_cli_pair_without_selecting_it(
        self,
    ) -> None:
        config.add_manual_candidate("future/model", paths=self.paths)
        result = subprocess.run(
            [
                str(self.config_wrapper),
                "--json",
                "models",
                "test",
                "future/model",
                "--effort",
                "max",
                "--authorize-usage",
                "--parent-thread",
                PARENT,
                "--sessions-dir",
                str(self.home / "sessions"),
            ],
            text=True,
            capture_output=True,
            check=False,
            env=self.env,
            timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        receipt = config.load_catalog(self.paths)["compatibility"][0]
        self.assertEqual(
            (receipt["model"], receipt["effort"], receipt["codex_version"]),
            ("future/model", "max", "codex-cli 0.153.2"),
        )
        self.assertEqual(
            config.load_settings(self.paths)["selections"],
            config.baseline_settings()["selections"],
        )
        self.assertIn("content-free transport canary", self.rows()[0]["prompt"])

    def test_retry_freezes_live_pair_and_digest_then_next_consult_reloads(self) -> None:
        original_digest = hashlib.sha256(self.live_config_path.read_bytes()).hexdigest()
        result = self.run_transport("--tier", "standard", case="mutate-retry")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            [(row["model"], row["effort"]) for row in self.rows()],
            [("gpt-5.6-terra", "high"), ("gpt-5.6-terra", "high")],
        )
        self.assertEqual(
            json.loads(result.stdout)["selection"]["source_revision"],
            f"sha256:{original_digest}",
        )
        self.assertEqual(len(self.rows()), 2)
        next_result = self.run_transport("--tier", "standard")
        self.assertEqual(next_result.returncode, 0, next_result.stderr)
        self.assertEqual(
            (self.rows()[2]["model"], self.rows()[2]["effort"]),
            ("gpt-6.1-sol", "ultra"),
        )
        self.assertNotEqual(
            json.loads(next_result.stdout)["selection"]["source_revision"],
            f"sha256:{original_digest}",
        )

    def test_runtime_mismatch_reroute_and_tool_use_are_terminal(self) -> None:
        for case in ("wrong-model", "wrong-effort", "reroute", "tool"):
            self.invocations.unlink(missing_ok=True)
            result = self.run_transport("--role", "advisor-terra", case=case)
            self.assertNotEqual(result.returncode, 0, case)
            self.assertEqual(len(self.rows()), 1, case)

    def test_term_reaps_owned_group_cleans_private_state_and_spares_unrelated(
        self,
    ) -> None:
        unrelated = subprocess.Popen(["sleep", "20"])
        ready = self.root / "ready"
        terminated = self.root / "terminated"
        process = subprocess.Popen(
            [
                "/bin/sh",
                str(self.transport),
                "--role",
                "advisor-terra",
                "--parent-thread",
                PARENT,
                "--sessions-dir",
                str(self.home / "sessions"),
            ],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env={
                **self.env,
                "FAKE_CASE": "hang",
                "FAKE_READY_MARKER": str(ready),
                "FAKE_TERM_MARKER": str(terminated),
            },
        )
        assert process.stdin
        process.stdin.write(PACKET)
        process.stdin.close()
        try:
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                if ready.exists():
                    break
                time.sleep(0.05)
            self.assertTrue(ready.exists())
            process.send_signal(signal.SIGTERM)
            process.wait(timeout=6)
            assert process.stdout and process.stderr
            process.stdout.close()
            process.stderr.close()
            self.assertTrue(terminated.exists())
            transport_root = self.home / ".tmp" / "advisor-transport"
            self.assertFalse(any(transport_root.glob("run.*")))
            self.assertIsNone(unrelated.poll())
        finally:
            if process.poll() is None:
                process.kill()
            unrelated.terminate()
            unrelated.wait(timeout=3)

    def test_wrapper_total_deadline_terminates_child_and_cleans_private_state(
        self,
    ) -> None:
        settings = config.baseline_settings()
        settings["deadline_seconds"] = 30
        config.save_settings(settings, expected_revision=0, paths=self.paths)
        ready = self.root / "deadline-ready"
        terminated = self.root / "deadline-terminated"
        started = time.monotonic()
        result = subprocess.run(
            [
                "/bin/sh",
                str(self.transport),
                "--tier",
                "standard",
                "--parent-thread",
                PARENT,
                "--sessions-dir",
                str(self.home / "sessions"),
            ],
            input=PACKET,
            text=True,
            capture_output=True,
            check=False,
            env={
                **self.env,
                "FAKE_CASE": "hang",
                "FAKE_READY_MARKER": str(ready),
                "FAKE_TERM_MARKER": str(terminated),
            },
            timeout=36,
        )
        elapsed = time.monotonic() - started
        self.assertNotEqual(result.returncode, 0)
        self.assertGreaterEqual(elapsed, 28)
        self.assertLess(elapsed, 35)
        self.assertTrue(ready.exists())
        self.assertTrue(terminated.exists())
        transport_root = self.home / ".tmp" / "advisor-transport"
        self.assertFalse(any(transport_root.glob("run.*")))

    def test_cancel_while_waiting_for_packet_is_prompt_and_cleans_capture(self) -> None:
        process = subprocess.Popen(
            [
                "/bin/sh",
                str(self.transport),
                "--role",
                "advisor-terra",
                "--parent-thread",
                PARENT,
                "--sessions-dir",
                str(self.home / "sessions"),
            ],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=self.env,
        )
        transport_root = self.home / ".tmp" / "advisor-transport"
        try:
            for _ in range(50):
                if any(transport_root.glob("run.*")):
                    break
                time.sleep(0.05)
            self.assertTrue(any(transport_root.glob("run.*")))
            started = time.monotonic()
            process.send_signal(signal.SIGTERM)
            process.wait(timeout=4)
            self.assertLess(time.monotonic() - started, 3)
            self.assertFalse(any(transport_root.glob("run.*")))
            self.assertEqual(self.rows(), [])
        finally:
            if process.poll() is None:
                process.kill()
            if process.stdin:
                process.stdin.close()
            if process.stdout:
                process.stdout.close()
            if process.stderr:
                process.stderr.close()

    def test_process_deadline_bounds_partial_json_line(self) -> None:
        server = self.root / "partial.py"
        server.write_text(
            "import sys,time; sys.stdout.write('{'); sys.stdout.flush(); time.sleep(5)"
        )
        script = f"""import sys; sys.path.insert(0,{str(self.process.parent)!r}); from advisor_process import JsonRpcProcess\np=JsonRpcProcess([sys.executable,{str(server)!r}],deadline_seconds=.2)\ntry:\n p.request('x',{{}})\nfinally:\n p.close()\n"""
        started = time.monotonic()
        result = subprocess.run(
            [sys.executable, "-c", script],
            capture_output=True,
            text=True,
            check=False,
            timeout=3,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertLess(time.monotonic() - started, 2)

    def test_jsonrpc_rejects_server_requests_and_notification_floods(self) -> None:
        cases = {
            "request": "import json,sys; r=json.loads(sys.stdin.readline()); print(json.dumps({'id':99,'method':'ask','params':{}}),flush=True)",
            "flood": "import json,sys; r=json.loads(sys.stdin.readline()); [print(json.dumps({'method':'note','params':{}}),flush=True) for _ in range(513)]",
        }
        for name, source in cases.items():
            with self.subTest(name=name):
                server = self.root / f"{name}.py"
                server.write_text(source)
                script = f"""import sys; sys.path.insert(0,{str(self.process.parent)!r}); from advisor_process import JsonRpcProcess
p=JsonRpcProcess([sys.executable,{str(server)!r}],deadline_seconds=1)
try:
 p.request('x',{{}})
finally:
 p.close()
"""
                result = subprocess.run(
                    [sys.executable, "-c", script],
                    capture_output=True,
                    text=True,
                    check=False,
                    timeout=3,
                )
                self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
