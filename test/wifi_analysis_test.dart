import 'package:flutter_test/flutter_test.dart';
import 'package:turbomon/models/wifi.dart';
import 'package:turbomon/services/wifi_analysis.dart';

WifiNetwork net(
  String bssid,
  int freq,
  int rssi, {
  int width = 20,
  int? center,
}) => WifiNetwork(
  ssid: bssid,
  bssid: bssid,
  rssi: rssi,
  frequency: freq,
  channelWidth: width,
  centerFrequency: center,
);

void main() {
  test('bands and channels from frequency', () {
    expect(WifiBand.ofFrequency(2412), WifiBand.ghz24);
    expect(WifiBand.ghz24.channelOf(2412), 1);
    expect(WifiBand.ghz24.channelOf(2484), 14);
    expect(WifiBand.ghz5.channelOf(5180), 36);
    expect(WifiBand.ghz6.channelOf(5955), 1);
    expect(WifiBand.ofFrequency(5955), WifiBand.ghz6);
    expect(WifiBand.ofFrequency(900), isNull);
    expect(WifiBand.ghz24.channels, hasLength(13));
    expect(WifiBand.ghz5.isDfs(100), isTrue);
    expect(WifiBand.ghz5.isDfs(36), isFalse);
    expect(WifiBand.ghz6.recommendable.first, 5);
  });

  test('2.4 GHz overlap: 1 and 6 do not touch, 1 and 3 do', () {
    final ch1 = net('a', 2412, -50);
    expect(ch1.overlaps(WifiBand.ghz24, 1), isTrue);
    expect(ch1.overlaps(WifiBand.ghz24, 3), isTrue);
    expect(ch1.overlaps(WifiBand.ghz24, 6), isFalse);
  });

  test('wide channels span from their centre frequency', () {
    final vht80 = net('b', 5180, -60, width: 80, center: 5210);
    expect(vht80.span, (low: 5170.0, high: 5250.0));
    for (final ch in [36, 40, 44, 48]) {
      expect(vht80.overlaps(WifiBand.ghz5, ch), isTrue, reason: 'channel $ch');
    }
    expect(vht80.overlaps(WifiBand.ghz5, 52), isFalse);
  });

  test('suggests the quietest of 1, 6 and 11', () {
    final a = analyseBand(WifiBand.ghz24, [
      net('a', 2412, -40),
      net('b', 2437, -70),
      net('c', 2462, -45),
      net('d', 5180, -30), // other band, ignored
    ]);
    expect(a.networks, hasLength(3));
    expect(a.recommended, 6);
    expect(a.stat(1)!.count, 1);
    expect(a.stat(3)!.count, 2, reason: 'channel 3 overlaps 1 and 6');
    expect(a.stat(13)!.strongest, -45, reason: 'channel 11 overlaps 13');
  });

  test('no suggestion without networks; DFS never suggested', () {
    expect(analyseBand(WifiBand.ghz5, const []).recommended, isNull);
    final busy = analyseBand(WifiBand.ghz5, [
      for (final f in [5180, 5200, 5220, 5240, 5745, 5765, 5785, 5805, 5825])
        net('$f', f, -40),
    ]);
    expect(WifiBand.ghz5.isDfs(busy.recommended!), isFalse);
  });

  test('security, strength and co-channel neighbours', () {
    expect(
      const WifiNetwork(
        ssid: '',
        bssid: 'x',
        rssi: -100,
        frequency: 2412,
        capabilities: '[RSN-SAE-CCMP]',
      ).security,
      'WPA3',
    );
    expect(
      const WifiNetwork(
        ssid: 'x',
        bssid: 'x',
        rssi: -30,
        frequency: 2412,
        capabilities: '[ESS]',
      ).security,
      'Open',
    );
    expect(net('x', 2412, -30).strength, 1);
    expect(net('x', 2412, -100).strength, 0);
    final link = WifiLink.fromJson({
      'bssid': 'a',
      'rssi': -50,
      'frequency': 2412,
    });
    expect(
      coChannelNeighbours(link, [
        net('a', 2412, -50),
        net('b', 2412, -80),
        net('c', 2437, -60),
      ]),
      1,
    );
  });

  test('BSSIDs stay out of JSON unless asked for', () {
    final n = net('aa:bb', 2412, -50);
    expect(n.toJson().containsKey('bssid'), isFalse);
    expect(n.toJson(includeBssid: true)['bssid'], 'aa:bb');
  });
}
