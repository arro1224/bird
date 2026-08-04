import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:flutter/material.dart';

class TagEditorSheet extends StatefulWidget {
  const TagEditorSheet({super.key, required this.initialTags});

  final String initialTags;

  @override
  State<TagEditorSheet> createState() => _TagEditorSheetState();
}

class _TagEditorSheetState extends State<TagEditorSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTags);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      12,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '添加标签',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: AppColors.brandDark,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例如：翠鸟，水鸟，枝头'),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.pop(context, _controller.text),
            child: const Text('保存标签'),
          ),
        ),
      ],
    ),
  );
}
