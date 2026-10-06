import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('delivery flavors have fixed package IDs and distinct display names', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final birdName = File(
      'android/app/src/bird/res/values/strings.xml',
    ).readAsStringSync();
    final birdV1Name = File(
      'android/app/src/birdV1/res/values/strings.xml',
    ).readAsStringSync();
    final channel = File(
      'android/app/src/main/java/deckers/thibault/aves/BirdBoxBleChannel.java',
    ).readAsStringSync();

    expect(gradle, contains('applicationId = "deckers.thibault.aves.bird"'));
    expect(gradle, contains('create("birdV1")'));
    expect(
      gradle,
      contains('applicationId = "deckers.thibault.aves.bird.v1"'),
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
    expect(
      birdV1Name,
      contains('<string name="app_name">拍鸟伴侣 V1</string>'),
    );
    expect(gradle, contains('resValue("string", "app_name", "BirdBox 扫描 A")'));
    expect(gradle, contains('resValue("string", "app_name", "BirdBox 扫描 B")'));
    expect(channel, contains('event.put("packageId", activity.getPackageName())'));
    expect(channel, contains('event.put("buildFlavor", BuildConfig.FLAVOR)'));
    expect(channel, contains('event.put("buildType", BuildConfig.BUILD_TYPE)'));
  });
}
