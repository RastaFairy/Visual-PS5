# OpenGL 4.6 conformance test run — 2026-10-01

The complete Khronos `cts-runner --type=gl46` run of opengl-cts-4.6.8.1 on one PlayStation 5,
with one driver build. This is the project's own test run, not a Khronos certification.

**122,799 results in 11 sessions: 98,590 Pass, 24,205 NotSupported, 4 warnings, 0 failures.**

| # | Session log | Cases | Pass | NotSupported | Warnings |
|---:|---|---:|---:|---:|---:|
| 1 | `config-gl45-es3-main-cfg-1-run-0-width-256-height-256-egl.qpa` | 1,325 | 1,325 | 0 | 0 |
| 2 | `config-gl45-es31-main-cfg-1-run-1-width-256-height-256-egl.qpa` | 31,248 | 30,866 | 382 | 0 |
| 3 | `config-gl30-khr-main-cfg-1-run-0-width-64-height-64-seed-1-egl.qpa` | 1 | 0 | 1 | 0 |
| 4 | `config-gl40-khr-main-cfg-1-run-1-width-64-height-64-seed-1-egl.qpa` | 1 | 1 | 0 | 0 |
| 5 | `config-gl43-khr-main-cfg-1-run-2-width-64-height-64-seed-1-egl.qpa` | 12 | 0 | 12 | 0 |
| 6 | `config-gl45-khr-main-cfg-1-run-3-width-64-height-64-seed-1-egl.qpa` | 8 | 2 | 6 | 0 |
| 7 | `config-gl46-khr-single-cfg-1-run-3-width-64-height-64-seed-1-egl.qpa` | 11,348 | 5,056 | 6,292 | 0 |
| 8 | `config-gl46-main-cfg-2-run-0-width-64-height-64-seed-1-egl.qpa` | 19,714 | 15,335 | 4,378 | 1 |
| 9 | `config-gl46-main-cfg-2-run-1-width-113-height-47-seed-2-egl.qpa` | 19,714 | 15,335 | 4,378 | 1 |
| 10 | `config-gl46-main-cfg-2-run-2-width-64-height--1-seed-3-egl.qpa` | 19,714 | 15,335 | 4,378 | 1 |
| 11 | `config-gl46-main-cfg-2-run-3-width--1-height-64-seed-3-egl.qpa` | 19,714 | 15,335 | 4,378 | 1 |

Every NotSupported result is justified by a rule in [notsupported.md](notsupported.md):

| Class | Results |
|---|---:|
| minimum-limit | 35 |
| not-applicable | 871 |
| optional-extension | 22,748 |
| sample-count | 532 |
| surface-type | 19 |

The 19 surface-type results are cases that create their own context and insist on a window surface, while the conformant EGL config has pbuffers only. Run on the same binary with `PS5_CTS_OFFSCREEN_WINDOW=1`, which gives them the offscreen surface as their window, all 22 cases of those sessions pass ([window-surface-cases.csv](window-surface-cases.csv)). That run is supplementary; it is not part of the official run above.

| File | Meaning |
|---|---|
| [cases.csv.gz](cases.csv.gz) | Every session, case and result |
| [cts-run-summary.xml](cts-run-summary.xml) | The runner's summary |
| [notsupported.md](notsupported.md), [notsupported.json](notsupported.json) | Justification of the NotSupported results |
| [run.json](run.json) | Source commit, test binary, session command lines, counts and raw-log hashes |
| [SHA256SUMS](SHA256SUMS) | Integrity of the exported files |
| [window-surface-cases.csv](window-surface-cases.csv) | The supplementary window-surface run |

```sh
python3 tools/verify-cts-official-run.py validation/2026-10-01-gl46-conformance
```

Source commit `3b8c0ca075f282f13ecbb3db2d468c2d5db91c4f`, test binary SHA-256 `979f24f00421be7ee22e679394bef07f0c13fc9a4832bb2199a4eedd585ee5af`.
