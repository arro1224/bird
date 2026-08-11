import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/features/settings/presentation/bird_settings_controller.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_card.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_controls.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_row.dart';
import 'package:aves/bird_companion/features/settings/presentation/widgets/bird_settings_scaffold.dart';
import 'package:flutter/material.dart';

class DisplaySettingsPage extends StatelessWidget {
  const DisplaySettingsPage({super.key, required this.controller});

  final BirdSettingsController controller;

  @override
  Widget build(BuildContext context) => BirdSettingsScaffold(
    title: '显示设置',
    body: ListenableBuilder(
      listenable: controller,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.settingsPageHorizontal,
          AppSpacing.md,
          AppSpacing.settingsPageHorizontal,
          AppSpacing.xl,
        ),
        children: [
          BirdSettingsCard(
            child: Column(
              children: [
                _ControlRow(
                  title: '网格列数（相册/审阅）',
                  subtitle: '设置照片网格显示的列数',
                  titleFontSize: 15,
                  trailing: SizedBox(
                    width: 168,
                    child: SegmentedButton<int>(
                      showSelectedIcon: false,
                      style: BirdSettingsControlStyles.segmented,
                      segments: const [
                        ButtonSegment(value: 3, label: Text('3列')),
                        ButtonSegment(value: 4, label: Text('4列')),
                        ButtonSegment(value: 5, label: Text('5列')),
                      ],
                      selected: {controller.gridColumns},
                      onSelectionChanged: (value) => controller.setGridColumns(value.first),
                    ),
                  ),
                ),
                _ControlRow(
                  title: '默认显示主体框',
                  subtitle: '在照片上显示 AI 识别的主体框',
                  trailing: Switch(
                    key: const Key('display-subject-box'),
                    value: controller.showSubjectBox,
                    onChanged: controller.setShowSubjectBox,
                  ),
                ),
                _ControlRow(
                  title: '选择后自动下一张',
                  subtitle: '确认/不保留后自动跳到下一张',
                  trailing: Switch(value: controller.autoAdvance, onChanged: controller.setAutoAdvance),
                ),
                _ControlRow(
                  title: '默认照片排序',
                  subtitle: '设定相册与审阅页面的默认排序方式',
                  trailing: BirdSettingsDropdownFrame(
                    width: 174,
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<BirdPhotoSortOrder>(
                        isExpanded: true,
                        value: controller.sortOrder,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                        items: BirdPhotoSortOrder.values
                            .map(
                              (item) => DropdownMenuItem(
                                value: item,
                                child: Text(item.label, style: const TextStyle(fontSize: 14)),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) controller.setSortOrder(value);
                        },
                      ),
                    ),
                  ),
                ),
                _ControlRow(
                  title: '评分与状态叠加',
                  subtitle: '在照片缩略图上显示评分与状态图标',
                  trailing: Switch(
                    value: controller.showRatingOverlay,
                    onChanged: controller.setShowRatingOverlay,
                  ),
                ),
                _ControlRow(
                  title: '连拍底栏缩略图大小',
                  subtitle: '设置连拍底栏缩略图的显示大小',
                  showDivider: false,
                  trailing: SizedBox(
                    width: 180,
                    child: SegmentedButton<BirdThumbnailSize>(
                      showSelectedIcon: false,
                      style: BirdSettingsControlStyles.segmented,
                      segments: BirdThumbnailSize.values.map((item) => ButtonSegment(value: item, label: Text(item.label))).toList(),
                      selected: {controller.thumbnailSize},
                      onSelectionChanged: (value) => controller.setThumbnailSize(value.first),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          BirdSettingsOutlineButton(
            key: const Key('display-reset'),
            label: '恢复默认显示设置',
            icon: Icons.refresh_rounded,
            onPressed: controller.resetDisplaySettings,
          ),
        ],
      ),
    ),
  );
}

class _ControlRow extends StatelessWidget {
  const _ControlRow({
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.showDivider = true,
    this.titleFontSize,
  });

  final String title;
  final String subtitle;
  final Widget trailing;
  final bool showDivider;
  final double? titleFontSize;

  @override
  Widget build(BuildContext context) => BirdSettingsRow(
    title: title,
    subtitle: subtitle,
    trailing: trailing,
    showDivider: showDivider,
    minHeight: 94,
    titleFontSize: titleFontSize,
  );
}
