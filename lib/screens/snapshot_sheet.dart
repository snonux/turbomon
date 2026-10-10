import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app_services.dart';
import '../services/snapshot.dart';
import '../services/snapshot_collector.dart';

/// The snapshot dialog, reachable from every screen.
Future<void> showSnapshotSheet(BuildContext context, AppServices services) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SnapshotSheet(services: services),
    );

class SnapshotSheet extends StatefulWidget {
  const SnapshotSheet({super.key, required this.services});

  final AppServices services;

  @override
  State<SnapshotSheet> createState() => _SnapshotSheetState();
}

class _SnapshotSheetState extends State<SnapshotSheet> {
  bool _bssids = false;
  bool _btAddresses = false;
  bool _history = false;
  bool _busy = false;

  SnapshotCollector get _collector => SnapshotCollector(widget.services);

  Future<String> _report() => _collector.build(
    options: SnapshotOptions(
      includeBssids: _bssids,
      includeBluetoothAddresses: _btAddresses,
    ),
    includeHistory: _history,
  );

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Snapshot failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() => _run(() async {
    final file = await _collector.stage(await _report());
    await widget.services.platform.shareFile(file.path, 'text/markdown');
  });

  Future<void> _save() => _run(() async {
    final saved = await widget.services.platform.saveFile(
      snapshotFileName(DateTime.now()),
      await _report(),
    );
    if (saved && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Snapshot saved')));
    }
  });

  Future<void> _preview() => _run(() async {
    final report = await _report();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            _ReportScreen(title: 'Snapshot preview', report: report),
      ),
    );
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Snapshot', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Freezes the graphs, processes, radios and findings into one '
              'Markdown report that a person can read and an LLM can parse.',
              style: theme.textTheme.bodySmall,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Include Wi-Fi BSSIDs'),
              subtitle: const Text(
                'Off by default: they can reveal your location',
              ),
              value: _bssids,
              onChanged: (v) => setState(() => _bssids = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Include Bluetooth addresses'),
              value: _btAddresses,
              onChanged: (v) => setState(() => _btAddresses = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Include background history'),
              subtitle: const Text(
                'The last 24 hours, if background scanning ran',
              ),
              value: _history,
              onChanged: (v) => setState(() => _history = v),
            ),
            if (_busy) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _share,
                  icon: const Icon(Icons.share),
                  label: const Text('Share'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Save'),
                ),
                TextButton(
                  onPressed: _busy ? null : _preview,
                  child: const Text('Preview'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          SavedSnapshotsScreen(services: widget.services),
                    ),
                  ),
                  child: const Text('Saved'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Snapshots the background service saved at the end of a run or on alert.
class SavedSnapshotsScreen extends StatefulWidget {
  const SavedSnapshotsScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<SavedSnapshotsScreen> createState() => _SavedSnapshotsScreenState();
}

class _SavedSnapshotsScreenState extends State<SavedSnapshotsScreen> {
  late Future<List<File>> _files = SnapshotCollector(widget.services).saved();

  Future<void> _share(File file) async {
    final staged = await SnapshotCollector(
      widget.services,
    ).stage(await file.readAsString(), name: p.basename(file.path));
    await widget.services.platform.shareFile(staged.path, 'text/markdown');
  }

  Future<void> _delete(File file) async {
    await file.delete();
    setState(() => _files = SnapshotCollector(widget.services).saved());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved snapshots')),
      body: FutureBuilder(
        future: _files,
        builder: (context, snapshot) {
          final files = snapshot.data ?? const <File>[];
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (files.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'None yet. Background scans save one when they stop, if '
                '"Snapshot when it stops" is on, and so do alerts with '
                'Snapshot ticked.',
              ),
            );
          }
          return ListView(
            children: [
              for (final f in files)
                ListTile(
                  title: Text(p.basename(f.path)),
                  onTap: () async {
                    final report = await f.readAsString();
                    if (!context.mounted) return;
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => _ReportScreen(
                          title: p.basename(f.path),
                          report: report,
                        ),
                      ),
                    );
                  },
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Share',
                        icon: const Icon(Icons.share),
                        onPressed: () => _share(f),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _delete(f),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ReportScreen extends StatelessWidget {
  const _ReportScreen({required this.title, required this.report});

  final String title;
  final String report;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: SelectableText(
        report,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
      ),
    ),
  );
}
