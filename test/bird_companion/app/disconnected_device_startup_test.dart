import 'package:aves/bird_companion/app/bird_companion_app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production always starts on the existing album experience', () {
    expect(birdStartupTab, 0);
  });
}
