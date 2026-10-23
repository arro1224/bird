import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_repository.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_device_policy.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_config_cubit.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_confirmation_page.dart';
import 'package:aves/bird_companion/features/copy/presentation/widgets/storage_device_card.dart';
import 'package:aves/bird_companion/features/copy/presentation/widgets/copy_preview_items_sheet.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_copy_environment.dart';

void main() {
  testWidgets('missing copy configuration resource does not claim a photo was deleted', (tester) async {
    final repository = FakeCopyEnvironment()..readSource = () async => throw const ApiException(message: 'Not found', statusCode: 404, code: 'not_found');
    final cubit = CopyConfigCubit(repository, batchId: 'b', scope: CopyScope.batchAllAssets, pollInterval: Duration.zero);
    await cubit.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: const CopyConfigFlow(batchId: 'b'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('复制资源暂不可用'), findsOneWidget);
    expect(find.textContaining('照片详情不可用'), findsNothing);
    expect(tester.widget<FilledButton>(find.byKey(const Key('copy-content-next'))).onPressed, isNull);
    expect(repository.createCalls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await cubit.close();
  });

  test('copy-specific 404 business failures retain their dedicated message', () {
    const error = ApiException(message: '', statusCode: 404, code: 'COPY_PREVIEW_EXPIRED');
    expect(UserMessageMapper.fromCopyConfigurationError(error).title, UserMessageMapper.fromError(error).title);
    expect(UserMessageMapper.fromCopyConfigurationError(error).title, isNot('复制资源暂不可用'));
  });

  testWidgets('opening and closing the read-only preview sheet keeps the confirmed token', (tester) async {
    final repository = FakeCopyEnvironment();
    final cubit = CopyConfigCubit(repository, batchId: null, scope: CopyScope.mediaFullBackup, pollInterval: Duration.zero);
    await cubit.initialize();
    cubit.selectTarget('target');
    cubit.setConflictStrategy(ConflictStrategy.skip);
    await tester.pumpWidget(
      BirdCompanionScope(
        dependencies: _PreviewDependencies(),
        child: MaterialApp(
          home: BlocProvider.value(value: cubit, child: const CopyConfigFlow(batchId: null)),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('copy-content-next')));
    await tester.pumpAndSettle();
    final token = cubit.state.preview!.previewToken;
    await tester.scrollUntilVisible(find.byKey(const Key('copy-preview-items-open')), 150, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('copy-preview-items-open')));
    await tester.pumpAndSettle();
    expect(find.byType(CopyPreviewItemsSheet), findsOneWidget);
    expect(cubit.state.preview!.previewToken, token);
    expect(cubit.state.pageActive, true);
    Navigator.of(tester.element(find.byType(CopyPreviewItemsSheet))).pop();
    await tester.pumpAndSettle();
    expect(cubit.state.preview!.previewToken, token);
    expect(cubit.state.preflightStatus, CopyPreflightStatus.valid);
    await tester.pumpWidget(const SizedBox.shrink());
    await cubit.close();
  });

  testWidgets('an opaque route pauses the copy page and returning requires recheck', (tester) async {
    final cubit = CopyConfigCubit(FakeCopyEnvironment(), batchId: 'b', scope: CopyScope.batchAllAssets, pollInterval: Duration.zero);
    await cubit.initialize();
    cubit.selectTarget('target');
    cubit.setConflictStrategy(ConflictStrategy.skip);
    await cubit.fetchPreview();
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: const CopyConfigFlow(batchId: 'b'),
        ),
      ),
    );
    final navigator = Navigator.of(tester.element(find.byType(CopyConfigFlow)));
    final route = navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('other page'))));
    await tester.pumpAndSettle();
    expect(cubit.state.pageActive, false);
    expect(cubit.state.preview, isNull);
    navigator.pop();
    await route;
    await tester.pumpAndSettle();
    expect(cubit.state.pageActive, true);
    expect(cubit.state.preflightStatus, CopyPreflightStatus.needsRecheck);
    expect(cubit.state.preview, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await cubit.close();
  });

  test('source, import_source and role-forbidden storage are excluded; dual-use targets stay', () async {
    final repository = FakeCopyEnvironment();
    repository.storage = [
      b3Device('source', source: true, reasons: ['当前任务源设备']),
      b3Device('import-card', source: true, productRole: 'import_source'),
      b3Device('dual', source: true),
      b3Device('forbidden', target: false),
      b3Device('readonly', target: false, reasons: ['COPY_TARGET_READ_ONLY']),
      b3Device('offline', online: false),
      b3Device('legacy-source', source: true, target: false, online: false),
      b3Device('legacy-source-with-reason', source: true, target: false, reasons: ['当前任务源设备']),
      b3Device('read-only-dual', source: true, target: false, reasons: ['COPY_TARGET_READ_ONLY']),
    ];
    final cubit = CopyConfigCubit(repository, batchId: 'b', scope: CopyScope.batchAllAssets, preferredTargetMediaId: 'import-card', pollInterval: Duration.zero);
    addTearDown(cubit.close);
    await cubit.initialize();
    expect(cubit.state.targetMediaId, isNull);
    expect(cubit.state.targetCandidates.map((d) => d.mediaId), ['dual', 'readonly', 'offline', 'read-only-dual']);
    expect(cubit.state.availableTargets.single.mediaId, 'dual');
    cubit.selectTarget('import-card');
    expect(cubit.state.targetMediaId, isNull);
    cubit.selectTarget('dual');
    expect(cubit.state.targetMediaId, 'dual');
  });

  test('optional product_role is parsed without making it required for legacy device records', () {
    final json = <String, dynamic>{
      'media_id': 'disk',
      'display_name': 'disk',
      'kind': 'usb_flash',
      'kind_confidence': 'high',
      'capacity_bytes': 2000,
      'free_bytes': 1000,
      'role_state': 'available',
      'can_be_source': true,
      'can_be_target': true,
      'target_block_reasons': [],
      'identity_confidence': 'stable_uuid',
    };
    expect(StorageDeviceSummary.fromJson(json).productRole, isNull);
    expect(CopyDevicePolicy.canSelectTarget(StorageDeviceSummary.fromJson(json), 'source'), true);
    expect(CopyDevicePolicy.isTargetCandidate(StorageDeviceSummary.fromJson({...json, 'product_role': 'import_source'}), 'source'), false);
    expect(CopyDevicePolicy.canSelectTarget(StorageDeviceSummary.fromJson({...json, 'product_role': 'future_role'}), 'source'), true);
  });

  for (final nested in [false, true]) {
    for (final source in [false, true]) {
      test('${nested ? 'nested' : 'flat'} known ${source ? 'source' : 'target'} offline code gets the fixed recheck message', () {
        final code = source ? 'COPY_SOURCE_NOT_PRESENT' : 'COPY_TARGET_NOT_PRESENT';
        final payload = nested
            ? {
                'error': {'code': code, 'message': code},
              }
            : {'error_code': code, 'error_message': code};
        final error = ApiException.fromDio(
          DioException(
            requestOptions: RequestOptions(),
            type: DioExceptionType.badResponse,
            response: Response(requestOptions: RequestOptions(), statusCode: 409, data: payload),
          ),
        );
        expect(error.code, code);
        final user = UserMessageMapper.fromError(error);
        expect(user.message, source ? '相机卡已断开，请重新插入后重新预检。' : '目标 U 盘已断开，请重新插入或选择其他目标设备。');
        expect(user.message, isNot(contains(code)));
      });
    }
  }

  test('unknown 409 and unknown block reasons never become an invented unplug or raw code', () {
    final user = UserMessageMapper.fromError(const ApiException(message: 'COPY_SOMETHING_NEW', statusCode: 409, code: 'COPY_SOMETHING_NEW'));
    expect(user.message, isNot(contains('断开')));
    expect(user.message, isNot(contains('拔')));
    expect(user.message, isNot(contains('COPY_')));
    final text = CopyDevicePolicy.targetDisabledReason(b3Device('blocked', target: false, reasons: ['DEVICE_FUTURE_BLOCK', '/dev/sdb']));
    expect(text, isNot(contains('DEVICE_FUTURE_BLOCK')));
    expect(text, isNot(contains('/dev')));
  });

  testWidgets('disabled cards show Chinese reasons and do not invoke selection', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StorageDeviceCard(
            device: b3Device('read-only', target: false, reasons: ['COPY_TARGET_READ_ONLY']),
            role: '目标设备',
            selected: false,
            onTap: () => taps++,
          ),
        ),
      ),
    );
    expect(find.textContaining('设备为只读'), findsOneWidget);
    expect(find.textContaining('COPY_TARGET_READ_ONLY'), findsNothing);
    await tester.tap(find.byKey(const Key('storage-device-read-only-目标设备')));
    expect(taps, 0);
  });

  testWidgets('configuration UI excludes source cards while retaining an eligible dual-use target', (tester) async {
    final repository = FakeCopyEnvironment();
    repository.storage.addAll([b3Device('import-card', source: true, productRole: 'import_source'), b3Device('dual', source: true)]);
    final cubit = CopyConfigCubit(repository, batchId: 'b', scope: CopyScope.batchAllAssets, pollInterval: Duration.zero);
    await cubit.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: const CopyConfigFlow(batchId: 'b'),
        ),
      ),
    );
    await tester.scrollUntilVisible(find.byKey(const Key('storage-device-dual-目标设备')), 350, scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const Key('storage-device-source-目标设备')), findsNothing);
    expect(find.byKey(const Key('storage-device-import-card-目标设备')), findsNothing);
    expect(find.byKey(const Key('storage-device-dual-目标设备')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await cubit.close();
  });

  testWidgets('invalidated confirmation has disabled Start and a recheck action, no permanent spinner', (tester) async {
    final repository = FakeCopyEnvironment();
    final cubit = CopyConfigCubit(repository, batchId: 'b', scope: CopyScope.batchAllAssets, pollInterval: Duration.zero);
    await cubit.initialize();
    cubit.selectTarget('target');
    cubit.setConflictStrategy(ConflictStrategy.skip);
    await cubit.fetchPreview();
    repository.storage[1] = b3Device('target', online: false);
    await cubit.refreshDevices();
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: CopyFinalConfirmationStep(state: cubit.state, onBack: () {}, onRefreshPreview: cubit.fetchPreview, onSubmit: cubit.submit),
        ),
      ),
    );
    expect(tester.widget<FilledButton>(find.byKey(const Key('copy-final-submit'))).onPressed, isNull);
    expect(find.byKey(const Key('copy-recheck-preview')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('目标 U 盘已断开'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    await cubit.close();
  });
}

class _PreviewDependencies implements BirdCompanionDependencies {
  @override
  final CopyJobRepository copyJobRepository = _PlanItems();
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _PlanItems implements CopyJobRepository {
  @override
  Future<CopyJobItemPage> previewItems(String previewId, {String? cursor}) async => const CopyJobItemPage(items: [CopyJobItem(copyItemId: 'item')], hasMore: false);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
