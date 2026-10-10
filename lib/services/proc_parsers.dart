/// Pure parsers for `/proc`, sysfs and shell command output. They never touch
/// the filesystem, so tests feed them captured text from real devices.
library;

import '../models/readings.dart';

/// `/proc/meminfo` as bytes per key (the file reports kB).
Map<String, int> parseMeminfo(String text) {
  final result = <String, int>{};
  final line = RegExp(
    r'^(\w+(?:\(\w+\))?):\s+(\d+)(?:\s+kB)?',
    multiLine: true,
  );
  for (final m in line.allMatches(text)) {
    result[m.group(1)!] = int.parse(m.group(2)!) * 1024;
  }
  return result;
}

MemoryReading? memoryFromMeminfo(Map<String, int> info) {
  final total = info['MemTotal'];
  if (total == null) return null;
  final available =
      info['MemAvailable'] ??
      (info['MemFree'] ?? 0) + (info['Cached'] ?? 0) + (info['Buffers'] ?? 0);
  return MemoryReading(
    totalBytes: total,
    availableBytes: available,
    cachedBytes: info['Cached'],
    buffersBytes: info['Buffers'],
    swapTotalBytes: info['SwapTotal'],
    swapFreeBytes: info['SwapFree'],
  );
}

/// Jiffy counters of one `cpu` line in `/proc/stat`.
class CpuTimes {
  const CpuTimes(this.busy, this.total);

  final int busy;
  final int total;

  /// Utilisation between [previous] and this reading, 0–100.
  double percentSince(CpuTimes previous) {
    final dt = total - previous.total;
    if (dt <= 0) return 0;
    return ((busy - previous.busy) / dt * 100).clamp(0, 100).toDouble();
  }
}

/// `/proc/stat` CPU lines: key -1 is the aggregate, 0.. the cores.
Map<int, CpuTimes> parseProcStat(String text) {
  final result = <int, CpuTimes>{};
  for (final line in text.split('\n')) {
    final m = RegExp(r'^cpu(\d*)\s+(.*)$').firstMatch(line.trim());
    if (m == null) continue;
    final v = m.group(2)!.trim().split(RegExp(r'\s+')).map(int.parse).toList();
    if (v.length < 4) continue;
    // user nice system idle iowait irq softirq steal [guest guest_nice]
    // guest time is already counted in user, so only the first 8 are summed.
    final fields = v.take(8).toList();
    final total = fields.reduce((a, b) => a + b);
    final idle = fields[3] + (fields.length > 4 ? fields[4] : 0);
    final key = m.group(1)!.isEmpty ? -1 : int.parse(m.group(1)!);
    result[key] = CpuTimes(total - idle, total);
  }
  return result;
}

/// `/proc/loadavg`: the 1, 5 and 15 minute load averages.
List<double>? parseLoadavg(String text) {
  final parts = text.trim().split(RegExp(r'\s+'));
  if (parts.length < 3) return null;
  final values = parts.take(3).map(double.tryParse).toList();
  if (values.contains(null)) return null;
  return values.cast<double>();
}

/// Output of `top -b -n 1 -q -o PID,USER,S,%CPU,RES,ARGS` (toybox top, the
/// one Android ships). Column positions come from the header when present,
/// so extra or reordered columns do not break it. ARGS is always last and may
/// contain spaces.
List<ProcessInfo> parseTop(String text) {
  final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
  var columns = ['PID', 'USER', 'S', '%CPU', 'RES', 'ARGS'];
  final headerIndex = lines.indexWhere(
    (l) => RegExp(r'^\s*PID\s').hasMatch(l) && l.contains('%CPU'),
  );
  var start = 0;
  if (headerIndex >= 0) {
    // toybox marks the sort column with brackets, sometimes glued to its
    // neighbour: `RES[ARGS]`.
    columns = lines[headerIndex]
        .replaceAll('[', ' ')
        .replaceAll(']', ' ')
        .trim()
        .split(RegExp(r'\s+'));
    start = headerIndex + 1;
  }
  int col(String name) => columns.indexOf(name);
  final pid = col('PID'), user = col('USER'), state = col('S');
  final cpu = col('%CPU'), res = col('RES');
  final name = [
    'ARGS',
    'CMDLINE',
    'NAME',
    'CMD',
    'COMMAND',
  ].map(col).firstWhere((i) => i >= 0, orElse: () => columns.length - 1);
  if (pid < 0 || cpu < 0) return const [];

  final processes = <ProcessInfo>[];
  for (final line in lines.skip(start)) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length < columns.length) continue;
    final id = int.tryParse(parts[pid]);
    if (id == null) continue;
    processes.add(
      ProcessInfo(
        pid: id,
        user: user >= 0 ? parts[user] : '?',
        name: parts.sublist(name).join(' '),
        cpuPercent: double.tryParse(parts[cpu]) ?? 0,
        rssBytes: res >= 0 ? parseSizeWithUnit(parts[res]) : 0,
        state: state >= 0 ? parts[state] : '?',
      ),
    );
  }
  processes.sort((a, b) => b.cpuPercent.compareTo(a.cpuPercent));
  return processes;
}

/// toybox sizes such as `123456` (KiB), `98M`, `1.2G`.
int parseSizeWithUnit(String text) {
  final m = RegExp(
    r'^([\d.]+)([KMGT]?)$',
    caseSensitive: false,
  ).firstMatch(text);
  if (m == null) return 0;
  final value = double.parse(m.group(1)!);
  final unit = m.group(2)!.toUpperCase();
  const factors = {
    '': 1024,
    'K': 1024,
    'M': 1 << 20,
    'G': 1 << 30,
    'T': 1 << 40,
  };
  return (value * factors[unit]!).round();
}

/// Sector and operation counters of one block device.
class DiskCounters {
  const DiskCounters(
    this.reads,
    this.readSectors,
    this.writes,
    this.writeSectors,
  );

  final int reads;
  final int readSectors;
  final int writes;
  final int writeSectors;

  DiskCounters operator +(DiskCounters o) => DiskCounters(
    reads + o.reads,
    readSectors + o.readSectors,
    writes + o.writes,
    writeSectors + o.writeSectors,
  );
}

final _wholeDisk = RegExp(r'^(sd[a-z]+|mmcblk\d+|nvme\d+n\d+|vd[a-z]+)$');

/// `/proc/diskstats` summed over whole physical disks; partitions, loop,
/// zram and device-mapper entries are skipped so nothing is counted twice.
DiskCounters? parseDiskstats(String text) {
  DiskCounters? sum;
  for (final line in text.split('\n')) {
    final f = line.trim().split(RegExp(r'\s+'));
    if (f.length < 10 || !_wholeDisk.hasMatch(f[2])) continue;
    final c = DiskCounters(
      int.parse(f[3]),
      int.parse(f[5]),
      int.parse(f[7]),
      int.parse(f[9]),
    );
    sum = sum == null ? c : sum + c;
  }
  return sum;
}

/// `/proc/<pid>/io`: bytes this process read and wrote at the block layer.
({int read, int write})? parseProcIo(String text) {
  final read = RegExp(
    r'^read_bytes:\s+(\d+)',
    multiLine: true,
  ).firstMatch(text);
  final write = RegExp(
    r'^write_bytes:\s+(\d+)',
    multiLine: true,
  ).firstMatch(text);
  if (read == null || write == null) return null;
  return (read: int.parse(read.group(1)!), write: int.parse(write.group(1)!));
}

/// A thermal zone's `temp` file: millidegrees on most kernels, degrees on a
/// few. Implausible values (sensors parked at -273 or 0) are dropped.
double? parseThermalTemp(String text) {
  final raw = int.tryParse(text.trim());
  if (raw == null) return null;
  final celsius = raw.abs() >= 1000 ? raw / 1000 : raw.toDouble();
  if (celsius <= 0 || celsius > 150) return null;
  return celsius;
}

/// Lines of `type<TAB>temp` from the thermal-zone loop in [SystemReader].
List<ThermalZone> parseThermalZones(String text) {
  final zones = <ThermalZone>[];
  for (final line in text.split('\n')) {
    final parts = line.split('\t');
    if (parts.length != 2) continue;
    final celsius = parseThermalTemp(parts[1]);
    if (celsius != null) zones.add(ThermalZone(parts[0].trim(), celsius));
  }
  return zones;
}

/// GPU busy figure from vendor sysfs. Adreno's `gpu_busy_percentage` reads
/// `42 %`; Mali's `utilization` and Samsung's `gpu_busy` are bare numbers;
/// Adreno's `gpubusy` is `busy total` cycle counts.
double? parseGpuBusy(String text) {
  final t = text.trim();
  final pair = RegExp(r'^(\d+)\s+(\d+)$').firstMatch(t);
  if (pair != null) {
    final total = int.parse(pair.group(2)!);
    return total == 0 ? 0 : int.parse(pair.group(1)!) / total * 100;
  }
  final m = RegExp(r'^([\d.]+)\s*%?').firstMatch(t);
  final value = m == null ? null : double.tryParse(m.group(1)!);
  if (value == null || value < 0 || value > 100) return null;
  return value;
}

/// `dumpsys batterystats` estimated power per uid in mAh. Handles the
/// `UID u0a123: 12.3` form and the plain `UID 10123: 12.3` form.
Map<int, double> parseBatteryStatsPower(String text) {
  final result = <int, double>{};
  final row = RegExp(
    r'^\s*UID (u(\d+)a(\d+)|\d+|[a-z]+): ([\d.]+)',
    multiLine: true,
  );
  for (final m in row.allMatches(text)) {
    final id = m.group(1)!;
    int? uid;
    if (m.group(2) != null) {
      uid = int.parse(m.group(2)!) * 100000 + 10000 + int.parse(m.group(3)!);
    } else {
      uid = int.tryParse(id) ?? const {'root': 0, 'system': 1000}[id];
    }
    if (uid == null) continue;
    result[uid] = (result[uid] ?? 0) + double.parse(m.group(4)!);
  }
  return result;
}

/// Splits batched shell output at [marker] lines into named sections.
Map<String, String> splitSections(String output, String marker) {
  final sections = <String, String>{};
  String? current;
  final buffer = StringBuffer();
  for (final line in output.split('\n')) {
    if (line.startsWith(marker)) {
      if (current != null) sections[current] = buffer.toString();
      current = line.substring(marker.length).trim();
      buffer.clear();
    } else if (current != null) {
      buffer.writeln(line);
    }
  }
  if (current != null) sections[current] = buffer.toString();
  return sections;
}
