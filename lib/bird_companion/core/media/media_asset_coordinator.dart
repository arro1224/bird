import 'dart:async';

import 'package:aves/bird_companion/core/media/media_asset_cache.dart';
import 'package:aves/bird_companion/core/media/media_asset_event.dart';
import 'package:aves/bird_companion/core/media/media_asset_models.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';

class MediaAssetRetryPolicy {
  const MediaAssetRetryPolicy({
    this.delays = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 5),
      Duration(seconds: 5),
    ],
    this.maxDelay = const Duration(seconds: 5),
    this.maxAttempts = 5,
  });

  final List<Duration> delays;
  final Duration maxDelay;
  final int maxAttempts;

  Duration delayFor(int zeroBasedAttempt, Duration? retryAfter) {
    final fallback = delays.isEmpty ? Duration.zero : delays[zeroBasedAttempt.clamp(0, delays.length - 1)];
    final requested = retryAfter ?? fallback;
    if (requested.isNegative) return Duration.zero;
    return requested > maxDelay ? maxDelay : requested;
  }
}

class MediaAssetCoordinator {
  MediaAssetCoordinator({
    required EventClient eventClient,
    required String? Function() activeDeviceId,
    required MediaAssetCacheInvalidator cacheInvalidator,
    MediaAssetRetryPolicy retryPolicy = const MediaAssetRetryPolicy(),
  }) : this._(
         eventClient,
         activeDeviceId,
         cacheInvalidator,
         retryPolicy,
       );

  MediaAssetCoordinator._(
    this._eventClient,
    this._activeDeviceId,
    this._cacheInvalidator,
    this.retryPolicy,
  ) {
    _eventSubscription = _eventClient.events.listen(
      (event) => unawaited(handleDeviceEvent(event)),
    );
  }

  final EventClient _eventClient;
  final String? Function() _activeDeviceId;
  final MediaAssetCacheInvalidator _cacheInvalidator;
  final MediaAssetRetryPolicy retryPolicy;
  final Map<MediaAssetKey, MediaAssetSnapshot> _snapshots = {};
  final Map<MediaAssetKey, Timer> _retryTimers = {};
  final StreamController<MediaAssetUpdate> _updates = StreamController<MediaAssetUpdate>.broadcast();
  late final StreamSubscription<DeviceEvent> _eventSubscription;
  bool _disposed = false;

  Stream<MediaAssetUpdate> get updates => _updates.stream;
  EventConnectionState get eventConnectionState => _eventClient.currentState;
  Stream<EventConnectionState> get eventConnectionStates => _eventClient.connectionStates;

  Stream<MediaAssetUpdate> watch(MediaAssetKey key) => updates.where((update) => update.snapshot.descriptor.key == key);

  MediaAssetSnapshot? snapshot(MediaAssetKey key) => _snapshots[key];

  MediaAssetSnapshot track(MediaAssetDescriptor descriptor) {
    final previous = _snapshots[descriptor.key];
    final effectiveDescriptor = _mergeRuntimeStatus(previous, descriptor);
    final changed = previous == null || previous.descriptor != effectiveDescriptor;
    final next = previous == null ? MediaAssetSnapshot(descriptor: effectiveDescriptor) : previous.copyWith(descriptor: effectiveDescriptor);
    _snapshots[descriptor.key] = next;
    if (effectiveDescriptor.status == MediaAssetStatus.failed || effectiveDescriptor.status == MediaAssetStatus.ready) {
      _cancelRetry(descriptor.key);
    }
    if (changed) {
      _emit(
        next,
        previous == null ? MediaAssetUpdateReason.tracked : MediaAssetUpdateReason.statusChanged,
      );
    }
    return next;
  }

  /// Clears an HTTP terminal state only after an explicit user action.
  MediaAssetSnapshot resetForManualRetry(MediaAssetDescriptor descriptor) {
    _cancelRetry(descriptor.key);
    final next = MediaAssetSnapshot(
      descriptor: descriptor,
      etag: _snapshots[descriptor.key]?.etag,
    );
    _snapshots[descriptor.key] = next;
    _emit(next, MediaAssetUpdateReason.statusChanged);
    return next;
  }

  MediaAssetDescriptor _mergeRuntimeStatus(
    MediaAssetSnapshot? previous,
    MediaAssetDescriptor incoming,
  ) {
    if (previous == null || previous.descriptor.uri != incoming.uri) {
      return incoming;
    }
    final runtimeStatus = previous.descriptor.status;
    if (runtimeStatus == MediaAssetStatus.failed && incoming.status != MediaAssetStatus.failed) {
      return incoming.copyWith(status: MediaAssetStatus.failed);
    }
    if (runtimeStatus == MediaAssetStatus.ready && incoming.status != MediaAssetStatus.ready && incoming.status != MediaAssetStatus.failed) {
      return incoming.copyWith(status: MediaAssetStatus.ready);
    }
    return incoming;
  }

  void recordLoaded(MediaAssetKey key, {String? etag}) {
    final previous = _snapshots[key];
    if (previous == null) return;
    _cancelRetry(key);
    final next = previous.copyWith(
      descriptor: previous.descriptor.copyWith(
        status: MediaAssetStatus.ready,
      ),
      etag: etag,
      retryAttempt: 0,
      clearFailure: true,
    );
    _snapshots[key] = next;
    _emit(next, MediaAssetUpdateReason.loaded);
  }

  bool recordFailure(MediaAssetKey key, MediaAssetFailure failure) {
    final previous = _snapshots[key];
    if (previous == null) return false;
    if (failure.kind == MediaAssetFailureKind.assetFailed || failure.kind == MediaAssetFailureKind.fileNotFound || failure.kind == MediaAssetFailureKind.unauthorized || !failure.retryable) {
      _cancelRetry(key);
      final status = failure.kind == MediaAssetFailureKind.assetFailed ? MediaAssetStatus.failed : previous.descriptor.status;
      final next = previous.copyWith(
        descriptor: previous.descriptor.copyWith(status: status),
        lastFailure: failure,
      );
      _snapshots[key] = next;
      _emit(next, MediaAssetUpdateReason.terminalFailure);
      return false;
    }
    if (previous.retryAttempt >= retryPolicy.maxAttempts) {
      final next = previous.copyWith(lastFailure: failure);
      _snapshots[key] = next;
      _emit(next, MediaAssetUpdateReason.terminalFailure);
      return false;
    }
    _cancelRetry(key);
    final delay = retryPolicy.delayFor(
      previous.retryAttempt,
      failure.retryAfter,
    );
    final next = previous.copyWith(
      retryAttempt: previous.retryAttempt + 1,
      lastFailure: failure,
    );
    _snapshots[key] = next;
    _emit(next, MediaAssetUpdateReason.retryScheduled);
    _retryTimers[key] = Timer(delay, () {
      _retryTimers.remove(key);
      final current = _snapshots[key];
      if (current != null && !_disposed) {
        _emit(current, MediaAssetUpdateReason.retryDue);
      }
    });
    return true;
  }

  Future<void> handleDeviceEvent(DeviceEvent event) async {
    final assetEvent = AssetReadyEvent.tryFromDeviceEvent(event);
    final deviceId = _activeDeviceId()?.trim();
    if (assetEvent == null || deviceId == null || deviceId.isEmpty || _disposed) {
      return;
    }
    final key = MediaAssetKey(
      deviceId: deviceId,
      fileId: assetEvent.fileId,
      kind: assetEvent.kind,
    );
    final previous = _snapshots[key];
    final descriptor =
        (previous?.descriptor ??
                MediaAssetDescriptor(
                  key: key,
                  status: MediaAssetStatus.ready,
                ))
            .copyWith(status: MediaAssetStatus.ready);
    _cancelRetry(key);
    if (previous == null || previous.etag != assetEvent.etag) {
      try {
        await _cacheInvalidator.remove(descriptor);
      } catch (_) {
        // A stale cache file must not suppress the authoritative ready event.
        // The next load can still replace it using the event ETag.
      }
    }
    if (_disposed) return;
    final next = MediaAssetSnapshot(
      descriptor: descriptor,
      etag: assetEvent.etag,
    );
    _snapshots[key] = next;
    _emit(next, MediaAssetUpdateReason.assetReadyEvent);
  }

  void _emit(MediaAssetSnapshot snapshot, MediaAssetUpdateReason reason) {
    if (!_disposed) {
      _updates.add(MediaAssetUpdate(snapshot: snapshot, reason: reason));
    }
  }

  void _cancelRetry(MediaAssetKey key) {
    _retryTimers.remove(key)?.cancel();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();
    await _eventSubscription.cancel();
    await _updates.close();
  }
}
