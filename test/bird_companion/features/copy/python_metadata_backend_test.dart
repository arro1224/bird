import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_metadata_page.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_api.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/finish/smart_follow_metadata_update_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import '../smart_follow/finish/metadata_fixtures.dart';

void main() {
  test('real Python: SmartFollow and ordinary CopyJob update metadata without recopy', () async {
    HttpOverrides.global = null;
    final client = ApiClient()..configure(Uri.parse(Platform.environment['BIRDBOX_METADATA_BASE']!));
    try {
      final pair = await client.post('/api/v1/device/pair', data: {'pairing_code': '123456', 'client_name': 'metadata-dart'}, idempotencyKey: 'metadata-dart-pair');
      client.setSession(accessToken: pair['access_token'] as String);
      final info = await client.get('/local-control-fixture');
      final api = SmartFollowApi(client);
      expect((await api.capabilities()).canUpdateMetadata, isTrue);
      final session = await api.startOnRecognitionJob(
        info['job_id'] as String,
        SmartFollowStartRequest(targetMediaId: info['target_media_id'] as String, pairPolicy: 'both', reviewExportEnabled: false),
        idempotencyKey: 'metadata-dart-start',
      );
      for (var i = 0; i < 2; i++) {
        await client.post('/local-control-fixture/commit/$i', data: <String, dynamic>{});
      }
      var children = await api.childJobs(session.sessionId, pageSize: 100);
      for (var i = 0; i < 100 && (children.items.isEmpty || children.items.any((c) => c.state.wire != 'completed')); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        children = await api.childJobs(session.sessionId, pageSize: 100);
      }
      expect(children.items, isNotEmpty);
      expect(children.items.every((c) => c.state.wire == 'completed'), isTrue);
      final before = await client.get('/local-control-fixture/report');
      final preview = await api.previewMetadata(session.sessionId);
      expect(preview.updatableFileCount, 2);
      final created = await api.createMetadataUpdate(session.sessionId, data: {'preview_token': preview.previewToken, 'target_media_id': preview.targetMediaId}, idempotencyKey: 'metadata-dart-confirm');
      var update = await api.metadataUpdate(created.updateId);
      for (var i = 0; i < 100 && !update.isTerminal; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        update = await api.metadataUpdate(created.updateId);
      }
      expect(SmartFollowMetadataUpdateReport(update).complete, isTrue);
      expect(update.updatedFileCount, 2);
      final file = (info['file_ids'] as List).first as String;
      final detail = await client.get('/api/v1/files/$file');
      await client.post('/api/v1/files/$file/decision', data: {'user_species': '人工鸟种', 'version': (detail['decision'] as Map?)?['version'] ?? detail['version'] ?? 0}, idempotencyKey: 'metadata-dart-review');
      final controller = CopyMetadataController(client: client, storage: MetadataStore(), copyJobId: children.items.first.copyJobId, deviceKey: 'box', currentKey: () => 'box');
      try {
        await controller.refresh();
        expect(controller.error, isNull);
        await controller.prepare();
        expect(controller.preview, isNotNull);
        expect(controller.canConfirm, isTrue);
        await controller.confirm();
        expect(controller.error, isNull);
        for (var i = 0; i < 100 && controller.update?.childrenSettled != true; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await controller.refresh();
        }
        expect(controller.update?.state, 'completed');
        final after = await client.get('/local-control-fixture/report');
        expect(after['file_count'], before['file_count']);
        expect(after['hashes'], before['hashes']);
        expect(after['xmp_count'], 2);
        expect(after['csv_count'], 2);
      } finally {
        controller.dispose();
      }
    } finally {
      await client.dispose();
    }
  }, skip: Platform.environment['BIRDBOX_METADATA_BASE'] == null ? 'Requires isolated production Python metadata fixture.' : false);

  testWidgets('real Python page: preview then explicit confirmation and settled report', (tester) async {
    HttpOverrides.global = null;
    final font = File('C:/Windows/Fonts/msyh.ttc');
    await tester.runAsync(() async {
      if (await font.exists()) {
        final loader = FontLoader('AcceptanceChinese')..addFont(font.readAsBytes().then(ByteData.sublistView));
        await loader.load();
      }
    });
    final client = ApiClient()..configure(Uri.parse(Platform.environment['BIRDBOX_METADATA_BASE']!));
    late CopyMetadataController controller;
    await tester.runAsync(() async {
      final pair = await client.post('/api/v1/device/pair', data: {'pairing_code': '123456', 'client_name': 'metadata-widget'}, idempotencyKey: 'metadata-widget-pair');
      client.setSession(accessToken: pair['access_token'] as String);
      final info = await client.get('/local-control-fixture');
      final api = SmartFollowApi(client);
      final id = await api.sessionIdForRecognitionJob(info['job_id'] as String);
      final children = await api.childJobs(id!, pageSize: 100);
      final file = (info['file_ids'] as List).first as String;
      final detail = await client.get('/api/v1/files/$file');
      final reviewVersion = (detail['decision'] as Map?)?['version'] ?? detail['version'] ?? 0;
      await client.post(
        '/api/v1/files/$file/decision',
        data: {
          'user_tags': ['页面验收 $reviewVersion'],
          'version': reviewVersion,
        },
        idempotencyKey: 'metadata-widget-review-$reviewVersion',
      );
      controller = CopyMetadataController(client: client, storage: MetadataStore(), copyJobId: children.items.first.copyJobId, deviceKey: 'box-widget', currentKey: () => 'box-widget');
    });
    final boundary = GlobalKey();
    Future<void> screenshot(String name) async {
      await tester.runAsync(() async {
        await tester.pump();
        final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 1);
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
        final path = File('build/$name.png');
        await path.parent.create(recursive: true);
        await path.writeAsBytes(bytes);
        image.dispose();
      });
    }

    try {
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1;
      await tester.runAsync(() async {
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              theme: ThemeData(fontFamily: 'AcceptanceChinese'),
              home: CopyMetadataPage(controller: controller),
            ),
          ),
        );
        for (var i = 0; i < 300 && controller.busy; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pump();
      expect(controller.error, isNull);
      expect(controller.enabled, isTrue);
      expect(controller.availability?.available, isTrue, reason: '${controller.availability?.raw} / ${controller.update?.raw}');
      await tester.runAsync(() async {
        await tester.tap(find.text('预览更新范围'));
        for (var i = 0; i < 300 && controller.busy; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pump();
      expect(controller.preview, isNotNull);
      debugPrint('UI acceptance: preview rendered');
      await screenshot('metadata-ordinary-real-python-preview');
      debugPrint('UI acceptance: preview screenshot saved');
      await tester.runAsync(() async {
        debugPrint('UI acceptance: tap confirm');
        await tester.tap(find.text('确认更新信息'));
        for (var i = 0; i < 300 && controller.busy; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        for (var i = 0; i < 100 && controller.update?.childrenSettled != true; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await controller.refresh();
        }
      });
      debugPrint('UI acceptance: update settled');
      await tester.runAsync(() => tester.pump());
      expect(controller.update?.state, 'completed');
      expect(controller.error, isNull);
      expect(find.text('识别信息更新完成'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await screenshot('metadata-ordinary-real-python-completed');
    } finally {
      await tester.runAsync(() => tester.pumpWidget(const SizedBox.shrink()));
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await client.dispose();
    }
  }, skip: Platform.environment['BIRDBOX_METADATA_BASE'] == null);
}
