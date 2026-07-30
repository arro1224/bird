import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';
import 'package:aves/bird_companion/features/tasks/presentation/task_experience_controller.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_design_components.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_nature_background.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_scene_art.dart';
import 'package:flutter/material.dart';

class SdCardFlowPage extends StatelessWidget {
  const SdCardFlowPage({super.key, required this.controller, this.onContinue});

  final TaskExperienceController controller;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.paper,
    body: Stack(
      children: [
        const Positioned.fill(
          child: TaskNatureBackground(reedOpacity: .48, mountainOpacity: .7),
        ),
        SafeArea(
          bottom: false,
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => Column(
              children: [
                _header(context),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                    child: _content(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _header(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 76,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Text(
          controller.sdCard.state == SdCardReadState.detected ? '检测到 SD 卡' : '读取 SD 卡',
          style: const TextStyle(
            color: AppColors.forestDeep,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        Positioned(
          left: 0,
          child: SizedBox(
            key: const Key('sd-card-back-button'),
            width: 56,
            height: 56,
            child: IconButton(
              tooltip: '返回',
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.forestDeep),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _content(BuildContext context) => switch (controller.sdCard.state) {
    SdCardReadState.detected => _detected(context),
    SdCardReadState.missing => _missing(context),
    SdCardReadState.readFailed => _failed(context),
    SdCardReadState.empty => _empty(context),
  };

  Widget _detected(BuildContext context) => Column(
    children: [
      const TaskSdCardArt(
        key: Key('sd-card-detected-hero'),
        checked: true,
      ),
      const SizedBox(height: 8),
      const Text(
        '已检测到存储卡',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppColors.forestDeep,
          fontSize: 28,
          fontWeight: FontWeight.w800,
          height: 1.15,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        controller.sdCard.name,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.mutedInk, fontSize: 16),
      ),
      const SizedBox(height: 16),
      TaskSurface(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        radius: 18,
        child: Column(
          children: [
            _info(Icons.image_outlined, '照片数量', _count(controller.sdCard.photoCount), unit: '张'),
            _info(Icons.pie_chart_outline_rounded, '预计读取空间', _space(controller.sdCard.requiredSpaceGb), unit: 'GB'),
            _info(
              Icons.insert_drive_file_outlined,
              '文件类型',
              'RAW ${_count(controller.sdCard.rawCount)} · JPEG ${_count(controller.sdCard.jpegCount)}',
              valueSize: 15.5,
            ),
            _info(Icons.calendar_month_outlined, '拍摄日期', _date(controller.sdCard.captureDate), divider: false),
          ],
        ),
      ),
      const SizedBox(height: 14),
      _notice(Icons.eco_outlined, '建议先生成缩略图，再开始 AI 分析'),
      const SizedBox(height: 14),
      TaskPrimaryButton('开始建立批次', icon: Icons.play_arrow_rounded, onPressed: onContinue ?? () {}),
      const SizedBox(height: 12),
      TaskPrimaryButton('稍后处理', filled: false, onPressed: () => Navigator.maybePop(context)),
    ],
  );

  Widget _missing(BuildContext context) => Column(
    children: [
      const TaskSdCardArt(dimmed: true),
      const SizedBox(height: 22),
      const Text(
        '未检测到存储卡',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.forestDeep, fontSize: 31, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      const Text('请插入相机 SD 卡后重试', style: TextStyle(color: AppColors.mutedInk, fontSize: 17)),
      const SizedBox(height: 26),
      const TaskSurface(
        padding: EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Column(
          children: [
            _Instruction('1', '确认 SD 卡方向正确', Icons.sd_card_outlined),
            Divider(height: 22),
            _Instruction('2', '插入到底并等待 2 秒', Icons.input_rounded),
            Divider(height: 22),
            _Instruction('3', '检查卡槽是否存在异物', Icons.cleaning_services_outlined),
          ],
        ),
      ),
      const SizedBox(height: 22),
      TaskPrimaryButton('重新检测', icon: Icons.refresh_rounded, onPressed: () => controller.setSdState(SdCardReadState.detected)),
      const SizedBox(height: 12),
      TaskPrimaryButton('查看设备状态', filled: false, onPressed: () => Navigator.maybePop(context)),
    ],
  );

  Widget _failed(BuildContext context) => Column(
    children: [
      const SizedBox(height: 34),
      const _RoundStatusIcon(icon: Icons.close_rounded, color: AppColors.danger),
      const SizedBox(height: 26),
      const Text(
        '存储卡读取失败',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.forestDeep, fontSize: 31, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      const Text('无法读取相机存储卡中的内容', style: TextStyle(color: AppColors.mutedInk, fontSize: 17)),
      const SizedBox(height: 28),
      TaskSurface(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '可能原因',
              style: TextStyle(color: AppColors.forestDeep, fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            for (final reason in const ['存储卡接触不良', '文件系统暂时不可读', '存储卡正在被其他任务占用', '存储卡可能存在损坏']) _reason(reason),
          ],
        ),
      ),
      const SizedBox(height: 22),
      TaskPrimaryButton('重新读取', icon: Icons.refresh_rounded, onPressed: () => controller.setSdState(SdCardReadState.detected)),
      const SizedBox(height: 12),
      TaskPrimaryButton('查看详细原因', filled: false, onPressed: () => _message(context, '演示模式：未连接真实存储卡')),
      const SizedBox(height: 12),
      TaskPrimaryButton('返回任务中心', filled: false, onPressed: () => Navigator.maybePop(context)),
    ],
  );

  Widget _empty(BuildContext context) => Column(
    children: [
      const TaskEmptyBoxArt(),
      const SizedBox(height: 18),
      const Text(
        '存储卡中没有可处理的照片',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.forestDeep, fontSize: 30, fontWeight: FontWeight.w800, height: 1.15),
      ),
      const SizedBox(height: 8),
      const Text('支持 RAW 与 JPEG 格式', style: TextStyle(color: AppColors.mutedInk, fontSize: 17)),
      const SizedBox(height: 24),
      TaskSurface(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '请检查',
              style: TextStyle(color: AppColors.forestDeep, fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            for (final item in const [
              (Icons.folder_outlined, '照片是否保存在 DCIM 文件夹'),
              (Icons.image_outlined, '是否使用支持的文件格式'),
              (Icons.sd_card_outlined, '存储卡是否已正确插入'),
              (Icons.shield_outlined, '相机是否使用了特殊加密或保护设置'),
            ])
              _check(item.$1, item.$2),
          ],
        ),
      ),
      const SizedBox(height: 22),
      TaskPrimaryButton('重新扫描', icon: Icons.refresh_rounded, onPressed: () => controller.setSdState(SdCardReadState.detected)),
      const SizedBox(height: 12),
      TaskPrimaryButton('更换存储卡', filled: false, onPressed: () => controller.setSdState(SdCardReadState.missing)),
    ],
  );

  Widget _info(
    IconData icon,
    String label,
    String value, {
    String? unit,
    bool divider = true,
    double valueSize = 26,
  }) => Column(
    children: [
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Row(
          children: [
            Icon(icon, color: AppColors.forestPrimary, size: 28),
            const SizedBox(width: 18),
            SizedBox(
              width: 116,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.ink, fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: value,
                      style: TextStyle(color: AppColors.forestPrimary, fontSize: valueSize, fontWeight: FontWeight.w800),
                    ),
                    if (unit != null)
                      TextSpan(
                        text: ' $unit',
                        style: const TextStyle(color: AppColors.ink, fontSize: 15, fontWeight: FontWeight.w500),
                      ),
                  ],
                ),
                textAlign: TextAlign.end,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(key: Key('sd-card-info-chevron'), Icons.chevron_right_rounded, color: AppColors.forestPrimary),
          ],
        ),
      ),
      if (divider) const Divider(height: 1),
    ],
  );

  Widget _notice(IconData icon, String text) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: AppColors.forestSoft.withValues(alpha: .52),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Icon(icon, color: AppColors.forestPrimary, size: 26),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: const TextStyle(color: AppColors.forestPrimary, fontSize: 15, height: 1.35)),
        ),
      ],
    ),
  );

  Widget _reason(String text) => Column(
    children: [
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 58),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.dangerSoft.withValues(alpha: .85)),
              child: const Icon(Icons.priority_high_rounded, color: AppColors.danger, size: 24),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Text(text, style: const TextStyle(color: AppColors.ink, fontSize: 17)),
            ),
          ],
        ),
      ),
      const Divider(height: 1),
    ],
  );

  Widget _check(IconData icon, String text) => Column(
    children: [
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 62),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.forestSoft.withValues(alpha: .42),
              child: Icon(icon, color: AppColors.forestPrimary),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Text(text, style: const TextStyle(color: AppColors.ink, fontSize: 17, height: 1.35)),
            ),
          ],
        ),
      ),
      const Divider(height: 1),
    ],
  );

  void _message(BuildContext context, String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  String _count(int value) => value.toString().replaceAllMapped(RegExp(r'(\\d)(?=(\\d{3})+$)'), (match) => '${match[1]},');

  String _space(double value) => value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1);

  String _date(DateTime date) => '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
}

class _RoundStatusIcon extends StatelessWidget {
  const _RoundStatusIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 94,
    height: 94,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color,
      border: Border.all(color: AppColors.cream.withValues(alpha: .94), width: 8),
      boxShadow: const [TaskDesign.shadow],
    ),
    child: Icon(icon, color: Colors.white, size: 62),
  );
}

class _Instruction extends StatelessWidget {
  const _Instruction(this.number, this.text, this.icon);

  final String number;
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      CircleAvatar(
        radius: 24,
        backgroundColor: AppColors.forestPrimary,
        foregroundColor: Colors.white,
        child: Text(number, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      ),
      const SizedBox(width: 18),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(color: AppColors.ink, fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      Icon(icon, color: AppColors.forestPrimary.withValues(alpha: .66), size: 54),
    ],
  );
}
