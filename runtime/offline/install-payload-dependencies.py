#!/usr/bin/env python3
"""Resolve hash-pinned payload dependencies from project or IDE-local files only."""
from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import os
import re
import shutil
import stat
import tarfile
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path, PurePosixPath
from typing import Any

MAX_PACKAGES = 64
MAX_EXTRACT_BYTES = 512 * 1024 * 1024
MAX_MEMBER_BYTES = 256 * 1024 * 1024
MAX_ARCHIVE_BYTES = 1024 * 1024 * 1024


def fail(message: str) -> None:
    raise RuntimeError(message)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def safe_relative(value: Any, label: str, allow_glob: bool = False) -> str:
    if not isinstance(value, str) or not value or "\\" in value or chr(0) in value:
        fail(f"{label} must be a non-empty POSIX relative path")
    raw_parts = value.split("/")
    path = PurePosixPath(value)
    if path.is_absolute() or any(part in ("", ".", "..") for part in raw_parts):
        fail(f"{label} escapes its declared root: {value}")
    if ":" in value or (not allow_glob and any(char in value for char in "*?[]")):
        fail(f"{label} contains unsupported path characters: {value}")
    return path.as_posix()


def ensure_no_links(root: Path, relative: str | None = None) -> Path:
    absolute_root = Path(os.path.abspath(root))
    current = Path(absolute_root.anchor)
    for segment in absolute_root.parts[1:]:
        current /= segment
        if current.is_symlink():
            fail(f"Refusing a path through a symbolic link: {current}")
    target = absolute_root
    if relative:
        for segment in PurePosixPath(relative).parts:
            target /= segment
            if target.is_symlink():
                fail(f"Refusing a path through a symbolic link: {target}")
    return target


def resolve_scoped(scope: str, relative: str, roots: dict[str, Path], label: str) -> Path:
    if scope not in roots:
        fail(f"{label} scope must be project or ide")
    safe = safe_relative(relative, label)
    root = ensure_no_links(roots[scope])
    candidate = ensure_no_links(root, safe)
    try:
        candidate.relative_to(root)
    except ValueError as exc:
        raise RuntimeError(f"{label} escapes its root") from exc
    return candidate


def validate_member(name: str) -> str:
    if not isinstance(name, str) or not name or "\\" in name or chr(0) in name:
        fail("Archive contains an invalid member path")
    path = PurePosixPath(name)
    if path.is_absolute() or any(part in ("", ".", "..") for part in name.split("/")) or ":" in name:
        fail(f"Archive member escapes its root: {name}")
    return path.as_posix()


def verify_package_tree(root: Path, package: dict[str, Any]) -> None:
    for field in ("binDirs", "includeDirs", "libraryDirs"):
        values = package.get(field, [])
        if not isinstance(values, list):
            fail(f"{package['id']}.{field} must be a list")
        for value in values:
            relative = safe_relative(value, f"{package['id']}.{field}")
            if not ensure_no_links(root, relative).is_dir():
                fail(f"Required dependency directory is missing: {root / relative}")
    required = package.get("requiredFiles", [])
    if not isinstance(required, list):
        fail(f"{package['id']}.requiredFiles must be a list")
    for value in required:
        relative = safe_relative(value, f"{package['id']}.requiredFiles")
        if not ensure_no_links(root, relative).is_file():
            fail(f"Required dependency file is missing: {root / relative}")
    executables = package.get("executableFiles", [])
    if not isinstance(executables, list):
        fail(f"{package['id']}.executableFiles must be a list")
    for value in executables:
        relative = safe_relative(value, f"{package['id']}.executableFiles")
        executable = ensure_no_links(root, relative)
        if not executable.is_file() or not os.access(executable, os.X_OK):
            fail(f"Required executable dependency is missing or not executable: {root / relative}")


def extract_archive(archive: Path, package: dict[str, Any], destination: Path) -> list[dict[str, Any]]:
    source = package["source"]
    prefix = source.get("prefix", "")
    prefix = safe_relative(prefix, f"{package['id']}.source.prefix") if prefix else ""
    patterns = package.get("files")
    if not isinstance(patterns, list) or not patterns:
        fail(f"Package {package['id']} must declare archive file patterns")
    patterns = [safe_relative(item, f"{package['id']}.files", allow_glob=True) for item in patterns]
    selected: dict[str, tuple[int, Any, int]] = {}
    total = 0

    def consider(name: str, size: int, kind: str, mode: int, opener: Any) -> None:
        nonlocal total
        clean = validate_member(name)
        if prefix:
            if not clean.startswith(prefix + "/"):
                return
            clean = clean[len(prefix) + 1:]
        if not any(fnmatch.fnmatchcase(clean, pattern) for pattern in patterns):
            return
        if kind != "file":
            fail(f"Selected archive member is not a regular file: {name}")
        if clean in selected:
            fail(f"Archive contains a duplicate selected path: {clean}")
        if size < 0 or size > MAX_MEMBER_BYTES:
            fail(f"Selected archive member exceeds the size limit: {clean}")
        total += size
        if total > MAX_EXTRACT_BYTES:
            fail(f"Package {package['id']} exceeds the extraction size limit")
        # Keep ordinary permission bits only; archive setuid/sticky bits are never honored.
        selected[clean] = (size, opener, (mode & 0o777) & ~0o022)

    if zipfile.is_zipfile(archive):
        with zipfile.ZipFile(archive) as bundle:
            for entry in bundle.infolist():
                name = entry.filename.rstrip("/")
                if not name or entry.is_dir():
                    continue
                mode = (entry.external_attr >> 16) & 0xFFFF
                file_type = stat.S_IFMT(mode)
                kind = "link" if stat.S_ISLNK(mode) else "other" if file_type not in (0, stat.S_IFREG) else "file"
                consider(entry.filename, entry.file_size, kind, mode, lambda e=entry: bundle.open(e, "r"))
            for relative, (_, opener, mode) in selected.items():
                target = destination.joinpath(*PurePosixPath(relative).parts)
                target.parent.mkdir(parents=True, exist_ok=True)
                with opener() as source_stream, target.open("xb") as target_stream:
                    shutil.copyfileobj(source_stream, target_stream)
                os.chmod(target, mode or 0o644)
    else:
        try:
            bundle = tarfile.open(archive, "r:*")
        except (tarfile.TarError, OSError) as exc:
            raise RuntimeError(f"Unsupported dependency archive: {archive}") from exc
        with bundle:
            for entry in bundle:
                if entry.isdir():
                    continue
                kind = "file" if entry.isfile() else "link" if entry.issym() or entry.islnk() else "other"
                consider(entry.name, entry.size, kind, entry.mode if entry.isfile() else 0, lambda e=entry, b=bundle: b.extractfile(e))
            for relative, (_, opener, mode) in selected.items():
                target = destination.joinpath(*PurePosixPath(relative).parts)
                target.parent.mkdir(parents=True, exist_ok=True)
                stream = opener()
                if stream is None:
                    fail(f"Could not read selected archive member: {relative}")
                with stream, target.open("xb") as target_stream:
                    shutil.copyfileobj(stream, target_stream)
                os.chmod(target, mode or 0o644)
    if not selected:
        fail(f"No files selected from dependency archive for {package['id']}")
    executable_files = package.get("executableFiles", [])
    if not isinstance(executable_files, list):
        fail(f"{package['id']}.executableFiles must be a list")
    for value in executable_files:
        relative = safe_relative(value, f"{package['id']}.executableFiles")
        if relative not in selected:
            fail(f"Executable dependency file is not selected from the archive: {relative}")
        target = destination.joinpath(*PurePosixPath(relative).parts)
        os.chmod(target, stat.S_IMODE(target.stat().st_mode) | 0o111)
    return [{"path": name, "sha256": sha256_file(destination.joinpath(*PurePosixPath(name).parts))} for name in sorted(selected)]


def package_hash(package: dict[str, Any]) -> str:
    return hashlib.sha256(json.dumps(package, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()


def download_archive(url: str, expected_hash: str, cache_root: Path) -> tuple[Path, str]:
    parsed_url = urllib.parse.urlsplit(url) if isinstance(url, str) else None
    if not parsed_url or parsed_url.scheme != "https" or not parsed_url.hostname or parsed_url.username or parsed_url.password or parsed_url.fragment:
        fail("Remote dependency archives must use HTTPS")
    if not isinstance(expected_hash, str) or not re.fullmatch(r"[a-f0-9]{64}", expected_hash):
        fail("Remote dependency archives need a lowercase SHA-256 pin")
    cache_root = ensure_no_links(cache_root)
    downloads = cache_root / "downloads"
    downloads.mkdir(parents=True, exist_ok=True)
    downloads = ensure_no_links(downloads)
    target = downloads / f"{expected_hash}.archive"
    if target.exists():
        if not target.is_file() or sha256_file(target) != expected_hash:
            fail(f"Remote archive cache entry is invalid and was not replaced: {target}")
        return target, "verified-download-cache"

    request = urllib.request.Request(url, headers={"User-Agent": "PS5-Homebrew-Studio/1.0"})
    temporary = downloads / f".{expected_hash}.{os.getpid()}.partial"
    digest = hashlib.sha256()
    total = 0
    try:
        with urllib.request.urlopen(request, timeout=30) as response, temporary.open("xb") as output:
            final_url = response.geturl()
            final = urllib.parse.urlsplit(final_url)
            if final.scheme != "https" or not final.hostname or final.username or final.password or final.fragment:
                fail("Remote dependency redirected away from HTTPS")
            while True:
                block = response.read(1024 * 1024)
                if not block:
                    break
                total += len(block)
                if total > MAX_ARCHIVE_BYTES:
                    fail("Remote dependency archive exceeds the 1 GiB download limit")
                digest.update(block)
                output.write(block)
        actual_hash = digest.hexdigest()
        if actual_hash != expected_hash:
            fail(f"Remote dependency SHA-256 mismatch: expected {expected_hash}, received {actual_hash}")
        os.replace(temporary, target)
        return target, "downloaded-https-sha256-verified"
    except (OSError, urllib.error.URLError) as exc:
        fail(f"Could not download the declared HTTPS dependency archive: {exc}")
    finally:
        if temporary.exists():
            temporary.unlink()


def verify_cached(target: Path, marker: Path, package: dict[str, Any], archive_hash: str) -> bool:
    try:
        data = json.loads(marker.read_text(encoding="utf-8"))
        if data.get("id") != package["id"] or data.get("version") != package["version"] or data.get("archiveSha256") != archive_hash or data.get("packageSha256") != package_hash(package):
            return False
        files = data.get("files")
        if not isinstance(files, list):
            return False
        expected_paths: set[str] = set()
        for record in files:
            relative = safe_relative(record.get("path"), "cached file path")
            expected_paths.add(relative)
            path = ensure_no_links(target, relative)
            if not path.is_file() or sha256_file(path) != record.get("sha256"):
                return False
        actual_paths = {
            path.relative_to(target).as_posix()
            for path in target.rglob("*")
            if path.is_file() and not path.is_symlink()
        }
        if actual_paths != expected_paths or any(path.is_symlink() for path in target.rglob("*")):
            return False
        verify_package_tree(target, package)
        return True
    except (OSError, RuntimeError, ValueError):
        return False


def prepare_package(package: dict[str, Any], roots: dict[str, Path], cache_root: Path) -> dict[str, Any]:
    identifier = package.get("id")
    version = package.get("version")
    if not isinstance(identifier, str) or not re.fullmatch(r"[a-z][a-z0-9_-]{0,63}", identifier):
        fail("Dependency id must use lowercase letters, digits, underscore, or hyphen")
    if not isinstance(version, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.+_-]{0,63}", version):
        fail(f"Dependency {identifier} has an invalid version")
    source = package.get("source")
    if not isinstance(source, dict):
        fail(f"Dependency {identifier} has no source declaration")
    source_location = ""
    origin = "local-directory"

    if source.get("kind") == "directory":
        root = resolve_scoped(str(source.get("scope", "")), str(source.get("path", "")), roots, f"{identifier}.source.path")
        source_location = f"{source.get('scope')}:{source.get('path')}"
        if not root.is_dir():
            fail(f"Dependency directory is missing: {root}")
        verify_package_tree(root, package)
    elif source.get("kind") == "archive":
        expected_hash = source.get("sha256")
        if not isinstance(expected_hash, str) or not re.fullmatch(r"[a-f0-9]{64}", expected_hash):
            fail(f"Dependency {identifier} needs a lowercase SHA-256 pin")
        local_scope = source.get("scope")
        local_path = source.get("path")
        if bool(local_scope) != bool(local_path):
            fail(f"Dependency {identifier} must declare both source.scope and source.path, or neither")
        archive = None
        origin = "local-file"
        if local_scope and local_path:
            candidate = resolve_scoped(str(local_scope), str(local_path), roots, f"{identifier}.source.path")
            if candidate.is_file():
                archive = candidate
                source_location = f"{local_scope}:{local_path}"
            elif not source.get("url"):
                fail(f"Dependency archive is missing: {candidate}; no verified HTTPS source is declared")
        if archive is None:
            url = source.get("url")
            if not url:
                fail(f"Dependency archive is missing for {identifier}; add it locally or declare an HTTPS URL with its SHA-256")
            archive, origin = download_archive(str(url), expected_hash, cache_root)
            parsed_url = urllib.parse.urlsplit(str(url))
            source_location = parsed_url.hostname or "HTTPS source"
            if parsed_url.path:
                source_location += parsed_url.path
        actual_hash = sha256_file(archive)
        if actual_hash != expected_hash:
            fail(f"Dependency archive hash mismatch for {identifier}: expected {expected_hash}, found {actual_hash}")
        cache_root = ensure_no_links(cache_root)
        cache_root.mkdir(parents=True, exist_ok=True)
        cache_root = ensure_no_links(cache_root)
        profile_hash = package_hash(package)
        cache_name = f"{identifier}-{version}-{actual_hash[:12]}-{profile_hash[:12]}"
        target = cache_root / cache_name
        marker = cache_root / f".{cache_name}.manifest.json"
        if target.exists() or marker.exists():
            if target.is_dir() and verify_cached(target, marker, package, actual_hash):
                root = target
            else:
                fail(f"Existing dependency cache is incomplete or modified: {target}")
        else:
            stage = Path(tempfile.mkdtemp(prefix=f".{identifier}-stage-", dir=cache_root))
            stage_marker = cache_root / f".{cache_name}.stage.json"
            try:
                files = extract_archive(archive, package, stage)
                verify_package_tree(stage, package)
                metadata = {"schema": "ps5hs-payload-dependency-cache", "id": identifier, "version": version, "archiveSha256": actual_hash, "packageSha256": profile_hash, "files": files}
                stage_marker.write_text(json.dumps(metadata, sort_keys=True, indent=2) + "\n", encoding="utf-8")
                os.replace(stage, target)
                os.replace(stage_marker, marker)
            except Exception:
                if stage.exists():
                    shutil.rmtree(stage, ignore_errors=True)
                if stage_marker.exists():
                    stage_marker.unlink()
                raise
            root = target
    else:
        fail(f"Dependency {identifier} source kind must be directory or archive")

    return {"id": identifier, "version": version, "root": str(root), "origin": origin, "source": source_location, "binDirs": package.get("binDirs", []), "includeDirs": package.get("includeDirs", []), "libraryDirs": package.get("libraryDirs", []), "libraries": package.get("libraries", []), "linkFiles": package.get("linkFiles", []), "executableFiles": package.get("executableFiles", [])}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--project-root", required=True, type=Path)
    parser.add_argument("--ide-root", required=True, type=Path)
    parser.add_argument("--cache-root", required=True, type=Path)
    args = parser.parse_args()
    manifest_path = ensure_no_links(args.manifest)
    roots = {"project": ensure_no_links(args.project_root), "ide": ensure_no_links(args.ide_root)}
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("schema") != "ps5hs-payload-dependencies" or manifest.get("version") != 1:
        fail("Unsupported payload dependency manifest schema or version")
    packages = manifest.get("packages", [])
    if not isinstance(packages, list) or len(packages) > MAX_PACKAGES:
        fail(f"Manifest packages must be a list of at most {MAX_PACKAGES} items")
    identifiers = [item.get("id") for item in packages if isinstance(item, dict)]
    if len(identifiers) != len(packages) or len(set(identifiers)) != len(identifiers):
        fail("Manifest package ids must be objects and unique")
    resolved = [prepare_package(item, roots, args.cache_root) for item in packages]
    print(json.dumps({"schema": "ps5hs-payload-dependencies-resolved", "packages": resolved}, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, tarfile.TarError, zipfile.BadZipFile, json.JSONDecodeError) as exc:
        raise SystemExit(f"payload dependency preparation failed: {exc}")
