import 'dart:async';

import 'package:turbomon/platform/access.dart';
import 'package:turbomon/platform/native_bridge.dart';

import 'samples.dart';

/// In-memory [NativeBridge] returning plausible data for a mid-range phone.
/// Wi-Fi and Bluetooth results are pushed by the test through [emitWifi] and
/// [emitBluetooth]. Every call is recorded in [calls].
class FakeBridge implements NativeBridge {
  FakeBridge({
    required this.filesDirPath,
    this.shizuku = 'missing',
    this.permissionsGranted = true,
    this.btEnabled = true,
    this.sdk = 34,
  });

  final String filesDirPath;
  String shizuku;
  bool permissionsGranted;
  bool btEnabled;
  int sdk;

  final List<String> calls = [];
  final wifiController = StreamController<List<Map<String, Object?>>>.broadcast();
  final btController = StreamController<Map<String, Object?>>.broadcast();

  List<Map<String, Object?>> lastScan = const [];
  Map<String, Object?>? connection;
  List<Map<String, Object?>> connectedDevices = const [];
  Map<String, Object?> backgroundStateValue = const {'running': false};
  Map<String, Object?>? startedConfig;
  Map<String, Object?>? updatedConfig;
  final List<(int, String, String)> notifications = [];
  final List<String> shared = [];
  int trafficTick = 0;

  /// Shell output served by [shizukuExec], keyed by exact command; when no
  /// key matches, the first key the command starts with is used.
  Map<String, ShellResult> shellResponses = {};

  void emitWifi(List<Map<String, Object?>> networks) {
    lastScan = networks;
    wifiController.add(networks);
  }

  void emitBluetooth(Map<String, Object?> sighting) => btController.add(sighting);

  Future<void> close() async {
    await wifiController.close();
    await btController.close();
  }

  @override
  Future<Map<String, Object?>> deviceInfo() async {
    calls.add('deviceInfo');
    return {
      'manufacturer': 'Google',
      'model': 'Pixel 7',
      'release': '14',
      'sdk': sdk,
      'kernel': '5.10.157-android13',
      'cores': 8,
      'pageSize': 4096,
    };
  }

  @override
  Future<Map<String, Object?>> memoryInfo() async =>
      {'totalBytes': 8 * 1024 * 1024 * 1024, 'availBytes': 3 * 1024 * 1024 * 1024};

  @override
  Future<Map<String, Object?>> battery() async => {
        'level': 76,
        'status': 'discharging',
        'plugged': 'none',
        'health': 'good',
        'tempC': 31.5,
        'voltageMv': 3912,
        'currentNowUa': -412000,
        'chargeCounterUah': 3400000,
      };

  @override
  Future<Map<String, Object?>> traffic() async {
    trafficTick++;
    return {
      'totalRx': 1000000 + trafficTick * 200000,
      'totalTx': 500000 + trafficTick * 20000,
      'mobileRx': 0,
      'mobileTx': 0,
    };
  }

  @override
  Future<Map<String, Object?>> thermal() async => {'status': 1, 'headroom': 0.42};

  @override
  Future<List<Map<String, Object?>>> storageVolumes() async => [
        {
          'label': 'Internal shared storage',
          'path': '/storage/emulated/0',
          'totalBytes': 128 * 1000 * 1000 * 1000,
          'freeBytes': 40 * 1000 * 1000 * 1000,
          'removable': false,
        },
      ];

  @override
  Future<bool> hasUsageAccess() async => false;
  @override
  Future<void> openUsageAccessSettings() async => calls.add('openUsageAccessSettings');
  @override
  Future<List<Map<String, Object?>>> appSizes() async => const [];
  @override
  Future<List<Map<String, Object?>>> appNetworkUsage(Duration window) async => const [];

  @override
  Future<bool> startWifiScan() async {
    calls.add('startWifiScan');
    return true;
  }

  @override
  Future<List<Map<String, Object?>>> wifiScanResults() async => lastScan;
  @override
  Stream<List<Map<String, Object?>>> wifiResults() => wifiController.stream;
  @override
  Future<Map<String, Object?>?> wifiConnection() async => connection;

  @override
  Future<bool> bluetoothEnabled() async => btEnabled;
  @override
  Stream<Map<String, Object?>> bluetoothSightings() => btController.stream;
  @override
  Future<void> startClassicDiscovery() async => calls.add('startClassicDiscovery');
  @override
  Future<List<Map<String, Object?>>> connectedBluetooth() async => connectedDevices;

  @override
  Future<bool> hasPermissions(List<String> permissions) async => permissionsGranted;
  @override
  Future<bool> requestPermissions(List<String> permissions) async {
    calls.add('requestPermissions');
    return permissionsGranted;
  }

  @override
  Future<bool> canDrawOverlays() async => false;
  @override
  Future<void> openOverlaySettings() async => calls.add('openOverlaySettings');

  @override
  Future<String> shizukuState() async => shizuku;
  @override
  Future<bool> requestShizuku() async => shizuku == 'granted';

  @override
  Future<ShellResult> shizukuExec(String command) async {
    calls.add('shizukuExec');
    final exact = shellResponses[command];
    if (exact != null) return exact;
    for (final e in shellResponses.entries) {
      if (command.startsWith(e.key)) return e.value;
    }
    return const ShellResult(1, '', 'not faked');
  }

  @override
  Future<Map<int, String>> packagesForUids(List<int> uids) async => const {};

  @override
  Future<void> startBackground(Map<String, Object?> config) async {
    calls.add('startBackground');
    startedConfig = config;
    backgroundStateValue = {'running': true, 'monitors': config['monitors']};
  }

  @override
  Future<void> stopBackground() async {
    calls.add('stopBackground');
    backgroundStateValue = const {'running': false};
  }

  @override
  Future<Map<String, Object?>> backgroundState() async => backgroundStateValue;
  @override
  Future<void> updateServiceConfig(Map<String, Object?> config) async => updatedConfig = config;
  @override
  Future<String> filesDir() async => filesDirPath;
  @override
  Future<void> notify(int id, String title, String body) async => notifications.add((id, title, body));
  @override
  Future<void> shareFile(String path, String mimeType) async => shared.add(path);
  @override
  Future<bool> saveFileAs(String path, String suggestedName, String mimeType) async => true;
  @override
  Future<bool> requestPinWidget() async => false;
  @override
  Future<void> refreshWidget() async {}
}

/// [SystemFiles] backed by a map of path to contents; missing paths are null,
/// as for a file the app is not allowed to read.
class FakeFiles implements SystemFiles {
  FakeFiles([Map<String, String>? files]) : files = files ?? {};
  final Map<String, String> files;
  final List<String> reads = [];

  @override
  Future<String?> read(String path) async {
    reads.add(path);
    return files[path];
  }
}

/// What a normal (non-elevated) app sees on Android 8+: no /proc/stat, but
/// cpufreq, meminfo and its own process.
FakeFiles normalAppFiles() => FakeFiles({
      '/proc/meminfo': meminfoSample,
      '/sys/devices/system/cpu/possible': '0-3\n',
      for (var i = 0; i < 4; i++) ...{
        '/sys/devices/system/cpu/cpu$i/cpufreq/scaling_cur_freq': '${1000000 + i * 300000}\n',
        '/sys/devices/system/cpu/cpu$i/cpufreq/cpuinfo_max_freq': '2000000\n',
      },
      '/proc/self/stat': pidStatLine(31337, 'buetow.turbomon', 'R', 40, 10, 25600),
      '/proc/self/io': 'rchar: 1000000\nwchar: 200000\nsyscr: 10\nsyscw: 5\n',
      '/sys/class/thermal/thermal_zone0/type': 'cpu-0-0-usr\n',
      '/sys/class/thermal/thermal_zone0/temp': '41200\n',
      '/sys/class/thermal/thermal_zone1/type': 'battery\n',
      '/sys/class/thermal/thermal_zone1/temp': '31000\n',
    });

/// A [PrivilegedShell] that answers from canned output, like Shizuku would.
class FakeShell implements PrivilegedShell {
  FakeShell(this.responses, {this.level = AccessLevel.shizuku});
  final Map<String, String> responses;
  @override
  final AccessLevel level;
  final List<String> commands = [];

  @override
  Future<ShellResult> run(String command) async {
    commands.add(command);
    for (final e in responses.entries) {
      if (command.startsWith(e.key)) return ShellResult(0, e.value);
    }
    return const ShellResult(1, '', 'no such file');
  }
}

/// Shell output for the combined CPU/process command the monitor runs.
String combinedCpuOutput(String stat, String ps, String pids) => "$stat@@TM@@\n$ps@@TM@@\n$pids\n";
