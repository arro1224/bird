import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ApiClient payload helpers', () {
    test('unwraps object, list, direct and empty responses', () {
      expect(
        ApiClient.unwrapResponse({
          'data': {'project_id': 'project-1'},
        }),
        {'project_id': 'project-1'},
      );
      expect(
        ApiClient.unwrapResponse({
          'data': [
            {'job_id': 'job-1'},
          ],
        }),
        [
          {'job_id': 'job-1'},
        ],
      );
      expect(ApiClient.unwrapResponse({'items': const []}), {
        'items': const [],
      });
      expect(ApiClient.unwrapResponse(null), isEmpty);
    });

    test('resolves nested media refs without changing signed URLs', () {
      final result =
          ApiClient.resolveMediaReferences(
                {
                  'items': [
                    {
                      'thumb_ref': '/media/thumb.jpg',
                      'preview_ref': 'https://cdn.example/signed.jpg?token=7',
                    },
                  ],
                },
                baseUri: Uri.parse('http://192.168.4.1:8080/'),
              )
              as Map<String, dynamic>;
      final item = (result['items'] as List).single as Map<String, dynamic>;

      expect(
        item['thumb_ref'],
        'http://192.168.4.1:8080/media/thumb.jpg',
      );
      expect(
        item['preview_ref'],
        'https://cdn.example/signed.jpg?token=7',
      );
    });
  });

  group('ApiException compatibility', () {
    test('prefers flat v1 error and preserves details', () {
      final exception = ApiException.fromDio(
        DioException(
          requestOptions: RequestOptions(path: '/jobs'),
          response: Response<Object?>(
            requestOptions: RequestOptions(path: '/jobs'),
            statusCode: 503,
            data: {
              'error_code': 'box_busy',
              'error_message': '盒子繁忙',
              'details': {'job_id': 'job-1'},
            },
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      expect(exception.code, 'box_busy');
      expect(exception.message, '盒子繁忙');
      expect(exception.details, {'job_id': 'job-1'});
      expect(exception.retryable, isTrue);
    });

    test('temporarily reads nested legacy error', () {
      final exception = ApiException.fromDio(
        DioException(
          requestOptions: RequestOptions(path: '/review'),
          response: Response<Object?>(
            requestOptions: RequestOptions(path: '/review'),
            statusCode: 409,
            data: {
              'error': {
                'code': 'version_conflict',
                'message': '版本冲突',
                'details': {'latest_version': 8},
              },
            },
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      expect(exception.code, 'version_conflict');
      expect(exception.message, '版本冲突');
      expect(exception.details['latest_version'], 8);
      expect(exception.retryable, isFalse);
    });
  });

  test('bbox must remain inside the normalized image range', () {
    expect(
      () => SubjectBox.fromJson(const {
        'bbox': <String, double>{
          'x': .8,
          'y': .1,
          'width': .3,
          'height': .2,
        },
      }),
      throwsA(isA<ProtocolCompatibilityException>()),
    );
  });

  test('protocol violations become an explicit compatibility message', () {
    final message = UserMessageMapper.fromError(
      const ProtocolCompatibilityException('progress', '必须位于 0–1 范围'),
    );

    expect(message.title, '盒子版本不兼容');
    expect(message.message, contains('协议'));
  });
}
