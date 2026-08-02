import 'dart:async';

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

/// Typed, targeted data invalidation. This replaces using one global refresh
/// for unrelated screens after every action.
class AppDataChangeBus {
  final _controller = StreamController<AppDataChange>.broadcast();
  Stream<AppDataChange> get changes => _controller.stream;
  void publish(Set<AppDataResource> resources, {String? reason}) => _controller.add(AppDataChange(resources, reason: reason));
  Future<void> dispose() => _controller.close();
}
