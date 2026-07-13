import 'package:aves/bird_companion/core/network/api_exception.dart';

class UserMessage {
  const UserMessage({required this.title, required this.message, this.actionLabel});

  final String title;
  final String message;
  final String? actionLabel;
}

abstract final class UserMessageMapper {
  static UserMessage fromError(Object error) {
    if (error is ApiException) {
      return switch (error.code) {
        'card_not_inserted' => const UserMessage(title: '未插入存储卡', message: '请插入存储卡后重试，或查看历史批次。'),
        'card_read_failed' => const UserMessage(title: '存储卡读取失败', message: '请重新插卡或检查存储卡格式。', actionLabel: '重试'),
        'storage_insufficient' => const UserMessage(title: '目标空间不足', message: '请更换目标盘或减少复制范围。'),
        'device_overheated' => const UserMessage(title: '盒子温度较高', message: '请等待降温，必要时暂停当前任务。'),
        'battery_low' => const UserMessage(title: '电量不足', message: '请连接电源后再继续执行高负载任务。'),
        _ => UserMessage(title: '操作未完成', message: error.message, actionLabel: '重试'),
      };
    }
    return const UserMessage(title: '操作未完成', message: '请检查与盒子的连接后重试。', actionLabel: '重试');
  }
}
