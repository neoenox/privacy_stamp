# Privacy audit procedure

This procedure is a release gate for the local-only image flow. It is a
procedure, not evidence that the current base or a future build has passed.
Record the exact commit SHA, build mode, artifact path, device/browser, and
date for every run. Do not put real personal data in fixtures, logs, or
screenshots.

## Android merged manifest

Run this against the exact release APK produced from the candidate commit.

```powershell
flutter build apk --release --no-pub
apkanalyzer manifest permissions build\app\outputs\flutter-apk\app-release.apk
aapt2 dump xmltree build\app\outputs\flutter-apk\app-release.apk AndroidManifest.xml > work\release-manifest.xml
```

Pass criteria for the local-only image flow:

- `android.permission.INTERNET` is absent.
- `android.permission.ACCESS_NETWORK_STATE` is absent unless a separately
  approved feature requires it.
- `android:usesCleartextTraffic` is absent or explicitly `false`.
- There are no unexpected providers, services, receivers, intent filters, or
  exported activities that introduce a data-sharing path.
- The output is from the candidate commit and not an older APK in the output
  directory.

If a future feature requires a permission, document the feature, the minimum
scope, and the approval before changing this gate. A static manifest pass does
not prove that runtime code never opens a socket.

## Web communication audit

Run a release-equivalent Web build locally, then inspect the visible flow in a
fresh Chrome profile or a clean incognito window.

1. Start the candidate build and open the local origin.
2. Open DevTools **Network**, enable **Preserve log**, clear the log, and
   filter for `Fetch/XHR`, `WS`, `beacon`, and `Other`.
3. Select an image, run detection/redaction, export the image, and repeat once
   with a transparent image and one with a malformed file.
4. Inspect every request's URL, initiator, request body, response body, and
   destination. Save the HAR only after removing local paths and any user data.

Pass criteria:

- No request is sent to an external origin during image selection, processing,
   or export.
- No image bytes, OCR text, coordinates, filenames, or metadata appear in a
   request body, query string, referrer, console message, or analytics payload.
- Any requests for the local app shell or explicitly approved local assets are
   listed separately and contain no user image data.
- Malformed input fails locally and does not trigger a retry to a remote
   service.

Record `PASS`, `FAIL`, or `NOT RUN` for each criterion. A clean Network panel
is runtime evidence for that browser session only; it is not a substitute for
the Android manifest check, dependency review, or source audit.

## Source and dependency review

Before release, review the candidate diff and dependency graph for new network,
telemetry, upload, or remote-inference code. Confirm that the exported bytes
are re-decoded locally and that the metadata/pixel tests in `test/` run on the
same commit. If an environment prevents a check, record the exact command and
reason as `NOT RUN`; do not infer a pass from a successful compile.

## Face/text/barcode detection adapter notes

`MlKitFaceDetector`, `MlKitTextDetector`, and `MlKitBarcodeDetector` run
Google ML Kit on-device (Android/iOS). Inference sends no image bytes
anywhere: each adapter builds a downscaled oriented BGRA `InputImage`
in memory and maps boxes back through normalized coordinates.

Models: all three use Google ML Kit's **bundled model** format
(`com.google.mlkit:face-detection:16.1.7` and equivalents for text/barcode).
Bundled models ship in the AAR; no runtime download is required.
The app manifest declares no `INTERNET`; Play Services may download
model updates inside its own process (outside this app's UID).
Verify the merged manifest on the candidate APK/AAB as before.

Caveats for the release gate:

- Detection is a hint, not coverage: false negatives remain possible,
  so the mandatory manual-review dialog stays. The UI offers one-tap
  clearing of automatic masks (`自動マスクを消す`).
- Web/desktop builds compile the adapters but always yield zero
  candidates (guarded `kIsWeb` + fail-open `try/catch`), so manual
  masking is the only path there.
- Detection uses ACCURATE mode with `minFaceSize: 0.05` for high recall.
  A first FAST pass at 1024px runs; if zero faces are found, a second
  ACCURATE pass at 2048px runs to catch small faces.
- The face detector returns `DetectionResult` (not just a region list)
  so callers can distinguish "ran but found no faces" from "ML Kit
  failed". See `lib/features/redaction/detection/face_detector.dart`.

## Verified

Run against the exact release APK produced from the candidate commit, on a
**physical Android device** (not an emulator). Record the device model,
Android version, build mode, and commit SHA.

- Release APK (`PRIVACY_STAMP_ALLOW_DEBUG_RELEASE_SIGNING=1` smoke) dumped
  with `aapt2 dump xmltree`: no `INTERNET`, no `ACCESS_NETWORK_STATE`, no
  `usesCleartextTraffic`. Remaining permissions are `BIND_JOB_SERVICE`
  (telemetry transport's own scheduler, inert without network) and `DUMP`
  (standard Flutter profile-install receiver guard). ML Kit components are
  all `exported=false`; the only exported receiver is the standard Flutter
  `ProfileInstallReceiver` behind the `DUMP` permission.
- `INTERNET`/`ACCESS_NETWORK_STATE` arrive via transitive
  `datatransport-backend-cct`/`transport-runtime` AARs and are stripped with
  `tools:node="remove"` in `android/app/src/main/AndroidManifest.xml`.
  (The debug manifest keeps its own `INTERNET` for hot reload; the gate
  applies to release artifacts.)
- Release builds run R8 (Flutter Gradle plugin forces `isMinifyEnabled`).
  Without keeps, face detection NPEs inside obfuscated vision internals
  (debug worked, release failed). `android/app/proguard-rules.pro` keeps
  `com.google.mlkit.**`, `com.google.android.gms.internal.mlkit_vision**`,
  and the Flutter bridge packages. Do not delete that file.
- Face detection on-device with a real-device camera photo: at least 1 face
  found and candidates displayed. Confirm this on the exact commit being
  released; stale APKs from older branches will not contain detection code.
