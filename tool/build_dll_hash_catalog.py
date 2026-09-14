#!/usr/bin/env python3
"""Build a deterministic DLL SHA-256 catalog from every reachable Git commit.

The input is a normal clone or a mirror.  A mirror is preferred in CI because
it contains every branch and tag, including refs that are not reachable from
the default branch.
"""

from __future__ import annotations

import argparse
import datetime as dt
import fnmatch
import hashlib
import json
import subprocess
from collections.abc import Iterable
from pathlib import Path


SCHEMA_VERSION = 2


def git(repo: Path, *args: str, text: bool = True) -> str | bytes:
    completed = subprocess.run(
        ["git", "-C", str(repo), *args],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=text,
    )
    return completed.stdout


def commits(repo: Path) -> list[str]:
    # --all deliberately includes all mirrored remote branches and tags.
    return str(git(repo, "rev-list", "--all", "--reverse")).splitlines()


def dll_blobs(repo: Path, commit: str) -> Iterable[tuple[str, str]]:
    tree = git(repo, "ls-tree", "-r", "-z", "--full-tree", commit, text=False)
    assert isinstance(tree, bytes)
    for entry in tree.split(b"\0"):
        if not entry:
            continue
        metadata, raw_path = entry.split(b"\t", 1)
        _mode, kind, object_id = metadata.split(b" ", 2)
        if kind != b"blob" or not raw_path.lower().endswith(b".dll"):
            continue
        # Git paths are byte strings; surrogateescape preserves unusual names
        # while keeping the output valid JSON.
        yield raw_path.decode("utf-8", "surrogateescape"), object_id.decode()


def sha256_blob(repo: Path, object_id: str) -> str:
    content = git(repo, "cat-file", "blob", object_id, text=False)
    assert isinstance(content, bytes)
    return hashlib.sha256(content).hexdigest()


def build_catalog(
    repo: Path,
    latest_path_patterns: list[str] | None = None,
    head_ref: str = "refs/heads/main",
) -> dict[str, object]:
    history = commits(repo)
    if not history:
        raise RuntimeError("The source repository has no reachable commits")
    head = str(git(repo, "rev-parse", f"{head_ref}^{{commit}}")).strip()
    if head not in history:
        raise RuntimeError("HEAD is not part of the mirrored history")

    blob_hashes: dict[str, str] = {}
    records: dict[tuple[str, str], dict[str, object]] = {}
    for commit in history:
        for path, blob in dll_blobs(repo, commit):
            digest = blob_hashes.get(blob)
            if digest is None:
                digest = sha256_blob(repo, blob)
                blob_hashes[blob] = digest
            record = records.setdefault(
                (path, digest),
                {
                    "path": path,
                    "file_name": path.rsplit("/", 1)[-1],
                    "sha256": digest,
                    "commits": [],
                },
            )
            cast_commits = record["commits"]
            assert isinstance(cast_commits, list)
            cast_commits.append(commit)

    def is_latest_path(path: str) -> bool:
        return latest_path_patterns is None or any(
            fnmatch.fnmatchcase(path, pattern) for pattern in latest_path_patterns
        )

    latest_pairs = set()
    for path, blob in dll_blobs(repo, head):
        if not is_latest_path(path):
            continue
        digest = blob_hashes.get(blob)
        if digest is None:
            digest = sha256_blob(repo, blob)
            blob_hashes[blob] = digest
        latest_pairs.add((path, digest))
    if not latest_pairs:
        raise RuntimeError("No DLLs in HEAD matched --latest-path")
    latest_hashes = {digest for _path, digest in latest_pairs}
    latest_files = [records[pair] for pair in sorted(latest_pairs)]
    historical_files = [
        record
        for (_path, digest), record in sorted(records.items())
        if digest not in latest_hashes
    ]

    # Retain a flat lookup for clients that only need "is this a known DLL?".
    all_files = latest_files + historical_files
    hashes = {str(item["sha256"]): str(item["file_name"]) for item in all_files}
    return {
        "schema_version": SCHEMA_VERSION,
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
        "source": {
            "repository": "https://github.com/sdli1995/dlssg_for_sm86",
            "head_commit": head,
            "commits_scanned": len(history),
            "latest_path_patterns": latest_path_patterns,
        },
        "latest": {"commit": head, "files": latest_files},
        "historical": {"files": historical_files},
        "hashes": dict(sorted(hashes.items())),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument(
        "--head-ref",
        default="refs/heads/main",
        help="Ref used as the current upstream version (default: refs/heads/main)",
    )
    parser.add_argument(
        "--latest-path",
        action="append",
        help="Glob for a current runtime DLL path; repeat to include several paths",
    )
    args = parser.parse_args()
    catalog = build_catalog(args.repo, args.latest_path, args.head_ref)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
