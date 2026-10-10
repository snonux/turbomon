import '../models/readings.dart';
import '../services/monitor_hub.dart';
import '../services/time_series.dart';

/// Compact history line for one background sample. Keys are short because a
/// week of samples every 30 s is ~20k lines; see docs/background.md.
Map<String, Object?> historyRecord(
  SystemSample s, {
  List<ProcessInfo> processes = const [],
  int? wifiRssi,
  int? wifiNetworks,
  int? bluetoothDevices,
  double? storageUsedPercent,
}) {
  double? r(double? v, [int d = 1]) =>
      v == null ? null : double.parse(v.toStringAsFixed(d));
  final temps = [s.thermal?.hottest, s.battery?.temperatureC].nonNulls;
  final record = <String, Object?>{
    't': s.time.millisecondsSinceEpoch,
    'cpu': r(s.cpu?.load),
    if (s.cpu != null) 'cpuProxy': s.cpu!.isFrequencyProxy,
    'ram': r(s.memory?.usedPercent),
    'gpu': r(s.gpu?.busyPercent),
    'bat': r(s.battery?.percent),
    'batMa': r(s.battery?.currentMa, 0),
    'batW': r(s.battery?.powerW, 2),
    'screen': s.battery?.screenOn,
    'temp': temps.isEmpty ? null : r(temps.reduce((a, b) => a > b ? a : b)),
    'thermal': s.thermal?.status,
    'rx': r(s.network?.rxBps, 0),
    'tx': r(s.network?.txBps, 0),
    'dr': r(s.diskIo?.readBps, 0),
    'dw': r(s.diskIo?.writeBps, 0),
    'wifiRssi': wifiRssi,
    'wifiNets': wifiNetworks,
    'bt': bluetoothDevices,
    'disk': r(storageUsedPercent),
    if (processes.isNotEmpty)
      'top': [
        for (final p in processes.take(5))
          {
            'name': p.name,
            'cpu': p.cpuPercent,
            if (p.batteryMah != null) 'mah': p.batteryMah,
          },
      ],
  };
  record.removeWhere((_, v) => v == null);
  return record;
}

/// Rebuilds graph series from history records, for snapshots of a past run.
Map<SeriesKey, TimeSeries> seriesFromHistory(
  List<Map<String, Object?>> records,
) {
  const keys = {
    SeriesKey.cpu: 'cpu',
    SeriesKey.ram: 'ram',
    SeriesKey.gpu: 'gpu',
    SeriesKey.batteryPower: 'batW',
    SeriesKey.batteryPercent: 'bat',
    SeriesKey.temperature: 'temp',
    SeriesKey.netRx: 'rx',
    SeriesKey.netTx: 'tx',
    SeriesKey.diskRead: 'dr',
    SeriesKey.diskWrite: 'dw',
  };
  final capacity = records.isEmpty ? 1 : records.length;
  final series = {for (final k in SeriesKey.values) k: TimeSeries(capacity)};
  for (final record in records) {
    final t = DateTime.fromMillisecondsSinceEpoch((record['t'] as num).toInt());
    for (final e in keys.entries) {
      final v = record[e.value];
      if (v is num) series[e.key]!.add(t, v.toDouble());
    }
  }
  return series;
}

/// Per-process CPU averages across the `top` lists of [records].
Map<String, ProcessAverage> processAveragesFromHistory(
  List<Map<String, Object?>> records,
) {
  final averages = <String, ProcessAverage>{};
  for (final record in records) {
    for (final p in record['top'] as List? ?? const []) {
      final m = p as Map;
      averages
          .putIfAbsent(m['name'] as String, ProcessAverage.new)
          .add((m['cpu'] as num).toDouble());
    }
  }
  return averages;
}

/// Whether the CPU figures in [records] were the frequency proxy.
bool historyCpuIsProxy(List<Map<String, Object?>> records) =>
    records.every((r) => r['cpuProxy'] != false);
