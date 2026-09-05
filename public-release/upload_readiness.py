#!/usr/bin/env python3
"""Fail-closed evidence gate for an Advisor marketplace-upload candidate."""

from __future__ import annotations

import argparse
import hashlib
from html.parser import HTMLParser
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import struct
import sys
from typing import Callable, Iterable, NamedTuple
from urllib.error import HTTPError, URLError
from urllib.parse import urljoin, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener

from candidate_inventory import CandidateError, collect_inventory, validate_archive


PUBLIC_BASE = "https://zerodelta.dev/advisor/"
MAX_SITE_FILE_BYTES = 1024 * 1024
SITE_FILES = (
    ("site/index.html", ""),
    ("site/support/index.html", "support/"),
    ("site/privacy/index.html", "privacy/"),
    ("site/terms/index.html", "terms/"),
    ("site/assets/style.css", "assets/style.css"),
    ("site/assets/logo.svg", "assets/logo.svg"),
    ("site/sitemap.xml", "sitemap.xml"),
)
_DRAFT = re.compile(r"\b(?:TODO|TBD|FIXME|PLACEHOLDER|CHANGEME|LOREM\s+IPSUM|INSERT(?:\s+TEXT)?|DRAFT)\b", re.I)
_VERSION_FIELD = re.compile(r"^\|\s*\*\*Version\*\*\s*\|(?P<value>.*?)\|\s*$", re.M)
_HEADING = re.compile(r"^ {0,3}(?P<marks>#{1,6})[ \t]+(?P<name>.*?)[ \t]*#*[ \t]*$", re.M)


class ReadinessError(RuntimeError):
    """The candidate lacks current, sufficient evidence for an upload."""


class FetchResponse(NamedTuple):
    """Minimal, injectable HTTP response evidence."""

    url: str
    status: int
    body: bytes


def progress(message: str) -> None:
    """Emit visible progress without contaminating JSON output."""
    print(f"upload-readiness: {message}", file=sys.stderr, flush=True)


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _safe_regular(path: Path, description: str) -> None:
    try:
        mode = path.lstat().st_mode
    except OSError as error:
        raise ReadinessError(f"{description} is missing") from error
    if stat.S_ISLNK(mode) or not stat.S_ISREG(mode):
        raise ReadinessError(f"{description} must be a regular file")


def _validate_site_tree(repo: Path) -> dict[str, bytes]:
    """Return the fixed deploy inventory after rejecting unsafe/untracked paths."""
    progress("checking local deployable site inventory")
    root = repo / "site"
    try:
        root_mode = root.lstat().st_mode
    except OSError as error:
        raise ReadinessError("site directory is missing") from error
    if stat.S_ISLNK(root_mode) or not stat.S_ISDIR(root_mode):
        raise ReadinessError("site directory must be a real directory")
    expected = {relative for relative, _remote in SITE_FILES}
    seen: set[str] = set()
    for directory, names, files in os.walk(root, followlinks=False):
        current = Path(directory)
        for name in [*names, *files]:
            path = current / name
            relative = path.relative_to(repo).as_posix()
            pure = PurePosixPath(relative)
            try:
                mode = path.lstat().st_mode
            except OSError as error:
                raise ReadinessError("could not inspect local site path") from error
            if ".." in pure.parts or stat.S_ISLNK(mode):
                raise ReadinessError("local site contains an unsafe path")
            if stat.S_ISDIR(mode):
                continue
            if not stat.S_ISREG(mode):
                raise ReadinessError("local site contains a special file")
            if relative not in expected:
                raise ReadinessError(f"local site file is outside the checked deploy inventory: {relative}")
            if path.stat().st_size > MAX_SITE_FILE_BYTES:
                raise ReadinessError(f"local site file exceeds {MAX_SITE_FILE_BYTES} byte limit: {relative}")
            seen.add(relative)
    if seen != expected:
        missing = sorted(expected - seen)
        raise ReadinessError(f"local checked deploy inventory is incomplete: {', '.join(missing)}")
    return {relative: (repo / relative).read_bytes() for relative, _remote in SITE_FILES}


def _listing_evidence(repo: Path, version: str) -> tuple[bytes, bytes, bytes]:
    progress("checking marketplace listing metadata and descriptions")
    listing = repo / "docs" / "public-listing.md"
    _safe_regular(listing, "public listing")
    try:
        raw = listing.read_bytes()
        text = raw.decode("utf-8")
    except (OSError, UnicodeDecodeError) as error:
        raise ReadinessError("public listing cannot be read as UTF-8") from error
    fields = list(_VERSION_FIELD.finditer(text))
    if len(fields) != 1:
        raise ReadinessError("public listing must contain exactly one Version metadata field")
    listed = fields[0].group("value").strip().strip("`").strip()
    if listed != version:
        raise ReadinessError("public listing Version metadata does not match the plugin manifest")
    headings = list(_HEADING.finditer(text))
    bodies: dict[str, bytes] = {}
    required = {"Short Description", "Long Description"}
    selected = [heading for heading in headings if len(heading.group("marks")) == 3 and heading.group("name") in required]
    if len(selected) != 2 or {heading.group("name") for heading in selected} != required:
        raise ReadinessError("public listing must contain exactly one Short Description and Long Description heading")
    for heading in selected:
        end = next(
            (candidate.start() for candidate in headings if candidate.start() > heading.start() and len(candidate.group("marks")) <= 3),
            len(text),
        )
        body = text[heading.end():end].strip()
        visible = re.sub(r"<!--.*?-->", "", body, flags=re.S).strip()
        if not visible or _DRAFT.search(visible):
            raise ReadinessError(f"public listing {heading.group('name')} is missing, empty, or draft text")
        bodies[heading.group("name")] = visible.encode("utf-8")
    return raw, bodies["Short Description"], bodies["Long Description"]


class _ReleaseMarkerParser(HTMLParser):
    """Collect structurally valid Advisor release markers from actual meta tags."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.markers: list[str] = []
        self.malformed = False

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag.lower() != "meta":
            return
        names = [value for key, value in attrs if key.lower() == "name" and value is not None]
        if not any(value.strip().lower() == "advisor-release" for value in names):
            return
        contents = [value for key, value in attrs if key.lower() == "content" and value is not None]
        if len(names) != 1 or len(contents) != 1:
            self.malformed = True
            return
        self.markers.append(contents[0].strip())


def _site_version_evidence(site: dict[str, bytes], version: str) -> None:
    for relative, _remote in SITE_FILES:
        if Path(relative).suffix.lower() != ".html":
            continue
        try:
            text = site[relative].decode("utf-8")
        except UnicodeDecodeError as error:
            raise ReadinessError(f"site version marker page is not UTF-8: {relative}") from error
        parser = _ReleaseMarkerParser()
        parser.feed(text)
        parser.close()
        if parser.malformed or parser.markers != [version]:
            raise ReadinessError(f"site page must contain exactly one matching advisor-release marker: {relative}")


class _NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):  # type: ignore[no-untyped-def]
        return None


def fetch_live(url: str) -> FetchResponse:
    """Fetch one exact public URL with bounded bytes and redirects disabled."""
    progress(f"fetching live evidence {url}")
    request = Request(url, headers={"Cache-Control": "no-cache", "Pragma": "no-cache", "User-Agent": "advisor-upload-readiness/1"})
    try:
        with build_opener(_NoRedirect()).open(request, timeout=10) as response:
            length = response.headers.get("Content-Length")
            normalized_length = length.strip() if length is not None else None
            if normalized_length is not None and (
                not normalized_length.isdigit() or int(normalized_length) > MAX_SITE_FILE_BYTES
            ):
                raise ReadinessError("live response exceeds byte limit")
            body = response.read(MAX_SITE_FILE_BYTES + 1)
            if len(body) > MAX_SITE_FILE_BYTES:
                raise ReadinessError("live response exceeds byte limit")
            return FetchResponse(response.geturl(), response.status, body)
    except HTTPError as error:
        raise ReadinessError(f"live request returned HTTP {error.code}") from error
    except (URLError, OSError, TimeoutError) as error:
        raise ReadinessError("live request failed") from error


def _expected_url(remote: str) -> str:
    url = urljoin(PUBLIC_BASE, remote)
    parsed = urlsplit(url)
    base = urlsplit(PUBLIC_BASE)
    if parsed.scheme != "https" or parsed.netloc != base.netloc or not parsed.path.startswith(base.path):
        raise ReadinessError("internal public URL construction failed")
    return url


def _assert_archive_has_no_trailing_bytes(archive_bytes: bytes) -> None:
    """Reject data appended after the conventional end-of-central-directory record."""
    marker = b"PK\x05\x06"
    position = archive_bytes.rfind(marker)
    if position < 0 or len(archive_bytes) < position + 22:
        raise ReadinessError("candidate archive has no valid end record")
    comment_size = struct.unpack_from("<H", archive_bytes, position + 20)[0]
    if position + 22 + comment_size != len(archive_bytes):
        raise ReadinessError("candidate archive has unexpected trailing bytes")


def verify_upload_ready(repo: Path, archive: Path, fetch: Callable[[str], FetchResponse] = fetch_live) -> dict[str, object]:
    """Produce current evidence that a precise local archive is safe to upload."""
    repo = repo.resolve()
    progress("checking Git-bound plugin inventory and archive")
    inventory = collect_inventory(repo)
    _safe_regular(archive, "candidate archive")
    try:
        validate_archive(inventory, archive)
        archive_bytes = archive.read_bytes()
    except (CandidateError, OSError) as error:
        raise ReadinessError("candidate archive does not exactly match the current Git-bound plugin inventory") from error
    _assert_archive_has_no_trailing_bytes(archive_bytes)
    listing, short, long = _listing_evidence(repo, inventory.version)
    site = _validate_site_tree(repo)
    _site_version_evidence(site, inventory.version)
    site_hashes: dict[str, str] = {}
    for relative, remote in SITE_FILES:
        expected_url = _expected_url(remote)
        progress(f"fetching and checking live byte match for {relative}")
        try:
            response = fetch(expected_url)
        except (ReadinessError, OSError, TimeoutError) as error:
            raise ReadinessError(f"live evidence request failed for {relative} at {expected_url}") from error
        if response.status != 200 or response.url != expected_url:
            raise ReadinessError(f"live evidence did not remain at the expected HTTPS origin/path: {relative}")
        if len(response.body) > MAX_SITE_FILE_BYTES:
            raise ReadinessError(f"live evidence exceeds the byte limit: {relative}")
        local = site[relative]
        if response.body != local:
            raise ReadinessError(f"live bytes differ from local deployable file: {relative}")
        site_hashes[relative] = _sha256(local)
    return {
        "archive_sha256": _sha256(archive_bytes),
        "listing_sha256": _sha256(listing),
        "long_description_sha256": _sha256(long),
        "release_version": inventory.version,
        "short_description_sha256": _sha256(short),
        "site_sha256": site_hashes,
    }


def _arguments(arguments: Iterable[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="emit the successful evidence object as JSON")
    parser.add_argument("archive", type=Path, help="exact candidate ZIP to check immediately before owner upload")
    return parser.parse_args(list(arguments))


def main(arguments: Iterable[str] | None = None) -> int:
    args = _arguments(sys.argv[1:] if arguments is None else arguments)
    repo = Path(__file__).resolve().parent.parent
    archive = args.archive if args.archive.is_absolute() else Path.cwd() / args.archive
    try:
        evidence = verify_upload_ready(repo, archive.absolute())
    except (CandidateError, ReadinessError) as error:
        print(f"NOT UPLOAD READY: {error}", file=sys.stderr)
        return 1
    if args.json:
        print(json.dumps(evidence, sort_keys=True, separators=(",", ":")))
    else:
        print(f"UPLOAD READY: version {evidence['release_version']} archive {evidence['archive_sha256']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
