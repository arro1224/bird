import 'package:flutter/material.dart';

class ExifPanel extends StatelessWidget {
  const ExifPanel({super.key, required this.exif});
  final Map<String, dynamic> exif;
  @override
  Widget build(BuildContext c) => ExpansionTile(
    title: const Text('拍摄参数'),
    children: exif.entries.map((e) => ListTile(title: Text(_label(e.key)), trailing: Text('${e.value}'))).toList(),
  );
}

String _label(String value) => switch (value.toLowerCase()) {
  'camera' || 'model' => '相机型号',
  'lens' || 'lens_model' => '镜头',
  'focal_length' => '焦距',
  'aperture' || 'f_number' => '光圈',
  'shutter_speed' || 'exposure_time' => '快门速度',
  'iso' || 'iso_speed' => '感光度',
  'captured_at' || 'datetime_original' => '拍摄时间',
  _ => value.replaceAll('_', ' '),
};
