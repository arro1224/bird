import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_card.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_controls.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_row.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_scaffold.dart';
import 'package:flutter/material.dart';

class HelpCenterPage extends StatefulWidget {
  const HelpCenterPage({super.key});

  @override
  State<HelpCenterPage> createState() => _HelpCenterPageState();
}

class _HelpCenterPageState extends State<HelpCenterPage> {
  static const _questions = [
    '连接不上设备',
    '扫码失败怎么办',
    '未检测到 SD 卡',
    '复制失败如何重试',
    '如何导出 XMP',
    '如何修改 AI 识别结果',
  ];
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final visibleQuestions = _questions.where((item) => item.toLowerCase().contains(_query.toLowerCase())).toList();
    return BirdSettingsScaffold(
      title: '帮助中心',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.settingsPageHorizontal,
          AppSpacing.md,
          AppSpacing.settingsPageHorizontal,
          AppSpacing.xl,
        ),
        children: [
          TextField(
            key: const Key('help-search'),
            onChanged: (value) => setState(() => _query = value.trim()),
            decoration: const InputDecoration(
              hintText: '搜索常见问题',
              prefixIcon: Icon(Icons.search_rounded),
              filled: true,
              fillColor: AppColors.settingsSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          BirdSettingsCard(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
                  child: Row(
                    children: [
                      Icon(Icons.help_outline_rounded, color: AppColors.forestPrimary),
                      SizedBox(width: AppSpacing.sm),
                      Text('常见问题', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                if (visibleQuestions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                    child: Center(
                      child: Text('没有找到相关问题', style: TextStyle(color: AppColors.mutedInk)),
                    ),
                  )
                else
                  for (var index = 0; index < visibleQuestions.length; index++)
                    BirdSettingsRow(
                      title: visibleQuestions[index],
                      showDivider: index != visibleQuestions.length - 1,
                      trailing: const BirdChevron(),
                      onTap: () => _message('已打开“${visibleQuestions[index]}”帮助内容'),
                    ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          BirdSettingsCard(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
                  child: Row(
                    children: [
                      Icon(Icons.support_agent_rounded, color: AppColors.forestPrimary),
                      SizedBox(width: AppSpacing.sm),
                      Text('联系我们', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                BirdSettingsRow(
                  title: '提交问题反馈',
                  leading: const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.forestPrimary),
                  trailing: const BirdChevron(),
                  onTap: () => _message('反馈入口为前端演示'),
                ),
                BirdSettingsRow(
                  title: '发送诊断包给客服',
                  leading: const Icon(Icons.description_outlined, color: AppColors.forestPrimary),
                  trailing: const BirdChevron(),
                  onTap: () => _message('演示模式不会发送真实诊断文件'),
                ),
                BirdSettingsRow(
                  title: '查看用户指南',
                  showDivider: false,
                  leading: const Icon(Icons.menu_book_outlined, color: AppColors.forestPrimary),
                  trailing: const BirdChevron(),
                  onTap: () => _message('用户指南入口为前端演示'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          const BirdSettingsCard(
            key: Key('help-support-hours'),
            child: Row(
              children: [
                Icon(Icons.headset_mic_outlined, color: AppColors.forestPrimary, size: 42),
                SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('工作日 9:00–18:00 在线支持', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                      SizedBox(height: AppSpacing.xxs),
                      Text('我们随时为您提供帮助', style: TextStyle(color: AppColors.mutedInk)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _message(String value) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
}
