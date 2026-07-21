import 'package:flutter/material.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';

class SortSheet extends StatelessWidget {
  const SortSheet({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext c) {
    final height = (MediaQuery.sizeOf(c).height * .48).clamp(320, 420).toDouble();
    return SizedBox(
      height: height,
      child: Material(
        color: AppColors.paperStrong,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  margin: const EdgeInsets.only(top: 10, bottom: 14),
                  decoration: BoxDecoration(color: AppColors.outlineStrong, borderRadius: BorderRadius.circular(99)),
                ),
              ),
              const Text(
                '排序方式',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.brandDark),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                  children: [
                    for (final option in ['captured_at_desc', 'score_desc', 'recommended_desc', 'confidence_desc'])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: option == value ? AppColors.brandLight : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(color: option == value ? AppColors.brandMid : AppColors.outline),
                            ),
                            leading: Icon(option == value ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: AppColors.brand),
                            onTap: () {
                              onChanged(option);
                              Navigator.pop(c);
                            },
                            title: Text(switch (option) {
                              'score_desc' => '照片质量从高到低',
                              'confidence_desc' => '识别度从高到低',
                              'recommended_desc' => '系统推荐优先',
                              _ => '拍摄时间最新',
                            }, style: const TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
