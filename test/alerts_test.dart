import 'package:flutter_test/flutter_test.dart';
import 'package:turbomon/models/readings.dart';
import 'package:turbomon/models/settings.dart';
import 'package:turbomon/services/alerts.dart';

SystemSample cpuAt(DateTime t, double percent) => SystemSample(
  time: t,
  cpu: CpuReading(totalPercent: percent),
);

void main() {
  final t0 = DateTime(2026, 10, 10, 12);
  final rule = AlertRule.defaults(
    AlertMetric.cpu,
  ).copyWith(enabled: true, threshold: 80, durationSeconds: 60);

  test('fires once the value was held for the duration, then re-arms', () {
    final e = AlertEvaluator([rule]);
    expect(e.check(cpuAt(t0, 90)), isEmpty);
    expect(e.check(cpuAt(t0.add(const Duration(seconds: 30)), 95)), isEmpty);
    final fired = e.check(
      cpuAt(t0.add(const Duration(seconds: 60)), 92),
      culprit: 'com.example',
    );
    expect(fired, hasLength(1));
    expect(fired.single.text, contains('com.example'));
    expect(fired.single.title, 'CPU load above 80 %');
    // Still high: no repeat.
    expect(e.check(cpuAt(t0.add(const Duration(seconds: 120)), 99)), isEmpty);
    // Drops, climbs again, fires again after another minute.
    expect(e.check(cpuAt(t0.add(const Duration(seconds: 130)), 10)), isEmpty);
    expect(e.check(cpuAt(t0.add(const Duration(seconds: 140)), 90)), isEmpty);
    expect(
      e.check(cpuAt(t0.add(const Duration(seconds: 200)), 90)),
      hasLength(1),
    );
  });

  test('a dip resets the timer', () {
    final e = AlertEvaluator([rule]);
    e.check(cpuAt(t0, 90));
    e.check(cpuAt(t0.add(const Duration(seconds: 50)), 20));
    expect(e.check(cpuAt(t0.add(const Duration(seconds: 70)), 90)), isEmpty);
  });

  test('disabled rules and missing values never fire', () {
    final e = AlertEvaluator([rule.copyWith(enabled: false)]);
    expect(e.rules, isEmpty);
    final on = AlertEvaluator([rule]);
    expect(on.check(SystemSample(time: t0)), isEmpty);
  });

  test('values per metric', () {
    final s = SystemSample(
      time: t0,
      memory: const MemoryReading(totalBytes: 100, availableBytes: 5),
      battery: const BatteryReading(currentMa: -900, temperatureC: 39),
      thermal: const ThermalReading(zones: [ThermalZone('cpu', 47)]),
    );
    expect(AlertEvaluator.valueOf(AlertMetric.ram, s), 95);
    expect(AlertEvaluator.valueOf(AlertMetric.batteryDrain, s), 900);
    expect(AlertEvaluator.valueOf(AlertMetric.temperature, s), 47);
    expect(AlertEvaluator.valueOf(AlertMetric.cpu, s), isNull);
  });
}
