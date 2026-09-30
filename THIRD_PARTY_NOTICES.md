# Third-party notices

This file lists the direct dependencies declared in `pubspec.yaml`. The lockfile
also contains transitive packages; a distribution build must generate and ship
the applicable notices and full license texts for that complete graph.

## Direct runtime dependencies

| Dependency | License |
| --- | --- |
| Flutter SDK | BSD-3-Clause |
| file_picker | MIT |
| image | MIT |
| shared_preferences | BSD-3-Clause |
| google_mlkit_face_detection (+ google_mlkit_commons) | Apache-2.0 |
| google_mlkit_text_recognition | Apache-2.0 |
| google_mlkit_barcode_scanning | Apache-2.0 |

## Direct development dependencies

| Dependency | License |
| --- | --- |
| flutter_test | BSD-3-Clause (Flutter SDK) |
| flutter_lints | BSD-3-Clause |

The detector assets named in the architecture contracts are intentionally not
bundled: Web MediaPipe, Tesseract.js, and ZXing have no current
runtime integration or corresponding asset notice here. If they are added,
record their licenses, versions, redistribution terms, and asset contents
before shipping.

Before an Android or Web production release, audit the complete `pubspec.lock`
dependency graph, platform SDK notices, generated artifacts, fonts/icons, and
any detector assets. This document is not a substitute for that release audit.
