import 'package:flutter_test/flutter_test.dart';
import 'package:turbomon/parsers/proc_parsers.dart';

import '../fakes/samples.dart';

void main() {
  group('parseMemInfo', () {
    test('reads the fields TurboMon uses from a real capture', () {
      final m = parseMemInfo(meminfoSample)!;
      expect(m.totalKb, 7799096);
      expect(m.availableKb, 2843520);
      expect(m.cachedKb, 2715660);
      expect(m.swapTotalKb, 4194300);
      expect(m.swapFreeKb, 2560972);
      expect(m.usedKb, 7799096 - 2843520);
      expect(m.usedPercent, closeTo(63.54, 0.01));
    });

    test('does not confuse Active(anon) style keys with plain ones', () {
      final m = parseMemInfo('MemTotal: 1000 kB\nActive(anon): 999 kB\nMemAvailable: 400 kB\n')!;
      expect(m.availableKb, 400);
    });

    test('falls back to Free + Cached + Buffers on kernels without MemAvailable', () {
      final m = parseMemInfo('MemTotal: 1000 kB\nMemFree: 100 kB\nBuffers: 50 kB\nCached: 250 kB\n')!;
      expect(m.availableKb, 400);
      expect(m.usedKb, 600);
      expect(m.swapTotalKb, 0);
    });

    test('returns null without MemTotal or for empty text', () {
      expect(parseMemInfo(''), isNull);
      expect(parseMemInfo('MemFree: 100 kB\n'), isNull);
    });

    test('usedPercent is 0 for a zero total instead of NaN', () {
      final m = parseMemInfo('MemTotal: 0 kB\nMemAvailable: 0 kB\n')!;
      expect(m.usedPercent, 0);
    });
  });

  group('parseProcStat and cpuPercentBetween', () {
    test('parses the aggregate line and every online core', () {
      final s = parseProcStat(procStatBefore);
      expect(s.keys, unorderedEquals(['cpu', 'cpu0', 'cpu1', 'cpu7']));
      // user nice system idle iowait irq softirq steal = 9900, idle+iowait = 8200.
      expect(s['cpu']!.total, 9900);
      expect(s['cpu']!.busy, 1700);
    });

    test('guest time is not double counted', () {
      final s = parseProcStat('cpu  10 0 10 80 0 0 0 0 50 7\n');
      expect(s['cpu']!.total, 100);
      expect(s['cpu']!.busy, 20);
    });

    test('accepts old kernels with only four counters', () {
      final s = parseProcStat('cpu 30 0 20 50\n');
      expect(s['cpu']!.total, 100);
      expect(s['cpu']!.busy, 50);
    });

    test('skips short or malformed cpu lines', () {
      expect(parseProcStat('cpu 1 2\ncpufoo a b c d e\n'), isEmpty);
    });

    test('computes percentages per key and drops offline cores', () {
      final pct = cpuPercentBetween(parseProcStat(procStatBefore), parseProcStat(procStatAfter));
      expect(pct['cpu'], closeTo(66.67, 0.01));
      expect(pct['cpu0'], closeTo(75, 0.001));
      expect(pct['cpu1'], closeTo(7.5, 0.001));
      expect(pct.containsKey('cpu7'), isFalse);
    });

    test('skips keys with no time passing or counters going backwards', () {
      final a = {'cpu': const CpuTimes(100, 1000), 'cpu0': const CpuTimes(10, 100)};
      final b = {'cpu': const CpuTimes(100, 1000), 'cpu0': const CpuTimes(5, 50), 'cpu1': const CpuTimes(1, 2)};
      expect(cpuPercentBetween(a, b), isEmpty);
    });

    test('clamps to 0..100', () {
      final pct = cpuPercentBetween(
        {'cpu': const CpuTimes(100, 1000)},
        {'cpu': const CpuTimes(400, 1100)},
      );
      expect(pct['cpu'], 100);
    });
  });

  group('CoreFreq', () {
    test('percentOfMax', () {
      expect(const CoreFreq(core: 0, curKhz: 1500000, maxKhz: 2000000).percentOfMax, 75);
      expect(const CoreFreq(core: 0, curKhz: 2500000, maxKhz: 2000000).percentOfMax, 100);
      expect(const CoreFreq(core: 0, curKhz: 1000, maxKhz: 0).percentOfMax, 0);
    });
  });

  group('disk stats', () {
    test('isWholeDisk keeps whole disks only', () {
      for (final yes in ['sda', 'sdb', 'sdaa', 'mmcblk0', 'mmcblk1', 'nvme0n1', 'vda', 'vdb']) {
        expect(isWholeDisk(yes), isTrue, reason: yes);
      }
      for (final no in [
        'sda1', 'sdb12', 'mmcblk0p1', 'mmcblk0boot0', 'mmcblk0rpmb', 'nvme0n1p2', 'loop0', 'loop12',
        'ram0', 'zram0', 'dm-0', 'dm-12', 'md0', 'vda1', 'sr0',
      ]) {
        expect(isWholeDisk(no), isFalse, reason: no);
      }
    });

    test('parseDiskStats reads the right columns of whole disks', () {
      final d = parseDiskStats(diskstatsBefore);
      expect(d.map((e) => e.device), ['sda', 'sdb', 'mmcblk0']);
      final sda = d.first;
      expect(sda.readsCompleted, 120000);
      expect(sda.sectorsRead, 9600000);
      expect(sda.writesCompleted, 80000);
      expect(sda.sectorsWritten, 6400000);
    });

    test('parseDiskStats ignores blank and short lines', () {
      expect(parseDiskStats('\n  \n8 0 sda 1 2\n'), isEmpty);
    });

    test('diskRatesBetween uses 512-byte sectors and elapsed time', () {
      final r = diskRatesBetween(
        parseDiskStats(diskstatsBefore),
        parseDiskStats(diskstatsAfter),
        const Duration(seconds: 2),
      );
      expect(r.map((e) => e.device), ['sda', 'sdb', 'mmcblk0']);
      final sda = r.first;
      expect(sda.readBytesPerSec, 20480 * 512 / 2);
      expect(sda.writeBytesPerSec, 20480 * 512 / 2);
      expect(sda.readOpsPerSec, 100);
      expect(sda.writeOpsPerSec, 50);
      expect(r[1].readBytesPerSec, 0);
    });

    test('diskRatesBetween: counter resets give 0, new devices and zero time are skipped', () {
      const before = [
        DiskCounters(device: 'sda', readsCompleted: 100, sectorsRead: 1000, writesCompleted: 100, sectorsWritten: 1000),
      ];
      const after = [
        DiskCounters(device: 'sda', readsCompleted: 5, sectorsRead: 10, writesCompleted: 110, sectorsWritten: 1100),
        DiskCounters(device: 'sdb', readsCompleted: 5, sectorsRead: 10, writesCompleted: 5, sectorsWritten: 10),
      ];
      final r = diskRatesBetween(before, after, const Duration(seconds: 1));
      expect(r, hasLength(1));
      expect(r.single.readBytesPerSec, 0);
      expect(r.single.readOpsPerSec, 0);
      expect(r.single.writeBytesPerSec, 100 * 512);
      expect(diskRatesBetween(before, after, Duration.zero), isEmpty);
    });
  });

  group('parsePidStats', () {
    test('handles spaces and parentheses in the command name', () {
      final s = parsePidStats(pidStatsSample);
      expect(s.map((e) => e.pid), [1, 212, 4321, 5555, 6666]);
      expect(s.map((e) => e.comm), ['init', 'kworker/u16:3', 'Binder:4321_2', 'com.example (x)', 'HwBinder: 1)']);
      final app = s[3];
      expect(app.state, 'R');
      expect(app.ticks, 1000);
      expect(app.rssPages, 51200);
      expect(s[0].ticks, 460);
      expect(s[0].rssPages, 1024);
      expect(s[4].state, 'S');
      expect(s[4].ticks, 3);
    });

    test('skips truncated lines and lines without a pid', () {
      final text = [
        '77 (gone) Z 1 2 3', // process exited mid-read
        '(nopid) S ${List.filled(30, '0').join(' ')}',
        'abc (x) S ${List.filled(30, '0').join(' ')}',
        '',
        pidStatLine(9, 'ok', 'S', 1, 1, 1),
      ].join('\n');
      expect(parsePidStats(text).map((e) => e.pid), [9]);
    });
  });

  group('parsePsNames', () {
    test('maps pid to user and full name, skipping the header', () {
      final n = parsePsNames(psSample);
      expect(n[1], ('root', 'init'));
      expect(n[5555], ('u0_a174', 'com.example.app'));
      expect(n[6666], ('u0_a12', 'com.android.phone with space'));
      expect(n.length, 5);
    });

    test('survives the leading newline left by the @@TM@@ separator', () {
      final n = parsePsNames('\n$psSample');
      expect(n[4321], ('system', 'system_server'));
    });

    test('ignores short lines', () {
      expect(parsePsNames('PID USER NAME\n12 root\n'), isEmpty);
    });
  });

  group('parseGpuBusy', () {
    test('every probed path has a parser that understands its format', () {
      const samples = {
        '/sys/class/kgsl/kgsl-3d0/gpu_busy_percentage': '37 %\n',
        '/sys/class/kgsl/kgsl-3d0/gpubusy': '  370000  1000000\n',
        '/sys/kernel/gpu/gpu_busy': '37 %\n',
        '/sys/class/misc/mali0/device/utilization': '37\n',
        '/sys/devices/platform/mali.0/utilization': '37\n',
        '/sys/module/ged/parameters/gpu_loading': '37\n',
      };
      expect(samples.keys.toSet(), gpuBusyPaths.toSet());
      for (final p in gpuBusyPaths) {
        expect(parseGpuBusy(p, samples[p]!), closeTo(37, 0.001), reason: p);
      }
    });

    test('Adreno gpubusy counters', () {
      const p = '/sys/class/kgsl/kgsl-3d0/gpubusy';
      expect(parseGpuBusy(p, '0 0'), isNull); // idle GPU, no window yet
      expect(parseGpuBusy(p, '5'), isNull);
      expect(parseGpuBusy(p, 'x y'), isNull);
      expect(parseGpuBusy(p, '1500 1000'), 100);
      expect(parseGpuBusy(p, '0 1000'), 0);
    });

    test('percentage forms', () {
      const p = '/sys/class/kgsl/kgsl-3d0/gpu_busy_percentage';
      expect(parseGpuBusy(p, '0 %'), 0);
      expect(parseGpuBusy(p, '12.5'), 12.5);
      expect(parseGpuBusy(p, '100'), 100);
      expect(parseGpuBusy(p, '250'), isNull);
      expect(parseGpuBusy(p, ''), isNull);
      expect(parseGpuBusy(p, '  \n'), isNull);
      expect(parseGpuBusy(p, 'n/a'), isNull);
    });
  });

  group('parseThermalZones', () {
    test('millidegrees, whole degrees, negatives and bogus sensors', () {
      final z = parseThermalZones(thermalSample);
      final byType = {for (final e in z) e.type: e.celsius};
      expect(byType['cpu-0-0-usr'], closeTo(41.2, 1e-9));
      expect(byType['cpu-1-0-usr'], closeTo(48.9, 1e-9));
      expect(byType['gpuss-0-usr'], closeTo(39.5, 1e-9));
      expect(byType['battery'], 31);
      expect(byType['xo-therm'], closeTo(33.6, 1e-9));
      expect(byType['pa-therm0'], -5);
      expect(byType.containsKey('sdm-therm'), isFalse);
      expect(byType.containsKey('tsens_tz_sensor_bogus'), isFalse);
      expect(byType.containsKey('skin'), isFalse);
      expect(z, hasLength(6));
    });

    test('ignores lines without a type', () {
      expect(parseThermalZones('=41000\nnoequals\n'), isEmpty);
    });

    test('the shell command prints type=temp per zone', () {
      expect(thermalZonesCommand, contains(r'$(cat $z/type)=$(cat $z/temp)'));
    });
  });

  group('parseBatteryStatsPerUid', () {
    test('sums Android 12+ and older formats per uid', () {
      final m = parseBatteryStatsPerUid(batteryStatsSample);
      expect(m['u0a174'], closeTo(220.0, 1e-9));
      expect(m['1000'], closeTo(88.1, 1e-9));
      expect(m['u0a12'], closeTo(5.67, 1e-9));
      expect(m['u10a5'], 1.5);
      expect(m.length, 4);
    });

    test('empty input gives an empty map', () {
      expect(parseBatteryStatsPerUid(''), isEmpty);
    });
  });

  group('uidFromAndroidName', () {
    test('converts app ids for user 0 and secondary users', () {
      expect(uidFromAndroidName('u0a174'), 10174);
      expect(uidFromAndroidName('u0a0'), 10000);
      expect(uidFromAndroidName('u10a5'), 1010005);
    });

    test('plain numbers pass through, other names are null', () {
      expect(uidFromAndroidName('1000'), 1000);
      expect(uidFromAndroidName('root'), isNull);
      expect(uidFromAndroidName('u0_a174'), isNull);
    });
  });
}
