import 'package:flutter/material.dart';

import '../parsers/wifi_channels.dart';
import '../services/app_state.dart';
import '../services/radio_controllers.dart';
import '../widgets/graphs.dart';
import '../widgets/wifi_graphs.dart';

enum _View { list, channels, signal }

/// Wi-Fi analysis: every network in range, channel graphs per band, and
/// signal over time, all updating live.
class WifiScreen extends StatefulWidget {
  const WifiScreen({super.key, required this.state});
  final AppState state;

  @override
  State<WifiScreen> createState() => _WifiScreenState();
}

class _WifiScreenState extends State<WifiScreen> {
  _View _view = _View.list;
  WifiBand _band = WifiBand.ghz24;
  final Set<String> _tracked = {};
  bool? _permitted;

  WifiController get wifi => widget.state.wifi;

  List<String> get _perms {
    final sdk = (widget.state.monitor.device['sdk'] as num?)?.toInt() ?? 33;
    return sdk >= 33 ? wifiPermissionsModern : wifiPermissionsLegacy;
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
      wifi.stop();
      await wifi.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_permitted == false) {
      return _PermissionAsk(
        icon: Icons.wifi_find,
        text: 'Scanning for Wi-Fi networks needs the "Nearby devices" permission '
            '(location on Android 12 and older). TurboMon never uses it to locate you.',
        onAsk: _ask,
      );
    }
    return ListenableBuilder(
      listenable: wifi,
      builder: (context, _) {
        final theme = Theme.of(context);
        final conn = wifi.connection;
        final last = wifi.lastResults;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: SegmentedButton<_View>(
                segments: const [
                  ButtonSegment(value: _View.list, label: Text('Networks')),
                  ButtonSegment(value: _View.channels, label: Text('Channels')),
                  ButtonSegment(value: _View.signal, label: Text('Signal')),
                ],
                selected: {_view},
                onSelectionChanged: (s) => setState(() => _view = s.first),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Row(children: [
                Expanded(
                  child: Text(
                    '${wifi.networks.length} networks'
                    '${last == null ? '' : ' · updated ${DateTime.now().difference(last).inSeconds} s ago'}'
                    ' · ${wifi.throttlingOff ? 'scanning every 5 s' : 'scanning every ${wifi.scanInterval.inSeconds} s'}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Scan now',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.refresh),
                  onPressed: wifi.scanNow,
                ),
              ]),
            ),
            if (conn != null && conn['ssid'] != null)
              Card(
                margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.wifi, color: signalColor((conn['rssi'] as num?) ?? -100)),
                  title: Text('Connected: ${conn['ssid']}'),
                  subtitle: Text('${conn['rssi']} dBm · ${conn['linkSpeedMbps'] ?? '?'} Mbps · '
                      '${conn['frequency'] ?? '?'} MHz'),
                  trailing: SizedBox(
                    width: 90,
                    child: LineGraph(
                      capacity: 60,
                      height: 30,
                      minY: -100,
                      maxY: -30,
                      formatY: (_) => '',
                      series: [GraphSeries(wifi.connectedSignal, color: theme.colorScheme.primary)],
                    ),
                  ),
                ),
              ),
            Expanded(
              child: switch (_view) {
                _View.list => _list(),
                _View.channels => _channels(),
                _View.signal => _signal(),
              },
            ),
          ],
        );
      },
    );
  }

  Widget _list() {
    if (wifi.networks.isEmpty) {
      return const Center(child: Text('Waiting for scan results...'));
    }
    return ListView.builder(
      itemCount: wifi.networks.length,
      itemBuilder: (context, i) {
        final n = wifi.networks[i];
        final unit = ((n.rssi + 100) / 70).clamp(0.0, 1.0);
        return ListTile(
          dense: true,
          leading: SizedBox(
            width: 46,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('${n.rssi}', style: TextStyle(color: signalColor(n.rssi), fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              LinearProgressIndicator(value: unit, color: signalColor(n.rssi), minHeight: 4),
            ]),
          ),
          title: Text(n.displayName),
          subtitle: Text('ch ${n.channel ?? '?'} · ${n.band?.label ?? '?'} · ${n.channelWidthMhz} MHz'
              '${n.standard.isEmpty ? '' : ' · ${n.standard}'}\n${n.security.isEmpty ? 'open' : n.security} · ${n.bssid}'),
          isThreeLine: true,
          trailing: Checkbox(
            value: _tracked.contains(n.bssid),
            onChanged: (v) => setState(() => v == true ? _tracked.add(n.bssid) : _tracked.remove(n.bssid)),
          ),
        );
      },
    );
  }

  Widget _channels() {
    final nets = wifi.networks.where((n) => n.band == _band).toList();
    final suggested = suggestedChannel(_band, nets);
    final rows = [for (final w in wifi.waterfall) w.$2[_band] ?? const <int, int>{}];
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      children: [
        SegmentedButton<WifiBand>(
          segments: [
            for (final b in WifiBand.values) ButtonSegment(value: b, label: Text(b.label)),
          ],
          selected: {_band},
          onSelectionChanged: (s) => setState(() => _band = s.first),
        ),
        const SizedBox(height: 8),
        Text('${nets.length} networks on ${_band.label}', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        ChannelGraph(band: _band, networks: nets),
        if (_band == WifiBand.ghz5)
          Text('Shaded channels are DFS (radar detection).', style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 12),
        Text('Strongest signal and networks per channel · suggested: $suggested',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        ChannelBars(band: _band, networks: nets),
        const SizedBox(height: 12),
        Text('Waterfall: strongest signal per channel, newest scan at the bottom',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        if (rows.isEmpty) const Text('Builds up as scans arrive.') else ChannelWaterfall(band: _band, rows: rows),
      ],
    );
  }

  Widget _signal() {
    final tracked = _tracked.isEmpty
        ? wifi.networks.take(5).map((n) => n.bssid).toList()
        : _tracked.toList();
    final names = {for (final n in wifi.networks) n.bssid: n.displayName};
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      children: [
        GraphCard(
          title: _tracked.isEmpty ? 'Signal, 5 strongest networks' : 'Signal, chosen networks',
          value: '${tracked.length} lines',
          graph: LineGraph(
            capacity: wifi.historyLength,
            minY: -100,
            maxY: -30,
            fill: false,
            height: 200,
            series: [
              for (var i = 0; i < tracked.length; i++)
                if (wifi.signalHistory[tracked[i]] != null)
                  GraphSeries(wifi.signalHistory[tracked[i]]!, color: seriesPalette[i % seriesPalette.length]),
            ],
          ),
          legend: [
            for (var i = 0; i < tracked.length; i++)
              (names[tracked[i]] ?? tracked[i], seriesPalette[i % seriesPalette.length]),
          ],
          note: 'One point per scan. Tick networks in the Networks list to choose which are drawn.',
        ),
        if (!wifi.throttlingOff)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Android allows 4 scans per 2 minutes. Turn off "Wi-Fi scan throttling" in developer '
              'options and TurboMon scans every 5 s.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: OutlinedButton(
            onPressed: wifi.tryFastScanning,
            child: const Text('I turned throttling off, scan faster'),
          ),
        ),
      ],
    );
  }
}

class _PermissionAsk extends StatelessWidget {
  const _PermissionAsk({required this.icon, required this.text, required this.onAsk});
  final IconData icon;
  final String text;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 48),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onAsk, child: const Text('Allow')),
          ]),
        ),
      );
}

/// Shared with the Bluetooth screen.
Widget permissionAsk({required IconData icon, required String text, required VoidCallback onAsk}) =>
    _PermissionAsk(icon: icon, text: text, onAsk: onAsk);
