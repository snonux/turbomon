import 'package:flutter/material.dart';

import '../app_services.dart';
import '../services/format.dart';
import '../widgets/section_card.dart';

enum AppUsageKind {
  storage('App storage'),
  network('App network use (24 h)');

  const AppUsageKind(this.title);
  final String title;
}

/// Per-app storage sizes or network totals. Both need "usage access", which
/// the user grants in system settings; this screen explains and links there.
class AppUsageScreen extends StatefulWidget {
  const AppUsageScreen({super.key, required this.services, required this.kind});

  final AppServices services;
  final AppUsageKind kind;

  @override
  State<AppUsageScreen> createState() => _AppUsageScreenState();
}

class _AppUsageScreenState extends State<AppUsageScreen>
    with WidgetsBindingObserver {
  late Future<List<Map<String, Object?>>?> _rows;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _rows = _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Coming back from the usage access settings page: try again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) setState(() => _rows = _load());
  }

  /// Null when usage access is missing.
  Future<List<Map<String, Object?>>?> _load() async {
    final platform = widget.services.platform;
    if (!await platform.hasUsageAccess()) return null;
    return switch (widget.kind) {
      AppUsageKind.storage => platform.appStorage(),
      AppUsageKind.network => platform.appNetwork(
        DateTime.now().subtract(const Duration(hours: 24)),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.kind.title)),
      body: FutureBuilder(
        future: _rows,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Hint('Could not read usage: ${snapshot.error}'),
            );
          }
          final rows = snapshot.data;
          if (rows == null) return _askForAccess();
          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, i) => _tile(rows[i]),
          );
        },
      ),
    );
  }

  Widget _askForAccess() => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Per-app figures need usage access. Android grants it in system '
          'settings: find TurboMon in the list and switch it on.',
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: widget.services.platform.openUsageAccessSettings,
          child: const Text('Open usage access settings'),
        ),
      ],
    ),
  );

  Widget _tile(Map<String, Object?> row) {
    int n(String key) => (row[key] as num?)?.toInt() ?? 0;
    switch (widget.kind) {
      case AppUsageKind.storage:
        final total = n('appBytes') + n('dataBytes') + n('cacheBytes');
        return ListTile(
          dense: true,
          title: Text(row['label'] as String? ?? ''),
          subtitle: Text(
            'app ${formatBytes(n('appBytes'))} · data ${formatBytes(n('dataBytes'))} '
            '· cache ${formatBytes(n('cacheBytes'))}',
          ),
          trailing: Text(formatBytes(total)),
        );
      case AppUsageKind.network:
        return ListTile(
          dense: true,
          title: Text(row['name'] as String? ?? ''),
          subtitle: Text(
            '↓ ${formatBytes(n('rxBytes'))} · ↑ ${formatBytes(n('txBytes'))}',
          ),
          trailing: Text(formatBytes(n('rxBytes') + n('txBytes'))),
        );
    }
  }
}
