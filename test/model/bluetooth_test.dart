import 'package:flutter_test/flutter_test.dart';
import 'package:turbomon/model/bluetooth.dart';

BtDevice dev(String address, {String name = '', int? maker, int rssi = -60, int t = 0}) => BtDevice(
      address: address,
      name: name,
      rssi: rssi,
      type: 'le',
      lastSeen: DateTime.fromMillisecondsSinceEpoch(1700000000000 + t * 1000),
      manufacturerId: maker,
    );

void main() {
  group('BtDevice', () {
    test('fromMap reads every field', () {
      final d = BtDevice.fromMap({
        'address': 'C4:7C:8D:6A:12:34',
        'name': 'Galaxy Buds2',
        'rssi': -67,
        'type': 'dual',
        'timestampMs': 1700000000000,
        'manufacturerId': 0x0075,
        'txPower': -12,
        'connectable': true,
        'bonded': true,
        'battery': 80,
      });
      expect(d.address, 'C4:7C:8D:6A:12:34');
      expect(d.displayName, 'Galaxy Buds2');
      expect(d.rssi, -67);
      expect(d.type, 'dual');
      expect(d.lastSeen, DateTime.fromMillisecondsSinceEpoch(1700000000000));
      expect(d.maker, 'Samsung');
      expect(d.txPower, -12);
      expect(d.connectable, isTrue);
      expect(d.bonded, isTrue);
      expect(d.batteryPercent, 80);
    });

    test('fromMap defaults', () {
      final before = DateTime.now();
      final d = BtDevice.fromMap({});
      expect(d.address, '');
      expect(d.displayName, '(unnamed)');
      expect(d.rssi, -100);
      expect(d.type, 'unknown');
      expect(d.maker, isNull);
      expect(d.bonded, isFalse);
      expect(d.connectable, isNull);
      expect(d.lastSeen.isBefore(before.subtract(const Duration(seconds: 1))), isFalse);
    });
  });

  group('groupKey', () {
    test('named devices group by name and maker', () {
      expect(groupKey(dev('11:22:33:44:55:66', name: 'Pixel Watch', maker: 0x00E0)), 'Pixel Watch|224');
      expect(groupKey(dev('11:22:33:44:55:66', name: 'Tile')), 'Tile|');
    });

    test('unnamed devices fall back to their address', () {
      expect(groupKey(dev('7A:11:22:33:44:55', maker: 0x004C)), '7A:11:22:33:44:55');
    });
  });

  group('mergeSighting', () {
    test('rotating random addresses of one named device merge into one group', () {
      final known = <String, BtGroup>{};
      mergeSighting(known, dev('5E:00:00:00:00:01', name: 'AirPods', maker: 0x004C, rssi: -70, t: 0));
      mergeSighting(known, dev('6F:00:00:00:00:02', name: 'AirPods', maker: 0x004C, rssi: -55, t: 60));
      mergeSighting(known, dev('5E:00:00:00:00:01', name: 'AirPods', maker: 0x004C, rssi: -58, t: 61));
      expect(known, hasLength(1));
      final g = known.values.single;
      expect(g.addresses, {'5E:00:00:00:00:01', '6F:00:00:00:00:02'});
      expect(g.latest.rssi, -58);
    });

    test('same name from different makers, and unnamed devices, stay apart', () {
      final known = <String, BtGroup>{};
      mergeSighting(known, dev('A', name: 'Speaker', maker: 0x05A7));
      mergeSighting(known, dev('B', name: 'Speaker', maker: 0x009E));
      mergeSighting(known, dev('C'));
      mergeSighting(known, dev('D'));
      mergeSighting(known, dev('C', rssi: -40));
      expect(known, hasLength(4));
      expect(known['C']!.latest.rssi, -40);
      expect(known['C']!.addresses, {'C'});
    });
  });

  test('companyName knows common makers and hex-formats the rest', () {
    expect(companyName(0x004C), 'Apple');
    expect(companyName(0x0006), 'Microsoft');
    expect(companyName(0x00E0), 'Google');
    expect(companyName(0x038F), 'Xiaomi');
    expect(companyName(0x1234), '0x1234');
    expect(companyName(0xABC), '0x0ABC');
    expect(companyName(0), '0x0000');
  });
}
