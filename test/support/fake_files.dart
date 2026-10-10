import 'package:turbomon/services/file_source.dart';

/// Serves fixed file contents by path.
class FakeFiles implements FileSource {
  FakeFiles([Map<String, String>? files]) : files = files ?? {};

  final Map<String, String> files;

  @override
  Future<String?> read(String path) async => files[path];

  @override
  Future<List<String>> list(String directory, String prefix) async => {
    for (final p in files.keys)
      if (p.startsWith('$directory/$prefix'))
        p.substring(0, p.lastIndexOf('/')),
  }.toList()..sort();
}
