import 'dart:convert';

import '../model/bluetooth.dart';
import '../model/readings.dart';
import '../model/ring_buffer.dart';
import '../parsers/proc_parsers.dart';
import '../parsers/wifi_channels.dart';
import 'alerts.dart';
import 'history.dart';

/// Version of the JSON block's layout. Bump it on any breaking change and
/// describe the change in docs/snapshot-schema.md.
const snapshotSchema = 'turbomon.snapshot/1';

/// Everything a snapshot report is built from. Plain data, so the report
/// can be produced from live controllers or from background history alike.
class SnapshotInput {
  SnapshotInput({
    required this.takenAt,
    required this.reason,
    required this.appVersion,
    required this.device,
    required this.access,
    required this.windowStart,
    required this.windowEnd,
    this.series = const {},
    this.cpuIsProxy = true,
    this.mem,
    this.battery,
    this.thermalStatus,
    this.thermalHeadroom,
    this.zones = const [],
    this.volumes = const [],
    this.diskRates = const [],
    this.processes = const [],
    this.wifi = const [],
    this.wifiConnection,
    this.bluetooth = const [],
    this.bluetoothConnected = const [],
    this.alerts = const [],
    this.history = const [],
    this.includeAddresses = false,
    this.rawShellOutput = const {},
    this.screenOff,
  });

  final DateTime takenAt;
  final String reason;
  final String appVersion;
  final Map<String, Object?> device;
  final String access;
  final DateTime windowStart;
  final DateTime windowEnd;
  final Map<String, RingBuffer> series;
  final bool cpuIsProxy;
  final MemInfo? mem;
  final BatteryReading? battery;
  final int? thermalStatus;
  final double? thermalHeadroom;
  final List<ThermalZone> zones;
  final List<StorageVolume> volumes;
  final List<DiskRate> diskRates;
  final List<ProcessRow> processes;
  final List<WifiNetwork> wifi;
  final Map<String, Object?>? wifiConnection;
  final List<BtDevice> bluetooth;
  final List<BtDevice> bluetoothConnected;
  final List<FiredAlert> alerts;
  final List<HistorySample> history;
  final bool includeAddresses;

  /// Verbatim output of `dumpsys` commands, when elevated.
  final Map<String, String> rawShellOutput;

  /// Whether the screen was off for most of the window, when known.
  final bool? screenOff;
}

/// A problem TurboMon flags with a simple rule, ranked by severity.
class Finding {
  const Finding(this.severity, this.text);
  final int severity; // 3 high, 2 medium, 1 low
  final String text;
}

String _pct(num v) => '${v.toStringAsFixed(0)} %';

String _dur(Duration d) {
  if (d.inMinutes >= 120) return '${(d.inMinutes / 60).toStringAsFixed(1)} h';
  if (d.inSeconds >= 120) return '${d.inMinutes} min';
  return '${d.inSeconds} s';
}

List<Finding> findingsFor(SnapshotInput i) {
  final out = <Finding>[];
  final window = _dur(i.windowEnd.difference(i.windowStart));

  final cpu = i.series['cpu'];
  if (cpu != null && cpu.known.isNotEmpty) {
    final avg = cpu.average!;
    if (i.cpuIsProxy) {
      final atMax = cpu.shareAtOrAbove(90);
      if (atMax >= 0.5) {
        out.add(Finding(2,
            'CPU cores ran at 90 % or more of their maximum frequency for ${_pct(atMax * 100)} of the $window window (frequency only; real CPU % needs Shizuku or root).'));
      }
    } else if (avg >= 50) {
      out.add(Finding(avg >= 80 ? 3 : 2, 'Total CPU averaged ${_pct(avg)} over $window.'));
    }
  }

  for (final p in i.processes.take(5)) {
    if (p.cpuPercent >= 10) {
      out.add(Finding(p.cpuPercent >= 25 ? 3 : 2,
          '`${p.name}` (pid ${p.pid}) used ${_pct(p.cpuPercent)} of total CPU in the last sample.'));
    }
  }
  final heavyBattery = [...i.processes.where((p) => (p.batteryMah ?? 0) >= 50)]
    ..sort((a, b) => b.batteryMah!.compareTo(a.batteryMah!));
  for (final p in heavyBattery.take(3)) {
    out.add(Finding(2,
        '`${p.name}` is estimated at ${p.batteryMah!.toStringAsFixed(0)} mAh since the last full charge (batterystats).'));
  }

  final drain = i.series['batteryDrainMa'];
  if (drain != null && drain.known.isNotEmpty) {
    final avg = drain.average!;
    if (avg >= 400) {
      final screen = i.screenOff == true ? ' with the screen off' : '';
      out.add(Finding(avg >= 800 ? 3 : 2, 'Battery drained ${avg.toStringAsFixed(0)} mA on average$screen over $window.'));
    }
  }

  final temps = [i.series['hottestC']?.max, i.series['batteryTempC']?.max].whereType<double>();
  if (temps.isNotEmpty) {
    final hot = temps.reduce((a, b) => a > b ? a : b);
    if (hot >= 45) out.add(Finding(hot >= 55 ? 3 : 2, 'Peak temperature was ${hot.toStringAsFixed(1)} °C.'));
  }
  if ((i.thermalStatus ?? 0) >= 2) {
    out.add(Finding(3,
        'Android reports thermal status "${thermalStatusNames[i.thermalStatus!.clamp(0, 6)]}": the CPU is being throttled.'));
  }

  final m = i.mem;
  if (m != null && m.usedPercent >= 90) {
    out.add(Finding(2, 'RAM is ${_pct(m.usedPercent)} used (${formatBytes(m.availableKb * 1024)} available).'));
  }
  if (m != null && m.swapTotalKb > 0 && (m.swapTotalKb - m.swapFreeKb) > m.swapTotalKb * 0.8) {
    out.add(const Finding(1, 'Swap (zram) is over 80 % full, so the system is under memory pressure.'));
  }

  for (final v in i.volumes) {
    if (v.usedPercent >= 90) {
      out.add(Finding(2, '${v.label} is ${_pct(v.usedPercent)} full (${formatBytes(v.freeBytes)} free).'));
    }
  }

  final net = i.series['netRxBps'];
  if (net != null && net.known.isNotEmpty && net.average! > 1024 * 1024) {
    out.add(Finding(1, 'Network download averaged ${formatRate(net.average!)} over $window.'));
  }

  for (final a in i.alerts) {
    out.add(Finding(3, 'Alert fired: ${a.message}.'));
  }

  // Background history: the busiest process across all samples.
  final procCpu = <String, List<double>>{};
  for (final s in i.history) {
    for (final p in (s.raw['procs'] as List?) ?? const []) {
      if (p is Map && p['name'] is String && p['cpu'] is num) {
        procCpu.putIfAbsent(p['name'] as String, () => []).add((p['cpu'] as num).toDouble());
      }
    }
  }
  if (procCpu.isNotEmpty && i.history.isNotEmpty) {
    final ranked = procCpu.entries
        .map((e) => (e.key, e.value.reduce((a, b) => a + b) / i.history.length))
        .toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    for (final (name, avg) in ranked.take(3)) {
      if (avg >= 5) {
        out.add(Finding(avg >= 20 ? 3 : 2, '`$name` averaged ${_pct(avg)} CPU across the background history.'));
      }
    }
  }

  out.sort((a, b) => b.severity.compareTo(a.severity));
  return out;
}

String _redact(String address, bool include) {
  if (include || address.isEmpty) return address;
  return 'redacted';
}

Map<String, Object?> snapshotJson(SnapshotInput i) => {
      'schema': snapshotSchema,
      'takenAt': i.takenAt.toUtc().toIso8601String(),
      'reason': i.reason,
      'app': {'name': 'TurboMon', 'version': i.appVersion},
      'device': i.device,
      'access': i.access,
      'window': {
        'start': i.windowStart.toUtc().toIso8601String(),
        'end': i.windowEnd.toUtc().toIso8601String(),
      },
      'cpuIsFrequencyProxy': i.cpuIsProxy,
      'series': {for (final e in i.series.entries) e.key: e.value.toJson()},
      if (i.mem != null)
        'memory': {
          'totalKb': i.mem!.totalKb,
          'availableKb': i.mem!.availableKb,
          'cachedKb': i.mem!.cachedKb,
          'swapTotalKb': i.mem!.swapTotalKb,
          'swapFreeKb': i.mem!.swapFreeKb,
        },
      if (i.battery != null)
        'battery': {
          'levelPercent': i.battery!.levelPercent,
          'status': i.battery!.status,
          'plugged': i.battery!.plugged,
          'health': i.battery!.health,
          'tempC': i.battery!.tempC,
          'voltageMv': i.battery!.voltageMv,
          'currentMa': i.battery!.currentMa,
          'powerW': i.battery!.powerW,
        },
      'thermal': {
        'status': i.thermalStatus,
        'statusName': i.thermalStatus == null ? null : thermalStatusNames[i.thermalStatus!.clamp(0, 6)],
        'headroom': i.thermalHeadroom,
        'zones': [for (final z in i.zones) {'type': z.type, 'celsius': z.celsius}],
      },
      'storage': [for (final v in i.volumes) v.toJson()],
      'diskIo': [
        for (final d in i.diskRates)
          {
            'device': d.device,
            'readBps': d.readBytesPerSec.round(),
            'writeBps': d.writeBytesPerSec.round(),
            'readOps': double.parse(d.readOpsPerSec.toStringAsFixed(1)),
            'writeOps': double.parse(d.writeOpsPerSec.toStringAsFixed(1)),
          },
      ],
      'processes': [for (final p in i.processes.take(20)) p.toJson()],
      'wifi': {
        'connected': i.wifiConnection == null
            ? null
            : {
                ...i.wifiConnection!,
                'bssid': _redact('${i.wifiConnection!['bssid'] ?? ''}', i.includeAddresses),
              },
        'networks': [
          for (final n in i.wifi)
            {
              'ssid': n.ssid,
              'bssid': _redact(n.bssid, i.includeAddresses),
              'rssi': n.rssi,
              'frequency': n.frequency,
              'channel': n.channel,
              'widthMhz': n.channelWidthMhz,
              'security': n.security,
              'standard': n.standard,
            },
        ],
      },
      'bluetooth': {
        'connected': [
          for (final d in i.bluetoothConnected)
            {'name': d.name, 'address': _redact(d.address, i.includeAddresses), 'type': d.type},
        ],
        'nearby': [
          for (final d in i.bluetooth)
            {
              'name': d.name,
              'address': _redact(d.address, i.includeAddresses),
              'rssi': d.rssi,
              'type': d.type,
              'maker': d.maker,
            },
        ],
      },
      'alerts': [for (final a in i.alerts) a.toJson()],
      'history': [for (final s in i.history) s.raw],
      'raw': i.rawShellOutput,
    };

/// The full Markdown report: an instruction for an LLM, context, findings,
/// then the data as one fenced JSON block.
String buildSnapshot(SnapshotInput i) {
  final b = StringBuffer();
  final findings = findingsFor(i);
  final d = i.device;
  b.writeln('# TurboMon snapshot ${_stamp(i.takenAt)}');
  b.writeln();
  b.writeln('> For an LLM: this is a performance snapshot of an Android phone taken by TurboMon. '
      'Identify the most likely causes of any CPU, battery, thermal, memory, storage or radio problem '
      'in it, and suggest concrete fixes (settings to change, apps to restrict or remove, '
      'or code changes if an app named here is the reader\'s own). The JSON block below follows '
      'schema `$snapshotSchema`; `series` values are oldest first and `null` means not measured.');
  b.writeln();
  b.writeln('## Context');
  b.writeln();
  b.writeln('- Reason: ${i.reason}');
  b.writeln('- Device: ${d['manufacturer'] ?? '?'} ${d['model'] ?? '?'}, Android ${d['release'] ?? '?'} (API ${d['sdk'] ?? '?'}), kernel ${d['kernel'] ?? '?'}');
  b.writeln('- Access level: ${i.access}');
  b.writeln('- Window: ${_stamp(i.windowStart)} to ${_stamp(i.windowEnd)} (${_dur(i.windowEnd.difference(i.windowStart))})');
  b.writeln('- TurboMon ${i.appVersion}');
  if (i.cpuIsProxy) {
    b.writeln('- CPU values are core frequency as a share of maximum, not utilisation (no Shizuku or root).');
  }
  b.writeln();
  b.writeln('## Findings');
  b.writeln();
  if (findings.isEmpty) {
    b.writeln('No rule flagged anything. The data below is still worth a look.');
  } else {
    for (final f in findings) {
      b.writeln('- ${['', 'Low', 'Medium', 'High'][f.severity]}: ${f.text}');
    }
  }
  b.writeln();
  if (i.processes.isNotEmpty) {
    b.writeln('## Top processes');
    b.writeln();
    b.writeln('| PID | Name | CPU % | RSS | Battery mAh |');
    b.writeln('| --- | --- | --- | --- | --- |');
    for (final p in i.processes.take(10)) {
      b.writeln('| ${p.pid} | ${p.name} | ${p.cpuPercent.toStringAsFixed(1)} | '
          '${formatBytes(p.rssKb * 1024)} | ${p.batteryMah?.toStringAsFixed(0) ?? ''} |');
    }
    b.writeln();
  }
  b.writeln('## Data');
  b.writeln();
  b.writeln('```json');
  b.writeln(const JsonEncoder.withIndent('  ').convert(snapshotJson(i)));
  b.writeln('```');
  return b.toString();
}

String _stamp(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

String snapshotFileName(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return 'turbomon-${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}.md';
}
