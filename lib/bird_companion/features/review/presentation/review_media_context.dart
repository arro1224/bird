import 'package:aves/bird_companion/app/app_dependencies.dart';
import 'package:aves/bird_companion/core/media/media_asset_coordinator.dart';
import 'package:aves/bird_companion/core/media/media_asset_service.dart';

class ReviewMediaContext {
  const ReviewMediaContext({
    this.loader,
    this.coordinator,
    this.deviceNamespace,
    this.allowNetworkFallback = false,
  });

  final MediaAssetLoader? loader;
  final MediaAssetCoordinator? coordinator;
  final String? deviceNamespace;
  final bool allowNetworkFallback;
}

/// Keeps review widgets compatible with lightweight dependency substitutes.
/// Production dependencies always expose the complete progressive media graph.
ReviewMediaContext resolveReviewMediaContext(
  BirdCompanionDependencies dependencies,
) {
  try {
    final session = dependencies.deviceSessionCubit.state;
    return ReviewMediaContext(
      loader: dependencies.mediaAssetService,
      coordinator: dependencies.mediaAssetCoordinator,
      deviceNamespace: session.device?.id,
      allowNetworkFallback: session.isConnected,
    );
  } on NoSuchMethodError {
    return const ReviewMediaContext();
  }
}
