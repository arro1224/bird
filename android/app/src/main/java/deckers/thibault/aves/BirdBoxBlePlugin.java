package deckers.thibault.aves;

import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.PluginRegistry;

/** BLE belongs to the Engine; an Activity can detach and reattach without losing pairing. */
public final class BirdBoxBlePlugin implements FlutterPlugin, ActivityAware {
    interface ChannelFactory {
        BirdBoxBleChannel create(android.content.Context context, io.flutter.plugin.common.BinaryMessenger messenger);
    }
    private final ChannelFactory factory;
    public BirdBoxBlePlugin() { this(BirdBoxBleChannel::new); }
    BirdBoxBlePlugin(ChannelFactory factory) { this.factory = factory; }
    private BirdBoxBleChannel channel;
    private ActivityPluginBinding activityBinding;
    private final PluginRegistry.RequestPermissionsResultListener permissions =
            (request, names, grants) -> channel != null && channel.onRequestPermissionsResult(request, grants);

    @Override public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        channel = factory.create(binding.getApplicationContext(), binding.getBinaryMessenger());
    }
    @Override public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        detach("engine_destroyed");
        if (channel != null) { channel.dispose("engine_destroyed"); channel = null; }
    }
    @Override public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        activityBinding = binding;
        binding.addRequestPermissionsResultListener(permissions);
        channel.attachActivity(binding.getActivity());
    }
    @Override public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
        onAttachedToActivity(binding);
    }
    @Override public void onDetachedFromActivityForConfigChanges() { detach("activity_recreating"); }
    @Override public void onDetachedFromActivity() { detach("activity_detached"); }
    private void detach(String reason) {
        if (activityBinding != null) {
            activityBinding.removeRequestPermissionsResultListener(permissions);
            activityBinding = null;
        }
        if (channel != null) channel.detachActivity(reason);
    }
}
