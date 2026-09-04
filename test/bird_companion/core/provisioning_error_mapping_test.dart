import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps Bluetooth permission failures to a safe settings action', () {
    final message = UserMessageMapper.fromError(
      const ProvisioningException(
        code: ProvisioningErrorCode.bluetoothPermissionDenied,
        retryable: true,
        diagnosticMessage: 'token=top-secret; pairing_session_id=not-for-ui',
      ),
    );

    expect(message.title, '需要蓝牙权限');
    expect(message.actionLabel, '前往设置');
    expect('${message.title}${message.message}', isNot(contains('top-secret')));
    expect(
      '${message.title}${message.message}',
      isNot(contains('pairing_session_id')),
    );
  });

  test('maps a user cancellation without urging the user to retry', () {
    final message = UserMessageMapper.fromError(
      const ProvisioningException(
        code: ProvisioningErrorCode.userCancelledDppDialog,
        retryable: false,
        diagnosticMessage: 'dpp://sensitive-uri',
      ),
    );

    expect(message.title, '已取消连接');
    expect(message.actionLabel, '继续配网');
    expect('${message.title}${message.message}', isNot(contains('dpp://')));
  });

  test('maps retryable box errors without displaying the raw box message', () {
    final message = UserMessageMapper.fromError(
      const ProvisioningException(
        code: ProvisioningErrorCode.wifiScanFailed,
        retryable: true,
        diagnosticMessage: 'backend message: password=secret',
      ),
    );

    expect(message.title, '未能搜索 Wi-Fi');
    expect(message.actionLabel, '重试');
    expect(
      '${message.title}${message.message}',
      isNot(contains('password=secret')),
    );
  });

  test('maps exhausted network recovery to BLE-preserving reconfiguration', () {
    final message = UserMessageMapper.fromError(
      const ProvisioningException(
        code: ProvisioningErrorCode.networkRecoveryFailed,
        retryable: true,
      ),
    );

    expect(message.title, '网络恢复失败');
    expect(message.message, contains('蓝牙连接会保留'));
    expect(message.actionLabel, '重新配网');
  });
}
