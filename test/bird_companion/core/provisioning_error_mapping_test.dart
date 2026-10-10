import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Bluetooth unavailable is a recoverable phone error with a Bluetooth action', () {
    const code = ProvisioningErrorCode.bluetoothUnavailable;
    final message = UserMessageMapper.fromError(const ProvisioningException(code: code, retryable: true));
    expect(code.origin, ProvisioningErrorOrigin.app);
    expect(ProvisioningErrorCodeWireValue.parse(code.wireValue), code);
    expect(message.title, '手机蓝牙未开启或不可用');
    expect(message.message, contains('开启蓝牙'));
    expect(message.message, isNot(contains('位置')));
    expect(message.actionLabel, '重新搜索');
  });
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
    expect(message.message, contains('开启系统位置服务'));
    expect(message.message, contains('App 不读取或上传您的位置'));
    expect(message.actionLabel, '去开启位置信息');
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
      ProvisioningErrorCode.blePairingTimeout: '系统蓝牙绑定未在规定时间内完成，请确认系统配对提示后重试。',
      ProvisioningErrorCode.blePairingRejected: '安全连接未完成，请重新配对。',
      ProvisioningErrorCode.bleGattOperationFailed: '手机与盒子的蓝牙通信中断，请重新连接后重试。',
      ProvisioningErrorCode.bleGattRecoveryFailed: '安全连接已建立，但重新连接盒子失败。',
      ProvisioningErrorCode.bleSecurityRecoveryFailed: '手机已尝试恢复安全连接，但流程未能完成。',
      ProvisioningErrorCode.bleEncryptedRetryFailed: '系统绑定已完成，但加密写入重试失败，请重新连接后重试。',
      ProvisioningErrorCode.bleBondStartFailed: '手机未能发起系统蓝牙配对，请检查蓝牙状态后重试。',
      ProvisioningErrorCode.bleBondLost: '手机与盒子的蓝牙绑定已丢失，请重新连接并完成系统配对。',
      ProvisioningErrorCode.bleBondStateUnknown: '手机未能确认蓝牙绑定状态，请检查蓝牙及附近设备权限后重试。',
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
