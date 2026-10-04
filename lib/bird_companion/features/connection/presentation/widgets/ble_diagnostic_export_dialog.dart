import 'package:aves/bird_companion/features/connection/domain/ble_diagnostic_export.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BleDiagnosticExportDialog extends StatefulWidget {
  const BleDiagnosticExportDialog({super.key, required this.export});
  final BleDiagnosticExport export;

  @override
  State<BleDiagnosticExportDialog> createState() => _BleDiagnosticExportDialogState();
}

class _BleDiagnosticExportDialogState extends State<BleDiagnosticExportDialog> {
  var _part = 0;
  String? _notice;

  Future<void> _copy(String text, String notice) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) setState(() => _notice = notice);
    } catch (_) {
      if (mounted) setState(() => _notice = '复制失败，请重试');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('回传蓝牙诊断'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('先发送短摘要用于定位。需要完整记录时，按编号逐段复制并分别发送，不要只发送最后一段。记录仅包含当前设备本地保留的本次诊断。'),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => _copy(widget.export.summaryJson, '短摘要已复制（不是完整记录）'), child: const Text('复制短摘要')),
          const SizedBox(height: 16),
          Text('完整记录：第 ${_part + 1} / ${widget.export.parts.length} 段'),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: _part == 0
                    ? null
                    : () => setState(() {
                        _part--;
                        _notice = null;
                      }),
                child: const Text('上一段'),
              ),
              TextButton(
                onPressed: _part + 1 == widget.export.parts.length
                    ? null
                    : () => setState(() {
                        _part++;
                        _notice = null;
                      }),
                child: const Text('下一段'),
              ),
            ],
          ),
          OutlinedButton(onPressed: () => _copy(widget.export.parts[_part], '第 ${_part + 1} / ${widget.export.parts.length} 段已复制，请粘贴发送'), child: const Text('复制当前段')),
          if (_notice != null) ...[const SizedBox(height: 12), Text(_notice!, key: const Key('ble-export-notice'))],
        ],
      ),
    ),
    actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('关闭'))],
  );
}
