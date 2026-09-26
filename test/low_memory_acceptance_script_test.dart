import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reuses the prebuilt integration-test APK for emulator acceptance', () {
    final script = File(
      '.github/scripts/run-low-memory-acceptance.sh',
    ).readAsStringSync();
    final workflow = File(
      '.github/workflows/local-acceptance-scripts.yml',
    ).readAsStringSync();

    expect(script, contains('flutter drive'));
    expect(script, contains('--no-pub'));
    expect(script, contains('--driver=test_driver/integration_test.dart'));
    expect(
      script,
      contains(r'--use-application-binary="$integration_apk_path"'),
    );
    expect(
      workflow,
      contains(
        'flutter build apk --debug --target=integration_test/'
        'synthetic_low_memory_acceptance_test.dart',
      ),
      reason: 'The reused APK must contain the integration-test entry point.',
    );
    expect(workflow, contains('app-debug-integration.apk'));
    expect(
      workflow,
      contains('app-debug-main.apk'),
      reason: 'Lifecycle D must restore and launch the production entry point.',
    );
    expect(
      script.indexOf(r'install_apk_with_retry "$main_apk_path" production'),
      lessThan(script.indexOf("printf 'Running D:")),
    );
    expect(
      script,
      isNot(contains('flutter test -d emulator-5554 integration_test/')),
    );

    final integrationTest = File(
      'integration_test/synthetic_low_memory_acceptance_test.dart',
    ).readAsStringSync();
    expect(
      integrationTest,
      isNot(contains("package:flutter_driver/driver_extension.dart")),
      reason:
          'integration_test must own the binding; the legacy flutter_driver '
          'extension conflicts with its bootstrap path.',
    );
    expect(
      integrationTest,
      isNot(contains('enableFlutterDriverExtension();')),
      reason:
          'flutter drive + integration_test does not require the legacy '
          'driver extension in the test entry point.',
    );
    expect(
      integrationTest,
      contains('IntegrationTestWidgetsFlutterBinding.ensureInitialized();'),
      reason: 'The integration_test binding must initialize the test entry.',
    );
    expect(
      integrationTest,
      isNot(contains('pumpAndSettle()')),
      reason: 'The low-memory 48MP route must use bounded waits.',
    );
  });

  test(
    'recovers bounded transient ADB transport failures without weakening AVD',
    () {
      final script = File(
        '.github/scripts/run-low-memory-acceptance.sh',
      ).readAsStringSync();
      final ciWrapper = File(
        '.github/scripts/run-low-memory-acceptance-ci.sh',
      ).readAsStringSync();
      final workflow = File(
        '.github/workflows/local-acceptance-scripts.yml',
      ).readAsStringSync();

      expect(script, contains('install_apk_with_retry'));
      expect(script, contains('for attempt in 1 2 3'));
      expect(script, contains('adb reconnect'));
      expect(script, contains('adb kill-server'));
      expect(script, contains('adb shell cmd package list packages'));
      expect(script, contains('capture_adb_failure_diagnostics'));
      expect(script, contains(r'"${prefix}-logcat.txt"'));
      expect(
        script,
        contains(
          r'install_apk_with_retry "$integration_apk_path" integration-test',
        ),
      );
      expect(
        ciWrapper,
        contains(r'"$real_adb" shell am wait-for-broadcast-idle'),
        reason:
            'API 35 acceptance must start after Android boot broadcasts are idle, '
            'not after an arbitrary fixed sleep.',
      );
      expect(
        ciWrapper,
        contains(r'"$real_timeout" 180s'),
        reason: 'Post-boot stabilization must remain bounded.',
      );
      expect(
        ciWrapper,
        isNot(contains('sleep 90')),
        reason:
            'A fixed post-boot delay was proven insufficient on the 2 GiB AVD.',
      );
      expect(
        ciWrapper,
        contains(r'install --no-streaming "$@"'),
        reason: 'Low-memory APK installation must avoid streaming pressure.',
      );
      expect(
        ciWrapper,
        contains('args[\$i]="180s"'),
        reason: 'Only the APK-install transport timeout may be extended.',
      );
      expect(
        ciWrapper,
        contains('bash .github/scripts/run-low-memory-acceptance.sh'),
      );
      expect(
        ciWrapper,
        contains(r'bootstrap_logcat=.ci-logs/android/bootstrap-logcat.txt'),
        reason: 'Driver/bootstrap failures before A:start must retain logcat.',
      );
      expect(
        ciWrapper,
        contains(
          r'"$real_adb" logcat -v threadtime > "$bootstrap_logcat" 2>&1 &',
        ),
      );
      expect(ciWrapper, contains('status=\$?'));
      expect(ciWrapper, contains('exit "\$status"'));
      expect(workflow, contains('api-level: 35'));
      expect(workflow, contains('arch: x86_64'));
      expect(
        workflow,
        contains('ram-size: 2048'),
        reason: 'Issue #17 permits a 1-2 GiB guest; use the 2 GiB upper bound.',
      );
      expect(workflow, contains('-memory 2048 -lowram'));
      expect(workflow, contains('emulator-boot-timeout: 900'));
      expect(
        workflow,
        contains(
          'script: bash .github/scripts/run-low-memory-acceptance-ci.sh',
        ),
      );
      expect(
        script,
        contains('12m'),
        reason: 'The A-C acceptance wall clock must remain 12 minutes.',
      );
    },
  );

  test('disables DDS for flutter drive on the low-memory Android emulator', () {
    final ciWrapper = File(
      '.github/scripts/run-low-memory-acceptance-ci.sh',
    ).readAsStringSync();

    expect(ciWrapper, contains(r'real_flutter="$(command -v flutter)"'));
    expect(ciWrapper, contains(r'if [[ "${1:-}" == "drive" ]]'));
    expect(ciWrapper, contains(r'exec "$REAL_FLUTTER" "$@" --no-dds'));
    expect(ciWrapper, contains(r'export REAL_FLUTTER="$real_flutter"'));
  });

  test('does not contend with flutter drive while VM service starts', () {
    final script = File(
      '.github/scripts/run-low-memory-acceptance.sh',
    ).readAsStringSync();

    expect(
      script,
      contains(r'''grep -q 'ACCEPTANCE_MILESTONE .* A:start' "$log"'''),
      reason: 'ADB memory sampling must wait until flutter drive is attached.',
    );
    expect(
      script.indexOf("grep -q 'ACCEPTANCE_MILESTONE .* A:start'"),
      lessThan(script.indexOf(r'pid=$(adb shell pidof')),
    );
  });

  test('samples PSS without invoking the application dump callback', () {
    final script = File(
      '.github/scripts/run-low-memory-acceptance.sh',
    ).readAsStringSync();

    expect(
      script,
      contains(r'adb shell run-as "$package" cat "/proc/$pid/smaps_rollup"'),
      reason:
          'PSS collection must read the debuggable app process directly '
          'instead of serializing through system_server.',
    );
    expect(
      script,
      isNot(contains('dumpsys meminfo')),
      reason:
          'Periodic dumpsys meminfo can stall system_server on the low-memory '
          'Google APIs guest.',
    );
  });
}
