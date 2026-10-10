import '../model/settings.dart';

enum AlertKind {
  cpu('High CPU', '%'),
  temperature('High temperature', '°C'),
  drain('Fast battery drain', 'mA'),
  ram('High RAM use', '%');

  const AlertKind(this.title, this.unit);
  final String title;
  final String unit;
}

class FiredAlert {
  const FiredAlert(this.kind, this.value, this.limit, this.at, this.since);
  final AlertKind kind;
  final double value;
  final double limit;
  final DateTime at;
  final DateTime since;

  String get message =>
      '${kind.title}: ${value.toStringAsFixed(0)} ${kind.unit} '
      '(limit ${limit.toStringAsFixed(0)} ${kind.unit}) for '
      '${at.difference(since).inSeconds} s';

  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'value': double.parse(value.toStringAsFixed(1)),
        'limit': limit,
        'at': at.toUtc().toIso8601String(),
        'since': since.toUtc().toIso8601String(),
      };
}

/// Fires an alert once a value has stayed over its limit for the sustain
/// time, then stays quiet for [cooldown] so one long spike is one alert.
class AlertEvaluator {
  AlertEvaluator({this.cooldown = const Duration(minutes: 10)});

  final Duration cooldown;
  final Map<AlertKind, DateTime> _overSince = {};
  final Map<AlertKind, DateTime> _lastFired = {};

  List<FiredAlert> check(
    AlertRules rules,
    DateTime now, {
    double? cpuPercent,
    double? tempC,
    double? drainMa,
    double? ramPercent,
  }) {
    final out = <FiredAlert>[];
    void one(AlertKind kind, bool enabled, double? value, double limit) {
      if (!enabled || value == null || value < limit) {
        _overSince.remove(kind);
        return;
      }
      final since = _overSince.putIfAbsent(kind, () => now);
      if (now.difference(since).inSeconds < rules.sustainSeconds) return;
      final last = _lastFired[kind];
      if (last != null && now.difference(last) < cooldown) return;
      _lastFired[kind] = now;
      out.add(FiredAlert(kind, value, limit, now, since));
    }

    one(AlertKind.cpu, rules.cpuEnabled, cpuPercent, rules.cpuPercent);
    one(AlertKind.temperature, rules.tempEnabled, tempC, rules.tempC);
    one(AlertKind.drain, rules.drainEnabled, drainMa, rules.drainMa);
    one(AlertKind.ram, rules.ramEnabled, ramPercent, rules.ramPercent);
    return out;
  }
}
