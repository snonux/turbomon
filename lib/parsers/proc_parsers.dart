// Parsers for the Linux /proc and sysfs text TurboMon reads, either directly
// (where Android lets a normal app) or through the privileged shell (Shizuku
// or root). All of them are pure functions over strings so they can be tested
// against captured device output.

/// Memory figures from `/proc/meminfo`, in kilobytes.
class MemInfo {
  const MemInfo({
    required this.totalKb,
    required this.availableKb,
    required this.cachedKb,
    required this.swapTotalKb,
    required this.swapFreeKb,
  });

  final int totalKb;
  final int availableKb;
  final int cachedKb;
  final int swapTotalKb;
  final int swapFreeKb;

  int get usedKb => totalKb - availableKb;
  double get usedPercent => totalKb == 0 ? 0 : usedKb * 100 / totalKb;
}

MemInfo? parseMemInfo(String text) {
  final values = <String, int>{};
  for (final line in text.split('\n')) {
    final m = RegExp(r'^(\w+(?:\(\w+\))?):\s+(\d+)').firstMatch(line);
    if (m != null) values[m.group(1)!] = int.parse(m.group(2)!);
  }
  final total = values['MemTotal'];
  if (total == null) return null;
  final available = values['MemAvailable'] ??
      (values['MemFree'] ?? 0) + (values['Cached'] ?? 0) + (values['Buffers'] ?? 0);
  return MemInfo(
    totalKb: total,
    availableKb: available,
    cachedKb: values['Cached'] ?? 0,
    swapTotalKb: values['SwapTotal'] ?? 0,
    swapFreeKb: values['SwapFree'] ?? 0,
  );
}

/// Jiffy counters of one `cpu` line in `/proc/stat`.
class CpuTimes {
  const CpuTimes(this.busy, this.total);
  final int busy;
  final int total;
}

/// Returns the aggregate line under key `cpu` and one entry per core
/// (`cpu0`, `cpu1`, ...). Offline cores are simply missing from the file.
Map<String, CpuTimes> parseProcStat(String text) {
  final out = <String, CpuTimes>{};
  for (final line in text.split('\n')) {
    if (!line.startsWith('cpu')) continue;
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length < 5) continue;
    final nums = parts.skip(1).map(int.tryParse).whereType<int>().toList();
    if (nums.length < 4) continue;
    // user nice system idle iowait irq softirq steal guest guest_nice;
    // guest time is already counted in user, so only the first 8 count.
    final counted = nums.take(8).toList();
    final idle = counted[3] + (counted.length > 4 ? counted[4] : 0);
    final total = counted.reduce((a, b) => a + b);
    out[parts[0]] = CpuTimes(total - idle, total);
  }
  return out;
}

/// CPU busy percentage between two `/proc/stat` readings, per key.
Map<String, double> cpuPercentBetween(
  Map<String, CpuTimes> before,
  Map<String, CpuTimes> after,
) {
  final out = <String, double>{};
  after.forEach((key, now) {
    final prev = before[key];
    if (prev == null) return;
    final dTotal = now.total - prev.total;
    final dBusy = now.busy - prev.busy;
    if (dTotal <= 0) return;
    out[key] = (dBusy * 100 / dTotal).clamp(0, 100).toDouble();
  });
  return out;
}

/// One core's frequency state from
/// `/sys/devices/system/cpu/cpuN/cpufreq/{scaling_cur_freq,cpuinfo_max_freq}`.
class CoreFreq {
  const CoreFreq({required this.core, required this.curKhz, required this.maxKhz, this.minKhz = 0});
  final int core;
  final int curKhz;
  final int maxKhz;
  final int minKhz;

  /// Current frequency as a share of the core's maximum, 0..100. This is the
  /// load proxy shown when real CPU % is not readable (Android 8+ normal app).
  double get percentOfMax => maxKhz <= 0 ? 0 : (curKhz * 100 / maxKhz).clamp(0, 100).toDouble();
}

/// `/proc/diskstats` counters for one block device.
class DiskCounters {
  const DiskCounters({
    required this.device,
    required this.readsCompleted,
    required this.sectorsRead,
    required this.writesCompleted,
    required this.sectorsWritten,
  });
  final String device;
  final int readsCompleted;
  final int sectorsRead;
  final int writesCompleted;
  final int sectorsWritten;
}

/// Whole disks only: partitions, loop, ram and dm devices are skipped so the
/// same bytes are not counted twice.
List<DiskCounters> parseDiskStats(String text) {
  final out = <DiskCounters>[];
  for (final line in text.split('\n')) {
    final p = line.trim().split(RegExp(r'\s+'));
    if (p.length < 10) continue;
    final name = p[2];
    if (!isWholeDisk(name)) continue;
    out.add(DiskCounters(
      device: name,
      readsCompleted: int.tryParse(p[3]) ?? 0,
      sectorsRead: int.tryParse(p[5]) ?? 0,
      writesCompleted: int.tryParse(p[7]) ?? 0,
      sectorsWritten: int.tryParse(p[9]) ?? 0,
    ));
  }
  return out;
}

bool isWholeDisk(String name) {
  if (RegExp(r'^(loop|ram|zram|dm-|md)').hasMatch(name)) return false;
  if (RegExp(r'^sd[a-z]+$').hasMatch(name)) return true; // UFS: sda, sdb...
  if (RegExp(r'^mmcblk\d+$').hasMatch(name)) return true; // eMMC/SD card
  if (RegExp(r'^nvme\d+n\d+$').hasMatch(name)) return true;
  if (RegExp(r'^vd[a-z]+$').hasMatch(name)) return true; // emulator
  return false;
}

/// Disk throughput between two readings. Sectors are 512 bytes regardless of
/// the device's real block size.
class DiskRate {
  const DiskRate({
    required this.device,
    required this.readBytesPerSec,
    required this.writeBytesPerSec,
    required this.readOpsPerSec,
    required this.writeOpsPerSec,
  });
  final String device;
  final double readBytesPerSec;
  final double writeBytesPerSec;
  final double readOpsPerSec;
  final double writeOpsPerSec;
}

List<DiskRate> diskRatesBetween(
  List<DiskCounters> before,
  List<DiskCounters> after,
  Duration elapsed,
) {
  final secs = elapsed.inMilliseconds / 1000;
  if (secs <= 0) return const [];
  final prev = {for (final d in before) d.device: d};
  final out = <DiskRate>[];
  for (final now in after) {
    final p = prev[now.device];
    if (p == null) continue;
    out.add(DiskRate(
      device: now.device,
      readBytesPerSec: _nonNeg(now.sectorsRead - p.sectorsRead) * 512 / secs,
      writeBytesPerSec: _nonNeg(now.sectorsWritten - p.sectorsWritten) * 512 / secs,
      readOpsPerSec: _nonNeg(now.readsCompleted - p.readsCompleted) / secs,
      writeOpsPerSec: _nonNeg(now.writesCompleted - p.writesCompleted) / secs,
    ));
  }
  return out;
}

int _nonNeg(int v) => v < 0 ? 0 : v;

/// CPU ticks and memory of one process from `/proc/<pid>/stat`.
class PidStat {
  const PidStat({
    required this.pid,
    required this.comm,
    required this.state,
    required this.ticks,
    required this.rssPages,
  });
  final int pid;
  final String comm;
  final String state;
  final int ticks; // utime + stime
  final int rssPages;
}

/// Parses the concatenation of many `/proc/<pid>/stat` files (one per line).
/// The command name is in parentheses and may itself contain spaces or
/// parentheses, so the fields are taken after the *last* `)`.
List<PidStat> parsePidStats(String text) {
  final out = <PidStat>[];
  for (final line in text.split('\n')) {
    final open = line.indexOf('(');
    final close = line.lastIndexOf(')');
    if (open <= 0 || close <= open) continue;
    final pid = int.tryParse(line.substring(0, open).trim());
    if (pid == null) continue;
    final rest = line.substring(close + 1).trim().split(RegExp(r'\s+'));
    // rest[0] is field 3 (state); utime=14, stime=15, rss=24 (1-based fields).
    if (rest.length < 22) continue;
    final utime = int.tryParse(rest[11]) ?? 0;
    final stime = int.tryParse(rest[12]) ?? 0;
    out.add(PidStat(
      pid: pid,
      comm: line.substring(open + 1, close),
      state: rest[0],
      ticks: utime + stime,
      rssPages: int.tryParse(rest[21]) ?? 0,
    ));
  }
  return out;
}

/// `ps -A -o PID,USER,NAME` output: PID to (user, full process name).
Map<int, (String, String)> parsePsNames(String text) {
  final out = <int, (String, String)>{};
  for (final line in text.split('\n').skip(1)) {
    final p = line.trim().split(RegExp(r'\s+'));
    if (p.length < 3) continue;
    final pid = int.tryParse(p[0]);
    if (pid == null) continue;
    out[pid] = (p[1], p.sublist(2).join(' '));
  }
  return out;
}

/// GPU load from one of the vendor sysfs files TurboMon probes. Formats seen:
/// Adreno `gpu_busy_percentage` ("37 %" or "37"), Adreno `gpubusy`
/// ("busy total" counters), Mali/Samsung `utilization`/`gpu_busy` ("37").
double? parseGpuBusy(String path, String text) {
  final t = text.trim();
  if (t.isEmpty) return null;
  if (path.endsWith('/gpubusy')) {
    final p = t.split(RegExp(r'\s+'));
    if (p.length < 2) return null;
    final busy = int.tryParse(p[0]);
    final total = int.tryParse(p[1]);
    if (busy == null || total == null || total == 0) return null;
    return (busy * 100 / total).clamp(0, 100).toDouble();
  }
  final m = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(t);
  if (m == null) return null;
  final v = double.parse(m.group(1)!);
  return v > 100 ? null : v;
}

/// Known GPU busy files, most specific first.
const gpuBusyPaths = [
  '/sys/class/kgsl/kgsl-3d0/gpu_busy_percentage',
  '/sys/class/kgsl/kgsl-3d0/gpubusy',
  '/sys/kernel/gpu/gpu_busy',
  '/sys/class/misc/mali0/device/utilization',
  '/sys/devices/platform/mali.0/utilization',
  '/sys/module/ged/parameters/gpu_loading',
];

/// One `/sys/class/thermal/thermal_zoneN` reading.
class ThermalZone {
  const ThermalZone(this.type, this.celsius);
  final String type;
  final double celsius;
}

/// Parses `type=temp` lines produced by the thermal shell command below.
/// Temperatures are in millidegrees on almost every kernel; small values are
/// already whole degrees.
List<ThermalZone> parseThermalZones(String text) {
  final out = <ThermalZone>[];
  for (final line in text.split('\n')) {
    final i = line.lastIndexOf('=');
    if (i <= 0) continue;
    final raw = double.tryParse(line.substring(i + 1).trim());
    if (raw == null) continue;
    final c = raw.abs() > 1000 ? raw / 1000 : raw;
    if (c < -40 || c > 150) continue; // unplugged or bogus sensor
    out.add(ThermalZone(line.substring(0, i).trim(), c));
  }
  return out;
}

const thermalZonesCommand =
    'for z in /sys/class/thermal/thermal_zone*; do echo "\$(cat \$z/type)=\$(cat \$z/temp)"; done 2>/dev/null';

/// Per-UID estimated battery use from `dumpsys batterystats`, in mAh.
/// Lines look like `UID u0a174: 12.3 fg: 1.2 ...` (Android 12+) or
/// `Uid u0a174: 12.3 ( cpu=... )` (older).
Map<String, double> parseBatteryStatsPerUid(String text) {
  final out = <String, double>{};
  final re = RegExp(r'^\s*(?:UID|Uid)\s+(\w+):\s+([\d.]+)', multiLine: true);
  for (final m in re.allMatches(text)) {
    final v = double.tryParse(m.group(2)!);
    if (v == null) continue;
    out[m.group(1)!] = (out[m.group(1)!] ?? 0) + v;
  }
  return out;
}

/// Converts `u0a174` to Linux UID 10174 (user 0); plain numbers pass through.
int? uidFromAndroidName(String name) {
  final m = RegExp(r'^u(\d+)a(\d+)$').firstMatch(name);
  if (m != null) {
    return int.parse(m.group(1)!) * 100000 + 10000 + int.parse(m.group(2)!);
  }
  return int.tryParse(name);
}
