import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:flutter/material.dart';

class FilterSheet extends StatefulWidget {
  const FilterSheet({super.key, required this.initial, required this.onApply});

  final PhotoQuery initial;
  final ValueChanged<PhotoQuery> onApply;

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late final TextEditingController _search = TextEditingController(text: widget.initial.search);
  late final TextEditingController _species = TextEditingController(text: widget.initial.species);
  late final TextEditingController _tags = TextEditingController(text: widget.initial.tags.join(', '));
  late double? _score = widget.initial.minScore;
  late String? _keep = widget.initial.keepState;
  late String? _analysis = widget.initial.analysisState;
  late String? _clarity = widget.initial.clarityState;
  late String? _recognition = widget.initial.recognitionState;
  late double? _certainty = widget.initial.minConfidence;
  late String _sort = widget.initial.sort;

  @override
  void dispose() {
    _search.dispose();
    _species.dispose();
    _tags.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final baseHeight = (media.size.height * .60).clamp(420, 560).toDouble();
    final sheetHeight = (baseHeight + media.viewInsets.bottom).clamp(baseHeight, media.size.height * .88).toDouble();
    return SizedBox(
      height: sheetHeight,
      child: Material(
        color: AppColors.paperStrong,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusSheet)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(AppSpacing.md, 10, AppSpacing.md, media.viewInsets.bottom + AppSpacing.md),
            child: Column(
              children: [
                const _SheetHandle(),
                SizedBox(
                  height: AppSpacing.minimumTouchTarget,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Text(
                        '筛选照片',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: AppColors.brandDark, fontWeight: FontWeight.w900),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(onPressed: _reset, child: const Text('重置')),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Expanded(
                  child: ListView(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    children: [
                      _FilterSection(
                        icon: Icons.star_outline_rounded,
                        title: '照片质量',
                        child: _ChoiceWrap<double?>(value: _score, options: const [(null, '全部'), (4, '≥4 星'), (3, '≥3 星')], onChanged: (value) => setState(() => _score = value)),
                      ),
                      _FilterSection(
                        icon: Icons.layers_outlined,
                        title: '保留状态',
                        child: _ChoiceWrap<String?>(value: _keep, options: const [(null, '全部'), ('keep', '保留'), ('pending', '待确认'), ('discard', '弃用'), ('featured', '精选')], onChanged: (value) => setState(() => _keep = value)),
                      ),
                      _FilterSection(
                        icon: Icons.image_outlined,
                        title: '清晰度',
                        child: _ChoiceWrap<String?>(value: _clarity, options: const [(null, '全部'), ('clear', '清晰'), ('average', '一般'), ('blurred', '模糊')], onChanged: (value) => setState(() => _clarity = value)),
                      ),
                      _FilterSection(
                        icon: Icons.flutter_dash_outlined,
                        title: '鸟种识别',
                        child: _ChoiceWrap<String?>(value: _recognition, options: const [(null, '全部'), ('recognized', '已识别'), ('needs_review', '待人工确认'), ('unknown', '无法确定')], onChanged: (value) => setState(() => _recognition = value)),
                      ),
                      _FilterSection(
                        icon: Icons.verified_outlined,
                        title: '识别度',
                        child: _ChoiceWrap<double?>(value: _certainty, options: const [(null, '不限'), (.65, '≥65%'), (.85, '≥85%')], onChanged: (value) => setState(() => _certainty = value)),
                      ),
                      _FilterSection(
                        icon: Icons.sort_rounded,
                        title: '排序方式',
                        child: _ChoiceWrap<String>(value: _sort, options: const [('score_desc', '照片质量'), ('captured_at_desc', '拍摄时间'), ('recommended_desc', '系统推荐')], onChanged: (value) => setState(() => _sort = value)),
                      ),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text(
                          '更多条件',
                          style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.brandDark),
                        ),
                        children: [
                          TextField(
                            controller: _search,
                            decoration: const InputDecoration(labelText: '文件名、鸟种或标签', prefixIcon: Icon(Icons.search_rounded)),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          TextField(
                            controller: _species,
                            decoration: const InputDecoration(labelText: '鸟种名称', prefixIcon: Icon(Icons.search_rounded)),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          TextField(
                            controller: _tags,
                            decoration: const InputDecoration(labelText: '标签（以逗号分隔）', prefixIcon: Icon(Icons.sell_outlined)),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          DropdownButtonFormField<String>(
                            initialValue: _analysis,
                            decoration: const InputDecoration(labelText: '识别进度'),
                            items: const [
                              DropdownMenuItem(value: 'completed', child: Text('识别完成')),
                              DropdownMenuItem(value: 'processing', child: Text('正在识别')),
                              DropdownMenuItem(value: 'low_confidence', child: Text('识别结果不确定')),
                              DropdownMenuItem(value: 'failed', child: Text('未能完成识别')),
                            ],
                            onChanged: (value) => setState(() => _analysis = value),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  height: AppSpacing.buttonHeight,
                  child: FilledButton.icon(onPressed: _apply, icon: const Icon(Icons.filter_alt_outlined), label: const Text('应用筛选')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _reset() {
    _search.clear();
    _species.clear();
    _tags.clear();
    setState(() {
      _score = null;
      _keep = null;
      _analysis = null;
      _clarity = null;
      _recognition = null;
      _certainty = null;
      _sort = 'captured_at_desc';
    });
  }

  void _apply() {
    widget.onApply(
      PhotoQuery(
        sort: _sort,
        search: _search.text.trim().isEmpty ? null : _search.text.trim(),
        species: _species.text.trim().isEmpty ? null : _species.text.trim(),
        minScore: _score,
        minConfidence: _certainty,
        tags: _tags.text.split(',').map((value) => value.trim()).where((value) => value.isNotEmpty).toList(),
        keepState: _keep,
        analysisState: _analysis,
        clarityState: _clarity,
        recognitionState: _recognition,
        recommendedOnly: widget.initial.recommendedOnly,
        groupId: widget.initial.groupId,
        sceneId: widget.initial.sceneId,
      ),
    );
    Navigator.pop(context);
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 44,
      height: 5,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(color: AppColors.outlineStrong, borderRadius: BorderRadius.circular(99)),
    ),
  );
}

class _FilterSection extends StatelessWidget {
  const _FilterSection({required this.icon, required this.title, required this.child});

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AppColors.brand, size: 22),
            const SizedBox(width: AppSpacing.xs),
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.brandDark)),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        child,
        const SizedBox(height: AppSpacing.sm),
        const Divider(),
      ],
    ),
  );
}

class _ChoiceWrap<T> extends StatelessWidget {
  const _ChoiceWrap({required this.value, required this.options, required this.onChanged});

  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var index = 0; index < options.length; index++) ...[
        if (index > 0) const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: ChoiceChip(
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: const VisualDensity(horizontal: -1, vertical: -2),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
            side: BorderSide(
              color: value == options[index].$1 ? AppColors.brand : AppColors.outlineStrong,
            ),
            labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: value == options[index].$1 ? AppColors.cream : AppColors.ink,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            label: SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(options[index].$2),
              ),
            ),
            selected: value == options[index].$1,
            showCheckmark: false,
            onSelected: (_) => onChanged(options[index].$1),
          ),
        ),
      ],
    ],
  );
}
