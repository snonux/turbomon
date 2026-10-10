import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:turbomon_platform/turbomon_platform.dart';

import '../models/readings.dart';
import '../models/settings.dart';
import 'alerts.dart';
import 'system_reader.dart';
import 'time_series.dart';

/// The series each live graph plots.
enum SeriesKey {
  cpu('CPU', '%'),
  ram('RAM', '%'),
  gpu('GPU', '%'),
  batteryPower('Battery power', 'W'),
  batteryPercent('Battery level', '%'),
  temperature('Temperature', '°C'),
  netRx('Download', 'B/s'),
  netTx('Upload', 'B/s'),
  diskRead('Disk read', 'B/s'),
  diskWrite('Disk write', 'B/s');

  const SeriesKey(this.label, this.unit);
  final String label;
  final String unit;
}

/// Running CPU average of one process across ticks, for findings.
class ProcessAverage {
  double _sum = 0;
  int _count = 0;
  double peak = 0;

  void add(double cpu) {
    _sum += cpu;
    _count++;
    if (cpu > peak) peak = cpu;
  }

  int get samples => _count;
  double get average => _count == 0 ? 0 : _sum / _count;
}

/// Samples the system while TurboMon is in the foreground and keeps the
/// ring buffers behind every graph. Sampling pauses while the app is in the
/// background; the optional background service has its own loop.
class MonitorHub extends ChangeNotifier with WidgetsBindingObserver {
  MonitorHub({
    required this.reader,
    required this.platform,
    required AppSettings settings,
  }) : _settings = settings {
    _resetSeries();
  }

  final SystemReader reader;
  final TurboMonPlatform platform;
  AppSettings _settings;

  Timer? _timer;
  bool _sampling = false;
  bool _processesBusy = false;
  bool _paused = false;
  DateTime? _lastBatteryStats;
  DateTime? _lastVolumes;
  AlertEvaluator _alerts = AlertEvaluator(const []);

  final DateTime startedAt = DateTime.now();
  SystemSample? latest;
  late Map<SeriesKey, TimeSeries> series;
  late List<TimeSeries> coreSeries;
  List<ProcessInfo> processes = const [];
  final Map<String, ProcessAverage> processAverages = {};
  Map<int, double> _batteryByUid = const {};
  List<StorageVolume> volumes = const [];
  final List<FiredAlert> firedAlerts = [];

  bool get running => _timer != null;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _alerts = AlertEvaluator(_settings.alerts);
    _schedule();
    unawaited(tick());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  /// Applies new settings: refresh rate, graph window and alert rules.
  void applySettings(AppSettings settings) {
    final resized = settings.graphCapacity != _settings.graphCapacity;
    final retimed = settings.refreshSeconds != _settings.refreshSeconds;
    _settings = settings;
    _alerts = AlertEvaluator(settings.alerts);
    if (resized) {
      series = series.map(
        (k, s) => MapEntry(k, s.resized(settings.graphCapacity)),
      );
      coreSeries = [
        for (final s in coreSeries) s.resized(settings.graphCapacity),
      ];
    }
    if (retimed && running) _schedule();
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final paused = state != AppLifecycleState.resumed;
    if (paused == _paused) return;
    _paused = paused;
    if (paused) {
      _timer?.cancel();
      _timer = null;
    } else {
      _schedule();
      unawaited(tick());
    }
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(seconds: _settings.refreshSeconds),
      (_) => tick(),
    );
  }

  void _resetSeries() {
    final n = _settings.graphCapacity;
    series = {for (final k in SeriesKey.values) k: TimeSeries(n)};
    coreSeries = [];
  }

  /// Takes one sample; overlapping ticks are skipped rather than queued.
  Future<void> tick() async {
    if (_sampling) return;
    _sampling = true;
    try {
      final sample = await reader.sample();
      _record(sample);
      latest = sample;
      unawaited(_refreshProcesses());
      unawaited(_refreshVolumes());
      await _checkAlerts(sample);
      notifyListeners();
    } finally {
      _sampling = false;
    }
  }

  void _record(SystemSample s) {
    void add(SeriesKey key, double? value) {
      if (value != null) series[key]!.add(s.time, value);
    }

    add(SeriesKey.cpu, s.cpu?.load);
    add(SeriesKey.ram, s.memory?.usedPercent);
    add(SeriesKey.gpu, s.gpu?.busyPercent);
    // Magnitude only; the screen colours it by charging state.
    add(SeriesKey.batteryPower, s.battery?.powerW?.abs());
    add(SeriesKey.batteryPercent, s.battery?.percent);
    final temps = [s.thermal?.hottest, s.battery?.temperatureC].nonNulls;
    add(
      SeriesKey.temperature,
      temps.isEmpty ? null : temps.reduce((a, b) => a > b ? a : b),
    );
    add(SeriesKey.netRx, s.network?.rxBps);
    add(SeriesKey.netTx, s.network?.txBps);
    add(SeriesKey.diskRead, s.diskIo?.readBps);
    add(SeriesKey.diskWrite, s.diskIo?.writeBps);

    final cores = s.cpu?.coreLoads ?? const [];
    while (coreSeries.length < cores.length) {
      coreSeries.add(TimeSeries(_settings.graphCapacity));
    }
    for (var i = 0; i < cores.length; i++) {
      final v = cores[i];
      if (v != null) coreSeries[i].add(s.time, v);
    }
  }

  Future<void> _refreshProcesses() async {
    if (_processesBusy || !reader.access.privileged) {
      if (!reader.access.privileged && processes.isNotEmpty) {
        processes = const [];
      }
      return;
    }
    _processesBusy = true;
    try {
      final now = DateTime.now();
      final stale =
          _lastBatteryStats == null ||
          now.difference(_lastBatteryStats!) > const Duration(minutes: 1);
      if (stale) {
        _lastBatteryStats = now;
        _batteryByUid = await reader.batteryByUid();
      }
      final list = await reader.processes();
      processes = [for (final p in list) p.withBattery(_batteryByUid[p.uid])];
      for (final p in processes) {
        processAverages
            .putIfAbsent(p.name, ProcessAverage.new)
            .add(p.cpuPercent);
      }
      notifyListeners();
    } finally {
      _processesBusy = false;
    }
  }

  Future<void> _refreshVolumes() async {
    final now = DateTime.now();
    if (_lastVolumes != null &&
        now.difference(_lastVolumes!) < const Duration(seconds: 30)) {
      return;
    }
    _lastVolumes = now;
    try {
      volumes = [
        for (final v in await platform.storageVolumes())
          StorageVolume.fromJson(v),
      ];
    } on Object {
      volumes = const [];
    }
  }

  Future<void> _checkAlerts(SystemSample sample) async {
    final culprit = processes.isEmpty ? null : processes.first.name;
    final fired = _alerts.check(sample, culprit: culprit);
    if (fired.isEmpty) return;
    firedAlerts.addAll(fired);
    // While the service runs it raises the same alerts; avoid doubles.
    if (await platform.serviceRunning()) return;
    for (final a in fired) {
      await platform.notify(a.rule.metric.index, a.title, a.text);
    }
  }
}
