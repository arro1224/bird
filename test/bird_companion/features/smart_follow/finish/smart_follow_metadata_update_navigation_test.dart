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
import 'package:aves/bird_companion/features/jobs/domain/job_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'metadata_update_fixtures.dart';

void main() {
  testWidgets('production parent route opens mapped RC3 job then fresh SF-B5 preview without writes', (tester) async {
    final env = MetadataUpdateEnvironment();
    final deps = _Dependencies(env);
    CopyJobDetailArgs? opened;
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      BirdCompanionScope(
        dependencies: deps,
        child: MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(),
          onGenerateRoute: (settings) {
            if (settings.name == BirdRoutes.copyJobDetail) {
              opened = settings.arguments! as CopyJobDetailArgs;
              return MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Existing RC3 detail')));
            }
            return BirdAppRouter.onGenerateRoute(settings);
          },
        ),
      ),
    );
    unawaited(navigator.currentState!.pushNamed(BirdRoutes.smartFollowMetadataUpdate, arguments: const SmartFollowMetadataUpdateArgs('sf_fake', updateId: 'update-1')));
    await tester.pumpAndSettle();
    expect(find.text('识别信息更新完成'), findsOneWidget);
    final copy = find.byKey(const Key('sf-update-copy-1'));
    await tester.scrollUntilVisible(copy, 250);
    await tester.ensureVisible(copy);
    await tester.pumpAndSettle();
    await tester.tap(copy);
    await tester.pumpAndSettle();
    expect(opened!.copyJobId, 'copy-2');
    expect(opened!.deviceId, 'box-1');
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    env.backend.available = true;
    deps.refreshCoordinator.requestRefresh();
    await tester.pumpAndSettle();
    final preview = find.byKey(const Key('sf-update-preview-again'));
    await tester.scrollUntilVisible(preview, 250);
    await tester.ensureVisible(preview);
    await tester.pumpAndSettle();
    await tester.tap(preview);
    await tester.pumpAndSettle();
    expect(find.text('预览识别信息更新'), findsOneWidget);
    expect(env.backend.previewReads, 1);
    expect(env.backend.creates, 0);
    await tester.pumpWidget(const SizedBox());
    await deps.dispose();
    env.dispose();
  });
  testWidgets('production route discovers existing active ID from session-only args', (tester) async {
    final env = MetadataUpdateEnvironment();
    final deps = _Dependencies(env);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      BirdCompanionScope(
        dependencies: deps,
        child: MaterialApp(navigatorKey: navigator, home: const Scaffold(), onGenerateRoute: BirdAppRouter.onGenerateRoute),
      ),
    );
    unawaited(navigator.currentState!.pushNamed(BirdRoutes.smartFollowMetadataUpdate, arguments: const SmartFollowMetadataUpdateArgs('sf_fake')));
    await tester.pumpAndSettle();
    expect(find.text('识别信息更新完成'), findsOneWidget);
    expect(env.backend.parentReads, ['update-1']);
    expect(env.backend.creates, 0);
    await tester.pumpWidget(const SizedBox());
    await deps.dispose();
    env.dispose();
  });
}

class _Dependencies implements BirdCompanionDependencies {
  _Dependencies(this.env);
  final MetadataUpdateEnvironment env;
  @override
  SmartFollowRepository get smartFollowRepository => env.repository;
  @override
  final DeviceSessionCubit deviceSessionCubit = _Session();
  @override
  final refreshCoordinator = SessionRefreshCoordinator();
  @override
  final apiClient = ApiClient()..configure(Uri.parse('http://127.0.0.1:12345'));
  @override
  final JobRepository jobRepository = _Jobs();
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
  @override
  Future<BirdJobStatus> detail(String id) async => BirdJobStatus(id: id, type: BirdJobType.analysis, state: BirdJobState.completed);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
