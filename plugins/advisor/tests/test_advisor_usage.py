"""Usage-envelope, journal, wrapper, and aggregate-audit regressions."""

from __future__ import annotations

import datetime as dt
import importlib.util
import json
import os
import stat
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / "scripts" / "advisor_config.py"
PROCESS = ROOT / "scripts" / "advisor_process.py"
AUDIT = ROOT / "scripts" / "advisor-audit.sh"
TRANSPORT = ROOT / "scripts" / "run-advisor.sh"
PARENT = "56565656-5656-7565-8565-565656565656"
PACKET = "DECISION\nquestion\nCONTEXT\nevidence\nOPTIONS\nchoice\nBOUNDARIES\nlimits\nREQUEST\nchallenge\n"


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


config = load_module("advisor_usage_config", MODULE)
process = load_module("advisor_usage_process", PROCESS)

FAKE_CODEX = r"""#!/usr/bin/env python3
import json, os, shutil, sys, time
from pathlib import Path
args=sys.argv[1:]
if args == ["--version"]: print("codex-cli 0.153.2"); raise SystemExit(0)
model=args[args.index("--model")+1]; effort=args[args.index("-c")+1].split('"')[1]
output=Path(args[args.index("--output-last-message")+1])
counter=Path(os.environ["FAKE_COUNT"])
attempt=int(counter.read_text())+1 if counter.exists() else 1
counter.write_text(str(attempt))
child=f"{attempt:08x}-1111-7111-8111-{attempt:012x}"
events=[{"type":"session_meta","payload":{"id":child,"source":"exec","originator":"codex_exec"}}, {"type":"turn_context","payload":{"model":model,"effort":effort,"sandbox_policy":{"type":"read-only"},"permission_profile":{"type":"managed"}}}]
sessions=Path(os.environ["CODEX_HOME"])/"sessions"/"fixture"; sessions.mkdir(parents=True,exist_ok=True)
(sessions/f"rollout-fake-{child}.jsonl").write_text("".join(json.dumps(x)+"\n" for x in events))
case=os.environ.get("FAKE_CASE","success")
usage={"input_tokens":attempt*10,"cached_input_tokens":attempt,"output_tokens":attempt*3,"reasoning_output_tokens":attempt*2}
if case == "partial" and attempt == 2: usage={"output_tokens":attempt*3}
print(json.dumps({"type":"thread.started","thread_id":child}), flush=True)
print(json.dumps({"type":"turn.completed","usage":usage}), flush=True)
if case == "hang":
    while True: time.sleep(1)
if case == "journal-failure":
    journal=Path(os.environ["CODEX_HOME"])/"advisor"/"usage-journal"
    if journal.exists(): shutil.rmtree(journal)
    journal.symlink_to(Path(os.environ["FAKE_COUNT"]))
if case == "failure" or (case == "retry-failure" and attempt == 2): raise SystemExit(9)
response={"recommendation":"neutral","why":"reason","strongest_objection":"objection","change_my_mind":"evidence","acceptance_checks":["check"],"risks":"none","follow_up_areas":"none"}
if case in ("retry", "retry-failure", "partial") and attempt == 1: response.pop("risks")
output.write_text(json.dumps(response))
"""


class UsageTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.home = self.base / "codex"
        self.paths = config.state_paths(self.home)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def record(self, consultation_id="123e4567-e89b-42d3-a456-426614174000", when=None):
        when = when or dt.datetime.now(dt.timezone.utc)
        usage = {"input": 10, "cached_input": 3, "output": 4, "reasoning": None}
        return {
            "schema_version": 1,
            "consultation_id": consultation_id,
            "started_at": when.isoformat().replace("+00:00", "Z"),
            "finished_at": (when + dt.timedelta(seconds=1))
            .isoformat()
            .replace("+00:00", "Z"),
            "tier": "standard",
            "model": "gpt-5.6-terra",
            "effort": "high",
            "outcome": "accepted",
            "transport_contract_version": "1.4",
            "total_duration_ms": 1000,
            "attempts": [
                {
                    "number": 1,
                    "duration_ms": 1000,
                    "outcome": "accepted",
                    "usage": dict(usage),
                }
            ],
            "totals": dict(usage),
        }

    def enable(self):
        self.home.mkdir(mode=0o700, exist_ok=True)
        config.set_usage_journal(True, paths=self.paths)

    def test_opt_out_creates_no_state_and_content_free_clear(self):
        self.assertFalse(config.write_usage_journal(self.record(), paths=self.paths))
        self.assertFalse(self.paths.root.exists())
        self.enable()
        self.assertTrue(config.write_usage_journal(self.record(), paths=self.paths))
        entry = next(self.paths.journal.iterdir())
        self.assertEqual(stat.S_IMODE(entry.stat().st_mode), 0o600)
        text = entry.read_text()
        for forbidden in ("prompt", "answer", "child_id", "error", str(self.base)):
            self.assertNotIn(forbidden, text)
        self.assertEqual(config.clear_usage_journal(paths=self.paths), 1)

    def test_astra_opt_in_journal_record_is_written_durably(self):
        self.enable()
        record = self.record("323e4567-e89b-42d3-a456-426614174000")
        record.update({"tier": "opt-in", "model": "gpt-6-astra"})

        self.assertTrue(config.write_usage_journal(record, paths=self.paths))

        path = self.paths.journal / f"{record['consultation_id']}.json"
        self.assertTrue(path.is_file())
        persisted = config.validate_journal_record(config.read_json(path))
        self.assertEqual((persisted["tier"], persisted["model"]), ("opt-in", "gpt-6-astra"))

    def test_journal_strict_retention_concurrency_and_write_failure(self):
        bad = self.record()
        bad["outcome"] = "../../private-error"
        with self.assertRaises(config.ConfigError):
            config.validate_journal_record(bad)
        bad = self.record()
        bad["attempts"][0]["duration_ms"] = True
        with self.assertRaises(config.ConfigError):
            config.validate_journal_record(bad)
        bad = self.record()
        bad["attempts"].append(dict(bad["attempts"][0]))
        with self.assertRaises(config.ConfigError):
            config.validate_journal_record(bad)
        bad = self.record()
        bad["totals"]["input"] = 11
        with self.assertRaises(config.ConfigError):
            config.validate_journal_record(bad)
        self.enable()
        old = self.record(
            "223e4567-e89b-42d3-a456-426614174000",
            dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=31),
        )
        config.write_usage_journal(old, paths=self.paths)
        rows = [self.record(f"123e4567-e89b-42d3-a456-{i:012d}") for i in range(8)]
        errors = []

        def write(row):
            try:
                config.write_usage_journal(row, paths=self.paths)
            except (config.ConfigError, OSError) as exc:
                errors.append(exc)

        threads = [threading.Thread(target=write, args=(row,)) for row in rows]
        [t.start() for t in threads]
        [t.join() for t in threads]
        self.assertEqual(errors, [])
        self.assertEqual(len(list(self.paths.journal.glob("*.json"))), 8)
        with (
            mock.patch.object(
                config, "_atomic_write", side_effect=OSError("private content")
            ),
            self.assertRaises(OSError),
        ):
            config.write_usage_journal(self.record(), paths=self.paths)
        config.clear_usage_journal(paths=self.paths)
        self.paths.journal.rmdir()
        outside = self.base / "outside"
        outside.mkdir()
        self.paths.journal.symlink_to(outside)
        with self.assertRaises(config.ConfigError):
            config.write_usage_journal(self.record(), paths=self.paths)

    def test_usage_parser_actual_exec_precedence_partial_and_malformed(self):
        events = self.base / "events.jsonl"
        rows = [
            {
                "payload": {
                    "info": {
                        "total_token_usage": {"input_tokens": 99, "output_tokens": 99}
                    }
                }
            },
            {
                "type": "turn.completed",
                "usage": {
                    "input_tokens": 0,
                    "cached_input_tokens": 0,
                    "output_tokens": 7,
                },
            },
        ]
        events.write_text("".join(json.dumps(x) + "\n" for x in rows))
        actual = process.usage_from_events(str(events), duration_ms=12)
        self.assertEqual(
            actual["usage"],
            {"input": 0, "cached_input": 0, "output": 7, "reasoning": None},
        )
        self.assertEqual(actual["availability"]["reasoning"], "counter_absent")
        events.write_text(
            json.dumps({"type": "turn.completed", "usage": {"input_tokens": True}})
            + "\n"
        )
        with self.assertRaises(process.ProcessUnavailable):
            process.usage_from_events(str(events), duration_ms=1)
        events.write_text(
            json.dumps({"type": "turn.completed", "usage": {"input_tokens": -1}}) + "\n"
        )
        with self.assertRaises(process.ProcessUnavailable):
            process.usage_from_events(str(events), duration_ms=1)
        events.write_text(
            "".join(
                json.dumps({"type": "turn.completed", "usage": {"input_tokens": value}})
                + "\n"
                for value in (1, 2)
            )
        )
        with self.assertRaises(process.ProcessUnavailable):
            process.usage_from_events(str(events), duration_ms=1)
        events.write_text("not-json\n")
        with self.assertRaises(process.ProcessUnavailable):
            process.usage_from_events(str(events), duration_ms=1)

    def transport(self, case, journal=False):
        self.home.mkdir(mode=0o700, exist_ok=True)
        if journal:
            self.enable()
        bindir = self.base / "bin"
        bindir.mkdir(exist_ok=True)
        fake = bindir / "codex"
        fake.write_text(FAKE_CODEX)
        fake.chmod(0o700)
        env = {
            **os.environ,
            "PATH": f"{bindir}:{os.environ['PATH']}",
            "CODEX_HOME": str(self.home),
            "FAKE_COUNT": str(self.base / "count"),
            "FAKE_CASE": case,
        }
        return subprocess.run(
            [
                "/bin/sh",
                str(TRANSPORT),
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
            env=env,
            timeout=10,
            check=False,
        )

    def test_real_wrapper_success_retry_and_terminal_failure_usage(self):
        success = self.transport("success")
        self.assertEqual(success.returncode, 0, success.stderr)
        envelope = json.loads(success.stdout)
        self.assertEqual(
            envelope["usage"]["totals"],
            {"input": 10, "cached_input": 1, "output": 3, "reasoning": 2},
        )
        self.assertGreaterEqual(
            envelope["usage"]["total_duration_ms"],
            envelope["attempts"][0]["duration_ms"],
        )
        (self.base / "count").unlink()
        retry = self.transport("retry", journal=True)
        self.assertEqual(retry.returncode, 0, retry.stderr)
        envelope = json.loads(retry.stdout)
        self.assertEqual(
            [x["outcome"] for x in envelope["attempts"]],
            ["rejected_response", "accepted"],
        )
        self.assertEqual(envelope["usage"]["totals"]["input"], 30)
        (self.base / "count").unlink()
        partial = self.transport("partial")
        self.assertEqual(partial.returncode, 0, partial.stderr)
        envelope = json.loads(partial.stdout)
        self.assertEqual(envelope["usage"]["totals"]["input"], 10)
        self.assertEqual(envelope["usage"]["availability"]["input"], "partial")
        (self.base / "count").unlink()
        failed = self.transport("failure", journal=True)
        self.assertNotEqual(failed.returncode, 0)
        envelope = json.loads(failed.stdout)
        self.assertEqual(
            (envelope["status"], envelope["attempts"][0]["usage"]["input"]),
            ("unavailable", 10),
        )
        (self.base / "count").unlink()
        retry_failed = self.transport("retry-failure", journal=True)
        self.assertNotEqual(retry_failed.returncode, 0)
        envelope = json.loads(retry_failed.stdout)
        self.assertEqual(
            [row["outcome"] for row in envelope["attempts"]],
            ["rejected_response", "launch_failed"],
        )
        self.assertEqual(envelope["usage"]["totals"]["input"], 30)

    def test_journal_write_failure_warns_without_failing_advice(self):
        result = self.transport("journal-failure", journal=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["status"], "completed")
        self.assertIn("usage journal write unavailable", result.stderr)

    def test_cancellation_reaps_child_and_emits_usage_envelope(self):
        self.home.mkdir(mode=0o700, exist_ok=True)
        self.enable()
        bindir = self.base / "bin"
        bindir.mkdir()
        fake = bindir / "codex"
        fake.write_text(FAKE_CODEX)
        fake.chmod(0o700)
        env = {
            **os.environ,
            "PATH": f"{bindir}:{os.environ['PATH']}",
            "CODEX_HOME": str(self.home),
            "FAKE_COUNT": str(self.base / "count"),
            "FAKE_CASE": "hang",
        }
        child = subprocess.Popen(
            [
                "/bin/sh",
                str(TRANSPORT),
                "--tier",
                "standard",
                "--parent-thread",
                PARENT,
                "--sessions-dir",
                str(self.home / "sessions"),
            ],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
        )
        assert child.stdin and child.stdout and child.stderr
        child.stdin.write(PACKET)
        child.stdin.close()
        deadline = time.monotonic() + 3
        while not (self.base / "count").exists() and time.monotonic() < deadline:
            time.sleep(0.02)
        self.assertTrue((self.base / "count").exists())
        child.terminate()
        self.assertEqual(child.wait(timeout=5), 130)
        envelope = json.loads(child.stdout.read())
        child.stdout.close()
        child.stderr.close()
        self.assertEqual(envelope["outcome"], "cancelled")
        self.assertEqual(envelope["attempts"][0]["usage"]["input"], 10)

    def audit(self, sessions, *extra):
        result = subprocess.run(
            [
                "/bin/sh",
                str(AUDIT),
                "--sessions-dir",
                str(sessions),
                "--since",
                "2026-09-03T00:00:00Z",
                "--until",
                "2026-09-05T00:00:00Z",
                *extra,
            ],
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("parsing", result.stderr)
        return json.loads(result.stdout)

    def test_accounting_requires_runtime_corroboration_and_deduplicates_journal(self):
        sessions = self.base / "sessions"
        sessions.mkdir()
        child = "11111111-1111-7111-8111-111111111111"
        runtime = {
            "thread_id": child,
            "parent_thread_id": PARENT,
            "agent_role": "advisor-tier-standard",
            "transport": "codex-exec",
            "model": "gpt-5.6-terra",
            "effort": "high",
            "sandbox_policy_type": "read-only",
            "permission_profile_type": "managed",
        }
        envelope = {
            "schema_version": 3,
            "status": "completed",
            "outcome": "accepted",
            "consultation_id": "123e4567-e89b-42d3-a456-426614174000",
            "selection": {
                "tier": "standard",
                "model": "gpt-5.6-terra",
                "effort": "high",
                "source": "saved",
                "revision": 0,
                "transport_contract_version": "1.4",
            },
            "attempts": [
                {
                    "number": 1,
                    "outcome": "accepted",
                    "duration_ms": 100,
                    "usage": {
                        "input": 11,
                        "cached_input": 2,
                        "output": 3,
                        "reasoning": None,
                    },
                    "availability": {
                        "input": "available",
                        "cached_input": "available",
                        "output": "available",
                        "reasoning": "counter_absent",
                    },
                }
            ],
            "usage": {
                "total_duration_ms": 100,
                "totals": {
                    "input": 11,
                    "cached_input": 2,
                    "output": 3,
                    "reasoning": None,
                },
                "availability": {
                    "input": "available",
                    "cached_input": "available",
                    "output": "available",
                    "reasoning": "unavailable",
                },
            },
            "runtime": runtime,
            "response": "ADVISOR RESPONSE",
        }

        def exec_output(value):
            return [
                {"type": "input_text", "text": "Script completed\nOutput:"},
                {
                    "type": "input_text",
                    "text": json.dumps(
                        {
                            "chunk_id": "fixture",
                            "exit_code": 0,
                            "original_token_count": 100,
                            "output": json.dumps(value),
                            "wall_time_seconds": 1.25,
                        }
                    ),
                },
            ]

        parent = [
            {"type": "session_meta", "payload": {"id": PARENT}},
            {
                "type": "response_item",
                "timestamp": "2026-09-04T00:00:00Z",
                "payload": {
                    "type": "custom_tool_call",
                    "name": "exec",
                    "call_id": "advisor-call",
                    "input": "await tools.exec_command({cmd:'sh /installed/run-advisor.sh --tier standard'})",
                },
            },
            {
                "type": "response_item",
                "timestamp": "2026-09-04T00:00:00Z",
                "payload": {
                    "type": "custom_tool_call_output",
                    "call_id": "advisor-call",
                    "output": exec_output(envelope),
                },
            },
        ]
        fake = dict(envelope)
        fake["consultation_id"] = "223e4567-e89b-42d3-a456-426614174000"
        fake["runtime"] = None
        parent.append(
            {
                "type": "response_item",
                "timestamp": "2026-09-04T00:00:01Z",
                "payload": {
                    "type": "function_call_output",
                    "call_id": "advisor-call",
                    "output": exec_output(fake),
                },
            }
        )
        missing_child = json.loads(json.dumps(envelope))
        missing_child["consultation_id"] = "323e4567-e89b-42d3-a456-426614174000"
        missing_child["runtime"]["thread_id"] = "33333333-3333-7333-8333-333333333333"
        parent.append(
            {
                "type": "response_item",
                "timestamp": "2026-09-04T00:00:02Z",
                "payload": {
                    "type": "function_call_output",
                    "call_id": "advisor-call",
                    "output": exec_output(missing_child),
                },
            }
        )
        ambiguous = exec_output(envelope)
        ambiguous.append(dict(ambiguous[1]))
        parent.append(
            {
                "type": "response_item",
                "timestamp": "2026-09-04T00:00:03Z",
                "payload": {
                    "type": "custom_tool_call_output",
                    "call_id": "advisor-call",
                    "output": ambiguous,
                },
            }
        )
        child_rows = [
            {
                "type": "session_meta",
                "payload": {"id": child, "source": "exec", "originator": "codex_exec"},
            },
            {
                "type": "turn_context",
                "payload": {
                    "model": "gpt-5.6-terra",
                    "effort": "high",
                    "sandbox_policy": {"type": "read-only"},
                },
            },
        ]
        (sessions / "parent.jsonl").write_text(
            "".join(json.dumps(x) + "\n" for x in parent)
        )
        (sessions / "child.jsonl").write_text(
            "".join(json.dumps(x) + "\n" for x in child_rows)
        )
        (sessions / "malformed-structural.jsonl").write_text(
            json.dumps({"type": "session_meta", "payload": {"id": {"bad": True}}})
            + "\n"
            + json.dumps(
                {
                    "type": "turn_context",
                    "payload": {
                        "model": "gpt-5.6-terra",
                        "effort": "high",
                        "sandbox_policy": "read-only",
                    },
                }
            )
            + "\n"
        )
        journal = self.base / "journal"
        journal.mkdir()
        duplicate = self.record()
        duplicate["started_at"] = "2026-09-04T00:00:01Z"
        duplicate["finished_at"] = "2026-09-04T00:00:02Z"
        duplicate["attempts"][0]["usage"]["input"] = 11
        duplicate["attempts"][0]["usage"]["cached_input"] = 2
        duplicate["attempts"][0]["usage"]["output"] = 3
        duplicate["totals"]["input"] = 11
        duplicate["totals"]["cached_input"] = 2
        duplicate["totals"]["output"] = 3
        (journal / "one.json").write_text(json.dumps(duplicate))
        report = self.audit(
            sessions, "--mode", "accounting", "--journal-dir", str(journal)
        )
        self.assertEqual((report["consultations"], report["attempts"]), (1, 1))
        self.assertEqual(report["usage"]["totals"]["input"], 11)
        self.assertEqual(report["usage"]["availability"]["reasoning"], "unavailable")
        self.assertEqual(
            report["coverage"],
            {"correlated": 1, "uncorrelatable": 3, "deduplicated": 1},
        )

    def test_legacy_window_uses_deltas_and_handles_counter_reset(self):
        sessions = self.base / "sessions"
        sessions.mkdir()
        child = "11111111-1111-7111-8111-111111111111"

        def token(stamp, value):
            return {
                "timestamp": stamp,
                "type": "event_msg",
                "payload": {
                    "type": "token_count",
                    "info": {
                        "total_token_usage": {
                            "input_tokens": value,
                            "cached_input_tokens": 0,
                            "output_tokens": value,
                            "reasoning_output_tokens": value,
                        }
                    },
                },
            }

        rows = [
            {
                "timestamp": "2026-09-02T00:00:00Z",
                "type": "session_meta",
                "payload": {"id": child, "agent_role": "advisor-terra"},
            },
            token("2026-09-02T23:00:00Z", 100),
            token("2026-09-04T01:00:00Z", 130),
            token("2026-09-04T02:00:00Z", 5),
        ]
        (sessions / "child.jsonl").write_text(
            "".join(json.dumps(x) + "\n" for x in rows)
        )
        report = self.audit(sessions, "--mode", "legacy")
        self.assertEqual(report["runtime"]["tokens"]["input"], 35)
        self.assertEqual(report["runtime"]["tokens"]["reasoning"], 35)


if __name__ == "__main__":
    unittest.main()
