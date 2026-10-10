import '../models/readings.dart';
import '../models/settings.dart';

/// An alert that crossed its limit for long enough.
class FiredAlert {
  const FiredAlert({
    required this.rule,
    required this.value,
    required this.time,
    this.culprit,
  });

  final AlertRule rule;
  final double value;
  final DateTime time;

  /// The top process at the time, when Shizuku or root can tell.
  final String? culprit;

  String get title =>
      '${rule.metric.label} above '
      '${rule.threshold.toStringAsFixed(0)} ${rule.metric.unit}';

  String get text {
    final base =
        '${rule.metric.label} was ${value.toStringAsFixed(0)} '
        '${rule.metric.unit} for ${rule.durationSeconds} s.';
    return culprit == null ? base : '$base Top process: $culprit.';
  }

  Map<String, Object?> toJson() => {
    'metric': rule.metric.name,
    'threshold': rule.threshold,
    'durationSeconds': rule.durationSeconds,
    'value': double.parse(value.toStringAsFixed(1)),
    'time': time.toIso8601String(),
    if (culprit != null) 'culprit': culprit,
  };
}

/// Tracks how long each enabled rule has been over its threshold. A rule
/// fires once per excursion and re-arms when the value drops back below.
class AlertEvaluator {
  AlertEvaluator(Iterable<AlertRule> rules)
    : rules = [
        for (final r in rules)
          if (r.enabled) r,
      ];

  final List<AlertRule> rules;
  final _since = <AlertMetric, DateTime>{};
  final _fired = <AlertMetric>{};

  static double? valueOf(AlertMetric metric, SystemSample s) =>
      switch (metric) {
        AlertMetric.cpu => s.cpu?.load,
        AlertMetric.temperature => _hottest(s),
        AlertMetric.batteryDrain => s.battery?.drainMa,
        AlertMetric.ram => s.memory?.usedPercent,
      };

  static double? _hottest(SystemSample s) {
    final values = [s.thermal?.hottest, s.battery?.temperatureC].nonNulls;
    return values.isEmpty ? null : values.reduce((a, b) => a > b ? a : b);
  }

  List<FiredAlert> check(SystemSample sample, {String? culprit}) {
    final fired = <FiredAlert>[];
    for (final rule in rules) {
      final value = valueOf(rule.metric, sample);
      if (value == null) continue;
      if (value < rule.threshold) {
        _since.remove(rule.metric);
        _fired.remove(rule.metric);
        continue;
      }
      final since = _since.putIfAbsent(rule.metric, () => sample.time);
      final held =
          sample.time.difference(since).inSeconds >= rule.durationSeconds;
      if (held && _fired.add(rule.metric)) {
        fired.add(
          FiredAlert(
            rule: rule,
            value: value,
            time: sample.time,
            culprit: culprit,
          ),
        );
      }
    }
    return fired;
  }
}
