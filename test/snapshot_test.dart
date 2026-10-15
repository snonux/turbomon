import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turbomon/models/bluetooth.dart';
import 'package:turbomon/models/readings.dart';
import 'package:turbomon/models/settings.dart';
import 'package:turbomon/models/wifi.dart';
import 'package:turbomon/services/alerts.dart';
import 'package:turbomon/services/monitor_hub.dart';
import 'package:turbomon/services/snapshot.dart';
import 'package:turbomon/services/time_series.dart';

/// A fixed input so the report is byte-for-byte stable.
SnapshotInput fixedInput() {
  final t0 = DateTime.utc(2026, 10, 10, 12);
  final series = {for (final k in SeriesKey.values) k: TimeSeries(10)};
  for (var i = 0; i < 6; i++) {
    final t = t0.add(Duration(seconds: 2 * i));
    series[SeriesKey.cpu]!.add(t, 60.0 + i);
    series[SeriesKey.ram]!.add(t, 70);
    series[SeriesKey.temperature]!.add(t, 40.0 + i);
  }
  final averages = {
    'com.example.hog': ProcessAverage()
      ..add(40)
      ..add(38)
      ..add(36),
    'system_server': ProcessAverage()
      ..add(5)
      ..add(4)
      ..add(6),
  };
  return SnapshotInput(
    generatedAt: t0.add(const Duration(seconds: 10)),
    device: const {
      'manufacturer': 'Google',
      'model': 'Pixel Test',
      'release': '14',
      'sdk': 34,
      'kernel': '6.1.0',
    },
    accessLevel: 'Shizuku (ADB shell)',
    series: series,
    latest: SystemSample(
      time: t0.add(const Duration(seconds: 10)),
      cpu: const CpuReading(
        totalPercent: 65,
        corePercents: [60, 70],
        coreCount: 2,
      ),
      memory: const MemoryReading(
        totalBytes: 8 << 30,
        availableBytes: 512 << 20,
      ),
      battery: const BatteryReading(
        percent: 55,
        currentMa: -650,
        voltageMv: 3800,
        screenOn: false,
      ),
      thermal: const ThermalReading(status: 2, zones: [ThermalZone('cpu', 45)]),
    ),
    cpuIsFrequencyProxy: false,
    processes: const [
      ProcessInfo(
        pid: 4242,
        user: 'u0_a99',
        name: 'com.example.hog',
        cpuPercent: 36,
        rssBytes: 200 << 20,
        state: 'R',
        batteryMah: 12.5,
      ),
    ],
    processAverages: averages,
    volumes: const [
      StorageVolume(
        label: 'Internal',
        path: '/s',
        totalBytes: 100 << 30,
        freeBytes: 5 << 30,
      ),
    ],
    wifiLink: const WifiLink(
      ssid: 'Home',
      bssid: '11:22',
      rssi: -78,
      linkMbps: 72,
      frequency: 2412,
    ),
    wifiNetworks: const [
      WifiNetwork(
        ssid: 'Home',
        bssid: '11:22',
        rssi: -78,
        frequency: 2412,
        capabilities: '[RSN]',
      ),
    ],
    bluetoothNearby: [
      BluetoothSighting(
        address: 'AA:BB',
        name: 'Buds',
        rssi: -60,
        companyId: 0x0075,
        lastSeen: t0,
      ),
    ],
    bluetoothPaired: const [
      PairedDevice(
        address: 'CC:DD',
        name: 'Car',
        connected: true,
        profiles: ['audio'],
      ),
    ],
    alerts: [
      FiredAlert(
        rule: AlertRule.defaults(
          AlertMetric.cpu,
        ).copyWith(enabled: true, threshold: 60),
        value: 64,
        time: t0.add(const Duration(seconds: 8)),
        culprit: 'com.example.hog',
      ),
    ],
    diagnostics: const {'cpuinfo': 'Load: 4.2 / 3.9 / 3.1\n'},
  );
}

void main() {
  test('report matches the golden file', () {
    final report = buildSnapshot(fixedInput());
    final golden = File('test/fixtures/snapshot_golden.md');
    if (Platform.environment['UPDATE_GOLDEN'] == '1') {
      golden.writeAsStringSync(report);
    }
    expect(report, golden.readAsStringSync());
  });

  test('the JSON block parses and carries the schema', () {
    final report = buildSnapshot(fixedInput());
    final json = RegExp(
      r'```json\n([\s\S]*?)\n```',
    ).firstMatch(report)!.group(1)!;
    final data = jsonDecode(json) as Map<String, Object?>;
    expect(data['schema'], snapshotSchema);
    expect(
      (data['series'] as Map).keys,
      containsAll(['cpu', 'ram', 'temperature']),
    );
    expect((data['processes'] as Map)['top'], hasLength(1));
    expect(data['findings'], isNotEmpty);
  });

  test('BSSIDs and Bluetooth addresses only on request', () {
    final plain = buildSnapshot(fixedInput());
    expect(plain, isNot(contains('11:22')));
    expect(plain, isNot(contains('AA:BB')));
    final full = buildSnapshot(
      fixedInput(),
      const SnapshotOptions(
        includeBssids: true,
        includeBluetoothAddresses: true,
      ),
    );
    expect(full, contains('11:22'));
    expect(full, contains('AA:BB'));
  });

  test('findings name the culprits', () {
    final f = findings(fixedInput());
    expect(f, contains(startsWith('CPU averaged 63 %')));
    expect(f, contains(startsWith('com.example.hog averaged 38 % CPU')));
    expect(f, contains('Battery draining 650 mA with screen off.'));
    expect(f, contains(startsWith('Thermal status is moderate')));
    expect(f, contains(startsWith('Only 512.0 MiB RAM available')));
    expect(f, contains(startsWith('Internal is 95 % full')));
    expect(f, contains('Wi-Fi signal is weak (-78 dBm).'));
    expect(f, contains(startsWith('Alert: CPU load above 60 %')));
  });

  test('an empty snapshot still reports', () {
    final report = buildSnapshot(
      SnapshotInput(
        generatedAt: DateTime(2026),
        device: const {},
        accessLevel: 'Normal app',
        series: {for (final k in SeriesKey.values) k: TimeSeries(2)},
      ),
    );
    expect(report, contains('Nothing stood out.'));
    expect(report, contains('clock speed'));
  });

  test('file names', () {
    expect(
      snapshotFileName(DateTime(2026, 10, 10, 9, 5, 7)),
      'turbomon-20261010-090507.md',
    );
  });
}
