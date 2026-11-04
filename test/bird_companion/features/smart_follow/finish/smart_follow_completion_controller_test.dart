import 'dart:async';

import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'completion_fixtures.dart';

void main() {
  late CompletionEnvironment env;
  setUp(() => env = CompletionEnvironment());
  tearDown(() => env.dispose());

  test('complete result uses actual copied bytes and separates photo/file counts', () async {
    await env.controller.refresh();
    final result = env.controller.result!;
    expect(result.summaryComplete, isTrue);
    expect(result.title, '跟随复制已完成');
    expect(result.sessionCount('copied_asset_count'), 1);
    expect(result.copiedFiles, 2);
    expect(result.copiedBytes, 128);
    expect(result.recognitionReport!.successCount, 3);
    expect(env.backend.reads, 2); // Includes end-of-read snapshot validation.
  });

  test('all pages are read and overlapping identical IDs counted once', () async {
    final a = CompletionBackend.child('a');
    final b = CompletionBackend.child('b');
    env.backend.data.addAll({'child_job_count': 2, 'eligible_count': 2, 'copied_asset_count': 2, 'copied_file_count': 4});
    env.backend.pages = {
      null: SmartFollowChildJobPage(items: [a], hasMore: true, nextCursor: 'next'),
      'next': SmartFollowChildJobPage(items: [a, b], hasMore: false),
    };
    await env.controller.refresh();
    expect(env.backend.cursors, [null, 'next']);
    expect(env.childReads, ['a', 'b']);
    expect(env.controller.result!.copiedFiles, 4);
    expect(env.controller.result!.copiedBytes, 256);
  });

  test('second page failure retains history but suppresses partial aggregate', () async {
    env.backend.data['child_job_count'] = 2;
    env.backend.pages[null] = SmartFollowChildJobPage(items: [CompletionBackend.child('a')], hasMore: true, nextCursor: 'next');
    env.backend.failSecondPage = true;
    await env.controller.refresh();
    final result = env.controller.result!;
    expect(result.children, hasLength(1));
    expect(result.historyComplete, isFalse);
    expect(result.copiedBytes, isNull);
    expect(result.title, contains('报告待补齐'));
  });

  test('duplicate cursor cannot be mistaken for complete history', () async {
    final page = SmartFollowChildJobPage(items: [CompletionBackend.child('a')], hasMore: true, nextCursor: 'loop');
    env.backend.pages = {null: page, 'loop': page};
    await env.controller.refresh();
    expect(env.backend.cursors, [null, 'loop']);
    expect(env.controller.result!.reportsComplete, isFalse);
  });

  test('has_more with missing cursor remains incomplete in wire parser', () async {
    final page = SmartFollowChildJobPage.fromJson({'items': [], 'has_more': true});
    expect(page.hasMore, isFalse);
    expect(page.paginationValid, isFalse);
    env.backend.pages[null] = page;
    await env.controller.refresh();
    expect(env.controller.result!.historyComplete, isFalse);
  });

  test('conflicting duplicate IDs invalidate full aggregation', () async {
    env.backend.pages[null] = SmartFollowChildJobPage(items: [CompletionBackend.child('a'), CompletionBackend.child('a', copied: 1)], hasMore: false);
    await env.controller.refresh();
    expect(env.controller.result!.historyComplete, isFalse);
  });

  test('missing has_more cannot establish final history', () async {
    env.backend.pages[null] = SmartFollowChildJobPage.fromJson({'items': []});
    await env.controller.refresh();
    expect(env.controller.result!.historyComplete, isFalse);
  });

  test('impossible copied-photo count is reported as a contradiction', () async {
    env.backend.data['copied_asset_count'] = 99;
    await env.controller.refresh();
    expect(env.controller.result!.summaryComplete, isFalse);
    expect(env.controller.result!.issues.join(), contains('照片数超过'));
  });

  test('report from another target cannot enter the summary', () async {
    env.backend.data['target_media_id'] = 'original-target';
    env.report['target_device'] = {'media_id': 'other-target'};
    await env.controller.refresh();
    expect(env.controller.result!.reportsComplete, isFalse);
  });

  for (final key in ['copied_files', 'failed_files', 'skipped_files', 'not_applicable_files']) {
    test('missing report $key is unknown, never evidence of zero', () async {
      env.report.remove(key);
      await env.controller.refresh();
      expect(env.controller.result!.summaryComplete, isFalse);
      expect(env.controller.result!.title, contains('报告待补齐'));
    });
  }

  test('missing actual bytes never falls back to planned bytes', () async {
    (env.detail['stats'] as Map).remove('copied_bytes');
    await env.controller.refresh();
    expect(env.controller.result!.copiedBytes, isNull);
    expect(env.controller.result!.summaryComplete, isFalse);
  });

  test('missing session counts do not inherit DTO default zero', () async {
    env.backend.data.remove('copied_asset_count');
    await env.controller.refresh();
    expect(env.controller.result!.session.copiedAssetCount, 0);
    expect(env.controller.result!.sessionCount('copied_asset_count'), isNull);
    expect(env.controller.result!.summaryComplete, isFalse);
  });

  test('nonterminal session skips completion reports entirely', () async {
    env.backend.data['state'] = 'draining';
    await env.controller.refresh();
    expect(env.controller.result!.title, '仍在处理');
    expect(env.backend.cursors, isEmpty);
    expect(env.childReads, isEmpty);
    expect(env.recognitionReportReads, 0);
  });

  test('terminal session with active child cannot aggregate or request its report', () async {
    env.backend.pages[null] = SmartFollowChildJobPage(items: [CompletionBackend.child('copy-1', state: 'running')], hasMore: false);
    env.detail['state'] = 'running';
    await env.controller.refresh();
    expect(env.reportReads, isEmpty);
    expect(env.controller.result!.reportsComplete, isFalse);
    expect(env.controller.result!.title, contains('报告待补齐'));
  });

  test('report not ready is retryable and never converts to success', () async {
    env.reportUnavailable = true;
    await env.controller.refresh();
    expect(env.controller.result!.copiedBytes, isNull);
    expect(env.controller.result!.children.single.issue, isNotNull);
    env.reportUnavailable = false;
    await env.controller.refresh();
    expect(env.controller.result!.summaryComplete, isTrue);
  });

  test('partial and failed authority states remain distinct', () async {
    env.backend.data['state'] = 'completed_partial';
    await env.controller.refresh();
    expect(env.controller.result!.title, '跟随复制部分完成');
    env.backend.data.addAll({'state': 'failed', 'state_version': 2, 'error_message': '目标盘已断开'});
    await env.controller.refresh();
    expect(env.controller.result!.title, '跟随复制失败');
    expect(env.controller.result!.session.errorMessage, '目标盘已断开');
  });

  test('zero eligible and explicit zero child count permit a zero-work result', () async {
    env.backend.data.addAll({'eligible_count': 0, 'copied_asset_count': 0, 'copied_file_count': 0, 'child_job_count': 0});
    env.backend.pages[null] = SmartFollowChildJobPage.empty;
    await env.controller.refresh();
    expect(env.controller.result!.summaryComplete, isTrue);
    expect(env.controller.result!.copiedBytes, 0);
    expect(env.controller.result!.informationStatus, '无复制批次');
    expect(env.reportReads, isEmpty);
  });

  test('missing child count prevents an empty page from implying zero success', () async {
    env.backend.data.remove('child_job_count');
    env.backend.pages[null] = SmartFollowChildJobPage.empty;
    await env.controller.refresh();
    expect(env.controller.result!.copiedBytes, isNull);
  });

  test('mismatched report identity is rejected', () async {
    env.wrongReport = true;
    await env.controller.refresh();
    expect(env.controller.result!.reportsComplete, isFalse);
    expect(env.controller.result!.children.single.report, isNull);
  });

  test('mismatched child identity is rejected before report read', () async {
    env.wrongChild = true;
    await env.controller.refresh();
    expect(env.controller.result!.reportsComplete, isFalse);
    expect(env.reportReads, isEmpty);
  });

  test('copy detail/report contradictions suppress report aggregate', () async {
    env.report['copied_files'] = 1;
    await env.controller.refresh();
    expect(env.controller.result!.copiedFiles, isNull);
  });

  test('session/report count contradictions suppress report aggregate', () async {
    env.backend.data['copied_file_count'] = 99;
    await env.controller.refresh();
    expect(env.controller.result!.copiedFiles, isNull);
    expect(env.controller.result!.issues.join(), contains('文件数不一致'));
  });

  test('recognition may still run after follow stops; do not fetch final report', () async {
    env.recognitionState = BirdJobState.running;
    await env.controller.refresh();
    expect(env.recognitionReportReads, 0);
    expect(env.controller.result!.recognitionReport, isNull);
    expect(env.controller.result!.recognition!.state, BirdJobState.running);
  });

  test('wrong recognition ownership cannot be used for classification', () async {
    env.wrongRecognition = true;
    await env.controller.refresh();
    expect(env.controller.result!.recognition, isNull);
    expect(env.recognitionReportReads, 0);
  });

  test('recognition report unavailable leaves file facts visible with warning', () async {
    env.recognitionReportUnavailable = true;
    await env.controller.refresh();
    expect(env.controller.result!.recognitionReport, isNull);
    expect(env.controller.result!.copiedFiles, 2);
    expect(env.controller.result!.summaryComplete, isFalse);
  });

  test('safe XMP fallback is explicit but is not a failed copy', () async {
    env.report['embed_degraded_count'] = 1;
    await env.controller.refresh();
    expect(env.controller.result!.title, '跟随复制已完成');
    expect(env.controller.result!.informationStatus, contains('配套 XMP'));
    expect(env.backend.createMetadataCalls, 0);
    expect(env.backend.actCalls, 0);
  });

  test('frozen disabled export configuration is respected', () async {
    env.detail['review_export'] = {'enabled': false};
    env.report.remove('csv_status');
    await env.controller.refresh();
    expect(env.controller.result!.informationStatus, contains('未开启'));
  });

  test('changing session during pagination discards combined results', () async {
    env.backend.changeAtEnd = true;
    await env.controller.refresh();
    expect(env.controller.result, isNull);
    expect(env.controller.error, isNotNull);
  });

  test('concurrent refreshes share a read and device reset drops late results', () async {
    env.gate = Completer<void>();
    final first = env.controller.refresh();
    final second = env.controller.refresh();
    expect(identical(first, second), isTrue);
    await Future<void>.delayed(Duration.zero);
    env.current = false;
    env.repository.resetForDeviceChange();
    env.gate!.complete();
    await first;
    expect(env.controller.result, isNull);
    expect(env.controller.error, contains('盒子连接已变化'));
    expect(env.reportReads, isEmpty);
  });
}
