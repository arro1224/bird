import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/features/tasks/domain/task_experience.dart';
import 'package:aves/bird_companion/features/tasks/presentation/task_experience_controller.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_design_components.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_page_frame.dart';
import 'package:flutter/material.dart';

class CopyContentPage extends StatelessWidget {
  const CopyContentPage({super.key, required this.controller, this.onNext});
  final TaskExperienceController controller;
  final VoidCallback? onNext;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (_, _) => TaskPageFrame(
      title: '复制照片',
      subtitle: '步骤 2 / 3 · 选择复制内容',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TaskSurface(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '复制范围',
                  style: TextStyle(color: AppColors.forestDeep, fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                RadioGroup<CopyMode>(
                  groupValue: controller.copyMode,
                  onChanged: (value) {
                    if (value != null) controller.selectCopyMode(value);
                  },
                  child: Column(
                    children: [
                      _mode(CopyMode.keep, '仅复制保留照片', '2,012 张', '推荐'),
                      _mode(CopyMode.all, '复制全部照片', '3,672 张', null),
                      _mode(CopyMode.dual, '双轨复制', '保留照片 + 完整备份', null),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TaskSurface(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '目标存储',
                  style: TextStyle(color: AppColors.forestDeep, fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                const Row(
                  children: [
                    _ExternalDriveIcon(key: Key('copy-target-drive-icon')),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Samsung T7 Shield', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                          SizedBox(height: 3),
                          Text('1.2 TB 可用', style: TextStyle(color: AppColors.mutedInk, fontSize: 15)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const LinearProgressIndicator(value: .52, minHeight: 6),
                const SizedBox(height: 8),
                Text('预计使用：${controller.copyEstimate.spaceGb} GB', style: const TextStyle(color: AppColors.mutedInk)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TaskSurface(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text(
                '生成同名 XMP',
                style: TextStyle(color: AppColors.forestDeep, fontWeight: FontWeight.w700),
              ),
              subtitle: const Text('写入评分、标签、鸟种和保留状态'),
              value: controller.generateXmp,
              onChanged: controller.setGenerateXmp,
            ),
          ),
          const SizedBox(height: 12),
          TaskActionButton('下一步', onPressed: onNext ?? () {}),
          const SizedBox(height: 10),
          TaskActionButton('保存为默认策略', filled: false, onPressed: () {}),
        ],
      ),
    ),
  );

  Widget _mode(CopyMode mode, String title, String subtitle, String? badge) {
    final selected = controller.copyMode == mode;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        key: const Key('copy-mode-card'),
        color: selected ? AppColors.forestSoft.withValues(alpha: .18) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => controller.selectCopyMode(mode),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 68,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              border: Border.all(color: selected ? AppColors.forestPrimary : const Color(0xFFD9D9D2), width: selected ? 1.2 : 1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Radio<CopyMode>(value: mode),
                const SizedBox(width: 2),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(color: AppColors.forestDeep, fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(subtitle, style: const TextStyle(color: AppColors.mutedInk, fontSize: 14)),
                    ],
                  ),
                ),
                if (badge != null)
                  Container(
                    key: const Key('copy-recommended-badge'),
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                    decoration: BoxDecoration(color: AppColors.forestSoft.withValues(alpha: .65), borderRadius: BorderRadius.circular(7)),
                    child: const Text('推荐', style: TextStyle(color: AppColors.forestPrimary, fontSize: 13)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExternalDriveIcon extends StatelessWidget {
  const _ExternalDriveIcon({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 48,
    height: 58,
    child: Transform.rotate(angle: .13, child: CustomPaint(painter: _ExternalDrivePainter())),
  );
}

class _ExternalDrivePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final outline = Paint()
      ..color = AppColors.forestPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    final body = RRect.fromRectAndRadius(Rect.fromLTWH(7, 3, size.width - 14, size.height - 8), const Radius.circular(7));
    canvas.drawRRect(body, Paint()..color = const Color(0xFFF7F8F2));
    canvas.drawRRect(body, outline);
    for (var x = 11.0; x < size.width - 10; x += 8) {
      canvas.drawLine(
        Offset(x, 8),
        Offset(x - 7, size.height - 14),
        Paint()
          ..color = const Color(0xFF94AD83)
          ..strokeWidth = 1,
      );
    }
    canvas.drawLine(Offset(10, size.height - 13), Offset(size.width - 10, size.height - 13), outline);
    canvas.drawCircle(Offset(size.width - 14, size.height - 8), 1.5, Paint()..color = AppColors.forestPrimary);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
