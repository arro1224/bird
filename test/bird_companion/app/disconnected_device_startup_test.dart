import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production startup always opens the v1 device module', () {
    final source = File(
      'lib/bird_companion/app/bird_companion_app.dart',
    ).readAsStringSync();
    final mainSource = File('lib/main.dart').readAsStringSync();

    expect(mainSource, contains('runIntegratedBirdApp()'));
    expect(source, contains('BirdAppShell('));
    expect(source, contains('initialIndex: 2'));
    expect(source, isNot(contains('? 0 : 2')));
    expect(source, isNot(contains('initialRoute: dependencies.deviceSessionCubit.state.isConnected')));
  });
}
