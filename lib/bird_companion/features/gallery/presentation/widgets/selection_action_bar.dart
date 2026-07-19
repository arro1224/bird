import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class SelectionActionBar extends StatefulWidget {
  const SelectionActionBar({
    super.key,
    required this.count,
    required this.busy,
    required this.onAction,
    required this.onAddTags,
    required this.onRemoveTags,
    required this.onClear,
  });

  final int count;
  final bool busy;
  final ValueChanged<String> onAction;
  final VoidCallback onAddTags;
  final VoidCallback onRemoveTags;
  final VoidCallback onClear;

  @override
  State<SelectionActionBar> createState() => _SelectionActionBarState();
}

class _SelectionActionBarState extends State<SelectionActionBar> {
  String? _pendingAction;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.paperStrong,
    elevation: 16,
    borderRadius: const BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusSheet)),
    clipBehavior: Clip.antiAlias,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(color: AppColors.outlineStrong, borderRadius: BorderRadius.circular(99)),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '批量操作',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: AppColors.brandDark, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: AppSpacing.md),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: AppSpacing.xs,
              crossAxisSpacing: AppSpacing.xs,
              childAspectRatio: 1.15,
              children: [
                _Action(icon: Icons.check_rounded, label: '确认保留', subtitle: '保留选中的照片', color: AppColors.keep, selected: _pendingAction == 'keep', onTap: widget.busy ? null : () => _choose('keep')),
                _Action(icon: Icons.close_rounded, label: '确认弃用', subtitle: '排除选中的照片', color: AppColors.danger, selected: _pendingAction == 'discard', onTap: widget.busy ? null : () => _choose('discard')),
                _Action(icon: Icons.new_label_outlined, label: '添加标签', subtitle: '批量添加或修改标签', onTap: widget.busy ? null : widget.onAddTags),
                _MoreAction(
                  busy: widget.busy,
                  onSelected: (value) {
                    if (value == 'remove_tags') {
                      widget.onRemoveTags();
                    } else {
                      _choose(value);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
              decoration: BoxDecoration(color: AppColors.brandLight.withValues(alpha: .65), borderRadius: BorderRadius.circular(AppSpacing.radiusCompact)),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.brand),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      _pendingAction == null ? '请先选择操作；完成后会在照片上显示结果。' : '已选择“${_label(_pendingAction!)}”，将处理 ${widget.count} 张照片。',
                      style: const TextStyle(fontSize: 12, color: AppColors.brand),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: widget.busy || _pendingAction == null
                    ? null
                    : () {
                        final action = _pendingAction!;
                        setState(() => _pendingAction = null);
                        widget.onAction(action);
                      },
                icon: widget.busy ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_circle_outline_rounded),
                label: Text(widget.busy ? '正在处理 ${widget.count} 张…' : '确认操作'),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  void _choose(String action) => setState(() => _pendingAction = action);

  String _label(String value) => switch (value) {
    'keep' => '确认保留',
    'discard' => '确认弃用',
    'featured' => '设为精选',
    _ => '标记待确认',
  };
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.subtitle, required this.onTap, this.color = AppColors.brand, this.selected = false});
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback? onTap;
  final Color color;
  final bool selected;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? color.withValues(alpha: .10) : AppColors.paperStrong,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
      side: BorderSide(color: selected ? color : AppColors.outline, width: selected ? 2 : 1),
    ),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: .10),
              child: Icon(icon, color: onTap == null ? AppColors.inkFaint : color),
            ),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppColors.inkMuted),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MoreAction extends StatelessWidget {
  const _MoreAction({required this.busy, required this.onSelected});
  final bool busy;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    enabled: !busy,
    onSelected: onSelected,
    itemBuilder: (_) => const [
      PopupMenuItem(
        value: 'pending',
        child: ListTile(leading: Icon(Icons.help_outline_rounded), title: Text('标记待确认')),
      ),
      PopupMenuItem(
        value: 'featured',
        child: ListTile(leading: Icon(Icons.star_outline_rounded), title: Text('设为精选')),
      ),
      PopupMenuItem(
        value: 'remove_tags',
        child: ListTile(leading: Icon(Icons.label_off_outlined), title: Text('删除标签')),
      ),
    ],
    child: _PassiveAction(
      icon: Icons.more_horiz_rounded,
      label: '更多操作',
      subtitle: '待确认、精选等',
      enabled: !busy,
    ),
  );
}

class _PassiveAction extends StatelessWidget {
  const _PassiveAction({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.enabled,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.paperStrong,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: AppColors.outline),
    ),
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            backgroundColor: AppColors.brand.withValues(alpha: .10),
            child: Icon(
              icon,
              color: enabled ? AppColors.brand : AppColors.inkFaint,
            ),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: AppColors.inkMuted),
          ),
        ],
      ),
    ),
  );
}
