import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('设备状态映射临时接口字段', () {
    final status = DeviceStatus.fromJson({'device_id': 'box', 'device_name': '测试盒子', 'card_inserted': true});
    expect(status.connection.id, 'box');
    expect(status.card.inserted, isTrue);
  });
}
