import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:flutter/material.dart';

class AlbumAddDeviceButton extends StatelessWidget {
  const AlbumAddDeviceButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: '查找或切换盒子',
    child: Semantics(
      button: true,
      label: '查找或切换盒子',
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
              child: const Icon(Icons.devices_other_rounded, size: 22, color: Colors.white),
            ),
          ),
        ),
      ),
    ),
  );
}
