import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:dio/dio.dart';

class UserMessage {
  const UserMessage({required this.title, required this.message, this.actionLabel});

  final String title;
  final String message;
  final String? actionLabel;
}

abstract final class UserMessageMapper {
  static UserMessage fromJobFailure({
    String? code,
    String? message,
  }) {
    final mapped = fromError(
      ApiException(
        message: message ?? '',
        code: code,
      ),
    );
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
            return const UserMessage(title: '无法验证盒子身份', message: '盒子的安全证书无效，请确认设备可信后重试。');
          case DioExceptionType.cancel:
            return const UserMessage(title: '连接已取消', message: '本次连接没有完成，您可以重新连接。', actionLabel: '重新连接');
          case DioExceptionType.badResponse:
            break;
        }
      }
      return switch (error.code) {
        'card_not_inserted' => const UserMessage(title: '未插入存储卡', message: '请插入存储卡后重试，或查看过去拍摄的照片。'),
        'card_read_failed' => const UserMessage(title: '存储卡读取失败', message: '请重新插卡或检查存储卡格式。', actionLabel: '重试'),
        'storage_insufficient' => const UserMessage(title: '目标空间不足', message: '请更换目标盘或减少复制范围。'),
        'device_overheated' => const UserMessage(title: '盒子温度较高', message: '请等待降温，必要时暂停当前任务。'),
        'battery_low' => const UserMessage(title: '电量不足', message: '请连接电源后再继续执行高负载任务。'),
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
    return const UserMessage(title: '操作未完成', message: '请检查与盒子的连接后重试。', actionLabel: '重试');
  }
}
