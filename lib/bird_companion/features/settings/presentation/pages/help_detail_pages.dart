import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/network_diagnostics_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/pages/system_logs_page.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_card.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_controls.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_row.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_scaffold.dart';
import 'package:flutter/material.dart';

class FaqDetailPage extends StatelessWidget {
  const FaqDetailPage({super.key, required this.question});

  final String question;

  @override
  Widget build(BuildContext context) => BirdSettingsScaffold(
    title: question,
    body: ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.settingsPageHorizontal,
        AppSpacing.md,
        AppSpacing.settingsPageHorizontal,
        AppSpacing.xl,
      ),
      children: [
        BirdSettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '先检查这些项目',
                style: TextStyle(color: AppColors.forestDeep, fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(_answer(question), style: const TextStyle(color: AppColors.mutedInk, height: 1.65)),
              const SizedBox(height: AppSpacing.md),
              const Text(
                '仍然无法解决',
                style: TextStyle(color: AppColors.forestDeep, fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: AppSpacing.xs),
              const Text('返回设备页重新操作；如果问题持续出现，请提交反馈并附加诊断包。', style: TextStyle(color: AppColors.mutedInk, height: 1.55)),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        BirdSettingsCard(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Column(
            children: [
              BirdSettingsRow(
                title: '运行网络诊断',
                subtitle: '检查当前连接链路',
                leading: const Icon(Icons.wifi_find_rounded, color: AppColors.forestPrimary),
                trailing: const BirdChevron(),
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(builder: (_) => const NetworkDiagnosticsPage()),
                ),
              ),
              BirdSettingsRow(
                title: '导出诊断包',
                subtitle: '为技术支持准备诊断信息',
                showDivider: false,
                leading: const Icon(Icons.archive_outlined, color: AppColors.forestPrimary),
                trailing: const BirdChevron(),
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(builder: (_) => const SystemLogsPage()),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  static String _answer(String question) => switch (question) {
    '连接不上设备' => '1. 确认拍鸟盒子已开机，状态指示灯正常。\n\n2. 手机已开启蓝牙和本地网络权限。\n\n3. 手机靠近盒子，并暂时关闭 VPN 或代理网络。',
    '扫码失败怎么办' => '1. 擦拭相机镜头并保持二维码完整清晰。\n\n2. 调整距离，避免反光和画面抖动。\n\n3. 仍无法识别时返回设备搜索，选择附近设备连接。',
    '未检测到 SD 卡' => '1. 重新插入 SD 卡并等待 5 秒。\n\n2. 检查卡片是否损坏或被写保护。\n\n3. 建议使用设备支持的 exFAT 格式。',
    '复制失败如何重试' => '1. 检查目标设备剩余空间。\n\n2. 保持盒子供电和网络稳定。\n\n3. 返回任务页打开失败任务并选择重试。',
    '如何导出 XMP' => '在复制默认设置中启用 XMP 导出，然后选择目标位置并创建复制任务。',
    _ => '在照片详情中打开识别结果，选择正确的鸟种或调整审阅状态，修改会保存在当前项目中。',
  };
}

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final _descriptionController = TextEditingController();
  final _contactController = TextEditingController();
  var _category = '设备连接问题';
  var _includeDiagnostics = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BirdSettingsScaffold(
    title: '提交问题反馈',
    body: ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.settingsPageHorizontal,
        AppSpacing.md,
        AppSpacing.settingsPageHorizontal,
        AppSpacing.xl,
      ),
      children: [
        BirdSettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '问题类型',
                style: TextStyle(color: AppColors.forestDeep, fontWeight: FontWeight.w800),
              ),
              DropdownButtonFormField<String>(
                initialValue: _category,
                items: const ['设备连接问题', '照片传输问题', '任务执行问题', '其他问题'].map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                onChanged: (value) => setState(() => _category = value ?? _category),
              ),
              const SizedBox(height: AppSpacing.md),
              const Text(
                '问题描述',
                style: TextStyle(color: AppColors.forestDeep, fontWeight: FontWeight.w800),
              ),
              TextField(
                key: const Key('feedback-description'),
                controller: _descriptionController,
                minLines: 4,
                maxLines: 6,
                decoration: const InputDecoration(hintText: '请描述出现问题前的操作和异常现象'),
              ),
              const SizedBox(height: AppSpacing.md),
              const Text(
                '联系方式（选填）',
                style: TextStyle(color: AppColors.forestDeep, fontWeight: FontWeight.w800),
              ),
              TextField(
                controller: _contactController,
                decoration: const InputDecoration(hintText: '手机号或邮箱'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        BirdSettingsCard(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('附加诊断包'),
            subtitle: const Text('包含设备状态与近期日志'),
            secondary: const Icon(Icons.archive_outlined, color: AppColors.forestPrimary),
            value: _includeDiagnostics,
            onChanged: (value) => setState(() => _includeDiagnostics = value),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const BirdSettingsCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, color: AppColors.forestPrimary),
              SizedBox(width: AppSpacing.sm),
              Expanded(child: Text('请勿在问题描述中填写密码或其他敏感信息。')),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        BirdSettingsPrimaryButton(
          label: '提交反馈',
          icon: Icons.send_outlined,
          onPressed: _submit,
        ),
      ],
    ),
  );

  void _submit() {
    final description = _descriptionController.text.trim();
    if (description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写问题描述')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('反馈已保存，待后端反馈接口接入后提交')),
    );
  }
}

class UserGuidePage extends StatelessWidget {
  const UserGuidePage({super.key});

  static const steps = [
    ('连接拍鸟盒子', '开启设备并在设备页完成发现与连接'),
    ('导入并建立索引', '插入 SD 卡，等待照片读取与索引完成'),
    ('完成照片审阅', '在相册中确认精选、保留与不保留状态'),
    ('复制与导出', '选择目标设备并创建复制任务'),
  ];

  @override
  Widget build(BuildContext context) => BirdSettingsScaffold(
    title: '用户指南',
    body: ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.settingsPageHorizontal,
        AppSpacing.md,
        AppSpacing.settingsPageHorizontal,
        AppSpacing.xl,
      ),
      children: [
        BirdSettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '快速开始',
                style: TextStyle(color: AppColors.forestDeep, fontSize: 18, fontWeight: FontWeight.w800),
              ),
              for (var i = 0; i < steps.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 17,
                        backgroundColor: AppColors.forestPrimary,
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(steps[i].$1, style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text(steps[i].$2, style: const TextStyle(color: AppColors.mutedInk)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        BirdSettingsCard(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Column(
            children: [
              for (var i = 0; i < 3; i++)
                BirdSettingsRow(
                  title: const ['设备连接指南', '照片审阅指南', '复制与备份指南'][i],
                  leading: Icon(const [Icons.link_rounded, Icons.photo_outlined, Icons.storage_outlined][i], color: AppColors.forestPrimary),
                  trailing: const BirdChevron(),
                  showDivider: i != 2,
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => FaqDetailPage(
                        question: i == 0
                            ? '连接不上设备'
                            : i == 1
                            ? '如何修改 AI 识别结果'
                            : '复制失败如何重试',
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
