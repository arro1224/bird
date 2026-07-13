import 'package:aves/bird_companion/features/jobs/domain/job_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('任务失败项映射可重试状态', () {
    final failure = JobFailure.fromJson(const {'file_id': 'p-1', 'error_code': 'TIMEOUT', 'reason': '超时', 'retryable': true});
    expect(failure.fileId, 'p-1');
    expect(failure.retryable, isTrue);
  });
}
