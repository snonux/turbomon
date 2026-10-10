import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:turbomon_platform/turbomon_platform.dart';

import '../models/monitor.dart';
import '../models/readings.dart';
import '../models/settings.dart';
import '../models/wifi.dart';
import '../services/access.dart';
import '../services/alerts.dart';
import '../services/format.dart';
import '../services/history_store.dart';
import '../services/snapshot.dart';
import '../services/storage_paths.dart';
import '../services/system_reader.dart';
import 'history_record.dart';

/// The loop inside the background service: samples each checked monitor at
/// its own interval, appends history, raises alerts, feeds the widget and
/// overlay, and stops itself when the configured auto-stop is reached.
class BackgroundRunner {
  BackgroundRunner({
    required this.config,
    required this.reader,
    required this.platform,
    required this.history,
    required this.paths,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       _alerts = AlertEvaluator(config.alerts);

  final BackgroundConfig config;
  final SystemReader reader;
  final TurboMonPlatform platform;
  final HistoryStore history;
  final StoragePaths paths;
  final DateTime Function() _clock;
  final AlertEvaluator _alerts;

  final _lastRun = <Monitor, DateTime>{};
  final fired = <FiredAlert>[];

  /// The widget and overlay values last shown, by field.
  final _shown = <String, String>{};
  Timer? _timer;
  bool _busy = false;
  bool _stopping = false;
  late DateTime startedAt;
  DateTime? deadline;

  Map<Monitor, int> get _monitors => config.plan.monitors;

  /// Base tick: the shortest interval, but at least 5 s.
  Duration get tick {
    final shortest = _monitors.values.fold<int>(3600, (a, b) => b < a ? b : a);
    return Duration(seconds: shortest < 5 ? 5 : shortest);
  }

  Future<void> start() async {
    startedAt = _clock();
    deadline = config.plan.autoStop.deadline(startedAt);
    await history.prune(config.retentionDays, startedAt);
    _timer = Timer.periodic(tick, (_) => runOnce());
    await runOnce();
  }

  /// One tick; public so tests can drive the loop without timers.
  Future<void> runOnce() async {
    if (_busy || _stopping) return;
    _busy = true;
    try {
      final now = _clock();
      final due = {
        for (final e in _monitors.entries)
          if (_lastRun[e.key] == null ||
              now.difference(_lastRun[e.key]!).inSeconds >= e.value - 1)
            e.key,
      };
      for (final m in due) {
        _lastRun[m] = now;
      }
      final sample = await reader.sample(
        monitors: due.isEmpty ? {Monitor.battery} : due,
      );
      final processes = due.contains(Monitor.processes)
          ? await _processes()
          : const <ProcessInfo>[];
      final record = historyRecord(
        sample,
        processes: processes,
        wifiRssi: due.contains(Monitor.wifi) ? await _wifiRssi() : null,
        wifiNetworks: due.contains(Monitor.wifi) ? await _wifiCount() : null,
        bluetoothDevices: due.contains(Monitor.bluetooth)
            ? await _bluetoothCount()
            : null,
        storageUsedPercent: due.contains(Monitor.storage)
            ? await _storageUsed()
            : null,
      );
      if (due.isNotEmpty) await history.append(record);
      await _raiseAlerts(sample, processes);
      await _publish(sample, now);
      final reason = _stopReason(sample, now);
      if (reason != null) await stop(reason);
    } finally {
      _busy = false;
    }
  }

  Future<void> stop(String reason) async {
    if (_stopping) return;
    _stopping = true;
    _timer?.cancel();
    String? saved;
    if (config.plan.snapshotOnStop) saved = await saveSnapshot();
    await platform.notify(
      90,
      'Background scan finished',
      saved == null ? reason : '$reason Snapshot saved in TurboMon.',
    );
    await platform.overlay(null);
    await platform.stopService();
  }

  /// Writes a snapshot of this run to the saved-snapshots folder.
  Future<String?> saveSnapshot() async {
    try {
      final now = _clock();
      final records = await history.read(since: startedAt, until: now);
      final input = SnapshotInput(
        generatedAt: now,
        device: await platform.device(),
        accessLevel: reader.access.level.label,
        series: seriesFromHistory(records),
        cpuIsFrequencyProxy: historyCpuIsProxy(records),
        processAverages: processAveragesFromHistory(records),
        alerts: fired,
        diagnostics: await reader.diagnostics(),
      );
      await paths.savedSnapshots.create(recursive: true);
      final file = File(
        p.join(paths.savedSnapshots.path, snapshotFileName(now)),
      );
      await file.writeAsString(buildSnapshot(input));
      return file.path;
    } on Object {
      return null;
    }
  }

  String? _stopReason(SystemSample sample, DateTime now) {
    final auto = config.plan.autoStop;
    final end = deadline;
    if (end != null && !now.isBefore(end)) {
      return 'Ran for ${formatDuration(now.difference(startedAt))}.';
    }
    final level = sample.battery?.percent;
    if (auto.mode == AutoStopMode.batteryBelow &&
        level != null &&
        level < auto.batteryBelow) {
      return 'Battery fell below ${auto.batteryBelow} %.';
    }
    return null;
  }

  Future<void> _raiseAlerts(
    SystemSample sample,
    List<ProcessInfo> processes,
  ) async {
    final culprit = processes.isEmpty ? null : processes.first.name;
    for (final alert in _alerts.check(sample, culprit: culprit)) {
      fired.add(alert);
      await platform.notify(alert.rule.metric.index, alert.title, alert.text);
      if (alert.rule.autoSnapshot) await saveSnapshot();
    }
  }

  /// Notification text, widget values and the overlay.
  Future<void> _publish(SystemSample s, DateTime now) async {
    final names = [for (final m in _monitors.keys) m.label].join(', ');
    final end = deadline;
    final left = end == null
        ? config.plan.autoStop.describe()
        : '${formatDuration(end.difference(now))} left';
    await platform.serviceStatus('$names · $left');

    String? pct(double? v) => v == null ? null : '${v.round()}%';
    final temps = [s.thermal?.hottest, s.battery?.temperatureC].nonNulls;
    final temp = temps.isEmpty ? null : temps.reduce((a, b) => a > b ? a : b);
    // Monitors not due this tick keep their last reading instead of blanking.
    final fresh = {
      'cpu': pct(s.cpu?.load),
      'ram': pct(s.memory?.usedPercent),
      'battery': pct(s.battery?.percent),
      'temp': temp == null ? null : '${temp.round()}°C',
    };
    for (final e in fresh.entries) {
      if (e.value != null) _shown[e.key] = e.value!;
    }
    final values = {for (final k in fresh.keys) k: _shown[k] ?? '–'};
    await platform.updateWidget(values);
    if (config.overlay) {
      await platform.overlay(
        'CPU ${values['cpu']}  RAM ${values['ram']}\n'
        'BAT ${values['battery']}  ${values['temp']}',
      );
    }
  }

  Future<List<ProcessInfo>> _processes() async {
    final list = await reader.processes(limit: 10);
    if (list.isEmpty) return list;
    final mah = await reader.batteryByUid();
    return [for (final p in list) p.withBattery(mah[p.uid])];
  }

  Future<int?> _wifiRssi() async {
    try {
      final raw = await platform.wifiConnection();
      final link = raw == null ? null : WifiLink.fromJson(raw);
      return link != null && link.valid ? link.rssi : null;
    } on Object {
      return null;
    }
  }

  Future<int?> _wifiCount() async {
    try {
      await platform.wifiStartScan();
      return (await platform.wifiScanResults()).length;
    } on Object {
      return null;
    }
  }

  /// Counts devices seen during a short LE scan.
  Future<int?> _bluetoothCount() async {
    final seen = <String>{};
    StreamSubscription<JsonMap>? sub;
    try {
      sub = platform.bluetoothScan().listen((event) {
        for (final d in event['devices'] as List? ?? const []) {
          seen.add((d as Map)['address'] as String);
        }
      });
      await Future<void>.delayed(const Duration(seconds: 6));
      return seen.length;
    } on Object {
      return null;
    } finally {
      await sub?.cancel();
    }
  }

  Future<double?> _storageUsed() async {
    try {
      final volumes = [
        for (final v in await platform.storageVolumes())
          StorageVolume.fromJson(v),
      ];
      final primary = volumes.where((v) => !v.removable).firstOrNull;
      return primary?.usedPercent;
    } on Object {
      return null;
    }
  }
}

/// Builds the runner for the service's headless engine.
Future<BackgroundRunner> createBackgroundRunner(
  TurboMonPlatform platform,
  BackgroundConfig config,
) async {
  final access = AccessController(platform);
  // Rights were granted in the foreground; never prompt from the service.
  await access.resolve(config.accessMode, interactive: false);
  final paths = await StoragePaths.resolve();
  return BackgroundRunner(
    config: config,
    reader: SystemReader(platform: platform, access: access),
    platform: platform,
    history: HistoryStore(paths.history),
    paths: paths,
  );
}
