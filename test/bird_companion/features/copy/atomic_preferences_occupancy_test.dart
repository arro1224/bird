import 'package:aves/bird_companion/app/app_router.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_device_policy.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_config_cubit.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_confirmation_page.dart';
import 'package:aves/bird_companion/features/copy/presentation/widgets/storage_device_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fakes/fake_copy_environment.dart';

Future<CopyConfigCubit> ready(FakeCopyEnvironment repository) async {
  final cubit = CopyConfigCubit(repository, batchId: 'batch', scope: CopyScope.batchAllAssets, pollInterval: Duration.zero);
  await cubit.initialize();
  cubit.selectTarget('target');
  cubit.setPairPolicy(PairPolicy.both);
  cubit.setConflictStrategy(ConflictStrategy.skip);
  expect(await cubit.fetchPreview(), isTrue);
  return cubit;
}

void main() {
  test('atomic creation consumes receipt without a second preference write', () async {
    final repository = FakeCopyEnvironment()..atomicPreferences = true;
    final cubit = await ready(repository);
    addTearDown(cubit.close);
    expect(repository.savedVersions, isEmpty);
    expect(cubit.state.draft.savePreferencesOnCreate, isTrue);
    expect(cubit.state.draft.toJson().containsKey('save_preferences_on_create'), isFalse);
    expect(await cubit.submit(), isTrue);
    expect(repository.createCalls, 1);
    expect(repository.savedVersions, isEmpty);
    expect(cubit.state.preferencesVersion, 2);
    expect(cubit.state.preferenceSaveNotice, isNull);
  });
  test('missing atomic receipt remains visible without duplicate create or compensation', () async {
    final repository = FakeCopyEnvironment()..atomicPreferences = true..includeAtomicReceipt = false;
    final cubit = await ready(repository);
    addTearDown(cubit.close);
    expect(await cubit.submit(), isTrue);
    expect(repository.createCalls, 1);
    expect(repository.savedVersions, isEmpty);
    expect(cubit.state.preferenceSaveNotice, contains('原子偏好回执'));
    expect(await cubit.submit(), isFalse);
  });
  test('legacy capability saves separately only after successful creation', () async {
    final repository = FakeCopyEnvironment();
    final cubit = await ready(repository);
    addTearDown(cubit.close);
    expect(cubit.state.draft.savePreferencesOnCreate, isFalse);
    expect(repository.savedVersions, isEmpty);
    expect(await cubit.submit(), isTrue);
    expect(repository.savedVersions, [1]);
  });
  testWidgets('unknown free capacity is not displayed as zero available', (tester) async {
    final device = b3Device('target', free: 0, capacityKnown: false);
    expect(CopyDevicePolicy.canSelectTarget(device, null), isFalse);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StorageDeviceCard(device: device, role: '目标设备', selected: false, onTap: () {}))));
    expect(find.textContaining('正在读取设备容量'), findsWidgets);
    expect(find.textContaining('0 MB 可用'), findsNothing);
  });
  for (final kind in ['copy', 'smart_follow']) {
    testWidgets('busy $kind routes to the authoritative owner', (tester) async {
      final repository = FakeCopyEnvironment();
      final cubit = await ready(repository);
      repository.storage[1] = b3Device('target', reasons: ['COPY_TARGET_BUSY'], blockingTasks: [BlockingCopyTask(kind: kind, id: 'owner-original')]);
      await cubit.refreshDevices();
      RouteSettings? opened;
      await tester.pumpWidget(MaterialApp(
        onGenerateRoute: (settings) { opened = settings; return MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Current owner'))); },
        home: BlocProvider.value(value: cubit, child: const CopyConfigFlow(batchId: 'batch')),
      ));
      await tester.pumpAndSettle();
      final button = find.byKey(const Key('copy-view-current-job'));
      await tester.scrollUntilVisible(button, 300, scrollable: find.byType(Scrollable).first);
      tester.widget<TextButton>(button).onPressed!();
      await tester.pumpAndSettle();
      expect(opened!.name, kind == 'copy' ? BirdRoutes.copyJobDetail : BirdRoutes.smartFollowRun);
      expect(kind == 'copy' ? (opened!.arguments as CopyJobDetailArgs).copyJobId : (opened!.arguments as SmartFollowRunArgs).sessionId, 'owner-original');
      await tester.pumpWidget(const SizedBox.shrink());
      await cubit.close();
    });
  }
}
