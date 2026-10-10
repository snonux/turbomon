import 'package:flutter_test/flutter_test.dart';
import 'package:turbomon/models/bluetooth.dart';
import 'package:turbomon/models/readings.dart';
import 'package:turbomon/services/battery_math.dart';
import 'package:turbomon/services/format.dart';
import 'package:turbomon/services/time_series.dart';

void main() {
  group('battery current', () {
    test('µA and mA, sign from the charging state', () {
      expect(normaliseCurrentMa(-450000, charging: false), -450);
      expect(normaliseCurrentMa(450000, charging: false), -450);
      expect(normaliseCurrentMa(-1200, charging: true), 1200);
      expect(normaliseCurrentMa(300, charging: false), -300);
      expect(normaliseCurrentMa(0, charging: false), isNull);
      expect(normaliseCurrentMa(null, charging: true), isNull);
    });

    test('power and drain', () {
      const b = BatteryReading(currentMa: -500, voltageMv: 4000);
      expect(b.powerW, -2);
      expect(b.drainMa, 500);
      expect(const BatteryReading(currentMa: 500).drainMa, isNull);
    });
  });

  test('CPU load falls back to the mean clock share', () {
    const cpu = CpuReading(
      frequencies: [
        CoreFrequency(index: 0, currentKHz: 1000000, maxKHz: 2000000),
        CoreFrequency(index: 1, currentKHz: 2000000, maxKHz: 2000000),
        CoreFrequency(index: 2),
      ],
    );
    expect(cpu.isFrequencyProxy, isTrue);
    expect(cpu.load, 75);
    expect(cpu.coreLoads, [50, 100, null]);
    expect(
      const CpuReading(totalPercent: 12, corePercents: [10, 14]).coreLoads,
      [10, 14],
    );
    expect(const CpuReading().load, isNull);
  });

  test('process uid from the Android user name', () {
    ProcessInfo p(String user) => ProcessInfo(
      pid: 1,
      user: user,
      name: 'x',
      cpuPercent: 0,
      rssBytes: 0,
      state: 'S',
    );
    expect(p('u0_a167').uid, 10167);
    expect(p('u10_a12').uid, 1010012);
    expect(p('system').uid, 1000);
    expect(p('nobody').uid, isNull);
  });

  test('thermal status names', () {
    expect(const ThermalReading(status: 3).statusName, 'severe');
    expect(const ThermalReading(status: 9).statusName, isNull);
    expect(
      const ThermalReading(
        zones: [ThermalZone('a', 30), ThermalZone('b', 45)],
      ).hottest,
      45,
    );
  });

  group('TimeSeries', () {
    test('drops the oldest point at capacity', () {
      final s = TimeSeries(3);
      for (var i = 0; i < 5; i++) {
        s.add(DateTime(2026, 1, 1, 0, 0, i), i.toDouble());
      }
      expect(s.values, [2, 3, 4]);
      expect(s.average, 3);
      expect(s.max, 4);
      expect(s.span, const Duration(seconds: 2));
      expect(s.fractionAtLeast(3), closeTo(2 / 3, 1e-9));
    });

    test('ignores NaN and keeps the newest points when resized', () {
      final s = TimeSeries(4)..add(DateTime(2026), double.nan);
      expect(s.isEmpty, isTrue);
      for (var i = 0; i < 4; i++) {
        s.add(DateTime(2026, 1, 1, 0, 0, i), i.toDouble());
      }
      expect(s.resized(2).values, [2, 3]);
      expect(s.toJson().first, [
        DateTime(2026, 1, 1).millisecondsSinceEpoch,
        0,
      ]);
    });
  });

  test('Bluetooth grouping by name and maker', () {
    final now = DateTime(2026);
    final a = BluetoothSighting.fromJson({
      'address': 'A',
      'name': 'Buds',
      'companyId': 0x0075,
    }, now);
    final b = BluetoothSighting.fromJson({
      'address': 'B',
      'name': 'Buds',
      'companyId': 0x0075,
    }, now);
    final c = BluetoothSighting.fromJson({'address': 'C', 'name': '  '}, now);
    expect(a.groupKey, b.groupKey);
    expect(a.maker, 'Samsung');
    expect(c.name, isNull);
    expect(c.groupKey, 'a:C');
    expect(c.toJson().containsKey('address'), isFalse);
    expect(c.toJson(includeAddress: true)['address'], 'C');
  });

  test('formatting', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1536), '1.5 KiB');
    expect(formatRate(1 << 20), '1.0 MiB/s');
    expect(formatDuration(const Duration(seconds: 42)), '42 s');
    expect(formatDuration(const Duration(minutes: 125)), '2 h 05 min');
    expect(formatMhz(1804800), '1805 MHz');
    expect(formatPercent(null), '–');
  });
}
