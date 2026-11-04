import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_gateway.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'finish/completion_fixtures.dart';
import 'finish/metadata_fixtures.dart';

class ReplayBackend extends CompletionBackend implements SmartFollowEventGateway {
  ReplayBackend() {
    data['event_seq'] = 3;
  }
  bool wrong = false;
  final after = <int>[];
  @override
  Future<Map<String, dynamic>> sessionEvents(String sessionId, {required int afterEventSeq}) async {
    after.add(afterEventSeq);
    final next = afterEventSeq < 3 ? afterEventSeq + 1 : afterEventSeq;
    return {
      'session_id': sessionId,
      'items': afterEventSeq < 3
          ? [
              {'session_id': wrong ? 'other-task' : sessionId, 'event_seq': next},
            ]
          : [],
      'has_more': next < 3,
      'next_event_seq': next,
      'last_event_seq': 3,
    };
  }
}

void main() {
  test('durable event cursor survives repository restart and is isolated by device', () async {
    final backend = ReplayBackend(), store = MetadataStore();
    var device = 'box-a';
    SmartFollowRepository create() => SmartFollowRepository(backend, metadataStorage: store, metadataDeviceId: () => device);
    final first = create();
    await first.refresh('sf_fake');
    expect(backend.after, [0, 1, 2]);
    first.dispose();
    final restored = create();
    await restored.refresh('sf_fake');
    expect(backend.after.last, 3);
    device = 'box-b';
    restored.resetForDeviceChange();
    await restored.refresh('sf_fake');
    expect(backend.after.sublist(4), [0, 1, 2]);
    restored.dispose();
  });
  test('wrong task event does not advance persisted cursor', () async {
    final backend = ReplayBackend()..wrong = true;
    final store = MetadataStore();
    final repository = SmartFollowRepository(backend, metadataStorage: store, metadataDeviceId: () => 'box-a');
    await expectLater(repository.refresh('sf_fake'), throwsStateError);
    expect(store.values, isEmpty);
    repository.dispose();
  });
}
