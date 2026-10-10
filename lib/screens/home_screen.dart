import 'package:flutter/material.dart';

import '../services/app_state.dart';
import 'bluetooth_screen.dart';
import 'device_screen.dart';
import 'graphs_screen.dart';
import 'overview_screen.dart';
import 'settings_screen.dart';
import 'snapshots_screen.dart';
import 'wifi_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.state, this.initialTab = 0});

  final AppState state;
  final int initialTab;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late int _tab = widget.initialTab;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _radiosFor(_tab));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // Live sampling pauses in the background; only the opt-in service runs then.
    if (s == AppLifecycleState.resumed) {
      state.monitor.start();
      _radiosFor(_tab);
      state.refreshBackground();
      state.refreshAccess();
      state.processPendingSnapshots();
    } else if (s == AppLifecycleState.paused) {
      state.monitor.stop();
      state.wifi.stop();
      state.bluetooth.stop();
    }
  }

  /// Wi-Fi and Bluetooth scan only while their tab is open.
  void _radiosFor(int tab) {
    if (tab == 3) {
      state.wifi.start();
    } else {
      state.wifi.stop();
    }
    if (tab == 4) {
      state.bluetooth.start();
    } else {
      state.bluetooth.stop();
    }
  }

  Future<void> _snapshot() async {
    final messenger = ScaffoldMessenger.of(context);
    final file = await state.takeSnapshot();
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text('Snapshot saved: ${file.uri.pathSegments.last}'),
      action: SnackBarAction(
        label: 'Share',
        onPressed: () => state.bridge.shareFile(file.path, 'text/markdown'),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      OverviewScreen(state: state),
      GraphsScreen(state: state),
      DeviceScreen(state: state),
      WifiScreen(state: state),
      BluetoothScreen(state: state),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Image.asset('logo-small.png', width: 28, height: 28),
          const SizedBox(width: 8),
          const Text('TurboMon'),
        ]),
        actions: [
          IconButton(
            tooltip: 'Take snapshot',
            icon: const Icon(Icons.photo_camera_outlined),
            onPressed: _snapshot,
          ),
          IconButton(
            tooltip: 'Snapshots',
            icon: const Icon(Icons.description_outlined),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => SnapshotsScreen(state: state))),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => SettingsScreen(state: state))),
          ),
        ],
      ),
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          setState(() => _tab = i);
          _radiosFor(i);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.speed), label: 'Top'),
          NavigationDestination(icon: Icon(Icons.show_chart), label: 'Graphs'),
          NavigationDestination(icon: Icon(Icons.battery_charging_full), label: 'Device'),
          NavigationDestination(icon: Icon(Icons.wifi), label: 'Wi-Fi'),
          NavigationDestination(icon: Icon(Icons.bluetooth), label: 'Bluetooth'),
        ],
      ),
    );
  }
}
