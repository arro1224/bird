import 'package:flutter/material.dart';

class ExifPanel extends StatelessWidget {
  const ExifPanel({super.key, required this.exif});
  final Map<String, dynamic> exif;
  @override
  Widget build(BuildContext c) => ExpansionTile(
    title: const Text('EXIF 信息'),
    children: exif.entries.map((e) => ListTile(title: Text(e.key), trailing: Text('${e.value}'))).toList(),
  );
}
