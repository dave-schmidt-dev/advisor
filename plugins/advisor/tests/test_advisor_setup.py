"""Regression coverage for ownership-safe Advisor startup allocation and cancellation cleanup."""

from __future__ import annotations

import json
import os
import signal
import subprocess
import time
import unittest
from pathlib import Path

if __package__:
    from .advisor_transport_support import (
        PARENT,
        AdvisorTransportTestCase,
    )
else:
    from advisor_transport_support import (
        PARENT,
        AdvisorTransportTestCase,
    )


class AdvisorSetupTests(AdvisorTransportTestCase):
    def test_mkdir_collision_preserves_unowned_path(self) -> None:
        capture_path = self.root / "mkdir_collision_target.txt"
        result = self.run_transport(
            "--role",
            "advisor-terra",
            env={
                "FAKE_MKDIR_CASE": "collision",
                "FAKE_MKDIR_CAPTURE": str(capture_path),
            },
        )
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("temporary directory creation failed", result.stderr)
        self.assertTrue(capture_path.exists())
        colliding_dir = Path(capture_path.read_text(encoding="utf-8").strip())
        self.assertTrue(colliding_dir.is_dir())
        sentinel = colliding_dir / "sentinel.txt"
        self.assertTrue(sentinel.exists())
        self.assertEqual(sentinel.read_text(encoding="utf-8"), "preserve me")
        self.assertEqual(self.rows(), [])

    def test_mkdir_failure_without_creation(self) -> None:
        capture_path = self.root / "mkdir_fail_target.txt"
        result = self.run_transport(
            "--role",
            "advisor-terra",
            env={
                "FAKE_MKDIR_CASE": "fail",
                "FAKE_MKDIR_CAPTURE": str(capture_path),
            },
        )
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("temporary directory creation failed", result.stderr)
        self.assertTrue(capture_path.exists())
        target_dir = Path(capture_path.read_text(encoding="utf-8").strip())
        self.assertFalse(target_dir.exists())
        self.assertEqual(self.rows(), [])

    def test_term_to_wrapper_during_delayed_allocator(self) -> None:
        ready = self.root / "allocator_ready"
        release = self.root / "allocator_release"
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
                "FAKE_MKDIR_CASE": "delay",
                "FAKE_MKDIR_READY": str(ready),
                "FAKE_MKDIR_RELEASE": str(release),
            },
        )
        try:
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline and not ready.exists():
                time.sleep(0.01)
            self.assertTrue(ready.exists())
            process.send_signal(signal.SIGTERM)
            release.write_text("go", encoding="utf-8")
            stdout, stderr = process.communicate(timeout=5)
            self.assertEqual(process.returncode, 130, stderr)
            envelope = json.loads(stdout)
            self.assertEqual(envelope["status"], "unavailable")
            self.assertEqual(envelope["outcome"], "cancelled")
            transport_root = self.home / ".tmp" / "advisor-transport"
            self.assertFalse(any(transport_root.glob("run.*")))
            self.assertEqual(self.rows(), [])
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=2)

    def test_term_to_process_group_during_delayed_allocator(self) -> None:
        ready = self.root / "pg_ready"
        release = self.root / "pg_release"
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
            start_new_session=True,
            env={
                **self.env,
                "FAKE_MKDIR_CASE": "delay",
                "FAKE_MKDIR_READY": str(ready),
                "FAKE_MKDIR_RELEASE": str(release),
            },
        )
        try:
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline and not ready.exists():
                time.sleep(0.01)
            self.assertTrue(ready.exists())
            os.killpg(os.getpgid(process.pid), signal.SIGTERM)
            release.write_text("go", encoding="utf-8")
            stdout, stderr = process.communicate(timeout=5)
            self.assertEqual(process.returncode, 130, stderr)
            envelope = json.loads(stdout)
            self.assertEqual(envelope["status"], "unavailable")
            self.assertEqual(envelope["outcome"], "cancelled")
            transport_root = self.home / ".tmp" / "advisor-transport"
            self.assertFalse(any(transport_root.glob("run.*")))
            self.assertEqual(self.rows(), [])
        finally:
            if process.poll() is None:
                try:
                    os.killpg(os.getpgid(process.pid), signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait(timeout=2)

    def test_chmod_failure_cleans_owned_directory(self) -> None:
        result = self.run_transport(
            "--role",
            "advisor-terra",
            env={"FAKE_CHMOD_CASE": "fail"},
        )
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("temporary directory protection failed", result.stderr)
        transport_root = self.home / ".tmp" / "advisor-transport"
        self.assertFalse(any(transport_root.glob("run.*")))
        self.assertEqual(self.rows(), [])

    def test_startup_cancellation_result_status130_and_no_provider_or_private_dirs(
        self,
    ) -> None:
        ready = self.root / "startup_ready"
        release = self.root / "startup_release"
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
                "FAKE_MKDIR_CASE": "delay",
                "FAKE_MKDIR_READY": str(ready),
                "FAKE_MKDIR_RELEASE": str(release),
            },
        )
        try:
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline and not ready.exists():
                time.sleep(0.01)
            self.assertTrue(ready.exists())
            process.send_signal(signal.SIGINT)
            release.write_text("go", encoding="utf-8")
            stdout, stderr = process.communicate(timeout=5)
            self.assertEqual(process.returncode, 130)
            envelope = json.loads(stdout)
            self.assertEqual(envelope["schema_version"], 3)
            self.assertEqual(envelope["status"], "unavailable")
            self.assertEqual(envelope["outcome"], "cancelled")
            self.assertEqual(envelope["selection"]["tier"], "standard")
            self.assertEqual(envelope["selection"]["model"], "gpt-5.6-terra")
            self.assertIsNone(envelope["runtime"])
            self.assertIsNone(envelope["response"])
            transport_root = self.home / ".tmp" / "advisor-transport"
            self.assertFalse(any(transport_root.glob("run.*")))
            self.assertEqual(self.rows(), [])
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=2)

    def test_early_cancellation_deterministic_repetition(self) -> None:
        for iteration in range(5):
            with self.subTest(iteration=iteration):
                ready = self.root / f"rep_ready_{iteration}"
                release = self.root / f"rep_release_{iteration}"
                process = subprocess.Popen(
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
                    stdin=subprocess.PIPE,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    env={
                        **self.env,
                        "FAKE_MKDIR_CASE": "delay",
                        "FAKE_MKDIR_READY": str(ready),
                        "FAKE_MKDIR_RELEASE": str(release),
                    },
                )
                try:
                    deadline = time.monotonic() + 5
                    while time.monotonic() < deadline and not ready.exists():
                        time.sleep(0.01)
                    self.assertTrue(ready.exists())
                    process.send_signal(signal.SIGTERM)
                    release.write_text("go", encoding="utf-8")
                    stdout, stderr = process.communicate(timeout=5)
                    self.assertEqual(process.returncode, 130, stderr)
                    envelope = json.loads(stdout)
                    self.assertEqual(envelope["status"], "unavailable")
                    self.assertEqual(envelope["outcome"], "cancelled")
                    transport_root = self.home / ".tmp" / "advisor-transport"
                    self.assertFalse(any(transport_root.glob("run.*")))
                    self.assertEqual(self.rows(), [])
                finally:
                    if process.poll() is None:
                        process.kill()
                        process.wait(timeout=2)


if __name__ == "__main__":
    unittest.main()
