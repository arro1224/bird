import 'dart:async';
import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/features/smart_follow/data/smart_follow_repository.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_metadata.dart';
import 'package:flutter_test/flutter_test.dart';
import 'metadata_fixtures.dart';

void main() {
  late MetadataEnvironment env;
  setUp(() => env = MetadataEnvironment());
  tearDown(() => env.dispose());
  test('capability off performs neither availability nor preview nor create', () async {
    env.backend.capability = false;
    await env.controller.prepare();
    expect(env.controller.enabled, isFalse);
    expect(env.backend.availabilityReads, 0);
    expect(env.backend.previewReads, 0);
    expect(env.backend.creates, 0);
  });
  test('availability false overrides an old session hint', () async {
    env.backend.data['metadata_update_available'] = true;
    env.backend.available = false;
    await env.controller.prepare();
    expect(env.controller.canPreview, isFalse);
    expect(env.backend.previewReads, 0);
  });
  test('running recognition remains secondary even after copy session completes', () async {
    env.recognitionState = BirdJobState.running;
    await env.controller.refresh();
    expect(env.controller.session!.isFinished, isTrue);
    expect(env.controller.actionLabel, '保存当前已有信息');
    env.recognitionState = BirdJobState.completed;
    await env.controller.refresh();
    expect(env.controller.actionLabel, '更新识别信息');
    expect(env.backend.creates, 0);
  });
  test('opening and cancelling preview never creates a write task', () async {
    await env.controller.prepare();
    expect(env.controller.canSubmit, isTrue);
    expect(env.backend.previewReads, 1);
    expect(env.backend.creates, 0);
  });
  test('explicit confirmation submits original token and target exactly once', () async {
    await env.controller.prepare();
    await env.controller.confirm();
    expect(env.backend.detailReads, 1);
    expect(env.backend.creates, 1);
    expect(env.backend.submitted, {'preview_token': 'token-1', 'target_media_id': 'media_usb_fake'});
    expect(env.backend.submittedKey, 'md-create-sf_fake-token-1');
    expect(env.controller.activeUpdateId, 'update-1');
    expect(env.controller.canPreview, isFalse);
  });
  test('blocked items require a separate explicit partial consent', () async {
    env.backend.previewData.addAll({'blocked_count': 1, 'requires_partial_confirmation': true});
    await env.controller.prepare();
    expect(env.controller.canSubmit, isFalse);
    await env.controller.confirm();
    expect(env.backend.creates, 0);
    env.controller.setPartialConsent(true);
    await env.controller.confirm();
    expect(env.backend.submitted!['confirm_partial'], isTrue);
  });
  test('positive conflicts require consent even when partial flag is false', () async {
    env.backend.previewData['conflict_count'] = 1;
    await env.controller.prepare();
    expect(env.controller.preview!.needsPartialConsent, isTrue);
    expect(env.controller.canSubmit, isFalse);
  });
  for (final key in SmartFollowMetadataPreview.countKeys) {
    test('missing preview $key stays unknown and disables confirmation', () async {
      env.backend.previewData.remove(key);
      await env.controller.prepare();
      expect(env.controller.preview!.count(key), isNull);
      expect(env.controller.canSubmit, isFalse);
      await env.controller.confirm();
      expect(env.backend.creates, 0);
    });
  }
  test('missing confirmation flag is not treated as explicit permission', () async {
    env.backend.previewData.remove('requires_partial_confirmation');
    await env.controller.prepare();
    expect(env.controller.canSubmit, isFalse);
  });
  test('invalid negative and fractional counts are not zero evidence', () {
    final value = SmartFollowMetadataPreview.fromJson({'preview_token': 't', 'child_job_count': -1, 'estimated_bytes': 1.5});
    expect(value.count('child_job_count'), isNull);
    expect(value.count('estimated_bytes'), isNull);
  });
  test('zero updateable photos disables submission', () async {
    env.backend.previewData['updatable_asset_count'] = 0;
    await env.controller.prepare();
    expect(env.controller.previewIssue, contains('没有可更新'));
    expect(env.controller.canSubmit, isFalse);
  });
  test('unknown write mode cannot silently use a default strategy', () async {
    env.backend.previewData['write_mode'] = 'future-incompatible-method';
    await env.controller.prepare();
    expect(env.controller.preview!.writeModeLabel, '暂无法确认写入方式');
    expect(env.controller.canSubmit, isFalse);
  });
  test('missing deadline blocks confirmation instead of assuming forever valid', () async {
    env.backend.previewData.remove('expires_at');
    await env.controller.prepare();
    expect(env.controller.previewIssue, contains('有效期'));
    expect(env.controller.canSubmit, isFalse);
  });
  test('expired preview requires a fresh read and new consent', () async {
    env.backend.previewData.addAll({'expires_at': '2029-01-01T00:00:00Z', 'blocked_count': 1});
    await env.controller.prepare();
    env.controller.setPartialConsent(true);
    expect(env.controller.canSubmit, isFalse);
    env.backend.previewData['expires_at'] = '2099-01-01T00:00:00Z';
    await env.controller.prepare();
    expect(env.controller.partialConsent, isFalse);
    expect(env.backend.creates, 0);
  });
  test('target identity must match the original session', () async {
    env.backend.previewData['target_media_id'] = 'different-target';
    await env.controller.prepare();
    expect(env.controller.canSubmit, isFalse);
    expect(env.controller.previewIssue, contains('目标盘'));
  });
  test('internal target paths cannot be used as a user-reviewable target name', () async {
    env.backend.previewData['target_display_name'] = '/mnt/usb/private';
    await env.controller.prepare();
    expect(env.controller.canSubmit, isFalse);
    expect(env.controller.previewIssue, contains('目标盘名称'));
  });
  test('failed preview with otherwise complete fields never enables writes', () async {
    env.backend.previewData['state'] = 'failed';
    await env.controller.prepare();
    expect(env.controller.canSubmit, isFalse);
    expect(env.controller.previewIssue, contains('预览尚未就绪或已失败'));
  });
  test('capability loss between preview and final click prevents creation', () async {
    await env.controller.prepare();
    env.backend.capability = false;
    await env.controller.confirm();
    expect(env.backend.creates, 0);
  });
  test('availability loss between preview and final click prevents creation', () async {
    await env.controller.prepare();
    env.backend.available = false;
    await env.controller.confirm();
    expect(env.backend.creates, 0);
  });
  test('recognition finishing requires a refreshed preview and confirmation', () async {
    env.recognitionState = BirdJobState.running;
    await env.controller.prepare();
    env.recognitionState = BirdJobState.completed;
    await env.controller.confirm();
    expect(env.backend.creates, 0);
    expect(env.controller.preview, isNull);
    expect(env.controller.error, contains('识别阶段已变化'));
  });
  test('changed preview detail cannot silently replace the confirmed scope', () async {
    await env.controller.prepare();
    env.backend.detailData = {...env.backend.previewData, 'updatable_asset_count': 2};
    await env.controller.confirm();
    expect(env.backend.creates, 0);
    expect(env.controller.error, contains('预览内容已变化'));
  });
  test('mismatched preview identity is rejected before creation', () async {
    await env.controller.prepare();
    env.backend.detailData = {...env.backend.previewData, 'preview_id': 'other-preview'};
    await env.controller.confirm();
    expect(env.backend.creates, 0);
  });
  test('existing parent bypasses preview and duplicate creation', () async {
    env.backend.active = 'old-parent';
    await env.controller.prepare();
    expect(env.controller.activeUpdateId, 'old-parent');
    expect(env.backend.previewReads, 0);
    await env.controller.confirm();
    expect(env.backend.creates, 0);
  });
  test('different active parent IDs require reconciliation', () async {
    env.backend.active = 'a';
    env.backend.data['active_metadata_update_id'] = 'b';
    await env.controller.prepare();
    expect(env.controller.error, contains('关联不一致'));
    expect(env.backend.previewReads, 0);
  });
  test('double-click final confirmation creates once', () async {
    await env.controller.prepare();
    env.backend.createGate = Completer<void>();
    final first = env.controller.confirm();
    final second = env.controller.confirm();
    await Future<void>.delayed(Duration.zero);
    expect(env.backend.creates, 1);
    env.backend.createGate!.complete();
    await Future.wait([first, second]);
    expect(env.backend.creates, 1);
  });
  test('unknown creation persists and blocks another preview across repository restart', () async {
    await env.controller.prepare();
    env.backend.createError = const ApiException(message: 'timeout', statusCode: 504);
    await env.controller.confirm();
    expect(env.controller.outcomeUnknown, isTrue);
    final restarted = SmartFollowRepository(env.backend, metadataStorage: env.store, metadataDeviceId: () => 'box-1');
    final restored = env.newController(follows: restarted);
    addTearDown(restored.dispose);
    addTearDown(restarted.dispose);
    await restored.prepare();
    expect(restored.outcomeUnknown, isTrue);
    expect(env.backend.previewReads, 1);
    expect(env.backend.creates, 1);
    env.backend.active = 'recovered-parent';
    env.backend.available = false;
    await restored.refresh();
    expect(restored.activeUpdateId, 'recovered-parent');
    expect(restored.outcomeUnknown, isFalse);
  });
  test('unknown intents are isolated by box identity', () async {
    await env.controller.prepare();
    env.backend.createError = const ApiException(message: 'timeout', statusCode: 504);
    await env.controller.confirm();
    final other = SmartFollowRepository(env.backend, metadataStorage: env.store, metadataDeviceId: () => 'box-2');
    addTearDown(other.dispose);
    expect(other.hasPendingMetadata('sf_fake'), isFalse);
  });
  test('definitive rejected creation allows obtaining a new preview', () async {
    await env.controller.prepare();
    env.backend.createError = const ApiException(message: 'invalid', statusCode: 422);
    await env.controller.confirm();
    expect(env.controller.outcomeUnknown, isFalse);
    await env.controller.prepare();
    expect(env.backend.previewReads, 2);
  });
  for (final code in ['COPY_PREVIEW_EXPIRED', 'SMART_FOLLOW_METADATA_PARTIAL_CONFIRMATION_REQUIRED']) {
    test('known $code rejection permits a new preview but never automatic resubmission', () async {
      await env.controller.prepare();
      env.backend.createError = ApiException(message: 'rejected', statusCode: 409, code: code);
      await env.controller.confirm();
      expect(env.controller.outcomeUnknown, isFalse);
      expect(env.controller.error, contains('预览'));
      expect(env.backend.creates, 1);
      await env.controller.prepare();
      expect(env.backend.previewReads, 2);
      expect(env.backend.creates, 1);
      expect(env.controller.partialConsent, isFalse);
    });
  }
  test('unknown 409 remains unresolved instead of silently changing preview token', () async {
    await env.controller.prepare();
    env.backend.createError = const ApiException(message: 'conflict', statusCode: 409, code: 'UNKNOWN_CONFLICT');
    await env.controller.confirm();
    expect(env.controller.outcomeUnknown, isTrue);
    await env.controller.prepare();
    expect(env.backend.previewReads, 1);
    expect(env.backend.creates, 1);
  });
  test('device change during preview drops late facts', () async {
    env.backend.previewGate = Completer<void>();
    final loading = env.controller.prepare();
    await Future<void>.delayed(Duration.zero);
    env.current = false;
    env.repository.resetForDeviceChange();
    env.backend.previewGate!.complete();
    await loading;
    expect(env.controller.preview, isNull);
    expect(env.backend.creates, 0);
  });
  test('background invalidation during final validation prevents writes', () async {
    await env.controller.prepare();
    env.backend.detailGate = Completer<void>();
    final submitting = env.controller.confirm();
    await Future<void>.delayed(Duration.zero);
    env.controller.invalidate();
    env.backend.detailGate!.complete();
    await submitting;
    expect(env.backend.creates, 0);
  });
  test('wrong recognition job cannot enable metadata actions', () async {
    env.wrongRecognition = true;
    await env.controller.prepare();
    expect(env.backend.previewReads, 0);
    expect(env.controller.canPreview, isFalse);
  });
  test('repository refuses reserved body overrides', () async {
    await env.controller.prepare();
    await expectLater(env.repository.createMetadataUpdate('sf_fake', env.controller.preview!, extra: {'target_media_id': 'other'}), throwsArgumentError);
    expect(env.backend.creates, 0);
  });
}
