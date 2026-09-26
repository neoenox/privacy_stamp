#!/usr/bin/env bash
set -euo pipefail

# CI-only transport shim for the 2 GiB API 35 AVD.
# The acceptance assertions and the 12-minute A-C wall clock remain in
# run-low-memory-acceptance.sh unchanged. This wrapper only gives Android's
# post-boot broadcast work a bounded best-effort stabilization window, makes APK
# installation less stressful on the low-memory guest, disables DDS for flutter
# drive on the emulator, and captures logcat before the integration test reaches
# A:start so bootstrap failures remain diagnosable.
# Flutter's integration-test guidance recommends --no-dds for mobile devices
# and emulators; keeping the driver connected directly to the VM service also
# avoids the startup boundary that previously stalled before A:start.

real_adb="$(command -v adb)"
real_timeout="$(command -v gtimeout || command -v timeout)"
real_flutter="$(command -v flutter)"
shim_dir="$PWD/.ci-low-memory-bin"
mkdir -p "$shim_dir"

cat > "$shim_dir/adb" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${REAL_ADB:?REAL_ADB is required}"

if [[ "${1:-}" == "install" ]]; then
  shift
  exec "$REAL_ADB" install --no-streaming "$@"
fi

exec "$REAL_ADB" "$@"
EOF

cat > "$shim_dir/timeout" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${REAL_TIMEOUT:?REAL_TIMEOUT is required}"

args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  if [[ "${args[$i]}" != "60s" ]]; then
    continue
  fi
  for ((j = i + 1; j + 1 < ${#args[@]}; j++)); do
    if [[ "${args[$j]}" == "adb" && "${args[$((j + 1))]}" == "install" ]]; then
      args[$i]="180s"
      break 2
    fi
  done
done

exec "$REAL_TIMEOUT" "${args[@]}"
EOF

cat > "$shim_dir/flutter" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${REAL_FLUTTER:?REAL_FLUTTER is required}"

if [[ "${1:-}" == "drive" ]]; then
  for arg in "$@"; do
    if [[ "$arg" == "--no-dds" ]]; then
      exec "$REAL_FLUTTER" "$@"
    fi
  done
  exec "$REAL_FLUTTER" "$@" --no-dds
fi

exec "$REAL_FLUTTER" "$@"
EOF

chmod +x "$shim_dir/adb" "$shim_dir/timeout" "$shim_dir/flutter"
export REAL_ADB="$real_adb"
export REAL_TIMEOUT="$real_timeout"
export REAL_FLUTTER="$real_flutter"
export PATH="$shim_dir:$PATH"

# sys.boot_completed=1 only means Android reached the boot-complete phase. On
# the 2 GiB Google APIs image, queued PRE_BOOT_COMPLETED/BOOT_COMPLETED receivers
# can continue for many minutes. Give ActivityManager a bounded stabilization
# opportunity, but do not make *global* broadcast-idle a prerequisite for the
# app acceptance: stock Google APIs background work can legally remain active
# longer than this job's useful preflight window. The acceptance itself remains
# fail-closed and keeps its unchanged 12-minute A-C wall clock.
printf 'Low-memory AVD boot completed; giving Android broadcast queues a bounded stabilization window.\n'
if "$real_timeout" 180s "$real_adb" shell am wait-for-broadcast-idle; then
  printf 'Android broadcast queues are idle; starting acceptance.\n'
else
  printf 'Android broadcast queues remained active after 180 seconds; continuing to the fail-closed app acceptance.\n' >&2
fi

# Confirm the package manager is responsive before spending the app-acceptance
# clock. This is a narrow readiness check rather than a requirement that every
# background system receiver in the Google APIs image has gone idle.
if ! "$real_timeout" 30s "$real_adb" shell cmd package list packages >/dev/null; then
  printf 'Android package manager did not become responsive; cannot start acceptance reliably.\n' >&2
  exit 1
fi

mkdir -p .ci-logs/android
bootstrap_logcat=.ci-logs/android/bootstrap-logcat.txt
: > "$bootstrap_logcat"
"$real_adb" logcat -v threadtime > "$bootstrap_logcat" 2>&1 &
bootstrap_logcat_pid=$!
cleanup_bootstrap_logcat() {
  kill "$bootstrap_logcat_pid" 2>/dev/null || true
  wait "$bootstrap_logcat_pid" 2>/dev/null || true
}
trap cleanup_bootstrap_logcat EXIT

set +e
bash .github/scripts/run-low-memory-acceptance.sh
status=$?
set -e
cleanup_bootstrap_logcat
trap - EXIT

printf 'Integration bootstrap markers captured from Android logcat:\n'
grep -E 'ACCEPTANCE_(BOOTSTRAP|MILESTONE)' "$bootstrap_logcat" || \
  printf 'No ACCEPTANCE_BOOTSTRAP/ACCEPTANCE_MILESTONE markers were present in Android logcat.\n'

exit "$status"
