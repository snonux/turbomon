import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where TurboMon keeps its files, all inside the app's private storage.
class StoragePaths {
  const StoragePaths({required this.support, required this.cache});

  final Directory support;
  final Directory cache;

  static Future<StoragePaths> resolve() async => StoragePaths(
    support: await getApplicationSupportDirectory(),
    cache: await getTemporaryDirectory(),
  );

  Directory get history => Directory(p.join(support.path, 'history'));

  /// Snapshots saved by the background service and kept until deleted.
  Directory get savedSnapshots => Directory(p.join(support.path, 'snapshots'));

  /// Staging folder for sharing; matches `cache-path snapshots/` in the
  /// plugin's FileProvider paths.
  Directory get shareStaging => Directory(p.join(cache.path, 'snapshots'));
}
