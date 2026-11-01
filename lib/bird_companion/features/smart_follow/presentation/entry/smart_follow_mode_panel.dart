import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_entry_decision.dart';
import 'package:flutter/material.dart';

/// Mode selection is intentionally separate from RC3 scope and task creation.
class SmartFollowModePanel extends StatelessWidget {
  const SmartFollowModePanel({
    super.key,
    required this.decision,
    required this.followSelected,
    required this.onModeChanged,
    required this.onOpenSession,
    this.recognitionEntry = false,
    this.onOpenRecognition,
    this.configuration,
  });

  final SmartFollowEntryDecision decision;
  final bool followSelected;
  final ValueChanged<bool> onModeChanged;
  final ValueChanged<String> onOpenSession;
  final bool recognitionEntry;
  final VoidCallback? onOpenRecognition;
  final Widget? configuration;

  @override
  Widget build(BuildContext context) {
    final session = decision.session;
    return Card(
      key: const Key('smart-follow-mode-panel'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('复制方式', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            if (decision.notice != null) Text(decision.notice!),
            if (decision.phase == RecognitionEntryPhase.running) const Text('识别中·仅复制当前结果：后续新识别出的照片不会加入普通复制任务。'),
            if (decision.phase == RecognitionEntryPhase.completed) const Text('本轮识别已完成，普通复制将冻结当前已识别结果。'),
            if (decision.phase == RecognitionEntryPhase.interrupted) const Text('识别已失败或中断。可以复制当前已完成结果，或先返回识别任务处理。'),
            if (session != null)
              FilledButton.icon(
                key: const Key('smart-follow-open-existing'),
                onPressed: () => onOpenSession(session.sessionId),
                icon: const Icon(Icons.sync),
                label: Text(session.isFinished ? '查看跟随结果' : '查看已有跟随任务'),
              ),
            if (decision.canChooseFollow)
              ListTile(
                key: const Key('smart-follow-select-mode'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(followSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                title: Text(decision.followLabel),
                trailing: decision.phase == RecognitionEntryPhase.running ? const Chip(label: Text('推荐')) : null,
                subtitle: Text(decision.phase == RecognitionEntryPhase.running ? '推荐：持续跟随本轮识别，后续符合条件的照片也会复制。' : '开始新一轮识别，并持续复制本轮符合条件的照片。'),
                onTap: () => onModeChanged(true),
              ),
            if (!decision.capabilities.canShowEntry) const Text('当前盒子版本暂不支持边识别边复制。'),
            ListTile(
              key: const Key('smart-follow-select-snapshot'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(!followSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked),
              title: Text(recognitionEntry ? (decision.job == null ? '仅识别照片' : '查看本轮识别') : decision.snapshotLabel),
              subtitle: Text(recognitionEntry ? '不创建跟随复制任务。' : '按预检确认的固定集合复制，不自动追加后续结果。'),
              onTap: () => onModeChanged(false),
            ),
            if (decision.phase == RecognitionEntryPhase.interrupted && onOpenRecognition != null) TextButton(onPressed: onOpenRecognition, child: const Text('查看识别任务')),
            if (followSelected && decision.canChooseFollow) ...[
              const Divider(),
              const Text('请确认跟随范围', style: TextStyle(fontWeight: FontWeight.bold)),
              if (decision.job != null) Text('识别任务：${decision.job!.id}'),
              const Text('仅复制本轮已可靠提交、已识别为鸟种的照片。后续本轮符合条件的结果也会加入；不会改变普通复制任务的清单。'),
              const SizedBox(height: 8),
              if (configuration != null)
                configuration!
              else ...[
                const Text('开始前还需选择目标设备，并确认文件类型、同名处理和信息保存策略。'),
                // SF-B2 supplies validated configuration; SF-B3 owns submission.
                // An incomplete configuration must never reach either create API.
                FilledButton(
                  key: const Key('smart-follow-start-unconfigured'),
                  onPressed: null,
                  child: Text(decision.followLabel),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
