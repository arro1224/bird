import 'package:flutter/material.dart';

class GallerySearchDialog extends StatefulWidget {
  const GallerySearchDialog({super.key, this.initialValue = ''});

  final String initialValue;

  @override
  State<GallerySearchDialog> createState() => _GallerySearchDialogState();
}

class _GallerySearchDialogState extends State<GallerySearchDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('搜索照片'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      textInputAction: TextInputAction.search,
      decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: '文件名、鸟种或标签'),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
      FilledButton(onPressed: _submit, child: const Text('搜索')),
    ],
  );

  void _submit() => Navigator.pop(context, _controller.text.trim());
}
