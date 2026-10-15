import 'package:flutter/material.dart';

import '../app_services.dart';
import '../models/wifi.dart';
import '../services/format.dart';
import '../services/wifi_analysis.dart';
import '../services/wifi_controller.dart';
import '../theme.dart';
import '../widgets/channel_graph.dart';
import '../widgets/expandable_chart.dart';
import '../widgets/section_card.dart';
import '../widgets/usage_graph.dart';

enum _WifiView { list, channels, signal }

/// Wi-Fi analysis: every network in range, channel graphs per band and
/// signal over time. Scanning runs only while this tab is open.
class WifiScreen extends StatefulWidget {
  const WifiScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<WifiScreen> createState() => _WifiScreenState();
}

class _WifiScreenState extends State<WifiScreen> {
  _WifiView _view = _WifiView.list;
  WifiBand _band = WifiBand.ghz24;

  WifiController get _wifi => widget.services.wifi;

  @override
  void initState() {
    super.initState();
    _wifi.start();
  }

  @override
  void dispose() {
    _wifi.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _wifi,
      builder: (context, _) {
        final blocked = switch (_wifi.state) {
          WifiState.needsPermission => _blocked(
            'Scanning needs the location permission, with location '
            'turned on. Android only shares scan results with it; '
            'TurboMon never reads where you are.',
          ),
          WifiState.disabled => _blocked('Wi-Fi is off. Turn it on to scan.'),
          _ => null,
        };
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _linkCard(),
            SegmentedButton<_WifiView>(
              segments: const [
                ButtonSegment(
                  value: _WifiView.list,
                  label: Text('Networks'),
                  icon: Icon(Icons.list),
                ),
                ButtonSegment(
                  value: _WifiView.channels,
                  label: Text('Channels'),
                  icon: Icon(Icons.bar_chart),
                ),
                ButtonSegment(
                  value: _WifiView.signal,
                  label: Text('Signal'),
                  icon: Icon(Icons.timeline),
                ),
              ],
              selected: {_view},
              onSelectionChanged: (s) => setState(() => _view = s.first),
            ),
            const SizedBox(height: 8),
            ?blocked,
            if (blocked == null)
              switch (_view) {
                _WifiView.list => _list(),
                _WifiView.channels => _channels(),
                _WifiView.signal => _signal(),
              },
          ],
        );
      },
    );
  }

  Widget _blocked(String text) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () {
              _wifi.stop();
              _wifi.start();
            },
            child: const Text('Try again'),
          ),
        ],
      ),
    ),
  );

  Widget _linkCard() {
    final link = _wifi.link;
    final scanAge = _wifi.lastResults == null
        ? 'waiting for the first scan'
        : 'last results ${formatTime(_wifi.lastResults!)}';
    final throttle = switch (_wifi.throttleOff) {
      true => 'throttling off, scanning every 5 s',
      false => 'scans throttled by Android, every 30 s',
      null => 'scanning',
    };
    return SectionCard(
      icon: Icons.wifi,
      title: link == null
          ? 'Not connected'
          : (link.ssid ?? 'Connected network'),
      subtitle: '$scanAge · $throttle',
      trailing: link == null
          ? null
          : Text(
              '${link.rssi} dBm',
              style: TextStyle(color: signalColor(link.rssi)),
            ),
      child: link == null
          ? const SizedBox.shrink()
          : Column(
              children: [
                StatRow(
                  'Link speed',
                  link.linkMbps == null ? '–' : '${link.linkMbps} Mbps',
                ),
                if (link.frequency != null)
                  StatRow(
                    'Channel',
                    '${WifiBand.ofFrequency(link.frequency!)?.channelOf(link.frequency!) ?? '?'} '
                        '(${link.frequency} MHz)',
                  ),
                StatRow(
                  'Networks on the same channel',
                  '${coChannelNeighbours(link, _wifi.networks)}',
                ),
                const SizedBox(height: 6),
                LiveUsageGraph(
                  listenable: _wifi,
                  linesBuilder: () => [
                    GraphLine(
                      _wifi.linkSignal,
                      color: signalColor(_wifi.link?.rssi ?? -100),
                    ),
                  ],
                  minValue: -100,
                  maxValue: -30,
                  height: 48,
                  semanticLabel: 'Connected signal graph',
                ),
              ],
            ),
    );
  }

  Widget _list() {
    final networks = _wifi.networks;
    if (networks.isEmpty) return const Hint('No networks in range yet.');
    return Card(
      child: Column(
        children: [
          for (final n in networks)
            ListTile(
              dense: true,
              leading: SizedBox(
                width: 44,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    LinearProgressIndicator(
                      value: n.strength,
                      color: signalColor(n.rssi),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${n.rssi}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              title: Text(n.displayName, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${n.band?.label ?? '?'} · ch ${n.channel ?? '?'} · ${n.channelWidth} MHz · '
                '${n.security}${n.standardName == null ? '' : ' · ${n.standardName}'}',
              ),
              trailing: IconButton(
                tooltip: 'Track signal',
                icon: Icon(
                  _wifi.tracked.contains(n.bssid)
                      ? Icons.push_pin
                      : Icons.push_pin_outlined,
                ),
                onPressed: () => _wifi.toggleTracked(n.bssid),
              ),
            ),
        ],
      ),
    );
  }

  Widget _channels() {
    final analyses = {
      for (final b in WifiBand.values) b: analyseBand(b, _wifi.networks),
    };
    final a = analyses[_band]!;
    final band = _band;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final b in WifiBand.values)
              ChoiceChip(
                label: Text('${b.label} (${analyses[b]!.networks.length})'),
                selected: _band == b,
                onSelected: (_) => setState(() => _band = b),
              ),
          ],
        ),
        SectionCard(
          title: 'Channel graph · ${_band.label}',
          subtitle: a.recommended == null
              ? 'No networks on this band'
              : 'Least crowded: channel ${a.recommended}'
                    '${_band == WifiBand.ghz5 ? ' · DFS channels shaded' : ''}',
          child: ExpandableChart(
            title: 'Channel graph · ${band.label}',
            listenable: _wifi,
            height: 220,
            builder: (context, size, expanded) => ChannelGraph(
              analysis: analyseBand(band, _wifi.networks),
              height: size.height,
            ),
          ),
        ),
        SectionCard(
          title: 'Strongest signal and networks per channel',
          child: ExpandableChart(
            title: 'Channel signal and count · ${band.label}',
            listenable: _wifi,
            height: 90,
            builder: (context, size, expanded) => ChannelBars(
              analysis: analyseBand(band, _wifi.networks),
              height: size.height,
              scrollable: !expanded,
            ),
          ),
        ),
        SectionCard(
          title: 'Waterfall',
          subtitle: 'Last ${_wifi.history.length} scans, newest on top',
          child: ExpandableChart(
            title: 'Waterfall · ${band.label}',
            listenable: _wifi,
            height: 8.0 * _wifi.history.length.clamp(6, 30),
            builder: (context, size, expanded) => ChannelWaterfall(
              band: band,
              history: _wifi.history,
              height: size.height,
            ),
          ),
        ),
      ],
    );
  }

  Widget _signal() {
    final byBssid = {for (final n in _wifi.networks) n.bssid: n};
    final tracked = [
      for (final b in _wifi.tracked)
        if (_wifi.signal[b] != null) b,
    ];
    if (tracked.isEmpty) {
      return const Hint(
        'Pin networks in the Networks view to follow their signal.',
      );
    }
    return SectionCard(
      title: 'Signal over time (dBm)',
      subtitle: 'Pinned networks; updates with each scan',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LiveUsageGraph(
            listenable: _wifi,
            linesBuilder: () => [
              for (final b in _wifi.tracked)
                if (_wifi.signal[b] != null)
                  GraphLine(
                    _wifi.signal[b]!,
                    label:
                        _wifi.networks
                            .where((n) => n.bssid == b)
                            .firstOrNull
                            ?.displayName ??
                        b,
                    color: networkColor(b),
                    fill: false,
                  ),
            ],
            minValue: -100,
            maxValue: -30,
            height: 160,
            semanticLabel: 'Wi-Fi signal over time',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            children: [
              for (final b in tracked)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 10, height: 10, color: networkColor(b)),
                    const SizedBox(width: 4),
                    Text(
                      '${byBssid[b]?.displayName ?? 'out of range'} '
                      '${_wifi.signal[b]!.latest?.value.round() ?? ''} dBm',
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
