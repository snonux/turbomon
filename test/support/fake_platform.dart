import 'dart:async';

import 'package:turbomon_platform/turbomon_platform.dart';

/// In-memory stand-in for the Android plugin. Tests set the fields they need
/// and read the recorded calls.
class FakePlatform extends TurboMonPlatform {
  FakePlatform();

  JsonMap deviceInfo = const {
    'manufacturer': 'Google',
    'model': 'Pixel Test',
    'release': '14',
    'sdk': 34,
    'kernel': '6.1.0',
    'cores': 4,
  };
  JsonMap memoryInfo = const {'total': 8 << 30, 'available': 3 << 30};
  JsonMap batteryInfo = const {
    'percent': 80.0,
    'status': 'discharging',
    'charging': false,
    'temperatureC': 31.5,
    'voltageMv': 3900,
    'currentNow': -450000,
    'screenOn': true,
  };
  JsonMap thermalInfo = const {'status': 0, 'headroom': 0.4};
  int rx = 0, tx = 0, elapsed = 0;
  List<JsonMap> volumes = const [
    {
      'label': 'Internal shared storage',
      'path': '/storage/emulated/0',
      'total': 128 << 30,
      'free': 40 << 30,
      'removable': false,
    },
  ];
  List<JsonMap> wifiResults = const [];
  JsonMap? wifiLink;
  bool wifiScanAccepted = true;
  int wifiScans = 0;
  List<JsonMap> paired = const [];
  JsonMap shizuku = const {'running': false, 'granted': false};
  String Function(String script)? shell;
  Map<String, bool> granted = {};
  bool running = false;
  String? config;

  final notifications = <(int, String, String)>[];
  final statuses = <String>[];
  final widgetValues = <Map<String, String>>[];
  final overlays = <String?>[];
  final wifiController = StreamController<JsonMap>.broadcast();
  final bluetoothController = StreamController<JsonMap>.broadcast();

  @override
  Future<JsonMap> device() async => deviceInfo;
  @override
  Future<JsonMap> memory() async => memoryInfo;
  @override
  Future<JsonMap> battery() async => batteryInfo;
  @override
  Future<JsonMap> thermal() async => thermalInfo;
  @override
  Future<JsonMap> traffic() async {
    elapsed += 1000;
    return {
      'elapsedMs': elapsed,
      'totalRx': rx,
      'totalTx': tx,
      'mobileRx': 0,
      'mobileTx': 0,
    };
  }

  @override
  Future<List<JsonMap>> storageVolumes() async => volumes;
  @override
  Future<bool> hasUsageAccess() async => false;
  @override
  Future<bool> wifiEnabled() async => true;
  @override
  Future<bool> wifiStartScan() async {
    wifiScans++;
    return wifiScanAccepted;
  }

  @override
  Future<List<JsonMap>> wifiScanResults() async => wifiResults;
  @override
  Future<JsonMap?> wifiConnection() async => wifiLink;
  @override
  Stream<JsonMap> wifiEvents() => wifiController.stream;
  @override
  Future<JsonMap> bluetoothState() async => const {
    'supported': true,
    'enabled': true,
    'le': true,
  };
  @override
  Future<List<JsonMap>> bluetoothPaired() async => paired;
  @override
  Future<bool> bluetoothDiscover() async => true;
  @override
  Stream<JsonMap> bluetoothScan() => bluetoothController.stream;
  @override
  Future<Map<String, bool>> permissionStatus(List<String> permissions) async =>
      {for (final p in permissions) p: granted[p] ?? true};
  @override
  Future<Map<String, bool>> requestPermissions(List<String> permissions) =>
      permissionStatus(permissions);
  @override
  Future<bool> canDrawOverlays() async => true;
  @override
  Future<JsonMap> shizukuStatus() async => shizuku;
  @override
  Future<bool> shizukuRequestPermission() async => shizuku['granted'] == true;
  @override
  Future<String> shizukuExec(String script) async => shell?.call(script) ?? '';
  @override
  Future<void> startService(String config) async {
    this.config = config;
    running = true;
  }

  @override
  Future<void> stopService() async => running = false;
  @override
  Future<bool> serviceRunning() async => running;
  @override
  Future<String?> serviceConfig() async => config;
  @override
  Future<void> serviceStatus(String text) async => statuses.add(text);
  @override
  Future<void> overlay(String? text) async => overlays.add(text);
  @override
  Future<void> updateWidget(Map<String, String> values) async =>
      widgetValues.add(values);
  @override
  Future<void> notify(int id, String title, String text) async =>
      notifications.add((id, title, text));
}
