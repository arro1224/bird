import 'dart:async';
import 'package:aves/bird_companion/core/network/api_exception.dart';

import 'package:aves/bird_companion/features/jobs/domain/job_page.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_configuration_controller.dart';
import 'package:aves/bird_companion/features/smart_follow/presentation/entry/smart_follow_creation_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'creation_fixtures.dart';
import 'configuration_fixtures.dart';

void main() {
  test('429 preserves the atomic intent and its key across service restart', () async {
    final env = CreationEnvironment(atomic: true);
    addTearDown(env.follows.dispose);
    final intent = await env.intent();
    env.jobs.createError = const ApiException(message: 'rate limited', statusCode: 429);
    await expectLater(env.service.start(intent, env.reader()), throwsA(isA<SmartFollowCreationPending>()));
    expect(env.service.hasPending('batch-1'), isTrue);
    final key = env.jobs.requests.single.idempotencyKey;
    env.jobs.createError = null;
    await env.newService().start(intent, env.reader());
    expect(env.jobs.requests.last.idempotencyKey, key);
  });
  test('a retry cannot silently replace the source card of the original request', () async {
    final env = CreationEnvironment(atomic: true);
    addTearDown(env.follows.dispose);
    final intent = await env.intent();
    env.jobs.timeoutBeforeCommit = true;
    await expectLater(env.service.start(intent, env.reader()), throwsA(isA<SmartFollowCreationPending>()));
    final json = intent.toLocalJson()..['source'] = 'different-card';
    await expectLater(env.newService().start(SmartFollowConfiguredIntent.fromLocalJson(json), env.reader()), throwsA(isA<SmartFollowCreationPending>()));
    expect(env.jobs.requests, hasLength(1));
  });

  test('an atomic recovery candidate with the wrong target stays unresolved', () async {
    final env = CreationEnvironment(atomic: true);
    addTearDown(env.follows.dispose);
    final json = (await env.intent()).toLocalJson();
    (json['request'] as Map)['target_media_id'] = 'different-target';
    env.configuration.devices[1] = configDevice('different-target');
    await expectLater(env.service.start(SmartFollowConfiguredIntent.fromLocalJson(json), env.reader()), throwsA(isA<SmartFollowCreationPending>()));
    expect(env.jobs.requests, hasLength(1));
    expect(env.service.hasPending('batch-1'), isTrue);
  });

  test('an unresolved follow cannot be discarded to start a separate recognition', () async {
    final env = CreationEnvironment(atomic: true);
    addTearDown(env.follows.dispose);
    await env.service.stageForBatch('batch-1', await env.intent());
    await env.service.discardStaged('batch-1');
    expect(env.service.hasStaged('batch-1'), isFalse);
    env.jobs.timeoutBeforeCommit = true;
    await expectLater(env.service.start(await env.intent(), env.reader()), throwsA(isA<SmartFollowCreationPending>()));
    await expectLater(env.newService().discardStaged('batch-1'), throwsA(isA<SmartFollowCreationPending>()));
    expect(env.jobs.requests, hasLength(1));
  });

  test('a different batch reader or widened eligibility cannot submit the frozen intent', () async {
    final env = CreationEnvironment(atomic: true);
    addTearDown(env.follows.dispose);
    final intent = await env.intent();
    final json = intent.toLocalJson();
    (json['request'] as Map)['eligibility_mode'] = 'all_assets';
    await expectLater(env.service.start(SmartFollowConfiguredIntent.fromLocalJson(json), env.reader()), throwsStateError);
    await expectLater(env.service.start(intent.forBatch('other'), env.reader()), throwsStateError);
    expect(env.jobs.requests, isEmpty);
  });

  test('atomic path posts analysis with full DTO and a transport-only stable key', () async {
    final env = CreationEnvironment(atomic: true);
    addTearDown(env.follows.dispose);
    final intent = await env.intent();
    final session = await env.service.start(intent, env.reader());
    expect(session.sessionId, 'sf-1');
    expect(env.jobs.requests.single.toJson(), {'mode': 'standard', 'include_grouping': true, 'smart_follow': intent.request.toJson()});
    expect(env.jobs.requests.single.idempotencyKey, startsWith('sf-atomic-'));
    expect(env.backend.startCalls, 0); // No second sequential follow-create POST.
    expect(env.service.hasPending('batch-1'), isFalse);
  });

  test('running path uses the existing recognition job only', () async {
    final env = CreationEnvironment();
    addTearDown(env.follows.dispose);
    final session = await env.service.start(await env.intent(), env.reader());
    expect(session.recognitionJobId, 'rec-1');
    expect(env.jobs.requests, isEmpty);
    expect(env.backend.startCalls, 1);
  });

  test('concurrent clicks share one atomic creation', () async {
    final env = CreationEnvironment(atomic: true);
    addTearDown(env.follows.dispose);
    env.jobs.createGate = Completer<void>();
    final intent = await env.intent();
    final first = env.service.start(intent, env.reader());
    final second = env.service.start(intent, env.reader());
    expect(identical(first, second), isTrue);
    env.jobs.createGate!.complete();
    await Future.wait([first, second]);
    expect(env.jobs.requests, hasLength(1));
  });

  test('response lost after commit recovers through jobs and session without reposting', () async {
    final env = CreationEnvironment(atomic: true);
    addTearDown(env.follows.dispose);
    env.jobs.timeoutAfterCommit = true;
    final session = await env.service.start(await env.intent(), env.reader());
    expect(session.sessionId, 'sf-1');
    expect(env.jobs.requests, hasLength(1));
    expect(env.backend.startCalls, 0);
  });

  test('unknown result survives service recreation and reuses exactly the original key/body', () async {
    final env = CreationEnvironment(atomic: true);
    addTearDown(env.follows.dispose);
    final intent = await env.intent();
    env.jobs.timeoutBeforeCommit = true;
    await expectLater(env.service.start(intent, env.reader()), throwsA(isA<SmartFollowCreationPending>()));
    expect(env.service.hasPending('batch-1'), isTrue);
    final original = env.jobs.requests.single;
    env.jobs.timeoutBeforeCommit = false;
    await env.newService().start(intent, env.reader());
    expect(env.jobs.requests, hasLength(2));
    expect(env.jobs.requests.last.idempotencyKey, original.idempotencyKey);
    expect(env.jobs.requests.last.toJson(), original.toJson());
  });

  test('unknown original intent cannot be replaced by changed copy parameters', () async {
    final env = CreationEnvironment(atomic: true);
    addTearDown(env.follows.dispose);
    final intent = await env.intent();
    env.jobs.timeoutBeforeCommit = true;
    await expectLater(env.service.start(intent, env.reader()), throwsA(isA<SmartFollowCreationPending>()));
    final json = intent.toLocalJson();
    (json['request'] as Map)['conflict_strategy'] = 'overwrite';
    final changed = SmartFollowConfiguredIntent.fromLocalJson(json);
    await expectLater(env.newService().start(changed, env.reader()), throwsA(isA<SmartFollowCreationPending>()));
    expect(env.jobs.requests, hasLength(1));
  });

  test('query-only recovery never sends a create request', () async {
    final env = CreationEnvironment(atomic: true);
    addTearDown(env.follows.dispose);
    env.jobs.timeoutBeforeCommit = true;
    await expectLater(env.service.start(await env.intent(), env.reader()), throwsA(isA<SmartFollowCreationPending>()));
    await expectLater(env.newService().recover('batch-1'), throwsA(isA<SmartFollowCreationPending>()));
    expect(env.jobs.requests, hasLength(1));
    env.jobs.rows.add(env.job(session: 'sf-1'));
    env.backend.start();
    expect((await env.newService().recover('batch-1')).sessionId, 'sf-1');
    expect(env.jobs.requests, hasLength(1));
  });

  test('ambiguous recovery or incomplete pagination never permits a blind repost', () async {
    final env = CreationEnvironment(atomic: true);
    addTearDown(env.follows.dispose);
    env.jobs.timeoutBeforeCommit = true;
    final intent = await env.intent();
    await expectLater(env.service.start(intent, env.reader()), throwsA(isA<SmartFollowCreationPending>()));
    env.jobs.rows.addAll([env.job(), env.job(id: 'rec-2')]);
    await expectLater(env.newService().start(intent, env.reader()), throwsA(isA<SmartFollowCreationPending>()));
    env.jobs.readPage = (_) async => JobPage(items: [env.job()], hasMore: true, nextCursor: 'same');
    await expectLater(env.newService().start(intent, env.reader()), throwsA(isA<SmartFollowCreationPending>()));
    expect(env.jobs.requests, hasLength(1));
  });

  test('existing external session is adopted without another POST', () async {
    final env = CreationEnvironment();
    addTearDown(env.follows.dispose);
    env.backend.start();
    final session = await env.service.start(await env.intent(), env.reader());
    expect(session.sessionId, 'sf-1');
    expect(env.backend.startCalls, 0);
    expect(env.jobs.requests, isEmpty);
  });

  test('expired confirmation or changed target free space requires reconfirmation', () async {
    for (final expired in [true, false]) {
      final env = CreationEnvironment(atomic: true);
      final intent = await env.intent();
      final json = intent.toLocalJson();
      if (expired) json['expires'] = DateTime.now().subtract(const Duration(minutes: 1)).toIso8601String();
      if (!expired) env.configuration.devices[1] = configDevice('media_usb_fake', free: 1);
      await expectLater(env.service.start(SmartFollowConfiguredIntent.fromLocalJson(json), env.reader()), throwsStateError);
      expect(env.jobs.requests, isEmpty);
      env.follows.dispose();
    }
  });

  test('device switch during configuration read cannot create on the new box', () async {
    final env = CreationEnvironment(atomic: true);
    addTearDown(env.follows.dispose);
    final intent = await env.intent();
    final pending = Completer<SmartFollowConfigurationSnapshot>();
    env.configuration.pending = () => pending.future;
    final request = env.service.start(intent, env.reader());
    env.context = 'box-2|http://box2';
    pending.complete(env.configuration.snapshot());
    await expectLater(request, throwsStateError);
    expect(env.jobs.requests, isEmpty);
  });

  test('failed durable intent write prevents POST', () async {
    final env = CreationEnvironment(atomic: true);
    addTearDown(env.follows.dispose);
    final intent = await env.intent();
    env.cache.failWrites = true;
    await expectLater(env.service.start(intent, env.reader()), throwsStateError);
    expect(env.jobs.requests, isEmpty);
  });

  test('staged pre-import confirmation is batch-bound and still revalidated', () async {
    final env = CreationEnvironment(atomic: true);
    addTearDown(env.follows.dispose);
    await env.service.stageForBatch('batch-1', await env.intent());
    expect(env.service.hasStaged('batch-1'), isTrue);
    env.configuration.available = false;
    await expectLater(env.newService().startStaged('batch-1', env.reader()), throwsStateError);
    expect(env.jobs.requests, isEmpty);
    env.configuration.available = true;
    await expectLater(env.newService().startStaged('batch-1', env.reader()), throwsStateError);
    expect(env.jobs.requests, isEmpty); // No automatic re-POST after a failed attempt.
    expect((await env.newService().start(await env.intent(), env.reader())).sessionId, 'sf-1');
  });

  test('automatic deferred retry queries an unknown request without posting again', () async {
    final env = CreationEnvironment(atomic: true);
    addTearDown(env.follows.dispose);
    await env.service.stageForBatch('batch-1', await env.intent());
    env.jobs.timeoutBeforeCommit = true;
    await expectLater(env.service.startStaged('batch-1', env.reader()), throwsA(isA<SmartFollowCreationPending>()));
    await expectLater(env.newService().startStaged('batch-1', env.reader()), throwsA(isA<SmartFollowCreationPending>()));
    expect(env.jobs.requests, hasLength(1));
  });

  test('existing recognition without a discoverable atomic session stays unknown', () async {
    final env = CreationEnvironment(atomic: true);
    addTearDown(env.follows.dispose);
    final intent = await env.intent();
    env.jobs.timeoutBeforeCommit = true;
    await expectLater(env.service.start(intent, env.reader()), throwsA(isA<SmartFollowCreationPending>()));
    env.jobs.rows.add(env.job());
    await expectLater(env.newService().start(intent, env.reader()), throwsA(isA<SmartFollowCreationPending>()));
    expect(env.jobs.requests, hasLength(1));
  });
}
