import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:turbomon/models/monitor.dart';
import 'package:turbomon/models/settings.dart';
import 'package:turbomon/services/access.dart';
import 'package:turbomon/services/settings_store.dart';

void main() {
  test('defaults: 2 s refresh, 4 min window, 120 points', () {
    const s = AppSettings();
    expect(s.graphCapacity, 120);
    expect(
      s.scanPlan.monitors.keys,
      containsAll([Monitor.cpu, Monitor.ram, Monitor.battery]),
    );
    expect(s.allAlerts.every((a) => !a.enabled), isTrue);
  });

  test('round-trips through JSON', () {
    final s = const AppSettings()
        .copyWith(
          refreshSeconds: 5,
          graphWindowMinutes: 15,
          accessMode: AccessMode.root,
          plan: Preset.builtIn.first.plan,
          overlayEnabled: true,
          presets: [
            Preset('Mine', ScanPlan(monitors: {Monitor.wifi: 300})),
          ],
        )
        .withAlert(
          AlertRule.defaults(
            AlertMetric.cpu,
          ).copyWith(enabled: true, threshold: 70),
        );
    final back = AppSettings.fromJson(
      (jsonDecode(jsonEncode(s.toJson())) as Map).cast<String, Object?>(),
    );
    expect(back.refreshSeconds, 5);
    expect(back.graphCapacity, 180);
    expect(back.accessMode, AccessMode.root);
    expect(back.scanPlan.monitors, Preset.builtIn.first.plan.monitors);
    expect(back.scanPlan.autoStop.durationMinutes, 480);
    expect(back.alert(AlertMetric.cpu).threshold, 70);
    expect(back.alert(AlertMetric.cpu).enabled, isTrue);
    expect(back.presets.single.plan.monitors, {Monitor.wifi: 300});
    expect(back.overlayEnabled, isTrue);
  });

  test('corrupt or missing settings give the defaults', () {
    expect(SettingsStore.decode(null).refreshSeconds, 2);
    expect(SettingsStore.decode('{not json').refreshSeconds, 2);
    expect(
      SettingsStore.decode(
        '{"plan": {"monitors": {"nope": 5}}}',
      ).scanPlan.monitors,
      isEmpty,
    );
  });

  test('store persists updates', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await SettingsStore.load();
    await store.update(store.value.copyWith(refreshSeconds: 1));
    final again = await SettingsStore.load();
    expect(again.value.refreshSeconds, 1);
  });

  group('auto-stop', () {
    final start = DateTime(2026, 10, 10, 22, 30);

    test('after a duration', () {
      expect(
        const AutoStop(durationMinutes: 480).deadline(start),
        DateTime(2026, 10, 11, 6, 30),
      );
    });

    test('at a time of day rolls over to tomorrow', () {
      const at7 = AutoStop(mode: AutoStopMode.atTime, timeOfDayMinutes: 7 * 60);
      expect(at7.deadline(start), DateTime(2026, 10, 11, 7));
      const at23 = AutoStop(
        mode: AutoStopMode.atTime,
        timeOfDayMinutes: 23 * 60,
      );
      expect(at23.deadline(start), DateTime(2026, 10, 10, 23));
      expect(at7.describe(), 'stops at 07:00');
    });

    test('battery and never have no deadline', () {
      expect(
        const AutoStop(mode: AutoStopMode.batteryBelow).deadline(start),
        isNull,
      );
      expect(const AutoStop(mode: AutoStopMode.never).deadline(start), isNull);
    });
  });

  test('background config round-trips', () {
    final c = BackgroundConfig(
      plan: Preset.builtIn[1].plan,
      alerts: [
        AlertRule.defaults(AlertMetric.temperature).copyWith(enabled: true),
      ],
      overlay: true,
      accessMode: AccessMode.shizuku,
      presetName: 'Heat check',
    );
    final back = BackgroundConfig.fromJson(
      (jsonDecode(jsonEncode(c.toJson())) as Map).cast<String, Object?>(),
    );
    expect(back.plan.monitors, c.plan.monitors);
    expect(back.alerts.single.metric, AlertMetric.temperature);
    expect(back.overlay, isTrue);
    expect(back.accessMode, AccessMode.shizuku);
    expect(back.presetName, 'Heat check');
  });
}
