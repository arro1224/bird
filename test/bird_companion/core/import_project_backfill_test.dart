import 'dart:io';

import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/mock_box_server/mock_box_server.dart';

/// 回归：导入任务完成后必须把项目 `total_files` 回填成实际照片数。
///
/// App 的任务首页用 `currentProject.totalFiles > 0` 门控「AI 分析 / 复制照片」，
/// 一旦回填缺失，界面上就表现为「正在同步批次照片状态」和
/// 「当前批次没有可处理照片」——2026-11-18 真机复现。
void main() {
  late MockBoxServer server;
  late ApiClient client;

  setUp(() async {
    server = MockBoxServer(
      photoCount: 60,
      assetDirectory: Directory('tool/mock_box_server/assets'),
      logRequests: false,
    );
    final baseUri = await server.start();
    client = ApiClient()..configure(baseUri);
  });

  tearDown(() async {
    await client.dispose();
    await server.close();
  });

  test('导入完成回填 total_files，current 批次门控可通过', () async {
    final project = await client.post(
      '/api/v1/projects',
      data: const {
        'name': '2026.11.18 拍摄批次',
        'card_id': 'card-mock-001',
      },
    );
    final projectId = project['project_id'].toString();
    expect(project['total_files'], 0);

    final importJob = await client.post(
      '/api/v1/projects/$projectId/imports',
      data: const {'source': 'card', 'read_only': true},
    );
    await server.completeJob(importJob['job_id'].toString());

    final current = await client.get('/api/v1/projects/current');
    final batch = Map<String, dynamic>.from(current['batch'] as Map);
    expect(batch['project_id'], projectId);
    expect(batch['total_files'], 60, reason: '导入完成后必须回填为实际照片数');
    expect(batch['state'], 'ready_to_review');
  });

  test('分析完成回填审阅计数，批量保留后计数随之变化', () async {
    final project = await client.post(
      '/api/v1/projects',
      data: const {
        'name': '2026.11.18 拍摄批次',
        'card_id': 'card-mock-001',
      },
    );
    final projectId = project['project_id'].toString();
    final importJob = await client.post(
      '/api/v1/projects/$projectId/imports',
      data: const {'source': 'card', 'read_only': true},
    );
    await server.completeJob(importJob['job_id'].toString());
    final analysisJob = await client.post(
      '/api/v1/projects/$projectId/analysis-jobs',
      data: const {'mode': 'standard'},
    );
    await server.completeJob(analysisJob['job_id'].toString());

    var batch = Map<String, dynamic>.from((await client.get('/api/v1/projects/current'))['batch'] as Map);
    // Mock 的 60 张里刻意包含少量「未能完成识别」的照片，因此已识别数不要求等于 60；
    // 但三种审阅状态的合计必须覆盖整批。
    expect(batch['analyzed_count'], greaterThan(0), reason: '分析完成后必须回填已识别张数');
    expect(
      (batch['pending_review_count'] as int) + (batch['keep_count'] as int) + (batch['discard_count'] as int),
      60,
      reason: '审阅计数合计必须等于批次照片数',
    );

    final ids = [for (var i = 1; i <= 60; i++) 'photo-${i.toString().padLeft(4, '0')}'];
    await client.post(
      '/api/v1/projects/$projectId/files/actions',
      data: {
        'file_ids': ids,
        'operation': 'discard',
        'version': batch['version'],
      },
    );

    batch = Map<String, dynamic>.from((await client.get('/api/v1/projects/current'))['batch'] as Map);
    expect(batch['discard_count'], 60, reason: '全量弃选后已弃选计数应等于批次照片数');
    expect(batch['pending_review_count'], 0);
    expect(batch['keep_count'], 0);
  });
}
