import 'package:flutter/services.dart';

/// Result of a command run through Shizuku or root.
class ShellResult {
  const ShellResult(this.exitCode, this.stdout, [this.stderr = '']);
  final int exitCode;
  final String stdout;
  final String stderr;
  bool get ok => exitCode == 0;
}

/// Everything TurboMon asks Android for. The real implementation talks to
/// MainActivity over platform channels; tests use a fake.
abstract class NativeBridge {
  Future<Map<String, Object?>> deviceInfo();
  Future<Map<String, Object?>> memoryInfo();
  Future<Map<String, Object?>> battery();
  Future<Map<String, Object?>> traffic();
  Future<Map<String, Object?>> thermal();
  Future<List<Map<String, Object?>>> storageVolumes();

  Future<bool> hasUsageAccess();
  Future<void> openUsageAccessSettings();
  Future<List<Map<String, Object?>>> appSizes();
  Future<List<Map<String, Object?>>> appNetworkUsage(Duration window);

  Future<bool> startWifiScan();
  Future<List<Map<String, Object?>>> wifiScanResults();
  Stream<List<Map<String, Object?>>> wifiResults();
  Future<Map<String, Object?>?> wifiConnection();

  Future<bool> bluetoothEnabled();
  Stream<Map<String, Object?>> bluetoothSightings();
  Future<void> startClassicDiscovery();
  Future<List<Map<String, Object?>>> connectedBluetooth();

  Future<bool> hasPermissions(List<String> permissions);
  Future<bool> requestPermissions(List<String> permissions);
  Future<bool> canDrawOverlays();
  Future<void> openOverlaySettings();

  /// 'missing', 'not_running', 'denied' or 'granted'.
  Future<String> shizukuState();
  Future<bool> requestShizuku();
  Future<ShellResult> shizukuExec(String command);
  Future<Map<int, String>> packagesForUids(List<int> uids);

  Future<void> startBackground(Map<String, Object?> config);
  Future<void> stopBackground();
  Future<Map<String, Object?>> backgroundState();
  Future<void> updateServiceConfig(Map<String, Object?> config);
  Future<String> filesDir();
  Future<void> notify(int id, String title, String body);
  Future<void> shareFile(String path, String mimeType);
  Future<bool> saveFileAs(String path, String suggestedName, String mimeType);
  Future<bool> requestPinWidget();
  Future<void> refreshWidget();
}

class AndroidNativeBridge implements NativeBridge {
  static const _m = MethodChannel('org.buetow.turbomon/native');
  static const _wifi = EventChannel('org.buetow.turbomon/wifi');
  static const _bt = EventChannel('org.buetow.turbomon/bluetooth');

  Future<Map<String, Object?>> _map(String method, [Object? args]) async {
    final r = await _m.invokeMethod<Map<Object?, Object?>>(method, args);
    return (r ?? const {}).cast<String, Object?>();
  }

  Future<List<Map<String, Object?>>> _list(String method, [Object? args]) async {
    final r = await _m.invokeMethod<List<Object?>>(method, args);
    return [
      for (final e in r ?? const [])
        if (e is Map) e.cast<String, Object?>(),
    ];
  }

  @override
  Future<Map<String, Object?>> deviceInfo() => _map('deviceInfo');
  @override
  Future<Map<String, Object?>> memoryInfo() => _map('memoryInfo');
  @override
  Future<Map<String, Object?>> battery() => _map('battery');
  @override
  Future<Map<String, Object?>> traffic() => _map('traffic');
  @override
  Future<Map<String, Object?>> thermal() => _map('thermal');
  @override
  Future<List<Map<String, Object?>>> storageVolumes() => _list('storageVolumes');

  @override
  Future<bool> hasUsageAccess() async => await _m.invokeMethod<bool>('hasUsageAccess') ?? false;
  @override
  Future<void> openUsageAccessSettings() => _m.invokeMethod('openUsageAccessSettings');
  @override
  Future<List<Map<String, Object?>>> appSizes() => _list('appSizes');
  @override
  Future<List<Map<String, Object?>>> appNetworkUsage(Duration window) =>
      _list('appNetworkUsage', {'windowMs': window.inMilliseconds});

  @override
  Future<bool> startWifiScan() async => await _m.invokeMethod<bool>('startWifiScan') ?? false;
  @override
  Future<List<Map<String, Object?>>> wifiScanResults() => _list('wifiScanResults');
  @override
  Stream<List<Map<String, Object?>>> wifiResults() => _wifi.receiveBroadcastStream().map((e) => [
        for (final n in (e as List?) ?? const [])
          if (n is Map) n.cast<String, Object?>(),
      ]);
  @override
  Future<Map<String, Object?>?> wifiConnection() async {
    final r = await _m.invokeMethod<Map<Object?, Object?>>('wifiConnection');
    return r?.cast<String, Object?>();
  }

  @override
  Future<bool> bluetoothEnabled() async => await _m.invokeMethod<bool>('bluetoothEnabled') ?? false;
  @override
  Stream<Map<String, Object?>> bluetoothSightings() =>
      _bt.receiveBroadcastStream().map((e) => (e as Map).cast<String, Object?>());
  @override
  Future<void> startClassicDiscovery() => _m.invokeMethod('startClassicDiscovery');
  @override
  Future<List<Map<String, Object?>>> connectedBluetooth() => _list('connectedBluetooth');

  @override
  Future<bool> hasPermissions(List<String> permissions) async =>
      await _m.invokeMethod<bool>('hasPermissions', {'permissions': permissions}) ?? false;
  @override
  Future<bool> requestPermissions(List<String> permissions) async =>
      await _m.invokeMethod<bool>('requestPermissions', {'permissions': permissions}) ?? false;
  @override
  Future<bool> canDrawOverlays() async => await _m.invokeMethod<bool>('canDrawOverlays') ?? false;
  @override
  Future<void> openOverlaySettings() => _m.invokeMethod('openOverlaySettings');

  @override
  Future<String> shizukuState() async => await _m.invokeMethod<String>('shizukuState') ?? 'missing';
  @override
  Future<bool> requestShizuku() async => await _m.invokeMethod<bool>('requestShizuku') ?? false;
  @override
  Future<ShellResult> shizukuExec(String command) async {
    final r = await _map('shizukuExec', {'command': command});
    return ShellResult(
      (r['exitCode'] as num?)?.toInt() ?? -1,
      (r['stdout'] as String?) ?? '',
      (r['stderr'] as String?) ?? '',
    );
  }

  @override
  Future<Map<int, String>> packagesForUids(List<int> uids) async {
    final r = await _m.invokeMethod<Map<Object?, Object?>>('packagesForUids', {'uids': uids});
    return {
      for (final e in (r ?? const {}).entries)
        if (e.key is num && e.value is String) (e.key as num).toInt(): e.value as String,
    };
  }

  @override
  Future<void> startBackground(Map<String, Object?> config) =>
      _m.invokeMethod('startBackground', {'config': config});
  @override
  Future<void> stopBackground() => _m.invokeMethod('stopBackground');
  @override
  Future<Map<String, Object?>> backgroundState() => _map('backgroundState');
  @override
  Future<void> updateServiceConfig(Map<String, Object?> config) =>
      _m.invokeMethod('updateServiceConfig', {'config': config});
  @override
  Future<String> filesDir() async => await _m.invokeMethod<String>('filesDir') ?? '';
  @override
  Future<void> notify(int id, String title, String body) =>
      _m.invokeMethod('notify', {'id': id, 'title': title, 'body': body});
  @override
  Future<void> shareFile(String path, String mimeType) =>
      _m.invokeMethod('shareFile', {'path': path, 'mimeType': mimeType});
  @override
  Future<bool> saveFileAs(String path, String suggestedName, String mimeType) async =>
      await _m.invokeMethod<bool>(
          'saveFileAs', {'path': path, 'name': suggestedName, 'mimeType': mimeType}) ??
      false;
  @override
  Future<bool> requestPinWidget() async => await _m.invokeMethod<bool>('requestPinWidget') ?? false;
  @override
  Future<void> refreshWidget() => _m.invokeMethod('refreshWidget');
}
