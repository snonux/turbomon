import 'package:flutter/material.dart';

import '../model/readings.dart';
import '../services/app_state.dart';
import '../widgets/graphs.dart';
import 'settings_screen.dart';

enum _Sort { cpu, ram, battery, name }

/// The `top`-style screen: bars per core, RAM and GPU, then the process table.
class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key, required this.state});
  final AppState state;

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  _Sort _sort = _Sort.cpu;

  @override
  Widget build(BuildContext context) {
    final m = widget.state.monitor;
    return ListenableBuilder(
      listenable: m,
      builder: (context, _) {
        final theme = Theme.of(context);
        final rows = [...m.processes];
        switch (_sort) {
          case _Sort.cpu:
            break; // already sorted by CPU
          case _Sort.ram:
            rows.sort((a, b) => b.rssKb.compareTo(a.rssKb));
          case _Sort.battery:
            rows.sort((a, b) => (b.batteryMah ?? -1).compareTo(a.batteryMah ?? -1));
          case _Sort.name:
            rows.sort((a, b) => a.name.compareTo(b.name));
        }
        final mem = m.mem;
        final b = m.battery;
        final cpuLabel = m.cpuIsProxy ? 'CPU freq' : 'CPU';
        return ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            if (!m.access.elevated) _AccessBanner(state: widget.state),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  UsageBar(label: cpuLabel, percent: m.cpu.last, height: 18),
                  for (var i = 0; i < m.cores.length; i++)
                    UsageBar(
                      label: 'cpu$i',
                      percent: m.cores[i].last,
                      height: 9,
                      detail: m.cpuIsProxy && i < m.coreFreqs.length
                          ? '${(m.coreFreqs[i].curKhz / 1000).round()} MHz'
                          : null,
                    ),
                  const SizedBox(height: 6),
                  UsageBar(
                    label: 'RAM',
                    percent: m.ram.last,
                    height: 18,
                    detail: mem == null
                        ? null
                        : '${formatBytes(mem.usedKb * 1024)} / ${formatBytes(mem.totalKb * 1024, digits: 0)}',
                  ),
                  if (mem != null && mem.swapTotalKb > 0)
                    UsageBar(
                      label: 'Swap',
                      percent: (mem.swapTotalKb - mem.swapFreeKb) * 100 / mem.swapTotalKb,
                      height: 9,
                    ),
                  if (m.gpuAvailable) UsageBar(label: 'GPU', percent: m.gpu.last, height: 18),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      if (b != null)
                        _Stat(Icons.battery_std, '${b.levelPercent} %'
                            '${b.powerW == null ? '' : ' · ${b.powerW!.toStringAsFixed(2)} W'}'
                            '${b.charging ? ' charging' : ''}'),
                      if (m.hottest.last != null)
                        _Stat(Icons.thermostat, '${m.hottest.last!.toStringAsFixed(1)} °C'),
                      if (m.rxBps != null)
                        _Stat(Icons.swap_vert, '↓${formatRate(m.rxBps!)} ↑${formatRate(m.txBps ?? 0)}'),
                      _Stat(Icons.security, m.access.label),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Text('${rows.length} processes', style: theme.textTheme.titleSmall),
                  const Spacer(),
                  SegmentedButton<_Sort>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    segments: const [
                      ButtonSegment(value: _Sort.cpu, label: Text('CPU')),
                      ButtonSegment(value: _Sort.ram, label: Text('RAM')),
                      ButtonSegment(value: _Sort.battery, label: Text('Batt')),
                      ButtonSegment(value: _Sort.name, label: Text('Name')),
                    ],
                    selected: {_sort},
                    onSelectionChanged: (s) => setState(() => _sort = s.first),
                  ),
                ],
              ),
            ),
            _ProcessHeader(),
            for (final p in rows.take(100)) _ProcessLine(p),
          ],
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.icon, this.text);
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16),
        const SizedBox(width: 4),
        Text(text, style: Theme.of(context).textTheme.bodySmall),
      ]);
}

class _AccessBanner extends StatelessWidget {
  const _AccessBanner({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.lock_outline),
        title: const Text('Normal app access'),
        subtitle: const Text(
            'Android hides other apps and real CPU % from normal apps. '
            'CPU bars show core frequency. Grant Shizuku or root for the full process list.'),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => SettingsScreen(state: state))),
      ),
    );
  }
}

const _mono = TextStyle(fontFeatures: [FontFeature.tabularFigures()], fontSize: 12);

class _ProcessHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = _mono.copyWith(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.outline);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      child: Row(children: [
        SizedBox(width: 52, child: Text('PID', style: s)),
        Expanded(child: Text('NAME', style: s)),
        SizedBox(width: 48, child: Text('CPU%', style: s, textAlign: TextAlign.right)),
        SizedBox(width: 64, child: Text('RSS', style: s, textAlign: TextAlign.right)),
        SizedBox(width: 44, child: Text('mAh', style: s, textAlign: TextAlign.right)),
      ]),
    );
  }
}

class _ProcessLine extends StatelessWidget {
  const _ProcessLine(this.p);
  final ProcessRow p;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      child: Row(children: [
        SizedBox(width: 52, child: Text('${p.pid}', style: _mono)),
        Expanded(child: Text(p.name, style: _mono, overflow: TextOverflow.ellipsis)),
        SizedBox(
          width: 48,
          child: Text(p.cpuPercent.toStringAsFixed(1),
              style: _mono.copyWith(color: p.cpuPercent >= 10 ? loadColor(p.cpuPercent * 2) : null),
              textAlign: TextAlign.right),
        ),
        SizedBox(width: 64, child: Text(formatBytes(p.rssKb * 1024, digits: 0), style: _mono, textAlign: TextAlign.right)),
        SizedBox(
            width: 44,
            child: Text(p.batteryMah?.toStringAsFixed(0) ?? '', style: _mono, textAlign: TextAlign.right)),
      ]),
    );
  }
}
