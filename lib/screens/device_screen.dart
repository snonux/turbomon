import 'package:flutter/material.dart';

import '../model/readings.dart';
import '../services/app_state.dart';
import '../widgets/graphs.dart';

/// Battery, temperatures, network, disk usage and disk I/O.
class DeviceScreen extends StatefulWidget {
  const DeviceScreen({super.key, required this.state});
  final AppState state;

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> with WidgetsBindingObserver {
  bool? _usageAccess;
  List<AppSize>? _sizes;
  List<Map<String, Object?>>? _appNet;
  bool _loadingApps = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkUsage();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Coming back from the usage access settings page.
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _checkUsage();
  }

  Future<void> _checkUsage() async {
    final ok = await widget.state.bridge.hasUsageAccess().catchError((_) => false);
    if (mounted) setState(() => _usageAccess = ok);
  }

  Future<void> _loadApps() async {
    setState(() => _loadingApps = true);
    final b = widget.state.bridge;
    final sizes = await b.appSizes().catchError((_) => <Map<String, Object?>>[]);
    final net = await b.appNetworkUsage(const Duration(hours: 24)).catchError((_) => <Map<String, Object?>>[]);
    if (!mounted) return;
    setState(() {
      _sizes = [for (final m in sizes) AppSize.fromMap(m)]..sort((a, c) => c.total.compareTo(a.total));
      _appNet = net..sort((a, c) => _netTotal(c).compareTo(_netTotal(a)));
      _loadingApps = false;
    });
  }

  static int _netTotal(Map<String, Object?> m) =>
      ((m['rxBytes'] as num?)?.toInt() ?? 0) + ((m['txBytes'] as num?)?.toInt() ?? 0);

  @override
  Widget build(BuildContext context) {
    final m = widget.state.monitor;
    return ListenableBuilder(
      listenable: m,
      builder: (context, _) {
        final b = m.battery;
        final theme = Theme.of(context);
        return ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            _Section('Battery', [
              if (b == null)
                const Text('Reading battery...')
              else ...[
                UsageBar(label: 'Level', percent: b.levelPercent.toDouble(), height: 16),
                _kv('Status', '${b.status}${b.plugged == 'none' ? '' : ' (${b.plugged})'}'),
                _kv('Current', b.currentMa == null ? 'not reported' : '${b.currentMa!.toStringAsFixed(0)} mA'),
                _kv('Power', b.powerW == null ? 'n/a' : '${b.powerW!.toStringAsFixed(2)} W'),
                _kv('Voltage', b.voltageMv == null ? 'n/a' : '${(b.voltageMv! / 1000).toStringAsFixed(2)} V'),
                _kv('Temperature', b.tempC == null ? 'n/a' : '${b.tempC!.toStringAsFixed(1)} °C'),
                _kv('Health', b.health),
                if (b.chargeCounterMah != null) _kv('Charge left', '${b.chargeCounterMah!.toStringAsFixed(0)} mAh'),
                if (m.batteryDrain.average != null)
                  _kv('Average drain', '${m.batteryDrain.average!.toStringAsFixed(0)} mA over the graph window'),
              ],
            ]),
            _Section('Temperatures', [
              _kv('Thermal status',
                  m.thermalStatus == null ? 'not reported' : thermalStatusNames[m.thermalStatus!.clamp(0, 6)]),
              if (m.thermalHeadroom != null)
                _kv('Headroom', '${(m.thermalHeadroom! * 100).toStringAsFixed(0)} % of throttling point'),
              if (m.zones.isEmpty)
                Text(
                  m.access.elevated
                      ? 'No thermal sensors reported.'
                      : 'Individual sensors are hidden from normal apps on most phones; Shizuku or root shows them.',
                  style: theme.textTheme.bodySmall,
                )
              else
                for (final z in [...m.zones]..sort((a, c) => c.celsius.compareTo(a.celsius)))
                  _kv(z.type, '${z.celsius.toStringAsFixed(1)} °C'),
            ]),
            _Section('Network', [
              _kv('Download', formatRate(m.rxBps ?? 0)),
              _kv('Upload', formatRate(m.txBps ?? 0)),
              if (m.mobileRxBps != null)
                _kv('Mobile data', '↓${formatRate(m.mobileRxBps!)} ↑${formatRate(m.mobileTxBps ?? 0)}'),
              if (m.mobileRxBps != null && m.rxBps != null)
                _kv('Wi-Fi and other',
                    '↓${formatRate((m.rxBps! - m.mobileRxBps!).clamp(0, double.infinity))} '
                        '↑${formatRate(((m.txBps ?? 0) - (m.mobileTxBps ?? 0)).clamp(0, double.infinity))}'),
              if (_appNet != null && _appNet!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Per app, last 24 h', style: theme.textTheme.labelLarge),
                for (final a in _appNet!.take(10))
                  _kv('${a['label'] ?? a['package']}',
                      '↓${formatBytes((a['rxBytes'] as num?) ?? 0)} ↑${formatBytes((a['txBytes'] as num?) ?? 0)}'),
              ],
            ]),
            _Section('Disk usage', [
              for (final v in m.volumes)
                UsageBar(
                  label: v.removable ? 'SD/USB' : 'Internal',
                  percent: v.usedPercent,
                  height: 16,
                  detail: '${formatBytes(v.freeBytes, digits: 0)} free',
                ),
              if (m.volumes.isEmpty) const Text('Reading volumes...'),
              const SizedBox(height: 6),
              if (_usageAccess == false)
                OutlinedButton.icon(
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Allow usage access for per-app sizes and data use'),
                  onPressed: () async {
                    await widget.state.bridge.openUsageAccessSettings();
                  },
                )
              else if (_sizes == null)
                OutlinedButton.icon(
                  icon: _loadingApps
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.apps),
                  label: const Text('Show per-app sizes and data use'),
                  onPressed: _loadingApps ? null : _loadApps,
                )
              else ...[
                Text('Largest apps (app + data + cache)', style: theme.textTheme.labelLarge),
                for (final a in _sizes!.take(15))
                  _kv(a.label.isEmpty ? a.package : a.label,
                      '${formatBytes(a.total)}  (${formatBytes(a.appBytes, digits: 0)} + ${formatBytes(a.dataBytes, digits: 0)} + ${formatBytes(a.cacheBytes, digits: 0)})'),
              ],
            ]),
            _Section('Disk I/O', [
              if (m.diskIoAvailable) ...[
                for (final d in m.diskRates)
                  _kv(d.device,
                      'R ${formatRate(d.readBytesPerSec)} (${d.readOpsPerSec.toStringAsFixed(0)}/s)  '
                          'W ${formatRate(d.writeBytesPerSec)} (${d.writeOpsPerSec.toStringAsFixed(0)}/s)'),
              ] else
                Text(
                  'System-wide disk counters are blocked for normal apps; Shizuku or root shows them.',
                  style: theme.textTheme.bodySmall,
                ),
              if (m.ownReadBps != null)
                _kv('TurboMon itself', 'R ${formatRate(m.ownReadBps!)}  W ${formatRate(m.ownWriteBps ?? 0)}'),
            ]),
          ],
        );
      },
    );
  }
}

Widget _kv(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 2, child: Text(k, overflow: TextOverflow.ellipsis)),
        Expanded(flex: 3, child: Text(v, textAlign: TextAlign.right)),
      ]),
    );

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              ...children,
            ],
          ),
        ),
      );
}
