#!/usr/bin/env python3
"""PS5 Vulkan Template - the notices a title folder carries: LEGAL.txt and licenses/.

    stage-notices.py APP_DIR VULKAN_DIR RADV_ARCHIVE

Called by ps5/tools/link-title.sh after it packages the title. It writes, beside
eboot.bin:

  LEGAL.txt                 no piracy; what the title is licensed under; trademarks
  licenses/README.txt       the same notice, then every part: its licence, copyright and source
  licenses/components.json  the same parts as data, each with the revision it was built from
                            (ps5/tools/source-bundle.py archives the source from it)
  licenses/<part>/...       the licence texts each part requires

Every text is read at the revision the title was built from (git show), not from a
working tree, so the notices match the source a release attaches. A part whose
repository has uncommitted changes is recorded as "dirty": a release refuses it.
The assets' notices stay in assets/NOTICES.txt (ps5/tools/build-assets.py).

Copyright (C) 2026 Mihawk
SPDX-License-Identifier: MIT
"""
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

PS5 = Path(__file__).resolve().parent.parent
ROOT = PS5.parent


UNCOMMITTED_REVISION = "uncommitted working tree"
UNRECORDED_REVISION = "vendored snapshot (revision not recorded)"


def git_run(repo, *args):
    return subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True)


def git(repo, *args):
    result = git_run(repo, *args)
    if result.returncode:
        raise subprocess.CalledProcessError(result.returncode, result.args, output=result.stdout, stderr=result.stderr)
    return result.stdout.strip()


def has_git_metadata(repo):
    return git_run(repo, "rev-parse", "--git-dir").returncode == 0


def has_git_commit(repo, rev):
    return bool(rev) and has_git_metadata(repo) and git_run(repo, "cat-file", "-e", f"{rev}^{{commit}}").returncode == 0


def source_metadata(repo):
    try:
        return json.loads((Path(repo) / ".ps5hs-source.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def source_remote(repo):
    repository = source_metadata(repo).get("repository", "")
    if repository:
        return "https://github.com/" + repository.removesuffix(".git")
    return "(local source snapshot)"


def revision(repo):
    """Return provenance without requiring a commit for generated or vendored working trees."""
    if has_git_metadata(repo):
        head = git_run(repo, "rev-parse", "--verify", "HEAD")
        if head.returncode == 0:
            rev = head.stdout.strip()
            dirty = bool(git(repo, "status", "--porcelain", "--untracked-files=all"))
            remotes = git(repo, "remote").split()
            name = "origin" if "origin" in remotes else (remotes[0] if remotes else None)
            remote = git(repo, "remote", "get-url", name) if name else "(no remote yet)"
            return rev, dirty, remote.removesuffix(".git")
        status = git_run(repo, "status", "--porcelain", "--untracked-files=all")
        if status.returncode:
            status.check_returncode()
        remotes = git(repo, "remote").split()
        name = "origin" if "origin" in remotes else (remotes[0] if remotes else None)
        remote = git(repo, "remote", "get-url", name) if name else "(no remote yet)"
        return UNCOMMITTED_REVISION, True, remote.removesuffix(".git")

    metadata = source_metadata(repo)
    recorded = metadata.get("sourceCommit") or metadata.get("commit")
    if not metadata.get("sourceRevisionRecorded") or not isinstance(recorded, str) or not re.fullmatch(r"[0-9a-f]{40}", recorded):
        recorded = UNRECORDED_REVISION
    return recorded, True, source_remote(repo)


def snapshot_file(repo, path):
    source = Path(repo) / path
    if source.is_symlink() or not source.is_file():
        raise SystemExit(f"vendored source is missing or linked: {source}")
    return source.read_bytes()
def pinned(script, name):
    """A revision a setup script pins ("name=<sha>")."""
    m = re.search(rf"^{name}=([0-9a-f]{{40}})", (PS5 / script).read_text(), re.M)
    return m.group(1) if m else None


def write_text(dest, repo, rev, path):
    """Stage a licence from the pinned Git revision or an explicitly unversioned local snapshot."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    if rev in (UNCOMMITTED_REVISION, UNRECORDED_REVISION) or not has_git_metadata(repo):
        data = snapshot_file(repo, path)
    else:
        result = subprocess.run(["git", "-C", str(repo), "show", f"{rev}:{path}"], capture_output=True)
        if result.returncode:
            result.check_returncode()
        data = result.stdout
    dest.write_bytes(data)


def write_tree(dest, repo, rev, path):
    """Stage a source folder from a pinned Git revision or a local vendored snapshot."""
    source = Path(repo) / path
    if has_git_metadata(repo):
        tar = subprocess.run(["git", "-C", str(repo), "archive", rev, path], capture_output=True, check=True).stdout
        dest.mkdir(parents=True, exist_ok=True)
        subprocess.run(["tar", "-x", "-C", str(dest), "--strip-components", str(len(Path(path).parts))], input=tar, check=True)
    else:
        if source.is_symlink() or not source.is_dir():
            raise SystemExit(f"vendored source tree is missing or linked: {source}")
        shutil.copytree(source, dest, dirs_exist_ok=True)
LEGAL = """{name} - legal use
{rule}

PIRACY IS NOT CONDONED. This title contains no games, no BIOS files, no
console firmware and no decryption keys, and none will ever be provided or
linked to. Use only games you own and files from hardware you own.
Downloading or sharing games, BIOS files, firmware or keys you do not own is
piracy: do not do it, and do not ask for help with it.

Licences: the title's own code and Sascha Willems' Vulkan examples are MIT.
It links the PS5 platform layer{kit}, which {are} GPL-3.0-or-later, so the
title as distributed is under GPL-3.0-or-later as a whole, and its complete
source is offered with it. Every part, its licence and its source are listed
in licenses/README.txt; the assets and theirs in assets/NOTICES.txt.

Not affiliated with or endorsed by Sony Interactive Entertainment.
"PlayStation" and "PS5" are trademarks of Sony Interactive Entertainment Inc.
Vulkan is a registered trademark of the Khronos Group Inc.; the RADV port is
not a conformant product (its conformanceVersion is 0.0.0.0).
"""


def main():
    app, vulkan, archive = (Path(a).resolve() for a in sys.argv[1:4])
    toolchains_root = Path(os.environ.get("PS5HS_TOOLCHAINS_ROOT") or vulkan.parent).resolve()
    name = json.loads((PS5 / "sce_sys/param.json").read_text())["localizedParameters"]["en-US"]["titleName"]
    out = app / "licenses"
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True)
    parts = []

    # The title: its own code, the foundation and the libraries in its tree
    rev, dirty, remote = revision(ROOT)
    write_text(out / "title/LICENSE.md", ROOT, rev, "LICENSE.md")
    libraries = [("external/imgui/LICENSE.txt", "imgui-LICENSE.txt"), ("external/ktx/LICENSE.md", "ktx-LICENSE.md"),
                 ("external/ktx/NOTICE.md", "ktx-NOTICE.md"), ("external/tinygltf/LICENSE", "tinygltf-LICENSE"),
                 ("ps5/third_party/volk/LICENSE.md", "volk-LICENSE.md")]
    for path, dest in libraries:
        write_text(out / "title" / dest, ROOT, rev, path)
    if rev in (UNCOMMITTED_REVISION, UNRECORDED_REVISION):
        glm = "vendored snapshot; upstream revision not recorded"
    else:
        entry = git(ROOT, "ls-tree", rev, "external/glm").split()
        glm = entry[2] if len(entry) >= 3 else "submodule revision not recorded"
    parts.append(dict(
        id="title", name=f"{name}: its program, the foundation (Sascha Willems' Vulkan examples and base class, the PS5 layer) "
                         "and the libraries in its tree (Dear ImGui, libktx, tinygltf with stb_image and nlohmann json, "
                         "volk, the Vulkan headers, glm)",
        licence="MIT (the title, the examples, Dear ImGui, tinygltf, volk, glm); Apache-2.0 (libktx); "
                "Apache-2.0 OR MIT (the Vulkan headers)",
        copyright=["Copyright (c) 2016-2026 Sascha Willems", "Copyright (C) 2026 Mihawk", "and each library's authors"],
        artifacts=["eboot.bin", "shaders/"], texts="licenses/title/",
        source=dict(kind="git", path=str(ROOT), remote=remote, revision=rev, dirty=dirty,
                    submodules={"external/glm": dict(remote="https://github.com/g-truc/glm", revision=glm)})))

    # The UI kit, from its pinned Git repository or the snapshot installed by setup-kit.sh.
    if (PS5 / "ui/setup-kit.sh").exists():
        kit_rev = pinned("ui/setup-kit.sh", "revision")
        if not kit_rev:
            raise SystemExit("the project does not record the UI kit revision")
        kit_candidates = [ROOT.parent / "PS5_VKHomebrewUI", ROOT / ".deps/PS5_VKHomebrewUI.git"]
        kit = next((p for p in kit_candidates if has_git_commit(p, kit_rev)), None)
        kit_dirty = False
        if kit is None:
            kit = ROOT / ".deps/hui"
            stamp = (kit / ".revision").read_text(encoding="utf-8").split() if (kit / ".revision").is_file() else []
            if not (kit / "LICENSE").is_file() or not stamp or stamp[0] != kit_rev:
                raise SystemExit(f"the pinned UI kit source {kit_rev} is unavailable for notices")
            kit_dirty = True
        write_text(out / "ui-kit/LICENSE", kit, kit_rev, "LICENSE")
        parts.append(dict(
            id="ui-kit", name="the UI kit: BlackBearReloaded's ps5-homebrew-ui with my Vulkan backend (PS5_VKHomebrewUI), "
                              "and the UI module that draws with it (ps5/ui/)",
            licence="GPL-3.0-or-later", copyright=["Copyright (C) 2026 BlackBearReloaded", "Copyright (C) 2026 Mihawk"],
            artifacts=["eboot.bin", "assets/hui/"], texts="licenses/ui-kit/",
            source=dict(kind="git", path=str(kit), remote="https://github.com/mihawk-99/PS5_VKHomebrewUI",
                        revision=kit_rev, dirty=kit_dirty)))
    # The payload SDK fork: the platform layer and headers used by this offline toolchain.
    sdk_rev = pinned("tools/setup-sdk.sh", "sdk_revision")
    if not sdk_rev:
        raise SystemExit("the project does not record the payload SDK revision")
    sdk_candidates = [ROOT.parent / "PS5_PayloadSDK",
                      toolchains_root / f"PS5_PayloadSDK-pinned-{sdk_rev[:8]}",
                      toolchains_root / "PS5_PayloadSDK"]
    sdk = next((p for p in sdk_candidates if has_git_commit(p, sdk_rev)), None)
    sdk_dirty = False
    if sdk is None:
        for candidate in sdk_candidates:
            metadata = source_metadata(candidate)
            source_rev = metadata.get("sourceCommit") or metadata.get("commit")
            if source_rev == sdk_rev and (candidate / "LICENSE").is_file():
                sdk = candidate
                sdk_dirty = True
                break
    if sdk is None:
        raise SystemExit(f"the pinned payload SDK source {sdk_rev} is unavailable for notices")
    write_text(out / "platform/GPL-3.0.txt", sdk, sdk_rev, "LICENSE")
    write_text(out / "platform/musl-regex-COPYRIGHT.txt", sdk, sdk_rev, "platform/src/regex/COPYRIGHT.musl")
    write_text(out / "platform/dlmalloc-SOURCE.txt", sdk, sdk_rev, "platform/src/dlmalloc/SOURCE")
    parts.append(dict(
        id="platform", name="the PS5 platform layer (libps5platform.a) and the SDK headers, from my payload SDK fork, "
                            "with musl's regex and dlmalloc",
        licence="GPL-3.0-or-later; musl's regex MIT; dlmalloc public domain",
        copyright=["Copyright (C) John Törnblom and the ps5-payload-dev contributors", "Copyright (C) 2026 Mihawk"],
        artifacts=["eboot.bin"], texts="licenses/platform/",
        source=dict(kind="git", path=str(sdk), remote="https://github.com/mihawk-99/PS5_PayloadSDK",
                    revision=sdk_rev, dirty=sdk_dirty)))
    # PS5_Vulkan: the link recipe, the CRT and its startup, the AGC imports, libc.prx
    vrev, vdirty, vremote = revision(vulkan)
    write_text(out / "ps5-vulkan/GPL-3.0.txt", vulkan, vrev, "LICENSE")
    parts.append(dict(
        id="ps5-vulkan", name="PS5_Vulkan: the RADV link recipe, the C runtime start-up, the AGC import stubs and "
                              "sce_module/libc.prx",
        licence="GPL-3.0-or-later", copyright=["Copyright (C) 2026 Mihawk"],
        artifacts=["eboot.bin", "sce_module/libc.prx"], texts="licenses/ps5-vulkan/",
        source=dict(kind="git", path=str(vulkan), remote=vremote, revision=vrev, dirty=vdirty)))

    # RADV: Mesa's Vulkan driver, from the revision recorded in the built archive.
    provenance = (archive.parent.parent / "PROVENANCE.txt").read_text(encoding="utf-8")
    mesa_rev = re.search(r"^revision: ([0-9a-f]{40})", provenance, re.M).group(1)
    radv_sdk = re.search(r"^sdk: ([0-9a-f]{40})", provenance, re.M)
    mesa_candidates = [ROOT.parent / "PS5_Mesa", toolchains_root / "PS5_Mesa"]
    mesa = next((p for p in mesa_candidates if has_git_commit(p, mesa_rev)), None)
    mesa_dirty = False
    if mesa is None:
        for candidate in mesa_candidates:
            metadata = source_metadata(candidate)
            source_rev = metadata.get("sourceCommit") or metadata.get("commit")
            if source_rev == mesa_rev and (candidate / "docs/license.rst").is_file() and (candidate / "licenses").is_dir():
                mesa = candidate
                mesa_dirty = True
                break
    if mesa is None:
        raise SystemExit(f"Mesa source revision {mesa_rev} is unavailable for notices")
    write_text(out / "radv/Mesa-license.rst", mesa, mesa_rev, "docs/license.rst")
    write_tree(out / "radv/licenses", mesa, mesa_rev, "licenses")
    parts.append(dict(
        id="radv", name="RADV, Mesa's Vulkan driver (with ACO, NIR and Mesa's Vulkan runtime), from my PS5_Mesa fork",
        licence="MIT, with other licences stated per file (licenses/radv/Mesa-license.rst)",
        copyright=["Copyright the Mesa contributors (per-file notices in the source)"],
        artifacts=["eboot.bin"], texts="licenses/radv/",
        source=dict(kind="git", path=str(mesa), remote="https://github.com/mihawk-99/PS5_Mesa",
                    revision=mesa_rev, dirty=mesa_dirty, built_with_sdk=radv_sdk.group(1) if radv_sdk else None)))
    # The LLVM runtime the SDK links in
    llvm = ROOT.parent / "PS5_LLVM/llvm/LICENSE.TXT"
    if llvm.exists():
        (out / "llvm-runtime").mkdir()
        shutil.copy2(llvm, out / "llvm-runtime/LICENSE.TXT")
    parts.append(dict(
        id="llvm-runtime", name="LLVM libc++, libc++abi, libunwind and compiler-rt builtins (linked into eboot.bin)",
        licence="Apache-2.0 WITH LLVM-exception",
        copyright=["Copyright (c) 2003-2026 University of Illinois at Urbana-Champaign and the LLVM project contributors"],
        artifacts=["eboot.bin"], texts="licenses/llvm-runtime/",
        source=dict(kind="fixed", revision="ps5-payload-dev SDK v0.42 release archives",
                    url="https://github.com/ps5-payload-dev/sdk/releases/tag/v0.42")))

    (out / "components.json").write_text(json.dumps(parts, indent=1, ensure_ascii=False) + "\n")
    has_kit = any(p["id"] == "ui-kit" for p in parts)
    legal = LEGAL.format(name=name, rule="=" * (len(name) + 12), kit=" and the UI kit" if has_kit else "",
                         are="are" if has_kit else "is")
    (app / "LEGAL.txt").write_text(legal)
    lines = [legal, "", "The parts of this title", "=======================", ""]
    for p in parts:
        src = p["source"]
        where = f'{src["remote"]} at {src["revision"]}' if src["kind"] == "git" else f'{src["revision"]}: {src["url"]}'
        lines += [p["name"], f'  licence:   {p["licence"]}', f'  copyright: {"; ".join(p["copyright"])}',
                  f'  in:        {", ".join(p["artifacts"])}', f'  texts:     {p["texts"]}', f'  source:    {where}', ""]
    lines += ["The assets: assets/NOTICES.txt, with their licence texts in assets/LICENSES/."]
    (out / "README.txt").write_text("\n".join(lines) + "\n")
    dirty = [p["id"] for p in parts if p["source"].get("dirty")]
    print(f"==> notices: LEGAL.txt, licenses/ ({len(parts)} parts{'; dirty: ' + ', '.join(dirty) if dirty else ''})")


if __name__ == "__main__":
    main()
