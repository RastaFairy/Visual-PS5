#!/usr/bin/env python3
"""Install the pinned PacBrew PS5 headers and static libraries offline."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import posixpath
import re
import shutil
import stat
import tarfile
import tempfile
from pathlib import Path, PurePosixPath


ARCHIVE_PREFIX = "opt/ps5-payload-sdk/target/user/homebrew/"
IMAGE_TARGET = Path("/opt/ps5-payload-sdk/target/user/homebrew")
STAGE_MARKER = Path("/etc/ps5hs-offline-image-stage-id")
INSTALL_MARKER = ".ps5hs-pacbrew-install.json"

EXACT_FILES = {
    "include/microhttpd.h",
    "include/png.h",
    "include/pngconf.h",
    "include/pnglibconf.h",
    "include/sqlite3.h",
    "include/zlib.h",
    "include/zconf.h",
    "lib/libjson-c.a",
    "lib/libmicrohttpd.a",
    "lib/libpng16.a",
    "lib/libsqlite3.a",
    "lib/libz.a",
    "lib/pkgconfig/json-c.pc",
    "lib/pkgconfig/libmicrohttpd.pc",
    "lib/pkgconfig/libpng16.pc",
    "lib/pkgconfig/zlib.pc",
}

REQUIRED_FILES = {
    "include/json-c/json.h",
    "include/microhttpd.h",
    "include/png.h",
    "include/pngconf.h",
    "include/pnglibconf.h",
    "include/libpng16/png.h",
    "include/libpng16/pngconf.h",
    "include/libpng16/pnglibconf.h",
    "include/sqlite3.h",
    "include/zlib.h",
    "include/zconf.h",
    "lib/libjson-c.a",
    "lib/libmicrohttpd.a",
    "lib/libpng16.a",
    "lib/libsqlite3.a",
    "lib/libz.a",
    "lib/pkgconfig/json-c.pc",
    "lib/pkgconfig/libmicrohttpd.pc",
    "lib/pkgconfig/libpng16.pc",
    "lib/pkgconfig/zlib.pc",
}

STATIC_ARCHIVES = {
    "lib/libjson-c.a",
    "lib/libmicrohttpd.a",
    "lib/libpng16.a",
    "lib/libsqlite3.a",
    "lib/libz.a",
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def ensure_no_symlink_components(path: Path) -> None:
    absolute = Path(os.path.abspath(path))
    current = Path(absolute.anchor)
    for segment in absolute.parts[1:]:
        current /= segment
        if current.is_symlink():
            raise RuntimeError(f"Refusing a destination that crosses a symlink: {current}")


def selected_member(relative_path: str) -> bool:
    return (
        relative_path in EXACT_FILES
        or (
            relative_path.startswith("include/json-c/")
            and relative_path.endswith(".h")
        )
        or (
            relative_path.startswith("include/libpng16/")
            and relative_path.endswith(".h")
        )
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive", required=True, type=Path)
    parser.add_argument("--sha256", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--target", required=True, type=Path)
    parser.add_argument("--stage-id")
    parser.add_argument("--cache-root", type=Path)
    return parser.parse_args()


def validate_destination(args: argparse.Namespace) -> tuple[Path, Path]:
    target = Path(os.path.abspath(args.target))
    if args.stage_id:
        if args.cache_root:
            raise RuntimeError("Image staging and project cache modes cannot be combined.")
        if not re.fullmatch(r"[a-f0-9]{32}", args.stage_id):
            raise RuntimeError("Invalid image staging identifier.")
        if not STAGE_MARKER.is_file() or STAGE_MARKER.read_text(encoding="ascii").strip() != args.stage_id:
            raise RuntimeError("The image staging marker is missing or does not match.")
        if target != IMAGE_TARGET:
            raise RuntimeError(f"Image dependency target is fixed at {IMAGE_TARGET}.")
        allowed_root = IMAGE_TARGET.parent
    else:
        if not args.cache_root:
            raise RuntimeError("Project cache mode requires --cache-root.")
        allowed_root = Path(os.path.abspath(args.cache_root))
        try:
            target.relative_to(allowed_root)
        except ValueError as exc:
            raise RuntimeError("Project dependency cache destination is outside its allowed root.") from exc
        if target == allowed_root:
            raise RuntimeError("Project dependency cache cannot replace its root directory.")

    ensure_no_symlink_components(allowed_root)
    ensure_no_symlink_components(target)
    target.parent.mkdir(parents=True, exist_ok=True)
    ensure_no_symlink_components(target)
    return target, allowed_root


def read_existing_manifest(target: Path, version: str, archive_hash: str) -> bool:
    marker = target / INSTALL_MARKER
    if not marker.is_file() or marker.is_symlink():
        return False
    try:
        manifest = json.loads(marker.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return False
    if (
        manifest.get("schema") != "ps5hs-pacbrew-homebrew"
        or manifest.get("version") != version
        or manifest.get("archiveSha256") != archive_hash
    ):
        return False
    recorded: dict[str, str] = {}
    for entry in manifest.get("files", []):
        if not isinstance(entry, dict):
            return False
        relative_path = entry.get("path")
        expected_hash = entry.get("sha256")
        if not isinstance(relative_path, str) or not isinstance(expected_hash, str):
            return False
        normalized = PurePosixPath(relative_path)
        if (
            normalized.is_absolute()
            or ".." in normalized.parts
            or normalized.as_posix() != relative_path
            or not selected_member(relative_path)
            or relative_path in recorded
            or not re.fullmatch(r"[0-9a-f]{64}", expected_hash)
        ):
            return False
        file_path = target.joinpath(*normalized.parts)
        if not file_path.is_file() or file_path.is_symlink():
            return False
        try:
            file_path.resolve(strict=True).relative_to(target.resolve(strict=True))
        except (OSError, ValueError):
            return False
        if sha256_file(file_path) != expected_hash:
            return False
        recorded[relative_path] = expected_hash
    if not REQUIRED_FILES.issubset(recorded):
        return False
    return True


def extract_selected_files(archive_path: Path, staging_root: Path) -> list[dict[str, str]]:
    files: dict[str, tarfile.TarInfo] = {}
    with tarfile.open(archive_path, mode="r:gz") as archive:
        for member in archive:
            normalized = PurePosixPath(member.name)
            if normalized.is_absolute() or ".." in normalized.parts:
                raise RuntimeError(f"Unsafe path in pinned PacBrew archive: {member.name}")
            name = normalized.as_posix()
            if not name.startswith(ARCHIVE_PREFIX):
                continue
            relative_path = name[len(ARCHIVE_PREFIX):]
            if not selected_member(relative_path):
                continue
            if relative_path in files:
                raise RuntimeError(f"Duplicate path in pinned PacBrew archive: {relative_path}")
            if not (member.isfile() or member.issym()):
                raise RuntimeError(f"Unsupported PacBrew archive entry: {relative_path}")
            files[relative_path] = member

        missing = sorted(REQUIRED_FILES.difference(files))
        if missing:
            raise RuntimeError("Pinned PacBrew archive lacks required entries: " + ", ".join(missing))

        extracted: list[dict[str, str]] = []
        for relative_path, member in sorted(files.items()):
            destination = staging_root / relative_path
            destination.parent.mkdir(parents=True, exist_ok=True)
            source_member = member
            if member.issym():
                link = PurePosixPath(member.linkname)
                if link.is_absolute() or ".." in link.parts:
                    raise RuntimeError(f"Unsafe symlink in pinned PacBrew archive: {relative_path}")
                resolved = posixpath.normpath(
                    posixpath.join(posixpath.dirname(relative_path), member.linkname)
                )
                if not selected_member(resolved) or resolved not in files:
                    raise RuntimeError(f"PacBrew symlink target is not included: {relative_path}")
                source_member = files[resolved]
                if not source_member.isfile():
                    raise RuntimeError(f"PacBrew symlink target is not a regular file: {relative_path}")
            source = archive.extractfile(source_member)
            if source is None:
                raise RuntimeError(f"Cannot read PacBrew archive entry: {relative_path}")
            with source, destination.open("wb") as output:
                shutil.copyfileobj(source, output)
            destination.chmod(stat.S_IMODE(source_member.mode) or 0o644)
            extracted.append({
                "path": relative_path,
                "sha256": sha256_file(destination),
            })

    for relative_path in STATIC_ARCHIVES:
        archive_file = staging_root / relative_path
        with archive_file.open("rb") as stream:
            if stream.read(8) != b"!<arch>\n":
                raise RuntimeError(f"PacBrew static library is not a valid archive: {relative_path}")
    return extracted


def install(args: argparse.Namespace) -> None:
    if not re.fullmatch(r"v[0-9]+(?:\.[0-9]+){1,2}", args.version):
        raise RuntimeError("Invalid PacBrew version pin.")
    if not re.fullmatch(r"[0-9a-f]{64}", args.sha256):
        raise RuntimeError("Invalid PacBrew SHA-256 pin.")
    if not args.archive.is_file() or args.archive.is_symlink():
        raise RuntimeError(f"PacBrew archive is missing or is not a regular file: {args.archive}")
    actual_hash = sha256_file(args.archive)
    if actual_hash != args.sha256:
        raise RuntimeError(f"PacBrew archive SHA-256 mismatch: expected {args.sha256}; got {actual_hash}")

    target, _ = validate_destination(args)
    if read_existing_manifest(target, args.version, actual_hash):
        print(f"PacBrew {args.version}: verified cached PS5 dependencies at {target}")
        return

    temporary_root = Path(tempfile.mkdtemp(prefix=".ps5hs-pacbrew-stage-", dir=target.parent))
    try:
        extracted = extract_selected_files(args.archive, temporary_root)
        for entry in extracted:
            relative_path = entry["path"]
            source = temporary_root / relative_path
            destination = target / relative_path
            destination.parent.mkdir(parents=True, exist_ok=True)
            ensure_no_symlink_components(destination.parent)
            os.replace(source, destination)

        for relative_path in REQUIRED_FILES:
            installed = target / relative_path
            if not installed.is_file() or installed.is_symlink():
                raise RuntimeError(f"Required PacBrew file was not installed: {installed}")

        manifest = {
            "schema": "ps5hs-pacbrew-homebrew",
            "version": args.version,
            "archiveSha256": actual_hash,
            "files": extracted,
        }
        marker_path = target / INSTALL_MARKER
        temporary_marker = temporary_root / INSTALL_MARKER
        temporary_marker.write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        os.replace(temporary_marker, marker_path)
        print(
            f"PacBrew {args.version}: installed and verified "
            f"{len(extracted)} PS5 dependency files at {target}"
        )
    finally:
        shutil.rmtree(temporary_root, ignore_errors=True)


def main() -> int:
    try:
        install(parse_args())
    except (OSError, tarfile.TarError, RuntimeError, ValueError) as exc:
        print(f"PacBrew offline dependency preparation failed: {exc}", file=os.sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
