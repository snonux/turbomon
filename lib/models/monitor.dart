/// The monitors background scanning can run, each with its own interval.
enum Monitor {
  cpu('CPU', 30),
  ram('RAM', 30),
  gpu('GPU', 30),
  battery('Battery', 30),
  network('Network speed', 30),
  temperature('Temperatures', 60),
  storage('Disk usage', 900),
  diskIo('Disk I/O', 30),
  wifi('Wi-Fi', 300),
  bluetooth('Bluetooth', 300),
  processes('Process list', 60);

  const Monitor(this.label, this.defaultIntervalSeconds);

  final String label;
  final int defaultIntervalSeconds;

  /// Monitors that only work with Shizuku or root.
  bool get needsPrivilege => this == processes;

  /// Background limits Android applies; shown as a warning in Settings.
  String? get backgroundWarning => switch (this) {
    wifi => 'Android may limit background Wi-Fi scans to one every 30 min.',
    bluetooth => 'Unfiltered Bluetooth scans pause while the screen is off.',
    _ => null,
  };

  static Monitor? byName(String name) {
    for (final m in values) {
      if (m.name == name) return m;
    }
    return null;
  }
}
