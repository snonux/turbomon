import 'dart:convert';

/// Every monitor TurboMon can sample, live or in the background.
enum Monitor {
  cpu('CPU'),
  ram('RAM'),
  gpu('GPU'),
  battery('Battery'),
  network('Network'),
  temperature('Temperatures'),
  diskUsage('Disk usage'),
  diskIo('Disk I/O'),
  wifi('Wi-Fi'),
  bluetooth('Bluetooth'),
  processes('Process list');

  const Monitor(this.label);
  final String label;

  /// Default background sampling interval for this monitor, in seconds.
  /// Wi-Fi is limited by Android's scan throttle, disk usage barely moves.
  int get defaultIntervalSeconds => switch (this) {
        Monitor.wifi => 120,
        Monitor.bluetooth => 60,
        Monitor.diskUsage => 600,
        Monitor.processes => 60,
        _ => 30,
      };
}

/// Which elevated access the user wants TurboMon to use.
enum AccessMode {
  auto('Automatic'),
  normal('Normal app only'),
  shizuku('Shizuku'),
  root('Root');

  const AccessMode(this.label);
  final String label;
}

enum AutoStopKind {
  never('Never'),
  duration('After a duration'),
  timeOfDay('At a time of day'),
  batteryBelow('When battery drops below');

  const AutoStopKind(this.label);
  final String label;
}

/// How and when background scanning stops on its own.
class AutoStop {
  const AutoStop({
    this.kind = AutoStopKind.duration,
    this.minutes = 60,
    this.hour = 7,
    this.minute = 0,
    this.batteryPercent = 20,
  });

  final AutoStopKind kind;
  final int minutes;
  final int hour;
  final int minute;
  final int batteryPercent;

  static const durationChoices = [15, 60, 240, 480, 1440];

  AutoStop copyWith({AutoStopKind? kind, int? minutes, int? hour, int? minute, int? batteryPercent}) =>
      AutoStop(
        kind: kind ?? this.kind,
        minutes: minutes ?? this.minutes,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        batteryPercent: batteryPercent ?? this.batteryPercent,
      );

  /// When the run started at [start] should stop; null for battery or never.
  DateTime? stopTime(DateTime start) => switch (kind) {
        AutoStopKind.duration => start.add(Duration(minutes: minutes)),
        AutoStopKind.timeOfDay => () {
            var t = DateTime(start.year, start.month, start.day, hour, minute);
            if (!t.isAfter(start)) t = t.add(const Duration(days: 1));
            return t;
          }(),
        _ => null,
      };

  String describe() => switch (kind) {
        AutoStopKind.never => 'runs until stopped',
        AutoStopKind.duration => 'stops after ${formatMinutes(minutes)}',
        AutoStopKind.timeOfDay =>
          'stops at ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
        AutoStopKind.batteryBelow => 'stops below $batteryPercent % battery',
      };

  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'minutes': minutes,
        'hour': hour,
        'minute': minute,
        'batteryPercent': batteryPercent,
      };

  factory AutoStop.fromJson(Map<String, Object?> j) => AutoStop(
        kind: AutoStopKind.values.asNameMap()[j['kind']] ?? AutoStopKind.duration,
        minutes: (j['minutes'] as num?)?.toInt() ?? 60,
        hour: (j['hour'] as num?)?.toInt() ?? 7,
        minute: (j['minute'] as num?)?.toInt() ?? 0,
        batteryPercent: (j['batteryPercent'] as num?)?.toInt() ?? 20,
      );
}

String formatMinutes(int minutes) {
  if (minutes < 60) return '$minutes min';
  if (minutes % 60 == 0) return '${minutes ~/ 60} h';
  return '${minutes ~/ 60} h ${minutes % 60} min';
}

/// What a background run samples and for how long. Also the shape of a
/// preset, and what is handed to the Android service as JSON.
class BackgroundPlan {
  const BackgroundPlan({
    required this.monitors,
    this.intervals = const {},
    this.autoStop = const AutoStop(),
    this.snapshotOnStop = true,
  });

  final Set<Monitor> monitors;
  final Map<Monitor, int> intervals;
  final AutoStop autoStop;
  final bool snapshotOnStop;

  int intervalOf(Monitor m) => intervals[m] ?? m.defaultIntervalSeconds;

  BackgroundPlan copyWith({
    Set<Monitor>? monitors,
    Map<Monitor, int>? intervals,
    AutoStop? autoStop,
    bool? snapshotOnStop,
  }) =>
      BackgroundPlan(
        monitors: monitors ?? this.monitors,
        intervals: intervals ?? this.intervals,
        autoStop: autoStop ?? this.autoStop,
        snapshotOnStop: snapshotOnStop ?? this.snapshotOnStop,
      );

  Map<String, Object?> toJson() => {
        'monitors': [for (final m in Monitor.values) if (monitors.contains(m)) m.name],
        'intervals': {for (final m in monitors) m.name: intervalOf(m)},
        'autoStop': autoStop.toJson(),
        'snapshotOnStop': snapshotOnStop,
      };

  factory BackgroundPlan.fromJson(Map<String, Object?> j) {
    final names = Monitor.values.asNameMap();
    final intervals = <Monitor, int>{};
    ((j['intervals'] as Map?) ?? const {}).forEach((k, v) {
      final m = names[k];
      if (m != null && v is num) intervals[m] = v.toInt();
    });
    return BackgroundPlan(
      monitors: {
        for (final n in (j['monitors'] as List?) ?? const []) ?names[n],
      },
      intervals: intervals,
      autoStop: AutoStop.fromJson(((j['autoStop'] as Map?) ?? const {}).cast<String, Object?>()),
      snapshotOnStop: (j['snapshotOnStop'] as bool?) ?? true,
    );
  }
}

class Preset {
  const Preset(this.name, this.plan);
  final String name;
  final BackgroundPlan plan;

  Map<String, Object?> toJson() => {'name': name, 'plan': plan.toJson()};
  factory Preset.fromJson(Map<String, Object?> j) => Preset(
        (j['name'] as String?) ?? 'Preset',
        BackgroundPlan.fromJson(((j['plan'] as Map?) ?? const {}).cast<String, Object?>()),
      );
}

const builtInPresets = [
  Preset(
    'Overnight drain check',
    BackgroundPlan(
      monitors: {Monitor.cpu, Monitor.battery, Monitor.processes, Monitor.temperature},
      autoStop: AutoStop(kind: AutoStopKind.duration, minutes: 480),
    ),
  ),
  Preset(
    'Quick 15-minute check',
    BackgroundPlan(
      monitors: {Monitor.cpu, Monitor.ram, Monitor.battery, Monitor.network, Monitor.temperature},
      intervals: {Monitor.cpu: 5, Monitor.ram: 5, Monitor.battery: 10, Monitor.network: 5, Monitor.temperature: 10},
      autoStop: AutoStop(kind: AutoStopKind.duration, minutes: 15),
    ),
  ),
  Preset(
    'Radio survey (Wi-Fi + Bluetooth)',
    BackgroundPlan(
      monitors: {Monitor.wifi, Monitor.bluetooth, Monitor.battery},
      autoStop: AutoStop(kind: AutoStopKind.duration, minutes: 60),
    ),
  ),
];

/// Limits that raise a notification when crossed for [sustainSeconds].
class AlertRules {
  const AlertRules({
    this.cpuEnabled = true,
    this.cpuPercent = 80,
    this.tempEnabled = true,
    this.tempC = 45,
    this.drainEnabled = true,
    this.drainMa = 600,
    this.ramEnabled = false,
    this.ramPercent = 90,
    this.sustainSeconds = 60,
    this.autoSnapshot = true,
  });

  final bool cpuEnabled;
  final double cpuPercent;
  final bool tempEnabled;
  final double tempC;
  final bool drainEnabled;
  final double drainMa;
  final bool ramEnabled;
  final double ramPercent;
  final int sustainSeconds;
  final bool autoSnapshot;

  bool get anyEnabled => cpuEnabled || tempEnabled || drainEnabled || ramEnabled;

  AlertRules copyWith({
    bool? cpuEnabled,
    double? cpuPercent,
    bool? tempEnabled,
    double? tempC,
    bool? drainEnabled,
    double? drainMa,
    bool? ramEnabled,
    double? ramPercent,
    int? sustainSeconds,
    bool? autoSnapshot,
  }) =>
      AlertRules(
        cpuEnabled: cpuEnabled ?? this.cpuEnabled,
        cpuPercent: cpuPercent ?? this.cpuPercent,
        tempEnabled: tempEnabled ?? this.tempEnabled,
        tempC: tempC ?? this.tempC,
        drainEnabled: drainEnabled ?? this.drainEnabled,
        drainMa: drainMa ?? this.drainMa,
        ramEnabled: ramEnabled ?? this.ramEnabled,
        ramPercent: ramPercent ?? this.ramPercent,
        sustainSeconds: sustainSeconds ?? this.sustainSeconds,
        autoSnapshot: autoSnapshot ?? this.autoSnapshot,
      );

  Map<String, Object?> toJson() => {
        'cpuEnabled': cpuEnabled,
        'cpuPercent': cpuPercent,
        'tempEnabled': tempEnabled,
        'tempC': tempC,
        'drainEnabled': drainEnabled,
        'drainMa': drainMa,
        'ramEnabled': ramEnabled,
        'ramPercent': ramPercent,
        'sustainSeconds': sustainSeconds,
        'autoSnapshot': autoSnapshot,
      };

  factory AlertRules.fromJson(Map<String, Object?> j) {
    const d = AlertRules();
    double n(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    bool b(String k, bool def) => (j[k] as bool?) ?? def;
    return AlertRules(
      cpuEnabled: b('cpuEnabled', d.cpuEnabled),
      cpuPercent: n('cpuPercent', d.cpuPercent),
      tempEnabled: b('tempEnabled', d.tempEnabled),
      tempC: n('tempC', d.tempC),
      drainEnabled: b('drainEnabled', d.drainEnabled),
      drainMa: n('drainMa', d.drainMa),
      ramEnabled: b('ramEnabled', d.ramEnabled),
      ramPercent: n('ramPercent', d.ramPercent),
      sustainSeconds: (j['sustainSeconds'] as num?)?.toInt() ?? d.sustainSeconds,
      autoSnapshot: b('autoSnapshot', d.autoSnapshot),
    );
  }
}

/// All user settings. Stored as one JSON string in SharedPreferences.
class Settings {
  const Settings({
    this.refreshSeconds = 2,
    this.graphWindowMinutes = 4,
    this.accessMode = AccessMode.auto,
    this.wifiScanSeconds = 30,
    this.includeAddresses = false,
    this.alerts = const AlertRules(),
    this.backgroundEnabled = false,
    this.plan = const BackgroundPlan(
      monitors: {Monitor.cpu, Monitor.ram, Monitor.battery, Monitor.network, Monitor.temperature},
    ),
    this.historyDays = 7,
    this.presets = builtInPresets,
    this.widgetEnabled = false,
    this.overlayEnabled = false,
  });

  final int refreshSeconds;
  final int graphWindowMinutes;
  final AccessMode accessMode;
  final int wifiScanSeconds;

  /// Whether snapshots keep Wi-Fi BSSIDs and Bluetooth addresses, which can
  /// locate the user. Off by default.
  final bool includeAddresses;
  final AlertRules alerts;
  final bool backgroundEnabled;
  final BackgroundPlan plan;
  final int historyDays;
  final List<Preset> presets;
  final bool widgetEnabled;
  final bool overlayEnabled;

  static const refreshChoices = [1, 2, 5];
  static const windowChoices = [1, 4, 15];

  /// Samples kept per live graph: the window divided by the refresh rate.
  int get graphCapacity => (graphWindowMinutes * 60 / refreshSeconds).ceil();

  Settings copyWith({
    int? refreshSeconds,
    int? graphWindowMinutes,
    AccessMode? accessMode,
    int? wifiScanSeconds,
    bool? includeAddresses,
    AlertRules? alerts,
    bool? backgroundEnabled,
    BackgroundPlan? plan,
    int? historyDays,
    List<Preset>? presets,
    bool? widgetEnabled,
    bool? overlayEnabled,
  }) =>
      Settings(
        refreshSeconds: refreshSeconds ?? this.refreshSeconds,
        graphWindowMinutes: graphWindowMinutes ?? this.graphWindowMinutes,
        accessMode: accessMode ?? this.accessMode,
        wifiScanSeconds: wifiScanSeconds ?? this.wifiScanSeconds,
        includeAddresses: includeAddresses ?? this.includeAddresses,
        alerts: alerts ?? this.alerts,
        backgroundEnabled: backgroundEnabled ?? this.backgroundEnabled,
        plan: plan ?? this.plan,
        historyDays: historyDays ?? this.historyDays,
        presets: presets ?? this.presets,
        widgetEnabled: widgetEnabled ?? this.widgetEnabled,
        overlayEnabled: overlayEnabled ?? this.overlayEnabled,
      );

  /// What the Android service needs: the plan plus everything it acts on.
  Map<String, Object?> serviceConfig() => {
        ...plan.toJson(),
        'alerts': alerts.toJson(),
        'historyDays': historyDays,
        'accessMode': accessMode.name,
        'widget': widgetEnabled,
        'overlay': overlayEnabled,
      };

  String encode() => jsonEncode({
        'refreshSeconds': refreshSeconds,
        'graphWindowMinutes': graphWindowMinutes,
        'accessMode': accessMode.name,
        'wifiScanSeconds': wifiScanSeconds,
        'includeAddresses': includeAddresses,
        'alerts': alerts.toJson(),
        'backgroundEnabled': backgroundEnabled,
        'plan': plan.toJson(),
        'historyDays': historyDays,
        'presets': presets.map((p) => p.toJson()).toList(),
        'widgetEnabled': widgetEnabled,
        'overlayEnabled': overlayEnabled,
      });

  factory Settings.decode(String? text) {
    if (text == null || text.isEmpty) return const Settings();
    final Object? raw;
    try {
      raw = jsonDecode(text);
    } on FormatException {
      return const Settings();
    }
    if (raw is! Map) return const Settings();
    final j = raw.cast<String, Object?>();
    const d = Settings();
    Map<String, Object?> sub(String k) => ((j[k] as Map?) ?? const {}).cast<String, Object?>();
    return Settings(
      refreshSeconds: (j['refreshSeconds'] as num?)?.toInt() ?? d.refreshSeconds,
      graphWindowMinutes: (j['graphWindowMinutes'] as num?)?.toInt() ?? d.graphWindowMinutes,
      accessMode: AccessMode.values.asNameMap()[j['accessMode']] ?? d.accessMode,
      wifiScanSeconds: (j['wifiScanSeconds'] as num?)?.toInt() ?? d.wifiScanSeconds,
      includeAddresses: (j['includeAddresses'] as bool?) ?? d.includeAddresses,
      alerts: j['alerts'] is Map ? AlertRules.fromJson(sub('alerts')) : d.alerts,
      backgroundEnabled: (j['backgroundEnabled'] as bool?) ?? d.backgroundEnabled,
      plan: j['plan'] is Map ? BackgroundPlan.fromJson(sub('plan')) : d.plan,
      historyDays: (j['historyDays'] as num?)?.toInt() ?? d.historyDays,
      presets: j['presets'] is List
          ? [
              for (final p in j['presets'] as List)
                if (p is Map) Preset.fromJson(p.cast<String, Object?>()),
            ]
          : d.presets,
      widgetEnabled: (j['widgetEnabled'] as bool?) ?? d.widgetEnabled,
      overlayEnabled: (j['overlayEnabled'] as bool?) ?? d.overlayEnabled,
    );
  }
}
