import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';
import 'package:aves/bird_companion/features/tasks/presentation/task_experience_controller.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_design_components.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_nature_background.dart';
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
        const Positioned.fill(child: TaskNatureBackground()),
        SafeArea(
          bottom: false,
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => Column(
              children: [
                _header(context),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
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
    height: 66,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Text(
          controller.sdCard.state == SdCardReadState.detected ? '检测到 SD 卡' : '读取 SD 卡',
          style: const TextStyle(color: AppColors.forestDeep, fontSize: 23, fontWeight: FontWeight.w700),
        ),
        Positioned(
          left: 8,
          child: IconButton(
            key: const Key('sd-card-back-button'),
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.forestDeep),
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

  Widget _hero(IconData icon, String title, String subtitle, {Color color = AppColors.forestPrimary}) => Column(
    children: [
      Icon(icon, size: 116, color: color),
      const SizedBox(height: 18),
      Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.forestDeep, fontSize: 29, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      Text(
        subtitle,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.mutedInk, fontSize: 17),
      ),
      const SizedBox(height: 26),
    ],
  );

  Widget _detected(BuildContext context) => Column(
    children: [
      const _DetectedSdCardHero(key: Key('sd-card-detected-hero')),
      const SizedBox(height: 18),
      const Text(
        '已检测到存储卡',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.forestDeep, fontSize: 29, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      Text(
        controller.sdCard.name,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.mutedInk, fontSize: 17),
      ),
      const SizedBox(height: 26),
      TaskSurface(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Column(
          children: [
            _info(Icons.image_outlined, '照片数量', '3,672 张'),
            _info(Icons.pie_chart_outline_rounded, '预计读取空间', '86.4 GB'),
            _info(Icons.insert_drive_file_outlined, '文件类型', 'RAW 2,518 · JPEG 1,154'),
            _info(Icons.calendar_month_outlined, '拍摄日期', '2026.07.16', divider: false),
          ],
        ),
      ),
      const SizedBox(height: 18),
      _hint('建议先生成缩略图，再开始 AI 分析'),
      const SizedBox(height: 18),
      _button('开始建立批次', onContinue ?? () {}, filled: true),
      const SizedBox(height: 10),
      _button('稍后处理', () => Navigator.maybePop(context)),
    ],
  );

  Widget _missing(BuildContext context) => Column(
    children: [
      _hero(Icons.sd_card_outlined, '未检测到存储卡', '请插入相机 SD 卡后重试', color: const Color(0xFF87927E)),
      const TaskSurface(
        child: Column(
          children: [
            _Instruction('1', '确认 SD 卡方向正确', Icons.sd_card_outlined),
            Divider(),
            _Instruction('2', '插入到底并等待 2 秒', Icons.input_rounded),
            Divider(),
            _Instruction('3', '检查卡槽是否存在异物', Icons.cleaning_services_outlined),
          ],
        ),
      ),
      const SizedBox(height: 20),
      _button('重新检测', () => controller.setSdState(SdCardReadState.detected), filled: true),
      const SizedBox(height: 10),
      _button('查看设备状态', () => Navigator.maybePop(context)),
    ],
  );

  Widget _failed(BuildContext context) => Column(
    children: [
      _hero(Icons.cancel_rounded, '存储卡读取失败', '无法读取相机存储卡中的内容', color: AppColors.danger),
      TaskSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '可能原因',
              style: TextStyle(color: AppColors.forestDeep, fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            for (final text in ['存储卡接触不良', '文件系统暂时不可读', '存储卡正在被其他任务占用', '存储卡可能存在损坏']) _reason(text),
          ],
        ),
      ),
      const SizedBox(height: 20),
      _button('重新读取', () => controller.setSdState(SdCardReadState.detected), filled: true),
      const SizedBox(height: 10),
      _button('查看详细原因', () => _message(context, '演示模式：未连接真实存储卡')),
      const SizedBox(height: 10),
      _button('返回任务中心', () => Navigator.maybePop(context)),
    ],
  );

  Widget _empty(BuildContext context) => Column(
    children: [
      _hero(Icons.photo_library_outlined, '存储卡中没有可处理的照片', '支持 RAW 与 JPEG 格式'),
      TaskSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '请检查',
              style: TextStyle(color: AppColors.forestDeep, fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final item in [(Icons.folder_outlined, '照片是否保存在 DCIM 文件夹'), (Icons.image_outlined, '是否使用支持的文件格式'), (Icons.sd_card_outlined, '存储卡是否已正确插入'), (Icons.shield_outlined, '相机是否使用了特殊加密或保护设置')]) _check(item.$1, item.$2),
          ],
        ),
      ),
      const SizedBox(height: 20),
      _button('重新扫描', () => controller.setSdState(SdCardReadState.detected), filled: true),
      const SizedBox(height: 10),
      _button('更换存储卡', () => controller.setSdState(SdCardReadState.missing)),
    ],
  );

  Widget _info(IconData icon, String label, String value, {bool divider = true}) => Column(
    children: [
      SizedBox(
        height: 58,
        child: Row(
          children: [
            Icon(icon, color: AppColors.forestPrimary, size: 24),
            const SizedBox(width: 8),
            SizedBox(width: 104, child: Text(label, maxLines: 1, style: const TextStyle(fontSize: 16))),
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                textAlign: TextAlign.end,
                style: TextStyle(color: AppColors.forestDeep, fontSize: value.length > 15 ? 12.5 : 17),
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right_rounded, key: Key('sd-card-info-chevron'), size: 18, color: AppColors.forestPrimary),
          ],
        ),
      ),
      if (divider) const Divider(height: 1),
    ],
  );
  Widget _reason(String text) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const CircleAvatar(
      radius: 14,
      backgroundColor: Color(0xFFF8DDD7),
      child: Icon(Icons.priority_high, size: 17, color: AppColors.danger),
    ),
    title: Text(text),
  );
  Widget _check(IconData icon, String text) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, color: AppColors.forestPrimary),
    title: Text(text),
  );
  Widget _hint(String text) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: AppColors.forestSoft.withValues(alpha: .58), borderRadius: BorderRadius.circular(14)),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: AppColors.forestPrimary),
    ),
  );
  Widget _button(String label, VoidCallback action, {bool filled = false}) => SizedBox(
    width: double.infinity,
    height: 56,
    child: filled ? FilledButton(onPressed: action, child: Text(label)) : OutlinedButton(onPressed: action, child: Text(label)),
  );
  void _message(BuildContext context, String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

class _DetectedSdCardHero extends StatelessWidget {
  const _DetectedSdCardHero({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 150,
    height: 145,
    child: CustomPaint(painter: _DetectedSdCardPainter()),
  );
}

class _DetectedSdCardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final card = Path()
      ..moveTo(size.width * .25, size.height * .08)
      ..lineTo(size.width * .72, size.height * .08)
      ..quadraticBezierTo(size.width * .78, size.height * .08, size.width * .78, size.height * .14)
      ..lineTo(size.width * .78, size.height * .72)
      ..quadraticBezierTo(size.width * .78, size.height * .79, size.width * .71, size.height * .79)
      ..lineTo(size.width * .25, size.height * .79)
      ..quadraticBezierTo(size.width * .19, size.height * .79, size.width * .19, size.height * .72)
      ..lineTo(size.width * .19, size.height * .22)
      ..close();
    canvas.drawShadow(card, const Color(0x44000000), 7, false);
    canvas.drawPath(card, Paint()..color = const Color(0xFF4E743A));
    canvas.drawPath(
      card,
      Paint()
        ..color = const Color(0xFF214D2B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    for (var i = 0; i < 5; i++) {
      canvas.drawRect(
        Rect.fromLTWH(size.width * (.29 + i * .085), size.height * .15, size.width * .055, size.height * .18),
        Paint()..color = const Color(0xFFE6E7C9),
      );
    }

    final sd = TextPainter(
      text: const TextSpan(
        text: 'SD',
        style: TextStyle(color: Colors.white, fontSize: 31, fontWeight: FontWeight.w800, fontStyle: FontStyle.italic),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    sd.paint(canvas, Offset((size.width - sd.width) * .48, size.height * .43));

    final center = Offset(size.width * .75, size.height * .77);
    canvas.drawCircle(center, size.width * .16, Paint()..color = const Color(0xFF3E9639));
    canvas.drawCircle(
      center,
      size.width * .16,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    final check = Path()
      ..moveTo(center.dx - 11, center.dy)
      ..lineTo(center.dx - 2, center.dy + 9)
      ..lineTo(center.dx + 14, center.dy - 10);
    canvas.drawPath(
      check,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Instruction extends StatelessWidget {
  const _Instruction(this.number, this.text, this.icon);
  final String number;
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 86,
    child: Row(
      children: [
        CircleAvatar(backgroundColor: AppColors.forestPrimary, foregroundColor: Colors.white, child: Text(number)),
        const SizedBox(width: 14),
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        Icon(icon, size: 46, color: AppColors.forestPrimary.withValues(alpha: .65)),
      ],
    ),
  );
}
