import 'monitor.dart';
import '../services/access.dart';

/// Values an alert can watch.
enum AlertMetric {
  cpu('CPU load', '%', 85),
  temperature('Temperature', '°C', 45),
  batteryDrain('Battery drain', 'mA', 800),
  ram('RAM used', '%', 90);

  const AlertMetric(this.label, this.unit, this.defaultThreshold);

  final String label;
  final String unit;
  final double defaultThreshold;
}

/// Fires when [metric] stays at or above [threshold] for [durationSeconds].
class AlertRule {
  const AlertRule({
    required this.metric,
    this.enabled = false,
    required this.threshold,
    this.durationSeconds = 60,
    this.autoSnapshot = false,
  });

  factory AlertRule.defaults(AlertMetric metric) =>
      AlertRule(metric: metric, threshold: metric.defaultThreshold);

  factory AlertRule.fromJson(Map<String, Object?> json) {
    final metric = AlertMetric.values.byName(json['metric'] as String);
    return AlertRule(
      metric: metric,
      enabled: json['enabled'] as bool? ?? false,
      threshold:
          (json['threshold'] as num?)?.toDouble() ?? metric.defaultThreshold,
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 60,
      autoSnapshot: json['autoSnapshot'] as bool? ?? false,
    );
  }

  final AlertMetric metric;
  final bool enabled;
  final double threshold;
  final int durationSeconds;
  final bool autoSnapshot;

  AlertRule copyWith({
    bool? enabled,
    double? threshold,
    int? durationSeconds,
    bool? autoSnapshot,
  }) => AlertRule(
    metric: metric,
    enabled: enabled ?? this.enabled,
    threshold: threshold ?? this.threshold,
    durationSeconds: durationSeconds ?? this.durationSeconds,
    autoSnapshot: autoSnapshot ?? this.autoSnapshot,
  );

  Map<String, Object?> toJson() => {
    'metric': metric.name,
    'enabled': enabled,
    'threshold': threshold,
    'durationSeconds': durationSeconds,
    'autoSnapshot': autoSnapshot,
  };
}

enum AutoStopMode {
  after('After a set time'),
  atTime('At a time of day'),
  batteryBelow('Below a battery level'),
  never('Never');

  const AutoStopMode(this.label);
  final String label;
}

class AutoStop {
  const AutoStop({
    this.mode = AutoStopMode.after,
    this.durationMinutes = 60,
    this.timeOfDayMinutes = 7 * 60,
    this.batteryBelow = 20,
  });

  factory AutoStop.fromJson(Map<String, Object?> json) => AutoStop(
    mode: AutoStopMode.values.byName(json['mode'] as String? ?? 'after'),
    durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 60,
    timeOfDayMinutes: (json['timeOfDayMinutes'] as num?)?.toInt() ?? 7 * 60,
    batteryBelow: (json['batteryBelow'] as num?)?.toInt() ?? 20,
  );

  static const durationChoices = [15, 60, 240, 480, 1440];

  final AutoStopMode mode;
  final int durationMinutes;

  /// Minutes after midnight, local time.
  final int timeOfDayMinutes;
  final int batteryBelow;

  /// The moment a run started at [start] should end, for the time-based
  /// modes; null for the others.
  DateTime? deadline(DateTime start) {
    switch (mode) {
      case AutoStopMode.after:
        return start.add(Duration(minutes: durationMinutes));
      case AutoStopMode.atTime:
        var at = DateTime(
          start.year,
          start.month,
          start.day,
          timeOfDayMinutes ~/ 60,
          timeOfDayMinutes % 60,
        );
        if (!at.isAfter(start)) at = at.add(const Duration(days: 1));
        return at;
      case AutoStopMode.batteryBelow:
      case AutoStopMode.never:
        return null;
    }
  }

  String describe() => switch (mode) {
    AutoStopMode.after => 'stops after ${_minutes(durationMinutes)}',
    AutoStopMode.atTime =>
      'stops at ${(timeOfDayMinutes ~/ 60).toString().padLeft(2, '0')}:'
          '${(timeOfDayMinutes % 60).toString().padLeft(2, '0')}',
    AutoStopMode.batteryBelow => 'stops below $batteryBelow % battery',
    AutoStopMode.never => 'runs until stopped',
  };

  static String _minutes(int m) => m < 60 ? '$m min' : '${m ~/ 60} h';

  AutoStop copyWith({
    AutoStopMode? mode,
    int? durationMinutes,
    int? timeOfDayMinutes,
    int? batteryBelow,
  }) => AutoStop(
    mode: mode ?? this.mode,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    timeOfDayMinutes: timeOfDayMinutes ?? this.timeOfDayMinutes,
    batteryBelow: batteryBelow ?? this.batteryBelow,
  );

  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'durationMinutes': durationMinutes,
    'timeOfDayMinutes': timeOfDayMinutes,
    'batteryBelow': batteryBelow,
  };
}

/// What a background run samples and when it ends.
class ScanPlan {
  const ScanPlan({
    required this.monitors,
    this.autoStop = const AutoStop(),
    this.snapshotOnStop = true,
  });

  factory ScanPlan.fromJson(Map<String, Object?> json) => ScanPlan(
    monitors: {
      for (final e in (json['monitors'] as Map? ?? const {}).entries)
        ?Monitor.byName(e.key as String): (e.value as num).toInt(),
    },
    autoStop: AutoStop.fromJson(
      (json['autoStop'] as Map?)?.cast<String, Object?>() ?? const {},
    ),
    snapshotOnStop: json['snapshotOnStop'] as bool? ?? true,
  );

  /// Checked monitors and their interval in seconds.
  final Map<Monitor, int> monitors;
  final AutoStop autoStop;
  final bool snapshotOnStop;

  static final standard = ScanPlan(
    monitors: {
      for (final m in [Monitor.cpu, Monitor.ram, Monitor.battery])
        m: m.defaultIntervalSeconds,
    },
  );

  ScanPlan copyWith({
    Map<Monitor, int>? monitors,
    AutoStop? autoStop,
    bool? snapshotOnStop,
  }) => ScanPlan(
    monitors: monitors ?? this.monitors,
    autoStop: autoStop ?? this.autoStop,
    snapshotOnStop: snapshotOnStop ?? this.snapshotOnStop,
  );

  Map<String, Object?> toJson() => {
    'monitors': {for (final e in monitors.entries) e.key.name: e.value},
    'autoStop': autoStop.toJson(),
    'snapshotOnStop': snapshotOnStop,
  };
}

class Preset {
  const Preset(this.name, this.plan);

  factory Preset.fromJson(Map<String, Object?> json) => Preset(
    json['name'] as String,
    ScanPlan.fromJson((json['plan'] as Map).cast<String, Object?>()),
  );

  final String name;
  final ScanPlan plan;

  static final builtIn = [
    Preset(
      'Overnight drain check',
      ScanPlan(
        monitors: {
          Monitor.cpu: 60,
          Monitor.battery: 60,
          Monitor.processes: 300,
        },
        autoStop: const AutoStop(durationMinutes: 480),
      ),
    ),
    Preset(
      'Heat check',
      ScanPlan(
        monitors: {
          Monitor.cpu: 15,
          Monitor.gpu: 15,
          Monitor.temperature: 15,
          Monitor.battery: 30,
        },
        autoStop: const AutoStop(durationMinutes: 60),
      ),
    ),
    Preset(
      'Network watch',
      ScanPlan(
        monitors: {Monitor.network: 15, Monitor.wifi: 300},
        autoStop: const AutoStop(durationMinutes: 240),
        snapshotOnStop: false,
      ),
    ),
  ];

  Map<String, Object?> toJson() => {'name': name, 'plan': plan.toJson()};
}

/// Everything under Settings, stored as one JSON document.
class AppSettings {
  const AppSettings({
    this.refreshSeconds = 2,
    this.graphWindowMinutes = 4,
    this.accessMode = AccessMode.auto,
    this.plan,
    this.retentionDays = 7,
    this.alerts = const [],
    this.overlayEnabled = false,
    this.presets = const [],
  });

  factory AppSettings.fromJson(Map<String, Object?> json) => AppSettings(
    refreshSeconds: (json['refreshSeconds'] as num?)?.toInt() ?? 2,
    graphWindowMinutes: (json['graphWindowMinutes'] as num?)?.toInt() ?? 4,
    accessMode:
        AccessMode.values.asNameMap()[json['accessMode']] ?? AccessMode.auto,
    plan: json['plan'] is Map
        ? ScanPlan.fromJson((json['plan'] as Map).cast<String, Object?>())
        : null,
    retentionDays: (json['retentionDays'] as num?)?.toInt() ?? 7,
    alerts: [
      for (final a in json['alerts'] as List? ?? const [])
        AlertRule.fromJson((a as Map).cast<String, Object?>()),
    ],
    overlayEnabled: json['overlayEnabled'] as bool? ?? false,
    presets: [
      for (final p in json['presets'] as List? ?? const [])
        Preset.fromJson((p as Map).cast<String, Object?>()),
    ],
  );

  static const refreshChoices = [1, 2, 5];
  static const windowChoices = [1, 4, 15];
  static const retentionChoices = [1, 3, 7, 14];

  final int refreshSeconds;
  final int graphWindowMinutes;
  final AccessMode accessMode;
  final ScanPlan? plan;
  final int retentionDays;
  final List<AlertRule> alerts;
  final bool overlayEnabled;

  /// User presets; [Preset.builtIn] are offered alongside.
  final List<Preset> presets;

  ScanPlan get scanPlan => plan ?? ScanPlan.standard;

  /// Ring-buffer size for the live graphs: one point per refresh.
  int get graphCapacity => graphWindowMinutes * 60 ~/ refreshSeconds;

  /// Each metric's rule, defaulting to a disabled rule.
  AlertRule alert(AlertMetric metric) => alerts.firstWhere(
    (a) => a.metric == metric,
    orElse: () => AlertRule.defaults(metric),
  );

  List<AlertRule> get allAlerts => [
    for (final m in AlertMetric.values) alert(m),
  ];

  AppSettings withAlert(AlertRule rule) => copyWith(
    alerts: [
      for (final m in AlertMetric.values) m == rule.metric ? rule : alert(m),
    ],
  );

  AppSettings copyWith({
    int? refreshSeconds,
    int? graphWindowMinutes,
    AccessMode? accessMode,
    ScanPlan? plan,
    int? retentionDays,
    List<AlertRule>? alerts,
    bool? overlayEnabled,
    List<Preset>? presets,
  }) => AppSettings(
    refreshSeconds: refreshSeconds ?? this.refreshSeconds,
    graphWindowMinutes: graphWindowMinutes ?? this.graphWindowMinutes,
    accessMode: accessMode ?? this.accessMode,
    plan: plan ?? this.plan,
    retentionDays: retentionDays ?? this.retentionDays,
    alerts: alerts ?? this.alerts,
    overlayEnabled: overlayEnabled ?? this.overlayEnabled,
    presets: presets ?? this.presets,
  );

  Map<String, Object?> toJson() => {
    'refreshSeconds': refreshSeconds,
    'graphWindowMinutes': graphWindowMinutes,
    'accessMode': accessMode.name,
    if (plan != null) 'plan': plan!.toJson(),
    'retentionDays': retentionDays,
    'alerts': [for (final a in alerts) a.toJson()],
    'overlayEnabled': overlayEnabled,
    'presets': [for (final p in presets) p.toJson()],
  };
}

/// What the background service receives when it starts. A run's clock starts
/// when the service does, so the quick-settings tile can restart the same
/// configuration later.
class BackgroundConfig {
  const BackgroundConfig({
    required this.plan,
    this.alerts = const [],
    this.overlay = false,
    this.accessMode = AccessMode.auto,
    this.retentionDays = 7,
    this.presetName,
  });

  factory BackgroundConfig.fromJson(Map<String, Object?> json) =>
      BackgroundConfig(
        plan: ScanPlan.fromJson((json['plan'] as Map).cast<String, Object?>()),
        alerts: [
          for (final a in json['alerts'] as List? ?? const [])
            AlertRule.fromJson((a as Map).cast<String, Object?>()),
        ],
        overlay: json['overlay'] as bool? ?? false,
        accessMode:
            AccessMode.values.asNameMap()[json['accessMode']] ??
            AccessMode.auto,
        retentionDays: (json['retentionDays'] as num?)?.toInt() ?? 7,
        presetName: json['presetName'] as String?,
      );

  final ScanPlan plan;
  final List<AlertRule> alerts;
  final bool overlay;
  final AccessMode accessMode;
  final int retentionDays;
  final String? presetName;

  Map<String, Object?> toJson() => {
    'plan': plan.toJson(),
    'alerts': [for (final a in alerts) a.toJson()],
    'overlay': overlay,
    'accessMode': accessMode.name,
    'retentionDays': retentionDays,
    if (presetName != null) 'presetName': presetName,
  };
}
