/// Battery state as TurboMon shows it, after normalising vendor quirks.
class BatteryReading {
  const BatteryReading({
    required this.levelPercent,
    required this.charging,
    required this.status,
    required this.plugged,
    required this.health,
    this.tempC,
    this.voltageMv,
    this.currentMa,
    this.chargeCounterMah,
  });

  final int levelPercent;
  final bool charging;
  final String status;
  final String plugged;
  final String health;
  final double? tempC;
  final int? voltageMv;

  /// Signed, Android's convention: positive flows into the battery.
  final double? currentMa;
  final double? chargeCounterMah;

  /// Current drawn from the battery, positive while discharging, 0 when charging.
  double? get drainMa => currentMa == null ? null : (currentMa! < 0 ? -currentMa! : 0);

  /// Power in watts flowing in or out, always positive.
  double? get powerW => (currentMa == null || voltageMv == null)
      ? null
      : currentMa!.abs() / 1000 * voltageMv! / 1000;

  factory BatteryReading.fromMap(Map<String, Object?> m) {
    final status = (m['status'] as String?) ?? 'unknown';
    final charging = status == 'charging' || status == 'full';
    final raw = (m['currentNowUa'] as num?)?.toInt();
    final counter = (m['chargeCounterUah'] as num?)?.toInt();
    return BatteryReading(
      levelPercent: (m['level'] as num?)?.toInt() ?? 0,
      charging: charging,
      status: status,
      plugged: (m['plugged'] as String?) ?? 'none',
      health: (m['health'] as String?) ?? 'unknown',
      tempC: (m['tempC'] as num?)?.toDouble(),
      voltageMv: (m['voltageMv'] as num?)?.toInt(),
      currentMa: normalizeCurrentMa(raw, charging: status == 'charging'),
      chargeCounterMah: (counter == null || counter <= 0) ? null : counter / 1000,
    );
  }
}

/// `BATTERY_PROPERTY_CURRENT_NOW` is documented as microamperes, positive
/// when charging. Some vendors report milliamperes, and some flip the sign.
/// Values above 20 000 can only be µA (no phone draws 20 A); the sign is
/// taken from the charging state instead of trusted.
double? normalizeCurrentMa(int? raw, {required bool charging}) {
  if (raw == null || raw == 0 || raw == -2147483648 || raw == 2147483647) return null;
  var ma = raw.abs() > 20000 ? raw / 1000 : raw.toDouble();
  if (charging && ma < 0) ma = -ma;
  if (!charging && ma > 0) ma = -ma;
  return ma;
}

/// One row of the process table.
class ProcessRow {
  const ProcessRow({
    required this.pid,
    required this.user,
    required this.name,
    required this.cpuPercent,
    required this.rssKb,
    required this.state,
    this.batteryMah,
    this.ioReadBps,
    this.ioWriteBps,
  });

  final int pid;
  final String user;
  final String name;
  final double cpuPercent;
  final int rssKb;
  final String state;
  final double? batteryMah;
  final double? ioReadBps;
  final double? ioWriteBps;

  /// `u0_a174` (ps) to `u0a174` (batterystats), for matching per-app battery.
  String get batteryUid => user.replaceAll('_', '');

  Map<String, Object?> toJson() => {
        'pid': pid,
        'user': user,
        'name': name,
        'cpu': double.parse(cpuPercent.toStringAsFixed(1)),
        'rssKb': rssKb,
        'state': state,
        if (batteryMah != null) 'batteryMah': double.parse(batteryMah!.toStringAsFixed(1)),
        if (ioReadBps != null) 'ioReadBps': ioReadBps!.round(),
        if (ioWriteBps != null) 'ioWriteBps': ioWriteBps!.round(),
      };
}

class StorageVolume {
  const StorageVolume({
    required this.label,
    required this.path,
    required this.totalBytes,
    required this.freeBytes,
    required this.removable,
  });
  final String label;
  final String path;
  final int totalBytes;
  final int freeBytes;
  final bool removable;
  int get usedBytes => totalBytes - freeBytes;
  double get usedPercent => totalBytes == 0 ? 0 : usedBytes * 100 / totalBytes;

  factory StorageVolume.fromMap(Map<String, Object?> m) => StorageVolume(
        label: (m['label'] as String?) ?? 'Storage',
        path: (m['path'] as String?) ?? '',
        totalBytes: (m['totalBytes'] as num?)?.toInt() ?? 0,
        freeBytes: (m['freeBytes'] as num?)?.toInt() ?? 0,
        removable: (m['removable'] as bool?) ?? false,
      );

  Map<String, Object?> toJson() =>
      {'label': label, 'totalBytes': totalBytes, 'freeBytes': freeBytes, 'removable': removable};
}

class AppSize {
  const AppSize(this.package, this.label, this.appBytes, this.dataBytes, this.cacheBytes);
  final String package;
  final String label;
  final int appBytes;
  final int dataBytes;
  final int cacheBytes;
  int get total => appBytes + dataBytes + cacheBytes;

  factory AppSize.fromMap(Map<String, Object?> m) => AppSize(
        (m['package'] as String?) ?? '',
        (m['label'] as String?) ?? '',
        (m['appBytes'] as num?)?.toInt() ?? 0,
        (m['dataBytes'] as num?)?.toInt() ?? 0,
        (m['cacheBytes'] as num?)?.toInt() ?? 0,
      );
}

const thermalStatusNames = [
  'none',
  'light',
  'moderate',
  'severe',
  'critical',
  'emergency',
  'shutdown',
];

String formatBytes(num bytes, {int digits = 1}) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v.abs() >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(i == 0 ? 0 : digits)} ${units[i]}';
}

String formatRate(num bytesPerSec) => '${formatBytes(bytesPerSec)}/s';
