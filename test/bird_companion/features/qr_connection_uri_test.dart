import 'package:aves/bird_companion/features/connection/presentation/qr_connection_uri.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('解析普通 HTTP 和 HTTPS 设备地址', () {
    expect(
      parseBirdBoxConnectionUri('http://192.168.4.1:8080/device'),
      Uri.parse('http://192.168.4.1:8080/device'),
    );
    expect(
      parseBirdBoxConnectionUri('https://birdbox.local'),
      Uri.parse('https://birdbox.local'),
    );
  });

  test('解析 birdbox 二维码协议并补充默认端口', () {
    expect(
      parseBirdBoxConnectionUri('birdbox://connect?host=192.168.4.1'),
      Uri.parse('http://192.168.4.1:8080'),
    );
    expect(
      parseBirdBoxConnectionUri('birdbox://connect?host=k7.local&port=9443&https=true'),
      Uri.parse('https://k7.local:9443'),
    );
  });

  test('拒绝空内容、普通网页外的未知协议和缺少主机的二维码', () {
    expect(parseBirdBoxConnectionUri(null), isNull);
    expect(parseBirdBoxConnectionUri(''), isNull);
    expect(parseBirdBoxConnectionUri('PBK7-25A7-9F3D'), isNull);
    expect(parseBirdBoxConnectionUri('ftp://192.168.4.1'), isNull);
    expect(parseBirdBoxConnectionUri('birdbox://connect?port=8080'), isNull);
    expect(
      parseBirdBoxConnectionUri('birdbox://connect?host=k7.local&port=70000'),
      isNull,
    );
    expect(
      parseBirdBoxConnectionUri('http://user:password@192.168.4.1:8080'),
      isNull,
    );
  });

  test('扫码结果可以明确区分连接、手动输入和取消', () {
    final uri = Uri.parse('http://192.168.4.1:8080');
    final connect = QrConnectionResult.connect(uri);
    const manual = QrConnectionResult.manual();

    expect(connect.type, QrConnectionResultType.connect);
    expect(connect.uri, uri);
    expect(manual.type, QrConnectionResultType.manual);
    expect(manual.uri, isNull);
  });
}
