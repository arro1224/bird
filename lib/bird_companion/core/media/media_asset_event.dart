import 'package:aves/bird_companion/core/media/media_asset_models.dart';
import 'package:aves/bird_companion/core/models/json_value.dart';
import 'package:aves/bird_companion/core/network/event_client.dart';
import 'package:equatable/equatable.dart';

class AssetReadyEvent extends Equatable {
  const AssetReadyEvent({
    required this.projectId,
    required this.fileId,
    required this.kind,
    required this.etag,
    required this.width,
    required this.height,
    required this.timestamp,
    this.eventId,
    this.jobId,
    this.generationMode,
  });

  final String? eventId;
  final String? jobId;
  final String projectId;
  final String fileId;
  final MediaAssetKind kind;
  final String etag;
  final int width;
  final int height;
  final String? generationMode;
  final DateTime timestamp;

  static AssetReadyEvent? tryFromDeviceEvent(DeviceEvent event) {
    if (event.type != 'asset_ready') return null;
    final payload = event.payload;
    final kind = MediaAssetKindWireValue.fromWire(
      payload.stringOrNull('kind'),
    );
    final projectId = payload.stringOrNull('project_id')?.trim() ?? '';
    final fileId = payload.stringOrNull('file_id')?.trim() ?? '';
    final etag = payload.stringOrNull('etag')?.trim() ?? '';
    final width = payload.intOrNull('width') ?? 0;
    final height = payload.intOrNull('height') ?? 0;
    if (kind == null || projectId.isEmpty || fileId.isEmpty || etag.isEmpty || width <= 0 || height <= 0 || payload.stringOrNull('status') != 'ready') {
      return null;
    }
    return AssetReadyEvent(
      eventId: event.eventId,
      jobId: payload.stringOrNull('job_id'),
      projectId: projectId,
      fileId: fileId,
      kind: kind,
      etag: etag,
      width: width,
      height: height,
      generationMode: payload.stringOrNull('generation_mode'),
      timestamp: event.timestamp,
    );
  }

  @override
  List<Object?> get props => [
    eventId,
    jobId,
    projectId,
    fileId,
    kind,
    etag,
    width,
    height,
    generationMode,
    timestamp,
  ];
}
