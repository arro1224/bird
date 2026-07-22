import 'package:aves/bird_companion/features/connection/domain/connection_address.dart';
import 'package:aves/bird_companion/features/connection/presentation/qr_connection_uri.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('只接受局域网、回环和 local 设备地址', () {
    expect(ConnectionAddress.tryParse('192.168.4.1:8080'), Uri.parse('http://192.168.4.1:8080'));
    expect(ConnectionAddress.tryParse('https://k7.local:9443'), Uri.parse('https://k7.local:9443'));
    expect(ConnectionAddress.tryParse('http://127.0.0.1:8080'), Uri.parse('http://127.0.0.1:8080'));
    expect(ConnectionAddress.tryParse('http://10.0.2.2:8080'), Uri.parse('http://10.0.2.2:8080'));
  });

  test('拒绝公网、账号信息和带路径的地址', () {
    expect(ConnectionAddress.tryParse('https://example.com'), isNull);
    expect(ConnectionAddress.tryParse('http://user:pass@192.168.4.1:8080'), isNull);
    expect(ConnectionAddress.tryParse('http://192.168.4.1:8080/device'), isNull);
    expect(ConnectionAddress.tryParse('http://192.168.4.1:8080?next=https://example.com'), isNull);
  });

  test('二维码协议复用本地地址校验', () {
    expect(parseBirdBoxConnectionUri('birdbox://connect?host=192.168.4.1'), Uri.parse('http://192.168.4.1:8080'));
    expect(parseBirdBoxConnectionUri('birdbox://connect?host=example.com'), isNull);
    expect(parseBirdBoxConnectionUri('https://k7.local/device'), isNull);
  });
}
