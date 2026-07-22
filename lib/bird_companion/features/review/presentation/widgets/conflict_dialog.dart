import 'package:flutter/material.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';

enum ConflictChoice { remote, local, cancel }

class ConflictDialog extends StatelessWidget {
  const ConflictDialog({super.key});
  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: AppColors.brandMid,
    titleTextStyle: const TextStyle(color: AppColors.cream, fontSize: 24, fontWeight: FontWeight.w900),
    contentTextStyle: const TextStyle(color: AppColors.brandLight, fontSize: 16),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(28),
      side: const BorderSide(color: AppColors.brandLight),
    ),
    title: const Text('这张照片在别处被修改过'),
    content: const Text('盒子里保存的内容比手机上的更新。当前协议没有“强制覆盖”能力；你可以使用盒子内容，或暂不覆盖并稍后重试。'),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, ConflictChoice.cancel), child: const Text('取消')),
      TextButton(onPressed: () => Navigator.pop(context, ConflictChoice.remote), child: const Text('使用盒子内容')),
      FilledButton(onPressed: () => Navigator.pop(context, ConflictChoice.local), child: const Text('暂不覆盖盒子')),
    ],
  );
}
