import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:turbomon_platform/turbomon_platform.dart';

import '../models/wifi.dart';
import 'permissions.dart';
import 'time_series.dart';

enum WifiState { idle, needsPermission, disabled, scanning }

/// Live Wi-Fi data for the Wi-Fi tab, within Android's scan throttle:
///
/// * results from anyone's scan arrive through the platform event stream;
/// * TurboMon's own scans start every 5 s and fall back to every 30 s (its
///   4-per-2-minutes budget) as soon as Android rejects one;
/// * the connected link is polled every second, which is not throttled.
class WifiController extends ChangeNotifier {
  WifiController({
    required this.platform,
    required this.permissions,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final TurboMonPlatform platform;
  final Permissions permissions;
  final DateTime Function() _clock;

  static const fastInterval = Duration(seconds: 5);
  static const throttledInterval = Duration(seconds: 30);
  static const historyLength = 30;
  static const signalCapacity = 120;

  WifiState state = WifiState.idle;
  List<WifiNetwork> networks = const [];
  WifiLink? link;
  DateTime? lastResults;

  /// Null until known; false once a scan was rejected.
  bool? throttleOff;

  /// Newest-last list of scans, each as bssid -> network, for the waterfall.
  final history = ListQueue<Map<String, WifiNetwork>>();

  /// Signal over time for tracked networks, by bssid.
  final signal = <String, TimeSeries>{};
  final tracked = <String>{};
  final linkSignal = TimeSeries(signalCapacity);

  StreamSubscription<JsonMap>? _events;
  Timer? _scanTimer;
  Timer? _linkTimer;
  bool _active = false;

  Duration get scanInterval =>
      throttleOff == false ? throttledInterval : fastInterval;

  Future<void> start() async {
    if (_active) return;
    _active = true;
    if (!await permissions.ensure(await permissions.wifi())) {
      _setState(WifiState.needsPermission);
      _active = false;
      return;
    }
    if (!await platform.wifiEnabled()) {
      _setState(WifiState.disabled);
      _active = false;
      return;
    }
    _setState(WifiState.scanning);
    _events = platform.wifiEvents().listen((event) {
      if (event['type'] == 'scan') unawaited(_loadResults());
    });
    _linkTimer = Timer.periodic(const Duration(seconds: 1), (_) => _pollLink());
    await _loadResults();
    await _scan();
  }

  void stop() {
    _active = false;
    _events?.cancel();
    _events = null;
    _scanTimer?.cancel();
    _linkTimer?.cancel();
    if (state == WifiState.scanning) state = WifiState.idle;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }

  void toggleTracked(String bssid) {
    if (!tracked.remove(bssid)) tracked.add(bssid);
    notifyListeners();
  }

  Future<void> _scan() async {
    if (!_active) return;
    final accepted = await platform.wifiStartScan();
    if (!accepted) {
      throttleOff = false;
    } else if (throttleOff == null) {
      _acceptedScans.add(_clock());
      _acceptedScans.removeWhere(
        (t) => _clock().difference(t) > const Duration(minutes: 2),
      );
      // More than 4 accepted in 2 minutes: throttling is switched off.
      if (_acceptedScans.length > 4) throttleOff = true;
    }
    _scanTimer?.cancel();
    _scanTimer = Timer(scanInterval, _scan);
    notifyListeners();
  }

  final _acceptedScans = <DateTime>[];

  Future<void> _loadResults() async {
    try {
      final raw = await platform.wifiScanResults();
      networks = [for (final r in raw) WifiNetwork.fromJson(r)]
        ..sort((a, b) => b.rssi.compareTo(a.rssi));
    } on PlatformException {
      _setState(WifiState.needsPermission);
      return;
    }
    final now = _clock();
    lastResults = now;
    history.addLast({for (final n in networks) n.bssid: n});
    while (history.length > historyLength) {
      history.removeFirst();
    }
    if (tracked.isEmpty) tracked.addAll(networks.take(3).map((n) => n.bssid));
    for (final n in networks) {
      if (tracked.contains(n.bssid)) {
        signal
            .putIfAbsent(n.bssid, () => TimeSeries(signalCapacity))
            .add(now, n.rssi.toDouble());
      }
    }
    notifyListeners();
  }

  Future<void> _pollLink() async {
    final raw = await platform.wifiConnection();
    final next = raw == null ? null : WifiLink.fromJson(raw);
    link = next != null && next.valid ? next : null;
    if (link != null) linkSignal.add(_clock(), link!.rssi.toDouble());
    notifyListeners();
  }

  void _setState(WifiState s) {
    state = s;
    notifyListeners();
  }
}
