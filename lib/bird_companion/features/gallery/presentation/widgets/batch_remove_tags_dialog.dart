import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/tag_input.dart';
import 'package:aves/bird_companion/features/gallery/domain/batch_tag_change.dart';
import 'package:flutter/material.dart';

class BatchRemoveTagsDialog extends StatefulWidget {
  const BatchRemoveTagsDialog({super.key, required this.loadPhotos});

  final Future<List<PhotoSummary>> Function() loadPhotos;

  @override
  State<BatchRemoveTagsDialog> createState() => _BatchRemoveTagsDialogState();
}

class _BatchRemoveTagsDialogState extends State<BatchRemoveTagsDialog> {
  List<PhotoSummary>? _photos;
  bool _failed = false;
  final _removed = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _photos = null;
      _failed = false;
      _removed.clear();
    });
    try {
      final photos = await widget.loadPhotos();
      if (mounted) setState(() => _photos = photos);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photos = _photos;
    final tags = normalizeUserTags(photos?.expand((photo) => photo.userTags) ?? const <String>[]);
    return AlertDialog(
      title: const Text('批量删除标签'),
      scrollable: true,
      content: SizedBox(
        width: 360,
        child: _failed
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('暂时无法读取所选照片的标签，请重试。'),
                  TextButton(onPressed: _load, child: const Text('重试')),
                ],
              )
            : photos == null
            ? const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              )
            : tags.isEmpty
            ? const Text('所选照片没有可删除的人工标签。')
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('点击标签上的 × 选择删除，确认后从所选照片中移除。'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in tags.where((tag) => !_removed.contains(tag)))
                        InputChip(
                          avatar: const Icon(Icons.eco_outlined, size: 17),
                          label: Text(tag),
                          deleteButtonTooltipMessage: '删除标签：$tag',
                          onDeleted: () => setState(() => _removed.add(tag)),
                        ),
                    ],
                  ),
                  if (_removed.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('将删除：${_removed.join('、')}'),
                    TextButton(onPressed: () => setState(_removed.clear), child: const Text('撤销选择')),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: photos == null || _removed.isEmpty ? null : () => Navigator.pop(context, BatchTagChange.remove(photos: photos, tags: _removed.toList())),
          child: const Text('确认删除'),
        ),
      ],
    );
  }
}
