import 'dart:io';

import 'package:path/path.dart' as p;

import '../app_services.dart';
import 'snapshot.dart';

/// Freezes what the app has collected into a snapshot report.
class SnapshotCollector {
  const SnapshotCollector(this.services);

  final AppServices services;

  Future<String> build({
    SnapshotOptions options = const SnapshotOptions(),
    bool includeHistory = false,
  }) async {
    final hub = services.hub;
    final now = DateTime.now();
    final access = services.access;
    final input = SnapshotInput(
      generatedAt: now,
      device: await services.platform.device(),
      // An unanswered shell explains missing CPU and process data.
      accessLevel: access.shellError == null
          ? access.level.label
          : '${access.level.label}, not answering: ${access.shellError}',
      series: hub.series,
      coreSeries: hub.coreSeries,
      latest: hub.latest,
      cpuIsFrequencyProxy: hub.latest?.cpu?.isFrequencyProxy ?? true,
      processes: hub.processes,
      processAverages: hub.processAverages,
      volumes: hub.volumes,
      wifiLink: services.wifi.link,
      wifiNetworks: services.wifi.networks,
      bluetoothNearby: services.bluetooth.devices,
      bluetoothPaired: services.bluetooth.paired,
      alerts: hub.firedAlerts,
      history: includeHistory
          ? await services.history.read(
              since: now.subtract(const Duration(hours: 24)),
            )
          : const [],
      diagnostics: await services.reader.diagnostics(),
    );
    return buildSnapshot(input, options);
  }

  /// Writes [report] to the share staging folder and returns the file.
  Future<File> stage(String report, {String? name}) async {
    final dir = services.paths.shareStaging;
    await dir.create(recursive: true);
    final file = File(
      p.join(dir.path, name ?? snapshotFileName(DateTime.now())),
    );
    return file.writeAsString(report);
  }

  /// Builds a snapshot and keeps it with the saved ones, as an alert does.
  Future<File> save() async {
    final dir = services.paths.savedSnapshots;
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, snapshotFileName(DateTime.now())));
    return file.writeAsString(await build());
  }

  /// Snapshots saved by background runs and alerts, newest first.
  Future<List<File>> saved() async {
    final dir = services.paths.savedSnapshots;
    if (!await dir.exists()) return const [];
    return [
      await for (final e in dir.list())
        if (e is File && e.path.endsWith('.md')) e,
    ]..sort((a, b) => b.path.compareTo(a.path));
  }
}
