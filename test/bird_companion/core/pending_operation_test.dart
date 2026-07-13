import 'package:aves/bird_companion/core/sync/pending_operation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('待同步操作会保留版本、状态和失败原因', () {
    final operation = PendingOperation(id: 'test', type: PendingOperationType.updateReview, payload: const {'file_id': 'p1'}, createdAt: DateTime.utc(2026), version: 2, status: PendingOperationStatus.failed, failureReason: 'timeout');
    final restored = PendingOperation.fromJson(operation.toJson());
    expect(restored.version, 2);
    expect(restored.status, PendingOperationStatus.failed);
    expect(restored.failureReason, 'timeout');
  });
}
