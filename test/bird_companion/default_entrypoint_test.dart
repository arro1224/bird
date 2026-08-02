import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default main delegates to the integrated production bootstrap', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(
      source,
      contains(
        "import 'package:aves/bird_companion/app/"
        "integrated_bird_bootstrap.dart';",
      ),
    );
    expect(source, contains('void main() => runIntegratedBirdApp();'));
    expect(source, isNot(contains('main_bird_settings.dart')));
  });
}
