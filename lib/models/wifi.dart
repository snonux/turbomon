import 'dart:math' as math;

enum WifiBand {
  ghz24('2.4 GHz'),
  ghz5('5 GHz'),
  ghz6('6 GHz');

  const WifiBand(this.label);
  final String label;

  static WifiBand? ofFrequency(int mhz) {
    if (mhz >= 2400 && mhz < 2500) return ghz24;
    if (mhz >= 4900 && mhz < 5900) return ghz5;
    if (mhz >= 5925 && mhz <= 7125) return ghz6;
    return null;
  }

  /// Every channel the band's graph shows on its x-axis, empty ones included.
  List<int> get channels => switch (this) {
    ghz24 => [for (var c = 1; c <= 13; c++) c],
    ghz5 => const [
      36, 40, 44, 48, 52, 56, 60, 64, //
      100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 144, //
      149, 153, 157, 161, 165,
    ],
    ghz6 => [for (var c = 1; c <= 233; c += 4) c],
  };

  /// Centre frequency of [channel] in MHz.
  int frequencyOf(int channel) => switch (this) {
    ghz24 => channel == 14 ? 2484 : 2407 + channel * 5,
    ghz5 => 5000 + channel * 5,
    ghz6 => 5950 + channel * 5,
  };

  int channelOf(int mhz) => switch (this) {
    ghz24 => mhz == 2484 ? 14 : (mhz - 2407) ~/ 5,
    ghz5 => (mhz - 5000) ~/ 5,
    ghz6 => (mhz - 5950) ~/ 5,
  };

  /// 5 GHz channels that need radar detection (DFS) in most regions.
  bool isDfs(int channel) => this == ghz5 && channel >= 52 && channel <= 144;

  /// Channels a new network should pick from: the non-overlapping 1/6/11 on
  /// 2.4 GHz, non-DFS channels on 5 GHz, preferred scanning channels on 6 GHz.
  List<int> get recommendable => switch (this) {
    ghz24 => const [1, 6, 11],
    ghz5 => [
      for (final c in channels)
        if (!isDfs(c)) c,
    ],
    ghz6 => [for (var c = 5; c <= 229; c += 16) c],
  };
}

/// One access point from a scan.
class WifiNetwork {
  const WifiNetwork({
    required this.ssid,
    required this.bssid,
    required this.rssi,
    required this.frequency,
    this.centerFrequency,
    this.channelWidth = 20,
    this.capabilities = '',
    this.standard,
    this.ageMs = 0,
  });

  factory WifiNetwork.fromJson(Map<String, Object?> json) {
    final freq = (json['frequency'] as num?)?.toInt() ?? 0;
    final center = (json['centerFreq0'] as num?)?.toInt() ?? 0;
    return WifiNetwork(
      ssid: json['ssid'] as String? ?? '',
      bssid: json['bssid'] as String? ?? '',
      rssi: (json['rssi'] as num?)?.toInt() ?? -100,
      frequency: freq,
      centerFrequency: center > 0 ? center : null,
      channelWidth: (json['channelWidth'] as num?)?.toInt() ?? 20,
      capabilities: json['capabilities'] as String? ?? '',
      standard: (json['standard'] as num?)?.toInt(),
      ageMs: (json['ageMs'] as num?)?.toInt() ?? 0,
    );
  }

  final String ssid;
  final String bssid;
  final int rssi;

  /// Primary channel frequency in MHz.
  final int frequency;

  /// Centre of the whole (bonded) channel for widths above 20 MHz.
  final int? centerFrequency;
  final int channelWidth;
  final String capabilities;

  /// Android's WifiAnnotations.WifiStandard code.
  final int? standard;
  final int ageMs;

  WifiBand? get band => WifiBand.ofFrequency(frequency);
  int? get channel => band?.channelOf(frequency);
  bool get hidden => ssid.isEmpty;
  String get displayName => hidden ? '(hidden network)' : ssid;

  /// Frequency range the network occupies, in MHz.
  ({double low, double high}) get span {
    final center = (channelWidth > 20 ? centerFrequency : null) ?? frequency;
    return (low: center - channelWidth / 2, high: center + channelWidth / 2);
  }

  /// Whether this network's span overlaps the 20 MHz block of [channel].
  bool overlaps(WifiBand band, int channel) {
    final f = band.frequencyOf(channel);
    final s = span;
    // 2.4 GHz channels are 5 MHz apart but 20-22 MHz wide, so neighbours
    // overlap; a strict inequality keeps channels 1 and 6 apart.
    return s.low < f + 10 && s.high > f - 10;
  }

  String get security {
    final c = capabilities.toUpperCase();
    if (c.contains('SAE') || c.contains('WPA3')) return 'WPA3';
    if (c.contains('WPA2') || c.contains('RSN')) return 'WPA2';
    if (c.contains('WPA')) return 'WPA';
    if (c.contains('WEP')) return 'WEP';
    if (c.contains('OWE')) return 'OWE';
    return 'Open';
  }

  String? get standardName => switch (standard) {
    1 => 'legacy',
    4 => 'Wi-Fi 4',
    5 => 'Wi-Fi 5',
    6 => 'Wi-Fi 6',
    7 => 'WiGig',
    8 => 'Wi-Fi 7',
    _ => null,
  };

  /// Signal as a 0–1 bar between -100 dBm (nothing) and -30 dBm (excellent).
  double get strength => ((rssi + 100) / 70).clamp(0, 1).toDouble();

  /// Linear power, for summing interference from several networks.
  double get milliwatts => math.pow(10, rssi / 10).toDouble();

  Map<String, Object?> toJson({bool includeBssid = false}) => {
    'ssid': displayName,
    if (includeBssid) 'bssid': bssid,
    'rssi': rssi,
    'frequency': frequency,
    'channel': channel,
    'channelWidth': channelWidth,
    'security': security,
    if (standardName != null) 'standard': standardName,
  };
}

/// The connected network's live link, which is not scan-throttled.
class WifiLink {
  const WifiLink({
    this.ssid,
    this.bssid,
    required this.rssi,
    this.linkMbps,
    this.frequency,
    this.txMbps,
    this.rxMbps,
  });

  factory WifiLink.fromJson(Map<String, Object?> json) => WifiLink(
    ssid: json['ssid'] as String?,
    bssid: json['bssid'] as String?,
    rssi: (json['rssi'] as num?)?.toInt() ?? -127,
    linkMbps: (json['linkMbps'] as num?)?.toInt(),
    frequency: (json['frequency'] as num?)?.toInt(),
    txMbps: (json['txMbps'] as num?)?.toInt(),
    rxMbps: (json['rxMbps'] as num?)?.toInt(),
  );

  final String? ssid;
  final String? bssid;
  final int rssi;
  final int? linkMbps;
  final int? frequency;
  final int? txMbps;
  final int? rxMbps;

  /// Android reports -127 when there is no usable reading.
  bool get valid => rssi > -127;

  Map<String, Object?> toJson() => {
    'ssid': ssid,
    'rssi': rssi,
    'linkMbps': linkMbps,
    'frequency': frequency,
  };
}
