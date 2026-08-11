import 'dart:async';

import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_repository.dart';
import 'package:aves/bird_companion/features/copy/presentation/copy_confirmation_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('B2 copy estimate contract', () {
    test('parses the stable target id and estimate version', () {
      final estimate = CopyEstimate.fromJson(
        _estimateJson(mode: 'keep', version: 8),
        requestedMode: 'keep',
      );

      expect(estimate.mode, 'keep');
      expect(estimate.version, 8);
      expect(estimate.targets.single.id, 'disk-stable-1');
    });

    test('does not invent a version or stable target id', () {
      final missingVersion = _estimateJson(mode: 'keep', version: 8)..remove('version');
      final missingTargetId = _estimateJson(mode: 'keep', version: 8);
      (missingTargetId['targets'] as List).single.remove('id');

      expect(
        () => CopyEstimate.fromJson(
          missingVersion,
          requestedMode: 'keep',
        ),
        throwsA(
          isA<ProtocolCompatibilityException>().having(
            (error) => error.field,
            'field',
            'version',
          ),
        ),
      );
      expect(
        () => CopyEstimate.fromJson(
          missingTargetId,
          requestedMode: 'keep',
        ),
        throwsA(isA<ProtocolCompatibilityException>()),
      );
    });

    test('rejects an estimate for a different copy mode', () {
      expect(
        () => CopyEstimate.fromJson(
          _estimateJson(mode: 'all', version: 2),
          requestedMode: 'keep',
        ),
        throwsA(
          isA<ProtocolCompatibilityException>().having(
            (error) => error.field,
            'field',
            'mode',
          ),
        ),
      );
    });
  });

  group('B2 copy flow state', () {
    test('a stale estimate cannot overwrite the latest mode', () async {
      final keep = Completer<CopyEstimate>();
      final all = Completer<CopyEstimate>();
      final repository = _CopyRepository(
        onEstimate: (_, mode) => mode == 'keep' ? keep.future : all.future,
      );
      final cubit = CopyConfirmationCubit(repository, 'project-1');
      addTearDown(cubit.close);

      final staleLoad = cubit.load('keep');
      final latestLoad = cubit.load('all');
      all.complete(_estimate(mode: 'all', version: 4));
      await latestLoad;
      keep.complete(_estimate(mode: 'keep', version: 3));
      await staleLoad;

      expect(cubit.state.mode, 'all');
      expect(cubit.state.estimate?.mode, 'all');
      expect(cubit.state.estimate?.version, 4);
    });

    test('a mode refresh clears a target that is no longer usable', () async {
      var calls = 0;
      final repository = _CopyRepository(
        onEstimate: (_, mode) async {
          calls++;
          return calls == 1
              ? _estimate(mode: mode, version: 1)
              : _estimate(
                  mode: mode,
                  version: 2,
                  targetOnline: false,
                );
        },
      );
      final cubit = CopyConfirmationCubit(repository, 'project-1');
      addTearDown(cubit.close);

      await cubit.load();
      expect(cubit.state.targetId, 'disk-stable-1');
      await cubit.load('all');

      expect(cubit.state.mode, 'all');
      expect(cubit.state.targetId, isNull);
      expect(cubit.state.submissionBlockReason, isNotNull);
    });

    test('submit re-estimates and requires reselection if target changed', () async {
      var calls = 0;
      final repository = _CopyRepository(
        onEstimate: (_, mode) async {
          calls++;
          return _estimate(
            mode: mode,
            version: calls,
            targetOnline: calls == 1,
          );
        },
      );
      final cubit = CopyConfirmationCubit(repository, 'project-1');
      addTearDown(cubit.close);

      await cubit.load();
      await cubit.submit();

      expect(repository.estimateCalls, 2);
      expect(repository.createCalls, 0);
      expect(cubit.state.estimate?.version, 2);
      expect(cubit.state.targetId, isNull);
      expect(cubit.state.error, isA<StateError>());
    });

    test('a double tap creates only one copy job with the fresh version', () async {
      final create = Completer<BirdJobStatus>();
      var version = 10;
      final repository = _CopyRepository(
        onEstimate: (_, mode) async => _estimate(
          mode: mode,
          version: version++,
        ),
        onCreate: () => create.future,
      );
      final cubit = CopyConfirmationCubit(
        repository,
        'project-1',
        null,
        'keep',
        null,
        false,
        true,
      );
      addTearDown(cubit.close);

      await cubit.load();
      final firstSubmit = cubit.submit();
      final duplicateSubmit = cubit.submit();
      await duplicateSubmit;

      expect(repository.estimateCalls, 2);
      expect(repository.createCalls, 1);
      expect(repository.createdVersion, 11);
      expect(repository.createdTargetId, 'disk-stable-1');
      expect(repository.createdXmpEnabled, isFalse);
      expect(repository.createdVerifyAfterCopy, isTrue);

      create.complete(
        const BirdJobStatus(
          id: 'job-copy-b2',
          type: BirdJobType.copy,
          state: BirdJobState.queued,
        ),
      );
      await firstSubmit;
      expect(cubit.state.jobId, 'job-copy-b2');
    });
  });
}

Map<String, dynamic> _estimateJson({
  required String mode,
  required int version,
}) => <String, dynamic>{
  'mode': mode,
  'file_count': 12,
  'required_bytes': 1024,
  'pending_count': 2,
  'version': version,
  'targets': <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'disk-stable-1',
      'name': 'Backup SSD',
      'free_bytes': 4096,
      'total_bytes': 8192,
      'online': true,
    },
  ],
};

CopyEstimate _estimate({
  required String mode,
  required int version,
  bool targetOnline = true,
}) => CopyEstimate(
  mode: mode,
  fileCount: 12,
  requiredBytes: 1024,
  pendingCount: 2,
  version: version,
  targets: <StorageTarget>[
    StorageTarget(
      id: 'disk-stable-1',
      name: 'Backup SSD',
      freeBytes: 4096,
      totalBytes: 8192,
      online: targetOnline,
    ),
  ],
);

class _CopyRepository implements CopyRepository {
  _CopyRepository({required this.onEstimate, this.onCreate});

  final Future<CopyEstimate> Function(String projectId, String mode) onEstimate;
  final Future<BirdJobStatus> Function()? onCreate;
  int estimateCalls = 0;
  int createCalls = 0;
  String? createdTargetId;
  bool? createdXmpEnabled;
  bool? createdVerifyAfterCopy;
  int? createdVersion;

  @override
  Future<CopyEstimate> estimate(String batchId, String mode) {
    estimateCalls++;
    return onEstimate(batchId, mode);
  }

  @override
  Future<BirdJobStatus> create(
    String batchId,
    String mode,
    String targetId, {
    required bool xmpEnabled,
    required bool verifyAfterCopy,
    required int version,
  }) {
    createCalls++;
    createdTargetId = targetId;
    createdXmpEnabled = xmpEnabled;
    createdVerifyAfterCopy = verifyAfterCopy;
    createdVersion = version;
    return onCreate?.call() ??
        Future<BirdJobStatus>.value(
          const BirdJobStatus(
            id: 'job-copy-b2',
            type: BirdJobType.copy,
            state: BirdJobState.queued,
          ),
        );
  }
}
