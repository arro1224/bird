import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/tag_input.dart';
import 'package:aves/bird_companion/core/widgets/existing_user_tags.dart';
import 'package:aves/bird_companion/features/gallery/domain/batch_tag_change.dart';
import 'package:flutter/material.dart';

class BatchAddTagsDialog extends StatefulWidget {
  const BatchAddTagsDialog({super.key, required this.loadPhotos});

  final Future<List<PhotoSummary>> Function() loadPhotos;

  @override
  State<BatchAddTagsDialog> createState() => _BatchAddTagsDialogState();
}

class _BatchAddTagsDialogState extends State<BatchAddTagsDialog> {
  late Future<List<PhotoSummary>> _photos = Future.sync(widget.loadPhotos);
  String _draft = '';

  @override
  Widget build(BuildContext context) => FutureBuilder<List<PhotoSummary>>(
    future: _photos,
    builder: (context, snapshot) {
      final photos = snapshot.data;
      final tags = parseUserTags(_draft);
      final existingTags = normalizeUserTags(photos?.expand((photo) => photo.userTags) ?? const <String>[]);
      final change = photos == null ? null : BatchTagChange.add(photos: photos, tags: tags);
      final canApply = change != null && change.groups.isNotEmpty;
      return AlertDialog(
        title: const Text('批量添加标签'),
        scrollable: true,
        content: SizedBox(
          width: 360,
          child: snapshot.connectionState == ConnectionState.waiting
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                )
              : photos == null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('暂时无法读取所选照片的标签，请重试。'),
                    TextButton(
                      onPressed: () {
                        final retry = Future.sync(widget.loadPhotos);
                        setState(() {
                          _photos = retry;
                        });
                      },
                      child: const Text('重试'),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (existingTags.isNotEmpty) ...[
                      ExistingUserTags(tags: existingTags, title: '所选照片已有标签'),
                      const SizedBox(height: 16),
                    ],
                    TextField(
                      decoration: const InputDecoration(hintText: '例如：水鸟，晨拍'),
                      textInputAction: TextInputAction.done,
                      onChanged: (value) => setState(() => _draft = value),
                      onSubmitted: (value) {
                        final submitted = BatchTagChange.add(photos: photos, tags: parseUserTags(value));
                        if (submitted.groups.isNotEmpty) Navigator.pop(context, submitted);
                      },
                    ),
                    if (!canApply && tags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text('所选照片都已有这些标签。'),
                    ],
                  ],
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: canApply ? () => Navigator.pop(context, change) : null,
            child: const Text('应用'),
          ),
        ],
      );
    },
  );
}
