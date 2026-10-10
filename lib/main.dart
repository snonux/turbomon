import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:turbomon_platform/turbomon_platform.dart';

import 'app_services.dart';
import 'background/background_runner.dart';
import 'models/settings.dart';
import 'screens/home_shell.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await AppServices.create();
  services.hub.start();
  // Settings changes reach the live sampler at once.
  services.settings.addListener(
    () => services.hub.applySettings(services.settings.value),
  );
  runApp(TurboMonApp(services: services));
}

/// Entry point of the background service's headless Flutter engine, started
/// by MonitorService.kt; the name must match its BACKGROUND_ENTRYPOINT.
@pragma('vm:entry-point')
Future<void> backgroundMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  const platform = TurboMonPlatform();
  final raw = await platform.serviceConfig();
  if (raw == null) {
    await platform.stopService();
    return;
  }
  final config = BackgroundConfig.fromJson(
    (jsonDecode(raw) as Map).cast<String, Object?>(),
  );
  final runner = await createBackgroundRunner(platform, config);
  platform.onStopRequested(() => runner.stop('Stopped by you.'));
  await runner.start();
}

class TurboMonApp extends StatelessWidget {
  const TurboMonApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TurboMon',
      theme: turboTheme(Brightness.light),
      darkTheme: turboTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: HomeShell(services: services),
    );
  }
}
