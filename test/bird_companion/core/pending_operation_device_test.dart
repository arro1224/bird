import 'package:aves/bird_companion/core/sync/pending_operation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('待同步操作序列化时保留来源设备', () {
    final operation = PendingOperation(
      id: 'review-1',
      type: PendingOperationType.updateReview,
      payload: const {'file_id': 'photo-1'},
      createdAt: DateTime.utc(2026, 7, 22),
      deviceId: 'box-a',
    );

    final restored = PendingOperation.fromJson(operation.toJson());
    expect(restored.deviceId, 'box-a');
    expect(restored.copyWith(status: PendingOperationStatus.failed).deviceId, 'box-a');
  });

  test('旧记录没有设备标识时保持为空，不能被当作当前设备记录', () {
    final restored = PendingOperation.fromJson({
      'id': 'legacy',
      'type': 'updateReview',
      'payload': const {'file_id': 'photo-1'},
      'created_at': DateTime.utc(2026, 7, 22).toIso8601String(),
    });

    expect(restored.deviceId, isNull);
  });
}
