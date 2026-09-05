#!/usr/bin/env python3
"""Create and validate the byte inventory for an Advisor candidate package."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import sys
import tempfile
import zipfile
from dataclasses import dataclass
from typing import Iterable

PLUGIN_PREFIX = "plugins/advisor/"
ARCHIVE_PREFIX = "advisor/"
MANIFEST_PATH = "plugins/advisor/.codex-plugin/plugin.json"
ZIP_TIMESTAMP = (1980, 1, 1, 0, 0, 0)
ZIP_REGULAR_MODE = 0o100644
ZIP_EXECUTABLE_MODE = 0o100755
SENSITIVE_PART = re.compile(r"(?:^|[._-])(?:secret|secrets|credential|credentials|password|private)(?:$|[._-])", re.I)
SENSITIVE_SUFFIXES = (".pem", ".key", ".p12", ".pfx", ".kdbx")


class CandidateError(RuntimeError):
    """A candidate cannot safely be frozen or packaged."""


@dataclass(frozen=True)
class InventoryItem:
    source_relative: str
    archive_name: str
    sha256: str
    size: int
    mode: int


@dataclass(frozen=True)
class CandidateInventory:
    repo: Path
    items: tuple[InventoryItem, ...]
    digest: str
    version: str


def progress(message: str) -> None:
    """Report an operation without contaminating concise machine output."""
    print(f"candidate-inventory: {message}", file=sys.stderr, flush=True)


def _run_git(repo: Path, arguments: list[str]) -> bytes:
    progress("checking Git candidate boundary")
    try:
        completed = subprocess.run(
            ["git", "-C", os.fspath(repo), *arguments], stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15, check=False,
        )
    except FileNotFoundError as error:
        raise CandidateError("Git is required to inventory the candidate") from error
    except subprocess.TimeoutExpired as error:
        raise CandidateError("Git candidate-boundary check timed out") from error
    if completed.returncode:
        raise CandidateError("Git candidate-boundary check failed")
    return completed.stdout


def validate_relative_path(path: str) -> None:
    """Reject names that cannot become safe normalized ZIP entry names."""
    pure = PurePosixPath(path)
    if not path or "\\" in path or pure.is_absolute() or ".." in pure.parts:
        raise CandidateError("candidate contains an unsafe path")
    if any(part in ("", ".") for part in pure.parts):
        raise CandidateError("candidate contains an unsafe path")


def _is_sensitive(path: str) -> bool:
    name = PurePosixPath(path).name.lower()
    return (
        name == ".env" or name.startswith(".env.")
        or name in {"id_rsa", "id_dsa", "id_ecdsa", "id_ed25519", ".npmrc", ".netrc"}
        or name.endswith(SENSITIVE_SUFFIXES) or bool(SENSITIVE_PART.search(name))
    )


def _is_generated(path: str) -> bool:
    parts = [part.lower() for part in PurePosixPath(path).parts]
    name = parts[-1]
    return (
        "__pycache__" in parts or ".cache" in parts or "cache" in parts
        or name == ".ds_store" or name.endswith((".pyc", ".pyo", ".log", ".tmp", ".temp", ".swp"))
        or name.endswith("~") or name in {"temp", "tmp"}
    )


def _tracked_plugin_paths(repo: Path) -> list[tuple[str, str]]:
    progress("enumerating tracked candidate files")
    output = _run_git(repo, ["ls-files", "--stage", "-z", "--", "plugins/advisor"])
    tracked: list[tuple[str, str]] = []
    for record in output.split(b"\0"):
        if not record:
            continue
        try:
            metadata, raw_path = record.split(b"\t", 1)
            mode = metadata.split(b" ", 1)[0].decode("ascii")
            source_relative = raw_path.decode("utf-8", "strict")
        except (UnicodeDecodeError, ValueError) as error:
            raise CandidateError("Git returned an invalid candidate path") from error
        validate_relative_path(source_relative)
        if not source_relative.startswith(PLUGIN_PREFIX):
            raise CandidateError("Git returned a path outside the candidate")
        if mode not in {"100644", "100755"}:
            raise CandidateError("candidate contains a symlink or special file")
        tracked.append((source_relative, mode))
    if not tracked:
        raise CandidateError("candidate has no tracked plugin files")
    return tracked


def _assert_no_untracked_artifacts(repo: Path) -> None:
    output = _run_git(repo, ["status", "--porcelain=v1", "-z", "--untracked-files=all", "--", "plugins/advisor"])
    for record in output.split(b"\0"):
        if not record or not record.startswith(b"?? "):
            continue
        try:
            path = record[3:].decode("utf-8", "strict")
        except UnicodeDecodeError as error:
            raise CandidateError("candidate has an invalid untracked file name") from error
        if _is_sensitive(path):
            raise CandidateError("candidate contains an untracked sensitive filename")
        raise CandidateError("candidate contains an untracked plugin artifact")


def _assert_no_sensitive_filenames(repo: Path) -> None:
    """Reject sensitive names even when a local ignore rule hides the file from Git."""
    candidate_root = repo / "plugins" / "advisor"
    progress("checking sensitive candidate filenames")
    try:
        for directory, directory_names, file_names in os.walk(candidate_root, followlinks=False):
            parent = Path(directory)
            for name in [*directory_names, *file_names]:
                relative = (parent / name).relative_to(candidate_root).as_posix()
                if _is_sensitive(relative):
                    raise CandidateError("candidate contains an excluded sensitive filename")
    except OSError as error:
        raise CandidateError("could not inspect candidate filenames") from error


def _assert_regular_file(repo: Path, source_relative: str) -> Path:
    relative = Path(*PurePosixPath(source_relative).parts)
    candidate_root = (repo / "plugins" / "advisor").resolve()
    current = repo
    for part in relative.parts:
        current /= part
        try:
            file_stat = current.lstat()
        except FileNotFoundError as error:
            raise CandidateError("candidate is missing a tracked file") from error
        if stat.S_ISLNK(file_stat.st_mode):
            raise CandidateError("candidate contains a symlink")
    try:
        resolved = current.resolve(strict=True)
        resolved.relative_to(candidate_root)
    except (FileNotFoundError, ValueError) as error:
        raise CandidateError("candidate contains a path outside its boundary") from error
    if not stat.S_ISREG(current.lstat().st_mode):
        raise CandidateError("candidate contains a special file")
    return current


def _sha256_file(path: Path) -> tuple[str, int]:
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            size += len(chunk)
            digest.update(chunk)
    return digest.hexdigest(), size


def _manifest_version(repo: Path, source_paths: set[str]) -> str:
    if MANIFEST_PATH not in source_paths:
        raise CandidateError("candidate is missing its plugin manifest")
    manifest_path = _assert_regular_file(repo, MANIFEST_PATH)
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise CandidateError("candidate plugin manifest is invalid JSON") from error
    if not isinstance(manifest, dict) or manifest.get("name") != "advisor":
        raise CandidateError("candidate plugin manifest identity is not advisor")
    version = manifest.get("version")
    if not isinstance(version, str) or not version.strip():
        raise CandidateError("candidate plugin manifest has no version")
    return version


def collect_inventory(repo: Path) -> CandidateInventory:
    """Collect every safe, tracked, shippable plugin file from ``repo``."""
    repo = repo.resolve()
    _assert_no_sensitive_filenames(repo)
    _assert_no_untracked_artifacts(repo)
    tracked = _tracked_plugin_paths(repo)
    source_paths = {path for path, _mode in tracked}
    version = _manifest_version(repo, source_paths)
    progress("hashing candidate files")
    items: list[InventoryItem] = []
    for source_relative, git_mode in tracked:
        plugin_relative = source_relative[len(PLUGIN_PREFIX):]
        validate_relative_path(plugin_relative)
        if _is_sensitive(plugin_relative):
            raise CandidateError("candidate contains an excluded sensitive filename")
        source_path = _assert_regular_file(repo, source_relative)
        if _is_generated(plugin_relative):
            continue
        file_hash, size = _sha256_file(source_path)
        zip_mode = ZIP_EXECUTABLE_MODE if git_mode == "100755" else ZIP_REGULAR_MODE
        items.append(InventoryItem(source_relative, ARCHIVE_PREFIX + plugin_relative, file_hash, size, zip_mode))
    items.sort(key=lambda item: item.archive_name.encode("utf-8"))
    if not items:
        raise CandidateError("candidate has no shippable files")
    digest_input = b"".join(
        item.archive_name.encode("utf-8") + b" " + format(item.mode, "o").encode("ascii") + b" "
        + item.sha256.encode("ascii") + b"\n" for item in items
    )
    return CandidateInventory(repo, tuple(items), hashlib.sha256(digest_input).hexdigest(), version)


def inventory_document(inventory: CandidateInventory) -> dict[str, object]:
    return {"digest": inventory.digest, "version": inventory.version, "files": [
        {"name": item.archive_name, "sha256": item.sha256, "size": item.size, "mode": format(item.mode, "06o")}
        for item in inventory.items
    ]}


def write_archive(inventory: CandidateInventory, output: Path) -> None:
    """Write a ZIP with fixed ordering, timestamps, and Unix file modes."""
    progress("writing deterministic candidate archive")
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9, strict_timestamps=True) as archive:
        for item in inventory.items:
            info = zipfile.ZipInfo(item.archive_name, date_time=ZIP_TIMESTAMP)
            info.create_system = 3
            info.external_attr = item.mode << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, (inventory.repo / item.source_relative).read_bytes(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)


def validate_archive(inventory: CandidateInventory, output: Path) -> None:
    """Check ZIP CRC, exact inventory, bytes, and embedded manifest identity."""
    progress("validating archive inventory and CRC")
    expected = [item.archive_name for item in inventory.items]
    try:
        with zipfile.ZipFile(output) as archive:
            entries = archive.infolist()
            if [entry.filename for entry in entries] != expected:
                raise CandidateError("archive inventory differs from candidate inventory")
            if archive.testzip() is not None:
                raise CandidateError("archive CRC validation failed")
            by_name = {item.archive_name: item for item in inventory.items}
            for entry in entries:
                item = by_name[entry.filename]
                if entry.date_time != ZIP_TIMESTAMP or (entry.external_attr >> 16) != item.mode:
                    raise CandidateError("archive does not have deterministic metadata")
                contents = archive.read(entry.filename)
                if len(contents) != item.size or hashlib.sha256(contents).hexdigest() != item.sha256:
                    raise CandidateError("archive bytes differ from candidate inventory")
            manifest = json.loads(archive.read("advisor/.codex-plugin/plugin.json").decode("utf-8"))
    except (OSError, zipfile.BadZipFile, KeyError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise CandidateError("archive validation failed") from error
    if manifest.get("name") != "advisor" or manifest.get("version") != inventory.version:
        raise CandidateError("embedded plugin manifest identity/version mismatch")


def package_candidate(repo: Path, output: Path) -> tuple[CandidateInventory, str, int]:
    """Create a new validated archive without overwriting an existing one."""
    try:
        output_parent = output.parent.resolve(strict=True)
    except OSError as error:
        raise CandidateError("archive parent directory does not exist") from error
    output = output_parent / output.name
    try:
        output.lstat()
    except FileNotFoundError:
        pass
    except OSError as error:
        raise CandidateError("could not inspect archive output") from error
    else:
        raise CandidateError("refusing to overwrite an existing archive")
    if not output_parent.is_dir():
        raise CandidateError("archive parent directory does not exist")
    try:
        output.relative_to((repo / "plugins" / "advisor").resolve())
    except ValueError:
        pass
    else:
        raise CandidateError("archive must be outside the candidate source tree")
    inventory = collect_inventory(repo)
    progress("creating temporary archive")
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{output.name}.", suffix=".tmp", dir=output.parent)
    os.close(descriptor)
    temporary = Path(temporary_name)
    try:
        write_archive(inventory, temporary)
        validate_archive(inventory, temporary)
        progress("hashing archive")
        archive_hash, archive_size = _sha256_file(temporary)
        progress("publishing archive without overwrite")
        try:
            os.link(temporary, output)
        except FileExistsError as error:
            raise CandidateError("refusing to overwrite an existing archive") from error
        except OSError as error:
            raise CandidateError("could not publish candidate archive") from error
        return inventory, archive_hash, archive_size
    finally:
        temporary.unlink(missing_ok=True)


_DIGEST_LINE = re.compile(r"^(?P<prefix>\s*(?:Candidate\s+)?[Cc]ontent\s+[Dd]igest\s*:\s*`)(?P<digest>[0-9a-f]{64})(?P<suffix>`\.\s*)$")
_DIGEST_FIELD = re.compile(r"[Cc]ontent\s+[Dd]igest\s*:")


def release_note_digest(notes: Path) -> str:
    """Return the one strictly formatted candidate digest in release notes."""
    try:
        note_stat = notes.lstat()
    except OSError as error:
        raise CandidateError("could not read release notes") from error
    if stat.S_ISLNK(note_stat.st_mode) or not stat.S_ISREG(note_stat.st_mode):
        raise CandidateError("release notes must be a regular file")
    try:
        lines = notes.read_text(encoding="utf-8").splitlines(keepends=True)
    except OSError as error:
        raise CandidateError("could not read release notes") from error
    fields = [line for line in lines if _DIGEST_FIELD.search(line)]
    if len(fields) != 1:
        raise CandidateError("release notes must contain exactly one content digest field")
    match = _DIGEST_LINE.fullmatch(fields[0].rstrip("\n\r"))
    if not match:
        raise CandidateError("release notes content digest field is malformed")
    return match.group("digest")


def write_release_note_digest(notes: Path, digest: str) -> None:
    """Atomically replace the one valid digest field."""
    if not re.fullmatch(r"[0-9a-f]{64}", digest):
        raise CandidateError("candidate digest is malformed")
    release_note_digest(notes)
    temporary: Path | None = None
    try:
        note_mode = stat.S_IMODE(notes.stat().st_mode)
        text = notes.read_text(encoding="utf-8")
        lines = text.splitlines(keepends=True)
        matching = [index for index, line in enumerate(lines) if _DIGEST_FIELD.search(line)]
        if len(matching) != 1:
            raise CandidateError("release notes must contain exactly one content digest field")
        index = matching[0]
        ending = "\r\n" if lines[index].endswith("\r\n") else "\n" if lines[index].endswith("\n") else ""
        match = _DIGEST_LINE.fullmatch(lines[index].removesuffix(ending))
        if not match:
            raise CandidateError("release notes content digest field is malformed")
        lines[index] = match.group("prefix") + digest + match.group("suffix") + ending
        updated = "".join(lines)
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=notes.parent, delete=False) as handle:
            temporary = Path(handle.name)
            handle.write(updated)
            handle.flush()
            os.fchmod(handle.fileno(), note_mode)
        os.replace(temporary, notes)
        temporary = None
    except OSError as error:
        raise CandidateError("could not update release notes") from error
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def _parse_args(arguments: Iterable[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subcommands = parser.add_subparsers(dest="command", required=True)
    inventory = subcommands.add_parser("inventory")
    inventory.add_argument("--repo", required=True, type=Path)
    inventory.add_argument("--digest", action="store_true")
    inventory.add_argument("--json", action="store_true")
    package = subcommands.add_parser("package")
    package.add_argument("--repo", required=True, type=Path)
    package.add_argument("--output", required=True, type=Path)
    package.add_argument("--json", action="store_true")
    notes = subcommands.add_parser("release-notes")
    notes.add_argument("--notes", required=True, type=Path)
    group = notes.add_mutually_exclusive_group(required=True)
    group.add_argument("--check", action="store_true")
    group.add_argument("--write")
    return parser.parse_args(list(arguments))


def main(arguments: Iterable[str] | None = None) -> int:
    args = _parse_args(sys.argv[1:] if arguments is None else arguments)
    try:
        if args.command == "inventory":
            inventory = collect_inventory(args.repo)
            if args.digest:
                print(inventory.digest)
            elif args.json:
                print(json.dumps(inventory_document(inventory), sort_keys=True, separators=(",", ":")))
            else:
                print(f"digest={inventory.digest} files={len(inventory.items)} version={inventory.version}")
        elif args.command == "package":
            inventory, archive_hash, archive_size = package_candidate(args.repo, args.output)
            result = {"archive": os.fspath(args.output), "bytes": archive_size, "sha256": archive_hash,
                      "candidate_digest": inventory.digest, "files": len(inventory.items), "version": inventory.version}
            if args.json:
                print(json.dumps(result, sort_keys=True, separators=(",", ":")))
            else:
                print(f"archive={result['archive']} bytes={archive_size} sha256={archive_hash} candidate_digest={inventory.digest} files={len(inventory.items)}")
        elif args.check:
            print(release_note_digest(args.notes))
        else:
            write_release_note_digest(args.notes, args.write)
        return 0
    except CandidateError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
