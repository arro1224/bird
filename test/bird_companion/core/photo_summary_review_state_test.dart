import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('photo list preserves review state returned after a batch operation', () {
    final photo = PhotoSummary.fromJson({
      'file_id': 'photo-1',
      'filename': 'DSC_0001.NEF',
      'format': 'RAW',
      'analysis_state': 'completed',
      'keep_state': 'keep',
      'user_tags': ['水鸟', '晨拍'],
    });

    expect(photo.keepState, 'keep');
    expect(photo.userTags, ['水鸟', '晨拍']);
  });
}
