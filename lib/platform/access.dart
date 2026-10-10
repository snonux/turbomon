import 'dart:async';
import 'dart:io';

import '../model/settings.dart';
import 'native_bridge.dart';

/// The access TurboMon actually has right now.
enum AccessLevel {
  normal('Normal app'),
  shizuku('Shizuku'),
  root('Root');

  const AccessLevel(this.label);
  final String label;
  bool get elevated => this != AccessLevel.normal;
}

/// Reads files the app may or may not be allowed to see. Returns null on any
/// error, so callers can fall back without try/catch everywhere.
abstract class SystemFiles {
  Future<String?> read(String path);
}

class RealSystemFiles implements SystemFiles {
  @override
  Future<String?> read(String path) async {
    try {
      return await File(path).readAsString();
    } on Object {
      return null;
    }
  }
}

/// Runs commands with shell (Shizuku) or root rights, or not at all.
abstract class PrivilegedShell {
  AccessLevel get level;
  Future<ShellResult> run(String command);
}

class NoShell implements PrivilegedShell {
  const NoShell();
  @override
  AccessLevel get level => AccessLevel.normal;
  @override
  Future<ShellResult> run(String command) async =>
      const ShellResult(-1, '', 'no elevated access');
}

class RootShell implements PrivilegedShell {
  @override
  AccessLevel get level => AccessLevel.root;
  @override
  Future<ShellResult> run(String command) async {
    try {
      final r = await Process.run('su', ['-c', command])
          .timeout(const Duration(seconds: 10));
      return ShellResult(r.exitCode, r.stdout.toString(), r.stderr.toString());
    } on Object catch (e) {
      return ShellResult(-1, '', '$e');
    }
  }

  static Future<bool> available() async {
    try {
      final r = await Process.run('su', ['-c', 'id'])
          .timeout(const Duration(seconds: 15));
      return r.exitCode == 0 && r.stdout.toString().contains('uid=0');
    } on Object {
      return false;
    }
  }
}

class ShizukuShell implements PrivilegedShell {
  ShizukuShell(this.bridge);
  final NativeBridge bridge;
  @override
  AccessLevel get level => AccessLevel.shizuku;
  @override
  Future<ShellResult> run(String command) async {
    try {
      return await bridge.shizukuExec(command).timeout(const Duration(seconds: 10));
    } on Object catch (e) {
      return ShellResult(-1, '', '$e');
    }
  }
}

/// Picks the shell for the user's [AccessMode]. Automatic prefers Shizuku
/// (no su prompt, survives without root) and falls back to root.
Future<PrivilegedShell> resolveShell(
  AccessMode mode,
  NativeBridge bridge, {
  Future<bool> Function() rootAvailable = RootShell.available,
  bool requestShizuku = false,
}) async {
  Future<PrivilegedShell?> shizuku() async {
    var state = await bridge.shizukuState();
    if (state == 'denied' && requestShizuku) {
      if (await bridge.requestShizuku()) state = 'granted';
    }
    return state == 'granted' ? ShizukuShell(bridge) : null;
  }

  switch (mode) {
    case AccessMode.normal:
      return const NoShell();
    case AccessMode.shizuku:
      return await shizuku() ?? const NoShell();
    case AccessMode.root:
      return await rootAvailable() ? RootShell() : const NoShell();
    case AccessMode.auto:
      final s = await shizuku();
      if (s != null) return s;
      return await rootAvailable() ? RootShell() : const NoShell();
  }
}
