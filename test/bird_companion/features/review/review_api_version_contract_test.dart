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
  }) async {
    postCalls++;
    return const {};
  }
}
