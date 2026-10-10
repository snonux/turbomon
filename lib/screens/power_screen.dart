import 'package:flutter/material.dart';

import '../app_services.dart';
import '../models/readings.dart';
import '../services/monitor_hub.dart';
import '../theme.dart';
import '../widgets/section_card.dart';
import '../widgets/usage_bar.dart';
import '../widgets/usage_graph.dart';

/// Battery, power draw and temperatures.
class PowerScreen extends StatelessWidget {
  const PowerScreen({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final hub = services.hub;
    return ListenableBuilder(
      listenable: hub,
      builder: (context, _) {
        final s = hub.latest;
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _battery(context, hub, s?.battery),
            _thermal(context, hub, s?.thermal),
          ],
        );
      },
    );
  }

  Widget _battery(BuildContext context, MonitorHub hub, BatteryReading? b) {
    if (b == null) {
      return const SectionCard(
        title: 'Battery',
        child: LinearProgressIndicator(),
      );
    }
    final power = b.powerW;
    final current = b.currentMa;
    return SectionCard(
      icon: b.charging ? Icons.battery_charging_full : Icons.battery_std,
      title: 'Battery',
      subtitle: [b.status, if (b.plugged != null) 'on ${b.plugged}'].join(' '),
      trailing: Text(
        b.percent == null ? '–' : '${b.percent!.round()} %',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UsageBar(
            label: 'Level',
            percent: b.percent,
            // Battery level is good when high, so invert the load colour.
            color: loadColor(b.percent == null ? null : 100 - b.percent!),
          ),
          StatRow('Current', current == null ? '–' : '${current.round()} mA'),
          StatRow(
            'Power',
            power == null ? '–' : '${power.toStringAsFixed(2)} W',
          ),
          StatRow(
            'Voltage',
            b.voltageMv == null
                ? '–'
                : '${(b.voltageMv! / 1000).toStringAsFixed(2)} V',
          ),
          StatRow(
            'Temperature',
            b.temperatureC == null
                ? '–'
                : '${b.temperatureC!.toStringAsFixed(1)} °C',
          ),
          StatRow('Health', b.health ?? '–'),
          const SizedBox(height: 10),
          Text(
            b.charging ? 'Charging power (W)' : 'Power draw (W)',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 4),
          UsageGraph(
            lines: [
              GraphLine(
                hub.series[SeriesKey.batteryPower]!,
                color: b.charging ? const Color(0xFF43A047) : turboOrange,
              ),
            ],
            semanticLabel: 'Battery power graph',
          ),
          const SizedBox(height: 10),
          Text('Level (%)', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          UsageGraph(
            lines: [
              GraphLine(
                hub.series[SeriesKey.batteryPercent]!,
                color: const Color(0xFF42A5F5),
              ),
            ],
            maxValue: 100,
            height: 56,
            semanticLabel: 'Battery level graph',
          ),
        ],
      ),
    );
  }

  Widget _thermal(BuildContext context, MonitorHub hub, ThermalReading? t) {
    final zones = [...?t?.zones]
      ..sort((a, b) => b.celsius.compareTo(a.celsius));
    final headroom = t?.headroom;
    return SectionCard(
      icon: Icons.thermostat,
      title: 'Temperatures',
      subtitle: t?.statusName == null
          ? null
          : 'Thermal status: ${t!.statusName}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (headroom != null)
            UsageBar(
              // Android's thermal headroom: 1.0 is where throttling starts.
              label: 'Heat',
              percent: headroom * 100,
              trailing: '${(headroom * 100).round()} % of limit',
            ),
          for (final z in zones.take(12)) _ZoneRow(z),
          if (zones.length <= 1 && !services.access.privileged)
            const Hint(
              'Only the battery sensor is readable as a normal app. Shizuku '
              'or root adds every thermal zone.',
            ),
          const SizedBox(height: 10),
          Text(
            'Hottest sensor (°C)',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 4),
          UsageGraph(
            lines: [
              GraphLine(hub.series[SeriesKey.temperature]!, color: turboOrange),
            ],
            semanticLabel: 'Temperature graph',
          ),
        ],
      ),
    );
  }
}

class _ZoneRow extends StatelessWidget {
  const _ZoneRow(this.zone);

  final ThermalZone zone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 20 °C reads as an empty bar, 60 °C as a full one.
    final share = ((zone.celsius - 20) / 40).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              zone.name,
              style: theme.textTheme.labelMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: share,
                minHeight: 8,
                color: loadColor(share * 100),
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
          SizedBox(
            width: 64,
            child: Text(
              '${zone.celsius.toStringAsFixed(1)} °C',
              textAlign: TextAlign.end,
              style: theme.textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );
  }
}
