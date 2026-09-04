import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:dio/dio.dart';

class UserMessage {
  const UserMessage({
    required this.title,
    required this.message,
    this.actionLabel,
  });

  final String title;
  final String message;
  final String? actionLabel;
}

abstract final class UserMessageMapper {
  static UserMessage fromStorageFailure({String? code, String? message}) => fromError(ApiException(message: message ?? '', code: code));

  static UserMessage fromJobFailure({String? code, String? message}) {
    final mapped = fromError(ApiException(message: message ?? '', code: code));
    if (code != null && mapped.title != '操作未完成') return mapped;
    final normalized = message?.trim();
    final containsInternalDetail = normalized == null || normalized.isEmpty || normalized.contains(RegExp(r'[/\\]')) || normalized.contains('Exception') || normalized.contains('http://') || normalized.contains('https://');
    return containsInternalDetail
        ? const UserMessage(
            title: '任务处理失败',
            message: '盒子未能处理部分文件，请查看失败项并选择重试或跳过。',
            actionLabel: '查看失败项',
          )
        : UserMessage(
            title: '任务处理失败',
            message: normalized,
            actionLabel: '查看失败项',
          );
  }

  static UserMessage fromError(Object error) {
    if (error is ProvisioningException) return fromProvisioningError(error);
    if (error is SignedAssetDownloadException) {
      return error.isExpired
          ? const UserMessage(
              title: '日志下载授权已过期',
              message: '正在使用当前设备会话重新申请下载地址；如果仍然失败，请重新配对设备。',
              actionLabel: '重新授权',
            )
          : const UserMessage(
              title: '日志下载失败',
              message: '盒子没有返回可用的诊断文件，请检查连接后重新导出。',
              actionLabel: '重新导出',
            );
    }
    if (error is ProtocolCompatibilityException) {
      return const UserMessage(
        title: '盒子版本不兼容',
        message: '盒子返回的数据不符合当前协议，请升级盒子服务或联系维护人员。',
        actionLabel: '重新连接',
      );
    }
    if (error is ApiException) {
      final cause = error.cause;
      if (cause is DioException) {
        switch (cause.type) {
          case DioExceptionType.connectionTimeout:
          case DioExceptionType.sendTimeout:
          case DioExceptionType.receiveTimeout:
          case DioExceptionType.transformTimeout:
            return const UserMessage(
              title: '连接超时',
              message: '盒子未及时响应。请确认盒子服务已启动、手机与盒子网络可达后重试。',
              actionLabel: '重新连接',
            );
          case DioExceptionType.connectionError:
          case DioExceptionType.unknown:
            return const UserMessage(
              title: '无法连接盒子',
              message: '请检查盒子地址、网络连接和盒子服务状态后重试。',
              actionLabel: '重新连接',
            );
          case DioExceptionType.badCertificate:
            return const UserMessage(
              title: '无法验证盒子身份',
              message: '盒子的安全证书无效，请确认设备可信后重试。',
            );
          case DioExceptionType.cancel:
            return const UserMessage(
              title: '连接已取消',
              message: '本次连接没有完成，您可以重新连接。',
              actionLabel: '重新连接',
            );
          case DioExceptionType.badResponse:
            break;
        }
      }
      return switch (error.code) {
        'card_not_inserted' => const UserMessage(
          title: '未插入存储卡',
          message: '请插入存储卡后重试，或查看过去拍摄的照片。',
        ),
        'card_read_failed' => const UserMessage(
          title: '存储卡读取失败',
          message: '请重新插卡或检查存储卡格式。',
          actionLabel: '重试',
        ),
        'storage_insufficient' => const UserMessage(
          title: '目标空间不足',
          message: '请更换目标盘或减少复制范围。',
        ),
        'device_overheated' => const UserMessage(
          title: '盒子温度较高',
          message: '请等待降温，必要时暂停当前任务。',
        ),
        'battery_low' => const UserMessage(
          title: '电量不足',
          message: '请连接电源后再继续执行高负载任务。',
        ),
        'job_version_conflict' => const UserMessage(
          title: '任务状态已更新',
          message: '盒子中的任务状态已经变化，请重新加载后再操作。',
          actionLabel: '重新加载',
        ),
        'job_action_unavailable' => const UserMessage(
          title: '当前操作不可用',
          message: '任务状态或设备条件已经变化，请查看盒子返回的最新可用操作。',
          actionLabel: '重新加载',
        ),
        'decision_version_conflict' => const UserMessage(
          title: '照片审阅结果已更新',
          message: '盒子中保存的是更新版本，请重新读取并人工选择要保留的结果。',
          actionLabel: '重新读取',
        ),
        'decision_version_required' => const UserMessage(
          title: '无法安全保存审阅结果',
          message: '照片缺少版本信息，请重新读取照片详情后再保存。',
          actionLabel: '重新读取',
        ),
        _ when error.statusCode == 404 => const UserMessage(
          title: '照片详情不可用',
          message: '盒子没有提供这张照片的详情。照片可能已被删除，或当前盒子服务版本不支持详情接口。',
          actionLabel: '重试',
        ),
        _ when error.statusCode == 409 => const UserMessage(
          title: '任务或照片状态已更新',
          message: '请重新加载盒子中的最新结果，再决定是否重新应用本次操作。',
          actionLabel: '重新加载',
        ),
        _ when error.statusCode == 422 => const UserMessage(
          title: '当前操作不可用',
          message: '任务状态或设备条件不允许执行本次操作，请刷新后查看可用操作。',
          actionLabel: '重新加载',
        ),
        _ when error.statusCode != null && error.statusCode! >= 500 => const UserMessage(
          title: '盒子服务暂不可用',
          message: '盒子暂时无法完成本次操作，请稍后重试。',
          actionLabel: '重试',
        ),
        _ => UserMessage(
          title: error.statusCode == 401 || error.statusCode == 403 ? '盒子拒绝连接' : '操作未完成',
          message: error.statusCode == 401 || error.statusCode == 403 ? '当前设备尚未完成配对或授权，请重新配对后连接。' : '盒子没有完成本次请求，请检查连接后重试。',
          actionLabel: '重试',
        ),
      };
    }
    return const UserMessage(
      title: '操作未完成',
      message: '请检查与盒子的连接后重试。',
      actionLabel: '重试',
    );
  }

  /// Maps the rc4 protocol error code only. Raw box diagnostics can contain
  /// pairing credentials, passwords or tokens and must never reach the UI.
  static UserMessage fromProvisioningError(ProvisioningException error) {
    switch (error.code) {
      case ProvisioningErrorCode.userCancelledDppDialog:
      case ProvisioningErrorCode.userCancelledWifiDialog:
        return const UserMessage(
          title: '已取消连接',
          message: '本次系统连接操作已取消，盒子未更改网络设置。',
          actionLabel: '继续配网',
        );
      case ProvisioningErrorCode.bluetoothPermissionDenied:
        return const UserMessage(
          title: '需要蓝牙权限',
          message: '请在系统设置中允许蓝牙和附近设备权限，然后返回继续。',
          actionLabel: '前往设置',
        );
      case ProvisioningErrorCode.localNetworkPermissionDenied:
        return const UserMessage(
          title: '需要本地网络权限',
          message: '请在系统设置中允许本地网络访问，然后返回继续。',
          actionLabel: '前往设置',
        );
      case ProvisioningErrorCode.systemWifiJoinDenied:
        return const UserMessage(
          title: '系统未允许加入网络',
          message: '请在系统提示中允许连接，或检查 Wi-Fi 设置后重试。',
          actionLabel: '重新检查',
        );
      case ProvisioningErrorCode.phoneDppNotSupported:
      case ProvisioningErrorCode.systemDppActivityUnavailable:
      case ProvisioningErrorCode.systemDppInvalidUri:
        return const UserMessage(
          title: '手机暂不支持此连接方式',
          message: '请返回后选择其他连接方式。',
          actionLabel: '返回上一步',
        );
      case ProvisioningErrorCode.wifiScanFailed:
        return const UserMessage(
          title: '未能搜索 Wi-Fi',
          message: '盒子暂时没有完成 Wi-Fi 搜索，请稍后重试。',
          actionLabel: '重试',
        );
      case ProvisioningErrorCode.networkRecoveryFailed:
        return const UserMessage(
          title: '网络恢复失败',
          message: '盒子未能恢复之前的 Wi-Fi，也未能重新开启直连热点。蓝牙连接会保留，请重新为盒子配网。',
          actionLabel: '重新配网',
        );
      case ProvisioningErrorCode.pairingCodeInvalid:
        return const UserMessage(
          title: '配对码不正确',
          message: '请确认盒子屏幕上的配对码后重新输入。',
          actionLabel: '重新输入',
        );
      case ProvisioningErrorCode.pairingCodeExpired:
      case ProvisioningErrorCode.pairingSessionExpired:
        return const UserMessage(
          title: '配对已过期',
          message: '请重新获取盒子屏幕上显示的配对码。',
          actionLabel: '重新获取',
        );
      case ProvisioningErrorCode.pairingRateLimited:
        return const UserMessage(
          title: '尝试次数过多',
          message: '请稍候再输入配对码。',
          actionLabel: '稍后重试',
        );
      default:
        final action = error.retryable ? '重试' : '返回上一步';
        final title = error.code.origin == ProvisioningErrorOrigin.app ? '手机连接未完成' : '盒子连接未完成';
        final message = error.retryable ? '请检查蓝牙和设备状态后重试。' : '当前操作无法继续，请返回上一步后重新选择。';
        return UserMessage(title: title, message: message, actionLabel: action);
    }
  }
}
