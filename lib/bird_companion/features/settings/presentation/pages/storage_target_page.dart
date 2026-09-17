import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/core/errors/user_message_mapper.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:aves/bird_companion/features/settings/presentation/bird_settings_controller.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_card.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_scaffold.dart';
import 'package:flutter/material.dart';

/// 存储设备页（迁移对照文档 §3.8）。
///
/// 实时列出盒子当前设备（后端交付前为协议字段 mock），支持设置用户别名；
/// 不再提供跨批次「设为默认目标」与预置设备卡片。
class StorageTargetPage extends StatefulWidget {
  const StorageTargetPage({super.key, required this.controller});

  final BirdSettingsController controller;

  @override
  State<StorageTargetPage> createState() => _StorageTargetPageState();
}

class _StorageTargetPageState extends State<StorageTargetPage> {
  List<StorageDeviceSummary>? _devices;

  /// 顶层推荐目标（§4.4 容错字段，审计 P1-3）；仅作展示预选，非默认盘。
  String? _recommendedTargetMediaId;
  Object? _error;

  @override
  void initState() {
    super.initState();
    // maybeOf 走 dependOnInheritedWidget（listen），不能在 initState 同步段执行，
    // 推迟到首帧后（与 copy_job_list_page 同一写法）。
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final dependencies = BirdCompanionScope.maybeOf(context);
    if (dependencies == null) {
      // 独立预览/测试环境没有盒子会话，不访问仓库。
      if (mounted) setState(() => _devices = const []);
      return;
    }
    setState(() {
      _devices = null;
      _error = null;
    });
    try {
      final result = await dependencies.copyRepository.devices();
      if (mounted) {
        setState(() {
          _devices = result.devices;
          _recommendedTargetMediaId = result.recommendedTargetMediaId;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) => BirdSettingsScaffold(
    title: '存储设备',
    body: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.settingsPageHorizontal,
            AppSpacing.md,
            AppSpacing.settingsPageHorizontal,
            AppSpacing.xl,
          ),
          children: [
            Text(
              '盒子当前连接的存储设备。设备身份使用稳定 media_id，换读卡器不影响身份。',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: AppColors.mutedInk),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_error != null) ...[
              _ErrorCard(error: _error!),
              const SizedBox(height: AppSpacing.md),
            ],
            if (_devices == null && _error == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_devices!.isEmpty)
              const BirdSettingsCard(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Text(
                    '没有检测到外接存储设备，连接盒子后可查看实时设备列表。',
                    style: TextStyle(color: AppColors.mutedInk),
                  ),
                ),
              )
            else
              for (final device in _devices!) ...[
                _DeviceRow(
                  key: Key('storage-device-${device.mediaId}'),
                  device: device,
                  recommended:
                      _recommendedTargetMediaId != null &&
                      device.mediaId == _recommendedTargetMediaId,
                  onRename: () => _renameDevice(device),
                  onSafeRemove: device.online && device.canBeTarget
                      ? () => _safeRemoveDevice(device)
                      : null,
                ),
                const SizedBox(height: AppSpacing.md),
              ],
            const SizedBox(height: AppSpacing.md),
            const BirdSettingsCard(
              borderColor: Color(0xFFE8C78B),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 34),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('复制前请确认目标存储空间充足', style: TextStyle(fontWeight: FontWeight.w700)),
                        SizedBox(height: AppSpacing.xxs),
                        Text('空间不足可能导致复制失败或数据不完整', style: TextStyle(color: AppColors.mutedInk)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  /// RC3 安全移除（§4.5）：确认后请求盒子校验，安全则提示可拔出（保持期 60s）。
  Future<void> _safeRemoveDevice(StorageDeviceSummary device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('安全移除设备'),
        content: Text(
          '盒子会先确认没有任务在写入「${device.presentationName}」，'
          '确认安全后即可拔出。要继续吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('再想想'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('安全移除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final result = await BirdCompanionScope.of(context).copyJobRepository.safeRemoveDevice(
        device.mediaId,
        role: 'target',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.safeToRemove
                ? '现在可以拔出「${device.presentationName}」（保持期 60 秒）'
                : result.reason ?? '暂时不能移除该设备',
          ),
        ),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      final message = UserMessageMapper.fromError(error);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${message.title}：${message.message}')),
      );
    }
  }

  Future<void> _renameDevice(StorageDeviceSummary device) async {
    final controller = TextEditingController(text: device.userAlias ?? device.label);
    final alias = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('给设备命名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 24,
          decoration: const InputDecoration(
            labelText: '用户别名',
            hintText: '例如：U 盘 Ee',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (alias == null || alias.isEmpty || !mounted) return;
    try {
      await BirdCompanionScope.of(context).copyRepository.setDeviceAlias(
        device.mediaId,
        alias,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('设备别名已更新')),
      );
    } catch (error) {
      if (!mounted) return;
      final message = UserMessageMapper.fromError(error);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${message.title}：${message.message}')),
      );
    }
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    super.key,
    required this.device,
    required this.onRename,
    this.recommended = false,
    this.onSafeRemove,
  });

  final StorageDeviceSummary device;
  final VoidCallback onRename;

  /// 顶层推荐目标（§4.4）：仅提示上次成功目标，可修改的预选而非默认盘。
  final bool recommended;

  /// RC3 安全移除（§4.5）：仅在线且可作为目标的设备提供。
  final VoidCallback? onSafeRemove;

  @override
  Widget build(BuildContext context) {
    final used = device.capacityBytes <= 0
        ? 0.0
        : ((device.capacityBytes - device.freeBytes) / device.capacityBytes)
              .clamp(0.0, 1.0);
    final online = device.online;
    return BirdSettingsCard(
      borderColor: online ? null : AppColors.outline,
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onRename,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox.square(
                    dimension: 48,
                    child: Center(
                      child: Icon(_kindIcon, size: 34, color: online ? AppColors.forestPrimary : AppColors.inkMuted),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                device.presentationName,
                                style: Theme.of(
                                  context,
                                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            if (!device.identityStable) ...[
                              const SizedBox(width: 6),
                              const _Badge('身份不稳定', AppColors.pending, AppColors.amberLight),
                            ],
                            if (recommended) ...[
                              const SizedBox(width: 6),
                              const _Badge('上次成功目标', AppColors.success, AppColors.forestSoft),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          device.detail.isEmpty ? '类型未确认' : device.detail,
                          style: const TextStyle(color: AppColors.mutedInk, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  const Icon(Icons.edit_outlined, size: 20, color: AppColors.mutedInk),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Text(
                    '${_formatBytes(device.freeBytes)} 可用 / ${_formatBytes(device.capacityBytes)}',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.mutedInk),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  if (device.filesystem.trim().isNotEmpty)
                    _Badge(device.filesystem.toUpperCase(), AppColors.forestPrimary, AppColors.forestSoft),
                  if (device.canBeSource) ...[
                    const SizedBox(width: AppSpacing.xs),
                    const _Badge('源', AppColors.forestPrimary, AppColors.forestSoft),
                  ],
                  if (device.canBeTarget) ...[
                    const SizedBox(width: AppSpacing.xs),
                    const _Badge('目标', AppColors.brand, AppColors.brandLight),
                  ],
                  const Spacer(),
                  Text(online ? '在线' : '已拔出', style: TextStyle(fontSize: 12, color: online ? AppColors.success : AppColors.mutedInk)),
                ],
              ),
              if (onSafeRemove != null) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: Key('storage-safe-remove-${device.mediaId}'),
                    onPressed: onSafeRemove,
                    icon: const Icon(Icons.usb_outlined, size: 16),
                    label: const Text('安全移除'),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xs),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: used,
                  minHeight: 7,
                  color: online ? AppColors.forestPrimary : AppColors.outline,
                  backgroundColor: AppColors.forestSoft,
                ),
              ),
              if (!online) ...[
                const SizedBox(height: AppSpacing.xs),
                const Text(
                  '设备已拔出或身份已变化，不能作为复制目标。',
                  style: TextStyle(color: AppColors.danger, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  IconData get _kindIcon => switch (device.kind) {
    'memory_card' || 'card_reader' => Icons.sd_card_outlined,
    'usb_flash' => Icons.usb_rounded,
    'external_hdd' || 'external_ssd' => Icons.speed_rounded,
    _ => Icons.storage_rounded,
  };
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.foreground, this.background);

  final String text;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: foreground,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final message = UserMessageMapper.fromError(error);
    return BirdSettingsCard(
      borderColor: AppColors.danger,
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.danger),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '${message.title}：${message.message}',
              style: const TextStyle(color: AppColors.danger, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  const gb = 1024 * 1024 * 1024;
  const tb = gb * 1024;
  if (bytes >= tb) return '${(bytes / tb).toStringAsFixed(1)} TB';
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(0)} MB';
}
