import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// One background sample as written by the Android service, one JSON object
/// per line in `files/history/YYYY-MM-DD.jsonl`.
class HistorySample {
  HistorySample(this.raw)
      : time = DateTime.fromMillisecondsSinceEpoch((raw['t'] as num?)?.toInt() ?? 0);

  final Map<String, Object?> raw;
  final DateTime time;

  double? num_(String k) => (raw[k] as num?)?.toDouble();
  String? get event => raw['event'] as String?;
}

/// Reads background history between two times.
class HistoryReader {
  HistoryReader(this.dir);
  final String dir;

  Future<List<HistorySample>> read(DateTime from, DateTime to) async {
    final out = <HistorySample>[];
    final d = Directory(dir);
    if (!await d.exists()) return out;
    final files = await d
        .list()
        .where((e) => e is File && e.path.endsWith('.jsonl'))
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    final fromDay = _day(from);
    final toDay = _day(to);
    for (final f in files) {
      final name = p.basenameWithoutExtension(f.path);
      if (name.compareTo(fromDay) < 0 || name.compareTo(toDay) > 0) continue;
      for (final line in await f.readAsLines()) {
        if (line.trim().isEmpty) continue;
        try {
          final j = jsonDecode(line);
          if (j is! Map) continue;
          final s = HistorySample(j.cast<String, Object?>());
          if (!s.time.isBefore(from) && !s.time.isAfter(to)) out.add(s);
        } on FormatException {
          // A line cut short by a crash or a full disk; skip it.
        }
      }
    }
    return out;
  }

  static String _day(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}
