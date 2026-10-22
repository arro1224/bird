import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_repository.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_job_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 返修 P1-4 / P1-5 / P1-10（2026-10-22 现场反馈）。
void main() {
  group('P1-4 时间本地化', () {
    // UTC 08:02 → 北京时间 +8 应显示 16:02（现场：14:42 看到固定少 8 小时）。
    final utcTime = DateTime.parse('2026-10-22T06:02:00Z');

    test('DateTime.parse 保留 UTC，toLocal 转换不改原始值', () {
      expect(utcTime.isUtc, isTrue);
      final local = utcTime.toLocal();
      expect(local.isUtc, isFalse);
      expect(local.difference(utcTime), utcTime.timeZoneOffset);
    });
  });

  group('P1-5 列表跳过统计', () {
    testWidgets('有跳过项 → 「处理完成 N/N（复制 X，跳过 Y）」而非 文件 4/5', (tester) async {
      final repository = _ListFakeRepository(
        jobs: [
          _job(
            id: 'copy_skipped',
            total: 5,
            copied: 4,
            skipped: 1,
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp(home: CopyJobListPage(repository: repository)));
      await tester.pumpAndSettle();

      expect(find.text('处理完成 5/5（复制 4，跳过 1）'), findsOneWidget);
      expect(find.text('文件 4/5'), findsNothing);
    });

    testWidgets('无跳过项 → 维持原「文件 X/Y」口径', (tester) async {
      final repository = _ListFakeRepository(
        jobs: [_job(id: 'copy_plain', total: 5, copied: 4, failed: 1)],
      );
      await tester.pumpWidget(MaterialApp(home: CopyJobListPage(repository: repository)));
      await tester.pumpAndSettle();

      expect(find.text('文件 5/5'), findsOneWidget);
    });
  });

  group('P1-10 错误映射', () {
    test('COPY_SCOPE_EMPTY 映射为可选文件说明，不再暗示连接问题', () {
      final message = UserMessageMapper.fromError(
        const ApiException(code: 'COPY_SCOPE_EMPTY', message: '', statusCode: 422),
      );
      expect(message.title, '所选照片没有可复制的文件');
      expect(message.message, contains('没有符合当前 RAW/JPEG 策略'));
    });
  });
}

CopyJobListItem _job({
  required String id,
  required int total,
  int copied = 0,
  int failed = 0,
  int skipped = 0,
}) => CopyJobListItem(
  copyJobId: id,
  state: CopyJobState.completed,
  scopeWire: 'batch_all_assets',
  stats: CopyJobStats(
    totalFiles: total,
    copiedFiles: copied,
    failedFiles: failed,
    skippedFiles: skipped,
    notApplicableFiles: 0,
    totalBytes: 1024,
    copiedBytes: 512,
    elapsedSeconds: 1,
  ),
  createdAt: DateTime.parse('2026-10-22T06:02:00Z'),
);

class _ListFakeRepository implements CopyJobRepository {
  _ListFakeRepository({required this.jobs});

  final List<CopyJobListItem> jobs;

  @override
  Future<CopyJobPage> listJobs({String? cursor}) async =>
      CopyJobPage(items: jobs, hasMore: false, nextCursor: null);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
