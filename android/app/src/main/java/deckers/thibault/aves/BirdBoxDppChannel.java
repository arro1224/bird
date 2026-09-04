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
    private static final int REQUEST_CODE_WINDOW = 1024;
    private static final long SYSTEM_ACTIVITY_TIMEOUT_MS = 180_000L;

    private final Activity activity;
    private final MethodChannel channel;
    private final Handler handler = new Handler(Looper.getMainLooper());
    @Nullable private MethodChannel.Result pendingResult;
    @Nullable private Uri transientDppUri;
    @Nullable private Runnable pendingTimeout;
    private int activeRequestCode = -1;
    private int launchGeneration;
    private boolean disposed;

    BirdBoxDppChannel(@NonNull Activity activity, @NonNull BinaryMessenger messenger) {
        this.activity = activity;
        channel = new MethodChannel(messenger, CHANNEL);
        channel.setMethodCallHandler(this::handleMethodCall);
    }

    private void handleMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        if (disposed) {
            result.error("invalid_state", "Easy Connect bridge is disposed.", null);
            return;
        }
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
        final int requestCode = requestCodeForGeneration(launchGeneration++);
        activeRequestCode = requestCode;
        pendingTimeout = () -> {
            if (activeRequestCode == requestCode) completeLaunch("timed_out", "timeout");
        };
        try {
            activity.startActivityForResult(intent, requestCode);
            handler.postDelayed(pendingTimeout, SYSTEM_ACTIVITY_TIMEOUT_MS);
        } catch (RuntimeException error) {
            completeLaunch("failed", "launch_exception");
        }
    }

    boolean onActivityResult(int requestCode, int resultCode) {
        if (!isDppRequestCode(requestCode)) return false;
        if (requestCode != activeRequestCode || pendingResult == null) return true;
        completeLaunch(
                mapActivityResult(resultCode),
                mapSystemResultCode(resultCode)
        );
        return true;
    }

    static boolean isValidDppUri(@Nullable String value) {
        return value != null
                && value.startsWith("DPP:")
                && value.endsWith(";;")
                && value.length() > "DPP:;;".length()
                && value.length() <= 4096
                && value.indexOf('\n') < 0
                && value.indexOf('\r') < 0;
    }

    @NonNull
    static String mapActivityResult(int resultCode) {
        if (resultCode == Activity.RESULT_OK) return "system_accepted";
        if (resultCode == Activity.RESULT_CANCELED) return "user_cancelled";
        return "failed";
    }

    @NonNull
    static String mapSystemResultCode(int resultCode) {
        if (resultCode == Activity.RESULT_OK) return "result_ok";
        if (resultCode == Activity.RESULT_CANCELED) return "result_cancelled";
        return "result_other";
    }

    static int requestCodeForGeneration(int generation) {
        return REQUEST_PROCESS_DPP_URI + Math.floorMod(generation, REQUEST_CODE_WINDOW);
    }

    static boolean isDppRequestCode(int requestCode) {
        return requestCode >= REQUEST_PROCESS_DPP_URI
                && requestCode < REQUEST_PROCESS_DPP_URI + REQUEST_CODE_WINDOW;
    }

    private void completeLaunch(@NonNull String outcome, @Nullable String systemResultCode) {
        final MethodChannel.Result result = pendingResult;
        if (result == null) {
            clearTransientUri();
            return;
        }
        pendingResult = null;
        final Runnable timeout = pendingTimeout;
        pendingTimeout = null;
        if (timeout != null) handler.removeCallbacks(timeout);
        activeRequestCode = -1;
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

    void onHostDestroying(boolean changingConfigurations) {
        if (!changingConfigurations && pendingResult != null) {
            completeLaunch("failed", "host_destroyed");
        }
    }

    void dispose() {
        if (disposed) return;
        disposed = true;
        final Runnable timeout = pendingTimeout;
        pendingTimeout = null;
        if (timeout != null) handler.removeCallbacks(timeout);
        final MethodChannel.Result result = pendingResult;
        pendingResult = null;
        activeRequestCode = -1;
        clearTransientUri();
        if (result != null) {
            result.success(launchResult("failed", "activity_disposed"));
        }
        channel.setMethodCallHandler(null);
    }
}
