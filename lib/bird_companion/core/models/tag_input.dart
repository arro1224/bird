/// Normalizes user-entered tags without imposing a product-specific limit.
/// Limits belong to the box contract; this helper only removes ambiguity from
/// common mobile input forms.
List<String> parseUserTags(String value) => normalizeUserTags(value.split(RegExp(r'[,，\n]')));

List<String> normalizeUserTags(Iterable<String> values) {
  final seen = <String>{};
  final result = <String>[];
  for (final value in values) {
    final tag = value.trim();
    if (tag.isNotEmpty && seen.add(tag)) result.add(tag);
  }
  return result;
}
