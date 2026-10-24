#!/usr/bin/env python3
"""Select the PS5 payload LLVM suite locally, provisioning Ubuntu packages only when needed."""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


def fail(message: str) -> None:
    raise RuntimeError(message)


def run(command: list[str], *, check: bool = False, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    try:
        result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False, env=env)
    except OSError as exc:
        fail(f"Could not run {command[0]}: {exc}")
    if check and result.returncode:
        fail(f"Command failed ({result.returncode}): {' '.join(command)}\n{result.stdout.strip()}")
    return result


def read_manifest(path: Path | None) -> dict[str, Any]:
    if path is None:
        return {"schema": "ps5hs-payload-dependencies", "version": 1}
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"Could not read payload dependency manifest: {exc}")
    if not isinstance(value, dict):
        fail("Payload dependency manifest root must be an object")
    if value.get("schema") != "ps5hs-payload-dependencies" or value.get("version") != 1:
        fail("Unsupported payload dependency manifest schema or version")
    return value


def requested_major(manifest: dict[str, Any]) -> int | None:
    toolchain = manifest.get("toolchain", {})
    if toolchain is not None and not isinstance(toolchain, dict):
        fail("toolchain must be an object")
    build = manifest.get("build") or {}
    if not isinstance(build, dict):
        fail("build must be an object")
    value = toolchain.get("llvmMajor") if isinstance(toolchain, dict) else None
    legacy = build.get("llvmMajor") if isinstance(build, dict) else None
    if value is not None and legacy is not None and str(value) != str(legacy):
        fail("toolchain.llvmMajor conflicts with the legacy build.llvmMajor value")
    value = value if value is not None else legacy
    if value is None:
        return None
    text = str(value)
    if not re.fullmatch(r"[0-9]{2}", text) or int(text) < 15:
        fail("LLVM major must be a supported two-digit version")
    return int(text)


def validate_host_packages(manifest: dict[str, Any]) -> list[dict[str, str | None]]:
    packages = manifest.get("hostPackages", [])
    if not isinstance(packages, list) or len(packages) > 64:
        fail("hostPackages must be a list of at most 64 Ubuntu package entries")
    result: list[dict[str, str | None]] = []
    seen: set[str] = set()
    for item in packages:
        if not isinstance(item, dict):
            fail("Each hostPackages entry must be an object")
        identifier = item.get("id")
        package = item.get("package")
        version = item.get("version")
        if not isinstance(identifier, str) or not re.fullmatch(r"[a-z][a-z0-9_-]{0,63}", identifier):
            fail("hostPackages entries need a safe lowercase id")
        if identifier in seen:
            fail(f"Duplicate host package id: {identifier}")
        seen.add(identifier)
        if not isinstance(package, str) or not re.fullmatch(r"[a-z0-9][a-z0-9+.-]{0,127}", package):
            fail(f"Invalid Ubuntu package name for {identifier}")
        if version is not None and (not isinstance(version, str) or not re.fullmatch(r"[A-Za-z0-9.+:~_-]{1,128}", version)):
            fail(f"Invalid pinned Ubuntu package version for {identifier}")
        result.append({"id": identifier, "package": package, "version": version})
    return result


def installed_debian_version(package: str) -> str | None:
    result = run(["dpkg-query", "-W", "-f=${Version}", package])
    return result.stdout.strip() if result.returncode == 0 and result.stdout.strip() else None


def apt_candidate(package: str) -> str | None:
    result = run(["apt-cache", "policy", package])
    match = re.search(r"^\s*Candidate:\s*(\S+)\s*$", result.stdout, re.MULTILINE)
    if not match or match.group(1) == "(none)":
        return None
    return match.group(1)


def privileged_prefix() -> list[str]:
    if os.geteuid() == 0:
        return []
    sudo = shutil.which("sudo")
    if not sudo or run([sudo, "-n", "true"]).returncode:
        fail("A required toolchain package is missing. Automatic installation needs passwordless sudo in WSL; run the IDE's offline-environment repair or install the named Ubuntu packages manually.")
    return [sudo, "-n"]


def apt_update(prefix: list[str], actions: list[dict[str, Any]]) -> bool:
    env = os.environ.copy()
    env["DEBIAN_FRONTEND"] = "noninteractive"
    result = run([*prefix, "apt-get", "-o", "Acquire::http::Timeout=10", "-o", "Acquire::https::Timeout=10", "-o", "Acquire::Retries=0", "update"], env=env)
    actions.append({"action": "apt-get update", "status": "completed" if result.returncode == 0 else "failed", "exitCode": result.returncode, "output": "\n".join(result.stdout.splitlines()[-8:])})
    return result.returncode == 0


def apt_install(prefix: list[str], specifications: list[str], actions: list[dict[str, Any]]) -> bool:
    if not specifications:
        return True
    env = os.environ.copy()
    env["DEBIAN_FRONTEND"] = "noninteractive"
    result = run([*prefix, "apt-get", "-o", "Acquire::http::Timeout=10", "-o", "Acquire::https::Timeout=10", "-o", "Acquire::Retries=0", "install", "-y", "--no-install-recommends", *specifications], env=env)
    actions.append({"action": "apt-get install", "packages": specifications, "status": "completed" if result.returncode == 0 else "failed", "exitCode": result.returncode, "output": "\n".join(result.stdout.splitlines()[-12:])})
    return result.returncode == 0


def apt_metadata_stale() -> bool:
    root = Path("/var/lib/apt/lists")
    if not root.is_dir():
        return True
    mtimes = [path.stat().st_mtime for path in root.iterdir() if path.is_file() and path.name not in {"lock", "auxfiles"}]
    return not mtimes or time.time() - max(mtimes) > 24 * 60 * 60


def package_version_is_newer(candidate: str, installed: str) -> bool:
    return run(["dpkg", "--compare-versions", candidate, "gt", installed]).returncode == 0


def toolchain_for_major(major: int, sdk_root: Path) -> dict[str, str] | None:
    config = shutil.which(f"llvm-config-{major}")
    if not config:
        return None
    version_result = run([config, "--version"])
    bindir_result = run([config, "--bindir"])
    if version_result.returncode or bindir_result.returncode:
        return None
    version = version_result.stdout.strip()
    if not re.fullmatch(rf"{major}\.[0-9][A-Za-z0-9.+~-]*", version):
        return None
    # LLVM deliberately ships several tools as symlinks to shared binaries
    # (clang++ -> clang and ld.lld -> lld). Their invocation name selects the
    # driver mode, so resolving the symlinks changes compiler/linker behavior.
    # Keep the path names returned by llvm-config --bindir intact.
    bindir = Path(bindir_result.stdout.strip()).absolute()
    compiler = bindir / "clang"
    compiler_cxx = bindir / "clang++"
    linker = bindir / "ld.lld"
    if not all(path.is_file() and os.access(path, os.X_OK) for path in (compiler, compiler_cxx, linker)):
        return None
    if not sdk_root.is_dir() or not (sdk_root / "toolchain/prospero.mk").is_file():
        fail(f"The PS5 Payload SDK is incomplete at {sdk_root}")
    return {
        "major": str(major),
        "version": version,
        "llvmConfig": str(Path(config).absolute()),
        "bindir": str(bindir),
        "compiler": str(compiler.absolute()),
        "compilerCxx": str(compiler_cxx.absolute()),
        "linker": str(linker.absolute()),
    }


def installed_majors() -> list[int]:
    values: set[int] = set()
    directories = [Path(item) for item in os.environ.get("PATH", "").split(os.pathsep) if item]
    for directory in directories:
        if directory.is_dir():
            for path in directory.glob("llvm-config-[0-9]*"):
                match = re.fullmatch(r"llvm-config-([0-9]+)", path.name)
                if match and int(match.group(1)) >= 15 and path.is_file() and os.access(path, os.X_OK):
                    values.add(int(match.group(1)))
    return sorted(values, reverse=True)


def available_apt_majors() -> list[int]:
    result = run(["apt-cache", "pkgnames"])
    values: set[int] = set()
    if result.returncode:
        return []
    for name in result.stdout.splitlines():
        match = re.fullmatch(r"llvm-([0-9]+)-dev", name.strip())
        if match and int(match.group(1)) >= 15:
            major = int(match.group(1))
            if all(apt_candidate(f"{package}-{major}") for package in ("clang", "lld")) and apt_candidate(f"llvm-{major}-dev"):
                values.add(major)
    return sorted(values, reverse=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--sdk-root", type=Path, default=Path("/opt/ps5-payload-sdk"))
    args = parser.parse_args()
    if not (args.sdk_root / "toolchain/prospero.mk").is_file():
        fail(f"The PS5 Payload SDK is incomplete at {args.sdk_root}")
    manifest = read_manifest(args.manifest)
    if manifest.get("toolchain") is not None and not isinstance(manifest["toolchain"], dict):
        fail("toolchain must be an object")
    requested = requested_major(manifest)
    host_packages = validate_host_packages(manifest)
    provisioned: list[str] = []
    actions: list[dict[str, Any]] = []
    warnings: list[str] = []
    apt_prefix: list[str] | None = None
    apt_update_attempted = False
    apt_index_available = False

    def refresh_apt(*, force: bool = False) -> bool:
        nonlocal apt_prefix, apt_update_attempted, apt_index_available
        if apt_update_attempted:
            return apt_index_available
        if not force and not apt_metadata_stale():
            apt_index_available = True
            return True
        apt_prefix = apt_prefix or privileged_prefix()
        apt_update_attempted = True
        apt_index_available = apt_update(apt_prefix, actions)
        return apt_index_available

    if requested is None or any(entry["version"] is None for entry in host_packages):
        if not refresh_apt():
            warnings.append("Ubuntu no pudo actualizar sus índices; se usarán las versiones compatibles que ya existan en WSL.")

    pending_host: list[str] = []
    required_host_install = False
    for entry in host_packages:
        package = str(entry["package"])
        desired = entry["version"]
        installed = installed_debian_version(package)
        candidate = apt_candidate(package)
        if desired is not None:
            if installed == desired:
                continue
            if candidate != desired and (not refresh_apt(force=True) or apt_candidate(package) != desired):
                fail(f"Pinned Ubuntu package version is unavailable: {package}={desired}")
            pending_host.append(f"{package}={desired}")
            required_host_install = True
        elif installed:
            if candidate and package_version_is_newer(candidate, installed):
                pending_host.append(package)
        else:
            if not candidate and (not refresh_apt(force=True) or not apt_candidate(package)):
                fail(f"Ubuntu has no candidate for required package {package}; check WSL network and apt sources")
            pending_host.append(package)
            required_host_install = True

    if pending_host:
        apt_prefix = apt_prefix or privileged_prefix()
        if apt_install(apt_prefix, pending_host, actions):
            provisioned.extend(pending_host)
        elif required_host_install:
            fail(f"Could not install required Ubuntu packages: {', '.join(pending_host)}")
        else:
            warnings.append("No se pudieron actualizar algunos paquetes host; se conservarán las versiones ya instaladas en WSL.")

    selected: dict[str, str] | None = None
    if requested is not None:
        selected = toolchain_for_major(requested, args.sdk_root)
        if selected is None:
            apt_prefix = apt_prefix or privileged_prefix()
            refresh_apt(force=True)
            packages = [f"clang-{requested}", f"lld-{requested}", f"llvm-{requested}-dev"]
            unavailable = [package for package in packages if not apt_candidate(package)]
            if unavailable:
                fail(f"Requested LLVM {requested} is not installed and is unavailable from configured Ubuntu repositories: {', '.join(unavailable)}. The IDE will not replace an explicit version with another one.")
            if not apt_install(apt_prefix, packages, actions):
                fail(f"Could not install the explicitly requested LLVM {requested} toolchain")
            provisioned.extend(packages)
            selected = toolchain_for_major(requested, args.sdk_root)
            if selected is None:
                fail(f"LLVM {requested} packages were installed, but a matching clang, clang++, ld.lld and llvm-config suite was not found")
    else:
        for major in installed_majors():
            selected = toolchain_for_major(major, args.sdk_root)
            if selected:
                break
        majors = available_apt_majors() if apt_index_available else []
        if not majors and selected is None and not apt_update_attempted:
            refresh_apt(force=True)
            majors = available_apt_majors() if apt_index_available else []
        latest_major = majors[0] if majors else None
        should_provision = selected is None
        if selected and latest_major is not None:
            current_major = int(selected["major"])
            should_provision = latest_major > current_major
            if latest_major == current_major:
                candidate_version = apt_candidate(f"llvm-{current_major}-dev")
                installed_version = installed_debian_version(f"llvm-{current_major}-dev")
                should_provision = bool(candidate_version and installed_version and package_version_is_newer(candidate_version, installed_version))
        if should_provision:
            if latest_major is None:
                if selected:
                    warnings.append("No hay una pareja LLVM más reciente disponible en los índices locales; se conserva la instalada.")
                    latest_major = int(selected["major"])
                else:
                    fail("No hay una pareja LLVM compatible instalada y Ubuntu no ofrece paquetes disponibles; se necesita conexión o instalar LLVM manualmente.")
            major = latest_major
            packages = [f"clang-{major}", f"lld-{major}", f"llvm-{major}-dev"]
            apt_prefix = apt_prefix or privileged_prefix()
            if apt_install(apt_prefix, packages, actions):
                provisioned.extend(packages)
                selected = toolchain_for_major(major, args.sdk_root)
                if selected is None:
                    fail(f"Ubuntu installed LLVM {major}, but the matching compiler and linker executables were not found")
            elif selected:
                warnings.append(f"No se pudo obtener LLVM {major}; se conserva LLVM {selected['version']} ya instalado.")
            else:
                fail(f"Ubuntu offers LLVM {major}, but it could not be installed; check WSL network and apt sources")
        if selected is None:
            fail("No compatible LLVM compiler/linker pair is available")

    resolved_host = []
    for entry in host_packages:
        package = str(entry["package"])
        resolved_host.append({
            "id": entry["id"],
            "package": package,
            "requestedVersion": entry["version"],
            "resolvedVersion": installed_debian_version(package),
            "source": "apt-installed" if any(item == package or item.startswith(package + "=") for item in provisioned) else "wsl-installed",
        })

    print(json.dumps({
        "schema": "ps5hs-payload-toolchain-resolved",
        "selection": "explicit" if requested is not None else "latest-compatible",
        "requestedMajor": requested,
        "toolchain": selected,
        "source": "apt-installed" if any(item.endswith(f"-{selected['major']}") or item == f"llvm-{selected['major']}-dev" for item in provisioned) else "wsl-installed",
        "hostPackages": resolved_host,
        "provisionedPackages": provisioned,
        "actions": actions,
        "warnings": warnings,
    }, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"payload toolchain resolution failed: {exc}", file=sys.stderr)
        raise SystemExit(2)
