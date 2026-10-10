import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../model/ring_buffer.dart';
import '../model/settings.dart';
import '../platform/access.dart';
import '../platform/native_bridge.dart';
import 'alerts.dart';
import 'history.dart';
import 'monitor_controller.dart';
import 'radio_controllers.dart';
import 'snapshot.dart';

/// Loads and saves [Settings] as one JSON string.
class SettingsStore {
  static const _key = 'turbomon.settings.v1';

  Future<Settings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return Settings.decode(prefs.getString(_key));
  }

  Future<void> save(Settings s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, s.encode());
  }
}

/// Picks the privileged shell for an [AccessMode]; injectable for tests.
typedef ShellResolver = Future<PrivilegedShell> Function(AccessMode mode, {bool requestShizuku});

/// Wires the controllers together and owns everything screens share.
class AppState extends ChangeNotifier {
  AppState({
    required this.bridge,
    required this.store,
    required Settings settings,
    SystemFiles? files,
    ShellResolver? shellResolver,
    this.appVersion = '0.0.0',
  })  : _settings = settings,
        _resolveShell = shellResolver ??
            ((mode, {requestShizuku = false}) => resolveShell(mode, bridge, requestShizuku: requestShizuku)),
        monitor = MonitorController(
          bridge: bridge,
          files: files ?? RealSystemFiles(),
          settings: settings,
        ),
        wifi = WifiController(bridge, scanInterval: Duration(seconds: settings.wifiScanSeconds)),
        bluetooth = BluetoothController(bridge);

  final NativeBridge bridge;
  final SettingsStore store;
  final ShellResolver _resolveShell;
  final String appVersion;
  final MonitorController monitor;
  final WifiController wifi;
  final BluetoothController bluetooth;

  Settings _settings;
  Settings get settings => _settings;

  Map<String, Object?> background = const {};
  bool get backgroundRunning => background['running'] == true;
  String shizukuState = 'missing';

  String? _filesDir;
  Future<String> filesDir() async => _filesDir ??= await bridge.filesDir();

  Future<void> init() async {
    monitor.onAlert = _onAlert;
    monitor.start();
    await refreshAccess();
    await refreshBackground();
    unawaited(processPendingSnapshots());
  }

  Future<void> refreshAccess({bool requestShizuku = false}) async {
    shizukuState = await bridge.shizukuState().catchError((_) => 'missing');
    final shell = await _resolveShell(_settings.accessMode, requestShizuku: requestShizuku);
    monitor.setShell(shell);
    shizukuState = await bridge.shizukuState().catchError((_) => 'missing');
    notifyListeners();
  }

  Future<void> refreshBackground() async {
    background = await bridge.backgroundState().catchError((_) => <String, Object?>{});
    // The service may have stopped on its own (auto-stop); keep the switch honest.
    if (_settings.backgroundEnabled && !backgroundRunning) {
      _settings = _settings.copyWith(backgroundEnabled: false);
      await store.save(_settings);
    }
    notifyListeners();
  }

  Future<void> updateSettings(Settings s) async {
    final accessChanged = s.accessMode != _settings.accessMode;
    _settings = s;
    await store.save(s);
    monitor.updateSettings(s);
    wifi.scanInterval = Duration(seconds: s.wifiScanSeconds);
    if (backgroundRunning) {
      await bridge.updateServiceConfig(s.serviceConfig()).catchError((_) {});
    }
    if (accessChanged) await refreshAccess(requestShizuku: true);
    notifyListeners();
  }

  /// Starts background scanning with the settings' plan, or a preset's.
  Future<void> startBackground([BackgroundPlan? plan]) async {
    final s = _settings.copyWith(backgroundEnabled: true, plan: plan ?? _settings.plan);
    _settings = s;
    await store.save(s);
    await bridge.startBackground(s.serviceConfig());
    await refreshBackground();
  }

  Future<void> stopBackground() async {
    _settings = _settings.copyWith(backgroundEnabled: false);
    await store.save(_settings);
    await bridge.stopBackground().catchError((_) {});
    await refreshBackground();
  }

  Future<void> _onAlert(FiredAlert a) async {
    await bridge.notify(1000 + a.kind.index, a.kind.title, a.message).catchError((_) {});
    if (_settings.alerts.autoSnapshot) {
      await takeSnapshot(reason: 'Automatic, after alert: ${a.message}');
    }
  }

  // Snapshots ---------------------------------------------------------------

  Future<Directory> snapshotsDir() async {
    final d = Directory(p.join(await filesDir(), 'snapshots'));
    await d.create(recursive: true);
    return d;
  }

  Future<List<File>> listSnapshots() async {
    final d = await snapshotsDir();
    final files = await d.list().where((e) => e is File && e.path.endsWith('.md')).cast<File>().toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  Future<SnapshotInput> _input({
    required String reason,
    required DateTime from,
    required DateTime to,
    List<HistorySample> history = const [],
    List<FiredAlert>? alerts,
  }) async {
    final m = monitor;
    final raw = <String, String>{};
    if (m.access.elevated) {
      for (final cmd in const [
        'dumpsys cpuinfo',
        'dumpsys power | grep -iE "wake ?lock|PARTIAL_WAKE"',
      ]) {
        final r = await m.shell.run(cmd);
        if (r.ok) raw[cmd] = r.stdout.length > 20000 ? r.stdout.substring(0, 20000) : r.stdout;
      }
    }
    final series = <String, RingBuffer>{
      'cpu': m.cpu,
      'ramUsedPercent': m.ram,
      if (m.gpuAvailable) 'gpuPercent': m.gpu,
      'batteryDrainMa': m.batteryDrain,
      'batteryPowerW': m.batteryPower,
      'batteryTempC': m.batteryTemp,
      'hottestC': m.hottest,
      'netRxBps': m.netRx,
      'netTxBps': m.netTx,
      if (m.diskIoAvailable) 'diskReadBps': m.diskRead,
      if (m.diskIoAvailable) 'diskWriteBps': m.diskWrite,
      for (var i = 0; i < m.cores.length; i++) 'core$i': m.cores[i],
    };
    final screenSamples = history.map((s) => s.raw['screenOn']).whereType<bool>().toList();
    return SnapshotInput(
      takenAt: DateTime.now(),
      reason: reason,
      appVersion: appVersion,
      device: m.device,
      access: m.access.label,
      windowStart: from,
      windowEnd: to,
      series: history.isEmpty ? series : _seriesFromHistory(history),
      cpuIsProxy: history.isEmpty ? m.cpuIsProxy : history.any((s) => s.raw['cpuProxy'] == true),
      mem: m.mem,
      battery: m.battery,
      thermalStatus: m.thermalStatus,
      thermalHeadroom: m.thermalHeadroom,
      zones: m.zones,
      volumes: m.volumes,
      diskRates: m.diskRates,
      processes: m.processes,
      wifi: wifi.networks,
      wifiConnection: wifi.connection,
      bluetooth: [for (final g in bluetooth.sorted) g.latest],
      bluetoothConnected: bluetooth.connected,
      alerts: alerts ?? m.firedAlerts.where((a) => !a.at.isBefore(from)).toList(),
      history: history,
      includeAddresses: _settings.includeAddresses,
      rawShellOutput: raw,
      screenOff: screenSamples.isEmpty
          ? null
          : screenSamples.where((on) => !on).length > screenSamples.length / 2,
    );
  }

  static Map<String, RingBuffer> _seriesFromHistory(List<HistorySample> h) {
    final keys = {
      'cpu': 'cpu',
      'ramUsedPercent': 'ram',
      'gpuPercent': 'gpu',
      'batteryDrainMa': 'drainMa',
      'batteryPowerW': 'powerW',
      'batteryTempC': 'battTempC',
      'hottestC': 'hottestC',
      'netRxBps': 'rxBps',
      'netTxBps': 'txBps',
      'diskReadBps': 'diskReadBps',
      'diskWriteBps': 'diskWriteBps',
      'wifiBestDbm': 'wifiBest',
      'bluetoothDevices': 'btCount',
      'batteryLevel': 'battLevel',
    };
    final out = <String, RingBuffer>{};
    keys.forEach((name, k) {
      if (!h.any((s) => s.raw[k] != null)) return;
      final r = RingBuffer(h.length);
      for (final s in h) {
        r.add(s.num_(k), s.time);
      }
      out[name] = r;
    });
    return out;
  }

  /// Takes a snapshot of the live window, or of background history when
  /// [from] is given, and saves it. Returns the file.
  Future<File> takeSnapshot({
    String reason = 'Taken by hand',
    DateTime? from,
    DateTime? to,
    List<FiredAlert>? alerts,
  }) async {
    final end = to ?? DateTime.now();
    List<HistorySample> history = const [];
    DateTime start;
    if (from != null) {
      start = from;
      history = await HistoryReader(p.join(await filesDir(), 'history')).read(from, end);
    } else {
      start = monitor.cpu.times.isEmpty ? (monitor.startedAt ?? end) : monitor.cpu.times.first;
    }
    final input = await _input(reason: reason, from: start, to: end, history: history, alerts: alerts);
    final dir = await snapshotsDir();
    final file = File(p.join(dir.path, snapshotFileName(input.takenAt)));
    await file.writeAsString(buildSnapshot(input));
    notifyListeners();
    return file;
  }

  /// Turns requests left by the background service (an alert, or the end of
  /// a run) into saved snapshots of the history they cover.
  Future<int> processPendingSnapshots() async {
    final dir = Directory(p.join(await filesDir(), 'snapshot-requests'));
    if (!await dir.exists()) return 0;
    var n = 0;
    await for (final e in dir.list()) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      try {
        final j = (jsonDecode(await e.readAsString()) as Map).cast<String, Object?>();
        final from = DateTime.fromMillisecondsSinceEpoch((j['fromMs'] as num).toInt());
        final to = DateTime.fromMillisecondsSinceEpoch((j['toMs'] as num).toInt());
        await takeSnapshot(reason: (j['reason'] as String?) ?? 'Background run', from: from, to: to);
        n++;
      } on Object {
        // A malformed request would otherwise be retried forever.
      }
      await e.delete();
    }
    return n;
  }

  @override
  void dispose() {
    monitor.dispose();
    wifi.dispose();
    bluetooth.dispose();
    super.dispose();
  }
}
