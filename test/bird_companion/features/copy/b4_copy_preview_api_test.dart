import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/features/copy/data/copy_api.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:flutter_test/flutter_test.dart';

// Synthetic wire responses, not captured board fixtures.
class PreviewClient extends ApiClient {
  PreviewClient({required this.building, required this.modern});
  final bool building, modern;
  final paths = <String>[];
  Map<String, dynamic> device(String id) => {
    'media_id': id,
    'display_name': id,
    'kind': 'usb_flash',
    'kind_confidence': 'high',
    'capacity_bytes': 2000000,
    'free_bytes': 1000000,
    'role_state': 'available',
    'can_be_source': id == 'source',
    'can_be_target': id == 'target',
    'target_block_reasons': [],
    'identity_confidence': 'stable_uuid',
  };
  Map<String, dynamic> get ready => {
    'state': 'ready',
    'preview_token': 'token',
    if (!building) 'preview_id': 'plan-id',
    'expires_at': DateTime.now().add(const Duration(minutes: 1)).toIso8601String(),
    if (modern) ...{'logical_assets': 5, 'planned_files': 2, 'planned_bytes': 200} else ...{'logical_photo_count': 5, 'actual_file_count': 2, 'total_bytes': 200},
    'date_directory_count': 1,
    'conflict_count': 3,
    'target_free_bytes': 1000000,
    'reserved_free_bytes': 100,
  };
  @override
  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? queryParameters, Map<String, String>? headers}) async {
    paths.add(path);
    if (path.endsWith('/storage/devices')) {
      return {
        'devices': [device('source'), device('target')],
      };
    }
    expect(path, endsWith('/copy-previews/plan-id'));
    return ready;
  }

  @override
  Future<Map<String, dynamic>> post(String path, {Object? data, String? idempotencyKey, Map<String, String>? headers}) async => building ? {'state': 'building', 'preview_id': 'plan-id'} : ready;
}

void main() {
  for (final building in [false, true]) {
    for (final modern in [false, true]) {
      test('preview adapter building=$building modern=$modern keeps id separate and planned count excludes skips', () async {
        final client = PreviewClient(building: building, modern: modern);
        final api = CopyApi(client);
        await api.devices();
        final result = await api.preview(const CopyRequestDraft(scope: CopyScope.batchAllAssets, sourceMediaId: 'source', targetMediaId: 'target', conflictStrategy: ConflictStrategy.skip, reviewExport: ReviewExportConfig.disabled()));
        expect(result.previewToken, 'token');
        expect(result.itemsId, 'plan-id');
        expect(result.logicalPhotoCount, 5);
        expect(result.actualFileCount, 2);
        expect(result.totalBytes, 200);
        expect(result.conflictCount, 3);
      });
    }
  }
}
