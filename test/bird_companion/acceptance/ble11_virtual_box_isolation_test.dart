import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('virtual BirdBox is test-only and has no release variant', () {
    final manifest = File(
      'android/virtualBirdBox/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final build = File(
      'android/virtualBirdBox/build.gradle.kts',
    ).readAsStringSync();

    expect(manifest, contains('android:testOnly="true"'));
    expect(
      build,
      contains('beforeVariants(selector().withBuildType("release"))'),
    );
    expect(build, contains('variantBuilder.enable = false'));
  });

  test('production app does not depend on the virtual peripheral module', () {
    final settings = File('android/settings.gradle.kts').readAsStringSync();
    final appBuild = File('android/app/build.gradle.kts').readAsStringSync();
    final productionSource = Directory(
      'android/app/src/main',
    ).listSync(recursive: true).whereType<File>();

    expect(settings, contains('include(":virtualBirdBox")'));
    expect(appBuild, isNot(contains('project(":virtualBirdBox")')));
    for (final file in productionSource) {
      if (!file.path.endsWith('.java') && !file.path.endsWith('.kt')) continue;
      expect(
        file.readAsStringSync(),
        isNot(contains('deckers.thibault.aves.virtualbirdbox')),
        reason: 'production source must not reference ${file.path}',
      );
    }
  });
}
