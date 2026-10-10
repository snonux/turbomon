import 'dart:io';

/// Reads `/proc` and sysfs files; a seam so tests can serve captured text.
abstract interface class FileSource {
  /// The file's content, or null when it is missing or unreadable.
  Future<String?> read(String path);

  /// Paths in [directory] whose name starts with [prefix]; empty if unreadable.
  Future<List<String>> list(String directory, String prefix);
}

class LocalFileSource implements FileSource {
  const LocalFileSource();

  @override
  Future<String?> read(String path) async {
    try {
      // sysfs files report a size of 0, so read to EOF rather than by length.
      return await File(path).readAsString();
    } on Object {
      return null;
    }
  }

  @override
  Future<List<String>> list(String directory, String prefix) async {
    try {
      return [
        await for (final entity in Directory(directory).list())
          if (entity.uri.pathSegments
              .lastWhere((s) => s.isNotEmpty)
              .startsWith(prefix))
            entity.path,
      ]..sort();
    } on Object {
      return const [];
    }
  }
}
