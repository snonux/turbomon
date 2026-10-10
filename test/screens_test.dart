import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:turbomon/app_services.dart';
import 'package:turbomon/main.dart';
import 'package:turbomon/models/settings.dart';
import 'package:turbomon/services/access.dart';
import 'package:turbomon/services/bluetooth_controller.dart';
import 'package:turbomon/services/monitor_hub.dart';
import 'package:turbomon/services/permissions.dart';
import 'package:turbomon/services/settings_store.dart';
import 'package:turbomon/services/storage_paths.dart';
import 'package:turbomon/services/system_reader.dart';
import 'package:turbomon/services/wifi_controller.dart';

import 'support/fake_files.dart';
import 'support/fake_platform.dart';

/// Smoke tests: every screen builds against a fake platform without
/// throwing, as a normal app with one sample taken.
void main() {
  late Directory root;
  late FakePlatform platform;
  late AppServices services;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = Directory.systemTemp.createTempSync('turbomon-ui');
    platform = FakePlatform();
    final access = AccessController(platform);
    final permissions = Permissions(platform);
    final reader = SystemReader(
      platform: platform,
      access: access,
      files: FakeFiles({
        '/proc/meminfo': File('test/fixtures/meminfo.txt').readAsStringSync(),
      }),
    );
    services = AppServices(
      platform: platform,
      settings: SettingsStore(),
      access: access,
      hub: MonitorHub(
        reader: reader,
        platform: platform,
        settings: const AppSettings(),
      ),
      wifi: WifiController(platform: platform, permissions: permissions),
      bluetooth: BluetoothController(
        platform: platform,
        permissions: permissions,
      ),
      permissions: permissions,
      paths: StoragePaths(
        support: Directory('${root.path}/support'),
        cache: Directory('${root.path}/cache'),
      ),
    );
    await services.hub.tick();
  });

  tearDown(() {
    services.hub.dispose();
    root.deleteSync(recursive: true);
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(TurboMonApp(services: services));
    await tester.pump();
  }

  testWidgets('every tab builds', (tester) async {
    await pumpApp(tester);
    expect(find.text('TurboMon · System'), findsOneWidget);
    expect(find.textContaining('RAM'), findsWidgets);

    for (final tab in ['Power', 'I/O', 'Wi-Fi', 'Bluetooth', 'System']) {
      await tester.tap(find.text(tab).last);
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('TurboMon · $tab'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: tab);
    }
  });

  testWidgets('settings and background screens build', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Refresh rate'), findsOneWidget);

    await tester.tap(find.text('Background scanning'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Background scanning'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Snapshot when it stops'), 300);
    expect(tester.takeException(), isNull);
  });

  testWidgets('snapshot sheet opens', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Snapshot'));
    await tester.pumpAndSettle();
    expect(find.text('Include Wi-Fi BSSIDs'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
  });
}
