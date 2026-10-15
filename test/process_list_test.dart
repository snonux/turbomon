import 'package:flutter_test/flutter_test.dart';
import 'package:turbomon/models/readings.dart';
import 'package:turbomon/services/process_list.dart';

const rows = [
  ProcessInfo(
    pid: 10,
    user: 'u0_a2',
    name: 'Alpha',
    cpuPercent: 150,
    rssBytes: 512 << 20,
    state: 'R',
    batteryMah: 4,
  ),
  ProcessInfo(
    pid: 2,
    user: 'root',
    name: 'beta',
    cpuPercent: 2,
    rssBytes: 16 << 20,
    state: 'S',
    batteryMah: 0,
  ),
  ProcessInfo(
    pid: 30,
    user: 'unknown',
    name: 'Gamma',
    cpuPercent: 2,
    rssBytes: 128 << 20,
    state: 'I',
  ),
];

void main() {
  final ascending = {
    ProcessSort.pid: [2, 10, 30],
    ProcessSort.name: [10, 2, 30],
    ProcessSort.user: [2, 10, 30],
    ProcessSort.uid: [2, 10, 30],
    ProcessSort.cpu: [2, 30, 10],
    ProcessSort.rss: [2, 30, 10],
    ProcessSort.state: [30, 10, 2],
    ProcessSort.battery: [2, 10, 30],
  };
  final descending = {
    ProcessSort.pid: [30, 10, 2],
    ProcessSort.name: [30, 2, 10],
    ProcessSort.user: [30, 10, 2],
    ProcessSort.uid: [10, 2, 30],
    ProcessSort.cpu: [10, 2, 30],
    ProcessSort.rss: [10, 30, 2],
    ProcessSort.state: [2, 10, 30],
    ProcessSort.battery: [10, 2, 30],
  };
  for (final field in ProcessSort.values) {
    test(
      'sort ${field.label} both directions, missing last and ties by PID',
      () {
        expect(
          selectProcesses(rows, sort: field, ascending: true).map((p) => p.pid),
          ascending[field],
        );
        expect(
          selectProcesses(rows, sort: field).map((p) => p.pid),
          descending[field],
        );
        expect(rows.map((p) => p.pid), [
          10,
          2,
          30,
        ], reason: 'Source order is untouched');
      },
    );
  }

  test('search covers names, PIDs, users, UIDs and states ignoring case', () {
    for (final query in [' ALPHA ', '10', 'U0_A2', '10002']) {
      expect(selectProcesses(rows, query: query).map((p) => p.pid), [10]);
    }
    expect(selectProcesses(rows, query: 'i').map((p) => p.pid), [30]);
    expect(selectProcesses(rows, query: 'absent'), isEmpty);
    expect(selectProcesses(const []), isEmpty);
  });

  test('all field filters combine and boundaries are inclusive', () {
    const filters = ProcessFilters(
      name: 'ALP',
      user: 'a2',
      state: 'r',
      pid: ProcessRange(min: 10, max: 10),
      uid: ProcessRange(min: 10002, max: 10002),
      cpu: ProcessRange(min: 150, max: 200),
      rssMiB: ProcessRange(min: 512, max: 512),
      battery: ProcessRange(min: 4, max: 4),
    );
    expect(filters.active, isTrue);
    expect(selectProcesses(rows, filters: filters).map((p) => p.pid), [10]);
    expect(selectProcesses(rows, query: 'beta', filters: filters), isEmpty);
  });

  test('each numeric filter rejects readings outside its range', () {
    for (final filter in const [
      ProcessFilters(pid: ProcessRange(min: 100)),
      ProcessFilters(uid: ProcessRange(min: 20000)),
      ProcessFilters(cpu: ProcessRange(max: 1)),
      ProcessFilters(rssMiB: ProcessRange(max: 1)),
      ProcessFilters(battery: ProcessRange(min: 5)),
    ]) {
      expect(selectProcesses(rows, filters: filter), isEmpty);
    }
  });

  test('zero differs from missing; unset ranges include missing values', () {
    expect(const ProcessFilters().active, isFalse);
    expect(selectProcesses(rows), hasLength(3));
    expect(
      selectProcesses(
        rows,
        filters: const ProcessFilters(battery: ProcessRange(max: 0)),
      ).map((p) => p.pid),
      [2],
    );
    expect(
      selectProcesses(
        rows,
        filters: const ProcessFilters(uid: ProcessRange(min: 0)),
      ).map((p) => p.pid),
      [10, 2],
    );
  });

  test('invalid and non-finite ranges do not accidentally match rows', () {
    for (final range in [
      const ProcessRange(min: 2, max: 1),
      const ProcessRange(min: -1),
      const ProcessRange(max: double.nan),
      const ProcessRange(min: double.infinity),
    ]) {
      expect(range.valid, isFalse);
      expect(range.matches(0), isFalse);
      expect(range.matches(null), isFalse);
    }
  });

  test('non-finite measurements sort last and cannot match numeric bounds', () {
    const invalid = ProcessInfo(
      pid: 1,
      user: 'shell',
      name: 'Invalid',
      cpuPercent: double.nan,
      rssBytes: 0,
      state: 'S',
      batteryMah: double.infinity,
    );
    for (final sort in [ProcessSort.cpu, ProcessSort.battery]) {
      for (final up in [true, false]) {
        expect(
          selectProcesses(
            [invalid, rows.first],
            sort: sort,
            ascending: up,
          ).last,
          same(invalid),
        );
      }
    }
    expect(const ProcessRange(min: 0).matches(double.nan), isFalse);
  });
}
