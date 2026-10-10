import 'dart:async';

import 'package:flutter/foundation.dart';

import '../model/bluetooth.dart';
import '../model/ring_buffer.dart';
import '../parsers/wifi_channels.dart';
import '../platform/native_bridge.dart';

/// Android permission names used by the radio screens.
const wifiPermissionsModern = ['android.permission.NEARBY_WIFI_DEVICES'];
const wifiPermissionsLegacy = ['android.permission.ACCESS_FINE_LOCATION'];
const btPermissionsModern = [
  'android.permission.BLUETOOTH_SCAN',
  'android.permission.BLUETOOTH_CONNECT',
];
const btPermissionsLegacy = ['android.permission.ACCESS_FINE_LOCATION'];

/// Live Wi-Fi survey. Android allows a foreground app 4 scans per 2 minutes,
/// so TurboMon scans every [scanInterval] (30 s by default) and also takes
/// every result the system or other apps produce. The connected network's
/// signal is not throttled and is polled every second.
class WifiController extends ChangeNotifier {
  WifiController(this.bridge, {this.scanInterval = const Duration(seconds: 30), this.historyLength = 40});

  final NativeBridge bridge;
  Duration scanInterval;
  final int historyLength;

  List<WifiNetwork> networks = const [];
  Map<String, Object?>? connection;
  DateTime? lastResults;
  DateTime? lastScanRequest;
  int scansRejected = 0;
  int scansAccepted = 0;
  bool permissionGranted = false;
  bool active = false;

  /// Signal history per BSSID for the signal-over-time graph.
  final Map<String, RingBuffer> signalHistory = {};
  late final RingBuffer connectedSignal = RingBuffer(120);

  /// Strongest signal per channel for each past result set, newest last,
  /// for the waterfall view.
  final List<(DateTime, Map<WifiBand, Map<int, int>>)> waterfall = [];

  /// Whether throttling looks off: several scans in a row were accepted
  /// less than 30 s apart.
  bool get throttlingOff => _fastAccepted >= 4;
  int _fastAccepted = 0;

  StreamSubscription<List<Map<String, Object?>>>? _sub;
  Timer? _scanTimer;
  Timer? _connTimer;

  Future<void> start() async {
    if (active) return;
    active = true;
    _sub = bridge.wifiResults().listen(_onResults, onError: (_) {});
    _onResults(await bridge.wifiScanResults().catchError((_) => <Map<String, Object?>>[]));
    await _scan();
    _schedule();
    _connTimer = Timer.periodic(const Duration(seconds: 1), (_) => _pollConnection());
    notifyListeners();
  }

  void _schedule() {
    _scanTimer?.cancel();
    final every = throttlingOff ? const Duration(seconds: 5) : scanInterval;
    _scanTimer = Timer.periodic(every, (_) async {
      final wasOff = throttlingOff;
      await _scan();
      if (wasOff != throttlingOff) _schedule();
    });
  }

  Future<void> _scan() async {
    final now = DateTime.now();
    final prev = lastScanRequest;
    lastScanRequest = now;
    final ok = await bridge.startWifiScan().catchError((_) => false);
    if (ok) {
      scansAccepted++;
      if (prev != null && now.difference(prev) < const Duration(seconds: 30)) {
        _fastAccepted++;
      }
    } else {
      scansRejected++;
      _fastAccepted = 0;
    }
    notifyListeners();
  }

  /// Scan now, e.g. from pull-to-refresh; may be rejected by the throttle.
  Future<void> scanNow() => _scan();

  /// Probe scan cadence without throttling (developer option off).
  Future<void> tryFastScanning() async {
    lastScanRequest = DateTime.now().subtract(const Duration(seconds: 10));
    await _scan();
    _schedule();
  }

  Future<void> _pollConnection() async {
    final c = await bridge.wifiConnection().catchError((_) => null);
    connection = c;
    final rssi = (c?['rssi'] as num?)?.toDouble();
    connectedSignal.add(rssi, DateTime.now());
    notifyListeners();
  }

  void _onResults(List<Map<String, Object?>> raw) {
    final now = DateTime.now();
    networks = [for (final m in raw) WifiNetwork.fromMap(m)]..sort((a, b) => b.rssi.compareTo(a.rssi));
    lastResults = now;
    for (final n in networks) {
      signalHistory.putIfAbsent(n.bssid, () => RingBuffer(historyLength)).add(n.rssi.toDouble(), now);
    }
    // Networks that vanished get a gap so their line breaks.
    for (final e in signalHistory.entries) {
      if (!networks.any((n) => n.bssid == e.key)) e.value.add(null, now);
    }
    final row = <WifiBand, Map<int, int>>{};
    for (final band in WifiBand.values) {
      final loads = channelLoads(band, networks);
      row[band] = {
        for (final l in loads)
          if (l.strongest != null) l.channel: l.strongest!,
      };
    }
    waterfall.add((now, row));
    if (waterfall.length > historyLength) waterfall.removeAt(0);
    notifyListeners();
  }

  void stop() {
    active = false;
    _sub?.cancel();
    _scanTimer?.cancel();
    _connTimer?.cancel();
    _sub = null;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}

/// Live Bluetooth survey from a continuous LE scan. Unlike Wi-Fi, Android
/// only rejects apps that start more than 5 scans in 30 s, so one long scan
/// reports devices about once a second.
class BluetoothController extends ChangeNotifier {
  BluetoothController(this.bridge);

  final NativeBridge bridge;
  final Map<String, BtGroup> devices = {};
  final Map<String, RingBuffer> signalHistory = {};
  List<BtDevice> connected = const [];
  bool active = false;
  bool enabled = true;
  String? error;
  StreamSubscription<Map<String, Object?>>? _sub;
  Timer? _tick;

  List<BtGroup> get sorted {
    final now = DateTime.now();
    final list = devices.values
        .where((g) => now.difference(g.latest.lastSeen) < const Duration(minutes: 2))
        .toList()
      ..sort((a, b) => b.latest.rssi.compareTo(a.latest.rssi));
    return list;
  }

  Future<void> start() async {
    if (active) return;
    active = true;
    error = null;
    enabled = await bridge.bluetoothEnabled().catchError((_) => false);
    if (!enabled) {
      notifyListeners();
      return;
    }
    _sub = bridge.bluetoothSightings().listen((m) {
      if (m['error'] != null) {
        error = '${m['error']}';
        notifyListeners();
        return;
      }
      final d = BtDevice.fromMap(m);
      mergeSighting(devices, d);
      notifyListeners();
    }, onError: (Object e) {
      error = '$e';
      notifyListeners();
    });
    await refreshConnected();
    // Once a second, append every group's latest signal (or a gap) so the
    // graph scrolls even when a device is quiet.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      for (final g in devices.values) {
        final key = groupKey(g.latest);
        final fresh = now.difference(g.latest.lastSeen) < const Duration(seconds: 5);
        signalHistory
            .putIfAbsent(key, () => RingBuffer(120))
            .add(fresh ? g.latest.rssi.toDouble() : null, now);
      }
    });
    notifyListeners();
  }

  Future<void> refreshConnected() async {
    final list = await bridge.connectedBluetooth().catchError((_) => <Map<String, Object?>>[]);
    connected = [for (final m in list) BtDevice.fromMap(m)];
    notifyListeners();
  }

  Future<void> classicDiscovery() => bridge.startClassicDiscovery().catchError((_) {});

  void stop() {
    active = false;
    _sub?.cancel();
    _sub = null;
    _tick?.cancel();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
