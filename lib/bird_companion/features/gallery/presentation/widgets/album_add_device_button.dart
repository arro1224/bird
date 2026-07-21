import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:flutter/material.dart';

class AlbumAddDeviceButton extends StatelessWidget {
  const AlbumAddDeviceButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: '新增或切换设备',
    child: Semantics(
      button: true,
      label: '新增或切换设备',
      child: SizedBox.square(
        dimension: 48,
        child: InkResponse(
          onTap: onPressed,
          radius: 24,
          child: Center(
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
              child: const Icon(Icons.add_rounded, size: 22, color: Colors.white),
            ),
          ),
        ),
      ),
    ),
  );
}
