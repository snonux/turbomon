import 'package:flutter/material.dart';

import '../app_services.dart';
import '../models/settings.dart';
import '../services/access.dart';
import '../services/app_version.dart';
import '../widgets/settings_widgets.dart';
import 'background_screen.dart';

/// Settings: live refresh, access level, background scanning, alerts,
/// overlay and widget, and About.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final store = services.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: Listenable.merge([store, services.access]),
        builder: (context, _) {
          final s = store.value;
          return ListView(
            children: [
              const SettingsHeader('Live view'),
              ListTile(
                title: const Text('Refresh rate'),
                subtitle: const Text('How often the live screens sample'),
                trailing: ChoiceDropdown<int>(
                  value: s.refreshSeconds,
                  options: AppSettings.refreshChoices,
                  label: (v) => '$v s',
                  onChanged: (v) => store.update(s.copyWith(refreshSeconds: v)),
                ),
              ),
              ListTile(
                title: const Text('Graph window'),
                subtitle: Text('${s.graphCapacity} points per graph'),
                trailing: ChoiceDropdown<int>(
                  value: s.graphWindowMinutes,
                  options: AppSettings.windowChoices,
                  label: (v) => '$v min',
                  onChanged: (v) =>
                      store.update(s.copyWith(graphWindowMinutes: v)),
                ),
              ),
              const SettingsHeader('Access level'),
              _accessSection(context, s),
              const SettingsHeader('Background, alerts, widget and overlay'),
              ListTile(
                leading: const Icon(Icons.schedule),
                title: const Text('Background scanning'),
                subtitle: Text(
                  '${s.scanPlan.monitors.length} monitors · ${s.scanPlan.autoStop.describe()}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => BackgroundScreen(services: services),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.notifications_active_outlined),
                title: const Text('Threshold alerts'),
                subtitle: Text(_alertSummary(s)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AlertsScreen(services: services),
                  ),
                ),
              ),
              const ListTile(
                leading: Icon(Icons.widgets_outlined),
                title: Text('Home-screen widget'),
                subtitle: Text(
                  'Long-press your home screen, choose Widgets, then TurboMon. '
                  'It refreshes live while background scanning runs, otherwise '
                  'every 30 minutes.',
                ),
              ),
              const SettingsHeader('About'),
              FutureBuilder(
                future: loadAppVersion(DefaultAssetBundle.of(context)),
                builder: (context, v) => AboutListTile(
                  icon: Image.asset('logo-small.png', width: 24, height: 24),
                  applicationName: 'TurboMon',
                  applicationVersion: v.data ?? '',
                  applicationIcon: Image.asset(
                    'logo-small.png',
                    width: 48,
                    height: 48,
                  ),
                  applicationLegalese:
                      'MIT licence · no internet access, no tracking',
                  aboutBoxChildren: const [
                    SizedBox(height: 12),
                    Text(
                      'A live system monitor: CPU, RAM, GPU, battery, '
                      'temperatures, network, storage, Wi-Fi and Bluetooth, '
                      'with snapshots an LLM can read.',
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _alertSummary(AppSettings s) {
    final on = s.allAlerts.where((a) => a.enabled).toList();
    if (on.isEmpty) return 'None enabled';
    return on
        .map(
          (a) => '${a.metric.label} ≥ ${a.threshold.round()} ${a.metric.unit}',
        )
        .join(', ');
  }

  Widget _accessSection(BuildContext context, AppSettings s) {
    final access = services.access;
    final shizuku = access.shizuku;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RadioGroup<AccessMode>(
          groupValue: s.accessMode,
          onChanged: (mode) async {
            if (mode == null) return;
            await services.settings.update(s.copyWith(accessMode: mode));
            await access.resolve(mode);
          },
          child: Column(
            children: [
              for (final mode in AccessMode.values)
                RadioListTile<AccessMode>(
                  value: mode,
                  dense: true,
                  title: Text(mode.label),
                  subtitle: Text(switch (mode) {
                    AccessMode.auto =>
                      'Uses Shizuku when it is running and allowed',
                    AccessMode.normal =>
                      'RAM, clocks, battery, radios; no process list',
                    AccessMode.shizuku =>
                      'ADB shell rights: real CPU %, processes, GPU, disk I/O',
                    AccessMode.root => 'Same as Shizuku, through su',
                  }),
                ),
            ],
          ),
        ),
        ListTile(
          dense: true,
          leading: Icon(
            access.privileged ? Icons.lock_open : Icons.lock_outline,
          ),
          title: Text('Now: ${access.level.label}'),
          subtitle: Text(
            access.problem ??
                'Shizuku ${shizuku.running ? 'running' : 'not running'}'
                    '${shizuku.running ? (shizuku.granted ? ', allowed' : ', not allowed yet') : ''}',
          ),
          trailing: TextButton(
            onPressed: () => access.resolve(s.accessMode),
            child: const Text('Check again'),
          ),
        ),
      ],
    );
  }
}

/// Alert rules: one card per metric.
class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key, required this.services});

  final AppServices services;

  static const _durations = [30, 60, 120, 300];

  @override
  Widget build(BuildContext context) {
    final store = services.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Threshold alerts')),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final s = store.value;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const Text(
                'A notification when a value stays at or above its limit for '
                'the set time. Alerts are checked while TurboMon is open and '
                'while background scanning runs.',
              ),
              for (final rule in s.allAlerts)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                    child: Column(
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(rule.metric.label),
                          subtitle: Text(
                            '≥ ${rule.threshold.round()} ${rule.metric.unit} '
                            'for ${rule.durationSeconds} s',
                          ),
                          value: rule.enabled,
                          onChanged: (on) async {
                            if (on) {
                              await services.permissions.ensure(
                                await services.permissions.notification(),
                              );
                            }
                            await store.update(
                              s.withAlert(rule.copyWith(enabled: on)),
                            );
                          },
                        ),
                        if (rule.enabled) ...[
                          Slider(
                            value: rule.threshold.clamp(
                              _min(rule.metric),
                              _max(rule.metric),
                            ),
                            min: _min(rule.metric),
                            max: _max(rule.metric),
                            divisions: 20,
                            label:
                                '${rule.threshold.round()} ${rule.metric.unit}',
                            onChanged: (v) => store.update(
                              s.withAlert(rule.copyWith(threshold: v)),
                            ),
                          ),
                          Row(
                            children: [
                              const Text('Held for'),
                              const SizedBox(width: 12),
                              ChoiceDropdown<int>(
                                value: rule.durationSeconds,
                                options: _durations,
                                label: (v) => '$v s',
                                onChanged: (v) => store.update(
                                  s.withAlert(
                                    rule.copyWith(durationSeconds: v),
                                  ),
                                ),
                              ),
                              const Spacer(),
                              const Text('Snapshot'),
                              Checkbox(
                                value: rule.autoSnapshot,
                                onChanged: (v) => store.update(
                                  s.withAlert(
                                    rule.copyWith(autoSnapshot: v ?? false),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  static double _min(AlertMetric m) => switch (m) {
    AlertMetric.cpu || AlertMetric.ram => 10,
    AlertMetric.temperature => 30,
    AlertMetric.batteryDrain => 100,
  };

  static double _max(AlertMetric m) => switch (m) {
    AlertMetric.cpu || AlertMetric.ram => 100,
    AlertMetric.temperature => 70,
    AlertMetric.batteryDrain => 3000,
  };
}
