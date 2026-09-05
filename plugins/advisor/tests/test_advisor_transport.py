"""Black-box coverage for configurable Advisor discovery and consultation transport."""

from __future__ import annotations

import importlib.util
import json
import os
import signal
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from contextlib import contextmanager
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONFIG_WRAPPER = ROOT / "scripts" / "advisor-config.sh"
TRANSPORT = ROOT / "scripts" / "run-advisor.sh"
PROCESS = ROOT / "scripts" / "advisor_process.py"
CONFIG_MODULE = ROOT / "scripts" / "advisor_config.py"
SPEC = importlib.util.spec_from_file_location("transport_advisor_config", CONFIG_MODULE)
assert SPEC and SPEC.loader
config = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = config
SPEC.loader.exec_module(config)

PARENT = "56565656-5656-7565-8565-565656565656"
PACKET = """DECISION
question
CONTEXT
evidence
OPTIONS
choice
BOUNDARIES
limits
REQUEST
challenge
"""

FAKE_CODEX = r"""#!/usr/bin/env python3
import json, os, signal, sys, time
from pathlib import Path

if sys.argv[1:] == ["--version"]:
    print(os.environ.get("FAKE_CODEX_VERSION", "codex-cli 0.153.2"))
    raise SystemExit(0)
if sys.argv[1:] == ["app-server", "--help"]:
    if os.environ.get("FAKE_DISCOVERY_UNSUPPORTED"):
        print("Usage: codex app-server")
    else:
        print("--ignore-user-config --ignore-rules")
    raise SystemExit(0)
if len(sys.argv) > 1 and sys.argv[1] == "app-server":
    for line in sys.stdin:
        request = json.loads(line)
        method = request.get("method")
        if method == "initialize":
            print(json.dumps({"id": request["id"], "result": {"serverInfo": {}}}), flush=True)
        elif method == "model/list":
            print(json.dumps({"id": request["id"], "result": {"data": [{
                "id": "friendly", "model": "provider/model", "displayName": "Friendly",
                "description": "model", "hidden": False, "isDefault": False,
                "defaultReasoningEffort": "high", "supportedReasoningEfforts": [
                    {"reasoningEffort": "high", "description": "default", "future": True}
                ], "unknownOptionalField": {"safe": True}
            }], "nextCursor": None}}), flush=True)
    raise SystemExit(0)

args = sys.argv[1:]
model = args[args.index("--model") + 1]
effort = args[args.index("-c") + 1].split('"')[1]
output = Path(args[args.index("--output-last-message") + 1])
workdir = Path(args[args.index("-C") + 1])
assert args[0] == "exec" and args[args.index("--sandbox") + 1] == "read-only"
assert workdir.is_dir() and workdir.parent.name.startswith("run.")
prompt = sys.stdin.read()
log = Path(os.environ["FAKE_INVOCATIONS"])
rows = json.loads(log.read_text()) if log.exists() else []
rows.append({"model": model, "effort": effort, "prompt": prompt})
log.write_text(json.dumps(rows))
attempt = len(rows)
case = os.environ.get("FAKE_CASE", "valid")

if case == "hang":
    marker = Path(os.environ["FAKE_TERM_MARKER"])
    def stopped(*_args):
        marker.write_text("terminated")
        raise SystemExit(143)
    signal.signal(signal.SIGTERM, stopped)
    Path(os.environ["FAKE_READY_MARKER"]).write_text(str(os.getpid()))
    while True:
        time.sleep(1)

if case == "mutate-retry" and attempt == 1:
    Path(os.environ["ADVISOR_LIVE_CONFIG"]).write_text(
        '[standard]\nmodel = "gpt-5.6-sol"\neffort = "ultra"\n\n'
        '[specialist]\nmodel = "gpt-6-astra"\neffort = "max"\n'
    )

child = f"{attempt:08x}-1111-7111-8111-{attempt:012x}"
runtime_model = "wrong/model" if case == "wrong-model" else model
runtime_effort = "low" if case == "wrong-effort" else effort
events = [
    {"type": "session_meta", "payload": {"id": child, "source": "exec", "originator": "codex_exec"}},
    {"type": "turn_context", "payload": {"model": runtime_model, "effort": runtime_effort, "sandbox_policy": {"type": "read-only"}, "permission_profile": {"type": "managed"}}},
]
if case == "tool":
    events.append({"type": "function_call", "name": "forbidden"})
if case == "reroute":
    events.append({"type": "model_reroute", "from": model, "to": runtime_model})
sessions = Path(os.environ["CODEX_HOME"]) / "sessions" / "fixture"
sessions.mkdir(parents=True, exist_ok=True)
(sessions / f"rollout-fake-{child}.jsonl").write_text("".join(json.dumps(row) + "\n" for row in events))
print(json.dumps({"type": "thread.started", "thread_id": child}))
response = {
    "recommendation": "neutral path", "why": "reason", "strongest_objection": "objection",
    "change_my_mind": "evidence", "acceptance_checks": ["check"], "risks": "none",
    "follow_up_areas": "none"
}
if case == "mutate-retry" and attempt == 1:
    response.pop("risks")
output.write_text(json.dumps(response))
"""


class AdvisorTransportTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.home = self.root / "codex"
        self.home.mkdir(mode=0o700)
        self.plugin_root = self.root / "plugin"
        shutil.copytree(ROOT, self.plugin_root)
        self.config_wrapper = self.plugin_root / "scripts" / "advisor-config.sh"
        self.transport = self.plugin_root / "scripts" / "run-advisor.sh"
        self.process = self.plugin_root / "scripts" / "advisor_process.py"
        self.live_config_path = self.plugin_root / "advisor.toml"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.fake = self.bin / "codex"
        self.fake.write_text(FAKE_CODEX, encoding="utf-8")
        self.fake.chmod(0o700)
        self.invocations = self.root / "invocations.json"
        self.env = {
            **os.environ,
            "CODEX_HOME": str(self.home),
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "FAKE_INVOCATIONS": str(self.invocations),
            "ADVISOR_LIVE_CONFIG": str(self.live_config_path),
        }
        self.paths = config.state_paths(self.home)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    @contextmanager
    def live_config(self, standard: dict[str, str], specialist: dict[str, str]):
        """Edit only this test's private plugin copy."""
        self.live_config_path.write_text(
            "[standard]\n"
            f'model = "{standard["model"]}"\n'
            f'effort = "{standard["effort"]}"\n\n'
            "[specialist]\n"
            f'model = "{specialist["model"]}"\n'
            f'effort = "{specialist["effort"]}"\n',
            encoding="utf-8",
        )
        yield self.live_config_path

    def run_transport(
        self, *arguments: str, case: str = "valid", env: dict[str, str] | None = None
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                "/bin/sh",
                str(self.transport),
                *arguments,
                "--parent-thread",
                PARENT,
                "--sessions-dir",
                str(self.home / "sessions"),
            ],
            input=PACKET,
            text=True,
            capture_output=True,
            check=False,
            env={**self.env, "FAKE_CASE": case, **(env or {})},
            timeout=10,
        )

    def rows(self) -> list[dict[str, str]]:
        return (
            json.loads(self.invocations.read_text())
            if self.invocations.exists()
            else []
        )

    def qualify(self, model: str, effort: str = "high") -> None:
        config.add_manual_candidate(model, paths=self.paths)
        config.record_compatibility(
            {"model": model, "effort": effort},
            codex_version="codex-cli 0.153.2",
            paths=self.paths,
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
                ("gpt-5.6-sol", "high"),
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
            {"model": "gpt-5.6-sol", "effort": "low"},
        ):
            standard = self.run_transport("--tier", "standard")
            specialist = self.run_transport("--tier", "specialist")
        self.assertEqual((standard.returncode, specialist.returncode), (0, 0))
        self.assertEqual(
            [(row["model"], row["effort"]) for row in self.rows()],
            [("gpt-6-astra", "max"), ("gpt-5.6-sol", "low")],
        )
        self.assertFalse(self.paths.root.exists(), "live config must not create state")
        selection = json.loads(standard.stdout)["selection"]
        self.assertEqual(selection["source"], "live-config")
        self.assertTrue(selection["source_revision"].startswith("sha256:"))

    def test_live_future_selector_needs_no_catalog_or_canary_and_invalid_toml_launches_nothing(self) -> None:
        with self.live_config(
            {"model": "future/provider-2049", "effort": "ultra"},
            {"model": "gpt-5.6-sol", "effort": "high"},
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
            '[specialist]\nmodel = "gpt-5.6-sol"\neffort = "high"\n'
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
        original_digest = config.hashlib.sha256(self.live_config_path.read_bytes()).hexdigest()
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
            ("gpt-5.6-sol", "ultra"),
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
            for _ in range(50):
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
