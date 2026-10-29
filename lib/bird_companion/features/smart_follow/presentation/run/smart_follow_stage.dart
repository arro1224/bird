import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_metadata.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';

/// 运行页阶段（App 修改任务书 §6 的九条文案，另加"已暂停"）。
///
/// 单独抽成纯函数的好处：文案与判定顺序可以被单测钉住，运行页/任务卡片/
/// 完成页共用同一套判定，不会出现"三个地方三种说法"。
enum SmartFollowStageTone { running, waiting, success, partial, failure }

class SmartFollowStage {
  const SmartFollowStage({
    required this.id,
    required this.label,
    required this.hint,
    required this.tone,
  });

  final String id;
  final String label;

  /// 副标题：只说"现在发生什么/用户该做什么"，不重复数字。
  final String hint;
  final SmartFollowStageTone tone;

  bool get isWaiting => tone == SmartFollowStageTone.waiting;

  @override
  String toString() => 'SmartFollowStage($id, $label)';
}

/// 判定顺序（改顺序前先看测试）：信息更新运行中 > 会话自身状态 > 识别是否还在跑。
///
/// [recognitionRunning] 来自识别任务（`BirdJobStatus.state`），因为会话在
/// `following` 时无法只靠计数区分"识别还在跑但暂时没新结果"和"识别已经结束"。
SmartFollowStage resolveSmartFollowStage({
  required SmartFollowSession session,
  SmartFollowMetadataUpdate? metadataUpdate,
  bool recognitionRunning = true,
}) {
  final activeUpdate = metadataUpdate;
  if (activeUpdate != null && !activeUpdate.isTerminal) {
    return const SmartFollowStage(
      id: 'updating_metadata',
      label: '正在统一保存信息',
      hint: '正在按原复制批次更新副本的识别与审阅信息，不会重新复制照片。',
      tone: SmartFollowStageTone.running,
    );
  }

  switch (session.state.wire) {
    case 'waiting_for_target':
      return const SmartFollowStage(
        id: 'waiting_target',
        label: '等待目标盘',
        hint: '识别仍在继续，队列已保留。请插回原来的目标盘；插错盘不会自动切换。',
        tone: SmartFollowStageTone.waiting,
      );
    case 'waiting_for_source':
      return const SmartFollowStage(
        id: 'waiting_source',
        label: '等待源卡',
        hint: '复制还需要原相机卡，请插回同一张卡；已复制的照片不受影响。',
        tone: SmartFollowStageTone.waiting,
      );
    case 'failed':
      return SmartFollowStage(
        id: 'failed',
        label: '失败／需要处理',
        hint: session.errorMessage?.trim().isNotEmpty == true ? session.errorMessage!.trim() : '盒子遇到了不能自动恢复的问题，请查看详情后再操作。',
        tone: SmartFollowStageTone.failure,
      );
    case 'completed':
      return SmartFollowStage(
        id: 'completed',
        label: '已完成',
        hint: session.metadataUpdateAvailable ? '照片已全部处理完；识别信息有新变化，可选择更新。' : '识别结果已全部处理完。',
        tone: SmartFollowStageTone.success,
      );
    case 'completed_partial':
      return SmartFollowStage(
        id: 'completed_partial',
        label: '部分完成',
        hint: session.failedAssetCount > 0 ? '有 ${session.failedAssetCount} 张照片没能复制，其余已完成。' : '已按你的要求结束跟随，后续识别结果不会再复制。',
        tone: SmartFollowStageTone.partial,
      );
    case 'paused':
      return const SmartFollowStage(
        id: 'paused',
        label: '已暂停',
        hint: '识别结果仍会记录下来，但暂时不会创建新的复制批次。',
        tone: SmartFollowStageTone.waiting,
      );
    case 'draining':
      return const SmartFollowStage(
        id: 'draining',
        label: '识别结束·正在完成剩余复制',
        hint: '不会再接收新的识别结果，正在把已识别的照片复制完。',
        tone: SmartFollowStageTone.running,
      );
    case 'created':
      return const SmartFollowStage(
        id: 'created',
        label: '识别与复制中',
        hint: '跟随任务已创建，正在等第一张已识别照片进入复制。',
        tone: SmartFollowStageTone.running,
      );
    case 'following':
      if (!recognitionRunning) {
        return const SmartFollowStage(
          id: 'following_recognition_done',
          label: '识别结束·正在完成剩余复制',
          hint: '识别已经结束，正在排空剩余队列。',
          tone: SmartFollowStageTone.running,
        );
      }
      // 复制快于识别：没有待复制、已分配的也都收敛了 → 等新结果，不提前完成。
      if (session.pendingCount == 0 && session.assignedCount <= session.copiedAssetCount + session.failedAssetCount) {
        return SmartFollowStage(
          id: 'waiting_new_results',
          label: '等待新的识别结果',
          hint: session.copiedAssetCount > 0 ? '已复制 ${session.copiedAssetCount} 张，识别出新照片后会继续复制。' : '已识别 ${session.eligibleCount} 张，识别出新照片后会继续复制。',
          tone: SmartFollowStageTone.running,
        );
      }
      return const SmartFollowStage(
        id: 'following',
        label: '识别与复制中',
        hint: '识别与复制同时进行；退出 App 不会停止盒子上的任务。',
        tone: SmartFollowStageTone.running,
      );
    default:
      // 未冻结的值原样显示，不猜语义（分工任务书 §6 硬规则）。
      return SmartFollowStage(
        id: 'unknown',
        label: session.state.label,
        hint: '盒子返回了当前版本还不认识的状态，请刷新或查看诊断信息。',
        tone: SmartFollowStageTone.waiting,
      );
  }
}
