import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('serializes unchanged, clear and value as three distinct states', () {
    const patch = UserDecisionPatch(
      fileId: 'photo-7',
      keepState: PatchField.value(KeepState.keep),
      userScore: PatchField.unchanged(),
      userSpeciesId: PatchField.clear(),
      userTags: PatchField.clear(),
      version: 4,
    );

    expect(patch.toJson(), {
      'keep_state': 'keep',
      'user_species_id': null,
      'user_tags': const <String>[],
      'version': 4,
    });
  });

  test('diff omits untouched fields without clearing them', () {
    const before = UserDecision(
      fileId: 'photo-7',
      keepState: KeepState.keep,
      userSpecies: '翠鸟',
      userTags: ['河岸'],
      version: 3,
    );
    const after = UserDecision(
      fileId: 'photo-7',
      keepState: KeepState.featured,
      userSpecies: '翠鸟',
      userTags: [],
      version: 3,
    );

    final json = UserDecisionPatch.diff(before, after).toJson();

    expect(json['keep_state'], 'featured');
    expect(json.containsKey('user_species'), isFalse);
    expect(json['user_tags'], isEmpty);
    expect(json['version'], 3);
  });
}
