"""Synthetic Git-fixture tests for Advisor candidate freezing and ZIP packaging."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
import zipfile


PUBLIC_RELEASE = Path(__file__).resolve().parent
INVENTORY_TOOL = PUBLIC_RELEASE / "candidate_inventory.py"
FREEZE_TOOL = PUBLIC_RELEASE / "freeze-candidate.sh"
PACKAGE_TOOL = PUBLIC_RELEASE / "package-candidate.sh"

SPEC = importlib.util.spec_from_file_location("candidate_inventory_under_test", INVENTORY_TOOL)
assert SPEC and SPEC.loader
candidate_inventory = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = candidate_inventory
SPEC.loader.exec_module(candidate_inventory)


class CandidatePackageTests(unittest.TestCase):
    """Exercise package behavior without touching this checkout's Git state."""

    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.repo = Path(self.temporary.name)
        self._make_fixture()

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def _git(self, *arguments: str) -> None:
        subprocess.run(["git", *arguments], cwd=self.repo, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def _make_fixture(self) -> None:
        for tool in (INVENTORY_TOOL, FREEZE_TOOL, PACKAGE_TOOL):
            destination = self.repo / "public-release" / tool.name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(tool, destination)
        files = {
            "plugins/advisor/.codex-plugin/plugin.json": json.dumps({"name": "advisor", "version": "9.9.9"}),
            "plugins/advisor/advisor-response.schema.json": '{"type":"object"}\n',
            "plugins/advisor/models.json": '{"models":[]}\n',
            "plugins/advisor/settings.schema.json": '{"type":"object"}\n',
            "plugins/advisor/agents/advisor.toml": "name = 'advisor'\n",
            "plugins/advisor/assets/icon.png": "not-a-real-image\n",
            "plugins/advisor/evals/cases.json": "[]\n",
            "plugins/advisor/scripts/run.sh": "#!/bin/sh\necho advisor\n",
            "plugins/advisor/skills/consultation/SKILL.md": "# consultation\n",
            "plugins/advisor/.cache/compiled.pyc": "generated\n",
            "plugins/advisor/logs/package.log": "generated\n",
            "plugins/advisor/temp/archive.tmp": "generated\n",
            "plugins/advisor/.DS_Store": "generated\n",
            "docs/release-notes-draft.md": "# Candidate\n\nCandidate content digest: `" + "0" * 64 + "`.\n",
        }
        for name, contents in files.items():
            target = self.repo / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(contents, encoding="utf-8")
        (self.repo / "plugins/advisor/scripts/run.sh").chmod(0o755)
        self._git("init")
        self._git("add", ".")

    def _run(self, *arguments: str, check: bool = True) -> subprocess.CompletedProcess[str]:
        return subprocess.run(arguments, cwd=self.repo, check=check, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def _inventory(self) -> dict[str, object]:
        result = self._run("python3", "public-release/candidate_inventory.py", "inventory", "--repo", str(self.repo), "--json")
        return json.loads(result.stdout)

    def _package(self, name: str) -> subprocess.CompletedProcess[str]:
        return self._run("sh", "public-release/package-candidate.sh", "--json", name)

    def test_archive_is_deterministic_and_exactly_matches_inventory(self) -> None:
        inventory = self._inventory()
        first = self._package("first.zip")
        second = self._package("second.zip")
        self.assertEqual((self.repo / "first.zip").read_bytes(), (self.repo / "second.zip").read_bytes())
        result = json.loads(first.stdout)
        self.assertEqual(result["candidate_digest"], inventory["digest"])
        self.assertGreater(result["bytes"], 0)
        names = [item["name"] for item in inventory["files"]]
        self.assertNotIn("advisor/.cache/compiled.pyc", names)
        self.assertNotIn("advisor/logs/package.log", names)
        self.assertNotIn("advisor/temp/archive.tmp", names)
        self.assertNotIn("advisor/.DS_Store", names)
        with zipfile.ZipFile(self.repo / "first.zip") as archive:
            self.assertEqual(archive.namelist(), [item["name"] for item in inventory["files"]])
            self.assertTrue(all(info.date_time == (1980, 1, 1, 0, 0, 0) for info in archive.infolist()))
            self.assertIsNone(archive.testzip())
            modes = {info.filename: info.external_attr >> 16 for info in archive.infolist()}
            self.assertEqual(modes["advisor/scripts/run.sh"], 0o100755)
            self.assertEqual(modes["advisor/models.json"], 0o100644)
        inventory_modes = {item["name"]: item["mode"] for item in inventory["files"]}
        self.assertEqual(inventory_modes["advisor/scripts/run.sh"], "100755")

    def test_full_tree_digest_changes_for_root_models_schema_and_assets(self) -> None:
        original = self._inventory()["digest"]
        for relative in ("models.json", "settings.schema.json", "assets/icon.png"):
            target = self.repo / "plugins/advisor" / relative
            target.write_text(target.read_text(encoding="utf-8") + "changed\n", encoding="utf-8")
            changed = self._inventory()["digest"]
            self.assertNotEqual(changed, original)
            original = changed

    def test_embedded_manifest_identity_and_version_are_checked(self) -> None:
        self._package("candidate.zip")
        with zipfile.ZipFile(self.repo / "candidate.zip") as archive:
            manifest = json.loads(archive.read("advisor/.codex-plugin/plugin.json"))
        self.assertEqual(manifest, {"name": "advisor", "version": "9.9.9"})
        manifest["name"] = "not-advisor"
        (self.repo / "plugins/advisor/.codex-plugin/plugin.json").write_text(json.dumps(manifest), encoding="utf-8")
        result = self._run("python3", "public-release/candidate_inventory.py", "inventory", "--repo", str(self.repo), "--digest", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("identity", result.stderr)

    def test_missing_files_symlinks_and_traversal_are_rejected(self) -> None:
        (self.repo / "plugins/advisor/assets/icon.png").unlink()
        result = self._run("python3", "public-release/candidate_inventory.py", "inventory", "--repo", str(self.repo), "--digest", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing", result.stderr)
        self._make_fixture()
        asset = self.repo / "plugins/advisor/assets/icon.png"
        asset.unlink()
        asset.symlink_to("../models.json")
        result = self._run("python3", "public-release/candidate_inventory.py", "inventory", "--repo", str(self.repo), "--digest", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("symlink", result.stderr)
        with self.assertRaises(candidate_inventory.CandidateError):
            candidate_inventory.validate_relative_path("../outside")

    def test_manifest_symlink_is_rejected_before_version_read(self) -> None:
        manifest = self.repo / "plugins/advisor/.codex-plugin/plugin.json"
        replacement = self.repo / "manifest.json"
        replacement.write_bytes(manifest.read_bytes())
        manifest.unlink()
        manifest.symlink_to(replacement)
        with self.assertRaisesRegex(candidate_inventory.CandidateError, "symlink"):
            candidate_inventory.collect_inventory(self.repo)

    def test_private_plugin_file_is_rejected(self) -> None:
        private = self.repo / "plugins/advisor/.env"
        private.write_text("not-a-secret\n", encoding="utf-8")
        self._git("add", "plugins/advisor/.env")
        result = self._run("python3", "public-release/candidate_inventory.py", "inventory", "--repo", str(self.repo), "--digest", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("sensitive", result.stderr)

    def test_untracked_plugin_file_is_rejected(self) -> None:
        (self.repo / "plugins/advisor/new-file.txt").write_text("untracked\n", encoding="utf-8")
        result = self._run("python3", "public-release/candidate_inventory.py", "inventory", "--repo", str(self.repo), "--digest", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("untracked", result.stderr)

    def test_ignored_sensitive_plugin_file_is_rejected(self) -> None:
        (self.repo / ".gitignore").write_text("plugins/advisor/.env\n", encoding="utf-8")
        (self.repo / "plugins/advisor/.env").write_text("ignored\n", encoding="utf-8")
        result = self._run("python3", "public-release/candidate_inventory.py", "inventory", "--repo", str(self.repo), "--digest", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("sensitive", result.stderr)

    def test_existing_archive_is_not_overwritten(self) -> None:
        target = self.repo / "already.zip"
        target.write_bytes(b"keep me")
        result = self._run("sh", "public-release/package-candidate.sh", str(target), check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(target.read_bytes(), b"keep me")

    def test_archive_created_during_build_is_not_overwritten(self) -> None:
        output = self.repo / "raced.zip"
        original_validate = candidate_inventory.validate_archive

        def create_owner_artifact(inventory: object, temporary: Path) -> None:
            original_validate(inventory, temporary)
            output.write_bytes(b"owner artifact created during build")

        with mock.patch.object(candidate_inventory, "validate_archive", side_effect=create_owner_artifact):
            with self.assertRaisesRegex(candidate_inventory.CandidateError, "overwrite"):
                candidate_inventory.package_candidate(self.repo, output)
        self.assertEqual(output.read_bytes(), b"owner artifact created during build")
        self.assertEqual(list(self.repo.glob(".raced.zip.*.tmp")), [])

    def test_dangling_archive_symlink_is_rejected_without_writing_target(self) -> None:
        output = self.repo / "candidate.zip"
        missing = self.repo / "missing-target.zip"
        output.symlink_to(missing.name)
        with self.assertRaisesRegex(candidate_inventory.CandidateError, "overwrite"):
            candidate_inventory.package_candidate(self.repo, output)
        self.assertTrue(output.is_symlink())
        self.assertFalse(missing.exists())

    def test_release_notes_require_one_well_formed_digest(self) -> None:
        notes = self.repo / "docs/release-notes-draft.md"
        for contents in ("# none\n", "Content digest: nope\n", "Content digest: `" + "a" * 64 + "`.\nContent digest: `" + "b" * 64 + "`.\n"):
            notes.write_text(contents, encoding="utf-8")
            result = self._run("python3", "public-release/candidate_inventory.py", "release-notes", "--notes", str(notes), "--check", check=False)
            self.assertNotEqual(result.returncode, 0)
        notes.write_text("Candidate content digest: `" + "a" * 64 + "`.\n", encoding="utf-8")
        self._run("python3", "public-release/candidate_inventory.py", "release-notes", "--notes", str(notes), "--write", "b" * 64)
        self.assertEqual(candidate_inventory.release_note_digest(notes), "b" * 64)

    def test_release_note_update_changes_only_field_and_preserves_mode(self) -> None:
        notes = self.repo / "docs/release-notes-draft.md"
        old = "a" * 64
        notes.write_text(f"Unrelated hash: {old}\nCandidate content digest: `{old}`.\n", encoding="utf-8")
        notes.chmod(0o640)
        candidate_inventory.write_release_note_digest(notes, "b" * 64)
        self.assertEqual(notes.read_text(encoding="utf-8"), f"Unrelated hash: {old}\nCandidate content digest: `{'b' * 64}`.\n")
        self.assertEqual(stat.S_IMODE(notes.stat().st_mode), 0o640)

    def test_release_note_update_rejects_symlink(self) -> None:
        notes = self.repo / "docs/release-notes-draft.md"
        target = self.repo / "docs/owner-notes.md"
        target.write_bytes(notes.read_bytes())
        notes.unlink()
        notes.symlink_to(target.name)
        with self.assertRaisesRegex(candidate_inventory.CandidateError, "regular file"):
            candidate_inventory.write_release_note_digest(notes, "b" * 64)
        self.assertIn("0" * 64, target.read_text(encoding="utf-8"))

    def test_release_note_publish_failure_cleans_temp_and_preserves_owner_bytes(self) -> None:
        notes = self.repo / "docs/release-notes-draft.md"
        original = notes.read_bytes()
        existing = set(notes.parent.iterdir())
        with mock.patch.object(candidate_inventory.os, "replace", side_effect=OSError("synthetic failure")):
            with self.assertRaisesRegex(candidate_inventory.CandidateError, "update"):
                candidate_inventory.write_release_note_digest(notes, "b" * 64)
        self.assertEqual(notes.read_bytes(), original)
        self.assertEqual(set(notes.parent.iterdir()), existing)

    def test_failure_cleanup_leaves_no_archive_or_temporary_file(self) -> None:
        output = self.repo / "failure.zip"
        with mock.patch.object(candidate_inventory, "write_archive", side_effect=RuntimeError("synthetic failure")):
            with self.assertRaises(RuntimeError):
                candidate_inventory.package_candidate(self.repo, output)
        self.assertFalse(output.exists())
        self.assertEqual(list(self.repo.glob(".failure.zip.*.tmp")), [])

    def test_freeze_reads_and_writes_the_shared_digest(self) -> None:
        self._run("sh", "public-release/freeze-candidate.sh", "--write")
        checked = self._run("sh", "public-release/freeze-candidate.sh", "--check")
        self.assertIn("PASS", checked.stdout)


def load_tests(loader: unittest.TestLoader, tests: unittest.TestSuite, pattern: str | None) -> unittest.TestSuite:
    """Keep the canonical candidate-package command as the release test runner."""
    test_path = PUBLIC_RELEASE / "test_upload_readiness.py"
    spec = importlib.util.spec_from_file_location("upload_readiness_tests", test_path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    sys.path.insert(0, str(PUBLIC_RELEASE))
    try:
        spec.loader.exec_module(module)
    finally:
        sys.path.pop(0)

    tests.addTests(loader.loadTestsFromModule(module))
    return tests


if __name__ == "__main__":
    unittest.main()
