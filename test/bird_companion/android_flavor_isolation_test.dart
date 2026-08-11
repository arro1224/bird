import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('birdV1 flavor installs independently from the production app', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final appName = File(
      'android/app/src/birdV1/res/values/strings.xml',
    ).readAsStringSync();

    expect(gradle, contains('create("birdV1")'));
    expect(gradle, contains('applicationIdSuffix = ".bird.v1"'));
    expect(appName, contains('<string name="app_name">拍鸟伴侣 V1</string>'));
  });
}
