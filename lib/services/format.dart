import 'package:intl/intl.dart';

/// Human-readable byte counts with binary units: `512 B`, `1.5 MiB`.
String formatBytes(num bytes, {int decimals = 1}) {
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value.abs() >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return unit == 0
      ? '${value.round()} ${units[unit]}'
      : '${value.toStringAsFixed(decimals)} ${units[unit]}';
}

/// A transfer rate: `0 B/s`, `12.3 KiB/s`.
String formatRate(num bytesPerSecond) => '${formatBytes(bytesPerSecond)}/s';

String formatPercent(num? value, {int decimals = 0}) =>
    value == null ? '–' : '${value.toStringAsFixed(decimals)} %';

/// `45 s`, `12 min`, `3 h 05 min`.
String formatDuration(Duration d) {
  if (d.inSeconds < 60) return '${d.inSeconds} s';
  if (d.inMinutes < 60) return '${d.inMinutes} min';
  final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
  return '${d.inHours} h $minutes min';
}

String formatMhz(int? khz) => khz == null ? '–' : '${(khz / 1000).round()} MHz';

String formatTime(DateTime t) => DateFormat.Hms().format(t);

String formatDateTime(DateTime t) =>
    DateFormat('yyyy-MM-dd HH:mm:ss').format(t);
