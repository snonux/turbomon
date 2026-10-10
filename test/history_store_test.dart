import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turbomon/background/history_record.dart';
import 'package:turbomon/models/readings.dart';
import 'package:turbomon/services/history_store.dart';
import 'package:turbomon/services/monitor_hub.dart';

void main() {
  late Directory dir;
  late HistoryStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('turbomon-history');
    store = HistoryStore(dir);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  Map<String, Object?> at(DateTime t, double cpu) => {
    't': t.millisecondsSinceEpoch,
    'cpu': cpu,
  };

  test('one file per day, read back in order within the window', () async {
    await store.append(at(DateTime(2026, 10, 9, 23, 59), 1));
    await store.append(at(DateTime(2026, 10, 10, 0, 1), 2));
    await store.append(at(DateTime(2026, 10, 10, 8), 3));
    expect(dir.listSync().map((f) => f.uri.pathSegments.last).toSet(), {
      '2026-10-09.jsonl',
      '2026-10-10.jsonl',
    });
    final read = await store.read(
      since: DateTime(2026, 10, 9, 23),
      until: DateTime(2026, 10, 10, 1),
    );
    expect(read.map((r) => r['cpu']), [1, 2]);
  });

  test('a truncated line is skipped', () async {
    await store.append(at(DateTime(2026, 10, 10, 1), 1));
    File(
      '${dir.path}/2026-10-10.jsonl',
    ).writeAsStringSync('{"t": 17', mode: FileMode.append);
    final read = await store.read(
      since: DateTime(2026, 10, 10),
      until: DateTime(2026, 10, 11),
    );
    expect(read, hasLength(1));
  });

  test('prune deletes days past retention', () async {
    await store.append(at(DateTime(2026, 10, 1), 1));
    await store.append(at(DateTime(2026, 10, 9), 1));
    await store.prune(7, DateTime(2026, 10, 10, 12));
    expect(dir.listSync().map((f) => f.uri.pathSegments.last), [
      '2026-10-09.jsonl',
    ]);
  });

  test('records drop nulls and rebuild into series', () {
    final t = DateTime(2026, 10, 10, 12);
    final r = historyRecord(
      SystemSample(
        time: t,
        cpu: const CpuReading(totalPercent: 33.333),
        battery: const BatteryReading(
          percent: 80,
          currentMa: -300,
          voltageMv: 4000,
        ),
      ),
      processes: const [
        ProcessInfo(
          pid: 1,
          user: 'u0_a1',
          name: 'app',
          cpuPercent: 25,
          rssBytes: 0,
          state: 'R',
        ),
      ],
    );
    expect(r['cpu'], 33.3);
    expect(r['cpuProxy'], isFalse);
    expect(r.containsKey('gpu'), isFalse);
    expect(r['batW'], -1.2);
    final series = seriesFromHistory([r]);
    expect(series[SeriesKey.cpu]!.latest!.value, 33.3);
    expect(series[SeriesKey.batteryPercent]!.latest!.value, 80);
    expect(processAveragesFromHistory([r, r])['app']!.average, 25);
    expect(historyCpuIsProxy([r]), isFalse);
  });
}
