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

  test('maps disabled location services to the correct system action', () {
    final message = UserMessageMapper.fromError(
      const ProvisioningException(
        code: ProvisioningErrorCode.locationServicesDisabled,
        retryable: true,
        diagnosticMessage: 'platformExceptionCode=location_service_disabled',
      ),
    );

    expect(message.title, '需要开启定位服务');
    expect(message.message, contains('开启定位服务'));
    expect(message.actionLabel, '前往设置');
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

  test('maps BLE security stages to distinct actionable messages', () {
    const expected = <ProvisioningErrorCode, String>{
      ProvisioningErrorCode.bleGattNotReady: '盒子连接尚未准备完成，请重试。',
      ProvisioningErrorCode.bleLePairingNotStarted: '手机未能启动安全连接，请关闭再打开蓝牙后重试。',
      ProvisioningErrorCode.blePairingTimeout: '配对长时间未完成，请检查系统配对界面后重试。',
      ProvisioningErrorCode.blePairingRejected: '安全连接未完成，请重新配对。',
      ProvisioningErrorCode.bleGattOperationFailed: '手机与盒子的蓝牙通信中断，请重新连接后重试。',
      ProvisioningErrorCode.bleGattRecoveryFailed: '安全连接已建立，但重新连接盒子失败。',
      ProvisioningErrorCode.bleSecurityRecoveryFailed: '手机已尝试恢复安全连接，但流程未能完成。',
      ProvisioningErrorCode.bleEncryptedRetryFailed: '安全连接已建立，但盒子未接受配对请求。',
      ProvisioningErrorCode.pairingOpenTimeout: '盒子未返回配对确认。',
    };

    for (final entry in expected.entries) {
      final message = UserMessageMapper.fromProvisioningError(
        ProvisioningException(code: entry.key, retryable: true),
      );
      expect(message.message, entry.value, reason: entry.key.wireValue);
      expect(message.actionLabel, isNotNull, reason: entry.key.wireValue);
    }
  });
}
