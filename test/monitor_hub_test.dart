import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turbomon/models/settings.dart';
import 'package:turbomon/services/access.dart';
import 'package:turbomon/services/monitor_hub.dart';
import 'package:turbomon/services/system_reader.dart';

import 'support/fake_files.dart';
import 'support/fake_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MonitorHub hub(FakePlatform platform, AlertRule rule) {
    return MonitorHub(
      reader: SystemReader(
        platform: platform,
        access: AccessController(platform),
        files: FakeFiles({
          '/proc/meminfo': File('test/fixtures/meminfo.txt').readAsStringSync(),
        }),
      ),
      platform: platform,
      settings: const AppSettings(),
    )..applySettings(AppSettings(alerts: [rule]));
  }

  test(
    'an alert with Snapshot ticked saves one while the app is open',
    () async {
      final platform = FakePlatform();
      var snapshots = 0;
      final h = hub(
        platform,
        const AlertRule(
          metric: AlertMetric.ram,
          enabled: true,
          threshold: 1,
          durationSeconds: 0,
          autoSnapshot: true,
        ),
      )..onAutoSnapshot = () async => snapshots++;
      await h.tick();
      expect(h.firedAlerts, hasLength(1));
      expect(snapshots, 1);
      h.dispose();
    },
  );

  test('alerts without Snapshot ticked save nothing', () async {
    final platform = FakePlatform();
    var snapshots = 0;
    final h = hub(
      platform,
      const AlertRule(
        metric: AlertMetric.ram,
        enabled: true,
        threshold: 1,
        durationSeconds: 0,
      ),
    )..onAutoSnapshot = () async => snapshots++;
    await h.tick();
    expect(h.firedAlerts, hasLength(1));
    expect(snapshots, 0);
    h.dispose();
  });
}
