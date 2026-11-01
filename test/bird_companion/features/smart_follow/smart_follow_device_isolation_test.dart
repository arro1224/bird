import 'dart:async';

import 'package:aves/bird_companion/features/smart_follow/data/fake_smart_follow_backend.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';
import 'package:flutter_test/flutter_test.dart';

class DelayedFollowBackend extends FakeSmartFollowBackend {
  Completer<SmartFollowSession>? sessionGate, startGate;
  Completer<String?>? lookupGate;
  Completer<SmartFollowCapabilities>? capabilityGate;
  @override
  Future<SmartFollowSession> session(String sessionId) => sessionGate?.future ?? super.session(sessionId);
  @override
  Future<String?> sessionIdForRecognitionJob(String recognitionJobId) => lookupGate?.future ?? super.sessionIdForRecognitionJob(recognitionJobId);
  @override
  Future<SmartFollowCapabilities> capabilities() => capabilityGate?.future ?? super.capabilities();
  @override
  Future<SmartFollowSession> startOnRecognitionJob(String recognitionJobId, SmartFollowStartRequest request, {String? idempotencyKey}) =>
      startGate?.future ?? super.startOnRecognitionJob(recognitionJobId, request, idempotencyKey: idempotencyKey);
}

const request = SmartFollowStartRequest(targetMediaId: 'usb', reviewExportEnabled: false);

void main() {
  test('late session response cannot repopulate caches after a device reset', () async {
    final backend = DelayedFollowBackend()..start();
    final repository = SmartFollowRepository(backend);
    addTearDown(repository.dispose);
    backend.sessionGate = Completer();
    final old = repository.refresh('sf_fake');
    final assertion = expectLater(old, throwsStateError);
    repository.resetForDeviceChange();
    backend.sessionGate!.complete(backend.current);
    await assertion;
    expect(repository.snapshot('sf_fake'), isNull);
    expect(repository.sessionIdForJob('rec_fake'), isNull);
  });

  test('old completion cannot remove a new device refresh with the same ID', () async {
    final backend = DelayedFollowBackend()..start();
    final repository = SmartFollowRepository(backend);
    addTearDown(repository.dispose);
    final firstGate = Completer<SmartFollowSession>();
    backend.sessionGate = firstGate;
    final first = repository.refresh('sf_fake');
    final assertion = expectLater(first, throwsStateError);
    repository.resetForDeviceChange();
    final secondGate = Completer<SmartFollowSession>();
    backend.sessionGate = secondGate;
    final second = repository.refresh('sf_fake');
    firstGate.complete(backend.current);
    await assertion;
    final third = repository.refresh('sf_fake');
    secondGate.complete(backend.current);
    expect((await second).sessionId, 'sf_fake');
    expect((await third).sessionId, 'sf_fake');
  });

  test('late capability response cannot enable another box', () async {
    final backend = DelayedFollowBackend();
    final repository = SmartFollowRepository(backend);
    addTearDown(repository.dispose);
    backend.capabilityGate = Completer();
    final request = repository.capabilities();
    final assertion = expectLater(request, throwsStateError);
    repository.resetForDeviceChange();
    backend.capabilityGate!.complete(const SmartFollowCapabilities(incrementalRecognition: true, copy: SmartFollowCapability(available: true), metadataUpdate: true));
    await assertion;
    expect(repository.cachedCapabilities, isNull);
  });

  test('device change during recovery prevents a POST on the new box', () async {
    final backend = DelayedFollowBackend();
    final repository = SmartFollowRepository(backend);
    addTearDown(repository.dispose);
    backend.lookupGate = Completer();
    final creation = repository.startOnRecognitionJob('rec_fake', request);
    final assertion = expectLater(creation, throwsStateError);
    repository.resetForDeviceChange();
    backend.lookupGate!.complete(null);
    await assertion;
    expect(backend.startCalls, 0);
  });

  test('late create response is not merged after switching boxes', () async {
    final backend = DelayedFollowBackend();
    final repository = SmartFollowRepository(backend);
    addTearDown(repository.dispose);
    backend.startGate = Completer();
    final creation = repository.startOnRecognitionJob('rec_fake', request);
    final assertion = expectLater(creation, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    repository.resetForDeviceChange();
    backend.startGate!.complete(backend.current);
    await assertion;
    expect(repository.snapshot('sf_fake'), isNull);
  });

  test('same job concurrent creation is shared and unresolved parameters stay frozen', () async {
    final backend = DelayedFollowBackend();
    final repository = SmartFollowRepository(backend);
    addTearDown(repository.dispose);
    backend.startGate = Completer();
    final first = repository.startOnRecognitionJob('rec_fake', request);
    final second = repository.startOnRecognitionJob('rec_fake', request);
    expect(identical(first, second), isTrue);
    expect(() => repository.startOnRecognitionJob('rec_fake', const SmartFollowStartRequest(targetMediaId: 'other', reviewExportEnabled: false)), throwsStateError);
    backend.startGate!.complete(backend.current);
    await Future.wait([first, second]);
  });
}
