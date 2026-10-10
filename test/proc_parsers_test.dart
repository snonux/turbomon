import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turbomon/services/proc_parsers.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  group('meminfo', () {
    test('parses kB into bytes and builds a reading', () {
      final info = parseMeminfo(fixture('meminfo.txt'));
      expect(info['MemTotal'], greaterThan(1 << 30));
      final m = memoryFromMeminfo(info)!;
      expect(m.availableBytes, info['MemAvailable']);
      expect(m.usedPercent, inInclusiveRange(0, 100));
      expect(m.cachedBytes, info['Cached']);
    });

    test('falls back to free + cached without MemAvailable', () {
      final m = memoryFromMeminfo(
        parseMeminfo(
          'MemTotal: 1000 kB\nMemFree: 100 kB\nCached: 200 kB\nBuffers: 50 kB\n',
        ),
      )!;
      expect(m.availableBytes, 350 * 1024);
    });

    test('is null without MemTotal', () {
      expect(memoryFromMeminfo(parseMeminfo('MemFree: 1 kB')), isNull);
    });
  });

  group('/proc/stat', () {
    test('reads aggregate and every core from a real capture', () {
      final before = parseProcStat(fixture('stat_before.txt'));
      final after = parseProcStat(fixture('stat_after.txt'));
      expect(before.keys, containsAll([-1, 0, 1, 2, 3]));
      final total = after[-1]!.percentSince(before[-1]!);
      expect(total, inInclusiveRange(0, 100));
    });

    test('counts iowait as idle and ignores guest columns', () {
      final a = parseProcStat('cpu  100 0 100 700 100 0 0 0 50 50');
      final b = parseProcStat('cpu  200 0 200 800 200 0 0 0 99 99');
      // busy +200, idle (+100 idle +100 iowait) +200 -> 50 %.
      expect(b[-1]!.percentSince(a[-1]!), 50);
    });

    test('a counter going backwards reads as 0, not negative', () {
      final a = parseProcStat('cpu 10 0 10 10');
      final b = parseProcStat('cpu 5 0 5 5');
      expect(b[-1]!.percentSince(a[-1]!), 0);
    });
  });

  test('loadavg', () {
    expect(parseLoadavg(fixture('loadavg.txt')), hasLength(3));
    expect(parseLoadavg('garbage'), isNull);
  });

  group('top', () {
    test('quiet output uses the requested default columns', () {
      final rows = parseTop(fixture('top_quiet.txt'));
      expect(rows, isNotEmpty);
      final server = rows.firstWhere((p) => p.name == 'system_server');
      expect(server.user, 'system');
      expect(server.rssBytes, greaterThan(100 << 20));
      // Sorted by CPU, highest first.
      for (var i = 1; i < rows.length; i++) {
        expect(
          rows[i - 1].cpuPercent,
          greaterThanOrEqualTo(rows[i].cpuPercent),
        );
      }
      // Kernel threads and names with spaces survive.
      expect(rows.any((p) => p.name.startsWith('[kworker')), isTrue);
      expect(rows.any((p) => p.name.contains(' ')), isTrue);
    });

    test('header output with the sort marker glued to a column', () {
      final rows = parseTop(fixture('top_header.txt'));
      expect(rows.map((p) => p.name), contains('system_server'));
      final app = rows.firstWhere((p) => p.user.startsWith('u0_a'));
      expect(app.uid, greaterThan(10000));
    });

    test('sizes with units', () {
      expect(parseSizeWithUnit('4.9M'), (4.9 * (1 << 20)).round());
      expect(parseSizeWithUnit('1G'), 1 << 30);
      expect(parseSizeWithUnit('512'), 512 * 1024);
      expect(parseSizeWithUnit('0'), 0);
      expect(parseSizeWithUnit('?'), 0);
    });
  });

  test('diskstats sums whole disks only', () {
    final c = parseDiskstats(fixture('diskstats.txt'))!;
    // sda + mmcblk0; partitions, loop, zram and dm-0 skipped.
    expect(c.reads, 120000 + 500);
    expect(c.readSectors, 9600000 + 4000);
    expect(c.writeSectors, 6400000 + 800);
    expect(parseDiskstats(''), isNull);
  });

  test('/proc/self/io', () {
    final io = parseProcIo(
      'rchar: 1\nwchar: 2\nread_bytes: 4096\nwrite_bytes: 8192\n',
    )!;
    expect(io.read, 4096);
    expect(io.write, 8192);
    expect(parseProcIo('rchar: 1'), isNull);
  });

  group('thermal', () {
    test('millidegrees, degrees and implausible values', () {
      expect(parseThermalTemp('41500'), 41.5);
      expect(parseThermalTemp('38'), 38);
      expect(parseThermalTemp('-273000'), isNull);
      expect(parseThermalTemp('0'), isNull);
      expect(parseThermalTemp('n/a'), isNull);
    });

    test('zone lines', () {
      final zones = parseThermalZones(
        'cpu-0-0\t45000\nbattery\t31000\nbroken\t\n',
      );
      expect(zones.map((z) => z.name), ['cpu-0-0', 'battery']);
    });
  });

  test('GPU busy formats of each vendor', () {
    expect(parseGpuBusy('42 %'), 42); // Adreno gpu_busy_percentage
    expect(parseGpuBusy('17'), 17); // Mali utilization
    expect(parseGpuBusy('250 1000'), 25); // Adreno gpubusy
    expect(parseGpuBusy('0 0'), 0);
    expect(parseGpuBusy('300'), isNull);
  });

  test('batterystats power per uid', () {
    final power = parseBatteryStatsPower(fixture('batterystats_uids.txt'));
    expect(power[10167], 52.1);
    expect(power[1000], 41.7);
    expect(power[10130], 12.03);
    expect(power[10 * 100000 + 10012], 3.5);
    expect(power[0], 9.0);
  });

  test('splitSections', () {
    final s = splitSections('junk\n@@ a\n1\n2\n@@ b\n3\n', '@@');
    expect(s['a'], '1\n2\n');
    expect(s['b'], '3\n\n');
  });
}
