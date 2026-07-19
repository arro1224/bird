import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/core/models/scene_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('照片扩展字段可从盒子契约解析并缓存往返', () {
    final photo = PhotoSummary.fromJson(const {
      'file_id': 'file-1',
      'filename': 'DSC_0001.NEF',
      'format': 'RAW',
      'analysis_state': 'completed',
      'scene_id': 'scene-1',
      'group_id': 'burst-1',
      'clarity_state': 'clear',
      'is_recommended': true,
      'recognition': {
        'species_topn': [
          {'species_id': 'alcedo-atthis', 'name': '普通翠鸟', 'confidence': .92},
        ],
      },
      'rating': {'total_score': 4.8, 'quality_score': 9.0, 'eye_score': 9.2, 'composition_score': 9.1},
    });

    expect(photo.sceneId, 'scene-1');
    expect(photo.clarityState, ClarityState.clear);
    expect(photo.isRecommended, isTrue);
    expect(photo.recognition!.candidates.single.speciesId, 'alcedo-atthis');
    expect(photo.rating!.eyeScore, 9.2);

    final restored = PhotoSummary.fromJson(photo.toJson());
    expect(restored, photo);
  });

  test('场景摘要保留封面、数量与拍摄时间', () {
    final scene = SceneSummary.fromJson(const {
      'scene_id': 'scene-1',
      'project_id': 'batch-1',
      'name': '清晨芦苇荡',
      'photo_count': 1284,
      'burst_group_count': 22,
      'captured_from': '2026-07-16T06:12:00Z',
      'captured_to': '2026-07-16T07:18:00Z',
      'cover': {'thumb_ref': 'http://bird-box.local/thumb/1'},
    });

    expect(scene.photoCount, 1284);
    expect(scene.burstGroupCount, 22);
    expect(scene.cover!.thumbnailUri.toString(), 'http://bird-box.local/thumb/1');
    expect(SceneSummary.fromJson(scene.toJson()), scene);
  });

  test('batch prefers pending_review_count while keeping legacy firmware compatibility', () {
    final batch = BatchSummary.fromJson(const {
      'project_id': 'batch-1',
      'name': '2026.07.16 崇明东滩',
      'created_at': '2026-07-16T06:12:00Z',
      'total_files': 3672,
      'analyzed_count': 2384,
      'pending_review_count': 1284,
      'review_count': 999,
      'keep_count': 2012,
      'discard_count': 376,
      'pending_copy_count': 0,
      'copy_state': 'idle',
    });

    expect(batch.pendingReviewCount, 1284);
    expect(batch.toJson()['pending_review_count'], 1284);
    expect(batch.toJson()['review_count'], 1284);
  });

  test('manual species decision preserves the stable species id', () {
    final decision = UserDecision.fromJson(const {
      'file_id': 'file-1',
      'keep_state': 'keep',
      'user_species_id': 'alcedo-atthis',
      'user_species': '普通翠鸟',
      'user_tags': ['清晰'],
      'version': 7,
    });

    expect(decision.userSpeciesId, 'alcedo-atthis');
    expect(decision.toJson()['user_species_id'], 'alcedo-atthis');
    expect(UserDecision.fromJson(decision.toJson()), decision);
  });
}
