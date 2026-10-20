#!/usr/bin/env python3
# PS5 OpenGL - OpenGL implementation for PlayStation 5.
# Copyright (C) 2026 BlackBearReloaded
# SPDX-License-Identifier: GPL-3.0-or-later

"""Verify exported official-run evidence (tools/export-cts-official-run.py).

Checks the published files against each other; it does not rerun any test.
"""

from __future__ import annotations

import argparse
import collections
import csv
import gzip
import hashlib
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ACCEPTED = {"Pass", "NotSupported", "QualityWarning", "CompatibilityWarning", "Waiver"}
DATA_FILES = {"cases.csv.gz", "cts-run-summary.xml", "notsupported.json", "notsupported.md", "run.json"}
WINDOW_FILE = "window-surface-cases.csv"
WINDOW_PREFIX = "KHR-NoContext."


def require(condition: bool, message: str) -> None:
    if not condition:
        sys.exit(f"official-run evidence: {message}")


def verify(evidence: Path) -> dict:
    sums = {}
    for line in (evidence / "SHA256SUMS").read_text().splitlines():
        digest, name = line.split("  ", 1)
        require(name not in sums and (evidence / name).resolve().parent == evidence.resolve(),
                f"bad checksum entry {name}")
        require(hashlib.sha256((evidence / name).read_bytes()).hexdigest() == digest,
                f"checksum mismatch: {name}")
        sums[name] = digest
    run = json.loads((evidence / "run.json").read_text())
    window = run.get("window_surface_run")
    require(set(sums) == DATA_FILES | ({WINDOW_FILE} if window else set()),
            "incomplete checksum inventory")
    with gzip.open(evidence / "cases.csv.gz", "rt", encoding="utf-8", newline="") as stream:
        rows = list(csv.DictReader(stream))
    per_session = collections.defaultdict(collections.Counter)
    seen = set()
    for row in rows:
        key = (row["session"], row["case"])
        require(key not in seen, f"duplicate result {key}")
        seen.add(key)
        require(row["status"] in ACCEPTED, f"{row['case']}: {row['status']}")
        per_session[row["session"]][row["status"]] += 1
    require([s["log"] for s in run["sessions"]] == list(dict.fromkeys(r["session"] for r in rows)),
            "session inventory or order mismatch")
    totals = collections.Counter()
    for session in run["sessions"]:
        counts = per_session[session["log"]]
        require(dict(sorted(counts.items())) == session["results"] and
                sum(counts.values()) == session["cases"], f"{session['log']}: count mismatch")
        totals.update(counts)
    require(sum(totals.values()) == run["totals"]["cases"] == len(rows), "total mismatch")
    for status, count in totals.items():
        require(run["totals"].get(status) == count, f"total {status} mismatch")

    summary = ET.parse(evidence / "cts-run-summary.xml").getroot()
    require(summary.get("Type") == "gl46" and summary.get("Conformant") == "True",
            "runner summary is not conformant")
    runs = list(summary.iter("TestRun"))
    require([e.get("FileName") for e in runs] == [s["log"] for s in run["sessions"]],
            "runner summary sessions mismatch")
    for element, session in zip(runs, run["sessions"]):
        result = element.find("TestResult")
        require(element.get("CmdLine") == session["command_line"], "command line mismatch")
        require(int(result.get("Failed")) == 0 and
                int(result.get("Passed")) == session["results"].get("Pass", 0) and
                int(result.get("NotSupported")) == session["results"].get("NotSupported", 0) and
                int(result.get("Executed")) == session["cases"], f"{session['log']}: summary mismatch")

    notsupported = json.loads((evidence / "notsupported.json").read_text())
    require(notsupported["unclassified"] == [], "unjustified NotSupported results")
    require(sum(rule["cases"] for rule in notsupported["rules"].values()) ==
            totals.get("NotSupported", 0), "NotSupported justification count mismatch")
    for session in run["sessions"]:
        key = session["log"].removesuffix(".qpa")
        require(sum(notsupported["sessions"][key]["not_supported"].values()) ==
                session["results"].get("NotSupported", 0), f"{session['log']}: NotSupported mismatch")

    if window:
        # Every surface-type NotSupported result of the official run passes in the window run.
        skipped = {(row["session"], row["case"]) for row in rows
                   if row["status"] == "NotSupported" and row["case"].startswith(WINDOW_PREFIX)}
        with (evidence / WINDOW_FILE).open(newline="") as stream:
            window_rows = list(csv.DictReader(stream))
        require(all(row["status"] == "Pass" for row in window_rows), "window run has a result other than Pass")
        ran = {(row["session"], row["case"]) for row in window_rows}
        require(len(ran) == len(window_rows) == window["cases"], "window run count mismatch")
        require(skipped <= ran and len(skipped) == window["covers_not_supported"],
                "window run does not cover the surface-type results")
        require(sum(rule["cases"] for rule in notsupported["rules"].values()
                    if rule["class"] == "surface-type") == len(skipped),
                "surface-type justification count mismatch")
    return run


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    args = parser.parse_args()
    run = verify(args.evidence)
    totals = run["totals"]
    window = run.get("window_surface_run")
    print(f"PASS: {args.evidence.name}: {totals['cases']} results in {len(run['sessions'])} sessions, "
          f"{totals.get('Pass', 0)} Pass, {totals.get('NotSupported', 0)} justified NotSupported, "
          f"{totals['warnings']} warnings, 0 failures" +
          (f"; window run {window['cases']} Pass" if window else ""))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
