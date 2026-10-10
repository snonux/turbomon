import 'package:flutter_test/flutter_test.dart';
import 'package:turbomon/parsers/wifi_channels.dart';

WifiNetwork net(int freq, {int rssi = -60, int width = 20, int centre = 0, String bssid = 'aa'}) => WifiNetwork(
      ssid: 'n$freq',
      bssid: bssid,
      rssi: rssi,
      frequency: freq,
      centerFrequency0: centre,
      channelWidthMhz: width,
    );

void main() {
  group('band and channel arithmetic', () {
    test('bandOf edges', () {
      expect(bandOf(2412), WifiBand.ghz24);
      expect(bandOf(2484), WifiBand.ghz24);
      expect(bandOf(5180), WifiBand.ghz5);
      expect(bandOf(5885), WifiBand.ghz5);
      expect(bandOf(5935), WifiBand.ghz6);
      expect(bandOf(5955), WifiBand.ghz6);
      expect(bandOf(7115), WifiBand.ghz6);
      expect(bandOf(0), isNull);
      expect(bandOf(5900), isNull);
      expect(bandOf(60480), isNull); // 60 GHz WiGig
    });

    test('labels', () {
      expect(WifiBand.ghz24.label, '2.4 GHz');
      expect(WifiBand.ghz5.label, '5 GHz');
      expect(WifiBand.ghz6.label, '6 GHz');
    });

    test('2.4 GHz round trips, including Japan channel 14', () {
      for (var c = 1; c <= 14; c++) {
        final f = frequencyOf(WifiBand.ghz24, c);
        expect(channelOf(f), c, reason: '$f');
        expect(bandOf(f), WifiBand.ghz24);
      }
      expect(frequencyOf(WifiBand.ghz24, 1), 2412);
      expect(frequencyOf(WifiBand.ghz24, 6), 2437);
      expect(frequencyOf(WifiBand.ghz24, 11), 2462);
      expect(frequencyOf(WifiBand.ghz24, 14), 2484);
    });

    test('5 GHz round trips for every listed channel', () {
      for (final c in channelsOf(WifiBand.ghz5)) {
        final f = frequencyOf(WifiBand.ghz5, c);
        expect(channelOf(f), c);
        expect(bandOf(f), WifiBand.ghz5);
      }
      expect(frequencyOf(WifiBand.ghz5, 36), 5180);
      expect(frequencyOf(WifiBand.ghz5, 165), 5825);
      expect(channelOf(5500), 100);
    });

    test('6 GHz round trips, including the odd channel 2 at 5935 MHz', () {
      for (final c in channelsOf(WifiBand.ghz6)) {
        final f = frequencyOf(WifiBand.ghz6, c);
        expect(channelOf(f), c);
        expect(bandOf(f), WifiBand.ghz6);
      }
      expect(frequencyOf(WifiBand.ghz6, 1), 5955);
      expect(frequencyOf(WifiBand.ghz6, 233), 7115);
      expect(channelOf(5935), 2);
      expect(frequencyOf(WifiBand.ghz6, 2), 5935);
    });

    test('channelOf rejects frequencies outside the bands', () {
      expect(channelOf(2400), isNull);
      expect(channelOf(4900), isNull);
      expect(channelOf(7200), isNull);
    });

    test('channelsOf', () {
      expect(channelsOf(WifiBand.ghz24), [for (var c = 1; c <= 13; c++) c]);
      expect(channelsOf(WifiBand.ghz5), hasLength(25));
      expect(channelsOf(WifiBand.ghz6).first, 1);
      expect(channelsOf(WifiBand.ghz6).last, 233);
      expect(channelsOf(WifiBand.ghz6), hasLength(59));
    });

    test('isDfs covers UNII-2 and UNII-2e only', () {
      expect(isDfs(36), isFalse);
      expect(isDfs(48), isFalse);
      expect(isDfs(52), isTrue);
      expect(isDfs(64), isTrue);
      expect(isDfs(100), isTrue);
      expect(isDfs(144), isTrue);
      expect(isDfs(149), isFalse);
      expect(isDfs(165), isFalse);
    });
  });

  group('WifiNetwork', () {
    test('fromMap reads every platform field', () {
      final n = WifiNetwork.fromMap({
        'ssid': 'HomeNet',
        'bssid': 'a4:2b:b0:11:22:33',
        'rssi': -54,
        'frequency': 5180,
        'centerFreq0': 5210,
        'channelWidth': 80,
        'security': 'WPA2-PSK',
        'standard': '802.11ac',
        'timestampMs': 1700000000000,
      });
      expect(n.ssid, 'HomeNet');
      expect(n.bssid, 'a4:2b:b0:11:22:33');
      expect(n.rssi, -54);
      expect(n.band, WifiBand.ghz5);
      expect(n.channel, 36);
      expect(n.span, (5170, 5250));
      expect(n.security, 'WPA2-PSK');
      expect(n.standard, '802.11ac');
      expect(n.lastSeen, DateTime.fromMillisecondsSinceEpoch(1700000000000));
      expect(n.displayName, 'HomeNet');
    });

    test('fromMap defaults for a sparse map and doubles from the channel', () {
      final n = WifiNetwork.fromMap({'frequency': 2437.0, 'rssi': -71.0});
      expect(n.ssid, '');
      expect(n.displayName, '(hidden)');
      expect(n.rssi, -71);
      expect(n.channelWidthMhz, 20);
      expect(n.lastSeen, isNull);
      expect(n.span, (2427, 2447));
      final empty = WifiNetwork.fromMap({});
      expect(empty.rssi, -100);
      expect(empty.band, isNull);
      expect(empty.channel, isNull);
    });
  });

  group('covers', () {
    test('20 MHz on 2.4 GHz overlaps the 22 MHz slots of nearby channels, but not 1 or 11', () {
      final n = net(2437); // channel 6
      final covered = [for (var c = 1; c <= 13; c++) if (covers(n, WifiBand.ghz24, c)) c];
      expect(covered, [2, 3, 4, 5, 6, 7, 8, 9, 10]);
      expect(covers(n, WifiBand.ghz5, 36), isFalse);
    });

    test('40 MHz on 2.4 GHz', () {
      final n = net(2412, width: 40, centre: 2422); // ch 1 + 5
      final covered = [for (var c = 1; c <= 13; c++) if (covers(n, WifiBand.ghz24, c)) c];
      expect(covered, containsAll([1, 3, 5, 7]));
      expect(covered, isNot(contains(11)));
    });

    test('20 MHz on 5 GHz covers only its own channel', () {
      final n = net(5180);
      expect([for (final c in channelsOf(WifiBand.ghz5)) if (covers(n, WifiBand.ghz5, c)) c], [36]);
    });

    test('40, 80 and 160 MHz on 5 GHz', () {
      List<int> on(WifiNetwork n) => [for (final c in channelsOf(WifiBand.ghz5)) if (covers(n, WifiBand.ghz5, c)) c];
      expect(on(net(5180, width: 40, centre: 5190)), [36, 40]);
      expect(on(net(5180, width: 80, centre: 5210)), [36, 40, 44, 48]);
      expect(on(net(5180, width: 160, centre: 5250)), [36, 40, 44, 48, 52, 56, 60, 64]);
      // Without centreFreq0 the primary channel is taken as the centre.
      expect(on(net(5500, width: 40)), [100, 104]);
    });

    test('6 GHz 160 MHz', () {
      final n = net(5955, width: 160, centre: 6025);
      final covered = [for (final c in channelsOf(WifiBand.ghz6)) if (covers(n, WifiBand.ghz6, c)) c];
      expect(covered, [1, 5, 9, 13, 17, 21, 25, 29]);
    });
  });

  group('channelLoads', () {
    test('counts networks and keeps the strongest signal per channel', () {
      final nets = [
        net(2412, rssi: -40, bssid: 'a'),
        net(2412, rssi: -70, bssid: 'b'),
        net(2462, rssi: -80, bssid: 'c'),
        net(5180, rssi: -30, bssid: 'd'),
      ];
      final loads = {for (final l in channelLoads(WifiBand.ghz24, nets)) l.channel: l};
      expect(loads.length, 13);
      expect(loads[1]!.networks, 2);
      expect(loads[1]!.strongest, -40);
      expect(loads[3]!.networks, 2);
      expect(loads[6]!.networks, 0);
      expect(loads[6]!.strongest, isNull);
      expect(loads[11]!.networks, 1);
      expect(loads[11]!.strongest, -80);
      expect(loads[13]!.networks, 1);
    });
  });

  group('suggestedChannel', () {
    test('only 1, 6 or 11 on 2.4 GHz', () {
      expect(suggestedChannel(WifiBand.ghz24, const []), 1);
      final nets = [net(2412, rssi: -40, bssid: 'a'), net(2437, rssi: -50, bssid: 'b')];
      expect(suggestedChannel(WifiBand.ghz24, nets), 11);
      // Channel 3 overlaps 1 and 6 but is never suggested itself.
      final busy = [net(2412, rssi: -40), net(2437, rssi: -40), net(2462, rssi: -90)];
      expect(suggestedChannel(WifiBand.ghz24, busy), 11);
    });

    test('a weak neighbour weighs less than a strong one', () {
      final nets = [
        net(2412, rssi: -90, bssid: 'a'),
        net(2412, rssi: -91, bssid: 'b'),
        net(2437, rssi: -35, bssid: 'c'),
        net(2462, rssi: -35, bssid: 'd'),
      ];
      expect(suggestedChannel(WifiBand.ghz24, nets), 1);
    });

    test('5 GHz avoids DFS and crowded channels', () {
      final nets = [
        net(5180, rssi: -40, width: 80, centre: 5210, bssid: 'a'), // 36-48
        net(5745, rssi: -60, bssid: 'b'), // 149
      ];
      final s = suggestedChannel(WifiBand.ghz5, nets);
      expect(isDfs(s), isFalse);
      expect(s, 153);
      expect(suggestedChannel(WifiBand.ghz5, const []), 36);
    });

    test('6 GHz picks a free channel', () {
      expect(suggestedChannel(WifiBand.ghz6, [net(5955, width: 80, centre: 5985)]), 17);
    });
  });
}
