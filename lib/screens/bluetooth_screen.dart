import 'package:flutter/material.dart';

import '../model/bluetooth.dart';
import '../services/app_state.dart';
import '../services/radio_controllers.dart';
import '../widgets/graphs.dart';
import '../widgets/wifi_graphs.dart' show signalColor;
import 'wifi_screen.dart' show permissionAsk;

enum _View { nearby, signal, connected }

/// Bluetooth: nearby devices from a continuous LE scan, signal over time,
/// and what is connected right now.
class BluetoothScreen extends StatefulWidget {
  const BluetoothScreen({super.key, required this.state});
  final AppState state;

  @override
  State<BluetoothScreen> createState() => _BluetoothScreenState();
}

class _BluetoothScreenState extends State<BluetoothScreen> {
  _View _view = _View.nearby;
  final Set<String> _tracked = {};
  bool? _permitted;

  BluetoothController get bt => widget.state.bluetooth;

  List<String> get _perms {
    final sdk = (widget.state.monitor.device['sdk'] as num?)?.toInt() ?? 33;
    return sdk >= 31 ? btPermissionsModern : btPermissionsLegacy;
  }

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final ok = await widget.state.bridge.hasPermissions(_perms).catchError((_) => false);
    if (mounted) setState(() => _permitted = ok);
  }

  Future<void> _ask() async {
    final ok = await widget.state.bridge.requestPermissions(_perms).catchError((_) => false);
    if (!mounted) return;
    setState(() => _permitted = ok);
    if (ok) {
      bt.stop();
      await bt.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_permitted == false) {
      return permissionAsk(
        icon: Icons.bluetooth_searching,
        text: 'Finding Bluetooth devices needs the "Nearby devices" permission '
            '(location on Android 11 and older). TurboMon never uses it to locate you.',
        onAsk: _ask,
      );
    }
    return ListenableBuilder(
      listenable: bt,
      builder: (context, _) {
        if (!bt.enabled) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Bluetooth is off. Turn it on to see nearby and connected devices.',
                  textAlign: TextAlign.center),
            ),
          );
        }
        final groups = bt.sorted;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: SegmentedButton<_View>(
                segments: const [
                  ButtonSegment(value: _View.nearby, label: Text('Nearby')),
                  ButtonSegment(value: _View.signal, label: Text('Signal')),
                  ButtonSegment(value: _View.connected, label: Text('Connected')),
                ],
                selected: {_view},
                onSelectionChanged: (s) {
                  setState(() => _view = s.first);
                  if (_view == _View.connected) bt.refreshConnected();
                },
              ),
            ),
            if (bt.error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text('Scan error: ${bt.error}', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            Expanded(
              child: switch (_view) {
                _View.nearby => _nearby(groups),
                _View.signal => _signal(groups),
                _View.connected => _connected(),
              },
            ),
          ],
        );
      },
    );
  }

  Widget _nearby(List<BtGroup> groups) {
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 0),
          child: Row(children: [
            Expanded(
              child: Text('${groups.length} devices seen in the last 2 minutes · live',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
            TextButton(onPressed: bt.classicDiscovery, child: const Text('Classic scan')),
          ]),
        ),
        if (groups.isEmpty)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Listening for devices...'))),
        for (final g in groups)
          ListTile(
            dense: true,
            leading: SizedBox(
              width: 46,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('${g.latest.rssi}',
                    style: TextStyle(color: signalColor(g.latest.rssi), fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                LinearProgressIndicator(
                  value: ((g.latest.rssi + 100) / 70).clamp(0.0, 1.0),
                  color: signalColor(g.latest.rssi),
                  minHeight: 4,
                ),
              ]),
            ),
            title: Text(g.latest.displayName),
            subtitle: Text([
              g.latest.type.toUpperCase(),
              if (g.latest.maker != null) g.latest.maker!,
              if (g.latest.bonded) 'paired',
              g.addresses.length > 1 ? '${g.addresses.length} addresses' : g.latest.address,
            ].join(' · ')),
            trailing: Checkbox(
              value: _tracked.contains(groupKey(g.latest)),
              onChanged: (v) => setState(() {
                final k = groupKey(g.latest);
                v == true ? _tracked.add(k) : _tracked.remove(k);
              }),
            ),
          ),
      ],
    );
  }

  Widget _signal(List<BtGroup> groups) {
    final keys = _tracked.isEmpty ? groups.take(5).map((g) => groupKey(g.latest)).toList() : _tracked.toList();
    final names = {for (final g in bt.devices.values) groupKey(g.latest): g.latest.displayName};
    return ListView(
      padding: const EdgeInsets.only(top: 8),
      children: [
        GraphCard(
          title: _tracked.isEmpty ? 'Signal, 5 strongest devices' : 'Signal, chosen devices',
          value: '${keys.length} lines',
          graph: LineGraph(
            capacity: 120,
            minY: -100,
            maxY: -30,
            fill: false,
            height: 220,
            series: [
              for (var i = 0; i < keys.length; i++)
                if (bt.signalHistory[keys[i]] != null)
                  GraphSeries(bt.signalHistory[keys[i]]!, color: seriesPalette[i % seriesPalette.length]),
            ],
          ),
          legend: [
            for (var i = 0; i < keys.length; i++) (names[keys[i]] ?? keys[i], seriesPalette[i % seriesPalette.length]),
          ],
          note: 'Last 2 minutes, one point per second. Walk towards a device and its line rises.',
        ),
      ],
    );
  }

  Widget _connected() {
    if (bt.connected.isEmpty) {
      return const Center(child: Text('No Bluetooth device is connected.'));
    }
    return ListView(
      children: [
        for (final d in bt.connected)
          ListTile(
            leading: const Icon(Icons.bluetooth_connected),
            title: Text(d.displayName),
            subtitle: Text([
              d.type,
              if (d.batteryPercent != null && d.batteryPercent! >= 0) 'battery ${d.batteryPercent} %',
              d.address,
            ].join(' · ')),
          ),
      ],
    );
  }
}
