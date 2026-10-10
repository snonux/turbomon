import 'package:flutter/material.dart';

import '../app_services.dart';
import '../models/readings.dart';
import '../services/format.dart';
import '../services/monitor_hub.dart';
import '../widgets/section_card.dart';
import '../widgets/usage_bar.dart';
import '../widgets/usage_graph.dart';
import 'app_usage_screen.dart';

const _downColor = Color(0xFF42A5F5);
const _upColor = Color(0xFFFF7A1A);

/// Network speed, storage and disk I/O.
class IoScreen extends StatelessWidget {
  const IoScreen({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final hub = services.hub;
    return ListenableBuilder(
      listenable: hub,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _network(context, hub, hub.latest?.network),
          _storage(context, hub.volumes),
          _diskIo(context, hub, hub.latest?.diskIo),
        ],
      ),
    );
  }

  Widget _network(BuildContext context, MonitorHub hub, NetworkRate? n) {
    return SectionCard(
      icon: Icons.network_check,
      title: 'Network speed',
      trailing: TextButton(
        onPressed: () => _openUsage(context, AppUsageKind.network),
        child: const Text('Per app'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _legendRow(
            context,
            'Download',
            n == null ? '–' : formatRate(n.rxBps),
            _downColor,
          ),
          _legendRow(
            context,
            'Upload',
            n == null ? '–' : formatRate(n.txBps),
            _upColor,
          ),
          const SizedBox(height: 6),
          UsageGraph(
            lines: [
              GraphLine(hub.series[SeriesKey.netRx]!, color: _downColor),
              GraphLine(
                hub.series[SeriesKey.netTx]!,
                color: _upColor,
                fill: false,
              ),
            ],
            height: 96,
            semanticLabel: 'Network speed graph',
          ),
          if (n != null) ...[
            const SizedBox(height: 6),
            StatRow(
              'Wi-Fi ↓ / ↑',
              '${formatRate(n.wifiRxBps)} / ${formatRate(n.wifiTxBps)}',
            ),
            StatRow(
              'Mobile ↓ / ↑',
              '${formatRate(n.mobileRxBps)} / ${formatRate(n.mobileTxBps)}',
            ),
          ],
        ],
      ),
    );
  }

  Widget _storage(BuildContext context, List<StorageVolume> volumes) {
    return SectionCard(
      icon: Icons.sd_storage_outlined,
      title: 'Storage',
      trailing: TextButton(
        onPressed: () => _openUsage(context, AppUsageKind.storage),
        child: const Text('Per app'),
      ),
      child: Column(
        children: [
          if (volumes.isEmpty) const LinearProgressIndicator(),
          for (final v in volumes) ...[
            UsageBar(
              label: v.removable ? 'SD' : 'Int',
              percent: v.usedPercent,
              trailing: '${formatBytes(v.freeBytes, decimals: 0)} free',
            ),
            StatRow(
              v.label,
              '${formatBytes(v.usedBytes)} of ${formatBytes(v.totalBytes)}',
            ),
          ],
        ],
      ),
    );
  }

  Widget _diskIo(BuildContext context, MonitorHub hub, DiskIoReading? io) {
    final own = io?.scope == 'self';
    return SectionCard(
      icon: Icons.sync_alt,
      title: 'Disk I/O',
      subtitle: io == null
          ? null
          : own
          ? 'TurboMon\'s own reads and writes'
          : 'All disks, from /proc/diskstats',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _legendRow(
            context,
            'Read',
            io == null ? '–' : formatRate(io.readBps),
            _downColor,
          ),
          _legendRow(
            context,
            'Write',
            io == null ? '–' : formatRate(io.writeBps),
            _upColor,
          ),
          if (io?.readOps != null)
            StatRow(
              'Operations/s (r / w)',
              '${io!.readOps!.toStringAsFixed(1)} / ${io.writeOps!.toStringAsFixed(1)}',
            ),
          const SizedBox(height: 6),
          UsageGraph(
            lines: [
              GraphLine(hub.series[SeriesKey.diskRead]!, color: _downColor),
              GraphLine(
                hub.series[SeriesKey.diskWrite]!,
                color: _upColor,
                fill: false,
              ),
            ],
            height: 80,
            semanticLabel: 'Disk I/O graph',
          ),
          if (own || io == null)
            const Hint(
              'Device-wide disk I/O needs Shizuku or root; Android blocks '
              '/proc/diskstats for normal apps.',
            ),
        ],
      ),
    );
  }

  Widget _legendRow(
    BuildContext context,
    String label,
    String value,
    Color color,
  ) => Row(
    children: [
      Container(width: 10, height: 10, color: color),
      const SizedBox(width: 6),
      Expanded(child: Text(label)),
      Text(
        value,
        style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
      ),
    ],
  );

  void _openUsage(BuildContext context, AppUsageKind kind) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AppUsageScreen(services: services, kind: kind),
        ),
      );
}
