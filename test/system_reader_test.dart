import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turbomon/models/monitor.dart';
import 'package:turbomon/services/access.dart';
import 'package:turbomon/services/system_reader.dart';

import 'support/fake_files.dart';
import 'support/fake_platform.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  late FakePlatform platform;
  late FakeFiles files;
  var now = DateTime(2026, 10, 10, 12);

  SystemReader reader(AccessController access) => SystemReader(
    platform: platform,
    access: access,
    files: files,
    clock: () => now,
  );

  setUp(() {
    platform = FakePlatform();
    files = FakeFiles({
      '/proc/meminfo': fixture('meminfo.txt'),
      '/sys/devices/system/cpu/present': '0-1\n',
      for (final c in [0, 1]) ...{
        '/sys/devices/system/cpu/cpu$c/cpufreq/scaling_cur_freq': '1200000',
        '/sys/devices/system/cpu/cpu$c/cpufreq/cpuinfo_min_freq': '300000',
        '/sys/devices/system/cpu/cpu$c/cpufreq/cpuinfo_max_freq': '2400000',
      },
      '/proc/self/io': 'read_bytes: 0\nwrite_bytes: 0\n',
    });
    now = DateTime(2026, 10, 10, 12);
  });

  test(
    'normal app: frequency proxy, memory, battery, rates from the second sample',
    () async {
      final r = reader(AccessController(platform));
      final first = await r.sample();
      expect(first.cpu!.isFrequencyProxy, isTrue);
      expect(first.cpu!.load, 50);
      expect(first.cpu!.coreCount, 2);
      expect(first.memory!.totalBytes, greaterThan(0));
      expect(first.network, isNull, reason: 'a rate needs two readings');
      expect(first.battery!.currentMa, -450);
      expect(first.battery!.powerW, closeTo(-1.755, 0.001));
      expect(first.thermal!.zones.single.name, 'battery');
      expect(first.gpu, isNull);

      platform.rx = 2048;
      files.files['/proc/self/io'] = 'read_bytes: 4096\nwrite_bytes: 0\n';
      now = now.add(const Duration(seconds: 2));
      final second = await r.sample();
      expect(second.network!.rxBps, 1024);
      expect(second.diskIo!.scope, 'self');
      expect(second.diskIo!.readBps, 2048);
    },
  );

  test('only the requested monitors are sampled', () async {
    final s = await reader(
      AccessController(platform),
    ).sample(monitors: {Monitor.ram});
    expect(s.memory, isNotNull);
    expect(s.cpu, isNull);
    expect(s.battery, isNull);
  });

  test('implausible emulator clocks are dropped', () async {
    files.files['/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq'] = '2';
    final s = await reader(
      AccessController(platform),
    ).sample(monitors: {Monitor.cpu});
    expect(s.cpu!.frequencies.first.currentKHz, isNull);
  });

  test(
    'Shizuku: real CPU %, GPU, thermal zones, disk I/O and processes',
    () async {
      platform.shizuku = const {'running': true, 'granted': true};
      var stat = fixture('stat_before.txt');
      var disk = fixture('diskstats.txt');
      platform.shell = (script) {
        if (script.startsWith('top')) return fixture('top_quiet.txt');
        if (script.contains('batterystats')) {
          return fixture('batterystats_uids.txt');
        }
        return '@@TM@@ stat\n$stat'
            '@@TM@@ disk\n$disk'
            '@@TM@@ thermal\ncpu-0\t52000\nskin\t36000\n'
            '@@TM@@ gpu\n/sys/class/kgsl/kgsl-3d0/gpu_busy_percentage\n37 %\nclock 585000000\n';
      };
      final access = AccessController(platform);
      await access.resolve(AccessMode.auto);
      expect(access.level, AccessLevel.shizuku);
      final r = reader(access);

      await r.sample();
      stat = fixture('stat_after.txt');
      disk = disk.replaceFirst('120000 3000 9600000', '120100 3000 9602048');
      now = now.add(const Duration(seconds: 2));
      final s = await r.sample();
      expect(s.cpu!.isFrequencyProxy, isFalse);
      expect(s.cpu!.corePercents, hasLength(2));
      expect(s.gpu!.busyPercent, 37);
      expect(s.gpu!.frequencyMHz, 585);
      expect(s.thermal!.hottest, 52);
      expect(s.diskIo!.scope, 'device');
      expect(s.diskIo!.readBps, 2048 * 512 / 2);
      expect(s.diskIo!.readOps, 50);

      final processes = await r.processes(limit: 5);
      expect(processes, hasLength(5));
      // TurboMon's own `top` probe is not one of the busiest processes.
      expect(processes.first.name, startsWith('sh -c settings'));
      final mah = await r.batteryByUid();
      expect(mah[1000], 41.7);
    },
  );

  test('a failing shell degrades to normal readings', () async {
    platform.shizuku = const {'running': true, 'granted': true};
    platform.shell = (_) => throw StateError('Shizuku died');
    final access = AccessController(platform);
    await access.resolve(AccessMode.shizuku);
    final r = reader(access);
    final s = await r.sample();
    expect(s.cpu!.isFrequencyProxy, isTrue);
    expect(await r.processes(), isEmpty);
    expect(await r.diagnostics(), isEmpty);
  });
}
