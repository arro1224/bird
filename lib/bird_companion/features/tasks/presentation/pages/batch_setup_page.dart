import 'dart:async';

import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/features/tasks/presentation/task_experience_controller.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_design_components.dart';
import 'package:aves/bird_companion/features/tasks/presentation/widgets/task_page_frame.dart';
import 'package:flutter/material.dart';

class BatchSetupPage extends StatefulWidget {
  const BatchSetupPage({super.key, required this.controller, this.onStartImport});

  final TaskExperienceController controller;
  final FutureOr<void> Function(String batchName)? onStartImport;

  @override
  State<BatchSetupPage> createState() => _BatchSetupPageState();
}

class _BatchSetupPageState extends State<BatchSetupPage> {
  late final TextEditingController _nameController;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final date = widget.controller.sdCard.scannedAt;
    _nameController = TextEditingController(
      text: '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')} 拍摄批次',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.controller.sdCard;
    return TaskPageFrame(
      title: '建立批次',
      subtitle: '步骤 1 / 4 · 导入与索引',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: Icon(Icons.create_new_folder_outlined, size: 76, color: AppColors.forestPrimary),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text(
              '为本次拍摄建立批次',
              style: TextStyle(color: AppColors.forestDeep, fontSize: 24, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            '批次名称',
            style: TextStyle(color: AppColors.forestDeep, fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('batch-name-field'),
            controller: _nameController,
            maxLength: 40,
            decoration: const InputDecoration(
              labelText: '批次名称',
              hintText: '输入便于查找的批次名称',
              counterText: '',
              prefixIcon: Icon(Icons.edit_outlined),
              filled: true,
            ),
          ),
          const SizedBox(height: 18),
          TaskSurface(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Column(
              children: [
                _InfoRow(icon: Icons.sd_card_outlined, label: '照片来源', value: card.name),
                _InfoRow(icon: Icons.image_outlined, label: '照片数量', value: '${card.photoCount} 张'),
                _InfoRow(icon: Icons.photo_size_select_actual_outlined, label: '文件类型', value: 'RAW ${card.rawCount} · JPEG ${card.jpegCount}'),
                _InfoRow(icon: Icons.storage_outlined, label: '预计空间', value: '${card.requiredSpaceGb} GB', showDivider: false),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.forestSoft.withValues(alpha: .5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline_rounded, color: AppColors.forestPrimary),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'SD 卡只读，原始照片不会被修改或删除',
                    style: TextStyle(color: AppColors.forestPrimary, height: 1.45, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          TaskActionButton(
            _submitting ? '正在创建任务…' : '开始导入并建立索引',
            onPressed: _submitting || widget.onStartImport == null
                ? null
                : () async {
                    if (_nameController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先填写批次名称')));
                      return;
                    }
                    final action = widget.onStartImport!;
                    setState(() => _submitting = true);
                    try {
                      await action(_nameController.text.trim());
                    } finally {
                      if (mounted) setState(() => _submitting = false);
                    }
                  },
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value, this.showDivider = true});

  final IconData icon;
  final String label;
  final String value;
  final bool showDivider;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 58),
        child: Row(
          children: [
            Icon(icon, color: AppColors.forestPrimary, size: 22),
            const SizedBox(width: 12),
            SizedBox(
              width: 74,
              child: Text(label, style: const TextStyle(color: AppColors.mutedInk)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: const TextStyle(color: AppColors.forestDeep, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
      if (showDivider) const Divider(height: 1),
    ],
  );
}
