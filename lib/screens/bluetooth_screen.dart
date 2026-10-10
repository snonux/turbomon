import 'package:flutter/material.dart';

import '../app_services.dart';
import '../models/bluetooth.dart';
import '../services/bluetooth_controller.dart';
import '../theme.dart';
import '../widgets/channel_graph.dart' show networkColor;
import '../widgets/section_card.dart';
import '../widgets/usage_graph.dart';

enum _BtView { nearby, signal, connected }

/// Nearby Bluetooth devices, their signal over time and what is connected.
/// The LE scan runs only while this tab is open.
class BluetoothScreen extends StatefulWidget {
  const BluetoothScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<BluetoothScreen> createState() => _BluetoothScreenState();
}

class _BluetoothScreenState extends State<BluetoothScreen> {
  _BtView _view = _BtView.nearby;

  BluetoothController get _bt => widget.services.bluetooth;

  @override
  void initState() {
    super.initState();
    _bt.start();
  }

  @override
  void dispose() {
    _bt.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _bt,
      builder: (context, _) {
        final problem = switch (_bt.state) {
          BluetoothScanState.needsPermission =>
            'Scanning needs the "Nearby devices" permission (location on Android 11 and older).',
          BluetoothScanState.disabled =>
            'Bluetooth is off. Turn it on to scan.',
          BluetoothScanState.unsupported => 'This device has no Bluetooth.',
          _ => null,
        };
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            SegmentedButton<_BtView>(
              segments: const [
                ButtonSegment(
                  value: _BtView.nearby,
                  label: Text('Nearby'),
                  icon: Icon(Icons.radar),
                ),
                ButtonSegment(
                  value: _BtView.signal,
                  label: Text('Signal'),
                  icon: Icon(Icons.timeline),
                ),
                ButtonSegment(
                  value: _BtView.connected,
                  label: Text('Paired'),
                  icon: Icon(Icons.headphones),
                ),
              ],
              selected: {_view},
              onSelectionChanged: (s) => setState(() => _view = s.first),
            ),
            const SizedBox(height: 8),
            if (problem != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(problem),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: () {
                          _bt.stop();
                          _bt.start();
                        },
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              )
            else
              switch (_view) {
                _BtView.nearby => _nearby(),
                _BtView.signal => _signal(),
                _BtView.connected => _paired(),
              },
          ],
        );
      },
    );
  }

  Widget _nearby() {
    final devices = _bt.devices;
    return SectionCard(
      icon: Icons.bluetooth_searching,
      title: '${devices.length} devices nearby',
      subtitle: 'Live LE scan · seen in the last minute',
      trailing: TextButton.icon(
        onPressed: _bt.discovering ? null : _bt.discover,
        icon: const Icon(Icons.search, size: 18),
        label: Text(_bt.discovering ? 'Searching…' : 'Classic'),
      ),
      child: devices.isEmpty
          ? const Hint(
              'Nothing found yet. Devices that advertise appear within seconds.',
            )
          : Column(children: [for (final d in devices) _deviceTile(d)]),
    );
  }

  Widget _deviceTile(BluetoothSighting d) {
    final rssi = d.rssi;
    final detail = [
      d.type,
      ?d.kind,
      if (d.maker != null && d.name != null) d.maker!,
      if (d.source == 'classic') 'classic',
    ].join(' · ');
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: SizedBox(
        width: 44,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            LinearProgressIndicator(
              value: rssi == null ? 0 : ((rssi + 100) / 70).clamp(0, 1),
              color: rssi == null ? null : signalColor(rssi),
            ),
            const SizedBox(height: 2),
            Text(
              rssi == null ? '–' : '$rssi',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
      title: Text(d.displayName, overflow: TextOverflow.ellipsis),
      subtitle: Text(detail),
      trailing: IconButton(
        tooltip: 'Track signal',
        icon: Icon(
          _bt.tracked.contains(d.groupKey)
              ? Icons.push_pin
              : Icons.push_pin_outlined,
        ),
        onPressed: () => _bt.toggleTracked(d.groupKey),
      ),
    );
  }

  Widget _signal() {
    final names = {for (final d in _bt.devices) d.groupKey: d.displayName};
    final tracked = [
      for (final k in _bt.tracked)
        if (_bt.signal[k] != null) k,
    ];
    if (tracked.isEmpty) {
      return const Hint(
        'Pin devices in the Nearby view to follow their signal. '
        'Walking towards a device makes its line rise.',
      );
    }
    return SectionCard(
      title: 'Signal over time (dBm)',
      subtitle: 'Pinned devices, about one point per second',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UsageGraph(
            lines: [
              for (final k in tracked)
                GraphLine(_bt.signal[k]!, color: networkColor(k), fill: false),
            ],
            minValue: -100,
            maxValue: -30,
            height: 160,
            semanticLabel: 'Bluetooth signal over time',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            children: [
              for (final k in tracked)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 10, height: 10, color: networkColor(k)),
                    const SizedBox(width: 4),
                    Text(
                      '${names[k] ?? 'out of range'} '
                      '${_bt.signal[k]!.latest?.value.round() ?? ''} dBm',
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _paired() {
    final paired = _bt.paired;
    return SectionCard(
      icon: Icons.headphones,
      title: 'Paired devices',
      subtitle: '${paired.where((p) => p.connected).length} connected',
      child: paired.isEmpty
          ? const Hint('No paired devices.')
          : Column(
              children: [
                for (final p in paired)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      p.connected
                          ? Icons.bluetooth_connected
                          : Icons.bluetooth_disabled,
                      color: p.connected ? turboOrange : null,
                    ),
                    title: Text(p.name ?? 'Unknown device'),
                    subtitle: Text(
                      p.connected
                          ? 'Connected · ${p.profiles.join(', ')}'
                          : 'Not connected${p.kind == null ? '' : ' · ${p.kind}'}',
                    ),
                  ),
              ],
            ),
    );
  }
}
