"""Synthetic offline tests for the marketplace upload-readiness evidence gate."""

from __future__ import annotations

import contextlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

PUBLIC_RELEASE = Path(__file__).resolve().parent
if str(PUBLIC_RELEASE) not in sys.path:
    sys.path.insert(0, str(PUBLIC_RELEASE))

import candidate_inventory
import upload_readiness


class UploadReadinessTests(unittest.TestCase):
    """Exercise release evidence against isolated repositories and fake HTTP only."""

    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.repo = Path(self.temporary.name)
        self._make_fixture()
        inventory = candidate_inventory.collect_inventory(self.repo)
        self.archive = self.repo / "candidate.zip"
        candidate_inventory.write_archive(inventory, self.archive)
        self.live = {
            upload_readiness._expected_url(url): self.repo.joinpath(relative).read_bytes()
            for relative, url in upload_readiness.SITE_FILES
        }

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def _git(self, *arguments: str) -> None:
        subprocess.run(["git", *arguments], cwd=self.repo, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def _make_fixture(self) -> None:
        plugin = self.repo / "plugins/advisor/.codex-plugin/plugin.json"
        plugin.parent.mkdir(parents=True)
        plugin.write_text(json.dumps({"name": "advisor", "version": "9.9.9"}), encoding="utf-8")
        payload = self.repo / "plugins/advisor/skills/consultation/SKILL.md"
        payload.parent.mkdir(parents=True)
        payload.write_text("# test\n", encoding="utf-8")
        listing = """# Public listing

| **Version** | `9.9.9` |

### Short Description
Useful read-only advice.

### Long Description
Detailed, publishable information for users.
"""
        (self.repo / "docs").mkdir()
        (self.repo / "docs/public-listing.md").write_text(listing, encoding="utf-8")
        for relative, _url in upload_readiness.SITE_FILES:
            page = self.repo / relative
            page.parent.mkdir(parents=True, exist_ok=True)
            if relative.endswith(".html"):
                page.write_text('<!doctype html><meta name="advisor-release" content="9.9.9">\n', encoding="utf-8")
            else:
                page.write_bytes(b"safe deployable asset\n")
        self._git("init")
        self._git("add", ".")

    def _fetch(self, url: str) -> upload_readiness.FetchResponse:
        return upload_readiness.FetchResponse(url, 200, self.live[url])

    def _verify(self) -> dict[str, object]:
        return upload_readiness.verify_upload_ready(self.repo, self.archive, self._fetch)

    def _assert_not_ready(self) -> None:
        with self.assertRaises(upload_readiness.ReadinessError):
            self._verify()

    def test_matching_current_archive_listing_and_live_site_are_ready(self) -> None:
        evidence = self._verify()
        self.assertEqual(evidence["release_version"], "9.9.9")
        self.assertEqual(set(evidence["site_sha256"]), {item[0] for item in upload_readiness.SITE_FILES})
        self.assertEqual(len(evidence["archive_sha256"]), 64)

    def test_each_page_requires_one_current_release_marker(self) -> None:
        page = self.repo / "site/index.html"
        for contents in (
            "<!doctype html>\n",
            '<meta name="advisor-release" content="9.9.8">\n',
            '<meta name="advisor-release" content="9.9.9"><meta name="advisor-release" content="9.9.9">\n',
        ):
            with self.subTest(contents=contents):
                original = page.read_bytes()
                page.write_text(contents, encoding="utf-8")
                self._assert_not_ready()
                page.write_bytes(original)

    def test_release_marker_parsing_handles_attribute_order_and_ignores_comments(self) -> None:
        page = self.repo / "site/index.html"
        page.write_text(
            '<!-- <meta name="advisor-release" content="old"> -->\n'
            '<meta content="9.9.9" data-purpose="release" name="advisor-release">\n',
            encoding="utf-8",
        )
        self.live[upload_readiness._expected_url("")] = page.read_bytes()
        self._verify()
        page.write_text(
            '<meta content="9.9.9" name="advisor-release">\n'
            '<meta name="advisor-release" content="9.9.9">\n',
            encoding="utf-8",
        )
        self._assert_not_ready()

    def test_every_html_inventory_entry_requires_a_marker_regardless_of_order(self) -> None:
        extra = ("site/extra/index.html", "extra/")
        reordered = (upload_readiness.SITE_FILES[-1], *reversed(upload_readiness.SITE_FILES[:-1]), extra)
        site = {
            relative: b'<meta name="advisor-release" content="9.9.9">'
            for relative, _remote in reordered
            if relative.endswith(".html")
        }
        with mock.patch.object(upload_readiness, "SITE_FILES", reordered):
            upload_readiness._site_version_evidence(site, "9.9.9")
            site[extra[0]] = b"<!doctype html>"
            with self.assertRaises(upload_readiness.ReadinessError):
                upload_readiness._site_version_evidence(site, "9.9.9")

    def test_listing_version_and_descriptions_fail_closed(self) -> None:
        listing = self.repo / "docs/public-listing.md"
        original = listing.read_text(encoding="utf-8")
        variants = (
            original.replace("9.9.9", "9.9.8", 1),
            original.replace("Useful read-only advice.", ""),
            original.replace("Detailed, publishable information for users.", "TODO"),
            original.replace("| **Version** | `9.9.9` |", "| **Version** | `9.9.9` |\n| **Version** | `9.9.9` |"),
        )
        for value in variants:
            with self.subTest(value=value):
                listing.write_text(value, encoding="utf-8")
                self._assert_not_ready()
                listing.write_text(original, encoding="utf-8")

    def test_listing_sections_stop_at_any_peer_heading_and_reject_duplicates(self) -> None:
        listing = self.repo / "docs/public-listing.md"
        original = listing.read_text(encoding="utf-8")
        variants = (
            original.replace("Useful read-only advice.\n\n### Long", "\n\n### Audience\nPeople\n\n### Long"),
            original + "\n### Short Description\nDuplicate copy.\n",
            original.replace("Detailed, publishable information for users.", "<!-- no actual copy -->\n\n## Support"),
        )
        for value in variants:
            with self.subTest(value=value):
                listing.write_text(value, encoding="utf-8")
                self._assert_not_ready()
        listing.write_text(original, encoding="utf-8")

    def test_changed_archive_or_site_bytes_are_not_ready(self) -> None:
        original = self.archive.read_bytes()
        self.archive.write_bytes(original + b"changed")
        self._assert_not_ready()
        self.archive.write_bytes(original)
        for relative, _url in (upload_readiness.SITE_FILES[0], upload_readiness.SITE_FILES[-1]):
            path = self.repo / relative
            previous = path.read_bytes()
            path.write_bytes(previous + b"changed")
            self._assert_not_ready()
            path.write_bytes(previous)

    def test_missing_or_unchecked_local_asset_is_not_ready(self) -> None:
        asset = self.repo / "site/assets/logo.svg"
        asset.unlink()
        self._assert_not_ready()
        asset.write_bytes(self.live[upload_readiness._expected_url("assets/logo.svg")])
        (self.repo / "site/assets/new.js").write_bytes(b"unexpected")
        self._assert_not_ready()

    def test_http_origin_size_and_timeout_fail_closed(self) -> None:
        cases = (
            lambda url: upload_readiness.FetchResponse(url, 503, b""),
            lambda url: upload_readiness.FetchResponse("https://example.invalid/advisor/", 200, self.live[url]),
            lambda url: upload_readiness.FetchResponse(url, 200, b"x" * (upload_readiness.MAX_SITE_FILE_BYTES + 1)),
            lambda url: (_ for _ in ()).throw(TimeoutError("synthetic timeout")),
        )
        for fetch in cases:
            with self.subTest(fetch=fetch):
                with self.assertRaises(upload_readiness.ReadinessError):
                    upload_readiness.verify_upload_ready(self.repo, self.archive, fetch)

    def test_live_fetch_accepts_whitespace_around_content_length(self) -> None:
        url = upload_readiness._expected_url("")
        body = b"safe bytes"

        class Response:
            status = 200
            headers = {"Content-Length": f"  {len(body)} \t"}

            def __enter__(self):
                return self

            def __exit__(self, *_args):
                return False

            def read(self, _limit):
                return body

            def geturl(self):
                return url

        opener = mock.Mock()
        opener.open.return_value = Response()
        with mock.patch.object(upload_readiness, "build_opener", return_value=opener):
            self.assertEqual(upload_readiness.fetch_live(url), upload_readiness.FetchResponse(url, 200, body))

    def test_live_fetch_exception_names_file_and_expected_url(self) -> None:
        def unavailable(_url: str) -> upload_readiness.FetchResponse:
            raise upload_readiness.ReadinessError("synthetic HTTP failure")

        with self.assertRaises(upload_readiness.ReadinessError) as raised:
            upload_readiness.verify_upload_ready(self.repo, self.archive, unavailable)
        self.assertIn("site/index.html", str(raised.exception))
        self.assertIn(upload_readiness._expected_url(""), str(raised.exception))

    def test_progress_is_visible_and_success_json_keys_are_stable(self) -> None:
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            evidence = self._verify()
        self.assertIn("checking Git-bound plugin inventory", stderr.getvalue())
        self.assertIn("fetching and checking live byte match", stderr.getvalue())
        encoded = json.dumps(evidence, sort_keys=True, separators=(",", ":"))
        self.assertTrue(encoded.startswith('{"archive_sha256"'))

    def test_cli_json_success_and_failure_exit_are_unambiguous(self) -> None:
        evidence = {
            "archive_sha256": "a" * 64,
            "listing_sha256": "b" * 64,
            "long_description_sha256": "c" * 64,
            "release_version": "9.9.9",
            "short_description_sha256": "d" * 64,
            "site_sha256": {},
        }
        stdout = io.StringIO()
        with mock.patch.object(upload_readiness, "verify_upload_ready", return_value=evidence), contextlib.redirect_stdout(stdout):
            self.assertEqual(upload_readiness.main(["--json", "candidate.zip"]), 0)
        self.assertEqual(json.loads(stdout.getvalue()), evidence)

        failure_stdout = io.StringIO()
        stderr = io.StringIO()
        with mock.patch.object(
            upload_readiness, "verify_upload_ready", side_effect=upload_readiness.ReadinessError("synthetic failure")
        ), contextlib.redirect_stdout(failure_stdout), contextlib.redirect_stderr(stderr):
            self.assertEqual(upload_readiness.main(["candidate.zip"]), 1)
        self.assertIn("NOT UPLOAD READY", stderr.getvalue())
        self.assertEqual(failure_stdout.getvalue(), "")


if __name__ == "__main__":
    unittest.main()
