import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('连接超时不会向用户暴露 Dio 英文异常', () {
    final cause = DioException(
      requestOptions: RequestOptions(path: '/api/v1/status'),
      type: DioExceptionType.connectionTimeout,
      message: 'The request connection took longer than 0:00:08 and was aborted.',
    );

    final message = UserMessageMapper.fromError(ApiException.fromDio(cause));

    expect(message.title, '连接超时');
    expect(message.message, contains('盒子未及时响应'));
    expect(message.message, isNot(contains('RequestOptions')));
  });

  test('连接错误显示可执行的中文提示', () {
    final cause = DioException(
      requestOptions: RequestOptions(path: '/api/v1/status'),
      type: DioExceptionType.connectionError,
      message: 'Connection refused',
    );

    final message = UserMessageMapper.fromError(ApiException.fromDio(cause));

    expect(message.title, '无法连接盒子');
    expect(message.actionLabel, '重新连接');
  });

  test('鉴权错误提示重新配对', () {
    const error = ApiException(message: 'Unauthorized', statusCode: 401);

    final message = UserMessageMapper.fromError(error);

    expect(message.title, '盒子拒绝连接');
    expect(message.message, contains('配对'));
  });
}
