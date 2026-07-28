import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default main delegates to the task and device application', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(
      source,
      contains("import 'main_bird_settings.dart' as bird_settings;"),
    );
    expect(source, contains('void main() => bird_settings.main();'));
  });
}
