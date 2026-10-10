import 'package:aves/bird_companion/features/connection/domain/ble_diagnostic_export.dart';
import 'package:aves/bird_companion/features/connection/data/platform/birdbox_ble_diagnostic_file_platform.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BleDiagnosticExportDialog extends StatefulWidget {
  const BleDiagnosticExportDialog({super.key, required this.export, this.files = const MethodChannelBirdBoxBleDiagnosticFilePlatform()});
  final BleDiagnosticExport export;
  final BirdBoxBleDiagnosticFilePlatform files;
  @override
  State<BleDiagnosticExportDialog> createState() => _BleDiagnosticExportDialogState();
}

class _BleDiagnosticExportDialogState extends State<BleDiagnosticExportDialog> {
  var _part = 0;
  bool _busy = false;
  String? _notice;
  BleDiagnosticFile? _file;
  Future<void> _copy(String text, String notice) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) setState(() => _notice = notice);
    } catch (_) {
      if (mounted) setState(() => _notice = '复制失败，请重试');
    }
  }

  Future<void> _fileAction({required bool save}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final file = _file ?? await widget.files.prepare(widget.export);
      if (!mounted) return;
      setState(() => _file = file);
      final outcome = save ? await widget.files.save(file) : await widget.files.share(file);
      if (mounted) {
        setState(
          () => _notice = switch (outcome) {
            'saved' => '文件已保存，写入内容已重新读取并校验',
            'cancelled' => '已取消保存，可再次选择位置',
            'share_opened' => '已打开系统分享面板。请以接收端实际收到文件为准。',
            _ => '操作未完成，请重试',
          },
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        final code = error is PlatformException ? error.code : '';
        if (code == 'file_verification_failed') _file = null;
        _notice = switch (code) {
          'share_unavailable' => '分享暂不可用，请使用“保存文件”',
          'file_verification_failed' => '文件校验失败，请重新导出',
          'diagnostic_too_large' => '本次保留记录超过文件大小上限，未截断导出内容',
          'diagnostic_cache_full' => '诊断缓存暂时已满，请稍后重试',
          _ => save ? '保存未完成，请重新选择位置并重试' : '导出或分享未完成，可重试或保存文件',
        };
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('回传蓝牙诊断'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText('诊断编号：${widget.export.traceId}'),
            Text('保留 ${widget.export.retainedScanCount} 次扫描、${widget.export.retainedEventCount} 条连接事件'),
            Text(widget.export.truncated ? '有记录裁剪、历史缺失或记录异常，详情已写入文件。文件包含此快照的全部保留记录。' : '文件包含此快照的全部本地保留记录。'),
            const SizedBox(height: 12),
            FilledButton(key: const Key('ble-share-full-file'), onPressed: _busy ? null : () => _fileAction(save: false), child: const Text('导出/分享完整诊断文件')),
            OutlinedButton(key: const Key('ble-save-full-file'), onPressed: _busy ? null : () => _fileAction(save: true), child: const Text('保存文件')),
            if (_busy) const LinearProgressIndicator(),
            if (_file != null) ...[
              const SizedBox(height: 12),
              SelectableText(_file!.fileName),
              Text('文件大小：${_file!.bytes} 字节'),
              SelectableText('文件 SHA-256：${_file!.sha256}', key: const Key('ble-final-file-sha256')),
              TextButton(onPressed: () => _copy(_file!.sha256, '文件校验值已复制'), child: const Text('复制文件 SHA-256')),
            ],
            const SizedBox(height: 12),
            OutlinedButton(onPressed: () => _copy(widget.export.summaryJson, '短摘要已复制（不是完整记录）'), child: const Text('复制短摘要')),
            ExpansionTile(
              title: const Text('分段复制备用'),
              children: [
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
              ],
            ),
            if (_notice != null) ...[const SizedBox(height: 12), Text(_notice!, key: const Key('ble-export-notice'))],
          ],
        ),
      ),
    ),
    actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('关闭'))],
  );
}
