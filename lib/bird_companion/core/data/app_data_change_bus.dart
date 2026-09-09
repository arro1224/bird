import 'dart:async';

import 'package:aves/bird_companion/core/models/review_models.dart';

enum AppDataResource {
  device,
  batches,
  photos,
  jobs,
  cache,
  sync,
  photoPreferences,
  copyPreferences,
}

class AppDataChange {
  const AppDataChange(this.resources, {this.reason});
  final Set<AppDataResource> resources;
  final String? reason;

  bool affects(AppDataResource resource) => resources.contains(resource);
}

/// App-internal review delta. It supplements the frozen box API response and
/// lets retained album screens update counters before the authoritative reload.
class ReviewDecisionChanged extends AppDataChange {
  const ReviewDecisionChanged({
    required this.deviceId,
    required this.projectId,
    required this.fileId,
    required this.beforeKeepState,
    required this.afterKeepState,
    required this.authoritativeVersion,
    required this.queued,
  }) : super(
         const {AppDataResource.photos, AppDataResource.batches},
         reason: 'review_decision_changed',
       );

  final String deviceId;
  final String? projectId;
  final String fileId;
  final KeepState beforeKeepState;
  final KeepState afterKeepState;
  final int? authoritativeVersion;
  final bool queued;
}

/// App-internal signal that an analysis job has completed and the album root
/// should wait for the corresponding project data to become readable.
class AnalysisCompleted extends AppDataChange {
  const AnalysisCompleted({
    required this.deviceId,
    required this.projectId,
  }) : super(
         const {
           AppDataResource.jobs,
           AppDataResource.batches,
           AppDataResource.photos,
         },
         reason: 'analysis_completed',
       );

  final String deviceId;
  final String projectId;
}

/// Typed, targeted data invalidation. This replaces using one global refresh
/// for unrelated screens after every action.
class AppDataChangeBus {
  final _controller = StreamController<AppDataChange>.broadcast();
  Stream<AppDataChange> get changes => _controller.stream;
  void publish(Set<AppDataResource> resources, {String? reason}) => _controller.add(AppDataChange(resources, reason: reason));
  void publishChange(AppDataChange change) => _controller.add(change);
  Future<void> dispose() => _controller.close();
}
