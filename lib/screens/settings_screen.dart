import 'package:flutter/material.dart';

import '../model/settings.dart';
import '../services/app_state.dart';

const _notificationPermission = ['android.permission.POST_NOTIFICATIONS'];

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.state});
  final AppState state;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AppState get state => widget.state;
  Settings get s => state.settings;

  Future<void> _set(Settings n) async {
    await state.updateSettings(n);
    if (mounted) setState(() {});
  }

  Future<bool> _ensureNotifications() async {
    final sdk = (state.monitor.device['sdk'] as num?)?.toInt() ?? 33;
    if (sdk < 33) return true;
    if (await state.bridge.hasPermissions(_notificationPermission)) return true;
    return state.bridge.requestPermissions(_notificationPermission);
  }

  Future<void> _toggleBackground(bool on) async {
    if (on) {
      await _ensureNotifications();
      await state.startBackground();
    } else {
      await state.stopBackground();
    }
    if (mounted) setState(() {});
  }

  /// Widget, overlay and background alerts all run from the background
  /// service; offer to start it when one of them is turned on.
  Future<void> _needsService(String what) async {
    if (state.backgroundRunning) return;
    final start = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Start background scanning?'),
        content: Text('$what updates from the background service, which is off. '
            'It shows a permanent notification and stops as set under Auto-stop.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Start')),
        ],
      ),
    );
    if (start == true) await _toggleBackground(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: state,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            _header('Display'),
            ListTile(
              title: const Text('Refresh rate'),
              trailing: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [for (final v in Settings.refreshChoices) ButtonSegment(value: v, label: Text('$v s'))],
                selected: {s.refreshSeconds},
                onSelectionChanged: (v) => _set(s.copyWith(refreshSeconds: v.first)),
              ),
            ),
            ListTile(
              title: const Text('Graph window'),
              trailing: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [for (final v in Settings.windowChoices) ButtonSegment(value: v, label: Text('$v min'))],
                selected: {s.graphWindowMinutes},
                onSelectionChanged: (v) => _set(s.copyWith(graphWindowMinutes: v.first)),
              ),
            ),
            ListTile(
              title: const Text('Wi-Fi scan interval'),
              subtitle: const Text('Android allows 4 scans per 2 minutes unless throttling is off'),
              trailing: DropdownButton<int>(
                value: s.wifiScanSeconds,
                items: [for (final v in const [30, 60, 120]) DropdownMenuItem(value: v, child: Text('$v s'))],
                onChanged: (v) => _set(s.copyWith(wifiScanSeconds: v)),
              ),
            ),
            _header('Access'),
            ListTile(
              title: const Text('Elevated access'),
              subtitle: Text('Now: ${state.monitor.access.label} · Shizuku: ${_shizukuText(state.shizukuState)}'),
              trailing: DropdownButton<AccessMode>(
                value: s.accessMode,
                items: [for (final m in AccessMode.values) DropdownMenuItem(value: m, child: Text(m.label))],
                onChanged: (m) => _set(s.copyWith(accessMode: m)),
              ),
            ),
            if (state.shizukuState == 'denied')
              ListTile(
                leading: const Icon(Icons.key),
                title: const Text('Grant Shizuku access'),
                onTap: () => state.refreshAccess(requestShizuku: true),
              ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Shizuku or root adds the full process list, real CPU %, GPU load, every thermal sensor, '
                'disk I/O and per-app battery use. See docs/shizuku-and-root.md.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            _header('Background scanning'),
            SwitchListTile(
              title: const Text('Scan in the background'),
              subtitle: Text(state.backgroundRunning ? _runningText() : 'Off: nothing runs once TurboMon is closed'),
              value: state.backgroundRunning,
              onChanged: _toggleBackground,
            ),
            const ListTile(dense: true, title: Text('What to scan, and how often')),
            for (final m in Monitor.values) _monitorRow(m),
            if (s.plan.monitors.contains(Monitor.wifi))
              _warn('In the background Android may allow only one Wi-Fi scan every 30 minutes.'),
            if (s.plan.monitors.contains(Monitor.bluetooth))
              _warn('Bluetooth scans may pause while the screen is off.'),
            if (s.plan.monitors.contains(Monitor.processes) || s.plan.monitors.contains(Monitor.gpu) ||
                s.plan.monitors.contains(Monitor.diskIo))
              if (!state.monitor.access.elevated)
                _warn('Process list, GPU and disk I/O need Shizuku or root and are skipped without them.'),
            ListTile(
              title: const Text('Auto-stop'),
              subtitle: Text(s.plan.autoStop.describe()),
              trailing: DropdownButton<AutoStopKind>(
                value: s.plan.autoStop.kind,
                items: [for (final k in AutoStopKind.values) DropdownMenuItem(value: k, child: Text(k.label))],
                onChanged: (k) => _setPlan(s.plan.copyWith(autoStop: s.plan.autoStop.copyWith(kind: k))),
              ),
            ),
            if (s.plan.autoStop.kind == AutoStopKind.duration)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(spacing: 6, children: [
                  for (final mins in AutoStop.durationChoices)
                    ChoiceChip(
                      label: Text(formatMinutes(mins)),
                      selected: s.plan.autoStop.minutes == mins,
                      onSelected: (_) =>
                          _setPlan(s.plan.copyWith(autoStop: s.plan.autoStop.copyWith(minutes: mins))),
                    ),
                ]),
              ),
            if (s.plan.autoStop.kind == AutoStopKind.timeOfDay)
              ListTile(
                title: const Text('Stop at'),
                trailing: TextButton(
                  child: Text('${s.plan.autoStop.hour.toString().padLeft(2, '0')}:'
                      '${s.plan.autoStop.minute.toString().padLeft(2, '0')}'),
                  onPressed: () async {
                    final t = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay(hour: s.plan.autoStop.hour, minute: s.plan.autoStop.minute),
                    );
                    if (t != null) {
                      _setPlan(s.plan.copyWith(autoStop: s.plan.autoStop.copyWith(hour: t.hour, minute: t.minute)));
                    }
                  },
                ),
              ),
            if (s.plan.autoStop.kind == AutoStopKind.batteryBelow)
              ListTile(
                title: Text('Battery below ${s.plan.autoStop.batteryPercent} %'),
                subtitle: Slider(
                  min: 5,
                  max: 80,
                  divisions: 15,
                  value: s.plan.autoStop.batteryPercent.toDouble(),
                  onChanged: (v) =>
                      _setPlan(s.plan.copyWith(autoStop: s.plan.autoStop.copyWith(batteryPercent: v.round()))),
                ),
              ),
            SwitchListTile(
              title: const Text('Save a snapshot when a run stops'),
              value: s.plan.snapshotOnStop,
              onChanged: (v) => _setPlan(s.plan.copyWith(snapshotOnStop: v)),
            ),
            ListTile(
              title: const Text('Keep history for'),
              trailing: DropdownButton<int>(
                value: s.historyDays,
                items: [for (final d in const [1, 3, 7, 14, 30]) DropdownMenuItem(value: d, child: Text('$d days'))],
                onChanged: (d) => _set(s.copyWith(historyDays: d)),
              ),
            ),
            const ListTile(dense: true, title: Text('Presets')),
            for (final p in s.presets)
              ListTile(
                leading: const Icon(Icons.play_circle_outline),
                title: Text(p.name),
                subtitle: Text('${p.plan.monitors.map((m) => m.label).join(', ')} · ${p.plan.autoStop.describe()}'),
                onTap: () async {
                  await _ensureNotifications();
                  await state.startBackground(p.plan);
                  if (mounted) setState(() {});
                },
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _set(s.copyWith(presets: [...s.presets]..remove(p))),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Save current choice as a preset'),
              onTap: _savePreset,
            ),
            _header('Alerts'),
            _alertRow('CPU above', s.alerts.cpuEnabled, s.alerts.cpuPercent, 50, 100, '%',
                (e, v) => s.alerts.copyWith(cpuEnabled: e, cpuPercent: v),
                note: 'Needs real CPU %, so Shizuku or root.'),
            _alertRow('Temperature above', s.alerts.tempEnabled, s.alerts.tempC, 35, 70, '°C',
                (e, v) => s.alerts.copyWith(tempEnabled: e, tempC: v)),
            _alertRow('Battery drain above', s.alerts.drainEnabled, s.alerts.drainMa, 200, 2000, 'mA',
                (e, v) => s.alerts.copyWith(drainEnabled: e, drainMa: v)),
            _alertRow('RAM above', s.alerts.ramEnabled, s.alerts.ramPercent, 60, 99, '%',
                (e, v) => s.alerts.copyWith(ramEnabled: e, ramPercent: v)),
            ListTile(
              title: const Text('For at least'),
              trailing: DropdownButton<int>(
                value: s.alerts.sustainSeconds,
                items: [for (final v in const [30, 60, 120, 300]) DropdownMenuItem(value: v, child: Text('$v s'))],
                onChanged: (v) => _set(s.copyWith(alerts: s.alerts.copyWith(sustainSeconds: v))),
              ),
            ),
            SwitchListTile(
              title: const Text('Save a snapshot when an alert fires'),
              value: s.alerts.autoSnapshot,
              onChanged: (v) => _set(s.copyWith(alerts: s.alerts.copyWith(autoSnapshot: v))),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('Alerts are checked while TurboMon is open, and by background scanning when it runs.',
                  style: TextStyle(fontSize: 12)),
            ),
            _header('Widget and overlay'),
            ListTile(
              leading: const Icon(Icons.widgets_outlined),
              title: const Text('Add home-screen widget'),
              subtitle: const Text('CPU, RAM, battery and temperature'),
              onTap: () async {
                final ok = await state.bridge.requestPinWidget();
                await _set(s.copyWith(widgetEnabled: true));
                if (!ok && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Add it from your launcher: long-press the home screen, Widgets, TurboMon.')));
                }
                await _needsService('The widget');
              },
            ),
            SwitchListTile(
              title: const Text('Floating overlay'),
              subtitle: const Text('Small live stats window over other apps'),
              value: s.overlayEnabled,
              onChanged: (on) async {
                if (on && !await state.bridge.canDrawOverlays()) {
                  await state.bridge.openOverlaySettings();
                  return; // the user comes back and flips the switch again
                }
                await _set(s.copyWith(overlayEnabled: on));
                if (on) await _needsService('The overlay');
              },
            ),
            _header('Snapshots'),
            SwitchListTile(
              title: const Text('Include Wi-Fi and Bluetooth addresses'),
              subtitle: const Text('Off by default: router addresses can reveal where you are'),
              value: s.includeAddresses,
              onChanged: (v) => _set(s.copyWith(includeAddresses: v)),
            ),
            _header('About'),
            ListTile(
              title: const Text('TurboMon'),
              subtitle: Text('Version ${state.appVersion} · MIT licence\nhttps://github.com/snonux/turbomon'),
              isThreeLine: true,
            ),
          ],
        ),
      ),
    );
  }

  String _runningText() {
    final stopAt = state.background['stopAtMs'] as num?;
    final mons = (state.background['monitors'] as List?)?.length ?? s.plan.monitors.length;
    if (stopAt == null) return 'Running, $mons monitors, ${s.plan.autoStop.describe()}';
    final left = DateTime.fromMillisecondsSinceEpoch(stopAt.toInt()).difference(DateTime.now());
    return 'Running, $mons monitors, ${formatMinutes(left.inMinutes.clamp(0, 100000))} left';
  }

  void _setPlan(BackgroundPlan p) => _set(s.copyWith(plan: p));

  Widget _monitorRow(Monitor m) {
    final on = s.plan.monitors.contains(m);
    final interval = s.plan.intervalOf(m);
    return CheckboxListTile(
      dense: true,
      value: on,
      title: Text(m.label),
      controlAffinity: ListTileControlAffinity.leading,
      onChanged: (v) {
        final set = {...s.plan.monitors};
        v == true ? set.add(m) : set.remove(m);
        _setPlan(s.plan.copyWith(monitors: set));
      },
      secondary: on
          ? DropdownButton<int>(
              value: _intervalChoices.contains(interval) ? interval : null,
              hint: Text('${interval}s'),
              items: [for (final v in _intervalChoices) DropdownMenuItem(value: v, child: Text(_fmtInterval(v)))],
              onChanged: (v) => _setPlan(s.plan.copyWith(intervals: {...s.plan.intervals, m: v!})),
            )
          : null,
    );
  }

  static const _intervalChoices = [5, 10, 30, 60, 120, 300, 600, 1800];
  static String _fmtInterval(int s) => s < 60 ? 'every $s s' : 'every ${s ~/ 60} min';

  Widget _alertRow(String title, bool enabled, double value, double min, double max, String unit,
      AlertRules Function(bool, double) apply,
      {String? note}) {
    return Column(children: [
      SwitchListTile(
        title: Text('$title ${value.toStringAsFixed(0)} $unit'),
        subtitle: note == null ? null : Text(note),
        value: enabled,
        onChanged: (e) async {
          if (e) await _ensureNotifications();
          await _set(s.copyWith(alerts: apply(e, value)));
        },
      ),
      if (enabled)
        Slider(
          min: min,
          max: max,
          divisions: ((max - min) / (unit == 'mA' ? 50 : 1)).round(),
          value: value.clamp(min, max),
          label: '${value.toStringAsFixed(0)} $unit',
          onChanged: (v) => _set(s.copyWith(alerts: apply(true, v))),
        ),
    ]);
  }

  Future<void> _savePreset() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Preset name'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await _set(s.copyWith(presets: [...s.presets, Preset(name, s.plan)]));
  }

  static String _shizukuText(String state) => switch (state) {
        'granted' => 'granted',
        'denied' => 'installed, not granted',
        'not_running' => 'installed, not running',
        _ => 'not installed',
      };

  Widget _header(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(t, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );

  Widget _warn(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Row(children: [
          const Icon(Icons.info_outline, size: 16),
          const SizedBox(width: 6),
          Expanded(child: Text(t, style: const TextStyle(fontSize: 12))),
        ]),
      );
}
