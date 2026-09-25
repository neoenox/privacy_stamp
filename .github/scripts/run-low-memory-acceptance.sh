#!/usr/bin/env bash
set -u -o pipefail

package=com.privacy_stamp
log=.ci-logs/android/acceptance.log
samples=.ci-logs/android/memory-samples.tsv
report=.ci-logs/android/acceptance-summary.txt
exit_info_before=.ci-logs/android/exit-info-before-relaunch.txt
exit_info_after=.ci-logs/android/exit-info-after-relaunch.txt
runtime_log=.ci-logs/android/runtime-logcat.txt
liveness_log=.ci-logs/android/adb-liveness.tsv
host_emulator_log=.ci-logs/android/host-emulator-samples.tsv
mkdir -p .ci-logs/android
: > "$samples"
: > "$runtime_log"
: > "$liveness_log"
: > "$host_emulator_log"

timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

timeout_bin="$(command -v timeout || command -v gtimeout || true)"
if [[ -z "$timeout_bin" ]]; then
  echo 'Required timeout utility is unavailable.' | tee "$report"
  exit 30
fi

capture_adb_failure_diagnostics() {
  local label="$1"
  local safe_label="${label//[^A-Za-z0-9_.-]/_}"
  local prefix=".ci-logs/android/failure-${safe_label}"

  printf 'Capturing ADB failure diagnostics for %s at %s\n' "$label" "$(timestamp)" \
    | tee -a .ci-logs/android/progress.log
  "$timeout_bin" --signal=TERM --kill-after=3s 10s adb devices -l \
    > "${prefix}-adb-devices.txt" 2>&1 || true
  "$timeout_bin" --signal=TERM --kill-after=3s 10s adb get-state \
    > "${prefix}-adb-state.txt" 2>&1 || true
  "$timeout_bin" --signal=TERM --kill-after=3s 10s adb shell getprop \
    > "${prefix}-getprop.txt" 2>&1 || true
  "$timeout_bin" --signal=TERM --kill-after=3s 10s adb shell cat /proc/meminfo \
    > "${prefix}-meminfo.txt" 2>&1 || true
  "$timeout_bin" --signal=TERM --kill-after=3s 15s adb logcat -d -v threadtime \
    > "${prefix}-logcat.txt" 2>&1 || true
}

adb_ready_once() {
  local state boot_completed
  "$timeout_bin" --signal=TERM --kill-after=3s 10s adb wait-for-device \
    >/dev/null 2>&1 || return 1
  state=$("$timeout_bin" --signal=TERM --kill-after=3s 10s adb get-state 2>/dev/null \
    | tr -d '\r') || return 1
  [[ "$state" == "device" ]] || return 1
  boot_completed=$("$timeout_bin" --signal=TERM --kill-after=3s 10s \
    adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r') || return 1
  [[ "$boot_completed" == "1" ]] || return 1
  "$timeout_bin" --signal=TERM --kill-after=3s 10s \
    adb shell cmd package list packages >/dev/null 2>&1 || return 1
}

wait_for_adb_stable() {
  local attempt
  for attempt in $(seq 1 10); do
    if adb_ready_once; then
      sleep 2
      if adb_ready_once; then
        return 0
      fi
    fi
    sleep 2
  done
  return 1
}

recover_adb_transport() {
  if wait_for_adb_stable; then
    return 0
  fi

  printf 'ADB transport is unstable; requesting reconnect at %s\n' "$(timestamp)" \
    | tee -a .ci-logs/android/progress.log
  adb reconnect >/dev/null 2>&1 || true
  if wait_for_adb_stable; then
    return 0
  fi

  printf 'ADB reconnect did not recover; restarting host ADB server at %s\n' "$(timestamp)" \
    | tee -a .ci-logs/android/progress.log
  adb kill-server >/dev/null 2>&1 || true
  adb start-server >/dev/null 2>&1 || true
  wait_for_adb_stable
}

install_apk_with_retry() {
  local apk_path="$1"
  local label="$2"
  local install_log="$3"
  local attempt status

  : > "$install_log"
  for attempt in 1 2 3; do
    printf 'Installing %s APK (attempt %s/3) at %s\n' "$label" "$attempt" "$(timestamp)" \
      | tee -a .ci-logs/android/progress.log

    if ! recover_adb_transport; then
      printf 'ADB was not stable before %s install attempt %s.\n' "$label" "$attempt" \
        | tee -a "$install_log"
      status=1
    else
      "$timeout_bin" --signal=TERM --kill-after=5s 60s adb install -r "$apk_path" \
        >> "$install_log" 2>&1
      status=$?
      if (( status == 0 )); then
        if wait_for_adb_stable; then
          printf '%s APK installed and ADB remained stable.\n' "$label" \
            | tee -a .ci-logs/android/progress.log
          return 0
        fi
        printf '%s APK install succeeded but ADB transport became unstable.\n' "$label" \
          | tee -a "$install_log"
        status=1
      fi
    fi

    printf '%s APK install attempt %s failed with exit %s.\n' "$label" "$attempt" "$status" \
      | tee -a .ci-logs/android/progress.log
    capture_adb_failure_diagnostics "${label}-install-attempt-${attempt}"
    (( attempt < 3 )) && sleep 5
  done

  return 1
}

printf 'AVD runner action handed off to test script at %s\n' "$(timestamp)" | tee -a .ci-logs/android/progress.log
actual_sha=$(git rev-parse HEAD 2>/dev/null || echo 'unknown')
printf 'Actual checkout SHA: %s\n' "$actual_sha" | tee -a .ci-logs/android/progress.log

preflight() {
  local label="$1"
  shift
  if ! "$@" > .ci-logs/android/preflight-${label}.txt 2>&1; then
    echo "Pre-flight check failed: ${label}" | tee "$report"
    exit 40
  fi
}

preflight adb-devices adb devices -l
preflight getprop adb shell getprop
preflight meminfo adb shell cat /proc/meminfo

fixture_probe=.ci-logs/android/preflight-synthetic-fixture.json
if ! dart run tool/acceptance/image_metadata_probe.dart \
  test/fixtures/synthetic-high-res-avd.jpg > "$fixture_probe" 2>&1; then
  echo 'Synthetic fixture metadata probe failed on the host.' | tee "$report"
  exit 47
fi
if ! python3 - "$fixture_probe" <<'PYFIXTURE'
import json
import sys

with open(sys.argv[1], encoding='utf-8') as handle:
    metadata = json.load(handle)
expected = {
    'format': 'JPEG',
    'width': 6000,
    'height': 8000,
    'pixels': 48000000,
    'gpsPresent': True,
}
for key, value in expected.items():
    if metadata.get(key) != value:
        raise SystemExit(f'fixture {key}={metadata.get(key)!r}, expected {value!r}')
PYFIXTURE
then
  echo 'Synthetic fixture does not satisfy the exact 48MP/GPS acceptance contract.' | tee "$report"
  exit 48
fi
printf 'Synthetic fixture preflight passed on host: 6000x8000 JPEG with GPS metadata.\n' \
  | tee -a .ci-logs/android/progress.log

api=$(adb shell getprop ro.build.version.sdk | tr -d '\r')
abi=$(adb shell getprop ro.product.cpu.abi | tr -d '\r')
if [[ "$api" != "35" ]]; then
  echo "Unexpected API level: $api (expected 35)" | tee "$report"
  exit 41
fi
if [[ "$abi" != "x86_64" ]]; then
  echo "Unexpected ABI: $abi (expected x86_64)" | tee "$report"
  exit 42
fi
integration_apk_path="build/app/outputs/flutter-apk/app-debug-integration.apk"
main_apk_path="build/app/outputs/flutter-apk/app-debug-main.apk"
if [[ ! -f "$integration_apk_path" ]]; then
  echo "Integration-test APK not found at $integration_apk_path" | tee "$report"
  exit 44
fi
if [[ ! -f "$main_apk_path" ]]; then
  echo "Production debug APK not found at $main_apk_path" | tee "$report"
  exit 46
fi
if ! install_apk_with_retry "$integration_apk_path" integration-test \
  .ci-logs/android/apk-install-integration.log; then
  echo "Failed to install integration-test debug APK after bounded ADB recovery." | tee "$report"
  capture_adb_failure_diagnostics integration-install-final
  exit 45
fi
if ! adb shell pm list packages 2>/dev/null | grep -q "^package:${package}$"; then
  echo "Expected package ${package} is not installed." | tee "$report"
  capture_adb_failure_diagnostics package-verification
  exit 43
fi

mem_total_kb=$(adb shell cat /proc/meminfo | awk '/^MemTotal:/ {print $2}' | tr -d '\r')
if [[ ! "$mem_total_kb" =~ ^[0-9]+$ ]]; then
  echo 'Unable to read guest MemTotal.' | tee "$report"
  exit 31
fi
if (( mem_total_kb < 1048576 || mem_total_kb > 2097152 )); then
  printf 'Guest RAM is outside the required 1-2 GiB window: %s kB\n' "$mem_total_kb" | tee "$report"
  exit 32
fi
printf 'Guest MemTotal: %s kB\n' "$mem_total_kb" | tee -a .ci-logs/android/progress.log

adb logcat -c || true

sample_memory() {
  while ! grep -q 'ACCEPTANCE_MILESTONE .* A:start' "$log" 2>/dev/null; do
    sleep 1
  done
  printf 'Memory sampling started after A:start at %s\n' "$(timestamp)" | tee -a .ci-logs/android/progress.log

  while true; do
    now=$(timestamp)
    pid=$(adb shell pidof "$package" 2>/dev/null | tr -d '\r' | awk '{print $1}')
    if [[ "$pid" =~ ^[0-9]+$ ]]; then
      # Avoid dumpsys meminfo here: on a constrained API 35 Google APIs
      # guest it serializes through system_server and can itself cause long
      # monitor contention/ANRs. The integration APK is debuggable, so run-as
      # can read the target process' smaps_rollup directly without invoking an
      # application dump callback or system_server.
      pss=$("$timeout_bin" --signal=TERM --kill-after=2s 5s \
        adb shell run-as "$package" cat "/proc/$pid/smaps_rollup" 2>/dev/null \
        | awk '/^Pss:/ {print $2; exit}' | tr -d '\r')
      if [[ ! "$pss" =~ ^[0-9]+$ ]]; then
        pss=0
      fi
      printf '%s\t%s\t%s\n' "$now" "$pid" "$pss" >> "$samples"
    fi
    sleep 2
  done
}

stream_runtime_logcat() {
  while ! grep -q 'ACCEPTANCE_MILESTONE .* A:start' "$log" 2>/dev/null; do
    sleep 1
  done
  printf 'Continuous logcat capture started after A:start at %s\n' "$(timestamp)" \
    | tee -a .ci-logs/android/progress.log
  adb logcat -v threadtime > "$runtime_log" 2>&1 || true
}

sample_host_liveness() {
  while ! grep -q 'ACCEPTANCE_MILESTONE .* A:start' "$log" 2>/dev/null; do
    sleep 1
  done
  printf 'Host/ADB liveness sampling started after A:start at %s\n' "$(timestamp)" \
    | tee -a .ci-logs/android/progress.log
  while true; do
    now=$(timestamp)
    state=$(adb get-state 2>&1 | tr -d '\r\n')
    status=$?
    printf '%s\t%s\t%s\n' "$now" "$status" "$state" >> "$liveness_log"
    ps -axo pid=,rss=,command= \
      | grep -E '[q]emu-system|[e]mulator( |$)|[c]rashpad_handler' \
      | awk -v now="$now" '{printf "%s\t%s\t%s\t", now, $1, $2; for (i=3;i<=NF;i++) printf "%s%s", $i, (i<NF?" ":"\n")}' \
      >> "$host_emulator_log" || true
    sleep 2
  done
}

sample_memory &
sampler_pid=$!
stream_runtime_logcat &
logcat_pid=$!
sample_host_liveness &
liveness_pid=$!
cleanup_monitors() {
  kill "$sampler_pid" "$logcat_pid" "$liveness_pid" 2>/dev/null || true
  wait "$sampler_pid" "$logcat_pid" "$liveness_pid" 2>/dev/null || true
}
trap cleanup_monitors EXIT

printf 'Running emulator-backed A-C synthetic acceptance (12 minute step limit).\n' | tee -a .ci-logs/android/progress.log
set +e
"$timeout_bin" --signal=TERM --kill-after=30s 12m \
  flutter drive -d emulator-5554 \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/synthetic_low_memory_acceptance_test.dart \
  --use-application-binary="$integration_apk_path" \
  --no-pub \
  --no-dds \
  2>&1 | tee "$log"
test_status=${PIPESTATUS[0]}
set -e
cleanup_monitors
trap - EXIT

if (( test_status != 0 )); then
  last_milestone=$(grep 'ACCEPTANCE_MILESTONE' "$log" | tail -n 1 || true)
  {
    printf 'Synthetic A-C acceptance failed with exit %s.\n' "$test_status"
    if [[ -n "$last_milestone" ]]; then
      printf 'last_milestone=%s\n' "$last_milestone"
    else
      printf 'last_milestone=none\n'
    fi
    printf 'continuous_logcat=%s\n' "$runtime_log"
    printf 'adb_liveness=%s\n' "$liveness_log"
    printf 'host_emulator_samples=%s\n' "$host_emulator_log"
  } | tee "$report"
  exit "$test_status"
fi

if [[ ! -s "$samples" ]]; then
  echo 'No application PID/memory samples were captured.' | tee "$report"
  exit 33
fi

unique_pids=$(awk -F '\t' '{print $2}' "$samples" | sort -u | wc -l | tr -d ' ')
peak_pss_kb=$(awk -F '\t' 'BEGIN{m=0} $3+0>m{m=$3+0} END{print m}' "$samples")
first_pid=$(awk -F '\t' 'NR==1{print $2}' "$samples")
last_pid=$(awk -F '\t' 'END{print $2}' "$samples")
restart_count=$(( unique_pids > 0 ? unique_pids - 1 : 0 ))

adb shell dumpsys activity exit-info "$package" > "$exit_info_before" 2>&1 || true
if grep -Eq 'REASON_(CRASH|ANR|LOW_MEMORY)|reason=(4|6|3)' "$exit_info_before"; then
  echo 'Unexpected crash/ANR/low-memory process exit was recorded before lifecycle D.' | tee "$report"
  exit 34
fi
if (( restart_count != 0 )); then
  printf 'Unexpected PID restart(s) during A-C: %s\n' "$restart_count" | tee "$report"
  exit 35
fi

printf 'Restoring production debug APK before lifecycle D.\n' | tee -a .ci-logs/android/progress.log
if ! install_apk_with_retry "$main_apk_path" production \
  .ci-logs/android/apk-install-main.log; then
  echo 'Failed to restore production debug APK before lifecycle D after bounded ADB recovery.' | tee "$report"
  capture_adb_failure_diagnostics production-restore-final
  exit 47
fi

printf 'Running D: force-stop and relaunch lifecycle acceptance.\n' | tee -a .ci-logs/android/progress.log
adb shell am force-stop "$package"
sleep 2
if adb shell pidof "$package" 2>/dev/null | grep -Eq '[0-9]'; then
  echo 'Application process remained alive after force-stop.' | tee "$report"
  exit 36
fi

adb shell monkey -p "$package" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
new_pid=''
for _ in $(seq 1 30); do
  new_pid=$(adb shell pidof "$package" 2>/dev/null | tr -d '\r' | awk '{print $1}')
  [[ "$new_pid" =~ ^[0-9]+$ ]] && break
  sleep 1
done
if [[ ! "$new_pid" =~ ^[0-9]+$ ]]; then
  echo 'Application did not relaunch after force-stop.' | tee "$report"
  exit 37
fi

sleep 3
adb shell dumpsys activity exit-info "$package" > "$exit_info_after" 2>&1 || true
adb logcat -d -v threadtime > .ci-logs/android/app-logcat-full.txt 2>&1 || true
grep -E 'com\.privacy_stamp|FATAL EXCEPTION|OutOfMemoryError|ANR in com\.privacy_stamp' \
  .ci-logs/android/app-logcat-full.txt > .ci-logs/android/app-logcat-filtered.txt || true
if grep -Eq 'FATAL EXCEPTION|OutOfMemoryError|ANR in com\.privacy_stamp' .ci-logs/android/app-logcat-filtered.txt; then
  echo 'Fatal/ANR/OOM evidence found in application logcat.' | tee "$report"
  exit 38
fi

cat > "$report" <<EOF
result=PASS
source_sha=${actual_sha}
api_level=35
target=google_apis
arch=x86_64
guest_mem_total_kb=$mem_total_kb
fixture_pixels=48000000
input_gps=present
output_format=PNG
output_pixels_match=true
output_gps=absent
sensitive_metadata=absent
sample_count=$(wc -l < "$samples" | tr -d ' ')
peak_pss_kb=$peak_pss_kb
pid_first=$first_pid
pid_last_before_lifecycle=$last_pid
involuntary_restart_count=$restart_count
force_stop_relaunch_pid=$new_pid
crash_anr_oom_before_lifecycle=0
crash_anr_oom_after_relaunch=0
private_inputs=0
EOF

cat "$report"
printf 'Synthetic acceptance ended at %s with PASS.\n' "$(timestamp)" | tee -a .ci-logs/android/progress.log
