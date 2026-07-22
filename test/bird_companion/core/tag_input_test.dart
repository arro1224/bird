import 'package:aves/bird_companion/core/models/tag_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('标签支持中英文逗号和换行，并保留首次输入顺序', () {
    expect(parseUserTags('水鸟, 晨拍，水鸟\n逆光'), ['水鸟', '晨拍', '逆光']);
  });

  test('空标签和仅含空白的标签会被移除', () {
    expect(normalizeUserTags([' ', '湿地', '', ' 湿地 ', '  ']), ['湿地']);
  });
}
