import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('strict error parser keeps code, retry and retry-after semantics', () {
    final error = ProvisioningException.fromJson({'code': 'NETWORK_OPERATION_BUSY', 'message': 'busy', 'retryable': true, 'retry_after_ms': 2000});

    expect(error.code, ProvisioningErrorCode.networkOperationBusy);
    expect(error.code.origin, ProvisioningErrorOrigin.box);
    expect(error.retryable, isTrue);
    expect(error.retryAfter, const Duration(seconds: 2));
    expect(error.toString(), isNot(contains('busy')));
  });

  test('unknown error code is rejected instead of guessed', () {
    expect(
      () => ProvisioningException.fromJson({'code': 'SOMETHING_NEW', 'message': 'raw', 'retryable': false, 'retry_after_ms': 0}),
      throwsA(isA<ProvisioningProtocolException>()),
    );
  });

  test('App-local errors are separated from box errors', () {
    expect(ProvisioningErrorCode.deviceIdMismatch.origin, ProvisioningErrorOrigin.app);
    expect(ProvisioningErrorCode.bleFragmentInvalid.origin, ProvisioningErrorOrigin.protocol);
  });
}
