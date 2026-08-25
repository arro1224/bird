package deckers.thibault.aves;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.net.wifi.WifiManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import java.util.LinkedHashMap;
import java.util.Map;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/** Android Easy Connect bridge. DPP URIs are transient and are never logged or persisted. */
final class BirdBoxDppChannel {
    static final String CHANNEL = "bird_companion/birdbox_dpp/methods";
    static final int REQUEST_PROCESS_DPP_URI = 48241;
    private static final long SYSTEM_ACTIVITY_TIMEOUT_MS = 180_000L;

    private final Activity activity;
    private final MethodChannel channel;
    private final Handler handler = new Handler(Looper.getMainLooper());
    @Nullable private MethodChannel.Result pendingResult;
    @Nullable private Uri transientDppUri;

    private final Runnable timeout = () -> completeLaunch("timed_out", "timeout");

    BirdBoxDppChannel(@NonNull Activity activity, @NonNull BinaryMessenger messenger) {
        this.activity = activity;
        channel = new MethodChannel(messenger, CHANNEL);
        channel.setMethodCallHandler(this::handleMethodCall);
    }

    private void handleMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "checkCapability":
                result.success(capability());
                return;
            case "launchEasyConnect":
                launchEasyConnect(call, result);
                return;
            case "clearTransientUri":
                clearTransientUri();
                result.success(null);
                return;
            default:
                result.notImplemented();
        }
    }

    @NonNull
    private Map<String, Object> capability() {
        final boolean apiLevelSupported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q;
        boolean easyConnectSupported = false;
        if (apiLevelSupported) {
            final WifiManager wifiManager = activity.getSystemService(WifiManager.class);
            easyConnectSupported = wifiManager != null && wifiManager.isEasyConnectSupported();
        }
        final Map<String, Object> value = new LinkedHashMap<>();
        value.put("apiLevelSupported", apiLevelSupported);
        value.put("easyConnectSupported", easyConnectSupported);
        value.put("activityAvailable", apiLevelSupported && canResolveEasyConnectActivity());
        return value;
    }

    private boolean canResolveEasyConnectActivity() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false;
        final Intent intent = new Intent(Settings.ACTION_PROCESS_WIFI_EASY_CONNECT_URI);
        intent.setData(Uri.parse("DPP:K:AA;;"));
        return intent.resolveActivity(activity.getPackageManager()) != null;
    }

    private void launchEasyConnect(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        if (pendingResult != null) {
            result.error("dpp_operation_busy", "An Easy Connect activity is already active.", null);
            return;
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.success(launchResult("activity_unavailable", "api_level"));
            return;
        }
        final String rawUri = call.argument("uri");
        if (!isValidDppUri(rawUri)) {
            result.success(launchResult("invalid_uri", "invalid_uri"));
            return;
        }
        final Uri uri = Uri.parse(rawUri);
        final Intent intent = new Intent(Settings.ACTION_PROCESS_WIFI_EASY_CONNECT_URI);
        intent.setData(uri);
        if (intent.resolveActivity(activity.getPackageManager()) == null) {
            result.success(launchResult("activity_unavailable", "unresolved"));
            return;
        }

        pendingResult = result;
        transientDppUri = uri;
        try {
            activity.startActivityForResult(intent, REQUEST_PROCESS_DPP_URI);
            handler.postDelayed(timeout, SYSTEM_ACTIVITY_TIMEOUT_MS);
        } catch (RuntimeException error) {
            completeLaunch("failed", error.getClass().getSimpleName());
        }
    }

    boolean onActivityResult(int requestCode, int resultCode) {
        if (requestCode != REQUEST_PROCESS_DPP_URI) return false;
        completeLaunch(
                mapActivityResult(resultCode),
                Integer.toString(resultCode)
        );
        return true;
    }

    static boolean isValidDppUri(@Nullable String value) {
        return value != null
                && value.startsWith("DPP:")
                && value.endsWith(";;")
                && value.length() > "DPP:;;".length();
    }

    @NonNull
    static String mapActivityResult(int resultCode) {
        if (resultCode == Activity.RESULT_OK) return "system_accepted";
        if (resultCode == Activity.RESULT_CANCELED) return "user_cancelled";
        return "failed";
    }

    private void completeLaunch(@NonNull String outcome, @Nullable String systemResultCode) {
        final MethodChannel.Result result = pendingResult;
        if (result == null) {
            clearTransientUri();
            return;
        }
        pendingResult = null;
        handler.removeCallbacks(timeout);
        clearTransientUri();
        result.success(launchResult(outcome, systemResultCode));
    }

    @NonNull
    private static Map<String, Object> launchResult(
            @NonNull String outcome,
            @Nullable String systemResultCode
    ) {
        final Map<String, Object> value = new LinkedHashMap<>();
        value.put("outcome", outcome);
        if (systemResultCode != null) value.put("systemResultCode", systemResultCode);
        return value;
    }

    private void clearTransientUri() {
        transientDppUri = null;
    }

    void dispose() {
        handler.removeCallbacks(timeout);
        final MethodChannel.Result result = pendingResult;
        pendingResult = null;
        clearTransientUri();
        if (result != null) {
            result.success(launchResult("failed", "activity_disposed"));
        }
        channel.setMethodCallHandler(null);
    }
}
