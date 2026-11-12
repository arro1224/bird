import 'package:flutter/material.dart';

class ExistingUserTags extends StatelessWidget {
  const ExistingUserTags({super.key, required this.tags, this.title = '已有标签'});

  final List<String> tags;
  final String title;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final tag in tags)
            Chip(
              avatar: const Icon(Icons.eco_outlined, size: 17),
              label: Text(tag),
            ),
        ],
      ),
    ],
  );
}
