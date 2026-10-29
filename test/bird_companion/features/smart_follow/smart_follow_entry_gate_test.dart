import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/features/smart_follow/data/fake_smart_follow_backend.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_entry_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 旧盒子：`/recognition-capabilities` 直接 404。
class _OldBoxBackend extends FakeSmartFollowBackend {
  @override
  Future<SmartFollowCapabilities> capabilities() async => throw const ApiException(message: 'not found', statusCode: 404);
}

void main() {
  Widget host(SmartFollowRepository repository, {bool requireMetadataUpdate = false, bool withDisabled = true}) => MaterialApp(
    home: Scaffold(
      body: SmartFollowEntryGate(
        repository: repository,
        requireMetadataUpdate: requireMetadataUpdate,
        builder: (_, capabilities) => Text('入口可用 batch=${capabilities.copy.batchSize}'),
        disabledBuilder: withDisabled ? (_) => const Text('当前盒子版本暂不支持边识别边复制') : null,
      ),
    ),
  );

  testWidgets('能力就绪时显示入口，并可读到批参数', (tester) async {
    final repository = SmartFollowRepository(FakeSmartFollowBackend(batchSize: 4));
    addTearDown(repository.dispose);
    await tester.pumpWidget(host(repository));
    await tester.pumpAndSettle();
    expect(find.text('入口可用 batch=4'), findsOneWidget);
  });

  testWidgets('capability=false：隐藏入口（未给 disabledBuilder 时整块不占位）', (tester) async {
    final repository = SmartFollowRepository(FakeSmartFollowBackend(eligibilityAvailable: false));
    addTearDown(repository.dispose);
    await tester.pumpWidget(host(repository, withDisabled: false));
    await tester.pumpAndSettle();
    expect(find.textContaining('入口可用'), findsNothing);
    expect(find.textContaining('暂不支持'), findsNothing);
  });

  testWidgets('capability=false 但给了说明：显示原因而不是可点入口', (tester) async {
    final repository = SmartFollowRepository(FakeSmartFollowBackend(eligibilityAvailable: false));
    addTearDown(repository.dispose);
    await tester.pumpWidget(host(repository));
    await tester.pumpAndSettle();
    expect(find.text('当前盒子版本暂不支持边识别边复制'), findsOneWidget);
    expect(find.textContaining('入口可用'), findsNothing);
  });

  testWidgets('旧盒子 404：同样走不可用分支，不抛异常', (tester) async {
    final repository = SmartFollowRepository(_OldBoxBackend());
    addTearDown(repository.dispose);
    await tester.pumpWidget(host(repository));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('当前盒子版本暂不支持边识别边复制'), findsOneWidget);
  });

  testWidgets('信息更新门控：metadata=false 时即使跟随可用也不显示更新入口', (tester) async {
    final repository = SmartFollowRepository(FakeSmartFollowBackend(metadataSupported: false));
    addTearDown(repository.dispose);
    await tester.pumpWidget(host(repository, requireMetadataUpdate: true));
    await tester.pumpAndSettle();
    expect(find.textContaining('入口可用'), findsNothing);

    final supported = SmartFollowRepository(FakeSmartFollowBackend());
    addTearDown(supported.dispose);
    await tester.pumpWidget(host(supported, requireMetadataUpdate: true));
    await tester.pumpAndSettle();
    expect(find.textContaining('入口可用'), findsOneWidget);
  });
}
