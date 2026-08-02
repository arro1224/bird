import 'package:aves/bird_companion/core/files/media_cache_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('signed URL refresh keeps media identity stable', () {
    final first = mediaCacheIdentity(
      uri: Uri.parse(
        'http://box.local/media/photo-7.jpg?expires=100&signature=one',
      ),
      mediaId: 'photo-7',
      variant: 'preview',
      deviceNamespace: 'box-a',
    );
    final refreshed = mediaCacheIdentity(
      uri: Uri.parse(
        'http://box.local/media/photo-7.jpg?expires=200&signature=two',
      ),
      mediaId: 'photo-7',
      variant: 'preview',
      deviceNamespace: 'box-a',
    );

    expect(refreshed, first);
    expect(first, isNot(contains('signature')));
  });

  test('same project and file on different devices never share media cache', () {
    final uri = Uri.parse('http://box.local/media/photo-7.jpg?signature=x');
    final boxA = mediaCacheIdentity(
      uri: uri,
      mediaId: 'photo-7',
      variant: 'preview',
      deviceNamespace: 'box-a',
    );
    final boxB = mediaCacheIdentity(
      uri: uri,
      mediaId: 'photo-7',
      variant: 'preview',
      deviceNamespace: 'box-b',
    );

    expect(boxA, isNot(boxB));
  });
}
