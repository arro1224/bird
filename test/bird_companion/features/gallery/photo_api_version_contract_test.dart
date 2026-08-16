import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/features/gallery/data/photo_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final operation in const ['pending', 'keep', 'discard', 'featured']) {
    test('batch $operation includes the required version and operation', () async {
      final client = _RecordingApiClient();

      await PhotoApi(client).batchOperation(
        'project-7',
        const ['photo-1', 'photo-2'],
        operation,
        version: 3,
      );

      expect(client.path, '/api/v1/projects/project-7/files/actions');
      expect(client.payload, {
        'file_ids': ['photo-1', 'photo-2'],
        'operation': operation,
        'value': null,
        'version': 3,
      });
    });
  }
}

class _RecordingApiClient extends ApiClient {
  String? path;
  Object? payload;

  @override
  Future<Map<String, dynamic>> post(
    String value, {
    Object? data,
    String? idempotencyKey,
  }) async {
    path = value;
    payload = data;
    return const {'succeeded_ids': <String>[]};
  }
}
