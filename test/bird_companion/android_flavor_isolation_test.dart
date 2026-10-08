import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production, simulation, and diagnostic flavors stay isolated', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final birdName = File(
      'android/app/src/bird/res/values/strings.xml',
    ).readAsStringSync();
    final channel = File(
      'android/app/src/main/java/deckers/thibault/aves/BirdBoxBleChannel.java',
    ).readAsStringSync();

    expect(gradle, contains('applicationId = "deckers.thibault.aves.bird"'));
    expect(
      gradle,
      contains(
        'create("bird") {\n'
        '            dimension = "app"\n'
        '            applicationId = "deckers.thibault.aves.bird"\n'
        '            buildConfigField("boolean", "BLE_SCAN_STRATEGY_FALLBACK_ENABLED", "true")',
      ),
    );
    expect(gradle, isNot(contains('create("birdV1")')));
    expect(gradle, contains('create("birdSim")'));
    expect(
      gradle,
      contains('applicationId = "deckers.thibault.aves.bird.sim"'),
    );
    expect(
      gradle,
      contains('applicationId = "deckers.thibault.aves.bird.scan.a"'),
    );
    expect(
      gradle,
      contains('applicationId = "deckers.thibault.aves.bird.scan.b"'),
    );
    expect(birdName, contains('<string name="app_name">拍鸟伴侣</string>'));
    expect(gradle, contains('resValue("string", "app_name", "拍鸟伴侣（模拟）")'));
    expect(gradle, contains('resValue("string", "app_name", "BirdBox 扫描 A")'));
    expect(gradle, contains('resValue("string", "app_name", "BirdBox 扫描 B")'));
    expect(gradle, contains('variantBuilder.enable = false'));
    expect(
      gradle,
      contains('if (appFlavor != "bird" && variantBuilder.buildType != "debug")'),
    );
    expect(channel, contains('event.put("packageId", activity.getPackageName())'));
    expect(channel, contains('event.put("buildFlavor", BuildConfig.FLAVOR)'));
    expect(channel, contains('event.put("buildType", BuildConfig.BUILD_TYPE)'));
  });
}
