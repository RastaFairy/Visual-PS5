#!/usr/bin/env python3
# PS5 OpenGL - OpenGL implementation for PlayStation 5.
# Copyright (C) 2026 BlackBearReloaded
# SPDX-License-Identifier: GPL-3.0-or-later

"""Export a finished official cts-runner run as publishable evidence.

  export-cts-official-run.py <run-dir> <evidence-dir> --mustpass <dist-dir>
      --commit <sha> --eboot <eboot.bin> --cts <release-name> --date <yyyy-mm-dd>
      [--window-run <run-dir>]

Refuses a run that is not conformant: every session must be complete, hold
exactly the cases of its must-pass list, and have no result other than Pass,
NotSupported or a warning; every NotSupported result must be justified.

--window-run adds the supplementary run of the same binary in which the cases
that insist on a window surface run on an offscreen one
(PS5_CTS_OFFSCREEN_WINDOW=1). It must pass every case the official run reports
as NotSupported for the surface type.
"""

from __future__ import annotations

import argparse
import collections
import csv
import gzip
import hashlib
import importlib.util
import io
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def load(name: str):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), HERE / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


RESULTS = load("cts-runner-results")
NOTSUPPORTED = load("cts-notsupported-report")
DATA_FILES = ("cases.csv.gz", "cts-run-summary.xml", "notsupported.json", "notsupported.md", "run.json")
WINDOW_FILE = "window-surface-cases.csv"
# The cases the surface-type rule of the NotSupported report covers.
WINDOW_PREFIX = "KHR-NoContext."


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def collect(run: Path, mustpass: Path) -> tuple[list[dict], list[tuple[str, str, str]]]:
    sessions, rows = [], []
    for index, (name, args) in enumerate(RESULTS.plan(run), 1):
        results, unfinished = RESULTS.session_results(run, name)
        expected = RESULTS.case_list(args, mustpass)
        if expected is None:
            sys.exit(f"{name}: no must-pass case list")
        if unfinished is not None or not any(
                (run / (name + suffix)).exists() for suffix in (".status", ".resume.status")):
            sys.exit(f"{name}: session is not complete")
        if len(expected) != len(set(expected)):
            sys.exit(f"{name}: duplicate must-pass cases")
        missing = [case for case in expected if case not in results]
        extra = sorted(set(results) - set(expected))
        if missing or extra:
            sys.exit(f"{name}: {len(missing)} cases without a result, {len(extra)} unexpected "
                     f"(first: {(missing + extra)[0]})")
        counts = collections.Counter(code for code, _ in results.values())
        rejected = sorted(case for case, (code, _) in results.items() if code not in RESULTS.ACCEPTED)
        if rejected:
            sys.exit(f"{name}: {len(rejected)} results are not accepted (first: {rejected[0]})")
        sessions.append({
            "index": index, "log": name, "command_line": " ".join(args), "cases": len(expected),
            "results": dict(sorted(counts.items())),
            "raw_logs_sha256": {part.name: sha256(part) for part in RESULTS.session_parts(run, name)},
        })
        rows += [(name, case, results[case][0]) for case in expected]
    return sessions, rows


def collect_window(run: Path, rows: list[tuple[str, str, str]]) -> tuple[dict, list[tuple[str, str, str]]]:
    """Results of the supplementary window-surface run, checked against the official rows."""
    skipped = {(session, case) for session, case, status in rows
               if status == "NotSupported" and case.startswith(WINDOW_PREFIX)}
    window_rows, logs = [], {}
    for name, _ in RESULTS.plan(run):
        results, unfinished = RESULTS.session_results(run, name)
        if not results:
            continue
        if unfinished is not None:
            sys.exit(f"window run: {name} is not complete")
        for case in sorted(results):
            if results[case][0] != "Pass":
                sys.exit(f"window run: {case} is {results[case][0]}")
            window_rows.append((name, case, "Pass"))
        logs.update({part.name: sha256(part) for part in RESULTS.session_parts(run, name)})
    missing = sorted(skipped - {(session, case) for session, case, _ in window_rows})
    if missing:
        sys.exit(f"window run: {len(missing)} surface-type cases were not run (first: {missing[0][1]})")
    return {"environment": "PS5_CTS_OFFSCREEN_WINDOW=1", "cases": len(window_rows),
            "covers_not_supported": len(skipped), "raw_logs_sha256": logs}, window_rows


def readme(data: dict, notsupported: dict) -> str:
    totals = data["totals"]
    classes = collections.Counter()
    for rule in notsupported["rules"].values():
        classes[rule["class"]] += rule["cases"]
    lines = [
        f"# OpenGL 4.6 conformance test run — {data['date']}", "",
        f"The complete Khronos `cts-runner --type=gl46` run of {data['cts_release']} on one PlayStation 5,",
        "with one driver build. This is the project's own test run, not a Khronos certification.", "",
        f"**{totals['cases']:,} results in {len(data['sessions'])} sessions: "
        f"{totals.get('Pass', 0):,} Pass, {totals.get('NotSupported', 0):,} NotSupported, "
        f"{totals['warnings']:,} warnings, 0 failures.**", "",
        "| # | Session log | Cases | Pass | NotSupported | Warnings |", "|---:|---|---:|---:|---:|---:|",
    ]
    for session in data["sessions"]:
        results = session["results"]
        warnings = results.get("QualityWarning", 0) + results.get("CompatibilityWarning", 0)
        lines.append(f"| {session['index']} | `{session['log']}` | {session['cases']:,} | "
                     f"{results.get('Pass', 0):,} | {results.get('NotSupported', 0):,} | {warnings:,} |")
    lines += ["", "Every NotSupported result is justified by a rule in "
              "[notsupported.md](notsupported.md):", "",
              "| Class | Results |", "|---|---:|"]
    lines += [f"| {name} | {count:,} |" for name, count in sorted(classes.items())]
    window = data.get("window_surface_run")
    if window:
        lines += ["", f"The {window['covers_not_supported']} surface-type results are cases that create their own "
                  "context and insist on a window surface, while the conformant EGL config has pbuffers only. "
                  f"Run on the same binary with `{window['environment']}`, which gives them the offscreen "
                  f"surface as their window, all {window['cases']} cases of those sessions pass "
                  f"([{WINDOW_FILE}]({WINDOW_FILE})). That run is supplementary; it is not part of the "
                  "official run above."]
    lines += ["", "| File | Meaning |", "|---|---|",
              "| [cases.csv.gz](cases.csv.gz) | Every session, case and result |",
              "| [cts-run-summary.xml](cts-run-summary.xml) | The runner's summary |",
              "| [notsupported.md](notsupported.md), [notsupported.json](notsupported.json) | "
              "Justification of the NotSupported results |",
              "| [run.json](run.json) | Source commit, test binary, session command lines, "
              "counts and raw-log hashes |",
              "| [SHA256SUMS](SHA256SUMS) | Integrity of the exported files |"]
    if window:
        lines.append(f"| [{WINDOW_FILE}]({WINDOW_FILE}) | The supplementary window-surface run |")
    lines += ["",
              "```sh", f"python3 tools/verify-cts-official-run.py validation/{data['directory']}", "```", "",
              f"Source commit `{data['source_commit']}`, test binary SHA-256 `{data['eboot_sha256']}`."]
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("run", type=Path)
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--mustpass", type=Path, required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--eboot", type=Path, required=True)
    parser.add_argument("--cts", required=True)
    parser.add_argument("--date", required=True)
    parser.add_argument("--window-run", type=Path)
    args = parser.parse_args()

    sessions, rows = collect(args.run, args.mustpass)
    notsupported = NOTSUPPORTED.report(args.run)
    if notsupported["unclassified"]:
        sys.exit(f"{len(notsupported['unclassified'])} NotSupported results are not justified")
    if (args.run / "crashes.txt").exists() and (args.run / "crashes.txt").read_text().strip():
        sys.exit("the run recorded crashes")

    totals = collections.Counter()
    for session in sessions:
        totals.update(session["results"])
    totals_out = dict(sorted(totals.items()))
    totals_out["cases"] = len(rows)
    totals_out["warnings"] = totals.get("QualityWarning", 0) + totals.get("CompatibilityWarning", 0)
    data = {
        "schema": 1, "date": args.date, "directory": args.evidence.name,
        "cts_release": args.cts, "runner": "the sessions of cts-runner --type=gl46",
        "source_commit": args.commit, "eboot_sha256": sha256(args.eboot),
        "sessions": sessions, "totals": totals_out,
    }
    files = list(DATA_FILES)
    args.evidence.mkdir(parents=True, exist_ok=True)
    if args.window_run:
        data["window_surface_run"], window_rows = collect_window(args.window_run, rows)
        with (args.evidence / WINDOW_FILE).open("w", newline="") as stream:
            writer = csv.writer(stream, lineterminator="\n")
            writer.writerow(["session", "case", "status"])
            writer.writerows(window_rows)
        files.append(WINDOW_FILE)
    text = io.StringIO()
    writer = csv.writer(text, lineterminator="\n")
    writer.writerow(["session", "case", "status"])
    writer.writerows(rows)
    with (args.evidence / "cases.csv.gz").open("wb") as raw:
        # mtime=0 keeps the archive reproducible.
        with gzip.GzipFile(fileobj=raw, mode="wb", mtime=0) as stream:
            stream.write(text.getvalue().encode())
    if RESULTS.summary(args.run, args.evidence / "cts-run-summary.xml") != 0:
        sys.exit("the runner summary is not conformant")
    (args.evidence / "notsupported.json").write_text(json.dumps(notsupported, indent=2) + "\n")
    (args.evidence / "notsupported.md").write_text(NOTSUPPORTED.markdown(notsupported))
    (args.evidence / "run.json").write_text(json.dumps(data, indent=2) + "\n")
    (args.evidence / "README.md").write_text(readme(data, notsupported))
    (args.evidence / "SHA256SUMS").write_text(
        "".join(f"{sha256(args.evidence / name)}  {name}\n" for name in files))
    print(f"exported {len(rows)} results to {args.evidence}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
