import 'package:aves/bird_companion/features/gallery/domain/photo_query.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('组合筛选生成稳定的请求参数并可保留游标翻页', () {
    const query = PhotoQuery(
      species: '白鹭',
      search: 'IMG_7821',
      minScore: 8,
      minConfidence: .8,
      tags: ['水鸟'],
      keepState: 'keep',
      analysisState: 'completed',
      clarityState: 'clear',
      recognitionState: 'recognized',
      recommendedOnly: true,
      sceneId: 'scene-1',
    );
    expect(query.parameters['species'], '白鹭');
    expect(query.parameters['min_score'], 8);
    expect(query.parameters['search'], 'IMG_7821');
    expect(query.parameters['clarity_state'], 'clear');
    expect(query.parameters['recognition_state'], 'recognized');
    expect(query.parameters['scene_id'], 'scene-1');
    expect(query.parameters['recommended_only'], isTrue);
    expect(query.next('60').parameters['cursor'], '60');
    expect(query.activeLabels, contains('鸟种：白鹭'));
    expect(query.activeLabels, contains('搜索：IMG_7821'));
    expect(PhotoQuery.fromJson(query.toJson()).parameters, query.copyWith(clearCursor: true).parameters);
  });
}
