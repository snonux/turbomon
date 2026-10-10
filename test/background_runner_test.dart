import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turbomon/background/background_runner.dart';
import 'package:turbomon/models/monitor.dart';
import 'package:turbomon/models/settings.dart';
import 'package:turbomon/services/access.dart';
import 'package:turbomon/services/history_store.dart';
import 'package:turbomon/services/storage_paths.dart';
import 'package:turbomon/services/system_reader.dart';

import 'support/fake_files.dart';
import 'support/fake_platform.dart';

void main() {
  late Directory root;
  late FakePlatform platform;
  late DateTime now;

  setUp(() {
    root = Directory.systemTemp.createTempSync('turbomon-bg');
    platform = FakePlatform();
    now = DateTime(2026, 10, 10, 22);
  });

  tearDown(() => root.deleteSync(recursive: true));

  BackgroundRunner runner(BackgroundConfig config) {
    final paths = StoragePaths(
      support: Directory('${root.path}/support'),
      cache: Directory('${root.path}/cache'),
    );
    return BackgroundRunner(
      config: config,
      reader: SystemReader(
        platform: platform,
        access: AccessController(platform),
        files: FakeFiles({
          '/proc/meminfo': 'MemTotal: 1000 kB\nMemAvailable: 400 kB\n',
        }),
        clock: () => now,
      ),
      platform: platform,
      history: HistoryStore(paths.history),
      paths: paths,
      clock: () => now,
    );
  }

  test(
    'samples each monitor at its own interval and stops at the deadline',
    () async {
      final r = runner(
        BackgroundConfig(
          plan: ScanPlan(
            monitors: {Monitor.ram: 30, Monitor.battery: 60},
            autoStop: const AutoStop(durationMinutes: 15),
          ),
          overlay: true,
        ),
      );
      expect(r.tick, const Duration(seconds: 30));
      await r.start();
      // start() schedules a periodic timer; the test drives ticks by hand.
      expect(platform.statuses.last, 'RAM, Battery · 15 min left');
      expect(platform.widgetValues.last, {
        'cpu': '–',
        'ram': '60%',
        'battery': '80%',
        'temp': '32°C',
      });
      expect(platform.overlays.last, contains('RAM 60%'));

      now = now.add(const Duration(seconds: 30));
      await r.runOnce();
      expect(
        platform.widgetValues.last['battery'],
        '80%',
        reason: 'battery keeps its last reading between its samples',
      );
      final history = await HistoryStore(
        Directory('${root.path}/support/history'),
      ).read(since: DateTime(2026, 10, 10), until: now);
      expect(history, hasLength(2));
      expect(history[0].keys, containsAll(['ram', 'bat']));
      expect(
        history[1].containsKey('bat'),
        isFalse,
        reason: 'battery is due every 60 s only',
      );

      platform.running = true;
      now = now.add(const Duration(minutes: 15));
      await r.runOnce();
      expect(platform.running, isFalse);
      expect(platform.notifications.last.$2, 'Background scan finished');
      expect(platform.notifications.last.$3, contains('Snapshot saved'));
      final saved = Directory('${root.path}/support/snapshots').listSync();
      expect(saved, hasLength(1));
      expect(
        File(saved.single.path).readAsStringSync(),
        contains('# TurboMon snapshot'),
      );
      expect(platform.overlays.last, isNull);
    },
  );

  test('stops below a battery level', () async {
    platform.batteryInfo = {...platform.batteryInfo, 'percent': 9.0};
    final r = runner(
      BackgroundConfig(
        plan: ScanPlan(
          monitors: {Monitor.battery: 60},
          autoStop: const AutoStop(
            mode: AutoStopMode.batteryBelow,
            batteryBelow: 10,
          ),
          snapshotOnStop: false,
        ),
      ),
    );
    platform.running = true;
    await r.start();
    expect(platform.running, isFalse);
    expect(platform.notifications.last.$3, 'Battery fell below 10 %.');
  });

  test('raises alerts with an automatic snapshot', () async {
    platform.batteryInfo = {...platform.batteryInfo, 'currentNow': -1500000};
    final r = runner(
      BackgroundConfig(
        plan: ScanPlan(
          monitors: {Monitor.battery: 30},
          autoStop: const AutoStop(mode: AutoStopMode.never),
        ),
        alerts: [
          AlertRule.defaults(AlertMetric.batteryDrain).copyWith(
            enabled: true,
            threshold: 1000,
            durationSeconds: 30,
            autoSnapshot: true,
          ),
        ],
      ),
    );
    await r.start();
    now = now.add(const Duration(seconds: 30));
    await r.runOnce();
    expect(platform.notifications.single.$2, 'Battery drain above 1000 mA');
    expect(
      Directory('${root.path}/support/snapshots').listSync(),
      hasLength(1),
    );
    expect(platform.statuses.last, endsWith('runs until stopped'));
  });
}
