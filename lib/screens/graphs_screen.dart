import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../model/readings.dart';
import '../model/ring_buffer.dart';
import '../services/app_state.dart';
import '../services/history.dart';
import '../widgets/graphs.dart';

/// Live scrolling usage graphs, and the background history.
class GraphsScreen extends StatefulWidget {
  const GraphsScreen({super.key, required this.state});
  final AppState state;

  @override
  State<GraphsScreen> createState() => _GraphsScreenState();
}

class _GraphsScreenState extends State<GraphsScreen> {
  bool _history = false;
  bool _perCore = false;
  Duration _range = const Duration(hours: 8);
  Future<List<HistorySample>>? _historyLoad;

  void _loadHistory() {
    final now = DateTime.now();
    setState(() {
      _historyLoad = widget.state.filesDir().then(
          (dir) => HistoryReader(p.join(dir, 'history')).read(now.subtract(_range), now));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Live'), icon: Icon(Icons.timeline)),
              ButtonSegment(value: true, label: Text('History'), icon: Icon(Icons.history)),
            ],
            selected: {_history},
            onSelectionChanged: (s) {
              setState(() => _history = s.first);
              if (_history) _loadHistory();
            },
          ),
        ),
        Expanded(child: _history ? _historyView() : _liveView()),
      ],
    );
  }

  Widget _liveView() {
    final m = widget.state.monitor;
    return ListenableBuilder(
      listenable: m,
      builder: (context, _) {
        final cap = m.settings.graphCapacity;
        final window = '${m.settings.graphWindowMinutes} min';
        String pct(double? v) => v == null ? 'n/a' : '${v.toStringAsFixed(0)} %';
        return ListView(
          padding: const EdgeInsets.only(bottom: 16, top: 4),
          children: [
            GraphCard(
              title: m.cpuIsProxy ? 'CPU frequency (% of max)' : 'CPU',
              value: pct(m.cpu.last),
              onTap: () => setState(() => _perCore = !_perCore),
              graph: LineGraph(
                capacity: cap,
                maxY: 100,
                fill: !_perCore,
                series: _perCore
                    ? [
                        for (var i = 0; i < m.cores.length; i++)
                          GraphSeries(m.cores[i], color: seriesPalette[i % seriesPalette.length]),
                      ]
                    : [GraphSeries(m.cpu, colorByLoad: true)],
              ),
              legend: _perCore
                  ? [for (var i = 0; i < m.cores.length; i++) ('cpu$i', seriesPalette[i % seriesPalette.length])]
                  : const [],
              note: '${_perCore ? 'Per core' : 'Total'}, last $window. Tap to ${_perCore ? 'combine' : 'split per core'}.'
                  '${m.cpuIsProxy ? ' Real CPU % needs Shizuku or root.' : ''}',
            ),
            GraphCard(
              title: 'RAM used',
              value: pct(m.ram.last),
              graph: LineGraph(capacity: cap, maxY: 100, series: [GraphSeries(m.ram, colorByLoad: true)]),
            ),
            if (m.gpuAvailable)
              GraphCard(
                title: 'GPU',
                value: pct(m.gpu.last),
                graph: LineGraph(capacity: cap, maxY: 100, series: [GraphSeries(m.gpu, colorByLoad: true)]),
              ),
            GraphCard(
              title: 'Battery power',
              value: m.batteryPower.last == null
                  ? 'n/a'
                  : '${m.batteryPower.last!.toStringAsFixed(2)} W'
                      '${m.battery?.charging == true ? ' in' : ' out'}',
              graph: LineGraph(
                capacity: cap,
                series: [GraphSeries(m.batteryPower, color: const Color(0xFFE0A100))],
                formatY: (v) => v.toStringAsFixed(1),
              ),
              note: m.batteryDrain.last == null
                  ? null
                  : 'Drain ${m.batteryDrain.last!.toStringAsFixed(0)} mA, avg ${m.batteryDrain.average?.toStringAsFixed(0) ?? '-'} mA',
            ),
            GraphCard(
              title: 'Network',
              value: '↓${formatRate(m.rxBps ?? 0)} ↑${formatRate(m.txBps ?? 0)}',
              graph: LineGraph(
                capacity: cap,
                fill: false,
                series: [
                  GraphSeries(m.netRx, color: seriesPalette[0]),
                  GraphSeries(m.netTx, color: seriesPalette[1]),
                ],
                formatY: (v) => formatBytes(v, digits: 0),
              ),
              legend: [('Download', seriesPalette[0]), ('Upload', seriesPalette[1])],
            ),
            GraphCard(
              title: 'Temperatures',
              value: m.hottest.last == null ? 'n/a' : '${m.hottest.last!.toStringAsFixed(1)} °C',
              graph: LineGraph(
                capacity: cap,
                minY: 20,
                fill: false,
                series: [
                  GraphSeries(m.hottest, color: seriesPalette[3]),
                  GraphSeries(m.batteryTemp, color: seriesPalette[2]),
                ],
              ),
              legend: [('Hottest sensor', seriesPalette[3]), ('Battery', seriesPalette[2])],
            ),
            if (m.diskIoAvailable)
              GraphCard(
                title: 'Disk I/O',
                value: 'R ${formatRate(m.diskRead.last ?? 0)} W ${formatRate(m.diskWrite.last ?? 0)}',
                graph: LineGraph(
                  capacity: cap,
                  fill: false,
                  series: [
                    GraphSeries(m.diskRead, color: seriesPalette[5]),
                    GraphSeries(m.diskWrite, color: seriesPalette[4]),
                  ],
                  formatY: (v) => formatBytes(v, digits: 0),
                ),
                legend: [('Read', seriesPalette[5]), ('Write', seriesPalette[4])],
              ),
          ],
        );
      },
    );
  }

  Widget _historyView() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Wrap(spacing: 6, children: [
            for (final (label, d) in const [
              ('1 h', Duration(hours: 1)),
              ('8 h', Duration(hours: 8)),
              ('24 h', Duration(hours: 24)),
              ('7 days', Duration(days: 7)),
            ])
              ChoiceChip(
                label: Text(label),
                selected: _range == d,
                onSelected: (_) {
                  _range = d;
                  _loadHistory();
                },
              ),
          ]),
        ),
        Expanded(
          child: FutureBuilder<List<HistorySample>>(
            future: _historyLoad,
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final h = snap.data!.where((s) => s.event == null).toList();
              if (h.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No background history in this range. Turn on background scanning '
                    'in Settings to record CPU, battery and more while TurboMon is closed.',
                    textAlign: TextAlign.center,
                  ),
                );
              }
              RingBuffer series(String key) {
                final r = RingBuffer(h.length);
                for (final s in h) {
                  r.add(s.num_(key), s.time);
                }
                return r;
              }

              final cards = <Widget>[];
              void card(String title, String key, {double? maxY, String unit = '', bool load = false}) {
                final r = series(key);
                if (r.known.isEmpty) return;
                cards.add(GraphCard(
                  title: title,
                  value: 'avg ${r.average!.toStringAsFixed(1)}$unit',
                  graph: LineGraph(
                    capacity: h.length,
                    maxY: maxY,
                    series: [GraphSeries(r, colorByLoad: load, color: seriesPalette[cards.length % 10])],
                  ),
                ));
              }

              card('CPU', 'cpu', maxY: 100, unit: ' %', load: true);
              card('RAM used', 'ram', maxY: 100, unit: ' %', load: true);
              card('GPU', 'gpu', maxY: 100, unit: ' %', load: true);
              card('Battery level', 'battLevel', maxY: 100, unit: ' %');
              card('Battery drain', 'drainMa', unit: ' mA');
              card('Hottest sensor', 'hottestC', unit: ' °C');
              card('Download', 'rxBps', unit: ' B/s');
              card('Upload', 'txBps', unit: ' B/s');
              card('Disk read', 'diskReadBps', unit: ' B/s');
              card('Disk write', 'diskWriteBps', unit: ' B/s');
              card('Strongest Wi-Fi', 'wifiBest', unit: ' dBm');
              card('Bluetooth devices nearby', 'btCount');
              return ListView(
                padding: const EdgeInsets.only(bottom: 16),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('${h.length} samples from ${_fmt(h.first.time)} to ${_fmt(h.last.time)}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                  ...cards,
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: FilledButton.icon(
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Snapshot this range'),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final f = await widget.state.takeSnapshot(
                          reason: 'Background history, last ${_range.inHours} h',
                          from: DateTime.now().subtract(_range),
                        );
                        messenger.showSnackBar(SnackBar(content: Text('Saved ${p.basename(f.path)}')));
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  static String _fmt(DateTime t) =>
      '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
