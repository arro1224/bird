import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:dio/dio.dart';

class UserMessage {
  const UserMessage({required this.title, required this.message, this.actionLabel});

  final String title;
  final String message;
  final String? actionLabel;
}

abstract final class UserMessageMapper {
  static UserMessage fromError(Object error) {
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
        'card_not_inserted' => const UserMessage(title: '未插入存储卡', message: '请插入存储卡后重试，或查看历史批次。'),
        'card_read_failed' => const UserMessage(title: '存储卡读取失败', message: '请重新插卡或检查存储卡格式。', actionLabel: '重试'),
        'storage_insufficient' => const UserMessage(title: '目标空间不足', message: '请更换目标盘或减少复制范围。'),
        'device_overheated' => const UserMessage(title: '盒子温度较高', message: '请等待降温，必要时暂停当前任务。'),
        'battery_low' => const UserMessage(title: '电量不足', message: '请连接电源后再继续执行高负载任务。'),
        _ => UserMessage(
          title: error.statusCode == 401 || error.statusCode == 403 ? '盒子拒绝连接' : '操作未完成',
          message: error.statusCode == 401 || error.statusCode == 403 ? '当前设备尚未完成配对或授权，请重新配对后连接。' : error.message,
          actionLabel: '重试',
        ),
      };
    }
    return const UserMessage(title: '操作未完成', message: '请检查与盒子的连接后重试。', actionLabel: '重试');
  }
}
