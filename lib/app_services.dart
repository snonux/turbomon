import 'package:turbomon_platform/turbomon_platform.dart';

import 'services/access.dart';
import 'services/bluetooth_controller.dart';
import 'services/history_store.dart';
import 'services/monitor_hub.dart';
import 'services/permissions.dart';
import 'services/settings_store.dart';
import 'services/snapshot_collector.dart';
import 'services/storage_paths.dart';
import 'services/system_reader.dart';
import 'services/wifi_controller.dart';

/// The long-lived objects the UI shares, built once in `main`.
class AppServices {
  AppServices({
    required this.platform,
    required this.settings,
    required this.access,
    required this.hub,
    required this.wifi,
    required this.bluetooth,
    required this.permissions,
    required this.paths,
  });

  static Future<AppServices> create({
    TurboMonPlatform platform = const TurboMonPlatform(),
  }) async {
    final settings = await SettingsStore.load();
    final access = AccessController(platform);
    await access.resolve(settings.value.accessMode, interactive: false);
    final permissions = Permissions(platform);
    final reader = SystemReader(platform: platform, access: access);
    final services = AppServices(
      platform: platform,
      settings: settings,
      access: access,
      hub: MonitorHub(
        reader: reader,
        platform: platform,
        settings: settings.value,
      ),
      wifi: WifiController(platform: platform, permissions: permissions),
      bluetooth: BluetoothController(
        platform: platform,
        permissions: permissions,
      ),
      permissions: permissions,
      paths: await StoragePaths.resolve(),
    );
    services.hub.onAutoSnapshot = () => SnapshotCollector(services).save();
    return services;
  }

  final TurboMonPlatform platform;
  final SettingsStore settings;
  final AccessController access;
  final MonitorHub hub;
  final WifiController wifi;
  final BluetoothController bluetooth;
  final Permissions permissions;
  final StoragePaths paths;

  HistoryStore get history => HistoryStore(paths.history);
  SystemReader get reader => hub.reader;
}
