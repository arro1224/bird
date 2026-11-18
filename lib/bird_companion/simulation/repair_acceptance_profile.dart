/// Opt-in November repair data. The generic demonstration remains unchanged.
enum RepairAcceptanceProfile {
  repair110('repair-110', 38, 40, 8, 16, 8),
  repair14('repair-14', 5, 5, 1, 2, 1);

  const RepairAcceptanceProfile(this.id, this.high, this.medium, this.unknown, this.blurry, this.tooSmall);
  final String id;
  final int high, medium, unknown, blurry, tooSmall;
  int get total => high + medium + unknown + blurry + tooSmall;
  int get needsReview => medium + unknown;
  int get filtered => blurry + tooSmall;
  String get manualSpeciesFileId => fileId(high + 1);
  static String fileId(int sequence) => 'photo-${sequence.toString().padLeft(4, '0')}';

  static RepairAcceptanceProfile? parse(String value) {
    if (value.isEmpty || value == 'demo') return null;
    return values.firstWhere((profile) => profile.id == value, orElse: () => throw FormatException('Unknown repair acceptance profile: $value'));
  }

  String verdict(int index) {
    if (index < high) return 'high';
    if (index < high + medium) return 'medium';
    if (index < high + medium + unknown) return 'unknown';
    if (index < high + medium + unknown + blurry) return 'blurry';
    return 'too_small';
  }

  Map<String, dynamic> seed(Map<String, dynamic> photo, int index) {
    final result = verdict(index);
    final hasCandidates = result == 'high' || result == 'medium';
    final raw = index < (total * .68).round();
    return {
      ...photo,
      'filename': 'DSC_${(index + 1).toString().padLeft(4, '0')}.${raw ? 'ARW' : 'JPG'}',
      'format': raw ? 'RAW' : 'JPEG',
      'analysis_state': result == 'blurry' || result == 'too_small' ? 'skipped' : 'completed',
      'recognition': {
        'verdict': result,
        'top1_class': hasCandidates ? 'Alcedo_atthis' : null,
        'species_topn': hasCandidates
            ? [
                {'species_id': 'common-kingfisher', 'name': '普通翠鸟', 'english_name': 'Common Kingfisher', 'scientific_name': 'Alcedo atthis', 'confidence': result == 'high' ? .94 : .42},
                {'species_id': 'little-egret', 'name': '白鹭', 'english_name': 'Little Egret', 'scientific_name': 'Egretta garzetta', 'confidence': result == 'high' ? .04 : .37},
              ]
            : <Map<String, dynamic>>[],
        // Filtered records deliberately have low_confidence too: that flag
        // alone cannot implement the recognition category contract.
        'low_confidence': result != 'high',
        'model_version': 'repair-acceptance-fixture-v1',
      },
      'clarity_state': result == 'blurry' ? 'blurred' : 'clear',
      'keep_state': 'pending',
      'user_tags': <String>[],
      'version': 0,
    };
  }

  static bool recognized(Map<String, dynamic> photo) {
    final recognition = photo['recognition'] as Map;
    return photo['analysis_state'] == 'completed' && recognition['verdict'] == 'high' && (recognition['top1_class'] as String?)?.isNotEmpty == true;
  }

  static bool requiresReview(Map<String, dynamic> photo) => photo['analysis_state'] == 'completed' && const {'medium', 'unknown'}.contains((photo['recognition'] as Map)['verdict']);
}
