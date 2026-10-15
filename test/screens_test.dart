import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:turbomon/app_services.dart';
import 'package:turbomon/main.dart';
import 'package:turbomon/models/settings.dart';
import 'package:turbomon/models/readings.dart';
import 'package:turbomon/services/access.dart';
import 'package:turbomon/services/bluetooth_controller.dart';
import 'package:turbomon/services/monitor_hub.dart';
import 'package:turbomon/services/permissions.dart';
import 'package:turbomon/services/settings_store.dart';
import 'package:turbomon/services/storage_paths.dart';
import 'package:turbomon/services/system_reader.dart';
import 'package:turbomon/services/time_series.dart';
import 'package:turbomon/services/wifi_controller.dart';
import 'package:turbomon/widgets/usage_graph.dart';
import 'package:turbomon/widgets/process_table.dart';

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

  testWidgets('CPU tap still splits cores and each graph expands separately', (
    tester,
  ) async {
    services.hub.coreSeries.addAll([TimeSeries(5), TimeSeries(5)]);
    await pumpApp(tester);
    final cpu = find.byWidgetPredicate(
      (widget) =>
          widget is UsageGraph && widget.semanticLabel == 'CPU clock graph',
    );
    await tester.ensureVisible(cpu);
    await tester.tapAt(tester.getTopLeft(cpu) + const Offset(30, 30));
    await tester.pump();
    expect(find.byTooltip('Expand cpu0 graph'), findsOneWidget);
    expect(find.byTooltip('Expand cpu1 graph'), findsOneWidget);

    await tester.tap(find.byTooltip('Expand cpu0 graph'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'cpu0 graph'), findsOneWidget);
    expect(
      tester.widget<UsageGraph>(find.byType(UsageGraph)).lines.single.series,
      same(services.hub.coreSeries.first),
    );
    await tester.tap(find.byTooltip('Close chart'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Expand cpu0 graph'), findsOneWidget);
    expect(cpu, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('snapshot sheet opens', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Snapshot'));
    await tester.pumpAndSettle();
    expect(find.text('Include Wi-Fi BSSIDs'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
  });

  testWidgets(
    'privileged process card searches beyond the former preview cap',
    (tester) async {
      platform.shizuku = const {'running': true, 'granted': true};
      await services.access.resolve(AccessMode.shizuku);
      services.hub.processes = [
        for (var i = 0; i < 70; i++)
          ProcessInfo(
            pid: 1000 + i,
            user: 'shell',
            name: 'process.$i',
            cpuPercent: (70 - i).toDouble(),
            rssBytes: 1024,
            state: 'S',
          ),
      ];
      await pumpApp(tester);
      final search = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Search processes',
      );
      await tester.ensureVisible(search);
      await tester.enterText(search, 'process.69');
      await tester.pumpAndSettle();
      expect(find.text('1 of 70 processes'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DataTable),
          matching: find.text('process.69'),
        ),
        findsOneWidget,
      );
      // Empty output from one failed top call must not clear the controls.
      final saved = services.hub.processes;
      services.hub.processes = [];
      services.hub.applySettings(const AppSettings());
      await tester.pump();
      expect(tester.widget<TextField>(search).controller!.text, 'process.69');
      expect(find.text('No process readings available yet.'), findsOneWidget);
      services.hub.processes = saved;
      services.hub.applySettings(const AppSettings());
      await tester.pump();
      expect(find.text('1 of 70 processes'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('process controls survive scrolling beyond the viewport cache', (
    tester,
  ) async {
    platform.shizuku = const {'running': true, 'granted': true};
    await services.access.resolve(AccessMode.shizuku);
    services.hub.processes = const [
      ProcessInfo(
        pid: 1000,
        user: 'system',
        name: 'system_server',
        cpuPercent: 20,
        rssBytes: 1024,
        state: 'S',
      ),
    ];
    // A short viewport places the process card beyond the cache at the top.
    await pumpApp(tester);
    tester.view.physicalSize = const Size(1080, 1000);
    await tester.pump();
    final search = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'Search processes',
    );
    await tester.scrollUntilVisible(
      search,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(search, 'system');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    final original = tester.state(find.byType(ProcessTable));
    final list = tester.state<ScrollableState>(find.byType(Scrollable).first);
    final processOffset =
        list.position.pixels +
        tester.getTopLeft(find.byType(ProcessTable)).dy -
        tester.getTopLeft(find.byType(Scrollable).first).dy;
    expect(processOffset, greaterThan(list.position.viewportDimension + 250));
    list.position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      search,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(ProcessTable)), same(original));
    expect(tester.widget<TextField>(search).controller!.text, 'system');
    expect(tester.takeException(), isNull);
  });
}
