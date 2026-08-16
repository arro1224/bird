import 'dart:async';

import 'package:aves/bird_companion/core/media/media_asset_coordinator.dart';
import 'package:aves/bird_companion/core/media/media_asset_models.dart';
import 'package:aves/bird_companion/core/media/media_asset_service.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

typedef MediaPlaceholderBuilder = Widget Function(BuildContext context);
typedef MediaFailureBuilder =
    Widget Function(
      BuildContext context,
      Object error,
      VoidCallback retry,
    );

/// Displays one media resource while delegating all retry timers and event
/// routing to the shared [MediaAssetCoordinator].
class ProgressiveMediaImage extends StatefulWidget {
  const ProgressiveMediaImage({
    super.key,
    required this.descriptor,
    required this.loader,
    required this.coordinator,
    required this.placeholderBuilder,
    required this.failureBuilder,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.cacheHeight,
    this.allowNetworkFallback = true,
  });

  final MediaAssetDescriptor descriptor;
  final MediaAssetLoader loader;
  final MediaAssetCoordinator coordinator;
  final MediaPlaceholderBuilder placeholderBuilder;
  final MediaFailureBuilder failureBuilder;
  final BoxFit fit;
  final int? cacheWidth;
  final int? cacheHeight;
  final bool allowNetworkFallback;

  @override
  State<ProgressiveMediaImage> createState() => _ProgressiveMediaImageState();
}

class _ProgressiveMediaImageState extends State<ProgressiveMediaImage> {
  StreamSubscription<MediaAssetUpdate>? _assetSubscription;
  StreamSubscription<EventConnectionState>? _connectionSubscription;
  MediaAssetLoadResult? _loaded;
  Object? _terminalError;
  CancelToken? _cancelToken;
  var _loadGeneration = 0;
  var _loading = false;
  var _fallbackActivated = false;
  var _retryAfterCurrentLoad = false;

  @override
  void initState() {
    super.initState();
    _subscribe();
    widget.coordinator.track(widget.descriptor);
    unawaited(_activateForStatus());
  }

  @override
  void didUpdateWidget(ProgressiveMediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final resourceChanged = oldWidget.descriptor.key != widget.descriptor.key || oldWidget.descriptor.uri != widget.descriptor.uri || oldWidget.loader != widget.loader || oldWidget.coordinator != widget.coordinator;
    if (resourceChanged) {
      _cancelCurrentLoad();
      unawaited(_assetSubscription?.cancel());
      unawaited(_connectionSubscription?.cancel());
      _loaded = null;
      _terminalError = null;
      _fallbackActivated = false;
      _retryAfterCurrentLoad = false;
      _subscribe();
    } else if (oldWidget.descriptor.status != widget.descriptor.status) {
      _terminalError = null;
      _fallbackActivated = false;
    }
    widget.coordinator.track(widget.descriptor);
    if (resourceChanged || oldWidget.descriptor.status != widget.descriptor.status || (!oldWidget.allowNetworkFallback && widget.allowNetworkFallback)) {
      unawaited(_activateForStatus());
    }
  }

  void _subscribe() {
    _assetSubscription = widget.coordinator.watch(widget.descriptor.key).listen(_onAssetUpdate);
    _connectionSubscription = widget.coordinator.eventConnectionStates.listen(
      _onConnectionState,
    );
  }

  Future<void> _activateForStatus() async {
    final descriptor = widget.coordinator.snapshot(widget.descriptor.key)?.descriptor ?? widget.descriptor;
    final status = descriptor.status;
    if (status == MediaAssetStatus.failed) {
      if (mounted) {
        setState(() {
          _terminalError = const MediaAssetFailure(
            kind: MediaAssetFailureKind.assetFailed,
            statusCode: 409,
            errorCode: 'asset_failed',
          );
        });
      }
      return;
    }
    if (status.canRequest) {
      await _load(descriptor: descriptor);
      return;
    }
    if (widget.allowNetworkFallback && widget.coordinator.eventConnectionState != EventConnectionState.connected) {
      _fallbackActivated = true;
      await _load(forceRefresh: true);
    }
  }

  void _onConnectionState(EventConnectionState state) {
    if (state == EventConnectionState.connected || !widget.allowNetworkFallback || _fallbackActivated || !widget.descriptor.status.isWaiting) {
      return;
    }
    _fallbackActivated = true;
    unawaited(_load(forceRefresh: true));
  }

  void _onAssetUpdate(MediaAssetUpdate update) {
    switch (update.reason) {
      case MediaAssetUpdateReason.assetReadyEvent:
        _fallbackActivated = false;
        _cancelCurrentLoad();
        unawaited(
          _load(
            forceRefresh: true,
            supersede: true,
            descriptor: update.snapshot.descriptor,
          ),
        );
      case MediaAssetUpdateReason.retryDue:
        if (_loading) {
          _retryAfterCurrentLoad = true;
        } else {
          unawaited(_load(forceRefresh: true));
        }
      case MediaAssetUpdateReason.terminalFailure:
        final failure = update.snapshot.lastFailure;
        if (failure != null && mounted) {
          setState(() => _terminalError = failure);
        }
      case MediaAssetUpdateReason.tracked:
      case MediaAssetUpdateReason.statusChanged:
      case MediaAssetUpdateReason.retryScheduled:
      case MediaAssetUpdateReason.loaded:
        break;
    }
  }

  Future<void> _load({
    bool forceRefresh = false,
    bool supersede = false,
    MediaAssetDescriptor? descriptor,
  }) async {
    if (_loading && !supersede) return;
    if (supersede) _cancelCurrentLoad();
    final generation = ++_loadGeneration;
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;
    _loading = true;
    try {
      final result = await widget.loader.load(
        descriptor ?? widget.descriptor,
        forceRefresh: forceRefresh,
        cancelToken: cancelToken,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loaded = result;
        _terminalError = null;
      });
    } on MediaAssetFailure catch (failure) {
      if (!mounted || generation != _loadGeneration || failure.kind == MediaAssetFailureKind.cancelled) {
        return;
      }
      if (!failure.retryable) {
        setState(() => _terminalError = failure);
      }
    } on MediaAssetStateException catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _terminalError = error);
      }
    } catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _terminalError = error);
      }
    } finally {
      if (generation == _loadGeneration) {
        _loading = false;
        if (identical(_cancelToken, cancelToken)) _cancelToken = null;
        if (_retryAfterCurrentLoad && mounted) {
          _retryAfterCurrentLoad = false;
          unawaited(_load(forceRefresh: true));
        }
      }
    }
  }

  void _manualRetry() {
    if (!mounted) return;
    setState(() => _terminalError = null);
    final retryDescriptor = widget.descriptor.copyWith(
      status: MediaAssetStatus.legacy,
    );
    widget.coordinator.resetForManualRetry(retryDescriptor);
    unawaited(
      _load(
        forceRefresh: true,
        supersede: true,
        descriptor: retryDescriptor,
      ),
    );
  }

  void _cancelCurrentLoad() {
    _loadGeneration++;
    _loading = false;
    _retryAfterCurrentLoad = false;
    _cancelToken?.cancel('Media resource changed.');
    _cancelToken = null;
  }

  @override
  void dispose() {
    _cancelCurrentLoad();
    unawaited(_assetSubscription?.cancel());
    unawaited(_connectionSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loaded = _loaded;
    if (loaded != null) {
      return Image.file(
        loaded.file,
        key: ValueKey(
          'media-image-${widget.descriptor.key.fileId}-'
          '${widget.descriptor.key.kind.wireValue}-${loaded.etag ?? loaded.file.path}',
        ),
        fit: widget.fit,
        cacheWidth: widget.cacheWidth,
        cacheHeight: widget.cacheHeight,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) => wasSynchronouslyLoaded || frame != null ? child : widget.placeholderBuilder(context),
        errorBuilder: (context, error, _) => widget.failureBuilder(context, error, _manualRetry),
      );
    }
    final error = _terminalError;
    return error == null ? widget.placeholderBuilder(context) : widget.failureBuilder(context, error, _manualRetry);
  }
}
