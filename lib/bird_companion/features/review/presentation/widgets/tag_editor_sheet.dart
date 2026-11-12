import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/models/tag_input.dart';
import 'package:aves/bird_companion/core/widgets/existing_user_tags.dart';
import 'package:flutter/material.dart';

class TagEditorSheet extends StatefulWidget {
  const TagEditorSheet({super.key, required this.existingTags});

  final List<String> existingTags;

  @override
  State<TagEditorSheet> createState() => _TagEditorSheetState();
}

class _TagEditorSheetState extends State<TagEditorSheet> {
  String _draft = '';

  void _submit(List<String> additions) {
    if (additions.isNotEmpty) Navigator.pop(context, additions);
  }

  @override
  Widget build(BuildContext context) {
    final existingTags = normalizeUserTags(widget.existingTags).toSet();
    List<String> parseAdditions(String value) => parseUserTags(value).where((tag) => !existingTags.contains(tag)).toList();
    final additions = parseAdditions(_draft);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '添加标签',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppColors.brandDark,
              ),
            ),
            const SizedBox(height: 16),
            if (existingTags.isNotEmpty) ...[
              ExistingUserTags(tags: existingTags.toList()),
              const SizedBox(height: 16),
            ],
            TextField(
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(hintText: '例如：翠鸟，水鸟，枝头'),
              onChanged: (value) => setState(() => _draft = value),
              onSubmitted: (value) => _submit(parseAdditions(value)),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: additions.isEmpty ? null : () => _submit(additions),
              child: const Text('保存标签'),
            ),
          ],
        ),
      ),
    );
  }
}
