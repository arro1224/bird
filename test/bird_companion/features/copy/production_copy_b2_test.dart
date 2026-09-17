import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/features/copy/data/copy_api.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('copy-v1 scope / policy / conflict enums', () {
    test('parses the four frozen copy scopes', () {
      expect(CopyScope.fromWire('selected_assets'), CopyScope.selectedAssets);
      expect(CopyScope.fromWire('kept_assets'), CopyScope.keptAssets);
      expect(CopyScope.fromWire('batch_all_assets'), CopyScope.batchAllAssets);
      expect(CopyScope.fromWire('media_full_backup'), CopyScope.mediaFullBackup);
    });

    test('rejects an invented copy scope instead of creating a temporary enum', () {
      expect(
        () => CopyScope.fromWire('dual'),
        throwsA(isA<ProtocolCompatibilityException>()),
      );
    });

    test('parses pair policies and conflict strategies', () {
      expect(PairPolicy.fromWire('raw_only'), PairPolicy.rawOnly);
      expect(PairPolicy.fromWire('jpeg_only'), PairPolicy.jpegOnly);
      expect(PairPolicy.fromWire('both'), PairPolicy.both);
      expect(ConflictStrategy.fromWire('skip'), ConflictStrategy.skip);
      expect(ConflictStrategy.fromWire('overwrite'), ConflictStrategy.overwrite);
      expect(ConflictStrategy.fromWire('keep_both'), ConflictStrategy.keepBoth);
    });
  });

  group('review export config', () {
    test('enabled export requires xmp and csv in v1', () {
      final config = ReviewExportConfig.fromJson({
        'enabled': true,
        'write_xmp': true,
        'write_csv': true,
        'embed_into_supported_copy': true,
      });
      expect(config.enabled, isTrue);
      expect(config.writeXmp, isTrue);
      expect(config.writeCsv, isTrue);
      expect(config.embedIntoSupportedCopy, isTrue);
    });

    test('disabled export forces every flag to false', () {
      final config = ReviewExportConfig.fromJson({'enabled': false});
      expect(config.enabled, isFalse);
      expect(config.writeXmp, isFalse);
      expect(config.writeCsv, isFalse);
      expect(config.embedIntoSupportedCopy, isFalse);
    });
  });

  group('storage device summary', () {
    test('parses the protocol device fields without linux paths', () {
      final device = StorageDeviceSummary.fromJson(_deviceJson());
      expect(device.mediaId, 'media_7f9a76e6c97690b61aedf6fd');
      expect(device.presentationName, 'U 盘 Ee');
      expect(device.kind, 'usb_flash');
      expect(device.canBeSource, isFalse);
      expect(device.canBeTarget, isTrue);
      expect(device.online, isTrue);
      expect(device.identityStable, isTrue);
    });

    test('user alias wins over label for presentation', () {
      final device = StorageDeviceSummary.fromJson({
        ..._deviceJson(),
        'user_alias': '我的备份盘',
      });
      expect(device.presentationName, '我的备份盘');
    });

    test('degraded identity cannot be a long-lived default target', () {
      final device = StorageDeviceSummary.fromJson({
        ..._deviceJson(),
        'identity_confidence': 'degraded',
      });
      expect(device.identityStable, isFalse);
    });
  });

  group('copy preview', () {
    test('parses protocol counts, token and expiry', () {
      final preview = CopyPreview.fromJson(_previewJson());
      expect(preview.previewToken, 'preview_mock_1');
      expect(preview.logicalPhotoCount, 34);
      expect(preview.actualFileCount, 67);
      expect(preview.rawCount, 34);
      expect(preview.videoCount, 0);
      expect(preview.companionCount, 2);
      expect(preview.conflictCount, 3);
      expect(preview.hasEnoughSpace, isTrue);
    });

    test('rejects preview without source and target snapshots', () {
      expect(
        () => CopyPreview.fromJson(_previewJson()..remove('source')),
        throwsA(isA<ProtocolCompatibilityException>()),
      );
    });
  });

  group('selection snapshot and job summary', () {
    test('parses an immutable selection snapshot', () {
      final snapshot = CopySelectionSnapshot.fromJson({
        'selection_id': 'sel_abc',
        'asset_count': 4,
        'created_at': '2026-08-24T14:30:00+08:00',
      });
      expect(snapshot.selectionId, 'sel_abc');
      expect(snapshot.assetCount, 4);
    });

    test('parses a created copy job summary', () {
      final job = CopyJobSummary.fromJson({
        'copy_job_id': 'copy_xyz',
        'state': 'queued',
        'event_seq': 0,
      });
      expect(job.copyJobId, 'copy_xyz');
      expect(job.eventSeq, 0);
    });

    test('creates an rc3 selection through session, chunk and seal', () async {
      final client = _SelectionApiClient();
      final snapshot = await CopyApi(client).createSelection(
        'batch_1',
        ['asset_1', 'asset_2'],
        clientRevision: 9,
      );

      expect(snapshot.selectionId, 'sel_1');
      expect(snapshot.assetCount, 2);
      expect(client.paths, [
        '/api/v1/batches/batch_1/copy-assets',
        '/api/v1/batches/batch_1/copy-selection-sessions',
        '/api/v1/copy-selection-sessions/session_1/chunks',
        '/api/v1/copy-selection-sessions/session_1/seal',
      ]);
      expect(client.posts.last, {'expected_unique_count': 2});
    });
  });

  group('copy request draft', () {
    test('serializes the preview request body per §13.4', () {
      const draft = CopyRequestDraft(
        batchId: 'batch_1',
        scope: CopyScope.recognizedAssets,
        sourceMediaId: 'media_src',
        sourceBindingToken: 'src_binding',
        targetMediaId: 'media_dst',
        expectedPreferencesVersion: 2,
        pairPolicy: PairPolicy.rawOnly,
        conflictStrategy: ConflictStrategy.keepBoth,
        reviewExport: ReviewExportConfig(
          enabled: true,
          writeXmp: true,
          writeCsv: true,
          embedIntoSupportedCopy: true,
        ),
      );
      expect(draft.toJson()['scope'], 'recognized_assets');
      expect(draft.toJson()['source_binding_token'], 'src_binding');
      expect(draft.toJson()['expected_preferences_version'], 2);
      expect(draft.toJson()['conflict_strategy'], 'keep_both');
      expect(draft.toJson()['pair_policy'], 'raw_only');
      expect((draft.toJson()['review_export'] as Map)['enabled'], isTrue);
    });

    test('sends explicit null selection_id for non-selected rc3 scopes', () {
      const draft = CopyRequestDraft(
        batchId: 'batch_1',
        scope: CopyScope.batchAllAssets,
        sourceMediaId: 'media_src',
        targetMediaId: 'media_dst',
        reviewExport: ReviewExportConfig.disabled(),
      );
      expect(draft.toJson()['selection_id'], isNull);
    });

    test('sends explicit null batch policy fields for media_full_backup', () {
      const draft = CopyRequestDraft(
        scope: CopyScope.mediaFullBackup,
        sourceMediaId: 'media_src',
        targetMediaId: 'media_dst',
        pairPolicy: PairPolicy.both,
        conflictStrategy: ConflictStrategy.skip,
        reviewExport: ReviewExportConfig.disabled(),
      );
      expect(draft.toJson()['pair_policy'], isNull);
      expect(draft.toJson()['batch_id'], isNull);
      expect(draft.toJson()['expected_preferences_version'], isNull);
    });
  });
}

class _SelectionApiClient extends ApiClient {
  final List<String> paths = [];
  final List<Object?> posts = [];

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  }) async {
    paths.add(path);
    return {
      'batch_id': 'batch_1',
      'manifest_revision': 4,
      'items': const <Object>[],
      'next_cursor': null,
    };
  }

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Object? data,
    String? idempotencyKey,
    Map<String, String>? headers,
  }) async {
    paths.add(path);
    posts.add(data);
    if (path.endsWith('/copy-selection-sessions')) {
      return {'session_id': 'session_1', 'state': 'open'};
    }
    if (path.endsWith('/chunks')) {
      return {
        'session_id': 'session_1',
        'chunk_index': 0,
        'accepted_count': 2,
      };
    }
    return {
      'selection_id': 'sel_1',
      'batch_id': 'batch_1',
      'count': 2,
      'digest': List.filled(64, 'a').join(),
      'client_revision': 9,
      'manifest_revision': 4,
      'sealed': true,
    };
  }
}

Map<String, dynamic> _deviceJson() => {
  'media_id': 'media_7f9a76e6c97690b61aedf6fd',
  'display_name': 'U 盘 Ee',
  'kind': 'usb_flash',
  'kind_confidence': 'medium',
  'detail': 'SanDisk Ultra USB 3.0 · 28.7 GB · EXFAT',
  'capacity_bytes': 30765203456,
  'free_bytes': 30500000000,
  'filesystem': 'exfat',
  'label': 'Ee',
  'role_state': 'available',
  'can_be_source': false,
  'can_be_target': true,
  'target_block_reasons': <String>[],
  'identity_confidence': 'stable_uuid',
  'last_seen_at': '2026-08-24T14:30:00+08:00',
};

Map<String, dynamic> _previewJson() => {
  'preview_token': 'preview_mock_1',
  'expires_at': '2026-08-24T15:00:00+08:00',
  'source': _deviceJson(),
  'target': _deviceJson(),
  'logical_photo_count': 34,
  'actual_file_count': 67,
  'total_bytes': 1073741824,
  'raw_count': 34,
  'jpeg_count': 33,
  'video_count': 0,
  'companion_count': 2,
  'estimated_date_directories': 2,
  'conflict_count': 3,
  'target_free_bytes': 30500000000,
  'safety_reserve_bytes': 1073741824,
  'unsupported_count': 0,
  'missing_count': 1,
};
