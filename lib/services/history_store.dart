import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Background history: one JSON Lines file per day (`2026-10-10.jsonl`) in
/// the app's private folder. Each line is one sample whose `t` is epoch ms.
class HistoryStore {
  HistoryStore(this.directory);

  final Directory directory;

  static String fileNameFor(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}.jsonl';

  Future<void> append(Map<String, Object?> record) async {
    final t = DateTime.fromMillisecondsSinceEpoch((record['t'] as num).toInt());
    await directory.create(recursive: true);
    await File(p.join(directory.path, fileNameFor(t))).writeAsString(
      '${jsonEncode(record)}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  /// Records with `since <= t <= until`, oldest first. Lines that do not
  /// parse (a write cut short by a kill) are skipped.
  Future<List<Map<String, Object?>>> read({
    required DateTime since,
    DateTime? until,
  }) async {
    final end = until ?? DateTime.now();
    final records = <Map<String, Object?>>[];
    for (final file in await _files()) {
      final day = _dayOf(file);
      if (day == null ||
          day.isAfter(end) ||
          day.add(const Duration(days: 1)).isBefore(since)) {
        continue;
      }
      for (final line in await file.readAsLines()) {
        if (line.trim().isEmpty) continue;
        try {
          final r = (jsonDecode(line) as Map).cast<String, Object?>();
          final t = DateTime.fromMillisecondsSinceEpoch(
            (r['t'] as num).toInt(),
          );
          if (!t.isBefore(since) && !t.isAfter(end)) records.add(r);
        } on FormatException {
          continue;
        }
      }
    }
    records.sort((a, b) => (a['t'] as num).compareTo(b['t'] as num));
    return records;
  }

  /// Deletes day files older than [days] before [now].
  Future<void> prune(int days, DateTime now) async {
    final cutoff = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: days));
    for (final file in await _files()) {
      final day = _dayOf(file);
      if (day != null && day.isBefore(cutoff)) await file.delete();
    }
  }

  Future<List<File>> _files() async {
    if (!await directory.exists()) return const [];
    return [
      await for (final e in directory.list())
        if (e is File && e.path.endsWith('.jsonl')) e,
    ]..sort((a, b) => a.path.compareTo(b.path));
  }

  static DateTime? _dayOf(File file) {
    final m = RegExp(r'(\d{4})-(\d{2})-(\d{2})\.jsonl$').firstMatch(file.path);
    if (m == null) return null;
    return DateTime(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
  }
}
