import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/features/review/data/review_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detail falls back to the photo version when its decision omits one', () async {
    final detail = await ReviewApi(_DetailApiClient()).detail('photo-7');

    expect(detail.photo.summary.version, 3);
    expect(detail.decision?.version, 3);
  });

  test('save stops before sending a review patch without a version', () async {
    final client = _DetailApiClient();

    expect(
      () => ReviewApi(client).save(
        const UserDecisionPatch(
          fileId: 'photo-7',
          keepState: PatchField.value(KeepState.keep),
        ),
      ),
      throwsA(isA<ProtocolCompatibilityException>()),
    );
    expect(client.postCalls, 0);
  });

  test('saveWithPhoto consumes the frozen PhotoResponse version', () async {
    final client = _DetailApiClient();

    final photo = await ReviewApi(client).saveWithPhoto(
      const UserDecisionPatch(
        fileId: 'photo-7',
        keepState: PatchField.value(KeepState.keep),
        version: 3,
      ),
      idempotencyKey: 'review-photo-7-v3',
    );

    expect(client.postCalls, 1);
    expect(photo.id, 'photo-7');
    expect(photo.keepState, 'keep');
    expect(photo.version, 4);
  });

  test('saveWithPhoto reads detail after a legacy simulator decision response', () async {
    final client = _LegacyDecisionApiClient();

    final photo = await ReviewApi(client).saveWithPhoto(
      const UserDecisionPatch(
        fileId: 'photo-7',
        keepState: PatchField.value(KeepState.keep),
        version: 3,
      ),
    );

    expect(client.postCalls, 1);
    expect(client.getCalls, 1);
    expect(photo.id, 'photo-7');
    expect(photo.keepState, 'keep');
    expect(photo.version, 4);
  });
}

class _DetailApiClient extends ApiClient {
  var getCalls = 0;
  var postCalls = 0;

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    getCalls++;
    if (getCalls == 1) {
      return {
        'file': {
          'file_id': 'photo-7',
          'filename': 'photo-7.jpg',
          'format': 'JPEG',
          'analysis_state': 'completed',
          'version': 3,
        },
        'decision': {
          'keep_state': 'pending',
        },
      };
    }
    return const {'items': <Object>[]};
  }

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Object? data,
    String? idempotencyKey,
    Map<String, String>? headers,
  }) async {
    postCalls++;
    return const {
      'file_id': 'photo-7',
      'filename': 'photo-7.jpg',
      'format': 'JPEG',
      'thumb_ref': 'http://box.local/photo-7-thumb.jpg',
      'preview_ref': 'http://box.local/photo-7-preview.jpg',
      'analysis_state': 'completed',
      'keep_state': 'keep',
      'is_recommended': false,
      'user_tags': <String>[],
      'version': 4,
    };
  }
}

class _LegacyDecisionApiClient extends ApiClient {
  var getCalls = 0;
  var postCalls = 0;

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Object? data,
    String? idempotencyKey,
  }) async {
    postCalls++;
    return const {
      'decision': {
        'file_id': 'photo-7',
        'keep_state': 'keep',
        'version': 4,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    getCalls++;
    return const {
      'file': {
        'file_id': 'photo-7',
        'filename': 'photo-7.jpg',
        'format': 'JPEG',
        'analysis_state': 'completed',
        'keep_state': 'keep',
        'version': 4,
      },
    };
  }
}
