import 'dart:io';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/simulation/mock_box_server.dart';
import 'package:aves/bird_companion/features/copy/data/copy_api.dart';
import 'package:aves/bird_companion/features/copy/data/copy_repository_impl.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_plan_integrity.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_api.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MockBoxServer server;
  late ApiClient client;
  setUp(() async {
    server = MockBoxServer(embeddedDemo: true, photoCount: 14, assetDirectory: Directory('tool/mock_box_server/assets'), logRequests: false, workflowAutoAdvance: true);
    client = ApiClient()..configure(await server.start());
  });
  tearDown(() async {
    await client.dispose();
    await server.close();
  });

  test('selected photos seal a real selection and preserve exact selection count', () async {
    final copy = CopyApi(client);
    final selection = await copy.createSelection('mock-batch-current', ['photo-0001', 'photo-0002', 'photo-0001'], clientRevision: 1);
    expect(selection.assetCount, 2);
    final devices = await copy.devices();
    expect(devices.devices.any((device) => device.canBeTarget), isTrue);
  });

  test('continuous copy advances without a computer and exposes files, history and metadata', () async {
    final api = SmartFollowApi(client);
    final cap = await api.capabilities();
    expect(cap.copy.continuousQueueAvailable, isTrue);
    expect(cap.canUpdateMetadata, isTrue);
    final job = await client.post(
      '/api/v1/projects/mock-batch-current/analysis-jobs',
      data: {
        'mode': 'standard',
        'smart_follow': {'target_media_id': 'media_7f9a76e6c97690b61aedf6fd'},
      },
    );
    final sid = job['smart_follow_session_id'] as String;
    var snapshot = await api.session(sid);
    expect(snapshot.isContinuous, isTrue);
    await api.act(sid, SmartFollowAction.pause, expectedStateVersion: snapshot.stateVersion);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    snapshot = await api.session(sid);
    expect(snapshot.recognizedCount, 0);
    await api.act(sid, SmartFollowAction.resume, expectedStateVersion: snapshot.stateVersion);
    for (var i = 0; i < 60; i++) {
      snapshot = await api.session(sid);
      if (snapshot.isFinished) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(snapshot.isFinished, isTrue);
    expect(snapshot.canShowCompletion, isTrue);
    expect(snapshot.copiedFileCount, 14);
    final first = await api.fileItems(sid, pageSize: 5);
    expect(first.items, hasLength(5));
    expect(first.hasMore, isTrue);
    final history = await api.groupedHistory();
    expect(history.items.any((item) => item.session?.sessionId == sid), isTrue);
    expect((await api.sessions()).items, hasLength(1));
    final availability = await api.metadataAvailability(sid);
    expect(availability.available, isTrue);
    final preview = await api.previewMetadata(sid);
    expect(preview.updatableAssetCount, 14);
    expect(preview.hasKnownWriteMode, isTrue);
    final update = await api.createMetadataUpdate(sid, data: {'preview_token': preview.previewToken, 'target_media_id': preview.targetMediaId});
    expect(update.isTerminal, isTrue);
    expect((await api.metadataUpdate(update.updateId)).updatedFileCount, 14);
  });

  test('review state survives closing and restarting the embedded box', () async {
    final directory = await Directory.systemTemp.createTemp('embedded-box-state-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/state.json');
    await client.dispose();
    await server.close();
    server = MockBoxServer(embeddedDemo: true, photoCount: 14, assetDirectory: Directory('tool/mock_box_server/assets'), logRequests: false, stateFile: file);
    client = ApiClient()..configure(await server.start());
    final page = await client.get('/api/v1/projects/mock-batch-current/files');
    final id = (page['items'] as List).first['file_id'];
    final detail = await client.get('/api/v1/files/$id');
    await client.post('/api/v1/files/$id/decision', data: {'keep_state': 'keep', 'version': (detail['decision'] as Map)['version'] ?? 1});
    await client.dispose();
    await server.close();
    server = MockBoxServer(embeddedDemo: true, photoCount: 14, assetDirectory: Directory('tool/mock_box_server/assets'), logRequests: false, stateFile: file);
    client = ApiClient()..configure(await server.start());
    expect(((await client.get('/api/v1/files/$id'))['decision'] as Map)['keep_state'], 'keep');
  });
  test('continuous sessions and completed file counts survive an embedded-box restart', () async {
    final directory = await Directory.systemTemp.createTemp('demo-follow-state-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/state.json');
    await client.dispose();
    await server.close();
    server = MockBoxServer(embeddedDemo: true, photoCount: 14, assetDirectory: Directory('tool/mock_box_server/assets'), logRequests: false, stateFile: file, workflowAutoAdvance: true);
    client = ApiClient()..configure(await server.start());
    final job = await client.post(
      '/api/v1/projects/mock-batch-current/analysis-jobs',
      data: {
        'mode': 'standard',
        'smart_follow': {'target_media_id': 'media_7f9a76e6c97690b61aedf6fd'},
      },
    );
    final sid = job['smart_follow_session_id'] as String;
    final api = SmartFollowApi(client);
    for (var i = 0; i < 60; i++) {
      if ((await api.session(sid)).isFinished) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect((await api.session(sid)).copiedFileCount, 14);
    await client.dispose();
    await server.close();
    server = MockBoxServer(embeddedDemo: true, photoCount: 14, assetDirectory: Directory('tool/mock_box_server/assets'), logRequests: false, stateFile: file, workflowAutoAdvance: true);
    client = ApiClient()..configure(await server.start());
    final restored = SmartFollowApi(client);
    expect((await restored.session(sid)).isFinished, isTrue);
    expect((await restored.session(sid)).copiedFileCount, 14);
    final second = await client.post(
      '/api/v1/projects/mock-batch-current/analysis-jobs',
      data: {
        'mode': 'standard',
        'smart_follow': {'target_media_id': 'media_7f9a76e6c97690b61aedf6fd'},
      },
    );
    expect(second['smart_follow_session_id'], isNot(sid));
    expect((await restored.sessions()).items, hasLength(2));
    expect((await restored.session(sid)).copiedFileCount, 14);
  });
  test('a single selected photo has a nonnegative, verifiable copy plan', () async {
    final copy = CopyApi(client);
    final selection = await copy.createSelection('mock-batch-current', ['photo-0001'], clientRevision: 1);
    final devices = (await copy.devices()).devices;
    final preview = await copy.preview(
      CopyRequestDraft(
        batchId: 'mock-batch-current',
        scope: CopyScope.selectedAssets,
        selectionId: selection.selectionId,
        sourceMediaId: devices.firstWhere((device) => device.canBeSource).mediaId,
        targetMediaId: devices.firstWhere((device) => device.canBeTarget).mediaId,
        conflictStrategy: ConflictStrategy.skip,
        reviewExport: const ReviewExportConfig.disabled(),
      ),
    );
    expect(preview.logicalPhotoCount, 1);
    expect(preview.plannedFileCount, 1);
    expect((await const CopyPlanVerifier().verify(preview, CopyRepositoryImpl(copy), isCurrent: () => true)).verified, isTrue);
  });
  test('ordinary copy history, disk aliases and selection counts survive restart', () async {
    final directory = await Directory.systemTemp.createTemp('demo-copy-state-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/state.json');
    await client.dispose();
    await server.close();
    server = MockBoxServer(embeddedDemo: true, photoCount: 14, assetDirectory: Directory('tool/mock_box_server/assets'), logRequests: false, stateFile: file);
    client = ApiClient()..configure(await server.start());
    var copy = CopyApi(client);
    final devices = (await copy.devices()).devices;
    final source = devices.firstWhere((device) => device.canBeSource);
    final target = devices.firstWhere((device) => device.canBeTarget);
    await copy.setDeviceAlias(target.mediaId, '演示备份盘');
    final selection = await copy.createSelection('mock-batch-current', ['photo-0001', 'photo-0002'], clientRevision: 1);
    final draft = CopyRequestDraft(
      batchId: 'mock-batch-current',
      scope: CopyScope.selectedAssets,
      selectionId: selection.selectionId,
      sourceMediaId: source.mediaId,
      targetMediaId: target.mediaId,
      conflictStrategy: ConflictStrategy.skip,
      reviewExport: const ReviewExportConfig.disabled(),
    );
    final preview = await copy.preview(draft);
    final created = await copy.createJob(draft, preview.previewToken);
    await client.dispose();
    await server.close();
    server = MockBoxServer(embeddedDemo: true, photoCount: 14, assetDirectory: Directory('tool/mock_box_server/assets'), logRequests: false, stateFile: file);
    client = ApiClient()..configure(await server.start());
    copy = CopyApi(client);
    expect((await copy.listJobs()).items.any((job) => job.copyJobId == created.copyJobId), isTrue);
    expect((await copy.getJob(created.copyJobId)).copyJobId, created.copyJobId);
    expect((await copy.devices()).devices.firstWhere((device) => device.mediaId == target.mediaId).presentationName, '演示备份盘');
    expect((await copy.preview(draft)).logicalPhotoCount, 2);
  });
}
