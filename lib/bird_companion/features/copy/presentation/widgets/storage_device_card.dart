import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_models.dart';
import 'package:flutter/material.dart';

/// 协议设备卡片（§4.1/§4.2 展示规则）。
///
/// 只展示用户可读名称、厂商/型号、容量、文件系统和角色；绝不展示
/// `/dev/sdX`、挂载点或内部序列号。不可选时显示原因，不得仅灰掉选项（§4.3）。
class StorageDeviceCard extends StatelessWidget {
  const StorageDeviceCard({
    super.key,
    required this.device,
    required this.role,
    required this.selected,
    required this.onTap,
    this.lastUsedForBatch = false,
  });

  final StorageDeviceSummary device;
  final String role;

  /// 用户选择的目标设备角色（源/目标），用于选中态与禁用原因。
  final bool selected;
  final VoidCallback? onTap;
  final bool lastUsedForBatch;

  bool get _canFillRole =>
      device.online && (role == '源设备' ? device.canBeSource : device.canBeTarget);

  @override
  Widget build(BuildContext context) {
    final used = device.capacityBytes <= 0
        ? 0.0
        : ((device.capacityBytes - device.freeBytes) / device.capacityBytes)
              .clamp(0.0, 1.0);
    final blockReason = _blockReason();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? AppColors.brand : AppColors.outline,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        key: Key('storage-device-${device.mediaId}-$role'),
        borderRadius: BorderRadius.circular(16),
        onTap: _canFillRole && onTap != null ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: AppColors.mist,
                    child: Icon(_kindIcon, color: AppColors.brand),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                device.presentationName,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.forestDeep,
                                ),
                              ),
                            ),
                            if (lastUsedForBatch) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.brandLight,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  '上次用于这个批次',
                                  style: TextStyle(
                                    color: AppColors.brand,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          device.detail.isEmpty
                              ? _typeConfidenceHint()
                              : '${device.detail} · ${_filesystemLabel()}',
                          style: const TextStyle(
                            color: AppColors.inkMuted,
                            fontSize: 12,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : _canFillRole
                        ? Icons.radio_button_off_rounded
                        : Icons.lock_outline_rounded,
                    color: selected
                        ? AppColors.brand
                        : _canFillRole
                        ? AppColors.inkMuted
                        : AppColors.danger,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_formatBytes(device.freeBytes)} 可用 / ${_formatBytes(device.capacityBytes)} · $role',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: _canFillRole
                            ? AppColors.forestDeep
                            : AppColors.inkMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (!device.identityStable)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.amberLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '身份不稳定',
                        style: TextStyle(
                          color: AppColors.pending,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: used,
                  minHeight: 7,
                  color: AppColors.brand,
                  backgroundColor: AppColors.mist,
                ),
              ),
              if (blockReason != null) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 15,
                      color: AppColors.danger,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        blockReason,
                        style: const TextStyle(
                          color: AppColors.danger,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String? _blockReason() {
    if (_canFillRole) return null;
    if (!device.online) return '设备已拔出或不可用';
    if (!device.identityStable) return '身份已变化，不能作为${role == '源设备' ? '源' : '目标'}设备';
    if (device.targetBlockReasons.isNotEmpty) {
      return device.targetBlockReasons.join('；');
    }
    return '该设备不能作为$role';
  }

  /// §4.2 第 5 条：无可靠证据时显示普通说明，不伪装成确定类型。
  String _typeConfidenceHint() {
    if (device.kind == 'unknown' ||
        device.kindConfidence == 'low' ||
        device.kindConfidence == 'unknown') {
      return 'USB 存储设备（类型未确认）';
    }
    return _kindLabel;
  }

  String get _kindLabel => switch (device.kind) {
    'memory_card' => '存储卡',
    'card_reader' => '读卡器',
    'usb_flash' => 'U 盘',
    'usb_storage' => 'USB 存储',
    'external_hdd' => '移动硬盘',
    'external_ssd' => '移动固态硬盘',
    'removable_storage' => '可移动存储',
    _ => 'USB 存储设备（类型未确认）',
  };

  String _filesystemLabel() {
    final value = device.filesystem.trim();
    return value.isEmpty ? '文件系统未知' : value.toUpperCase();
  }

  IconData get _kindIcon => switch (device.kind) {
    'memory_card' || 'card_reader' => Icons.sd_card_outlined,
    'usb_flash' => Icons.usb_rounded,
    'usb_storage' || 'removable_storage' || 'unknown' =>
      Icons.storage_rounded,
    'external_hdd' => Icons.storage_rounded,    'external_ssd' => Icons.speed_rounded,
    _ => Icons.storage_rounded,
  };
}

String _formatBytes(int bytes) {
  const gb = 1024 * 1024 * 1024;
  const tb = gb * 1024;
  if (bytes >= tb) return '${(bytes / tb).toStringAsFixed(1)} TB';
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(0)} MB';
}
