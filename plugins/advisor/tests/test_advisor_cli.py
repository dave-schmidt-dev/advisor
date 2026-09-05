"""Black-box tests for the local Advisor settings entrypoint."""

from __future__ import annotations

import json
import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest
import uuid
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "scripts" / "advisor-config.sh"
PARENT = "56565656-5656-7565-8565-565656565656"
FAKE_CODEX = r'''#!/usr/bin/env python3
import json, os, signal, sys, time
from pathlib import Path

if sys.argv[1:] == ["--version"]:
    print(os.environ.get("FAKE_CODEX_VERSION", "codex-cli 0.153.2"))
    raise SystemExit(0)
if sys.argv[1:] == ["app-server", "--help"]:
    print("--ignore-user-config --ignore-rules")
    raise SystemExit(0)
if len(sys.argv) > 1 and sys.argv[1] == "app-server":
    raise SystemExit(90)

args = sys.argv[1:]
model = args[args.index("--model") + 1]
effort = args[args.index("-c") + 1].split('"')[1]
output = Path(args[args.index("--output-last-message") + 1])
log = Path(os.environ["FAKE_CODEX_LOG"])
rows = json.loads(log.read_text()) if log.exists() else []
rows.append({"model": model, "effort": effort})
log.write_text(json.dumps(rows))
attempt_file = Path(os.environ.get("FAKE_ATTEMPT_FILE", str(log) + ".attempt"))
attempt = int(attempt_file.read_text()) + 1 if attempt_file.exists() else 1
attempt_file.write_text(str(attempt))
case = os.environ.get("FAKE_CODEX_CASE", "valid")

if case == "hang":
    ready = Path(os.environ["FAKE_READY_MARKER"])
    terminated = Path(os.environ["FAKE_TERM_MARKER"])
    def stop(*_args):
        terminated.write_text("terminated")
        raise SystemExit(143)
    signal.signal(signal.SIGTERM, stop)
    ready.write_text(str(os.getpid()))
    while True:
        time.sleep(1)

child = f"{attempt:08x}-1111-7111-8111-{attempt:012x}"
sessions = Path(os.environ["CODEX_HOME"]) / "sessions" / "fixture"
sessions.mkdir(parents=True, exist_ok=True)
events = [
    {"type": "session_meta", "payload": {"id": child, "source": "exec", "originator": "codex_exec"}},
    {"type": "turn_context", "payload": {"model": model, "effort": effort, "sandbox_policy": {"type": "read-only"}, "permission_profile": {"type": "managed"}}},
]
(sessions / f"rollout-fake-{child}.jsonl").write_text("".join(json.dumps(row) + "\n" for row in events))
print(json.dumps({"type": "thread.started", "thread_id": child}))
response = {
    "recommendation": "neutral path", "why": "reason", "strongest_objection": "objection",
    "change_my_mind": "evidence", "acceptance_checks": ["check"], "risks": "none",
    "follow_up_areas": "none",
}
if case == "invalid-once" and attempt == 1:
    response.pop("risks")
output.write_text(json.dumps(response))
'''


class AdvisorCliTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.home = self.root / "codex"
        self.home.mkdir(mode=0o700)
        self.binary = self.root / "bin"
        self.binary.mkdir()
        self.fake = self.binary / "codex"
        self.fake.write_text(FAKE_CODEX, encoding="utf-8")
        self.fake.chmod(0o700)
        self.log = self.root / "codex.log"
        self.attempts = self.root / "attempts"
        self.env = {
            **os.environ,
            "CODEX_HOME": str(self.home),
            "CODEX_THREAD_ID": PARENT,
            "PATH": f"{self.binary}:{os.environ['PATH']}",
            "FAKE_CODEX_LOG": str(self.log),
            "FAKE_ATTEMPT_FILE": str(self.attempts),
        }
        self.write_parent_fixture("read-only")

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def write_parent_fixture(self, sandbox: str) -> None:
        sessions = self.home / "sessions" / "fixture"
        sessions.mkdir(parents=True, exist_ok=True)
        rollout = sessions / f"rollout-fake-{PARENT}.jsonl"
        rows = [
            {"type": "session_meta", "payload": {"id": PARENT, "agent_role": "root"}},
            {"type": "turn_context", "payload": {"sandbox_policy": {"type": sandbox}, "permission_profile": {"type": "managed"}}},
        ]
        rollout.write_text("".join(json.dumps(row) + "\n" for row in rows))

    def run_cli(
        self, *args: str, env: dict[str, str] | None = None, timeout: float = 10
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(CLI), *args], text=True, capture_output=True,
            env=env or self.env, check=False, timeout=timeout,
        )

    def invocations(self) -> list[dict[str, str]]:
        return json.loads(self.log.read_text()) if self.log.exists() else []

    def add(self, model: str = "manual/model") -> None:
        result = self.run_cli("--json", "models", "add", model)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_help_json_cold_start_and_doctor_inspect_actual_parent(self) -> None:
        help_result = self.run_cli("--help")
        self.assertEqual(help_result.returncode, 0)
        for command in ("show", "models", "set", "preset", "doctor", "reset", "restore", "deadline", "journal"):
            self.assertIn(command, help_result.stdout)
        show = self.run_cli("--json", "show")
        self.assertEqual(show.returncode, 0, show.stderr)
        self.assertEqual(len(show.stdout.splitlines()), 1)
        current = json.loads(show.stdout)
        self.assertEqual(current["selections"]["standard"]["model"], "gpt-5.6-terra")
        self.assertTrue(current["selection_revision"].startswith("sha256:"))
        self.assertTrue(current["live_config"]["path"].endswith("advisor.toml"))
        doctor = self.run_cli("--json", "doctor")
        self.assertEqual(doctor.returncode, 0, doctor.stderr)
        payload = json.loads(doctor.stdout)
        self.assertEqual(payload["parent_runtime"]["status"], "available")
        self.assertEqual(payload["parent_runtime"]["sandbox_policy_type"], "read-only")
        self.assertIn("inspecting parent runtime evidence", doctor.stderr)
        self.assertFalse((self.home / "advisor").exists())
        self.assertEqual(self.invocations(), [])

    def test_pristine_default_resolve_works_on_newer_cli_without_setup(self) -> None:
        for version in ("codex-cli 0.153.4", "codex-cli 9.0.0"):
            result = self.run_cli(
                "--json", "resolve", "--tier", "standard",
                env={**self.env, "FAKE_CODEX_VERSION": version},
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            launch = json.loads(result.stdout)["launch"]
            self.assertEqual(
                (launch["model"], launch["effort"]), ("gpt-5.6-terra", "high")
            )
            self.assertFalse((self.home / "advisor").exists())
            self.assertEqual(self.invocations(), [])

    def test_doctor_reports_missing_malformed_and_unsafe_evidence_without_inference(self) -> None:
        rollout = self.home / "sessions" / "fixture" / f"rollout-fake-{PARENT}.jsonl"
        rollout.write_text("not-json\n")
        malformed = json.loads(self.run_cli("--json", "doctor").stdout)
        self.assertEqual(malformed["parent_runtime"]["status"], "unavailable")
        self.write_parent_fixture("danger-full-access")
        unsafe = json.loads(self.run_cli("--json", "doctor").stdout)
        self.assertEqual(unsafe["parent_runtime"]["status"], "unavailable")
        rollout.unlink()
        missing = json.loads(self.run_cli("--json", "doctor").stdout)
        self.assertEqual(missing["parent_runtime"]["status"], "unavailable")
        self.assertEqual(self.invocations(), [])

    def test_add_test_select_preset_and_pair_freshness(self) -> None:
        self.add()
        unauthorized = self.run_cli(
            "--json", "models", "test", "manual/model", "--effort", "high",
            "--parent-thread", PARENT,
        )
        self.assertEqual(unauthorized.returncode, 2)
        self.assertEqual(self.invocations(), [])
        tested = self.run_cli(
            "--json", "models", "test", "manual/model", "--effort", "high",
            "--authorize-usage", "--parent-thread", PARENT,
            "--sessions-dir", str(self.home / "sessions"),
        )
        self.assertEqual(tested.returncode, 0, tested.stderr)
        self.assertFalse(json.loads(tested.stdout)["compatibility"]["selected"])
        self.assertEqual(len(self.invocations()), 1)
        listed = json.loads(self.run_cli("--json", "models", "list").stdout)
        receipts = listed["models"]["candidates"][0]["tested_compatibility"]
        self.assertEqual([(row["effort"], row["current"]) for row in receipts], [("high", True)])
        stale_env = {**self.env, "FAKE_CODEX_VERSION": "codex-cli 0.154.0"}
        retained = json.loads(self.run_cli("--json", "models", "list", env=stale_env).stdout)
        self.assertTrue(retained["models"]["candidates"][0]["tested_compatibility"][0]["current"])
        selected = self.run_cli(
            "--json", "set", "--tier", "standard", "--model", "manual/model", "--effort", "high"
        )
        self.assertEqual(selected.returncode, 2)
        self.assertIn("advisor.toml", selected.stdout)
        preset = self.run_cli(
            "--json", "preset", "manual", "--model", "manual/model", "--effort", "high"
        )
        self.assertEqual(preset.returncode, 0, preset.stderr)
        status = json.loads(self.run_cli("--json", "status").stdout)
        self.assertEqual(status["selections"]["standard"]["model"], "gpt-5.6-terra")

    def test_canary_uses_at_most_two_attempts_and_records_only_success(self) -> None:
        self.add()
        result = self.run_cli(
            "--json", "models", "test", "manual/model", "--effort", "high",
            "--authorize-usage", "--parent-thread", PARENT,
            "--sessions-dir", str(self.home / "sessions"),
            env={**self.env, "FAKE_CODEX_CASE": "invalid-once"},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.invocations()), 2)
        self.assertIn("one fresh corrective retry", result.stderr)
        catalog = json.loads((self.home / "advisor" / "catalog.json").read_text())
        self.assertEqual(len(catalog["compatibility"]), 1)

    def test_invalid_settings_recovery_reset_deadline_journal_and_errors(self) -> None:
        self.assertEqual(self.run_cli("--json", "deadline", "120").returncode, 0)
        self.assertEqual(self.run_cli("--json", "journal", "enable").returncode, 0)
        self.add("kept/model")
        settings = self.home / "advisor" / "settings.json"
        prior = self.home / "advisor" / "settings.previous.json"
        malformed = b'{"schema_version":1,"nested":' + b"[" * 1000
        settings.write_bytes(malformed)
        invalid = self.run_cli("--json", "show")
        self.assertEqual(invalid.returncode, 0)
        self.assertEqual(json.loads(invalid.stdout)["legacy_settings"], "invalid")
        restored = self.run_cli("--json", "restore")
        self.assertEqual(restored.returncode, 0, restored.stderr)
        invalid_copy = self.home / "advisor" / "settings.invalid.json"
        self.assertEqual(invalid_copy.read_bytes(), malformed)
        self.assertTrue(prior.exists())
        self.assertEqual(self.run_cli("--json", "deadline", "120").returncode, 0)
        self.assertEqual(self.run_cli("--json", "journal", "enable").returncode, 0)
        reset = self.run_cli("--json", "reset")
        self.assertEqual(reset.returncode, 2)
        self.assertIn("advisor.toml", reset.stdout)
        catalog = json.loads((self.home / "advisor" / "catalog.json").read_text())
        self.assertEqual(catalog["candidates"][0]["model"], "kept/model")
        self.assertEqual(self.run_cli("--json", "journal", "disable").returncode, 0)
        self.assertEqual(self.run_cli("--json", "journal", "clear").returncode, 0)

    def test_doctor_reports_dependencies_stale_selection_and_last_failure(self) -> None:
        self.add()
        settings_dir = self.home / "advisor"
        settings = {
            "schema_version": 1, "revision": 1,
            "selections": {"standard": {"model": "manual/model", "effort": "high"}, "specialist": {"model": "gpt-5.6-sol", "effort": "high"}},
            "presets": {}, "deadline_seconds": 300, "usage_journal_enabled": True,
        }
        (settings_dir / "settings.json").write_text(json.dumps(settings) + "\n")
        os.chmod(settings_dir / "settings.json", 0o600)
        record = {
            "schema_version": 1, "consultation_id": str(uuid.uuid4()),
            "started_at": "2026-09-04T12:00:00Z", "finished_at": "2026-09-04T12:00:01Z",
            "tier": "standard", "model": "manual/model", "effort": "high",
            "outcome": "failed", "transport_contract_version": "1.4", "total_duration_ms": 1,
            "attempts": [{"number": 1, "duration_ms": 1, "outcome": "runtime_failed", "usage": {"input": None, "cached_input": None, "output": None, "reasoning": None}}],
            "totals": {"input": None, "cached_input": None, "output": None, "reasoning": None},
        }
        written = self.run_cli("--json", "_journal-record", json.dumps(record))
        self.assertEqual(written.returncode, 0, written.stderr)
        doctor = json.loads(self.run_cli("--json", "doctor").stdout)
        self.assertEqual(doctor["live_config"]["pairs"]["standard"]["model"], "gpt-5.6-terra")
        self.assertTrue(doctor["live_config"]["source_revision"].startswith("sha256:"))
        self.assertIsNone(doctor["stale_selections"])
        self.assertEqual(doctor["last_content_free_failure"]["outcome"], "failed")
        self.assertEqual(doctor["dependencies"]["codex"]["status"], "available")
        minimal = self.root / "minimal-bin"
        minimal.mkdir()
        (minimal / "python3").symlink_to(Path(sys.executable))
        (minimal / "dirname").symlink_to("/usr/bin/dirname")
        no_codex = {**self.env, "PATH": str(minimal)}
        missing = json.loads(self.run_cli("--json", "doctor", env=no_codex).stdout)
        self.assertEqual(missing["dependencies"]["codex"]["status"], "missing")
        self.assertEqual(missing["dependencies"]["jq"], "missing")
        no_python_bin = self.root / "no-python-bin"
        no_python_bin.mkdir()
        (no_python_bin / "dirname").symlink_to("/usr/bin/dirname")
        no_python = self.run_cli(
            "--json", "doctor", env={**self.env, "PATH": str(no_python_bin)}
        )
        self.assertEqual(no_python.returncode, 2)
        self.assertIn("python3 is unavailable", no_python.stderr)

    def test_real_cli_natural_deadline_reaps_child_and_preserves_unrelated(self) -> None:
        self.add()
        self.assertEqual(self.run_cli("--json", "deadline", "30").returncode, 0)
        ready = self.root / "deadline-ready"
        terminated = self.root / "deadline-terminated"
        unrelated = subprocess.Popen(["sleep", "45"])
        started = time.monotonic()
        try:
            result = self.run_cli(
                "--json", "models", "test", "manual/model", "--effort", "high",
                "--authorize-usage", "--parent-thread", PARENT,
                "--sessions-dir", str(self.home / "sessions"),
                env={**self.env, "FAKE_CODEX_CASE": "hang", "FAKE_READY_MARKER": str(ready), "FAKE_TERM_MARKER": str(terminated)},
                timeout=38,
            )
            elapsed = time.monotonic() - started
            self.assertEqual(result.returncode, 2)
            self.assertGreaterEqual(elapsed, 28)
            self.assertLess(elapsed, 37)
            self.assertTrue(ready.exists())
            self.assertTrue(terminated.exists())
            self.assertIsNone(unrelated.poll())
            transport_root = self.home / ".tmp" / "advisor-transport"
            self.assertFalse(any(transport_root.glob("run.*")))
            self.assertFalse(any((self.home / "advisor" / "canaries").glob("*.json")))
        finally:
            unrelated.terminate()
            unrelated.wait(timeout=3)

    def test_real_cli_caller_cancellation_reaps_child_and_preserves_unrelated(self) -> None:
        self.add()
        ready = self.root / "cancel-ready"
        terminated = self.root / "cancel-terminated"
        unrelated = subprocess.Popen(["sleep", "20"])
        process = subprocess.Popen(
            [str(CLI), "--json", "models", "test", "manual/model", "--effort", "high", "--authorize-usage", "--parent-thread", PARENT, "--sessions-dir", str(self.home / "sessions")],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            env={**self.env, "FAKE_CODEX_CASE": "hang", "FAKE_READY_MARKER": str(ready), "FAKE_TERM_MARKER": str(terminated)},
        )
        try:
            started = time.monotonic()
            while not ready.exists() and time.monotonic() - started < 5:
                time.sleep(0.05)
            self.assertTrue(ready.exists())
            process.send_signal(signal.SIGTERM)
            process.wait(timeout=8)
            self.assertTrue(terminated.exists())
            self.assertIsNone(unrelated.poll())
            transport_root = self.home / ".tmp" / "advisor-transport"
            self.assertFalse(any(transport_root.glob("run.*")))
            self.assertFalse(any((self.home / "advisor" / "canaries").glob("*.json")))
        finally:
            if process.poll() is None:
                process.kill()
            if process.stdout:
                process.stdout.close()
            if process.stderr:
                process.stderr.close()
            unrelated.terminate()
            unrelated.wait(timeout=3)


if __name__ == "__main__":
    unittest.main()
