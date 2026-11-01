import 'dart:async';
import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/core/session/device_session_cubit.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_repository.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_report.dart';
import 'package:aves/bird_companion/features/jobs/domain/job_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'metadata_fixtures.dart';

void main() {
  for (final completion in [false, true]) {
    testWidgets('production ${completion ? 'completion' : 'run'} route previews then confirms one metadata task', (tester) async {
      final env = MetadataEnvironment();
      final deps = _Dependencies(env);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        BirdCompanionScope(
          dependencies: deps,
          child: MaterialApp(navigatorKey: navigator, home: const Scaffold(), onGenerateRoute: BirdAppRouter.onGenerateRoute),
        ),
      );
      unawaited(navigator.currentState!.pushNamed(completion ? BirdRoutes.smartFollowCompletion : BirdRoutes.smartFollowRun, arguments: completion ? const SmartFollowCompletionArgs('sf_fake') : const SmartFollowRunArgs('sf_fake')));
      await tester.pumpAndSettle();
      final entry = find.byKey(const Key('sf-metadata-open-preview'));
      await tester.scrollUntilVisible(entry, 300);
      await tester.ensureVisible(entry);
      await tester.pumpAndSettle();
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.text('预览识别信息更新'), findsOneWidget);
      expect(env.backend.creates, 0);
      final confirm = find.byKey(const Key('sf-metadata-confirm'));
      await tester.scrollUntilVisible(confirm, 250);
      await tester.ensureVisible(confirm);
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(env.backend.creates, 1);
      await tester.tap(find.byKey(const Key('sf-metadata-view-existing')));
      await tester.pumpAndSettle();
      expect(find.text('识别信息更新任务'), findsOneWidget);
      expect(find.text('正在更新'), findsOneWidget);
      expect(env.backend.updateReads, 1);
      expect(env.backend.creates, 1);
      await tester.pumpWidget(const SizedBox());
      await deps.dispose();
      env.dispose();
    });
  }
  testWidgets('direct production preview route cannot bypass capability', (tester) async {
    final env = MetadataEnvironment();
    env.backend.capability = false;
    final deps = _Dependencies(env);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      BirdCompanionScope(
        dependencies: deps,
        child: MaterialApp(navigatorKey: navigator, home: const Scaffold(), onGenerateRoute: BirdAppRouter.onGenerateRoute),
      ),
    );
    unawaited(navigator.currentState!.pushNamed(BirdRoutes.smartFollowMetadataPreview, arguments: const SmartFollowMetadataPreviewArgs('sf_fake')));
    await tester.pumpAndSettle();
    expect(find.text('当前盒子未开放统一信息更新，无法提交。'), findsOneWidget);
    expect(env.backend.previewReads, 0);
    expect(env.backend.creates, 0);
    await tester.pumpWidget(const SizedBox());
    await deps.dispose();
    env.dispose();
  });
}

class _Dependencies implements BirdCompanionDependencies {
  _Dependencies(this.env);
  final MetadataEnvironment env;
  @override
  SmartFollowRepository get smartFollowRepository => env.repository;
  @override
  late final JobRepository jobRepository = _Jobs(env);
  @override
  final CopyJobRepository copyJobRepository = _Copies();
  @override
  final DeviceSessionCubit deviceSessionCubit = _Session();
  @override
  final refreshCoordinator = SessionRefreshCoordinator();
  @override
  final apiClient = ApiClient()..configure(Uri.parse('http://127.0.0.1:12345'));
  @override
  Future<void> dispose() async {
    await refreshCoordinator.dispose();
    await apiClient.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Session implements DeviceSessionCubit {
  @override
  DeviceSessionState get state => DeviceSessionState(
    phase: DeviceSessionPhase.connected,
    device: DeviceConnection(id: 'box-1', name: 'BirdBox', baseUri: Uri.parse('http://127.0.0.1:12345'), networkMode: NetworkMode.lan),
  );
  @override
  Stream<DeviceSessionState> get stream => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Jobs implements JobRepository {
  _Jobs(this.env);
  final MetadataEnvironment env;
  @override
  Future<BirdJobStatus> detail(String id) => env.controller.readRecognition(id);
  @override
  Future<JobReport> report(String id) async => JobReport(jobId: id, result: JobReportResult.success, totalCount: 5, successCount: 5, failedCount: 0, skippedCount: 0);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Copies implements CopyJobRepository {
  @override
  Future<CopyJobDetail> getJob(String id) async => CopyJobDetail.fromJson({
    'copy_job_id': id,
    'state': 'completed',
    'stats': {'copied_files': 2, 'failed_files': 0, 'skipped_files': 0, 'not_applicable_files': 0, 'copied_bytes': 128},
    'review_export': {'enabled': false},
  });
  @override
  Future<CopyReport> jobReport(String id) async => CopyReport.fromJson({'copy_job_id': id, 'copied_files': 2, 'failed_files': 0, 'skipped_files': 0, 'not_applicable_files': 0});
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
