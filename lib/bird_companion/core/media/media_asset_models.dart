import 'package:equatable/equatable.dart';

enum MediaAssetKind { thumbnail, preview }

extension MediaAssetKindWireValue on MediaAssetKind {
  static MediaAssetKind? fromWire(String? value) => switch (value) {
    'thumbnail' => MediaAssetKind.thumbnail,
    'preview' => MediaAssetKind.preview,
    _ => null,
  };

  String get wireValue => switch (this) {
    MediaAssetKind.thumbnail => 'thumbnail',
    MediaAssetKind.preview => 'preview',
  };
}

/// Wire state plus two App-only compatibility states.
///
/// [legacy] means that an older box omitted the field. [unknown] keeps a
/// future enum value from making the complete photo response unparsable.
enum MediaAssetStatus {
  notRequested,
  pending,
  ready,
  failed,
  legacy,
  unknown,
}

extension MediaAssetStatusWireValue on MediaAssetStatus {
  static MediaAssetStatus fromWire(String? value) => switch (value) {
    null => MediaAssetStatus.legacy,
    'not_requested' => MediaAssetStatus.notRequested,
    'pending' => MediaAssetStatus.pending,
    'ready' => MediaAssetStatus.ready,
    'failed' => MediaAssetStatus.failed,
    _ => MediaAssetStatus.unknown,
  };

  String? get wireValue => switch (this) {
    MediaAssetStatus.notRequested => 'not_requested',
    MediaAssetStatus.pending => 'pending',
    MediaAssetStatus.ready => 'ready',
    MediaAssetStatus.failed => 'failed',
    MediaAssetStatus.legacy || MediaAssetStatus.unknown => null,
  };

  bool get canRequest => switch (this) {
    MediaAssetStatus.ready || MediaAssetStatus.legacy || MediaAssetStatus.unknown => true,
    MediaAssetStatus.notRequested || MediaAssetStatus.pending || MediaAssetStatus.failed => false,
  };

  bool get isWaiting => this == MediaAssetStatus.notRequested || this == MediaAssetStatus.pending;
}

class MediaAssetKey extends Equatable {
  const MediaAssetKey({
    required this.deviceId,
    required this.fileId,
    required this.kind,
  });

  final String deviceId;
  final String fileId;
  final MediaAssetKind kind;

  @override
  List<Object?> get props => [deviceId, fileId, kind];
}

class MediaAssetDescriptor extends Equatable {
  const MediaAssetDescriptor({
    required this.key,
    required this.status,
    this.uri,
  });

  final MediaAssetKey key;
  final Uri? uri;
  final MediaAssetStatus status;

  MediaAssetDescriptor copyWith({
    Uri? uri,
    MediaAssetStatus? status,
  }) => MediaAssetDescriptor(
    key: key,
    uri: uri ?? this.uri,
    status: status ?? this.status,
  );

  @override
  List<Object?> get props => [key, uri, status];
}

enum MediaAssetFailureKind {
  notReady,
  assetFailed,
  fileNotFound,
  unauthorized,
  transient,
  cancelled,
  other,
}

class MediaAssetFailure extends Equatable implements Exception {
  const MediaAssetFailure({
    required this.kind,
    this.statusCode,
    this.errorCode,
    this.message,
    this.retryable = false,
    this.retryAfter,
    this.details = const {},
    this.cause,
  });

  final MediaAssetFailureKind kind;
  final int? statusCode;
  final String? errorCode;
  final String? message;
  final bool retryable;
  final Duration? retryAfter;
  final Map<String, dynamic> details;
  final Object? cause;

  @override
  List<Object?> get props => [
    kind,
    statusCode,
    errorCode,
    message,
    retryable,
    retryAfter,
    details,
  ];

  @override
  String toString() =>
      'MediaAssetFailure(kind: $kind, statusCode: $statusCode, '
      'errorCode: $errorCode, retryable: $retryable)';
}

class MediaAssetSnapshot extends Equatable {
  const MediaAssetSnapshot({
    required this.descriptor,
    this.etag,
    this.retryAttempt = 0,
    this.lastFailure,
  });

  final MediaAssetDescriptor descriptor;
  final String? etag;
  final int retryAttempt;
  final MediaAssetFailure? lastFailure;

  MediaAssetSnapshot copyWith({
    MediaAssetDescriptor? descriptor,
    String? etag,
    bool clearEtag = false,
    int? retryAttempt,
    MediaAssetFailure? lastFailure,
    bool clearFailure = false,
  }) => MediaAssetSnapshot(
    descriptor: descriptor ?? this.descriptor,
    etag: clearEtag ? null : etag ?? this.etag,
    retryAttempt: retryAttempt ?? this.retryAttempt,
    lastFailure: clearFailure ? null : lastFailure ?? this.lastFailure,
  );

  @override
  List<Object?> get props => [descriptor, etag, retryAttempt, lastFailure];
}

enum MediaAssetUpdateReason {
  tracked,
  statusChanged,
  retryScheduled,
  retryDue,
  loaded,
  assetReadyEvent,
  terminalFailure,
}

class MediaAssetUpdate extends Equatable {
  const MediaAssetUpdate({
    required this.snapshot,
    required this.reason,
  });

  final MediaAssetSnapshot snapshot;
  final MediaAssetUpdateReason reason;

  @override
  List<Object?> get props => [snapshot, reason];
}

class MediaAssetStateException implements Exception {
  const MediaAssetStateException(this.status);

  final MediaAssetStatus status;

  @override
  String toString() => 'MediaAssetStateException: resource is $status';
}
