"""Regression coverage for the repository file-size rule."""

from __future__ import annotations

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


CHECKER = Path(__file__).resolve().parents[1] / "scripts" / "check_file_size.py"


class FileSizeCheckerTests(unittest.TestCase):
    """Exercise the CLI in disposable Git repositories."""

    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.repo = Path(temporary.name)
        subprocess.run(
            ["git", "init", "-q"],
            cwd=self.repo,
            capture_output=True,
            check=True,
        )

    def write(self, name: str, contents: bytes | str) -> None:
        """Write a fixture under the temporary repository root."""
        data = contents.encode() if isinstance(contents, str) else contents
        (self.repo / name).write_bytes(data)

    def check(self) -> subprocess.CompletedProcess[str]:
        """Run the checker against all files in the temporary repository."""
        return subprocess.run(
            [sys.executable, str(CHECKER), "--all"],
            cwd=self.repo,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_counts_lines_with_and_without_trailing_newline(self) -> None:
        self.write("terminated.py", b"pass\n" * 800)
        self.write("unterminated.py", b"pass\n" * 799 + b"pass")

        result = self.check()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("terminated.py has 800 lines", result.stdout)
        self.assertIn("unterminated.py has 800 lines", result.stdout)

    def test_rejects_exception_without_reason(self) -> None:
        self.write("small.py", "pass\n")
        self.write(".file-size-exceptions", "small.py\n")

        result = self.check()

        self.assertEqual(result.returncode, 1)
        self.assertIn("exception entry needs a reason", result.stderr)

    def test_rejects_numeric_cap(self) -> None:
        self.write("small.py", "pass\n")
        self.write(".file-size-exceptions", "small.py 900 old limit\n")

        result = self.check()

        self.assertEqual(result.returncode, 1)
        self.assertIn("line caps are no longer supported", result.stderr)

    def test_rejects_duplicate_exception_path(self) -> None:
        self.write("small.py", "pass\n")
        self.write(".file-size-exceptions", "small.py first reason\nsmall.py second reason\n")

        result = self.check()

        self.assertEqual(result.returncode, 1)
        self.assertIn("duplicate exception path small.py", result.stderr)

    def test_rejects_file_over_ceiling_without_exception(self) -> None:
        self.write("large.py", b"pass\n" * 801)

        result = self.check()

        self.assertEqual(result.returncode, 1)
        self.assertIn("large.py has 801 lines (maximum 800)", result.stderr)

    def test_warns_above_target_through_ceiling(self) -> None:
        self.write("target.py", b"pass\n" * 501)

        result = self.check()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("target.py has 501 lines (target 500)", result.stdout)

    def test_notices_stale_exception(self) -> None:
        self.write("small.py", "pass\n")
        self.write(".file-size-exceptions", "small.py legacy 2026-09-27: old oversized file\n")

        result = self.check()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("remove its exception from .file-size-exceptions", result.stdout)

    def test_staged_honors_alternate_exceptions_and_ignores_working_tree_only_edits(self) -> None:
        self.write("large.py", b"pass\n" * 801)
        subprocess.run(["git", "add", "large.py"], cwd=self.repo, check=True)

        self.write(".file-size-exceptions", "large.py default allowed\n")
        subprocess.run(["git", "add", ".file-size-exceptions"], cwd=self.repo, check=True)

        default_res = subprocess.run(
            [sys.executable, str(CHECKER), "--staged"],
            cwd=self.repo,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(default_res.returncode, 0, default_res.stderr)

        self.write("alt-exceptions", "large.py alternate allowed\n")
        res = subprocess.run(
            [sys.executable, str(CHECKER), "--staged", "--exceptions", "alt-exceptions"],
            cwd=self.repo,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(res.returncode, 1)
        self.assertIn("add a reasoned entry to alt-exceptions", res.stderr)

        subprocess.run(["git", "add", "alt-exceptions"], cwd=self.repo, check=True)
        res = subprocess.run(
            [sys.executable, str(CHECKER), "--staged", "--exceptions", "alt-exceptions"],
            cwd=self.repo,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(res.returncode, 0, res.stderr)

        self.write("alt-exceptions", "")
        res = subprocess.run(
            [sys.executable, str(CHECKER), "--staged", "--exceptions", "alt-exceptions"],
            cwd=self.repo,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(res.returncode, 0, res.stderr)


if __name__ == "__main__":
    unittest.main()
