import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/bird_ui.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:flutter/material.dart';

class DeviceErrorDetailPage extends StatelessWidget {
  const DeviceErrorDetailPage({super.key, required this.status});
  final DeviceStatus status;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.brand,
    appBar: AppBar(title: const Text('异常详情')),
    body: BirdDarkTheme(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('错误概览', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.amberSoft, AppColors.amber]),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.cream,
                  child: Icon(Icons.priority_high_rounded, color: AppColors.amber, size: 34),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '错误码 ${status.errorCode ?? '未知'}',
                        style: const TextStyle(color: AppColors.brandDark, fontSize: 22, fontWeight: FontWeight.w900),
                      ),
                      Text(status.errorMessage ?? '设备当前没有可读的错误说明。', style: const TextStyle(color: AppColors.brandDark)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('排查建议', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          const _Step(index: 1, text: '重新插入存储卡'),
          const _Step(index: 2, text: '检查网络连接'),
          const _Step(index: 3, text: '重启设备后重试'),
          const SizedBox(height: 22),
          FilledButton.icon(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.refresh_rounded), label: const Text('已处理，返回重试')),
        ],
      ),
    ),
  );
}

class _Step extends StatelessWidget {
  const _Step({required this.index, required this.text});
  final int index;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: AppColors.brandMid,
          child: Text(
            '$index',
            style: const TextStyle(color: AppColors.cream, fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(width: 12),
        Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ],
    ),
  );
}
