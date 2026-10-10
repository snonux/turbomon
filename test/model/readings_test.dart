import 'package:flutter_test/flutter_test.dart';
import 'package:turbomon/model/readings.dart';

void main() {
  group('normalizeCurrentMa', () {
    test('microamperes are converted to milliamperes', () {
      expect(normalizeCurrentMa(-412000, charging: false), -412);
      expect(normalizeCurrentMa(1500000, charging: true), 1500);
    });

    test('vendors reporting milliamperes are kept as is', () {
      expect(normalizeCurrentMa(-412, charging: false), -412);
      expect(normalizeCurrentMa(1500, charging: true), 1500);
    });

    test('sign follows the charging state, not the vendor', () {
      expect(normalizeCurrentMa(412000, charging: false), -412);
      expect(normalizeCurrentMa(-1500000, charging: true), 1500);
      expect(normalizeCurrentMa(300, charging: false), -300);
      expect(normalizeCurrentMa(-300, charging: true), 300);
    });

    test('unknown or sentinel values are null', () {
      expect(normalizeCurrentMa(null, charging: false), isNull);
      expect(normalizeCurrentMa(0, charging: false), isNull);
      expect(normalizeCurrentMa(-2147483648, charging: false), isNull);
      expect(normalizeCurrentMa(2147483647, charging: true), isNull);
    });
  });

  group('BatteryReading.fromMap', () {
    test('discharging phone', () {
      final b = BatteryReading.fromMap({
        'level': 76,
        'status': 'discharging',
        'plugged': 'none',
        'health': 'good',
        'tempC': 31.5,
        'voltageMv': 3900,
        'currentNowUa': -400000,
        'chargeCounterUah': 3400000,
      });
      expect(b.levelPercent, 76);
      expect(b.charging, isFalse);
      expect(b.currentMa, -400);
      expect(b.drainMa, 400);
      expect(b.powerW, closeTo(1.56, 1e-9));
      expect(b.chargeCounterMah, 3400);
      expect(b.tempC, 31.5);
      expect(b.health, 'good');
    });

    test('charging phone with a vendor that flips the sign and reports mA', () {
      final b = BatteryReading.fromMap({
        'level': 40,
        'status': 'charging',
        'plugged': 'usb',
        'voltageMv': 4200,
        'currentNowUa': -2000,
      });
      expect(b.charging, isTrue);
      expect(b.currentMa, 2000);
      expect(b.drainMa, 0);
      expect(b.powerW, closeTo(8.4, 1e-9));
      expect(b.plugged, 'usb');
    });

    test('a full battery counts as charging', () {
      final b = BatteryReading.fromMap({'level': 100, 'status': 'full', 'plugged': 'ac'});
      expect(b.charging, isTrue);
      expect(b.currentMa, isNull);
      expect(b.drainMa, isNull);
      expect(b.powerW, isNull);
    });

    test('defaults for an empty map; non-positive charge counter is null', () {
      final b = BatteryReading.fromMap({'chargeCounterUah': -1});
      expect(b.levelPercent, 0);
      expect(b.status, 'unknown');
      expect(b.plugged, 'none');
      expect(b.health, 'unknown');
      expect(b.chargeCounterMah, isNull);
      expect(b.voltageMv, isNull);
    });
  });

  group('ProcessRow', () {
    test('batteryUid strips the underscore of ps user names', () {
      const p = ProcessRow(pid: 1, user: 'u0_a174', name: 'x', cpuPercent: 0, rssKb: 0, state: 'S');
      expect(p.batteryUid, 'u0a174');
    });

    test('toJson rounds and omits unknown fields', () {
      const p = ProcessRow(pid: 5, user: 'root', name: 'init', cpuPercent: 12.345, rssKb: 100, state: 'S');
      expect(p.toJson(), {'pid': 5, 'user': 'root', 'name': 'init', 'cpu': 12.3, 'rssKb': 100, 'state': 'S'});
      const q = ProcessRow(
          pid: 5, user: 'root', name: 'init', cpuPercent: 1, rssKb: 1, state: 'S',
          batteryMah: 12.34, ioReadBps: 10.6, ioWriteBps: 0.4);
      expect(q.toJson()['batteryMah'], 12.3);
      expect(q.toJson()['ioReadBps'], 11);
      expect(q.toJson()['ioWriteBps'], 0);
    });
  });

  group('StorageVolume and AppSize', () {
    test('StorageVolume.fromMap and percentages', () {
      final v = StorageVolume.fromMap({'label': 'SD card', 'totalBytes': 1000, 'freeBytes': 250, 'removable': true});
      expect(v.usedBytes, 750);
      expect(v.usedPercent, 75);
      expect(v.removable, isTrue);
      expect(v.toJson(), {'label': 'SD card', 'totalBytes': 1000, 'freeBytes': 250, 'removable': true});
      expect(StorageVolume.fromMap({}).usedPercent, 0);
      expect(StorageVolume.fromMap({}).label, 'Storage');
    });

    test('AppSize total', () {
      final a = AppSize.fromMap({'package': 'p', 'label': 'P', 'appBytes': 1, 'dataBytes': 2, 'cacheBytes': 3});
      expect(a.total, 6);
    });
  });

  group('formatBytes and formatRate', () {
    test('picks the right unit', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(1023), '1023 B');
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
      expect(formatBytes(3.5 * 1024 * 1024 * 1024), '3.5 GB');
      expect(formatBytes(2 * 1024 * 1024 * 1024 * 1024), '2.0 TB');
      expect(formatBytes(5000 * 1024 * 1024 * 1024 * 1024), '5000.0 TB');
    });

    test('digits and negatives', () {
      expect(formatBytes(1536, digits: 0), '2 KB');
      expect(formatBytes(1536, digits: 2), '1.50 KB');
      expect(formatBytes(-2048), '-2.0 KB');
    });

    test('formatRate', () {
      expect(formatRate(0), '0 B/s');
      expect(formatRate(1024 * 1024), '1.0 MB/s');
    });
  });

  test('thermal status names match PowerManager.THERMAL_STATUS_*', () {
    expect(thermalStatusNames, hasLength(7));
    expect(thermalStatusNames[0], 'none');
    expect(thermalStatusNames[3], 'severe');
    expect(thermalStatusNames[6], 'shutdown');
  });
}
