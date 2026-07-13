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
  late final TextEditingController _species = TextEditingController(text: widget.initial.species);
  late final TextEditingController _score = TextEditingController(text: widget.initial.minScore?.toString() ?? '');
  late final TextEditingController _confidence = TextEditingController(text: widget.initial.minConfidence?.toString() ?? '');
  late final TextEditingController _tags = TextEditingController(text: widget.initial.tags.join(', '));
  String? _keep;
  String? _analysis;
  @override
  void initState() {
    super.initState();
    _keep = widget.initial.keepState;
    _analysis = widget.initial.analysisState;
  }

  @override
  void dispose() {
    _species.dispose();
    _score.dispose();
    _confidence.dispose();
    _tags.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text('筛选照片', style: Theme.of(context).textTheme.titleLarge),
          TextField(
            controller: _species,
            decoration: const InputDecoration(labelText: '鸟种名称'),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _score,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '最低评分'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _confidence,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '最低置信度（0-1）'),
                ),
              ),
            ],
          ),
          TextField(
            controller: _tags,
            decoration: const InputDecoration(labelText: '标签（以逗号分隔）'),
          ),
          DropdownButtonFormField<String>(
            value: _keep,
            decoration: const InputDecoration(labelText: '保留状态'),
            items: const [
              DropdownMenuItem(value: 'pending', child: Text('待审')),
              DropdownMenuItem(value: 'keep', child: Text('保留')),
              DropdownMenuItem(value: 'discard', child: Text('淘汰')),
              DropdownMenuItem(value: 'featured', child: Text('精选')),
            ],
            onChanged: (v) => setState(() => _keep = v),
          ),
          DropdownButtonFormField<String>(
            value: _analysis,
            decoration: const InputDecoration(labelText: '分析状态'),
            items: const [
              DropdownMenuItem(value: 'completed', child: Text('已完成')),
              DropdownMenuItem(value: 'processing', child: Text('分析中')),
              DropdownMenuItem(value: 'low_confidence', child: Text('低置信度')),
              DropdownMenuItem(value: 'failed', child: Text('失败')),
            ],
            onChanged: (v) => setState(() => _analysis = v),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              widget.onApply(
                PhotoQuery(
                  sort: widget.initial.sort,
                  species: _species.text.trim().isEmpty ? null : _species.text.trim(),
                  minScore: double.tryParse(_score.text),
                  minConfidence: double.tryParse(_confidence.text),
                  tags: _tags.text.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty).toList(),
                  keepState: _keep,
                  analysisState: _analysis,
                  groupId: widget.initial.groupId,
                ),
              );
              Navigator.pop(context);
            },
            child: const Text('应用筛选'),
          ),
        ],
      ),
    ),
  );
}
