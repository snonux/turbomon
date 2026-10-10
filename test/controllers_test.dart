import 'package:flutter_test/flutter_test.dart';
import 'package:turbomon/services/bluetooth_controller.dart';
import 'package:turbomon/services/permissions.dart';
import 'package:turbomon/services/wifi_controller.dart';

import 'support/fake_platform.dart';

void main() {
  test('Wi-Fi: results, link, history and throttle detection', () async {
    final platform = FakePlatform()
      ..wifiResults = const [
        {'ssid': 'Home', 'bssid': 'a', 'rssi': -40, 'frequency': 2412},
        {'ssid': 'Cafe', 'bssid': 'b', 'rssi': -70, 'frequency': 5180},
      ]
      ..wifiLink = const {
        'ssid': 'Home',
        'bssid': 'a',
        'rssi': -41,
        'frequency': 2412,
      };
    final wifi = WifiController(
      platform: platform,
      permissions: Permissions(platform),
    );
    await wifi.start();
    expect(wifi.state, WifiState.scanning);
    expect(wifi.networks.first.ssid, 'Home');
    expect(wifi.history, hasLength(1));
    expect(wifi.tracked, {'a', 'b'});
    expect(wifi.scanInterval, WifiController.fastInterval);

    platform.wifiController.add(const {'type': 'scan', 'updated': true});
    await Future<void>.delayed(Duration.zero);
    expect(wifi.history, hasLength(2));
    expect(wifi.signal['a']!.length, 2);

    wifi.stop();
    platform.wifiScanAccepted = false;
    await wifi.start();
    expect(wifi.throttleOff, isFalse);
    expect(wifi.scanInterval, WifiController.throttledInterval);
    wifi.stop();
  });

  test('Wi-Fi without permission reports it', () async {
    final platform = FakePlatform()..granted = {Permissions.nearbyWifi: false};
    final wifi = WifiController(
      platform: platform,
      permissions: Permissions(platform),
    );
    await wifi.start();
    expect(wifi.state, WifiState.needsPermission);
  });

  test('Bluetooth: groups rotating addresses and tracks signal', () async {
    final platform = FakePlatform()
      ..paired = const [
        {
          'name': 'Car',
          'address': 'C',
          'connected': true,
          'profiles': ['audio'],
        },
        {
          'name': 'Watch',
          'address': 'W',
          'connected': false,
          'profiles': <String>[],
        },
      ];
    final bt = BluetoothController(
      platform: platform,
      permissions: Permissions(platform),
    );
    await bt.start();
    expect(bt.state, BluetoothScanState.scanning);
    platform.bluetoothController.add({
      'type': 'devices',
      'devices': [
        {'address': 'R1', 'name': 'Buds', 'rssi': -60, 'companyId': 0x0075},
        {'address': 'R2', 'name': 'Buds', 'rssi': -58, 'companyId': 0x0075},
        {'address': 'X', 'rssi': -90},
      ],
    });
    await Future<void>.delayed(Duration.zero);
    expect(bt.devices, hasLength(2));
    expect(bt.devices.first.rssi, -58);
    expect(bt.signal.values.single.length, 2);
    expect(bt.paired.first.name, 'Car');

    platform.bluetoothController.add(const {'type': 'error', 'code': -2});
    await Future<void>.delayed(Duration.zero);
    expect(bt.state, BluetoothScanState.needsPermission);
    bt.stop();
  });
}
