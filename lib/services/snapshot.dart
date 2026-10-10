import 'dart:convert';

import '../models/bluetooth.dart';
import '../models/readings.dart';
import '../models/wifi.dart';
import 'alerts.dart';
import 'format.dart';
import 'monitor_hub.dart';
import 'time_series.dart';
import 'wifi_analysis.dart';

/// Version of the JSON block's layout; bump on any breaking change and
/// update docs/snapshot-schema.md and the golden test with it.
const snapshotSchema = 'turbomon.snapshot/1';

class SnapshotOptions {
  const SnapshotOptions({
    this.includeBssids = false,
    this.includeBluetoothAddresses = false,
  });

  /// BSSIDs and Bluetooth addresses can locate the user, so both are off
  /// unless switched on in the snapshot dialog.
  final bool includeBssids;
  final bool includeBluetoothAddresses;
}

/// Everything a snapshot reports, gathered from the live hub, the Wi-Fi and
/// Bluetooth controllers, background history and diagnostics.
class SnapshotInput {
  const SnapshotInput({
    required this.generatedAt,
    required this.device,
    required this.accessLevel,
    required this.series,
    this.coreSeries = const [],
    this.latest,
    this.cpuIsFrequencyProxy = true,
    this.processes = const [],
    this.processAverages = const {},
    this.volumes = const [],
    this.wifiLink,
    this.wifiNetworks = const [],
    this.bluetoothNearby = const [],
    this.bluetoothPaired = const [],
    this.alerts = const [],
    this.history = const [],
    this.diagnostics = const {},
  });

  final DateTime generatedAt;
  final Map<String, Object?> device;
  final String accessLevel;
  final Map<SeriesKey, TimeSeries> series;
  final List<TimeSeries> coreSeries;
  final SystemSample? latest;
  final bool cpuIsFrequencyProxy;
  final List<ProcessInfo> processes;
  final Map<String, ProcessAverage> processAverages;
  final List<StorageVolume> volumes;
  final WifiLink? wifiLink;
  final List<WifiNetwork> wifiNetworks;
  final List<BluetoothSighting> bluetoothNearby;
  final List<PairedDevice> bluetoothPaired;
  final List<FiredAlert> alerts;

  /// Background history records (one JSON object per sample).
  final List<Map<String, Object?>> history;

  /// Raw `dumpsys` output by service; only with Shizuku or root.
  final Map<String, String> diagnostics;

  /// The time span the data covers: the oldest live or history point to now.
  DateTime get windowStart {
    final starts = [
      for (final s in series.values)
        if (s.points.isNotEmpty) s.points.first.time,
      if (history.isNotEmpty)
        DateTime.fromMillisecondsSinceEpoch(
          (history.first['t'] as num).toInt(),
        ),
    ];
    if (starts.isEmpty) return generatedAt;
    return starts.reduce((a, b) => a.isBefore(b) ? a : b);
  }
}

/// Rule-based observations, phrased so a person or an LLM can act on them.
List<String> findings(SnapshotInput input) {
  final out = <String>[];
  final window = formatDuration(
    input.generatedAt.difference(input.windowStart),
  );
  final cpu = input.series[SeriesKey.cpu]!;
  if (cpu.length >= 5) {
    final avg = cpu.average!;
    if (input.cpuIsFrequencyProxy) {
      final atMax = cpu.fractionAtLeast(95);
      if (atMax >= 0.5) {
        out.add(
          'CPU clock was at or near maximum for '
          '${(atMax * 100).round()} % of the window ($window).',
        );
      }
    } else if (avg >= 50) {
      out.add(
        'CPU averaged ${avg.round()} % over $window '
        '(peak ${cpu.max!.round()} %).',
      );
    }
  }

  final heavy =
      input.processAverages.entries
          .where((e) => e.value.samples >= 3 && e.value.average >= 20)
          .toList()
        ..sort((a, b) => b.value.average.compareTo(a.value.average));
  for (final e in heavy.take(3)) {
    out.add(
      '${e.key} averaged ${e.value.average.round()} % CPU over '
      '${e.value.samples} samples (peak ${e.value.peak.round()} %).',
    );
  }

  final battery = input.latest?.battery;
  final drain = battery?.drainMa;
  if (drain != null && drain >= 500) {
    final screen = battery?.screenOn == false ? ' with screen off' : '';
    out.add('Battery draining ${drain.round()} mA$screen.');
  }
  final level = input.series[SeriesKey.batteryPercent]!;
  if (level.length >= 2 && level.span >= const Duration(minutes: 10)) {
    final drop = level.points.first.value - level.latest!.value;
    final perHour = drop / (level.span.inSeconds / 3600);
    if (perHour >= 10) {
      out.add(
        'Battery level fell ${drop.toStringAsFixed(1)} points in '
        '${formatDuration(level.span)} (${perHour.round()} %/h).',
      );
    }
  }

  final temp = input.series[SeriesKey.temperature]!;
  if (temp.max != null && temp.max! >= 42) {
    out.add('Temperature peaked at ${temp.max!.toStringAsFixed(1)} °C.');
  }
  final status = input.latest?.thermal;
  if (status?.status != null && status!.status! >= 2) {
    out.add(
      'Thermal status is ${status.statusName}: the device is throttling.',
    );
  }

  final memory = input.latest?.memory;
  if (memory != null && memory.availableBytes < memory.totalBytes * 0.1) {
    out.add(
      'Only ${formatBytes(memory.availableBytes)} RAM available '
      '(${(100 - memory.usedPercent).round()} %).',
    );
  }

  final gpu = input.series[SeriesKey.gpu]!;
  if (gpu.length >= 5 && gpu.average! >= 70) {
    out.add('GPU averaged ${gpu.average!.round()} % busy over $window.');
  }

  for (final v in input.volumes) {
    if (v.usedPercent >= 90) {
      out.add(
        '${v.label} is ${v.usedPercent.round()} % full '
        '(${formatBytes(v.freeBytes)} free).',
      );
    }
  }

  final link = input.wifiLink;
  if (link != null) {
    if (link.rssi <= -75) {
      out.add('Wi-Fi signal is weak (${link.rssi} dBm).');
    }
    final neighbours = coChannelNeighbours(link, input.wifiNetworks);
    if (neighbours >= 5) {
      out.add('$neighbours other networks share the connected Wi-Fi channel.');
    }
  }

  for (final a in input.alerts) {
    out.add(
      'Alert: ${a.title} at ${formatTime(a.time)}'
      '${a.culprit == null ? '' : ' (top process ${a.culprit})'}.',
    );
  }
  return out;
}

/// Builds the Markdown report: an instruction line for an LLM, context,
/// findings and one fenced JSON block with the raw data.
String buildSnapshot(
  SnapshotInput input, [
  SnapshotOptions options = const SnapshotOptions(),
]) {
  final found = findings(input);
  final start = input.windowStart;
  final d = input.device;
  final b = StringBuffer()
    ..writeln('# TurboMon snapshot')
    ..writeln()
    ..writeln(
      '> This is a system-monitoring report from an Android phone, '
      'made by TurboMon. Identify the likely causes of any problem it shows '
      '(battery drain, heat, slowness, network issues) and suggest fixes. '
      'The JSON block follows the schema `$snapshotSchema`.',
    )
    ..writeln()
    ..writeln('## Context')
    ..writeln()
    ..writeln('- Device: ${d['manufacturer']} ${d['model']}')
    ..writeln(
      '- Android: ${d['release']} (API ${d['sdk']}), kernel ${d['kernel']}',
    )
    ..writeln('- Access level: ${input.accessLevel}')
    ..writeln('- Snapshot taken: ${formatDateTime(input.generatedAt)}')
    ..writeln(
      '- Window: ${formatDateTime(start)} to ${formatDateTime(input.generatedAt)} '
      '(${formatDuration(input.generatedAt.difference(start))})',
    )
    ..writeln(
      input.cpuIsFrequencyProxy
          ? '- CPU figures are clock speed as a share of maximum, not utilisation '
                '(real CPU % needs Shizuku or root).'
          : '- CPU figures are utilisation from /proc/stat.',
    )
    ..writeln()
    ..writeln('## Findings')
    ..writeln();
  if (found.isEmpty) {
    b.writeln('- Nothing stood out.');
  } else {
    for (final f in found) {
      b.writeln('- $f');
    }
  }
  b
    ..writeln()
    ..writeln('## Data')
    ..writeln()
    ..writeln('```json')
    ..writeln(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(snapshotJson(input, found, options)),
    )
    ..writeln('```');
  return b.toString();
}

Map<String, Object?> snapshotJson(
  SnapshotInput input,
  List<String> found,
  SnapshotOptions options,
) {
  final latest = input.latest;
  return {
    'schema': snapshotSchema,
    'generatedAt': input.generatedAt.toIso8601String(),
    'window': {
      'start': input.windowStart.toIso8601String(),
      'end': input.generatedAt.toIso8601String(),
    },
    'device': input.device,
    'access': input.accessLevel,
    'cpuIsFrequencyProxy': input.cpuIsFrequencyProxy,
    'current': {
      'cpu': latest?.cpu?.toJson(),
      'memory': latest?.memory?.toJson(),
      'gpu': latest?.gpu?.toJson(),
      'battery': latest?.battery?.toJson(),
      'network': latest?.network?.toJson(),
      'thermal': latest?.thermal?.toJson(),
      'diskIo': latest?.diskIo?.toJson(),
    },
    'series': {
      for (final e in input.series.entries)
        if (!e.value.isEmpty)
          e.key.name: {'unit': e.key.unit, 'points': e.value.toJson()},
    },
    'cores': [for (final s in input.coreSeries) s.toJson(decimals: 1)],
    'processes': {
      'top': [for (final p in input.processes.take(20)) p.toJson()],
      'averages': [
        for (final e
            in (input.processAverages.entries.toList()
                  ..sort((a, b) => b.value.average.compareTo(a.value.average)))
                .take(20))
          {
            'name': e.key,
            'avgCpu': double.parse(e.value.average.toStringAsFixed(1)),
            'peakCpu': e.value.peak,
            'samples': e.value.samples,
          },
      ],
    },
    'storage': [for (final v in input.volumes) v.toJson()],
    'wifi': {
      'link': input.wifiLink?.toJson(),
      'networks': [
        for (final n in input.wifiNetworks)
          n.toJson(includeBssid: options.includeBssids),
      ],
    },
    'bluetooth': {
      'nearby': [
        for (final d in input.bluetoothNearby)
          d.toJson(includeAddress: options.includeBluetoothAddresses),
      ],
      'paired': [
        for (final p in input.bluetoothPaired)
          p.toJson(includeAddress: options.includeBluetoothAddresses),
      ],
    },
    'alerts': [for (final a in input.alerts) a.toJson()],
    'history': input.history,
    'findings': found,
    'diagnostics': input.diagnostics,
  };
}

/// File name for a snapshot taken at [time]: `turbomon-20261010-142233.md`.
String snapshotFileName(DateTime time) {
  String two(int v) => v.toString().padLeft(2, '0');
  return 'turbomon-${time.year}${two(time.month)}${two(time.day)}-'
      '${two(time.hour)}${two(time.minute)}${two(time.second)}.md';
}
