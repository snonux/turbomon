import 'package:flutter/material.dart';

import '../app_services.dart';
import 'bluetooth_screen.dart';
import 'io_screen.dart';
import 'power_screen.dart';
import 'settings_screen.dart';
import 'snapshot_sheet.dart';
import 'system_screen.dart';
import 'wifi_screen.dart';

/// The app frame: five monitor tabs, with the snapshot and settings actions
/// on every one of them.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.services});

  final AppServices services;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  static const _tabs = [
    (label: 'System', icon: Icons.memory_outlined, selected: Icons.memory),
    (label: 'Power', icon: Icons.bolt_outlined, selected: Icons.bolt),
    (label: 'I/O', icon: Icons.swap_vert_outlined, selected: Icons.swap_vert),
    (label: 'Wi-Fi', icon: Icons.wifi_outlined, selected: Icons.wifi),
    (
      label: 'Bluetooth',
      icon: Icons.bluetooth_outlined,
      selected: Icons.bluetooth,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final s = widget.services;
    return Scaffold(
      appBar: AppBar(
        title: Text('TurboMon · ${_tabs[_tab].label}'),
        actions: [
          ListenableBuilder(
            listenable: s.access,
            builder: (context, _) => Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Tooltip(
                message: 'Access level',
                child: Chip(
                  label: Text(s.access.level.name),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Snapshot',
            icon: const Icon(Icons.camera_alt_outlined),
            onPressed: () => showSnapshotSheet(context, s),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SettingsScreen(services: s),
              ),
            ),
          ),
        ],
      ),
      body: switch (_tab) {
        0 => SystemScreen(services: s),
        1 => PowerScreen(services: s),
        2 => IoScreen(services: s),
        3 => WifiScreen(services: s),
        _ => BluetoothScreen(services: s),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          for (final t in _tabs)
            NavigationDestination(
              icon: Icon(t.icon),
              selectedIcon: Icon(t.selected),
              label: t.label,
            ),
        ],
      ),
    );
  }
}
