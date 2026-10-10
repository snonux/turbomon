import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:turbomon_platform/turbomon_platform.dart';

/// What TurboMon can read on this device right now.
enum AccessLevel {
  normal('Normal app'),
  shizuku('Shizuku (ADB shell)'),
  root('Root');

  const AccessLevel(this.label);
  final String label;
}

/// What the user asked for in Settings. [auto] uses Shizuku when it is
/// running and granted, and never triggers a root prompt on its own.
enum AccessMode {
  auto('Automatic'),
  normal('Normal app only'),
  shizuku('Shizuku'),
  root('Root');

  const AccessMode(this.label);
  final String label;
}

/// Runs shell scripts with elevated rights.
abstract interface class ShellRunner {
  Future<String> run(String script);
}

class ShizukuRunner implements ShellRunner {
  const ShizukuRunner(this.platform);

  final TurboMonPlatform platform;

  @override
  Future<String> run(String script) => platform.shizukuExec(script);
}

class RootRunner implements ShellRunner {
  const RootRunner();

  static const _timeout = Duration(seconds: 15);

  @override
  Future<String> run(String script) async {
    final result = await Process.run('su', ['-c', script]).timeout(_timeout);
    return result.stdout as String;
  }

  /// Whether `su` exists and grants uid 0. On Magisk this shows its prompt
  /// the first time, so it only runs when the user picks root mode.
  static Future<bool> available() async {
    try {
      final result = await Process.run('su', ['-c', 'id -u']).timeout(_timeout);
      return result.exitCode == 0 && (result.stdout as String).trim() == '0';
    } on Object {
      return false;
    }
  }
}

/// Status of the optional Shizuku service as the platform reports it.
class ShizukuStatus {
  const ShizukuStatus({this.running = false, this.granted = false});

  factory ShizukuStatus.fromJson(Map<String, Object?> json) => ShizukuStatus(
    running: json['running'] as bool? ?? false,
    granted: json['granted'] as bool? ?? false,
  );

  final bool running;
  final bool granted;
}

/// Resolves the [AccessMode] the user chose into a working [AccessLevel] and
/// the shell runner that goes with it.
class AccessController extends ChangeNotifier {
  AccessController(this.platform);

  final TurboMonPlatform platform;

  AccessLevel _level = AccessLevel.normal;
  ShellRunner? _runner;
  String? _problem;
  ShizukuStatus _shizuku = const ShizukuStatus();

  AccessLevel get level => _level;
  ShellRunner? get runner => _runner;
  ShizukuStatus get shizuku => _shizuku;

  /// Why the requested mode fell back to normal, for the Settings screen.
  String? get problem => _problem;

  bool get privileged => _runner != null;

  /// Picks the access level for [mode]. With [interactive] false (the
  /// background service), Shizuku's permission dialog is never shown.
  Future<void> resolve(AccessMode mode, {bool interactive = true}) async {
    _shizuku = await _shizukuStatus();
    var level = AccessLevel.normal;
    String? problem;
    switch (mode) {
      case AccessMode.normal:
        break;
      case AccessMode.auto:
        if (_shizuku.granted) level = AccessLevel.shizuku;
      case AccessMode.shizuku:
        if (!_shizuku.running) {
          problem = 'Shizuku is not running. Install it and start its service.';
        } else if (!_shizuku.granted) {
          final granted =
              interactive && await platform.shizukuRequestPermission();
          _shizuku = await _shizukuStatus();
          if (granted) {
            level = AccessLevel.shizuku;
          } else {
            problem = 'TurboMon has no permission in Shizuku.';
          }
        } else {
          level = AccessLevel.shizuku;
        }
      case AccessMode.root:
        if (await RootRunner.available()) {
          level = AccessLevel.root;
        } else {
          problem = 'su is missing or did not grant root.';
        }
    }
    _level = level;
    _problem = problem;
    _runner = switch (level) {
      AccessLevel.normal => null,
      AccessLevel.shizuku => ShizukuRunner(platform),
      AccessLevel.root => const RootRunner(),
    };
    notifyListeners();
  }

  Future<ShizukuStatus> _shizukuStatus() async {
    try {
      return ShizukuStatus.fromJson(await platform.shizukuStatus());
    } on Object {
      return const ShizukuStatus();
    }
  }
}
