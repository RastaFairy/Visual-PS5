#!/usr/bin/env python3
# PS5 OpenGL - OpenGL implementation for PlayStation 5.
# Copyright (C) 2026 BlackBearReloaded
# SPDX-License-Identifier: GPL-3.0-or-later

"""Justify every NotSupported result of an official cts-runner run.

Reads the session logs of one run directory (a resumed session's later logs
override earlier results of the same case) and assigns each NotSupported result
to a rule below. A result no rule covers fails the report: it needs a review,
not a default.
"""

from __future__ import annotations

import argparse
import collections
import html
import json
import re
from pathlib import Path

CASE = re.compile(r"^#beginTestCaseResult (\S+)\r?\n(.*?)^#endTestCaseResult",
                  re.MULTILINE | re.DOTALL)
STATUS = re.compile(r'<Result\s+StatusCode="([^"]+)"[^>]*>(.*?)</Result>', re.DOTALL)

# (class, case-name pattern, reason pattern, justification)
RULES = [
    ("optional-extension", r"\.sparse_(texture2?|texture_clamp|buffer)_tests\.", r"",
     "ARB_sparse_texture, ARB_sparse_texture2, ARB_sparse_texture_clamp and "
     "ARB_sparse_buffer are not part of OpenGL 4.6"),
    ("optional-extension", r"\.negative_texture_lookup_functions_with_bias_tests\.",
     r"sparse_texture2 extension not supported|texture_shadow_lod extension not supported",
     "tests of ARB_sparse_texture2 and EXT_texture_shadow_lod built-ins"),
    ("optional-extension", r"\.fragment_shading_rate\.",
     r"Fragment shading rate functionality not supported",
     "EXT_fragment_shading_rate is not part of OpenGL 4.6"),
    ("optional-extension", r"\.ext_texture_shadow_lod\.", r"EXT_texture_shadow_lod is not supported",
     "EXT_texture_shadow_lod is not part of OpenGL 4.6"),
    ("optional-extension", r"\.texture_filter_minmax_tests\.", r"^Not Supported$",
     "ARB_texture_filter_minmax is not part of OpenGL 4.6"),
    ("optional-extension", r"\.post_depth_coverage_tests\.", r"GL_ARB_post_depth_coverage not supported",
     "ARB_post_depth_coverage is not part of OpenGL 4.6"),
    ("optional-extension", r"", r"GL_KHR_blend_equation_advanced",
     "KHR_blend_equation_advanced(_coherent) is not part of OpenGL 4.6"),
    ("optional-extension", r"", r"GL_EXT_shader_framebuffer_fetch not supported",
     "EXT_shader_framebuffer_fetch is not part of OpenGL 4.6"),
    ("optional-extension", r"",
     r"GL_EXT_texture_sRGB_R8|GL_EXT_texture_sRGB_RG8|texture srgb rg8 not supported",
     "EXT_texture_sRGB_R8 and EXT_texture_sRGB_RG8 are not part of OpenGL 4.6"),
    ("optional-extension", r"^KHR-Single-GL46\.subgroups\.", r"Subgroup operations are not supported",
     "KHR_shader_subgroup is not part of OpenGL 4.6"),
    ("optional-extension", r"^KHR-Single-GL46\.meshShader\.", r"GL_EXT_mesh_shader is not supported",
     "EXT_mesh_shader is not part of OpenGL 4.6"),
    ("optional-extension", r"\.shader_viewport_layer_array\.", r"^Not supported$",
     "ARB_shader_viewport_layer_array is not part of OpenGL 4.6"),
    ("optional-extension", r"\.shaders\.shader_integer_mix\.prototypes$", r"^NotSupported$",
     "the case tests the EXT_shader_integer_mix extension string; the "
     "functionality itself is GLSL 4.50 and tested by the other cases"),
    ("optional-extension", r"\.internalformat\..*depth_component", r"Required extension is not supported",
     "the cases require the ARB_depth_texture extension string, which a core "
     "profile does not list"),

    ("sample-count", r"",
     r"Sample count not supported|Requested sample count is greater|"
     r"Sample count exceeds GL_MAX_SAMPLES|Test sample count great(er)? than|"
     r"Test requires larger GL_MAX_SAMPLE_MASK_WORDS|"
     r"Test requires multiple supported sample counts",
     "the case needs more samples than the implementation's maximum of 4 "
     "(OpenGL 4.6 requires MAX_SAMPLES >= 4, integer formats >= 1)"),
    ("sample-count", r"", r"No multisample buffers|Multisampled default framebuffer required",
     "the session's default framebuffer config is single-sampled"),

    ("minimum-limit", r"\.draw_indirect\.compute_interop\.large\.",
     r"GL_MAX_SHADER_STORAGE_BLOCK_SIZE is too small",
     "needs more than the required minimum MAX_SHADER_STORAGE_BLOCK_SIZE (2^27)"),
    ("minimum-limit", r"\.geometry_shading\.basic\.output_256$", r"2048 output components required",
     "needs more than the required minimum MAX_GEOMETRY_TOTAL_OUTPUT_COMPONENTS (1024)"),
    ("minimum-limit", r"\.tessellation_shader\.",
     r"GL_MAX_TESS_EVALUATION_OUTPUT_COMPONENTS > GL_MAX_TRANSFORM_FEEDBACK_INTERLEAVED_COMPONENTS",
     "both limits are at their required minimums (128 and 64)"),
    ("minimum-limit", r"\.texture_query_lod\.", r"Too small viewport",
     "the case needs a larger surface than this session's"),

    ("not-applicable", r"\.texture_swizzle\.functional_format_idx_\d+_target_idx_[56]$",
     r"^Target not supported$",
     "the case fetches with texelFetch, which GLSL does not define for "
     "rectangle (lod) and cube map targets"),
    ("not-applicable",
     r"\.texture_swizzle\.functional_format_idx_(38_target_idx_[78]|(6[3-9]|70)_target_idx_[278])$",
     r"^Target not supported$",
     "the test excludes depth formats on 3D and multisample targets and "
     "RGB9_E5 on multisample targets"),
    ("not-applicable",
     r"\.texture_swizzle\.smoke_access_idx_(1|6|8|9|12|13)_channel_idx_\d+$",
     r"^Target not supported$",
     "GLSL defines no textureProj* function for the 2D array target of the "
     "smoke test"),
    ("not-applicable", r"\.cull_distance\.functional_test_item_8_primitive_mode_(lines|triangles)_",
     r"^Not supported$",
     "the test fetches cull distances only when drawing points"),
    ("not-applicable", r"",
     r"only in ES context|requires a GLES context|not supported in the GL context|"
     r"not supported in a non-GLES context",
     "the case applies to OpenGL ES contexts only"),
    ("not-applicable", r"\.draw_elements_base_vertex_tests\.valid_active_tf$", r"^Not Supported$",
     "the case applies to OpenGL ES contexts only"),
    ("not-applicable", r"\.internalformat\.renderbuffer\.rgb9_e5$", r"Unsuported framebuffer",
     "RGB9_E5 is not a required color-renderable format"),
    ("not-applicable", r"\.texture\.border_clamp\.formats\.compressed_srgb8",
     r"Compressed texture format not supported",
     "the sRGB ETC2 formats are supported but, like every Mesa driver, not "
     "listed in COMPRESSED_TEXTURE_FORMATS, which the test consults"),

    ("surface-type", r"^KHR-NoContext\.", r"Test not supported in non-windowed context",
     "the case creates its own window-surface context; the conformant EGL "
     "config renders to pbuffers"),
]
COMPILED = [(name, re.compile(case), re.compile(why), text) for name, case, why, text in RULES]


def log_order(path: Path) -> int:
    match = re.search(r"\.resume(\d*)$", path.name)
    return int(match.group(1) or 0) if match else -1


def session_results(files: list[Path]) -> dict:
    results = {}
    for path in sorted(files, key=log_order):
        for match in CASE.finditer(path.read_text(errors="replace")):
            status = STATUS.search(match.group(2))
            if status:
                why = " ".join(html.unescape(re.sub(r"<[^>]+>", " ", status.group(2))).split())
                results[match.group(1)] = (status.group(1), why)
    return results


def classify(name: str, why: str) -> int | None:
    for index, (_, case, reason, _) in enumerate(COMPILED):
        if case.search(name) and reason.search(why):
            return index
    return None


def report(run: Path) -> dict:
    sessions = collections.defaultdict(list)
    for path in run.iterdir():
        if (path.is_file() and ".qpa" in path.name and
                not path.name.endswith((".status", ".caselist", ".orig"))):
            sessions[path.name.split(".qpa")[0]].append(path)
    out = {"run": run.name, "sessions": {}, "rules": {}, "unclassified": []}
    for session in sorted(sessions):
        results = session_results(sessions[session])
        counts = collections.Counter(status for status, _ in results.values())
        classes = collections.Counter()
        for name, (status, why) in sorted(results.items()):
            if status != "NotSupported":
                continue
            index = classify(name, why)
            if index is None:
                out["unclassified"].append({"session": session, "case": name, "reason": why})
                continue
            classes[COMPILED[index][0]] += 1
            rule = out["rules"].setdefault(str(index), {
                "class": COMPILED[index][0], "justification": COMPILED[index][3],
                "cases": 0, "example": name})
            rule["cases"] += 1
        out["sessions"][session] = {"results": dict(sorted(counts.items())),
                                    "not_supported": dict(sorted(classes.items()))}
    return out


def markdown(data: dict) -> str:
    lines = [f"# NotSupported results of run `{data['run']}`", "",
             "Every NotSupported result is covered by one of the rules below.", "",
             "| Session | Pass | NotSupported | Other |", "|---|---:|---:|---:|"]
    for session, row in data["sessions"].items():
        results = row["results"]
        other = sum(count for status, count in results.items()
                    if status not in ("Pass", "NotSupported"))
        lines.append(f"| `{session}` | {results.get('Pass', 0):,} | "
                     f"{results.get('NotSupported', 0):,} | {other:,} |")
    lines += ["", "| Class | Cases | Why | Example |", "|---|---:|---|---|"]
    for rule in sorted(data["rules"].values(), key=lambda row: (row["class"], -row["cases"])):
        lines.append(f"| {rule['class']} | {rule['cases']:,} | {rule['justification']} | "
                     f"`{rule['example']}` |")
    if data["unclassified"]:
        lines += ["", "## Unclassified", "", "| Session | Case | Reason |", "|---|---|---|"]
        lines += [f"| `{row['session']}` | `{row['case']}` | {row['reason']} |"
                  for row in data["unclassified"]]
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run", type=Path)
    parser.add_argument("--json", type=Path)
    parser.add_argument("--markdown", type=Path)
    args = parser.parse_args()
    data = report(args.run)
    if args.json:
        args.json.write_text(json.dumps(data, indent=2) + "\n")
    if args.markdown:
        args.markdown.write_text(markdown(data))
    total = sum(rule["cases"] for rule in data["rules"].values())
    classes = collections.Counter()
    for rule in data["rules"].values():
        classes[rule["class"]] += rule["cases"]
    print(f"NotSupported: {total} justified " +
          " ".join(f"{name}={count}" for name, count in sorted(classes.items())) +
          f"; unclassified={len(data['unclassified'])}")
    for row in data["unclassified"][:20]:
        print(f"  unclassified: {row['case']}: {row['reason'][:100]}")
    return 1 if data["unclassified"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
