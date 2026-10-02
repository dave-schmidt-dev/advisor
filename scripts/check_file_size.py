"""Warn about large source files and enforce the repository line ceiling."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import sys


DEFAULT_TARGET = 500
DEFAULT_MAX_LINES = 800
DEFAULT_EXCEPTIONS_PATH = ".file-size-exceptions"
CHECKED_SUFFIXES = (".py", ".sh", ".js")


def count_lines(contents: bytes) -> int:
    """Return the number of lines in *contents* without decoding it."""
    if not contents:
        return 0
    return contents.count(b"\n") + (not contents.endswith(b"\n"))


def applies_to(path: str) -> bool:
    """Return whether *path* is covered by this repository's file-size rule."""
    return path.endswith(CHECKED_SUFFIXES)


def parse_exceptions(contents: bytes, source: str) -> tuple[dict[str, str], list[str]]:
    """Parse exception *contents* and return entries with format errors."""
    try:
        text = contents.decode()
    except UnicodeDecodeError:
        return {}, [f"{source}: exceptions file must be UTF-8"]

    entries: dict[str, str] = {}
    seen_paths: set[str] = set()
    errors: list[str] = []
    for line_number, raw_line in enumerate(text.splitlines(), start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split(maxsplit=1)
        path = fields[0]
        if path in seen_paths:
            errors.append(f"{source}:{line_number}: duplicate exception path {path}")
            continue
        seen_paths.add(path)
        if len(fields) == 1 or not fields[1].strip():
            errors.append(f"{source}:{line_number}: exception entry needs a reason")
            continue
        second_token = fields[1].split(maxsplit=1)[0]
        if second_token.isdigit():
            errors.append(
                f"{source}:{line_number}: line caps are no longer supported; remove the cap"
            )
            continue
        entries[path] = fields[1].strip()
    return entries, errors


def run_git(arguments: list[str]) -> tuple[bytes | None, str | None]:
    """Run Git with *arguments*, returning stdout or a diagnostic error."""
    result = subprocess.run(["git", *arguments], capture_output=True, check=False)
    if result.returncode == 0:
        return result.stdout, None
    detail = result.stderr.decode(errors="replace").strip()
    return None, detail or f"git {' '.join(arguments)} failed"


def index_blob(path: str) -> tuple[bytes | None, str | None]:
    """Return the indexed blob for *path*, or a diagnostic when it is absent."""
    return run_git(["cat-file", "blob", f":{path}"])


def indexed_paths(
    exceptions_path: str = DEFAULT_EXCEPTIONS_PATH,
) -> tuple[list[str], set[str], list[str]]:
    """Return checked paths and the changed paths eligible for legacy notices."""
    changed_paths, error = run_git(["diff", "--cached", "--name-only", "-z", "--diff-filter=ACMR"])
    if error:
        return [], set(), [error]
    staged_paths = {os.fsdecode(path) for path in changed_paths.split(b"\0") if path}
    changed, error = run_git(["diff", "--cached", "--name-only", "--", exceptions_path])
    if error:
        return [], set(), [error]
    if not changed:
        return sorted(staged_paths), staged_paths, []
    output, error = run_git(["ls-files", "-z"])
    if error:
        return [], set(), [error]
    return [os.fsdecode(path) for path in output.split(b"\0") if path], staged_paths, []


def all_paths() -> tuple[list[str], list[str]]:
    """Return all tracked and non-ignored working-tree paths."""
    output, error = run_git(["ls-files", "-z", "-co", "--exclude-standard"])
    if error:
        return [], [error]
    return [os.fsdecode(path) for path in output.split(b"\0") if path], []


def working_exceptions(path: str) -> tuple[dict[str, str], list[str]]:
    """Load exceptions from the working tree, if present."""
    exception_path = Path(path)
    if not exception_path.exists():
        return {}, []
    try:
        return parse_exceptions(exception_path.read_bytes(), path)
    except OSError as error:
        return {}, [f"{path}: {error}"]


def staged_exceptions(
    exceptions_path: str = DEFAULT_EXCEPTIONS_PATH,
) -> tuple[dict[str, str], list[str]]:
    """Load exceptions from the index, treating an absent blob as no entries."""
    contents, error = index_blob(exceptions_path)
    if error:
        return {}, []
    return parse_exceptions(contents, exceptions_path)


def check_files(
    paths: list[str],
    exceptions: dict[str, str],
    target: int,
    max_lines: int,
    exceptions_path: str,
    staged: bool,
    legacy_notice_paths: set[str],
) -> list[str]:
    """Check *paths* and return every ceiling violation."""
    errors: list[str] = []
    for path in paths:
        if not applies_to(path):
            continue
        if staged:
            contents, error = index_blob(path)
            if error:
                errors.append(f"{path}: unable to read staged blob: {error}")
                continue
        else:
            file_path = Path(path)
            if not file_path.is_file():
                continue
            try:
                contents = file_path.read_bytes()
            except OSError as error:
                errors.append(f"{path}: {error}")
                continue

        line_count = count_lines(contents)
        exception = exceptions.get(path)
        if target < line_count <= max_lines:
            print(
                f"file-size: {path} has {line_count} lines (target {target}); "
                "split it when a clean seam exists"
            )
        if line_count > max_lines and exception is None:
            errors.append(
                f"file-size: {path} has {line_count} lines (maximum {max_lines}); "
                f"add a reasoned entry to {exceptions_path}"
            )
        elif (
            path in legacy_notice_paths
            and line_count > max_lines
            and exception is not None
            and exception.startswith("legacy ")
        ):
            print(
                f"file-size: {path} is a legacy exception ({line_count} lines); "
                "extract a clean seam from it in this piece of work"
            )
        elif exception is not None and line_count <= max_lines:
            print(
                f"file-size: {path} has {line_count} lines (at or under {max_lines}); "
                f"remove its exception from {exceptions_path}"
            )
    return errors


def parse_arguments(arguments: list[str]) -> argparse.Namespace:
    """Parse command-line *arguments* for the file-size checker."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", type=int, default=DEFAULT_TARGET)
    parser.add_argument("--max-lines", type=int, default=DEFAULT_MAX_LINES)
    parser.add_argument("--exceptions", default=DEFAULT_EXCEPTIONS_PATH)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--staged", action="store_true")
    modes.add_argument("--all", action="store_true")
    parser.add_argument("files", metavar="FILE", nargs="*")
    options = parser.parse_args(arguments)
    if (options.staged or options.all) == bool(options.files):
        parser.error("provide exactly one of --staged, --all, or FILE arguments")
    return options


def main(arguments: list[str] | None = None) -> int:
    """Check the selected files from *arguments* and return an exit status."""
    options = parse_arguments(sys.argv[1:] if arguments is None else arguments)
    errors: list[str] = []
    if options.target <= 0:
        errors.append("--target must be a positive integer")
    if options.max_lines <= 0:
        errors.append("--max-lines must be a positive integer")

    if options.staged:
        paths, legacy_notice_paths, path_errors = indexed_paths(options.exceptions)
        exceptions, exception_errors = staged_exceptions(options.exceptions)
        errors.extend(path_errors)
        errors.extend(exception_errors)
        errors.extend(
            check_files(
                paths,
                exceptions,
                options.target,
                options.max_lines,
                options.exceptions,
                True,
                legacy_notice_paths,
            )
        )
    else:
        paths, path_errors = all_paths() if options.all else (options.files, [])
        exceptions, exception_errors = working_exceptions(options.exceptions)
        errors.extend(path_errors)
        errors.extend(exception_errors)
        errors.extend(
            check_files(
                paths,
                exceptions,
                options.target,
                options.max_lines,
                options.exceptions,
                False,
                set(paths) if not options.all else set(),
            )
        )

    for error in errors:
        print(error, file=sys.stderr)
    return int(bool(errors))


if __name__ == "__main__":
    raise SystemExit(main())
