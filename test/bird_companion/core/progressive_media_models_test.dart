import 'dart:convert';
import 'dart:io';

import 'package:aves/bird_companion/core/media/media_asset_event.dart';
import 'package:aves/bird_companion/core/media/media_asset_models.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('旧照片缺少资源状态时保持 legacy URL 加载兼容', () {
    final preview = PreviewRef.fromJson(const {
      'thumb_ref': 'http://box/thumb.jpg',
      'preview_ref': 'http://box/preview.jpg',
    });

    expect(preview.thumbnailStatus, MediaAssetStatus.legacy);
    expect(preview.previewStatus, MediaAssetStatus.legacy);
    expect(preview.thumbnailStatus.canRequest, isTrue);
    expect(preview.toJson(), isNot(contains('thumbnail_status')));
    expect(preview.toJson(), isNot(contains('preview_status')));
  });

  test('四种资源状态可往返，未知值不会破坏照片解析', () {
    final pending = PreviewRef.fromJson(const {
      'thumbnail_status': 'pending',
      'preview_status': 'not_requested',
    });
    final unknown = PreviewRef.fromJson(const {
      'thumbnail_status': 'future_state',
      'preview_status': 'failed',
    });

    expect(pending.thumbnailStatus, MediaAssetStatus.pending);
    expect(pending.previewStatus, MediaAssetStatus.notRequested);
    expect(pending.toJson()['thumbnail_status'], 'pending');
    expect(unknown.thumbnailStatus, MediaAssetStatus.unknown);
    expect(unknown.previewStatus, MediaAssetStatus.failed);
    expect(unknown.toJson(), isNot(contains('thumbnail_status')));
  });

  test('候选 Photo 与 asset_ready fixtures 可被运行时模型解析', () {
    final photoJson = _fixture('photo-progressive.response.json');
    final eventJson = _fixture('asset-ready-event.response.json');
    final photo = PhotoSummary.fromJson(photoJson);
    final event = AssetReadyEvent.tryFromDeviceEvent(
      DeviceEvent.fromJson(eventJson),
    );

    expect(photo.preview.thumbnailStatus, MediaAssetStatus.pending);
    expect(photo.preview.previewStatus, MediaAssetStatus.notRequested);
    expect(event, isNotNull);
    expect(event?.eventId, 'evt-asset-0001');
    expect(event?.fileId, 'file-xxx');
    expect(event?.kind, MediaAssetKind.thumbnail);
    expect(event?.etag, '"sha256-opaque-value"');
  });

  test('不完整或非 ready 的资源事件会被安全忽略', () {
    final event = DeviceEvent(
      type: 'asset_ready',
      payload: const {
        'project_id': 'project-1',
        'file_id': 'file-1',
        'kind': 'thumbnail',
        'status': 'pending',
      },
      timestamp: DateTime.utc(2026, 8, 16),
    );

    expect(AssetReadyEvent.tryFromDeviceEvent(event), isNull);
  });
}

Map<String, dynamic> _fixture(String name) {
  final file = File(
    'docs/contracts/proposals/progressive-media/fixtures/$name',
  );
  return Map<String, dynamic>.from(jsonDecode(file.readAsStringSync()) as Map);
}
