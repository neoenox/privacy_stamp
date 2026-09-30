# Privacy Stamp MVP status

This document records the repository state, not a production readiness claim.

## Implemented

- Flutter Android/Web project with a local-only landing screen and one-image
  `file_picker` selection flow.
- In-memory image bytes passed through a shared normalized rectangle, detection,
  OCR-region, and stamp contract.
- On-device ML Kit face detection on native platforms (FAST then ACCURATE retry, downscaled
  oriented copy, normalized back-mapping, padded boxes), merged with rule-engine
  hits and exported as automatic stamps with a one-tap clear control.
- On-device ML Kit text recognition on native platforms (Japanese script,
  downscaled oriented copy, line-level normalized regions fed to the
  rule engine for email/phone/postal/card/coordinate/label hits).
- On-device ML Kit barcode scanning on native platforms (all formats,
  downscaled oriented copy, normalized back-mapping, padded boxes,
  every value treated as sensitive).
- Pure Dart rules for email, Japanese/international phone, postal-code review
  candidates, Luhn-valid card candidates, coordinates, labelled values, and an
  all-OCR-region contract for future detector adapters.
- PNG re-encoding with EXIF orientation baked and opaque rectangular masks.
- Manual stamp addition, selection, move, resize, and visible-button removal.
- Separate-file export and locally persisted export history count without a
  billing or free-tier lockout.
- Unit/widget tests for the rule engine, opaque mask export, and local-only
  landing screen.
- GitHub Actions quality gates for format, analyze, test, Web build, Android
  debug build, and a non-distributable Android release smoke build.

## Not implemented

- Web MediaPipe face/OCR adapters, Tesseract.js, and ZXing local bundled
  adapters.
- Automatic face/text/barcode coverage, or a
  guarantee that all sensitive content is hidden.
- Android share-intent receiver and system share-out.
- Google Play Billing purchase/restore, product ID, entitlement state, or an
  enforced free-tier limit.

## Privacy and security boundary

The current application path decodes, masks, and encodes selected image bytes
locally. No server, upload API, analytics SDK, or remote detector is configured
in this repository. This is a code-level boundary, not an independently audited
privacy guarantee.

The MVP threat model covers accidental exposure of visible sensitive regions
before a user publishes an image. It does not cover false negatives, OCR or
detector errors, unsupported content, screenshots/copies, malicious files,
compromised devices or browsers, browser extensions, hosting/CDN behavior,
third-party dependency compromise, or unreviewed metadata and permission
behavior.

Manual review remains mandatory because automatic detectors can miss content. The
exporter creates a separate PNG and does not overwrite the selected source;
tests re-decode output pixels and metadata. Browser DevTools egress inspection
remains unverified.

## Verification status

| Area | Current evidence | Status |
| --- | --- | --- |
| Formatting | `dart format --output=none --set-exit-if-changed .` | CI gate |
| Static analysis | `flutter analyze --fatal-infos` | CI gate |
| Pure Dart/widget tests | `flutter test` | CI gate |
| Web artifact | `flutter build web --release` | CI gate; browser use unverified |
| Android debug artifact | `flutter build apk --debug` | CI gate; device use unverified |
| Android release smoke | `flutter build apk --release` | CI gate when toolchain permits; not distributable |
| Privacy behavior | Pixel/metadata reinspection tests | Browser DevTools egress and full device edit/save flow unverified |

The workflow records command exit codes, test and skip counts, analyzer
warning/info lines, failure commands, logs, and available build artifacts in the
GitHub Actions summary and artifact bundle.

## Android/Web and release blockers

- The Android namespace and application ID are now fixed at
  `com.privacy_stamp`; the manifest label is "Privacy Stamp".
- Release signing is wired via git-ignored `android/key.properties` and
  fails closed when the key is absent; CI smoke builds explicitly opt into
  debug signing. A
  production upload key still needs to be generated on a release machine; see
  `docs/RELEASE.md`.
- Full Android image edit/save interaction, Web Chrome DOM/drag/drop/browser
  storage, deployed-host behavior, and browser network-panel audit are
  unverified. Emulator launch and image-picker cancellation were exercised.
- Full direct and transitive third-party license texts are not bundled for a
  distribution release.
- A production upload key, a Play Console listing, and the Play App Signing
  enrollment have not been created yet; see `docs/RELEASE.md`.
- Production work also needs detector runtime acceptance, review/coverage UX, exported
  pixel reinspection, privacy/network tests, billing/share decisions, and a
  rollback/support plan.
