/// Typed readings for one sampling tick. Every value that a device or access
/// level may not provide is nullable, and the UI hides what is null rather
/// than showing a guess.
library;

/// One CPU core's clock, from `/sys/devices/system/cpu/cpuN/cpufreq`.
class CoreFrequency {
  const CoreFrequency({
    required this.index,
    this.currentKHz,
    this.minKHz,
    this.maxKHz,
  });

  final int index;
  final int? currentKHz;
  final int? minKHz;
  final int? maxKHz;

  /// Current clock as a share of the core's maximum, 0–100. This is the load
  /// proxy used when real CPU percentages are not readable.
  double? get sharePercent {
    final cur = currentKHz, max = maxKHz;
    if (cur == null || max == null || max <= 0) return null;
    return (cur / max * 100).clamp(0, 100).toDouble();
  }

  Map<String, Object?> toJson() => {
    'core': index,
    'curKHz': currentKHz,
    'minKHz': minKHz,
    'maxKHz': maxKHz,
  };
}

class CpuReading {
  const CpuReading({
    this.totalPercent,
    this.corePercents = const [],
    this.frequencies = const [],
    this.coreCount = 0,
  });

  /// Real utilisation from /proc/stat deltas; needs Shizuku or root.
  final double? totalPercent;
  final List<double> corePercents;
  final List<CoreFrequency> frequencies;
  final int coreCount;

  /// True when [load] is the frequency proxy rather than real utilisation.
  bool get isFrequencyProxy => totalPercent == null;

  /// The figure graphs plot: real CPU % when known, else mean clock share.
  double? get load {
    if (totalPercent != null) return totalPercent;
    final shares = [
      for (final f in frequencies)
        if (f.sharePercent != null) f.sharePercent!,
    ];
    if (shares.isEmpty) return null;
    return shares.reduce((a, b) => a + b) / shares.length;
  }

  /// Per-core figure for the header bars, real or proxy like [load].
  List<double?> get coreLoads {
    if (corePercents.isNotEmpty) return corePercents;
    return [for (final f in frequencies) f.sharePercent];
  }

  Map<String, Object?> toJson() => {
    'totalPercent': totalPercent,
    'corePercents': corePercents,
    'frequencies': [for (final f in frequencies) f.toJson()],
    'coreCount': coreCount,
  };
}

class MemoryReading {
  const MemoryReading({
    required this.totalBytes,
    required this.availableBytes,
    this.cachedBytes,
    this.buffersBytes,
    this.swapTotalBytes,
    this.swapFreeBytes,
  });

  final int totalBytes;
  final int availableBytes;
  final int? cachedBytes;
  final int? buffersBytes;
  final int? swapTotalBytes;
  final int? swapFreeBytes;

  int get usedBytes => totalBytes - availableBytes;

  double get usedPercent => totalBytes <= 0 ? 0 : usedBytes / totalBytes * 100;

  Map<String, Object?> toJson() => {
    'totalBytes': totalBytes,
    'availableBytes': availableBytes,
    'cachedBytes': cachedBytes,
    'buffersBytes': buffersBytes,
    'swapTotalBytes': swapTotalBytes,
    'swapFreeBytes': swapFreeBytes,
  };
}

class GpuReading {
  const GpuReading({this.busyPercent, this.frequencyMHz, required this.source});

  final double? busyPercent;
  final int? frequencyMHz;

  /// The sysfs path the figure came from, for the snapshot's context.
  final String source;

  Map<String, Object?> toJson() => {
    'busyPercent': busyPercent,
    'frequencyMHz': frequencyMHz,
    'source': source,
  };
}

class BatteryReading {
  const BatteryReading({
    this.percent,
    this.status = 'unknown',
    this.charging = false,
    this.plugged,
    this.health,
    this.temperatureC,
    this.voltageMv,
    this.currentMa,
    this.screenOn,
  });

  final double? percent;
  final String status;
  final bool charging;
  final String? plugged;
  final String? health;
  final double? temperatureC;
  final int? voltageMv;

  /// Normalised current in mA: positive while charging, negative while
  /// draining, whatever sign and unit the vendor reports.
  final double? currentMa;
  final bool? screenOn;

  /// Power in watts, signed like [currentMa].
  double? get powerW {
    final ma = currentMa, mv = voltageMv;
    if (ma == null || mv == null) return null;
    return ma * mv / 1e6;
  }

  /// Drain in mA as a positive number, or null while charging.
  double? get drainMa {
    final ma = currentMa;
    if (ma == null || ma >= 0) return null;
    return -ma;
  }

  Map<String, Object?> toJson() => {
    'percent': percent,
    'status': status,
    'charging': charging,
    'plugged': plugged,
    'health': health,
    'temperatureC': temperatureC,
    'voltageMv': voltageMv,
    'currentMa': currentMa,
    'powerW': powerW,
    'screenOn': screenOn,
  };
}

/// Bytes per second over the last interval, split by network type.
class NetworkRate {
  const NetworkRate({
    required this.rxBps,
    required this.txBps,
    required this.mobileRxBps,
    required this.mobileTxBps,
  });

  final double rxBps;
  final double txBps;
  final double mobileRxBps;
  final double mobileTxBps;

  /// Everything that is not mobile; on phones that is Wi-Fi (or Ethernet).
  double get wifiRxBps => (rxBps - mobileRxBps).clamp(0, double.infinity);
  double get wifiTxBps => (txBps - mobileTxBps).clamp(0, double.infinity);

  Map<String, Object?> toJson() => {
    'rxBps': rxBps,
    'txBps': txBps,
    'mobileRxBps': mobileRxBps,
    'mobileTxBps': mobileTxBps,
  };
}

class ThermalZone {
  const ThermalZone(this.name, this.celsius);

  final String name;
  final double celsius;

  Map<String, Object?> toJson() => {'name': name, 'celsius': celsius};
}

class ThermalReading {
  const ThermalReading({this.status, this.headroom, this.zones = const []});

  /// PowerManager thermal status, 0 (none) to 6 (shutdown).
  final int? status;

  /// Thermal headroom; 1.0 means throttling starts.
  final double? headroom;
  final List<ThermalZone> zones;

  static const statusNames = [
    'none',
    'light',
    'moderate',
    'severe',
    'critical',
    'emergency',
    'shutdown',
  ];

  String? get statusName =>
      status == null || status! < 0 || status! >= statusNames.length
      ? null
      : statusNames[status!];

  double? get hottest => zones.isEmpty
      ? null
      : zones.map((z) => z.celsius).reduce((a, b) => a > b ? a : b);

  Map<String, Object?> toJson() => {
    'status': statusName,
    'headroom': headroom,
    'zones': [for (final z in zones) z.toJson()],
  };
}

class DiskIoReading {
  const DiskIoReading({
    required this.readBps,
    required this.writeBps,
    this.readOps,
    this.writeOps,
    required this.scope,
  });

  final double readBps;
  final double writeBps;
  final double? readOps;
  final double? writeOps;

  /// `device` from /proc/diskstats (needs Shizuku or root), or `self` for
  /// TurboMon's own I/O from /proc/self/io.
  final String scope;

  Map<String, Object?> toJson() => {
    'readBps': readBps,
    'writeBps': writeBps,
    'readOps': readOps,
    'writeOps': writeOps,
    'scope': scope,
  };
}

class StorageVolume {
  const StorageVolume({
    required this.label,
    required this.path,
    required this.totalBytes,
    required this.freeBytes,
    this.removable = false,
  });

  factory StorageVolume.fromJson(Map<String, Object?> json) => StorageVolume(
    label: json['label'] as String? ?? 'Volume',
    path: json['path'] as String? ?? '',
    totalBytes: (json['total'] as num?)?.toInt() ?? 0,
    freeBytes: (json['free'] as num?)?.toInt() ?? 0,
    removable: json['removable'] as bool? ?? false,
  );

  final String label;
  final String path;
  final int totalBytes;
  final int freeBytes;
  final bool removable;

  int get usedBytes => totalBytes - freeBytes;
  double get usedPercent => totalBytes <= 0 ? 0 : usedBytes / totalBytes * 100;

  Map<String, Object?> toJson() => {
    'label': label,
    'totalBytes': totalBytes,
    'freeBytes': freeBytes,
    'removable': removable,
  };
}

/// One row of the top-style process table.
class ProcessInfo {
  const ProcessInfo({
    required this.pid,
    required this.user,
    required this.name,
    required this.cpuPercent,
    required this.rssBytes,
    required this.state,
    this.batteryMah,
  });

  final int pid;
  final String user;
  final String name;
  final double cpuPercent;
  final int rssBytes;
  final String state;

  /// Estimated use from `dumpsys batterystats`, joined by uid.
  final double? batteryMah;

  /// Kernel uid for an Android user name such as `u0_a123` (10123).
  int? get uid {
    final app = RegExp(r'^u(\d+)_a(\d+)$').firstMatch(user);
    if (app != null) {
      return int.parse(app.group(1)!) * 100000 +
          10000 +
          int.parse(app.group(2)!);
    }
    return const {'root': 0, 'system': 1000, 'shell': 2000}[user];
  }

  ProcessInfo withBattery(double? mah) => ProcessInfo(
    pid: pid,
    user: user,
    name: name,
    cpuPercent: cpuPercent,
    rssBytes: rssBytes,
    state: state,
    batteryMah: mah,
  );

  Map<String, Object?> toJson() => {
    'pid': pid,
    'user': user,
    'name': name,
    'cpuPercent': cpuPercent,
    'rssBytes': rssBytes,
    'state': state,
    if (batteryMah != null) 'batteryMah': batteryMah,
  };
}

/// Everything sampled in one tick. Fields are null when that monitor was not
/// sampled or the device does not provide it.
class SystemSample {
  const SystemSample({
    required this.time,
    this.cpu,
    this.memory,
    this.gpu,
    this.battery,
    this.network,
    this.thermal,
    this.diskIo,
  });

  final DateTime time;
  final CpuReading? cpu;
  final MemoryReading? memory;
  final GpuReading? gpu;
  final BatteryReading? battery;
  final NetworkRate? network;
  final ThermalReading? thermal;
  final DiskIoReading? diskIo;
}
