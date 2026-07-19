import 'dart:convert';
import 'dart:io';

import 'package:aves/bird_companion/core/network/api_endpoints.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OpenAPI 覆盖 App 当前使用的所有 HTTP 路径', () {
    final contract = File('contracts/openapi/bird_box_v1.yaml').readAsStringSync();
    const paths = [
      ApiEndpoints.deviceStatus,
      ApiEndpoints.batches,
      ApiEndpoints.currentBatch,
      ApiEndpoints.batchResume,
      ApiEndpoints.photos,
      ApiEndpoints.batchPhotoOperation,
      ApiEndpoints.groups,
      ApiEndpoints.scenes,
      ApiEndpoints.speciesSearch,
      ApiEndpoints.photoDetail,
      ApiEndpoints.photoDecision,
      ApiEndpoints.photoHistory,
      ApiEndpoints.copyEstimate,
      ApiEndpoints.copyCreate,
      ApiEndpoints.jobs,
      ApiEndpoints.jobDetail,
      ApiEndpoints.jobFailures,
      ApiEndpoints.taskControl,
      ApiEndpoints.logExport,
      ApiEndpoints.events,
    ];
    for (final path in paths) {
      expect(contract, contains(path), reason: '契约缺少 $path');
    }
    expect(contract, contains('xmp_enabled'));
    expect(contract, contains('remove_tags'));
    expect(contract, contains('low_confidence'));
    expect(contract, contains('clarity_state'));
    expect(contract, contains('is_recommended'));
    expect(contract, contains('eye_score'));
    expect(contract, contains('BatchPage:'));
    expect(contract, contains('ReviewDetail:'));
    expect(contract, contains('UserDecision:'));
    expect(contract, contains('user_species_id'));
    expect(contract, contains('pending_review_count'));
    expect(contract, contains('thumb_ref'));
    expect(contract, contains('BatchOperationOutcome:'));
    expect(contract, contains('ErrorEnvelope:'));
  });

  test('事件 schema 是可解析 JSON 且包含关键字段', () {
    for (final path in ['contracts/events/job_event.schema.json', 'contracts/events/device_event.schema.json']) {
      final value = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
      expect(value['type'], 'object');
      expect(value['required'], containsAll(['event_type', 'payload']));
    }
  });
}
