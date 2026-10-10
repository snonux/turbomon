import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../model/readings.dart';
import '../services/app_state.dart';

/// Saved snapshot reports: view, share, save elsewhere, delete.
class SnapshotsScreen extends StatefulWidget {
  const SnapshotsScreen({super.key, required this.state});
  final AppState state;

  @override
  State<SnapshotsScreen> createState() => _SnapshotsScreenState();
}

class _SnapshotsScreenState extends State<SnapshotsScreen> {
  late Future<List<File>> _files = widget.state.listSnapshots();

  void _reload() => setState(() => _files = widget.state.listSnapshots());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Snapshots')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.photo_camera_outlined),
        label: const Text('Take snapshot'),
        onPressed: () async {
          await widget.state.takeSnapshot();
          _reload();
        },
      ),
      body: FutureBuilder<List<File>>(
        future: _files,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final files = snap.data!;
          if (files.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No snapshots yet. A snapshot saves what TurboMon sees as a Markdown report '
                  'an LLM can read to find the cause of a CPU, battery or heat problem.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            children: [
              for (final f in files)
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(p.basename(f.path)),
                  subtitle: Text(formatBytes(f.lengthSync())),
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => SnapshotViewScreen(state: widget.state, file: f),
                    ));
                    _reload();
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

class SnapshotViewScreen extends StatelessWidget {
  const SnapshotViewScreen({super.key, required this.state, required this.file});
  final AppState state;
  final File file;

  @override
  Widget build(BuildContext context) {
    final name = p.basename(file.path);
    return Scaffold(
      appBar: AppBar(
        title: Text(name, style: const TextStyle(fontSize: 15)),
        actions: [
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.share),
            onPressed: () => state.bridge.shareFile(file.path, 'text/markdown'),
          ),
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await Clipboard.setData(ClipboardData(text: await file.readAsString()));
              messenger.showSnackBar(const SnackBar(content: Text('Copied, paste it into your LLM chat')));
            },
          ),
          IconButton(
            tooltip: 'Save as',
            icon: const Icon(Icons.save_alt),
            onPressed: () => state.bridge.saveFileAs(file.path, name, 'text/markdown'),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final nav = Navigator.of(context);
              await file.delete();
              nav.pop();
            },
          ),
        ],
      ),
      body: FutureBuilder<String>(
        future: file.readAsString(),
        builder: (context, snap) => snap.hasData
            ? SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  snap.data!,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              )
            : const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
