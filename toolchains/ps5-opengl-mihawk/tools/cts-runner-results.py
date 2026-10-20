#!/usr/bin/env python3
# PS5 OpenGL - OpenGL implementation for PlayStation 5.
# Copyright (C) 2026 BlackBearReloaded
# SPDX-License-Identifier: GPL-3.0-or-later

"""Read a fetched cts-runner run directory (see tools/cts-console-run.sh).

  status <run-dir> [--mustpass <khronos mustpass root>]
      Per-session progress and every result that is not Pass or NotSupported.
  resume <run-dir> <session-log> --mustpass <data root>
      After a crash or hang, write <session-log>.caselist with the cases not
      yet run, skipping and recording the one that was running.
  retest <run-dir> <new-run-dir> [--match regex] [--codes Fail,Crash]
      Case lists for a focused rerun of the non-passing cases (or the matching
      ones) of every session; run it with CTS_ONLY_CASELISTS=1.
  summary <run-dir> [--output cts-run-summary.xml]
      The cts-runner summary for a sessions-mode run, from the per-session
      results, in the upstream format (Conformant only when every session
      completed with no failures).
"""

from __future__ import annotations

import argparse
import collections
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from xml.sax.saxutils import quoteattr

BEGIN = "#beginTestCaseResult "
STATUS = re.compile(r'<Result\s+StatusCode="([^"]+)"[^>]*>([^<]*)</Result>')
# Statuses the upstream TestRunner does not count as failures.
ACCEPTED = {"Pass", "NotSupported", "QualityWarning", "CompatibilityWarning", "Waiver"}


def parse_qpa(path: Path) -> tuple[dict[str, tuple[str, str]], str | None]:
    """Case results in one log, and the case that never finished, if any."""
    results: dict[str, tuple[str, str]] = {}
    current = None
    body: list[str] = []
    with path.open("r", errors="replace") as stream:
        for line in stream:
            if line.startswith(BEGIN):
                current = line[len(BEGIN):].strip()
                body = []
            elif line.startswith("#endTestCaseResult") and current:
                match = STATUS.search("".join(body))
                results[current] = (match.group(1), match.group(2).strip()) if match else ("Missing", "")
                current = None
            elif line.startswith("#terminateTestCaseResult") and current:
                results[current] = ("Terminated", line.split(None, 1)[1].strip() if " " in line else "")
                current = None
            elif current:
                body.append(line)
    return results, current


def plan(run: Path) -> list[tuple[str, list[str]]]:
    root = ET.parse(run / "plan" / "cts-run-summary.xml").getroot()
    return [(e.get("FileName"), e.get("CmdLine").split()) for e in root.iter("TestRun")]


def case_list(args: list[str], mustpass: Path | None) -> list[str] | None:
    for arg in args:
        if arg.startswith(("--deqp-caselist-resource=", "--deqp-caselist-file=")) and mustpass:
            path = mustpass / arg.split("=", 1)[1]
            return [line.strip() for line in path.read_text().splitlines() if line.strip()]
    return None


def session_parts(run: Path, name: str) -> list[Path]:
    """The session log, then its resumed parts in order."""
    parts = [run / name] if (run / name).exists() else []
    parts += sorted(run.glob(name + ".resume*"), key=lambda p: (len(p.name), p.name))
    return [p for p in parts if not p.name.endswith((".status", ".caselist", ".orig"))]


def crashes(run: Path) -> dict[str, str]:
    path = run / "crashes.txt"
    if not path.exists():
        return {}
    return dict(line.split("\t", 1) for line in path.read_text().splitlines() if "\t" in line)


def session_results(run: Path, name: str) -> tuple[dict[str, tuple[str, str]], str | None]:
    merged: dict[str, tuple[str, str]] = {}
    unfinished = None
    for part in session_parts(run, name):
        results, unfinished = parse_qpa(part)
        merged.update(results)
    for case, reason in crashes(run).items():
        if case.startswith(name + ":"):
            merged[case.split(":", 1)[1]] = ("Crash", reason)
    return merged, unfinished


def status(run: Path, mustpass: Path | None) -> int:
    sessions = plan(run)
    bad = 0
    totals = collections.Counter()
    for index, (name, args) in enumerate(sessions, 1):
        results, unfinished = session_results(run, name)
        expected = case_list(args, mustpass)
        counts = collections.Counter(code for code, _ in results.values())
        totals.update(counts)
        done = any((run / (name + suffix)).exists() for suffix in (".status", ".resume.status"))
        size = f"{len(results)}/{len(expected)}" if expected else f"{len(results)}"
        state = "done" if done else ("running" if unfinished else ("-" if not results else "partial"))
        print(f"{index:3} {state:8} {size:>13} {name}  " +
              " ".join(f"{k}={v}" for k, v in sorted(counts.items())))
        for case, (code, detail) in sorted(results.items()):
            if code not in ACCEPTED:
                bad += 1
                print(f"      {code}: {case}  {detail[:120]}")
    print("total " + " ".join(f"{k}={v}" for k, v in sorted(totals.items())))
    return 1 if bad else 0


def resume(run: Path, name: str, mustpass: Path, crashed: str | None = None) -> int:
    args = dict(plan(run))[name]
    # A focused rerun resumes within its own case list, kept on first resume.
    original = run / (name + ".caselist.orig")
    if not original.exists() and (run / (name + ".caselist")).exists():
        original.write_text((run / (name + ".caselist")).read_text())
    expected = ([c for c in original.read_text().split() if c] if original.exists()
                else case_list(args, mustpass))
    if expected is None:
        sys.exit(f"{name} has no case list resource")
    results, unfinished = session_results(run, name)
    # With buffered logs the QPA tail may be lost; klog names the running case.
    unfinished = crashed or unfinished
    if unfinished:
        with (run / "crashes.txt").open("a") as stream:
            stream.write(f"{name}:{unfinished}\tprocess ended or hung in this case\n")
        results[unfinished] = ("Crash", "")
    remaining = [case for case in expected if case not in results]
    # Keep earlier resumed logs: the runner always writes <name>.resume.
    current = run / (name + ".resume")
    if current.exists():
        number = 1
        while (run / f"{name}.resume{number}").exists():
            number += 1
        current.rename(run / f"{name}.resume{number}")
        print(f"renamed local {current.name} -> {name}.resume{number}")
    (run / (name + ".caselist")).write_text("\n".join(remaining) + "\n")
    print(f"{name}: {len(results)} done, crashed={unfinished}, {len(remaining)} remaining")
    return 0


def retest(run: Path, new: Path, match: str | None, codes: set[str] | None) -> int:
    (new / "plan").mkdir(parents=True, exist_ok=True)
    (new / "plan" / "cts-run-summary.xml").write_bytes((run / "plan" / "cts-run-summary.xml").read_bytes())
    total = 0
    for name, _ in plan(run):
        results, _ = session_results(run, name)
        cases = [case for case, (code, _) in results.items()
                 if (code in codes if codes else code not in ACCEPTED) and (not match or re.search(match, case))]
        if cases:
            (new / (name + ".caselist")).write_text("\n".join(cases) + "\n")
            total += len(cases)
            print(f"{name}: {len(cases)}")
    print(f"{total} cases")
    return 0


def summary(run: Path, output: Path) -> int:
    lines = []
    conformant = True
    for name, args in plan(run):
        counts = collections.Counter()
        results, unfinished = session_results(run, name)
        for code, _ in results.values():
            counts[code] += 1
        failed = sum(v for k, v in counts.items() if k not in ACCEPTED)
        complete = unfinished is None and any(
            (run / (name + s)).exists() for s in (".status", ".resume.status"))
        conformant &= complete and failed == 0
        warnings = counts["QualityWarning"] + counts["CompatibilityWarning"]
        lines.append(
            f'<TestRun FileName={quoteattr(name)} CmdLine={quoteattr(" ".join(args))}>'
            f'<TestResult Passed="{counts["Pass"]}" Failed="{failed}" '
            f'NotSupported="{counts["NotSupported"]}" Warnings="{warnings}" '
            f'Waived="{counts["Waiver"]}" DeviceLost="0" Executed="{sum(counts.values())}"/>'
            "</TestRun>")
    output.write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        f'<Summary Type="gl46" Conformant="{"True" if conformant else "False"}">'
        '<Configs FileName="configs.qpa"/>' + "".join(lines) + "</Summary>\n")
    print(f"{output}: conformant={conformant}")
    return 0 if conformant else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["status", "resume", "retest", "summary"])
    parser.add_argument("run", type=Path)
    parser.add_argument("session", nargs="?")
    parser.add_argument("--mustpass", type=Path, help="directory containing gl_cts/ (the app data root)")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--match")
    parser.add_argument("--codes")
    parser.add_argument("--crashed", help="case that was running when the process ended (from klog)")
    args = parser.parse_args()
    if args.command == "status":
        return status(args.run, args.mustpass)
    if args.command == "resume":
        if not args.session or not args.mustpass:
            parser.error("resume needs a session log name and --mustpass")
        return resume(args.run, args.session, args.mustpass, args.crashed)
    if args.command == "retest":
        codes = set(args.codes.split(",")) if args.codes else None
        return retest(args.run, Path(args.session), args.match, codes)
    return summary(args.run, args.output or args.run / "cts-run-summary.xml")


if __name__ == "__main__":
    raise SystemExit(main())
