import 'dart:async';

import 'package:flutter/foundation.dart';

import '../model/readings.dart';
import '../model/ring_buffer.dart';
import '../model/settings.dart';
import '../parsers/proc_parsers.dart';
import '../platform/access.dart';
import '../platform/native_bridge.dart';
import 'alerts.dart';

/// Samples every live metric on a timer while the app is in the foreground
/// and keeps the graph history. The background service has its own sampler
/// in Kotlin; this one only runs while TurboMon is open.
class MonitorController extends ChangeNotifier {
  MonitorController({
    required this.bridge,
    required this.files,
    required Settings settings,
    this.onAlert,
    DateTime Function()? clock,
  })  : _settings = settings,
        _clock = clock ?? DateTime.now {
    _allocate();
  }

  final NativeBridge bridge;
  final SystemFiles files;
  final DateTime Function() _clock;

  /// Called for each alert that fires while the app is open.
  Future<void> Function(FiredAlert alert)? onAlert;

  Settings _settings;
  Settings get settings => _settings;

  PrivilegedShell shell = const NoShell();
  AccessLevel get access => shell.level;

  Timer? _timer;
  bool _sampling = false;
  bool get running => _timer != null;
  DateTime? startedAt;
  int _tick = 0;

  // Graph series.
  late RingBuffer cpu;
  List<RingBuffer> cores = [];
  late RingBuffer ram;
  late RingBuffer gpu;
  late RingBuffer batteryPower;
  late RingBuffer batteryDrain;
  late RingBuffer netRx;
  late RingBuffer netTx;
  late RingBuffer hottest;
  late RingBuffer batteryTemp;
  late RingBuffer diskRead;
  late RingBuffer diskWrite;

  /// True when CPU values are frequency as a share of maximum, because real
  /// utilisation (/proc/stat) is not readable.
  bool cpuIsProxy = true;
  bool gpuAvailable = false;
  bool diskIoAvailable = false;

  // Latest readings.
  Map<String, Object?> device = const {};
  MemInfo? mem;
  List<CoreFreq> coreFreqs = const [];
  Map<String, double> corePercent = const {};
  BatteryReading? battery;
  int? thermalStatus;
  double? thermalHeadroom;
  List<ThermalZone> zones = const [];
  List<StorageVolume> volumes = const [];
  List<DiskRate> diskRates = const [];
  List<ProcessRow> processes = const [];
  Map<String, double> batteryPerUid = const {};
  double? ownReadBps;
  double? ownWriteBps;
  double? rxBps;
  double? txBps;
  double? mobileRxBps;
  double? mobileTxBps;
  final List<FiredAlert> firedAlerts = [];

  // Previous counters for rates.
  Map<String, CpuTimes>? _prevStat;
  Map<int, int>? _prevPidTicks;
  int? _prevTotalJiffies;
  Map<String, Object?>? _prevTraffic;
  DateTime? _prevTrafficAt;
  List<DiskCounters>? _prevDisk;
  DateTime? _prevDiskAt;
  (int, int)? _prevOwnIo;
  DateTime? _prevOwnIoAt;

  final AlertEvaluator _alerts = AlertEvaluator();

  void _allocate() {
    final n = _settings.graphCapacity;
    cpu = RingBuffer(n);
    ram = RingBuffer(n);
    gpu = RingBuffer(n);
    batteryPower = RingBuffer(n);
    batteryDrain = RingBuffer(n);
    netRx = RingBuffer(n);
    netTx = RingBuffer(n);
    hottest = RingBuffer(n);
    batteryTemp = RingBuffer(n);
    diskRead = RingBuffer(n);
    diskWrite = RingBuffer(n);
    cores = [for (final c in cores) c.resized(n)];
  }

  /// Applies new settings; graphs keep their newest samples.
  void updateSettings(Settings s) {
    final resize = s.graphCapacity != _settings.graphCapacity;
    final restart = s.refreshSeconds != _settings.refreshSeconds;
    _settings = s;
    if (resize) {
      final n = s.graphCapacity;
      cpu = cpu.resized(n);
      ram = ram.resized(n);
      gpu = gpu.resized(n);
      batteryPower = batteryPower.resized(n);
      batteryDrain = batteryDrain.resized(n);
      netRx = netRx.resized(n);
      netTx = netTx.resized(n);
      hottest = hottest.resized(n);
      batteryTemp = batteryTemp.resized(n);
      diskRead = diskRead.resized(n);
      diskWrite = diskWrite.resized(n);
      cores = [for (final c in cores) c.resized(n)];
    }
    if (restart && running) {
      stop();
      start();
    }
    notifyListeners();
  }

  void setShell(PrivilegedShell s) {
    shell = s;
    _prevStat = null;
    _prevPidTicks = null;
    _prevDisk = null;
    notifyListeners();
  }

  void start() {
    if (_timer != null) return;
    startedAt ??= _clock();
    _timer = Timer.periodic(Duration(seconds: _settings.refreshSeconds), (_) => sample());
    sample();
  }

  /// Pauses sampling, e.g. while the app is in the background.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }

  Future<String?> _read(String path) async {
    final direct = await files.read(path);
    if (direct != null && direct.isNotEmpty) return direct;
    if (!shell.level.elevated) return null;
    final r = await shell.run('cat $path');
    return r.ok ? r.stdout : null;
  }

  /// Takes one sample of everything. Public for tests.
  Future<void> sample() async {
    if (_sampling) return;
    _sampling = true;
    final now = _clock();
    try {
      if (device.isEmpty) {
        device = await _safe(bridge.deviceInfo, const <String, Object?>{});
      }
      await Future.wait([
        _sampleCpu(now),
        _sampleMemory(now),
        _sampleGpu(now),
        _sampleBattery(now),
        _sampleTraffic(now),
        _sampleThermal(now),
        _sampleDisk(now),
      ]);
      if (_tick % 15 == 0) {
        volumes = [
          for (final v in await _safe(bridge.storageVolumes, const <Map<String, Object?>>[]))
            StorageVolume.fromMap(v),
        ];
      }
      if (shell.level.elevated && _tick % 30 == 0) {
        await _sampleBatteryStats();
      }
      _checkAlerts(now);
    } finally {
      _tick++;
      _sampling = false;
      notifyListeners();
    }
  }

  static Future<T> _safe<T>(Future<T> Function() f, T fallback) async {
    try {
      return await f();
    } on Object {
      return fallback;
    }
  }

  Future<void> _sampleCpu(DateTime now) async {
    // Real utilisation, plus the process table when elevated, in one shell
    // round trip: /proc/stat, ps names, then every /proc/<pid>/stat.
    String? stat;
    String? psText;
    String? pidText;
    if (shell.level.elevated) {
      final r = await shell.run(
          "cat /proc/stat; echo '@@TM@@'; ps -A -o PID,USER,NAME; echo '@@TM@@'; cat /proc/[0-9]*/stat 2>/dev/null");
      if (r.stdout.contains('@@TM@@')) {
        final parts = r.stdout.split('@@TM@@');
        stat = parts[0];
        psText = parts.length > 1 ? parts[1] : null;
        pidText = parts.length > 2 ? parts[2] : null;
      }
    }
    stat ??= await files.read('/proc/stat');

    final parsed = stat == null ? const <String, CpuTimes>{} : parseProcStat(stat);
    if (parsed.containsKey('cpu')) {
      cpuIsProxy = false;
      if (_prevStat != null) {
        final pct = cpuPercentBetween(_prevStat!, parsed);
        corePercent = Map.fromEntries(pct.entries.where((e) => e.key != 'cpu'));
        cpu.add(pct['cpu'], now);
        _addCores(now, [
          for (var i = 0; i < 64; i++)
            if (parsed.containsKey('cpu$i')) pct['cpu$i'],
        ]);
      }
      if (pidText != null && psText != null) {
        _updateProcesses(parsed['cpu']!.total, psText, pidText);
      }
      _prevStat = parsed;
    }
    coreFreqs = await _readCoreFreqs();
    if (cpuIsProxy) {
      if (coreFreqs.isEmpty) {
        cpu.add(null, now);
      } else {
        final avg = coreFreqs.map((c) => c.percentOfMax).reduce((a, b) => a + b) / coreFreqs.length;
        cpu.add(avg, now);
        _addCores(now, [for (final c in coreFreqs) c.percentOfMax]);
      }
      processes = await _ownProcessOnly();
    }
  }

  void _addCores(DateTime now, List<double?> values) {
    final n = _settings.graphCapacity;
    while (cores.length < values.length) {
      cores.add(RingBuffer(n));
    }
    for (var i = 0; i < values.length; i++) {
      cores[i].add(values[i], now);
    }
  }

  int? _coreCount;

  Future<List<CoreFreq>> _readCoreFreqs() async {
    _coreCount ??= await _countCores();
    final out = <CoreFreq>[];
    for (var i = 0; i < (_coreCount ?? 0); i++) {
      final base = '/sys/devices/system/cpu/cpu$i/cpufreq';
      final cur = int.tryParse((await files.read('$base/scaling_cur_freq'))?.trim() ?? '');
      final max = int.tryParse((await files.read('$base/cpuinfo_max_freq'))?.trim() ?? '');
      if (cur == null || max == null) continue;
      out.add(CoreFreq(core: i, curKhz: cur, maxKhz: max));
    }
    return out;
  }

  Future<int> _countCores() async {
    final possible = (await files.read('/sys/devices/system/cpu/possible'))?.trim();
    final m = RegExp(r'(\d+)-(\d+)').firstMatch(possible ?? '');
    if (m != null) return int.parse(m.group(2)!) + 1;
    final fromDevice = (device['cores'] as num?)?.toInt();
    return fromDevice ?? 8;
  }

  void _updateProcesses(int totalJiffies, String psText, String pidText) {
    final names = parsePsNames(psText);
    final stats = parsePidStats(pidText);
    final prev = _prevPidTicks;
    final dTotal = _prevTotalJiffies == null ? 0 : totalJiffies - _prevTotalJiffies!;
    final pageKb = ((device['pageSize'] as num?)?.toInt() ?? 4096) ~/ 1024;
    final rows = <ProcessRow>[];
    for (final s in stats) {
      final before = prev?[s.pid];
      final pct = (before == null || dTotal <= 0) ? 0.0 : (s.ticks - before) * 100 / dTotal;
      final (user, name) = names[s.pid] ?? ('?', s.comm);
      rows.add(ProcessRow(
        pid: s.pid,
        user: user,
        name: name,
        cpuPercent: pct.clamp(0, 100).toDouble(),
        rssKb: s.rssPages * pageKb,
        state: s.state,
        batteryMah: batteryPerUid[user.replaceAll('_', '')],
      ));
    }
    rows.sort((a, b) {
      final c = b.cpuPercent.compareTo(a.cpuPercent);
      return c != 0 ? c : b.rssKb.compareTo(a.rssKb);
    });
    processes = rows;
    _prevPidTicks = {for (final s in stats) s.pid: s.ticks};
    _prevTotalJiffies = totalJiffies;
  }

  Future<List<ProcessRow>> _ownProcessOnly() async {
    final text = await files.read('/proc/self/stat');
    if (text == null) return const [];
    final s = parsePidStats(text);
    if (s.isEmpty) return const [];
    final pageKb = ((device['pageSize'] as num?)?.toInt() ?? 4096) ~/ 1024;
    return [
      ProcessRow(
        pid: s.first.pid,
        user: 'self',
        name: 'org.buetow.turbomon',
        cpuPercent: 0,
        rssKb: s.first.rssPages * pageKb,
        state: s.first.state,
      ),
    ];
  }

  Future<void> _sampleMemory(DateTime now) async {
    final text = await files.read('/proc/meminfo');
    var m = text == null ? null : parseMemInfo(text);
    if (m == null) {
      final info = await _safe(bridge.memoryInfo, const <String, Object?>{});
      final total = (info['totalBytes'] as num?)?.toInt();
      final avail = (info['availBytes'] as num?)?.toInt();
      if (total != null && avail != null) {
        m = MemInfo(
          totalKb: total ~/ 1024,
          availableKb: avail ~/ 1024,
          cachedKb: 0,
          swapTotalKb: 0,
          swapFreeKb: 0,
        );
      }
    }
    mem = m;
    ram.add(m?.usedPercent, now);
  }

  String? _gpuPath;
  bool _gpuProbed = false;

  Future<void> _sampleGpu(DateTime now) async {
    if (!_gpuProbed || (_gpuPath == null && shell.level.elevated && _tick % 30 == 0)) {
      _gpuProbed = true;
      for (final p in gpuBusyPaths) {
        final t = await _read(p);
        if (t != null && parseGpuBusy(p, t) != null) {
          _gpuPath = p;
          break;
        }
      }
    }
    final path = _gpuPath;
    if (path == null) {
      gpuAvailable = false;
      return;
    }
    final t = await _read(path);
    final v = t == null ? null : parseGpuBusy(path, t);
    gpuAvailable = v != null;
    gpu.add(v, now);
  }

  Future<void> _sampleBattery(DateTime now) async {
    final m = await _safe(bridge.battery, const <String, Object?>{});
    if (m.isEmpty) return;
    final b = BatteryReading.fromMap(m);
    battery = b;
    batteryPower.add(b.powerW, now);
    batteryDrain.add(b.drainMa, now);
    batteryTemp.add(b.tempC, now);
  }

  Future<void> _sampleTraffic(DateTime now) async {
    final t = await _safe(bridge.traffic, const <String, Object?>{});
    if (t.isEmpty) return;
    final prev = _prevTraffic;
    final at = _prevTrafficAt;
    if (prev != null && at != null) {
      final secs = now.difference(at).inMilliseconds / 1000;
      double? rate(String k) {
        final a = (prev[k] as num?)?.toInt();
        final b = (t[k] as num?)?.toInt();
        if (a == null || b == null || a < 0 || b < 0 || secs <= 0) return null;
        final d = b - a;
        return d < 0 ? 0 : d / secs;
      }

      rxBps = rate('totalRx');
      txBps = rate('totalTx');
      mobileRxBps = rate('mobileRx');
      mobileTxBps = rate('mobileTx');
      netRx.add(rxBps, now);
      netTx.add(txBps, now);
    }
    _prevTraffic = t;
    _prevTrafficAt = now;
  }

  Future<void> _sampleThermal(DateTime now) async {
    final t = await _safe(bridge.thermal, const <String, Object?>{});
    thermalStatus = (t['status'] as num?)?.toInt();
    thermalHeadroom = (t['headroom'] as num?)?.toDouble();
    // Zones are read every few ticks: there can be 80 of them.
    if (_tick % 5 == 0) {
      String? text;
      if (shell.level.elevated) {
        final r = await shell.run(thermalZonesCommand);
        if (r.ok) text = r.stdout;
      }
      if (text == null) {
        final lines = <String>[];
        for (var i = 0; i < 100; i++) {
          final type = await files.read('/sys/class/thermal/thermal_zone$i/type');
          if (type == null) {
            if (i > 0) break;
            continue;
          }
          final temp = await files.read('/sys/class/thermal/thermal_zone$i/temp');
          if (temp != null) lines.add('${type.trim()}=${temp.trim()}');
        }
        text = lines.join('\n');
      }
      zones = parseThermalZones(text);
    }
    final socZones = zones.where((z) =>
        RegExp(r'cpu|soc|tsens|big|little|mid|ap|tz', caseSensitive: false).hasMatch(z.type));
    final pool = socZones.isNotEmpty ? socZones : zones;
    hottest.add(pool.isEmpty ? null : pool.map((z) => z.celsius).reduce((a, b) => a > b ? a : b), now);
  }

  Future<void> _sampleDisk(DateTime now) async {
    final text = await _read('/proc/diskstats');
    if (text != null) {
      final c = parseDiskStats(text);
      if (c.isNotEmpty) {
        if (_prevDisk != null && _prevDiskAt != null) {
          diskRates = diskRatesBetween(_prevDisk!, c, now.difference(_prevDiskAt!));
          diskRead.add(diskRates.fold<double>(0, (a, d) => a + d.readBytesPerSec), now);
          diskWrite.add(diskRates.fold<double>(0, (a, d) => a + d.writeBytesPerSec), now);
        }
        diskIoAvailable = true;
        _prevDisk = c;
        _prevDiskAt = now;
      }
    } else {
      diskIoAvailable = false;
    }
    // TurboMon's own I/O is always readable.
    final io = await files.read('/proc/self/io');
    if (io != null) {
      int? field(String k) =>
          int.tryParse(RegExp('^$k:\\s*(\\d+)', multiLine: true).firstMatch(io)?.group(1) ?? '');
      final r = field('rchar');
      final w = field('wchar');
      if (r != null && w != null) {
        if (_prevOwnIo != null && _prevOwnIoAt != null) {
          final secs = now.difference(_prevOwnIoAt!).inMilliseconds / 1000;
          if (secs > 0) {
            ownReadBps = (r - _prevOwnIo!.$1) / secs;
            ownWriteBps = (w - _prevOwnIo!.$2) / secs;
          }
        }
        _prevOwnIo = (r, w);
        _prevOwnIoAt = now;
      }
    }
  }

  Future<void> _sampleBatteryStats() async {
    final r = await shell.run('dumpsys batterystats --charged 2>/dev/null | grep -iE "^ +(UID|Uid) "');
    if (r.ok && r.stdout.isNotEmpty) {
      batteryPerUid = parseBatteryStatsPerUid(r.stdout);
    }
  }

  void _checkAlerts(DateTime now) {
    final hot = [hottest.last, batteryTemp.last].whereType<double>();
    final fired = _alerts.check(
      _settings.alerts,
      now,
      cpuPercent: cpuIsProxy ? null : cpu.last,
      tempC: hot.isEmpty ? null : hot.reduce((a, b) => a > b ? a : b),
      drainMa: batteryDrain.last,
      ramPercent: ram.last,
    );
    for (final a in fired) {
      firedAlerts.add(a);
      if (firedAlerts.length > 50) firedAlerts.removeAt(0);
      onAlert?.call(a);
    }
  }
}
