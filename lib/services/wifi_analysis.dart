import '../models/wifi.dart';

/// How busy one channel is.
class ChannelStat {
  const ChannelStat({
    required this.channel,
    required this.count,
    this.strongest,
    required this.interference,
  });

  final int channel;

  /// Networks whose span overlaps this channel.
  final int count;

  /// Strongest overlapping signal in dBm.
  final int? strongest;

  /// Summed power of overlapping networks in mW; lower is better.
  final double interference;
}

class BandAnalysis {
  const BandAnalysis({
    required this.band,
    required this.networks,
    required this.channels,
    this.recommended,
  });

  final WifiBand band;
  final List<WifiNetwork> networks;
  final List<ChannelStat> channels;

  /// The least crowded channel worth picking, or null with no networks seen.
  final int? recommended;

  ChannelStat? stat(int channel) {
    for (final s in channels) {
      if (s.channel == channel) return s;
    }
    return null;
  }
}

BandAnalysis analyseBand(WifiBand band, Iterable<WifiNetwork> all) {
  final networks = [
    for (final n in all)
      if (n.band == band) n,
  ];
  final stats = [for (final ch in band.channels) _statFor(band, ch, networks)];
  int? best;
  if (networks.isNotEmpty) {
    double? bestScore;
    for (final ch in band.recommendable) {
      final s = stats.firstWhere((s) => s.channel == ch);
      if (bestScore == null || s.interference < bestScore) {
        best = ch;
        bestScore = s.interference;
      }
    }
  }
  return BandAnalysis(
    band: band,
    networks: networks,
    channels: stats,
    recommended: best,
  );
}

ChannelStat _statFor(WifiBand band, int channel, List<WifiNetwork> networks) {
  var count = 0;
  int? strongest;
  var power = 0.0;
  for (final n in networks) {
    if (!n.overlaps(band, channel)) continue;
    count++;
    power += n.milliwatts;
    if (strongest == null || n.rssi > strongest) strongest = n.rssi;
  }
  return ChannelStat(
    channel: channel,
    count: count,
    strongest: strongest,
    interference: power,
  );
}

/// Networks on the same primary channel as the connected one, minus itself.
int coChannelNeighbours(WifiLink link, Iterable<WifiNetwork> networks) {
  final freq = link.frequency;
  if (freq == null) return 0;
  return networks
      .where((n) => n.frequency == freq && n.bssid != link.bssid)
      .length;
}
