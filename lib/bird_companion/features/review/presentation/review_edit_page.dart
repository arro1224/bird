import 'dart:async';

import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/presentation/user_facing_text.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/core/models/tag_input.dart';
import 'package:aves/bird_companion/core/widgets/bird_navigation.dart';
import 'package:aves/bird_companion/core/widgets/natural_backdrop.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class ReviewEditResult {
  const ReviewEditResult({required this.keepState, this.speciesId, required this.species, required this.score, required this.tags});
  final KeepState keepState;
  final String? speciesId;
  final String species;
  final String score;
  final String tags;
}

class ReviewEditPage extends StatefulWidget {
  const ReviewEditPage({
    super.key,
    required this.keepState,
    required this.species,
    required this.score,
    required this.tags,
    this.initialCandidates = const [],
    this.previewUri,
  });

  final KeepState keepState;
  final String species;
  final String score;
  final String tags;
  final List<SpeciesCandidate> initialCandidates;
  final Uri? previewUri;

  @override
  State<ReviewEditPage> createState() => _ReviewEditPageState();
}

class _ReviewEditPageState extends State<ReviewEditPage> {
  late final KeepState _keep = widget.keepState;
  late final _species = TextEditingController(text: widget.species);
  late final _score = TextEditingController(text: widget.score);
  late final _tags = TextEditingController(text: widget.tags);
  late List<SpeciesCandidate> _candidates = widget.initialCandidates;
  String? _speciesId;
  Timer? _searchDebounce;
  bool _searching = false;
  String? _searchMessage;

  @override
  void initState() {
    super.initState();
    _speciesId = _candidateForName(widget.species)?.speciesId;
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _species.dispose();
    _score.dispose();
    _tags.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.paper,
    appBar: BirdSecondaryAppBar(title: '修改识别结果'),
    body: NaturalBackdrop(
      dense: true,
      child: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.ml, AppSpacing.md, AppSpacing.ml, AppSpacing.xxl),
          children: [
            TextField(
              controller: _species,
              onChanged: (value) {
                if (_candidateForName(value)?.speciesId != _speciesId) _speciesId = null;
                _scheduleSearch(value);
              },
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: '搜索鸟种名称',
                suffixIcon: _searching ? const Padding(padding: EdgeInsets.all(14), child: CircularProgressIndicator(strokeWidth: 2)) : null,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (widget.previewUri != null) _CurrentResultCard(uri: widget.previewUri!, species: _species.text, candidate: _selectedCandidate),
            const SizedBox(height: AppSpacing.lg),
            Text('可能的鸟种', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: AppColors.brandDark)),
            const SizedBox(height: AppSpacing.sm),
            if (_searchMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Text(_searchMessage!, style: const TextStyle(color: AppColors.inkMuted)),
              )
            else if (_candidates.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Text('系统没有找到相似鸟种，你可以直接输入名称。', style: TextStyle(color: AppColors.inkMuted)),
              )
            else
              Card(
                child: Column(
                  children: [
                    for (var index = 0; index < _candidates.length; index++) ...[
                      _CandidateTile(
                        candidate: _candidates[index],
                        selected: _species.text.trim() == _candidates[index].name,
                        onTap: () => setState(() {
                          _species.text = _candidates[index].name;
                          _speciesId = _candidates[index].speciesId;
                        }),
                      ),
                      if (index != _candidates.length - 1) const Divider(height: 1, indent: 20, endIndent: 20),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.lg),
            Text('人工标签', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: AppColors.brandDark)),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final tag in _tagValues)
                  InputChip(
                    avatar: const Icon(Icons.eco_outlined, size: 17),
                    label: Text(tag),
                    onDeleted: () => _removeTag(tag),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add_circle_outline_rounded, size: 18),
                  label: const Text('添加标签'),
                  side: const BorderSide(color: AppColors.outlineStrong, style: BorderStyle.solid),
                  onPressed: _addTag,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              height: AppSpacing.largeButtonHeight,
              child: FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: const Text('保存修改')),
            ),
          ],
        ),
      ),
    ),
  );

  SpeciesCandidate? get _selectedCandidate {
    return _candidateForName(_species.text);
  }

  SpeciesCandidate? _candidateForName(String value) {
    for (final candidate in _candidates) {
      if (candidate.name == value.trim()) return candidate;
    }
    return null;
  }

  void _scheduleSearch(String value) {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () => _search(value));
  }

  Future<void> _search(String value) async {
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _candidates = widget.initialCandidates;
        _searchMessage = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _searchMessage = null;
    });
    try {
      final results = await BirdCompanionScope.of(context).photoRepository.searchSpecies(query);
      if (!mounted || _species.text.trim() != query) return;
      setState(() {
        _searching = false;
        _candidates = results;
        _searchMessage = results.isEmpty ? '没有找到匹配鸟种，可继续使用手动输入的名称。' : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchMessage = '暂时无法搜索鸟种，可选择原候选或手动输入。';
      });
    }
  }

  void _save() => Navigator.of(context).pop(
    ReviewEditResult(
      keepState: _keep,
      speciesId: _speciesId,
      species: _species.text.trim(),
      score: _score.text.trim(),
      tags: _tags.text.trim(),
    ),
  );

  List<String> get _tagValues => parseUserTags(_tags.text);

  void _removeTag(String value) => setState(() => _tags.text = _tagValues.where((tag) => tag != value).join(', '));

  Future<void> _addTag() async {
    var draft = '';
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('添加标签'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(hintText: '例如：湿地'),
          onChanged: (value) => draft = value,
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, draft.trim()), child: const Text('添加')),
        ],
      ),
    );
    if (value == null || value.isEmpty || !mounted) return;
    setState(() => _tags.text = normalizeUserTags([..._tagValues, ...parseUserTags(value)]).join(', '));
  }
}

class _CurrentResultCard extends StatelessWidget {
  const _CurrentResultCard({required this.uri, required this.species, this.candidate});

  final Uri uri;
  final String species;
  final SpeciesCandidate? candidate;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusImage),
            child: SizedBox(
              width: 112,
              height: 112,
              child: CachedNetworkImage(
                imageUrl: uri.toString(),
                fit: BoxFit.cover,
                placeholder: (_, _) => const ColoredBox(
                  color: AppColors.brandLight,
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                errorWidget: (_, _, _) => const ColoredBox(color: AppColors.brandLight, child: Icon(Icons.photo_outlined)),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(species.isEmpty ? '待确认鸟种' : species, style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: AppColors.brandDark)),
                if (candidate != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text('识别度：${UserFacingText.recognitionCertaintyWithPercent(candidate!.confidence)}', style: const TextStyle(color: AppColors.inkMuted)),
                ],
                const SizedBox(height: AppSpacing.sm),
                const Chip(label: Text('当前结果')),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({required this.candidate, required this.selected, required this.onTap});

  final SpeciesCandidate candidate;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    minVerticalPadding: AppSpacing.sm,
    leading: Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: AppColors.brand),
    title: Text(candidate.name),
    subtitle: Text('识别度：${UserFacingText.recognitionCertainty(candidate.confidence)}'),
    trailing: Text(
      '${(candidate.confidence * 100).round()}%',
      style: TextStyle(color: selected ? AppColors.brand : AppColors.inkMuted, fontWeight: FontWeight.w700),
    ),
    onTap: onTap,
  );
}
