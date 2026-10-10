import 'package:flutter_test/flutter_test.dart';
import 'package:turbomon/services/access.dart';

import 'support/fake_platform.dart';

void main() {
  test('automatic uses Shizuku only when it is running and granted', () async {
    final platform = FakePlatform();
    final access = AccessController(platform);
    await access.resolve(AccessMode.auto);
    expect(access.level, AccessLevel.normal);
    expect(access.problem, isNull);

    platform.shizuku = const {'running': true, 'granted': true};
    await access.resolve(AccessMode.auto);
    expect(access.level, AccessLevel.shizuku);
    expect(access.privileged, isTrue);
  });

  test('Shizuku mode explains why it fell back', () async {
    final platform = FakePlatform();
    final access = AccessController(platform);
    await access.resolve(AccessMode.shizuku);
    expect(access.level, AccessLevel.normal);
    expect(access.problem, contains('not running'));

    platform.shizuku = const {'running': true, 'granted': false};
    await access.resolve(AccessMode.shizuku, interactive: false);
    expect(access.problem, contains('no permission'));
  });

  test('normal mode never elevates', () async {
    final platform = FakePlatform()
      ..shizuku = const {'running': true, 'granted': true};
    final access = AccessController(platform);
    await access.resolve(AccessMode.normal);
    expect(access.level, AccessLevel.normal);
    expect(access.runner, isNull);
  });
}
