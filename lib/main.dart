import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'platform/native_bridge.dart';
import 'screens/home_screen.dart';
import 'services/app_state.dart';
import 'services/app_version.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = SettingsStore();
  final settings = await store.load();
  String version;
  try {
    version = await loadAppVersion(rootBundle);
  } on Object {
    version = '?';
  }
  final state = AppState(
    bridge: AndroidNativeBridge(),
    store: store,
    settings: settings,
    appVersion: version,
  );
  runApp(TurboMonApp(state: state));
  await state.init();
}

const turboBlue = Color(0xFF0B2545);
const turboOrange = Color(0xFFFF8C1A);

class TurboMonApp extends StatelessWidget {
  const TurboMonApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: turboBlue,
            secondary: turboOrange,
            brightness: b,
          ),
          useMaterial3: true,
        );
    return MaterialApp(
      title: 'TurboMon',
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: HomeScreen(state: state),
    );
  }
}
