import '../models/readings.dart';

enum ProcessSort {
  pid('PID'),
  name('Name'),
  user('User'),
  uid('UID'),
  cpu('CPU %'),
  rss('RSS'),
  state('State'),
  battery('mAh');

  const ProcessSort(this.label);
  final String label;
}

/// Inclusive bounds. Missing readings only match when no bound is set.
class ProcessRange {
  const ProcessRange({this.min, this.max});

  final num? min;
  final num? max;
  bool get active => min != null || max != null;
  bool get valid =>
      (min == null || (min!.isFinite && min! >= 0)) &&
      (max == null || (max!.isFinite && max! >= 0)) &&
      (min == null || max == null || min! <= max!);

  bool matches(num? value) =>
      !active ||
      (valid &&
          value != null &&
          value.isFinite &&
          (min == null || value >= min!) &&
          (max == null || value <= max!));
}

class ProcessFilters {
  const ProcessFilters({
    this.name = '',
    this.user = '',
    this.state = '',
    this.pid = const ProcessRange(),
    this.uid = const ProcessRange(),
    this.cpu = const ProcessRange(),
    this.rssMiB = const ProcessRange(),
    this.battery = const ProcessRange(),
  });

  final String name, user, state;
  final ProcessRange pid, uid, cpu, rssMiB, battery;

  bool get active =>
      [name, user, state].any((s) => s.trim().isNotEmpty) ||
      [pid, uid, cpu, rssMiB, battery].any((r) => r.active);

  bool matches(ProcessInfo p) =>
      _contains(p.name, name) &&
      _contains(p.user, user) &&
      _contains(p.state, state) &&
      pid.matches(p.pid) &&
      uid.matches(p.uid) &&
      cpu.matches(p.cpuPercent) &&
      rssMiB.matches(p.rssBytes / (1024 * 1024)) &&
      battery.matches(p.batteryMah);
}

bool _contains(String value, String query) =>
    value.toLowerCase().contains(query.trim().toLowerCase());

/// Filters the entire sample, then sorts a copy. Unknown values stay last
/// in either direction; PID breaks ties so live rows do not shuffle randomly.
List<ProcessInfo> selectProcesses(
  Iterable<ProcessInfo> processes, {
  String query = '',
  ProcessFilters filters = const ProcessFilters(),
  ProcessSort sort = ProcessSort.cpu,
  bool ascending = false,
}) {
  final needle = query.trim().toLowerCase();
  final rows = processes.where((p) {
    return filters.matches(p) &&
        (needle.isEmpty ||
            [
              p.name,
              '${p.pid}',
              p.user,
              '${p.uid ?? ''}',
              p.state,
            ].any((s) => s.toLowerCase().contains(needle)));
  }).toList();

  Object? value(ProcessInfo p) => switch (sort) {
    ProcessSort.pid => p.pid,
    ProcessSort.name => p.name.toLowerCase(),
    ProcessSort.user => p.user.toLowerCase(),
    ProcessSort.uid => p.uid,
    ProcessSort.cpu => p.cpuPercent.isFinite ? p.cpuPercent : null,
    ProcessSort.rss => p.rssBytes,
    ProcessSort.state => p.state.toLowerCase(),
    ProcessSort.battery => p.batteryMah?.isFinite == true ? p.batteryMah : null,
  };

  rows.sort((a, b) {
    final av = value(a), bv = value(b);
    if (av == null && bv != null) return 1;
    if (bv == null && av != null) return -1;
    final compared = av == null
        ? 0
        : av is num
        ? av.compareTo(bv as num)
        : (av as String).compareTo(bv as String);
    return compared == 0
        ? a.pid.compareTo(b.pid)
        : ascending
        ? compared
        : -compared;
  });
  return rows;
}
