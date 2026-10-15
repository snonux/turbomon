import 'package:flutter_test/flutter_test.dart';
import 'package:turbomon/services/permissions.dart';

import 'support/fake_platform.dart';

class _PermissionPlatform extends FakePlatform {
  final requests = <List<String>>[];
  Map<String, bool> response = {};
  void Function()? onRequest;

  @override
  Future<Map<String, bool>> requestPermissions(List<String> permissions) async {
    requests.add(List.of(permissions));
    onRequest?.call();
    return response;
  }
}

void main() {
  for (final sdk in [24, 30, 31, 32, 33, 37]) {
    test('permission requirements on Android API $sdk', () async {
      final platform = _PermissionPlatform()..deviceInfo = {'sdk': sdk};
      final permissions = Permissions(platform);
      expect(await permissions.wifi(), [
        if (sdk >= 33) Permissions.nearbyWifi,
        if (sdk >= 31) Permissions.coarseLocation,
        Permissions.fineLocation,
      ]);
      expect(
        await permissions.bluetooth(),
        sdk >= 31
            ? [Permissions.bluetoothScan, Permissions.bluetoothConnect]
            : [Permissions.fineLocation],
      );
      expect(await permissions.notification(), [
        if (sdk >= 33) Permissions.notifications,
      ]);
    });
  }

  test('already granted and empty requests do not open a dialog', () async {
    final platform = _PermissionPlatform();
    final permissions = Permissions(platform);
    expect(await permissions.ensure(const []), isTrue);
    expect(await permissions.ensure(await permissions.wifi()), isTrue);
    expect(platform.requests, isEmpty);
  });

  test(
    'new fine grant succeeds with an existing coarse and nearby grant',
    () async {
      final platform = _PermissionPlatform()
        ..granted = {Permissions.fineLocation: false}
        ..response = {Permissions.fineLocation: true};
      platform.onRequest = () =>
          platform.granted[Permissions.fineLocation] = true;
      final permissions = Permissions(platform);
      final required = await permissions.wifi();
      expect(await permissions.ensure(required), isTrue);
      expect(platform.requests, [required]);
      // Coarse must remain in an upgrade request; Android rejects fine alone.
      expect(platform.requests.single, contains(Permissions.coarseLocation));
    },
  );

  test('approximate location is insufficient for Wi-Fi scan results', () async {
    final platform = _PermissionPlatform()
      ..granted = {Permissions.fineLocation: false};
    final permissions = Permissions(platform);
    expect(await permissions.ensure(await permissions.wifi()), isFalse);
  });

  test('a permission withdrawn during the dialog stays denied', () async {
    final platform = _PermissionPlatform()
      ..granted = {Permissions.bluetoothConnect: false}
      ..response = {Permissions.bluetoothConnect: true};
    platform.onRequest = () {
      platform.granted[Permissions.bluetoothConnect] = true;
      platform.granted[Permissions.bluetoothScan] = false;
    };
    final permissions = Permissions(platform);
    expect(await permissions.ensure(await permissions.bluetooth()), isFalse);
  });

  test('a dismissed request does not count as a grant', () async {
    final platform = _PermissionPlatform()
      ..granted = {Permissions.notifications: false};
    final permissions = Permissions(platform);
    expect(await permissions.ensure(await permissions.notification()), isFalse);
  });
}
