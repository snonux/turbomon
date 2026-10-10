import 'package:turbomon_platform/turbomon_platform.dart';

/// Runtime permissions per feature, which differ by Android version. Each is
/// requested when its feature is first used, never at install.
class Permissions {
  Permissions(this.platform);

  final TurboMonPlatform platform;
  int? _sdk;

  static const fineLocation = 'android.permission.ACCESS_FINE_LOCATION';
  static const nearbyWifi = 'android.permission.NEARBY_WIFI_DEVICES';
  static const bluetoothScan = 'android.permission.BLUETOOTH_SCAN';
  static const bluetoothConnect = 'android.permission.BLUETOOTH_CONNECT';
  static const notifications = 'android.permission.POST_NOTIFICATIONS';

  Future<int> sdk() async =>
      _sdk ??= (await platform.device())['sdk'] as int? ?? 0;

  /// Wi-Fi scan results still need fine location (and location turned on)
  /// on every Android version; 13+ also asks for NEARBY_WIFI_DEVICES.
  Future<List<String>> wifi() async => await sdk() >= 33
      ? const [nearbyWifi, fineLocation]
      : const [fineLocation];

  Future<List<String>> bluetooth() async => await sdk() >= 31
      ? const [bluetoothScan, bluetoothConnect]
      : const [fineLocation];

  Future<List<String>> notification() async =>
      await sdk() >= 33 ? const [notifications] : const [];

  /// Requests [permissions]; true when all of them are granted.
  Future<bool> ensure(List<String> permissions) async {
    if (permissions.isEmpty) return true;
    final status = await platform.permissionStatus(permissions);
    if (permissions.every((p) => status[p] == true)) return true;
    final result = await platform.requestPermissions(permissions);
    return permissions.every((p) => result[p] == true);
  }
}
