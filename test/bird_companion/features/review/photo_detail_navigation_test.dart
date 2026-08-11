import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/core/data/app_data_change_bus.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/core/session/session_refresh_coordinator.dart';
import 'package:aves/bird_companion/features/review/domain/review_repository.dart';
import 'package:aves/bird_companion/features/review/presentation/photo_detail_page.dart';
import 'package:aves/bird_companion/features/review/presentation/widgets/subject_overlay_view.dart';
import 'package:aves/bird_companion/features/settings/data/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('详情箭头复用原地翻页逻辑并遵守首尾边界', (tester) async {
    final repository = _ReviewRepository();
    await tester.pumpWidget(
      _app(
        repository,
        const PhotoDetailPage(
          fileId: 'p1',
          displayIndex: 1,
          totalCount: 3,
          sequence: ['p1', 'p2', 'p3'],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.loadedIds, ['p1']);
    expect(find.byKey(const ValueKey('photo-previous-button')), findsNothing);
    expect(find.byKey(const ValueKey('photo-next-button')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('photo-next-button')));
    await tester.pumpAndSettle();
    expect(repository.loadedIds, ['p1', 'p2']);
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.byKey(const ValueKey('photo-previous-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('photo-next-button')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('photo-next-button')));
    await tester.pumpAndSettle();
    expect(repository.loadedIds, ['p1', 'p2', 'p3']);
    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.byKey(const ValueKey('photo-previous-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('photo-next-button')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('photo-previous-button')));
    await tester.pumpAndSettle();
    expect(repository.loadedIds, ['p1', 'p2', 'p3', 'p2']);
    expect(find.text('2 / 3'), findsOneWidget);
  });

  testWidgets('已加载末尾的下一张箭头调用现有分页加载器', (tester) async {
    final repository = _ReviewRepository();
    var loadMoreCount = 0;
    await tester.pumpWidget(
      _app(
        repository,
        PhotoDetailPage(
          fileId: 'p1',
          displayIndex: 1,
          totalCount: 2,
          sequence: const ['p1'],
          hasMoreSequence: true,
          loadMoreSequence: () async {
            loadMoreCount++;
            return const PhotoSequencePage(ids: ['p1', 'p2'], hasMore: false);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('photo-next-button')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('photo-next-button')));
    await tester.pumpAndSettle();

    expect(loadMoreCount, 1);
    expect(repository.loadedIds, ['p1', 'p2']);
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.byKey(const ValueKey('photo-previous-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('photo-next-button')), findsNothing);
  });

  testWidgets('右上角菜单保留翻页和修改记录入口', (tester) async {
    final repository = _ReviewRepository();
    await tester.pumpWidget(
      _app(
        repository,
        const PhotoDetailPage(
          fileId: 'p2',
          displayIndex: 2,
          totalCount: 3,
          sequence: ['p1', 'p2', 'p3'],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('photo-previous-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('photo-next-button')), findsOneWidget);
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();

    expect(find.text('上一张'), findsOneWidget);
    expect(find.text('下一张'), findsOneWidget);
    expect(find.text('修改记录'), findsOneWidget);

    await tester.tap(find.text('上一张'));
    await tester.pumpAndSettle();
    expect(repository.loadedIds.last, 'p1');
  });

  testWidgets('自动下一张设置继续复用详情翻页逻辑', (tester) async {
    final repository = _ReviewRepository();
    await tester.pumpWidget(
      _app(
        repository,
        const PhotoDetailPage(
          fileId: 'p1',
          displayIndex: 1,
          totalCount: 2,
          sequence: ['p1', 'p2'],
        ),
        autoAdvance: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('保留'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('保留'));
    await tester.pumpAndSettle();

    expect(repository.savedDecisions, hasLength(1));
    expect(repository.savedDecisions.single.fileId, 'p1');
    expect(repository.savedDecisions.single.keepState, KeepState.keep);
    expect(repository.loadedIds.last, 'p2');
    expect(find.byKey(const ValueKey('photo-previous-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('photo-next-button')), findsNothing);
  });

  for (final width in const [360.0, 390.0, 426.0]) {
    for (final textScale in const [1.0, 1.3, 1.5]) {
      testWidgets('${width.toInt()}dp 与 ${textScale}x 字体下箭头保持边缘布局且不遮挡中央识别框', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = _ReviewRepository();
        await tester.pumpWidget(
          _app(
            repository,
            const PhotoDetailPage(
              fileId: 'p2',
              displayIndex: 2,
              totalCount: 3,
              sequence: ['p1', 'p2', 'p3'],
            ),
            textScale: textScale,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final preview = tester.getRect(find.byType(SubjectOverlayView));
        final previous = tester.getRect(find.byKey(const ValueKey('photo-previous-button')));
        final next = tester.getRect(find.byKey(const ValueKey('photo-next-button')));
        final subject = tester.getRect(find.byKey(const ValueKey('subject-box-0')));
        expect(previous.size, const Size(52, 52));
        expect(next.size, const Size(52, 52));
        expect(preview.contains(previous.center), isTrue);
        expect(preview.contains(next.center), isTrue);
        expect(previous.center.dx, lessThan(preview.left + 40));
        expect(next.center.dx, greaterThan(preview.right - 40));
        expect(previous.overlaps(subject), isFalse);
        expect(next.overlaps(subject), isFalse);
      });
    }
  }
}

Widget _app(
  _ReviewRepository repository,
  Widget home, {
  bool autoAdvance = false,
  double textScale = 1,
}) => BirdCompanionScope(
  dependencies: _TestDependencies(repository, autoAdvance: autoAdvance),
  child: MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: home,
  ),
);

class _TestDependencies implements BirdCompanionDependencies {
  _TestDependencies(this.reviewRepository, {required bool autoAdvance}) : settingsStore = _MemorySettingsStore(autoAdvance);

  @override
  final ReviewRepository reviewRepository;

  @override
  final SettingsStore settingsStore;

  @override
  final SessionRefreshCoordinator refreshCoordinator = SessionRefreshCoordinator();

  @override
  final AppDataChangeBus dataChangeBus = AppDataChangeBus();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemorySettingsStore implements SettingsStore {
  const _MemorySettingsStore(this.autoAdvance);

  final bool autoAdvance;

  @override
  BirdSettingsSnapshot read() => BirdSettingsSnapshot(autoAdvance: autoAdvance);

  @override
  Future<void> write(BirdSettingsSnapshot snapshot) async {}
}

class _ReviewRepository implements ReviewRepository {
  final List<String> loadedIds = [];
  final List<UserDecision> savedDecisions = [];

  @override
  Future<ReviewDetail> detail(String fileId) async {
    loadedIds.add(fileId);
    return ReviewDetail(
      photo: PhotoDetail(
        summary: PhotoSummary(
          id: fileId,
          filename: '$fileId.jpg',
          format: 'JPEG',
          preview: const PreviewRef(),
          analysisState: AnalysisState.completed,
        ),
        subjects: const [
          SubjectBox(x: .35, y: .25, width: .30, height: .50),
        ],
      ),
    );
  }

  @override
  Future<List<BirdGroup>> groups(String batchId, {String? sceneId}) async => const [];

  @override
  Future<ReviewSaveResult> save(UserDecision value, {String? projectId}) async {
    savedDecisions.add(value);
    return const ReviewSaveResult();
  }
}
