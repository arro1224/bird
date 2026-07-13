import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:flutter/material.dart';

enum BirdKeepState { pending, keep, discard, featured }

extension BirdKeepStatePresentation on BirdKeepState {
  String get label => switch (this) {
    BirdKeepState.pending => '待确认',
    BirdKeepState.keep => '保留',
    BirdKeepState.discard => '弃用',
    BirdKeepState.featured => '精选',
  };

  IconData get icon => switch (this) {
    BirdKeepState.pending => Icons.help_outline_rounded,
    BirdKeepState.keep => Icons.check_circle_outline_rounded,
    BirdKeepState.discard => Icons.remove_circle_outline_rounded,
    BirdKeepState.featured => Icons.star_outline_rounded,
  };

  Color get color => switch (this) {
    BirdKeepState.pending => AppColors.pending,
    BirdKeepState.keep => AppColors.keep,
    BirdKeepState.discard => AppColors.discard,
    BirdKeepState.featured => AppColors.featured,
  };
}

class KeepStateSelector extends StatelessWidget {
  const KeepStateSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final BirdKeepState value;
  final ValueChanged<BirdKeepState> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<BirdKeepState>(
      segments: BirdKeepState.values
          .map(
            (state) => ButtonSegment<BirdKeepState>(
              value: state,
              icon: Icon(state.icon, color: state.color),
              label: Text(state.label),
            ),
          )
          .toList(),
      selected: {value},
      showSelectedIcon: false,
      emptySelectionAllowed: false,
      multiSelectionEnabled: false,
      onSelectionChanged: enabled ? (selection) => onChanged(selection.first) : null,
    );
  }
}
