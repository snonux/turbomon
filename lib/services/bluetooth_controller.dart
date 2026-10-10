import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:turbomon_platform/turbomon_platform.dart';

import '../models/bluetooth.dart';
import 'permissions.dart';
import 'time_series.dart';

enum BluetoothScanState {
  idle,
  needsPermission,
  disabled,
  unsupported,
  scanning,
}

/// Live Bluetooth data for the Bluetooth tab: one long-running LE scan
/// (updates about once a second), classic discovery on request and the paired
/// devices with their connection state.
class BluetoothController extends ChangeNotifier {
  BluetoothController({
    required this.platform,
    required this.permissions,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final TurboMonPlatform platform;
  final Permissions permissions;
  final DateTime Function() _clock;

  static const staleAfter = Duration(seconds: 60);
  static const signalCapacity = 120;

  BluetoothScanState state = BluetoothScanState.idle;
  final Map<String, BluetoothSighting> _byGroup = {};
  List<PairedDevice> paired = const [];
  final signal = <String, TimeSeries>{};
  final tracked = <String>{};
  bool discovering = false;

  StreamSubscription<JsonMap>? _scan;
  Timer? _pairedTimer;

  /// Devices seen in the last minute, strongest first.
  List<BluetoothSighting> get devices {
    final cutoff = _clock().subtract(staleAfter);
    return _byGroup.values.where((d) => d.lastSeen.isAfter(cutoff)).toList()
      ..sort((a, b) => (b.rssi ?? -200).compareTo(a.rssi ?? -200));
  }

  Future<void> start() async {
    if (_scan != null) return;
    final adapter = await platform.bluetoothState();
    if (adapter['supported'] != true) {
      return _set(BluetoothScanState.unsupported);
    }
    if (!await permissions.ensure(await permissions.bluetooth())) {
      return _set(BluetoothScanState.needsPermission);
    }
    if (adapter['enabled'] != true) return _set(BluetoothScanState.disabled);
    _set(BluetoothScanState.scanning);
    _scan = platform.bluetoothScan().listen(_onEvent);
    _pairedTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _loadPaired(),
    );
    unawaited(_loadPaired());
  }

  void stop() {
    _scan?.cancel();
    _scan = null;
    _pairedTimer?.cancel();
    discovering = false;
    if (state == BluetoothScanState.scanning) state = BluetoothScanState.idle;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }

  /// Starts a classic discovery pass; its finds join the same list.
  Future<void> discover() async {
    try {
      discovering = await platform.bluetoothDiscover();
    } on PlatformException {
      discovering = false;
    }
    notifyListeners();
    if (discovering) {
      Timer(const Duration(seconds: 12), () {
        discovering = false;
        notifyListeners();
      });
    }
  }

  void toggleTracked(String groupKey) {
    if (!tracked.remove(groupKey)) tracked.add(groupKey);
    notifyListeners();
  }

  void _onEvent(JsonMap event) {
    if (event['type'] == 'error') {
      final code = event['code'];
      _set(
        code == -2
            ? BluetoothScanState.needsPermission
            : BluetoothScanState.disabled,
      );
      return;
    }
    final now = _clock();
    for (final raw in event['devices'] as List? ?? const []) {
      final d = BluetoothSighting.fromJson(raw as JsonMap, now);
      _byGroup[d.groupKey] = d;
      if (tracked.isEmpty && d.name != null) tracked.add(d.groupKey);
      if (tracked.contains(d.groupKey) && d.rssi != null) {
        signal
            .putIfAbsent(d.groupKey, () => TimeSeries(signalCapacity))
            .add(now, d.rssi!.toDouble());
      }
    }
    notifyListeners();
  }

  Future<void> _loadPaired() async {
    try {
      paired = [
        for (final p in await platform.bluetoothPaired())
          PairedDevice.fromJson(p),
      ]..sort((a, b) => (b.connected ? 1 : 0) - (a.connected ? 1 : 0));
      notifyListeners();
    } on PlatformException {
      // Permission withdrawn mid-scan; the scan stream reports it too.
    }
  }

  void _set(BluetoothScanState s) {
    state = s;
    notifyListeners();
  }
}
