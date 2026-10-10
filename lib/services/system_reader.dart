import 'dart:async';

import 'package:turbomon_platform/turbomon_platform.dart';

import '../models/monitor.dart';
import '../models/readings.dart';
import 'access.dart';
import 'battery_math.dart';
import 'file_source.dart';
import 'proc_parsers.dart';

/// Takes one [SystemSample] at a time. Rates (CPU %, network, disk I/O) are
/// deltas against the previous call, so the first sample has none of them.
///
/// Plain files are read directly; with Shizuku or root the protected ones
/// (/proc/stat, /proc/diskstats, thermal zones, GPU sysfs) are fetched in one
/// batched shell script per tick.
class SystemReader {
  SystemReader({
    required this.platform,
    required this.access,
    this.files = const LocalFileSource(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final TurboMonPlatform platform;
  final AccessController access;
  final FileSource files;
  final DateTime Function() _clock;

  static const _marker = '@@TM@@';
  static const gpuBusyPaths = [
    '/sys/class/kgsl/kgsl-3d0/gpu_busy_percentage',
    '/sys/class/kgsl/kgsl-3d0/gpubusy',
    '/sys/class/misc/mali0/device/utilization',
    '/sys/kernel/gpu/gpu_busy',
    '/sys/devices/platform/gpu/utilization',
  ];
  static const gpuClockPaths = [
    '/sys/class/kgsl/kgsl-3d0/gpuclk',
    '/sys/kernel/gpu/gpu_clock',
    '/sys/class/misc/mali0/device/clock',
  ];

  int? _coreCount;
  Map<int, CpuTimes>? _lastStat;
  ({DateTime at, Map<String, Object?> raw})? _lastTraffic;
  ({DateTime at, DiskCounters counters})? _lastDisk;
  ({DateTime at, int read, int write})? _lastSelfIo;

  /// Samples [monitors] (all by default).
  Future<SystemSample> sample({Set<Monitor> monitors = const {}}) async {
    bool want(Monitor m) => monitors.isEmpty || monitors.contains(m);
    final now = _clock();
    final privileged = await _privilegedSections(
      stat: want(Monitor.cpu),
      disk: want(Monitor.diskIo),
      thermal: want(Monitor.temperature),
      gpu: want(Monitor.gpu),
    );

    // Battery temperature also feeds the temperature monitor.
    final battery = want(Monitor.battery) || want(Monitor.temperature)
        ? await _battery()
        : null;
    final results = await Future.wait<Object?>([
      want(Monitor.cpu) ? _cpu(privileged['stat']) : Future.value(),
      want(Monitor.ram) ? _memory() : Future.value(),
      want(Monitor.gpu) ? _gpu(privileged['gpu']) : Future.value(),
      want(Monitor.network) ? _network(now) : Future.value(),
      want(Monitor.temperature)
          ? _thermal(privileged['thermal'], battery?.temperatureC)
          : Future.value(),
      want(Monitor.diskIo) ? _diskIo(now, privileged['disk']) : Future.value(),
    ]);
    return SystemSample(
      time: now,
      cpu: results[0] as CpuReading?,
      memory: results[1] as MemoryReading?,
      gpu: results[2] as GpuReading?,
      battery: want(Monitor.battery) ? battery : null,
      network: results[3] as NetworkRate?,
      thermal: results[4] as ThermalReading?,
      diskIo: results[5] as DiskIoReading?,
    );
  }

  /// The top-style process list; empty without Shizuku or root, since
  /// Android hides other apps' /proc entries from normal apps.
  Future<List<ProcessInfo>> processes({int limit = 40}) async {
    if (access.runner == null) return const [];
    const top = 'top -b -n 1 -q -o PID,USER,S,%CPU,RES,ARGS -s 4';
    try {
      // One extra row, since the probe itself is dropped below.
      final out = await access.run('$top -m ${limit + 1}');
      // toybox top ignores -m with -q on some builds; cap the list here.
      return parseTop(
        out,
      ).where((p) => !p.name.startsWith(top)).take(limit).toList();
    } on Object {
      return const [];
    }
  }

  /// Raw `dumpsys` output for snapshots, keyed by service; empty when
  /// unprivileged.
  Future<Map<String, String>> diagnostics() async {
    if (access.runner == null) return const {};
    const commands = {
      'batterystats': 'dumpsys batterystats --charged | head -c 60000',
      'cpuinfo': 'dumpsys cpuinfo | head -c 20000',
      'wakelocks': "dumpsys power | grep -iE 'wake ?lock' | head -c 20000",
    };
    final script = commands.entries
        .map((e) => 'echo "$_marker ${e.key}"; ${e.value}')
        .join('\n');
    try {
      return splitSections(await access.run(script), _marker);
    } on Object {
      return const {};
    }
  }

  /// Estimated mAh per uid from batterystats, for the process table.
  Future<Map<int, double>> batteryByUid() async {
    if (access.runner == null) return const {};
    try {
      return parseBatteryStatsPower(
        await access.run(
          // Only the "Estimated power use" section has `UID x: mAh` lines.
          "dumpsys batterystats --charged | grep -E '^ +UID [0-9a-z]+: [0-9.]+'",
        ),
      );
    } on Object {
      return const {};
    }
  }

  Future<Map<String, String>> _privilegedSections({
    required bool stat,
    required bool disk,
    required bool thermal,
    required bool gpu,
  }) async {
    if (access.runner == null) return const {};
    final parts = <String>[
      if (stat) 'echo "$_marker stat"; cat /proc/stat',
      if (disk) 'echo "$_marker disk"; cat /proc/diskstats',
      if (thermal)
        'echo "$_marker thermal"; for z in /sys/class/thermal/thermal_zone*; '
            r'do printf "%s\t%s\n" "$(cat $z/type)" "$(cat $z/temp)"; done',
      if (gpu)
        'echo "$_marker gpu"; for f in ${gpuBusyPaths.join(' ')}; '
            r'do [ -r $f ] && { echo "$f"; cat $f; break; }; done; '
            'for f in ${gpuClockPaths.join(' ')}; '
            r'do [ -r $f ] && { echo "clock $(cat $f)"; break; }; done',
    ];
    if (parts.isEmpty) return const {};
    try {
      return splitSections(await access.run(parts.join('\n')), _marker);
    } on Object {
      return const {};
    }
  }

  Future<CpuReading> _cpu(String? privilegedStat) async {
    final cores = _coreCount ??= await _countCores();
    final stat = privilegedStat ?? await files.read('/proc/stat');
    double? total;
    var perCore = const <double>[];
    if (stat != null) {
      final times = parseProcStat(stat);
      final last = _lastStat;
      if (last != null && times.containsKey(-1) && last.containsKey(-1)) {
        total = times[-1]!.percentSince(last[-1]!);
        perCore = [
          for (var i = 0; i < cores; i++)
            if (times[i] != null && last[i] != null)
              times[i]!.percentSince(last[i]!)
            else
              0,
        ];
      }
      if (times.isNotEmpty) _lastStat = times;
    }
    final frequencies = await Future.wait([
      for (var i = 0; i < cores; i++) _frequency(i),
    ]);
    return CpuReading(
      totalPercent: total,
      corePercents: perCore,
      frequencies: frequencies,
      coreCount: cores,
    );
  }

  Future<int> _countCores() async {
    final present = await files.read('/sys/devices/system/cpu/present');
    // Format: "0-7" or "0".
    final m = RegExp(r'(\d+)\s*$').firstMatch(present?.trim() ?? '');
    if (m != null) return int.parse(m.group(1)!) + 1;
    final device = await platform.device();
    return (device['cores'] as int?) ?? 1;
  }

  Future<CoreFrequency> _frequency(int core) async {
    final base = '/sys/devices/system/cpu/cpu$core/cpufreq';
    Future<int?> read(String name) async =>
        int.tryParse((await files.read('$base/$name'))?.trim() ?? '');
    final values = await Future.wait([
      read('scaling_cur_freq'),
      read('cpuinfo_min_freq'),
      read('cpuinfo_max_freq'),
    ]);
    // Emulators expose cpufreq with placeholder values in the single digits.
    bool plausible(int? khz) => khz != null && khz >= 1000;
    return CoreFrequency(
      index: core,
      currentKHz: plausible(values[0]) ? values[0] : null,
      minKHz: plausible(values[1]) ? values[1] : null,
      maxKHz: plausible(values[2]) ? values[2] : null,
    );
  }

  Future<MemoryReading?> _memory() async {
    final meminfo = await files.read('/proc/meminfo');
    final parsed = meminfo == null
        ? null
        : memoryFromMeminfo(parseMeminfo(meminfo));
    if (parsed != null) return parsed;
    final m = await platform.memory();
    final total = (m['total'] as num?)?.toInt();
    if (total == null) return null;
    return MemoryReading(
      totalBytes: total,
      availableBytes: (m['available'] as num?)?.toInt() ?? 0,
    );
  }

  Future<GpuReading?> _gpu(String? privileged) async {
    var text = privileged;
    if (text == null || text.trim().isEmpty) {
      // Unprivileged attempt; SELinux blocks these on most phones.
      for (final path in gpuBusyPaths) {
        final value = await files.read(path);
        if (value != null) {
          text = '$path\n$value';
          break;
        }
      }
    }
    if (text == null || text.trim().isEmpty) return null;
    final lines = text.trim().split('\n');
    final busyLine = lines.length > 1 && !lines[1].startsWith('clock ')
        ? lines[1]
        : null;
    final clockLine = lines.firstWhere(
      (l) => l.startsWith('clock '),
      orElse: () => '',
    );
    final busy = busyLine == null ? null : parseGpuBusy(busyLine);
    final clock = int.tryParse(clockLine.replaceFirst('clock ', '').trim());
    if (busy == null && clock == null) return null;
    return GpuReading(
      busyPercent: busy,
      // kgsl reports Hz, Samsung MHz.
      frequencyMHz: clock == null
          ? null
          : (clock > 100000 ? clock ~/ 1000000 : clock),
      source: lines.first.startsWith('/') ? lines.first : 'sysfs',
    );
  }

  Future<BatteryReading?> _battery() async {
    final b = await platform.battery();
    if (b.isEmpty) return null;
    final charging = b['charging'] as bool? ?? false;
    return BatteryReading(
      percent: (b['percent'] as num?)?.toDouble(),
      status: b['status'] as String? ?? 'unknown',
      charging: charging,
      plugged: b['plugged'] as String?,
      health: b['health'] as String?,
      temperatureC: (b['temperatureC'] as num?)?.toDouble(),
      voltageMv: (b['voltageMv'] as num?)?.toInt(),
      currentMa: normaliseCurrentMa(
        b['currentNow'] as num?,
        charging: charging,
      ),
      screenOn: b['screenOn'] as bool?,
    );
  }

  Future<NetworkRate?> _network(DateTime now) async {
    final raw = await platform.traffic();
    final last = _lastTraffic;
    _lastTraffic = (at: now, raw: raw);
    if (last == null) return null;
    final seconds = now.difference(last.at).inMilliseconds / 1000;
    if (seconds <= 0) return null;
    double rate(String key) {
      final a = (last.raw[key] as num?)?.toDouble() ?? 0;
      final b = (raw[key] as num?)?.toDouble() ?? 0;
      // Counters reset when an interface goes away; never report negatives.
      return a < 0 || b < a ? 0 : (b - a) / seconds;
    }

    return NetworkRate(
      rxBps: rate('totalRx'),
      txBps: rate('totalTx'),
      mobileRxBps: rate('mobileRx'),
      mobileTxBps: rate('mobileTx'),
    );
  }

  Future<ThermalReading> _thermal(
    String? privileged,
    double? batteryTemp,
  ) async {
    final t = await platform.thermal();
    var zones = privileged == null
        ? const <ThermalZone>[]
        : parseThermalZones(privileged);
    if (zones.isEmpty) zones = await _readableZones();
    if (batteryTemp != null) {
      zones = [ThermalZone('battery', batteryTemp), ...zones];
    }
    return ThermalReading(
      status: (t['status'] as num?)?.toInt(),
      headroom: (t['headroom'] as num?)?.toDouble(),
      zones: _dedupe(zones),
    );
  }

  Future<List<ThermalZone>> _readableZones() async {
    final zones = <ThermalZone>[];
    for (final dir in await files.list('/sys/class/thermal', 'thermal_zone')) {
      final type = await files.read('$dir/type');
      final temp = await files.read('$dir/temp');
      final celsius = temp == null ? null : parseThermalTemp(temp);
      if (type != null && celsius != null) {
        zones.add(ThermalZone(type.trim(), celsius));
      }
    }
    return zones;
  }

  /// Kernels often list a sensor under the same type several times; keep the
  /// hottest of each so the list stays readable.
  List<ThermalZone> _dedupe(List<ThermalZone> zones) {
    final byName = <String, ThermalZone>{};
    for (final z in zones) {
      final seen = byName[z.name];
      if (seen == null || z.celsius > seen.celsius) byName[z.name] = z;
    }
    return byName.values.toList();
  }

  Future<DiskIoReading?> _diskIo(DateTime now, String? privileged) async {
    final counters = privileged == null ? null : parseDiskstats(privileged);
    if (counters != null) {
      final last = _lastDisk;
      _lastDisk = (at: now, counters: counters);
      if (last == null) return null;
      final s = now.difference(last.at).inMilliseconds / 1000;
      if (s <= 0) return null;
      final c = counters, p = last.counters;
      // /proc/diskstats counts 512-byte sectors regardless of the device.
      return DiskIoReading(
        readBps: (c.readSectors - p.readSectors) * 512 / s,
        writeBps: (c.writeSectors - p.writeSectors) * 512 / s,
        readOps: (c.reads - p.reads) / s,
        writeOps: (c.writes - p.writes) / s,
        scope: 'device',
      );
    }
    final io = await files.read('/proc/self/io');
    final own = io == null ? null : parseProcIo(io);
    if (own == null) return null;
    final last = _lastSelfIo;
    _lastSelfIo = (at: now, read: own.read, write: own.write);
    if (last == null) return null;
    final s = now.difference(last.at).inMilliseconds / 1000;
    if (s <= 0) return null;
    return DiskIoReading(
      readBps: (own.read - last.read) / s,
      writeBps: (own.write - last.write) / s,
      scope: 'self',
    );
  }
}
