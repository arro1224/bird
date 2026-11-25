import 'package:aves/bird_companion/core/presentation/user_facing_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('N07 候选概率统一保留一位小数', () {
    expect(UserFacingText.recognitionPercent(0), '0.0%');
    expect(UserFacingText.recognitionPercent(.873478), '87.3%');
    expect(UserFacingText.recognitionPercent(.000825), '0.1%');
    expect(UserFacingText.recognitionPercent(.000001), '0.0%');
    expect(UserFacingText.recognitionPercent(1), '100.0%');
  });
}
