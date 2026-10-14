"""Record and verify every tracked file in every local upstream Git tag.

Usage: python tool/catalog_driver_fingerprints.py UPSTREAM_REPOSITORY [--check]
Only Git blobs are read; the upstream checkout is never modified and DLLs are
never executed. Requires Python 3.10+ and Git, with no third-party packages.
"""

import argparse
import hashlib
import json
import re
import subprocess
from collections import defaultdict
from pathlib import Path, PurePosixPath


PROXIES = {
    "version.dll", "winmm.dll", "dbghelp.dll", "dinput8.dll",
    "dxgi.dll", "d3d12.dll", "winhttp.dll",
}
PROJECT = Path(__file__).resolve().parent.parent
MANIFEST = PROJECT / "driver-fingerprints.json"


def git(repository, *arguments):
    return subprocess.check_output(["git", "-C", str(repository), *arguments])


def version_key(version):
    match = re.fullmatch(r"[vV]?(\d+)\.(\d+)(?:\.(\d+))?(?:-([0-9A-Za-z.-]+))?(?:\+([0-9A-Za-z.-]+))?", version)
    if not match:
        raise ValueError(f"Invalid release version: {version}")
    numbers = tuple(int(match[index] or 0) for index in (1, 2, 3))
    prerelease = tuple((0, int(part)) if part.isdigit() else (1, part) for part in (match[4] or "").split('.') if part)
    return numbers, not bool(match[4]), prerelease


def proxy_version(tag, path):
    parts = PurePosixPath(path).parts
    if parts[-1].lower() not in PROXIES:
        return None
    if parts[0] == "archive" and len(parts) >= 3:
        version = parts[1]
    elif parts[0] in {"alternatives", "altnative", "310.1"} or len(parts) == 1:
        version = tag
    else:
        return None
    version_key(version)
    return version.removeprefix("v").removeprefix("V")


def read_blobs(repository, objects):
    fingerprints = {}
    with subprocess.Popen(
        ["git", "-C", str(repository), "cat-file", "--batch"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE,
    ) as process:
        for oid, expected_size in sorted(objects.items()):
            process.stdin.write((oid + "\n").encode("ascii"))
            process.stdin.flush()
            header = process.stdout.readline().decode("ascii").strip().split()
            if header != [oid, "blob", str(expected_size)]:
                raise ValueError(f"Unexpected Git blob: {header}")
            sha256 = hashlib.sha256()
            sha1 = hashlib.sha1(f"blob {expected_size}\0".encode("ascii"))
            remaining = expected_size
            prefix = b""
            while remaining:
                chunk = process.stdout.read(min(1024 * 1024, remaining))
                if not chunk:
                    raise ValueError(f"Truncated Git blob: {oid}")
                if not prefix:
                    prefix = chunk[:64]
                sha256.update(chunk)
                sha1.update(chunk)
                remaining -= len(chunk)
            if process.stdout.read(1) != b"\n" or sha1.hexdigest() != oid:
                raise ValueError(f"Git blob integrity check failed: {oid}")
            fingerprints[oid] = {"sha256": sha256.hexdigest(), "pe": prefix.startswith(b"MZ")}
        process.stdin.close()
        if process.wait() != 0:
            raise RuntimeError("git cat-file failed")
    return fingerprints


def catalog(repository):
    source = git(repository, "remote", "get-url", "origin").decode().strip()
    tags = git(repository, "tag", "--list").decode().splitlines()
    if not tags:
        raise ValueError("The upstream repository has no tags")
    tags.sort(key=version_key)
    releases = []
    objects = {}
    for tag in tags:
        commit = git(repository, "rev-parse", f"refs/tags/{tag}^{{commit}}").decode().strip()
        tag_object = git(repository, "rev-parse", f"refs/tags/{tag}").decode().strip()
        files = []
        for entry in git(repository, "ls-tree", "-r", "-l", "-z", commit).split(b"\0"):
            if not entry:
                continue
            metadata, raw_path = entry.split(b"\t", 1)
            mode, kind, oid, size = metadata.decode("ascii").split()
            if kind != "blob":
                raise ValueError(f"Unsupported tracked object in {tag}: {raw_path!r}")
            path = raw_path.decode("utf-8")
            size = int(size)
            if oid in objects and objects[oid] != size:
                raise ValueError(f"Inconsistent Git object size: {oid}")
            objects[oid] = size
            files.append({"path": path, "mode": mode, "git_blob": oid, "size": size})
        releases.append({"tag": tag, "tag_object": tag_object, "commit": commit, "files": files})

    blobs = read_blobs(repository, objects)
    proxy_versions = defaultdict(set)
    runtime_fingerprints = defaultdict(dict)
    for release in releases:
        for file in release["files"]:
            blob = blobs[file["git_blob"]]
            file["sha256"] = blob["sha256"]
            version = proxy_version(release["tag"], file["path"])
            if version is not None:
                if file["mode"] not in {"100644", "100755"} or not blob["pe"]:
                    raise ValueError(f"Proxy is not an actual PE DLL: {release['tag']}:{file['path']}")
                file["proxy_version"] = version
                proxy_versions[file["sha256"]].add(version)
            parts = PurePosixPath(file["path"]).parts
            if parts[0] == 'dlssg_sm86':
                runtime_version, relative = release['tag'].lstrip('vV'), file['path']
            elif len(parts) > 3 and parts[0] == 'archive' and parts[2] == 'dlssg_sm86':
                runtime_version, relative = parts[1].lstrip('vV'), '/'.join(parts[2:])
            else:
                continue
            previous = runtime_fingerprints[runtime_version].get(relative)
            if previous and previous != file['sha256']:
                raise ValueError(f"Conflicting runtime bytes for {runtime_version}:{relative}")
            runtime_fingerprints[runtime_version][relative] = file['sha256']

    ambiguous = {digest: sorted(versions, key=version_key) for digest, versions in proxy_versions.items() if len(versions) > 1}
    manifest = {
        "schema_version": 2,
        "source_repository": source,
        "hash_algorithm": "SHA-256",
        "git_object_integrity": "SHA-1 of blob header and bytes verified against each tree entry",
        "tag_count": len(releases),
        "file_count": sum(len(release["files"]) for release in releases),
        "unique_blob_count": len(blobs),
        "proxy_fingerprint_count": len(proxy_versions),
        "ambiguous_proxy_fingerprints": ambiguous,
        "runtime_fingerprints": dict(sorted(runtime_fingerprints.items(), key=lambda item: version_key(item[0]))),
        "tags": releases,
    }
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repository", type=Path)
    parser.add_argument("--check", action="store_true", help="Recompute all hashes and compare without writing files")
    args = parser.parse_args()
    manifest = catalog(args.repository.resolve())
    content = json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"
    if args.check:
        actual = MANIFEST.read_text(encoding="utf-8") if MANIFEST.exists() else None
        if actual != content:
            raise ValueError(f"Generated catalog is missing or stale: {MANIFEST}")
    else:
        MANIFEST.parent.mkdir(parents=True, exist_ok=True)
        MANIFEST.write_text(content, encoding="utf-8", newline="\n")
    print(f"Verified {manifest['tag_count']} tags, {manifest['file_count']} files, "
          f"{manifest['unique_blob_count']} unique Git blobs and {manifest['proxy_fingerprint_count']} proxy fingerprints.")
    for release in manifest["tags"]:
        proxies = [file for file in release["files"] if "proxy_version" in file]
        print(f"{release['tag']}: {len(release['files'])} files, {len(proxies)} proxy DLLs, commit {release['commit']}")
    print(f"Catalog {'verified' if args.check else 'generated'}; {len(manifest['ambiguous_proxy_fingerprints'])} shared proxy fingerprints retained as version candidates.")


if __name__ == "__main__":
    main()
