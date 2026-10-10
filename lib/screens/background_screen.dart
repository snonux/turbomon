import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../app_services.dart';
import '../models/monitor.dart';
import '../models/settings.dart';
import '../widgets/settings_widgets.dart';

/// Background scanning: the master switch, what to scan and how often,
/// auto-stop, presets, history retention and the floating overlay.
class BackgroundScreen extends StatefulWidget {
  const BackgroundScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<BackgroundScreen> createState() => _BackgroundScreenState();
}

class _BackgroundScreenState extends State<BackgroundScreen> {
  static const _intervals = [5, 15, 30, 60, 300, 900, 1800];

  bool _running = false;
  Timer? _poll;

  AppServices get _s => widget.services;

  @override
  void initState() {
    super.initState();
    _refresh();
    // The service can stop on its own (auto-stop, notification button).
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final running = await _s.platform.serviceRunning();
    if (mounted && running != _running) setState(() => _running = running);
  }

  Future<void> _start({String? presetName}) async {
    final settings = _s.settings.value;
    if (settings.scanPlan.monitors.isEmpty) {
      _toast('Pick at least one monitor first.');
      return;
    }
    await _s.permissions.ensure(await _s.permissions.notification());
    final config = BackgroundConfig(
      plan: settings.scanPlan,
      alerts: settings.alerts,
      overlay: settings.overlayEnabled,
      accessMode: settings.accessMode,
      retentionDays: settings.retentionDays,
      presetName: presetName,
    );
    await _s.platform.startService(jsonEncode(config.toJson()));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await _refresh();
  }

  Future<void> _stop() async {
    await _s.platform.stopService();
    await _refresh();
  }

  Future<void> _update(AppSettings next) => _s.settings.update(next);

  Future<void> _setOverlay(AppSettings s, bool on) async {
    if (on && !await _s.platform.canDrawOverlays()) {
      _toast(
        'Allow "Display over other apps" for TurboMon, then switch this on again.',
      );
      await _s.platform.openOverlaySettings();
      return;
    }
    await _update(s.copyWith(overlayEnabled: on));
    if (_running) _toast('Restart background scanning to apply.');
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _savePreset(AppSettings s) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save as preset'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    await _update(
      s.copyWith(
        presets: [
          ...s.presets.where((p) => p.name != name),
          Preset(name, s.scanPlan),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Background scanning')),
      body: ListenableBuilder(
        listenable: _s.settings,
        builder: (context, _) {
          final s = _s.settings.value;
          final plan = s.scanPlan;
          return ListView(
            children: [
              SwitchListTile(
                title: const Text('Background scanning'),
                subtitle: Text(
                  _running
                      ? 'Running · ${plan.autoStop.describe()}'
                      : 'Off: nothing runs once TurboMon is closed',
                ),
                value: _running,
                onChanged: (on) => on ? _start() : _stop(),
              ),
              const SettingsHeader('Presets'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final p in [...Preset.builtIn, ...s.presets])
                      ActionChip(
                        label: Text(p.name),
                        onPressed: () async {
                          await _update(s.copyWith(plan: p.plan));
                          await _start(presetName: p.name);
                        },
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 18),
                      label: const Text('Save current'),
                      onPressed: () => _savePreset(s),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                  'Tapping a preset applies it and starts scanning. The '
                  'quick-settings tile restarts the last one.',
                ),
              ),
              const SettingsHeader('What to scan'),
              for (final m in Monitor.values) _monitorTile(s, m),
              const SettingsHeader('Auto-stop'),
              RadioGroup<AutoStopMode>(
                groupValue: plan.autoStop.mode,
                onChanged: (mode) {
                  if (mode != null) {
                    _update(
                      s.copyWith(
                        plan: plan.copyWith(
                          autoStop: plan.autoStop.copyWith(mode: mode),
                        ),
                      ),
                    );
                  }
                },
                child: Column(
                  children: [
                    for (final mode in AutoStopMode.values)
                      RadioListTile<AutoStopMode>(
                        dense: true,
                        value: mode,
                        title: Text(mode.label),
                        secondary: plan.autoStop.mode == mode
                            ? _autoStopValue(s, mode)
                            : null,
                      ),
                  ],
                ),
              ),
              SwitchListTile(
                title: const Text('Snapshot when it stops'),
                subtitle: const Text('Saved under Snapshot, Saved'),
                value: plan.snapshotOnStop,
                onChanged: (v) =>
                    _update(s.copyWith(plan: plan.copyWith(snapshotOnStop: v))),
              ),
              const SettingsHeader('History and overlay'),
              ListTile(
                title: const Text('Keep history for'),
                trailing: ChoiceDropdown<int>(
                  value: s.retentionDays,
                  options: AppSettings.retentionChoices,
                  label: (v) => '$v days',
                  onChanged: (v) => _update(s.copyWith(retentionDays: v)),
                ),
              ),
              SwitchListTile(
                title: const Text('Floating overlay'),
                subtitle: const Text(
                  'A small CPU, RAM, battery and temperature readout over other '
                  'apps while scanning runs. Drag to move, tap to open TurboMon.',
                ),
                value: s.overlayEnabled,
                onChanged: (v) => _setOverlay(s, v),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Widget _monitorTile(AppSettings s, Monitor m) {
    final plan = s.scanPlan;
    final interval = plan.monitors[m];
    final warning = m.backgroundWarning;
    final needsAccess = m.needsPrivilege && !_s.access.privileged;
    return CheckboxListTile(
      dense: true,
      value: interval != null,
      title: Text(m.label),
      subtitle: warning == null && !needsAccess
          ? null
          : Text(needsAccess ? 'Needs Shizuku or root' : warning!),
      secondary: interval == null
          ? null
          : ChoiceDropdown<int>(
              value: interval,
              options: _intervals,
              label: _intervalLabel,
              onChanged: (v) => _update(
                s.copyWith(
                  plan: plan.copyWith(monitors: {...plan.monitors, m: v}),
                ),
              ),
            ),
      onChanged: (on) {
        final monitors = {...plan.monitors};
        if (on == true) {
          monitors[m] = m.defaultIntervalSeconds;
        } else {
          monitors.remove(m);
        }
        _update(s.copyWith(plan: plan.copyWith(monitors: monitors)));
      },
    );
  }

  Widget _autoStopValue(AppSettings s, AutoStopMode mode) {
    final plan = s.scanPlan;
    final auto = plan.autoStop;
    void set(AutoStop next) =>
        _update(s.copyWith(plan: plan.copyWith(autoStop: next)));
    return switch (mode) {
      AutoStopMode.after => ChoiceDropdown<int>(
        value: auto.durationMinutes,
        options: AutoStop.durationChoices,
        label: (v) => v < 60 ? '$v min' : '${v ~/ 60} h',
        onChanged: (v) => set(auto.copyWith(durationMinutes: v)),
      ),
      AutoStopMode.atTime => TextButton(
        onPressed: () async {
          final picked = await showTimePicker(
            context: context,
            initialTime: TimeOfDay(
              hour: auto.timeOfDayMinutes ~/ 60,
              minute: auto.timeOfDayMinutes % 60,
            ),
          );
          if (picked != null) {
            set(
              auto.copyWith(timeOfDayMinutes: picked.hour * 60 + picked.minute),
            );
          }
        },
        child: Text(
          '${(auto.timeOfDayMinutes ~/ 60).toString().padLeft(2, '0')}:'
          '${(auto.timeOfDayMinutes % 60).toString().padLeft(2, '0')}',
        ),
      ),
      AutoStopMode.batteryBelow => ChoiceDropdown<int>(
        value: auto.batteryBelow,
        options: const [5, 10, 15, 20, 30, 50],
        label: (v) => '$v %',
        onChanged: (v) => set(auto.copyWith(batteryBelow: v)),
      ),
      AutoStopMode.never => const SizedBox.shrink(),
    };
  }

  static String _intervalLabel(int s) => s < 60 ? '$s s' : '${s ~/ 60} min';
}
