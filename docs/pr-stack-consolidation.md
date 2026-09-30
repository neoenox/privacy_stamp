# PR stack consolidation — 2026-09-30

The active dependency chain is #51 (current-main CI repair), #54 (image import
errors), then this consolidation branch. Closing an old PR as superseded does
not mean its acceptance passed or its replacement has merged.

| Old PR | Disposition |
| --- | --- |
| #44 | Port acceptance scripts, exact-head workflow, dual APKs, diagnostics, 2 GiB guest, bounded preview and PNG export optimization. Keep #51 adb priming and emulator no-snapshot/camera flags. |
| #46 | Main already has newer detection/diagnostics from #49. Recover immutable Stamp, privacy-chunk guard, manifest permission removal, review/export integration step, regression tests and notices. Keep current detectors and controller fixes. |
| #47 | Main already has OCR implementation. Recover OCR tests and current capability documentation. |
| #48 | Main already has barcode implementation. Recover barcode tests and notices. |
| #50 | Keep #51 explicit ML Kit script dependencies and analyzer repairs. Recover release keep rules and their Gradle wiring, plus test-harness annotation. Do not reintroduce missing-class suppression for scripts now bundled. |

The old #44 Flutter quality workflow is not copied over #51's repaired workflow;
format/analyze/unit/Web/debug/release/signing-guard gates remain in place.
Historical emulator/device results in old PR descriptions are not evidence for
this branch. Branches are retained for provenance.

## Verification and outstanding acceptance

- Local Flutter 3.44.0 / Dart 3.12.0: 114 unit/widget tests passed, then six
  recovered face regression tests passed; analyzer clean.
- CI uses its configured stable Flutter and must validate the pushed candidate.
- #17 remains open: API 35 Google APIs x86_64, 1–2 GiB guest, deterministic
  48MP GPS fixture, pixel equality, metadata stripping, lifecycle and
  OOM/ANR/process-death gates remain mandatory. A–C wall clock stays 12 minutes.
- The #51/#54 prior CI failures were emulator boot timeouts, before app
  acceptance. The restored #44 configuration is a candidate repair, not proof.
- Exact-candidate release face/OCR/barcode runtime and privacy/network audits
  remain required. Build success alone is not detector acceptance.
- No production signing, Secrets, Play Console, release or deployment changes.
