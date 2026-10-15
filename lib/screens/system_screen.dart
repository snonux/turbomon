import 'package:flutter/material.dart';

import '../app_services.dart';
import '../models/readings.dart';
import '../services/format.dart';
import '../services/monitor_hub.dart';
import '../theme.dart';
import '../widgets/section_card.dart';
import '../widgets/usage_bar.dart';
import '../widgets/usage_graph.dart';

/// The top/htop-style screen: per-core bars, RAM and GPU, live graphs and
/// the process table.
class SystemScreen extends StatefulWidget {
  const SystemScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<SystemScreen> createState() => _SystemScreenState();
}

class _SystemScreenState extends State<SystemScreen> {
  bool _splitCores = false;

  @override
  Widget build(BuildContext context) {
    final hub = widget.services.hub;
    return ListenableBuilder(
      listenable: hub,
      builder: (context, _) {
        final s = hub.latest;
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _cpuCard(s?.cpu),
            _memoryCard(s?.memory, s?.gpu),
            _graphsCard(hub, s),
            _processCard(hub),
          ],
        );
      },
    );
  }

  Widget _cpuCard(CpuReading? cpu) {
    final proxy = cpu?.isFrequencyProxy ?? true;
    final loads = cpu?.coreLoads ?? const [];
    return SectionCard(
      icon: Icons.memory,
      title: 'CPU${cpu == null ? '' : ' · ${cpu.coreCount} cores'}',
      subtitle: proxy
          ? 'Clock speed as a share of each core\'s maximum'
          : 'Utilisation from /proc/stat',
      trailing: Text(
        formatPercent(cpu?.load),
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(color: loadColor(cpu?.load)),
      ),
      child: Column(
        children: [
          if (cpu == null)
            const LinearProgressIndicator()
          else if (loads.every((l) => l == null))
            Hint(
              widget.services.access.privileged
                  ? _shellWaiting()
                  : 'This device hides CPU load and clock speeds from apps. '
                        'Shizuku or root unlocks real CPU % (Settings, Access '
                        'level).',
            )
          else
            for (var i = 0; i < loads.length; i++)
              UsageBar(
                label: 'cpu$i',
                percent: loads[i],
                trailing: proxy
                    ? formatMhz(cpu.frequencies.elementAtOrNull(i)?.currentKHz)
                    : null,
              ),
        ],
      ),
    );
  }

  Widget _memoryCard(MemoryReading? m, GpuReading? gpu) {
    return SectionCard(
      icon: Icons.storage_outlined,
      title: 'Memory${gpu != null ? ' and GPU' : ''}',
      child: Column(
        children: [
          if (m == null)
            const LinearProgressIndicator()
          else ...[
            UsageBar(
              label: 'RAM',
              percent: m.usedPercent,
              trailing:
                  '${formatBytes(m.usedBytes)} / ${formatBytes(m.totalBytes)}',
              labelWidth: 44,
            ),
            if ((m.swapTotalBytes ?? 0) > 0)
              UsageBar(
                label: 'Swap',
                percent:
                    (m.swapTotalBytes! - (m.swapFreeBytes ?? 0)) /
                    m.swapTotalBytes! *
                    100,
                trailing: formatBytes(
                  m.swapTotalBytes! - (m.swapFreeBytes ?? 0),
                ),
              ),
            if (m.cachedBytes != null)
              StatRow('Cached', formatBytes(m.cachedBytes!)),
            StatRow('Available', formatBytes(m.availableBytes)),
          ],
          // The GPU bar hides itself rather than showing a guess.
          if (gpu?.busyPercent != null)
            UsageBar(
              label: 'GPU',
              percent: gpu!.busyPercent,
              trailing: gpu.frequencyMHz == null
                  ? null
                  : '${gpu.busyPercent!.round()} % · ${gpu.frequencyMHz} MHz',
            ),
        ],
      ),
    );
  }

  Widget _graphsCard(MonitorHub hub, SystemSample? s) {
    final window = '${hub.series[SeriesKey.cpu]!.capacity} samples';
    final cpuLabel = (s?.cpu?.isFrequencyProxy ?? true) ? 'CPU clock' : 'CPU';
    return SectionCard(
      icon: Icons.show_chart,
      title: 'Live graphs',
      subtitle: '$window · tap the CPU graph to split it per core',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _graphLabel(cpuLabel, formatPercent(s?.cpu?.load)),
          InkWell(
            onTap: () => setState(() => _splitCores = !_splitCores),
            child: _splitCores && hub.coreSeries.isNotEmpty
                ? _coreGrid(hub)
                : LiveUsageGraph(
                    listenable: hub,
                    linesBuilder: () => [GraphLine(hub.series[SeriesKey.cpu]!)],
                    maxValue: 100,
                    semanticLabel: '$cpuLabel graph',
                  ),
          ),
          const SizedBox(height: 10),
          _graphLabel('RAM', formatPercent(s?.memory?.usedPercent)),
          LiveUsageGraph(
            listenable: hub,
            linesBuilder: () => [GraphLine(hub.series[SeriesKey.ram]!)],
            maxValue: 100,
            semanticLabel: 'RAM graph',
          ),
          if (!hub.series[SeriesKey.gpu]!.isEmpty) ...[
            const SizedBox(height: 10),
            _graphLabel('GPU', formatPercent(s?.gpu?.busyPercent)),
            LiveUsageGraph(
              listenable: hub,
              linesBuilder: () => [GraphLine(hub.series[SeriesKey.gpu]!)],
              maxValue: 100,
              semanticLabel: 'GPU graph',
            ),
          ],
        ],
      ),
    );
  }

  Widget _coreGrid(MonitorHub hub) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 3.2,
      mainAxisSpacing: 4,
      crossAxisSpacing: 8,
      children: [
        for (var i = 0; i < hub.coreSeries.length; i++)
          Stack(
            children: [
              LiveUsageGraph(
                listenable: hub,
                linesBuilder: () => [
                  if (i < hub.coreSeries.length) GraphLine(hub.coreSeries[i]),
                ],
                maxValue: 100,
                height: 48,
                semanticLabel: 'cpu$i graph',
              ),
              Text('cpu$i', style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
      ],
    );
  }

  /// Shown while the privileged shell has not answered yet.
  String _shellWaiting() {
    final access = widget.services.access;
    final error = access.shellError;
    return 'Waiting for ${access.level.label} to answer'
        '${error == null ? '' : ' ($error)'}. TurboMon keeps trying.';
  }

  Widget _graphLabel(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.labelLarge),
        ),
        Text(value, style: Theme.of(context).textTheme.labelLarge),
      ],
    ),
  );

  Widget _processCard(MonitorHub hub) {
    final services = widget.services;
    final theme = Theme.of(context);
    final mono = theme.textTheme.bodySmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final withBattery = hub.processes.any((p) => p.batteryMah != null);
    return SectionCard(
      icon: Icons.list_alt,
      title: 'Processes',
      subtitle: services.access.privileged
          ? 'Sorted by CPU · via ${services.access.level.label}'
          : null,
      child: !services.access.privileged
          ? const Hint(
              'Android hides other apps\' processes from normal apps. Turn on '
              'Shizuku or root under Settings, Access level, to see the full '
              'top-style list.',
            )
          : hub.processes.isEmpty
          ? services.access.shellError == null
                ? const LinearProgressIndicator()
                : Hint(_shellWaiting())
          : Table(
              columnWidths: {
                0: const FixedColumnWidth(52),
                1: const FlexColumnWidth(),
                2: const FixedColumnWidth(48),
                3: const FixedColumnWidth(62),
                4: const FixedColumnWidth(18),
                if (withBattery) 5: const FixedColumnWidth(44),
              },
              children: [
                TableRow(
                  children: [
                    for (final h in [
                      'PID',
                      'NAME',
                      'CPU%',
                      'RSS',
                      'S',
                      if (withBattery) 'mAh',
                    ])
                      Text(h, style: theme.textTheme.labelSmall),
                  ],
                ),
                for (final p in hub.processes.take(30))
                  TableRow(
                    children: [
                      Text('${p.pid}', style: mono),
                      Padding(
                        // Keeps a gutter when a long name fills the column.
                        padding: const EdgeInsets.only(right: 6),
                        child: Text(
                          p.name,
                          style: mono,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        p.cpuPercent.toStringAsFixed(1),
                        style: mono?.copyWith(color: loadColor(p.cpuPercent)),
                      ),
                      Text(formatBytes(p.rssBytes, decimals: 0), style: mono),
                      Text(p.state, style: mono),
                      if (withBattery)
                        Text(
                          p.batteryMah?.toStringAsFixed(0) ?? '',
                          style: mono,
                        ),
                    ],
                  ),
              ],
            ),
    );
  }
}
