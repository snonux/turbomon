// Wi-Fi band and channel arithmetic, independent of Android so it can be
// tested and reused by the channel graphs.

enum WifiBand { ghz24, ghz5, ghz6 }

extension WifiBandLabel on WifiBand {
  String get label => switch (this) {
        WifiBand.ghz24 => '2.4 GHz',
        WifiBand.ghz5 => '5 GHz',
        WifiBand.ghz6 => '6 GHz',
      };
}

WifiBand? bandOf(int freqMhz) {
  if (freqMhz >= 2400 && freqMhz <= 2500) return WifiBand.ghz24;
  if (freqMhz >= 5150 && freqMhz <= 5895) return WifiBand.ghz5;
  if (freqMhz >= 5925 && freqMhz <= 7125) return WifiBand.ghz6;
  return null;
}

/// IEEE channel number for a centre frequency.
int? channelOf(int freqMhz) {
  if (freqMhz == 2484) return 14;
  if (freqMhz >= 2412 && freqMhz <= 2472) return (freqMhz - 2407) ~/ 5;
  if (freqMhz >= 5150 && freqMhz <= 5895) return (freqMhz - 5000) ~/ 5;
  if (freqMhz == 5935) return 2;
  if (freqMhz >= 5955 && freqMhz <= 7115) return (freqMhz - 5950) ~/ 5;
  return null;
}

int frequencyOf(WifiBand band, int channel) => switch (band) {
      WifiBand.ghz24 => channel == 14 ? 2484 : 2407 + channel * 5,
      WifiBand.ghz5 => 5000 + channel * 5,
      WifiBand.ghz6 => channel == 2 ? 5935 : 5950 + channel * 5,
    };

/// Every channel shown on a band's x-axis, empty ones included.
List<int> channelsOf(WifiBand band) => switch (band) {
      WifiBand.ghz24 => [for (var c = 1; c <= 13; c++) c],
      WifiBand.ghz5 => const [
          36, 40, 44, 48, 52, 56, 60, 64, //
          100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 144,
          149, 153, 157, 161, 165,
        ],
      WifiBand.ghz6 => [for (var c = 1; c <= 233; c += 4) c],
    };

/// 5 GHz channels that need radar detection (DFS) before use.
bool isDfs(int channel) => channel >= 52 && channel <= 144;

/// One access point from a scan, as delivered by the platform.
class WifiNetwork {
  const WifiNetwork({
    required this.ssid,
    required this.bssid,
    required this.rssi,
    required this.frequency,
    this.centerFrequency0 = 0,
    this.channelWidthMhz = 20,
    this.security = '',
    this.standard = '',
    this.lastSeen,
  });

  final String ssid;
  final String bssid;
  final int rssi;
  final int frequency;
  final int centerFrequency0;
  final int channelWidthMhz;
  final String security;
  final String standard;
  final DateTime? lastSeen;

  WifiBand? get band => bandOf(frequency);
  int? get channel => channelOf(frequency);
  String get displayName => ssid.isEmpty ? '(hidden)' : ssid;

  /// Frequency span the network occupies, from its centre and width.
  (int, int) get span {
    final centre = centerFrequency0 > 0 ? centerFrequency0 : frequency;
    final half = channelWidthMhz ~/ 2;
    return (centre - half, centre + half);
  }

  factory WifiNetwork.fromMap(Map<Object?, Object?> m) => WifiNetwork(
        ssid: (m['ssid'] as String?) ?? '',
        bssid: (m['bssid'] as String?) ?? '',
        rssi: (m['rssi'] as num?)?.toInt() ?? -100,
        frequency: (m['frequency'] as num?)?.toInt() ?? 0,
        centerFrequency0: (m['centerFreq0'] as num?)?.toInt() ?? 0,
        channelWidthMhz: (m['channelWidth'] as num?)?.toInt() ?? 20,
        security: (m['security'] as String?) ?? '',
        standard: (m['standard'] as String?) ?? '',
        lastSeen: m['timestampMs'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch((m['timestampMs'] as num).toInt()),
      );
}

/// Whether a network's span covers a channel's 20 MHz slot.
bool covers(WifiNetwork n, WifiBand band, int channel) {
  if (n.band != band) return false;
  final f = frequencyOf(band, channel);
  final (lo, hi) = n.span;
  // 2.4 GHz channels are 22 MHz wide and 5 MHz apart, so a 20 MHz network
  // bleeds into the two neighbours on each side.
  final halfSlot = band == WifiBand.ghz24 ? 11 : 10;
  return f + halfSlot > lo && f - halfSlot < hi;
}

/// Strongest signal and network count of one channel.
class ChannelLoad {
  const ChannelLoad(this.channel, this.networks, this.strongest);
  final int channel;
  final int networks;
  final int? strongest;
}

List<ChannelLoad> channelLoads(WifiBand band, List<WifiNetwork> networks) => [
      for (final c in channelsOf(band))
        () {
          final on = networks.where((n) => covers(n, band, c)).toList();
          final best = on.isEmpty
              ? null
              : on.map((n) => n.rssi).reduce((a, b) => a > b ? a : b);
          return ChannelLoad(c, on.length, best);
        }(),
    ];

/// The least crowded channel to suggest. Each overlapping network weighs by
/// its signal (a -40 dBm neighbour hurts far more than a -90 one). On
/// 2.4 GHz only 1, 6 and 11 are suggested, since others overlap two of them.
int suggestedChannel(WifiBand band, List<WifiNetwork> networks) {
  final candidates = band == WifiBand.ghz24
      ? const [1, 6, 11]
      : channelsOf(band).where((c) => !(band == WifiBand.ghz5 && isDfs(c))).toList();
  int? best;
  double bestScore = double.infinity;
  for (final c in candidates) {
    var score = 0.0;
    for (final n in networks) {
      if (covers(n, band, c)) score += (n.rssi + 100).clamp(1, 70);
    }
    if (score < bestScore) {
      bestScore = score;
      best = c;
    }
  }
  return best ?? candidates.first;
}
