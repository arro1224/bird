import 'package:aves/bird_companion/core/presentation/user_facing_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('识别度统一格式化为四舍五入后的百分比', () {
    expect(UserFacingText.recognitionPercent(0), '0%');
    expect(UserFacingText.recognitionPercent(.855), '86%');
    expect(UserFacingText.recognitionPercent(1), '100%');
  });
}
