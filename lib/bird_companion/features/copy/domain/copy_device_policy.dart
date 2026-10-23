import 'copy_models.dart';

/// Source roles are excluded; temporarily unusable targets remain explainable.
abstract final class CopyDevicePolicy {
  static bool isTargetCandidate(StorageDeviceSummary device, String? sourceMediaId) =>
      device.mediaId != sourceMediaId &&
      device.productRole != 'import_source' &&
      !(device.canBeSource && !device.canBeTarget && (device.targetBlockReasons.isEmpty || device.targetBlockReasons.contains('当前任务源设备'))) &&
      (device.canBeTarget || !device.online || device.targetBlockReasons.isNotEmpty);

  static bool canSelectTarget(StorageDeviceSummary device, String? sourceMediaId) => isTargetCandidate(device, sourceMediaId) && device.online && device.canBeTarget && device.targetBlockReasons.isEmpty;

  static String? targetDisabledReason(StorageDeviceSummary device, {String? sourceMediaId}) {
    if (device.mediaId == sourceMediaId || device.productRole == 'import_source') return '相机卡用于导入，不能作为复制目标。';
    if (!device.online) return '设备已断开，请重新插入后检测。';
    if (canSelectTarget(device, sourceMediaId)) return null;
    final reasons = device.targetBlockReasons.map(_reason).toSet();
    return reasons.isEmpty ? '该设备当前不能作为复制目标。' : reasons.join('；');
  }

  static String _reason(String value) {
    final known = switch (value) {
      'COPY_TARGET_READ_ONLY' => '设备为只读，请更换可写的目标设备',
      'COPY_TARGET_BUSY' => '设备正被其他任务占用，请稍后再试',
      'COPY_UNSUPPORTED_FILESYSTEM' => '文件系统不受支持，请更换目标设备',
      'COPY_INSUFFICIENT_SPACE' => '设备空间不足，请更换目标设备',
      'COPY_MEDIA_ID_CHANGED' => '设备身份已变化，请重新检测',
      _ => null,
    };
    if (known != null) return known;
    // Compatibility with the original contract's plain Chinese reasons. Never
    // render unknown internal codes, paths, URLs or arbitrary diagnostic data.
    if (value.length <= 160 && RegExp(r'[\u4e00-\u9fff]').hasMatch(value) && !RegExp(r'[/\\]|[A-Z][A-Z0-9]*_[A-Z0-9_]+|https?:|Exception').hasMatch(value)) return value;
    return '该设备当前不可用，请检查设备状态';
  }
}
