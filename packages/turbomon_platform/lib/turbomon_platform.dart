/// Dart side of TurboMon's Android plugin.
///
/// Each method maps one-to-one onto a call in `TurboMonPlatformPlugin.kt` and
/// returns plain maps and lists; the app turns them into typed models. Tests
/// substitute a fake by implementing [TurboMonPlatform].
library;

import 'package:flutter/services.dart';

typedef JsonMap = Map<String, Object?>;

class TurboMonPlatform {
  const TurboMonPlatform();

  static const MethodChannel _channel = MethodChannel(
    'org.buetow.turbomon/platform',
  );
  static const EventChannel _wifiEvents = EventChannel(
    'org.buetow.turbomon/wifi',
  );
  static const EventChannel _bluetoothEvents = EventChannel(
    'org.buetow.turbomon/bluetooth',
  );

  Future<JsonMap> device() => _map('device');
  Future<JsonMap> memory() => _map('memory');
  Future<JsonMap> battery() => _map('battery');
  Future<JsonMap> thermal() => _map('thermal');
  Future<JsonMap> traffic() => _map('traffic');
  Future<List<JsonMap>> storageVolumes() => _list('storageVolumes');

  Future<bool> hasUsageAccess() => _bool('hasUsageAccess');
  Future<bool> openUsageAccessSettings() => _bool('openUsageAccessSettings');
  Future<List<JsonMap>> appStorage() => _list('appStorage');
  Future<List<JsonMap>> appNetwork(DateTime since) =>
      _list('appNetwork', {'sinceMs': since.millisecondsSinceEpoch});
  Future<Map<int, String>> packagesForUids(List<int> uids) async {
    final raw = await _channel.invokeMapMethod<String, String>(
      'packagesForUids',
      {'uids': uids},
    );
    return {
      for (final e in (raw ?? const {}).entries) int.parse(e.key): e.value,
    };
  }

  Future<bool> wifiEnabled() => _bool('wifiEnabled');

  /// False when Android rejected the scan (throttled, or Wi-Fi is off).
  Future<bool> wifiStartScan() => _bool('wifiStartScan');
  Future<List<JsonMap>> wifiScanResults() => _list('wifiScanResults');
  Future<JsonMap?> wifiConnection() async {
    final raw = await _channel.invokeMethod<Object?>('wifiConnection');
    return raw == null ? null : _asMap(raw);
  }

  /// `{type: scan|link}` whenever results or the connected link change.
  Stream<JsonMap> wifiEvents() =>
      _wifiEvents.receiveBroadcastStream().map(_asMap);

  Future<JsonMap> bluetoothState() => _map('bluetoothState');
  Future<List<JsonMap>> bluetoothPaired() => _list('bluetoothPaired');
  Future<bool> bluetoothDiscover() => _bool('bluetoothDiscover');

  /// A running LE scan while listened to: `{type: devices, devices: [...]}`
  /// about once a second, or `{type: error, code: n}`.
  Stream<JsonMap> bluetoothScan() =>
      _bluetoothEvents.receiveBroadcastStream().map(_asMap);

  Future<Map<String, bool>> permissionStatus(List<String> permissions) =>
      _permissions('permissionStatus', permissions);
  Future<Map<String, bool>> requestPermissions(List<String> permissions) =>
      _permissions('requestPermissions', permissions);
  Future<bool> canDrawOverlays() => _bool('canDrawOverlays');
  Future<bool> openOverlaySettings() => _bool('openOverlaySettings');

  Future<JsonMap> shizukuStatus() => _map('shizukuStatus');
  Future<bool> shizukuRequestPermission() => _bool('shizukuRequestPermission');
  Future<String> shizukuExec(String script) async =>
      await _channel.invokeMethod<String>('shizukuExec', {'script': script}) ??
      '';

  Future<void> startService(String config) =>
      _channel.invokeMethod<void>('startService', {'config': config});
  Future<void> stopService() => _channel.invokeMethod<void>('stopService');
  Future<bool> serviceRunning() => _bool('serviceRunning');

  /// The configuration the service was last started with, as JSON.
  Future<String?> serviceConfig() =>
      _channel.invokeMethod<String>('serviceConfig');
  Future<void> serviceStatus(String text) =>
      _channel.invokeMethod<void>('serviceStatus', {'text': text});

  /// Shows [text] in the floating overlay, or hides it when null.
  Future<void> overlay(String? text) =>
      _channel.invokeMethod<void>('overlay', {'text': text});
  Future<void> updateWidget(Map<String, String> values) =>
      _channel.invokeMethod<void>('updateWidget', {'values': values});
  Future<void> notify(int id, String title, String text) => _channel
      .invokeMethod<void>('notify', {'id': id, 'title': title, 'text': text});

  Future<bool> shareFile(String path, String mime) =>
      _bool('shareFile', {'path': path, 'mime': mime});

  /// Asks the user where to save [content]; false when they cancel.
  Future<bool> saveFile(String name, String content) =>
      _bool('saveFile', {'name': name, 'content': content});

  Future<JsonMap> _map(String method, [Object? args]) async {
    final raw = await _channel.invokeMethod<Object?>(method, args);
    return raw == null ? const {} : _asMap(raw);
  }

  Future<List<JsonMap>> _list(String method, [Object? args]) async {
    final raw = await _channel.invokeListMethod<Object?>(method, args);
    return [for (final e in raw ?? const []) _asMap(e)];
  }

  Future<bool> _bool(String method, [Object? args]) async =>
      await _channel.invokeMethod<bool>(method, args) ?? false;

  Future<Map<String, bool>> _permissions(
    String method,
    List<String> permissions,
  ) async =>
      await _channel.invokeMapMethod<String, bool>(method, {
        'permissions': permissions,
      }) ??
      const {};

  static JsonMap _asMap(Object? raw) =>
      (raw as Map).map((key, value) => MapEntry(key as String, _deep(value)));

  static Object? _deep(Object? value) => switch (value) {
    Map() => _asMap(value),
    List() => value.map(_deep).toList(),
    _ => value,
  };
}
