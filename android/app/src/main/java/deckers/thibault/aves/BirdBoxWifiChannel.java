package deckers.thibault.aves;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.pm.PackageManager;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.NetworkRequest;
import android.net.wifi.WifiNetworkSpecifier;
import android.os.Build;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import java.util.LinkedHashMap;
import java.util.Map;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/** Android 10+ local-only Wi-Fi request and process routing bridge. */
final class BirdBoxWifiChannel implements MethodChannel.MethodCallHandler {
    private static final String CHANNEL = "bird_companion/birdbox_wifi/methods";
    private static final int PERMISSION_REQUEST = 0xB172;
    private static final int JOIN_TIMEOUT_MS = 30000;

    private final Activity activity;
    private final ConnectivityManager connectivityManager;
    private final MethodChannel channel;

    @Nullable private MethodChannel.Result pendingPermissionResult;
    @Nullable private MethodChannel.Result pendingJoinResult;
    @Nullable private ConnectivityManager.NetworkCallback networkCallback;
    @Nullable private Network requestedNetwork;
    @Nullable private String requestedSsid;
    private boolean disposed;

    BirdBoxWifiChannel(
            @NonNull Activity activity,
            @NonNull BinaryMessenger messenger
    ) {
        this.activity = activity;
        this.connectivityManager = (ConnectivityManager) activity.getSystemService(Context.CONNECTIVITY_SERVICE);
        this.channel = new MethodChannel(messenger, CHANNEL);
        this.channel.setMethodCallHandler(this);
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        if (disposed && !"dispose".equals(call.method)) {
            result.error("invalid_state", "Wi-Fi bridge is disposed.", null);
            return;
        }
        switch (call.method) {
            case "ensurePermissions":
                ensurePermissions(result);
                return;
            case "joinDirectAp":
                joinDirectAp(call, result);
                return;
            case "bindProcessToNetwork":
                bindProcessToNetwork(call, result);
                return;
            case "releaseNetwork":
                releaseNetwork();
                result.success(null);
                return;
            case "dispose":
                dispose();
                result.success(null);
                return;
            default:
                result.notImplemented();
        }
    }

    private void ensurePermissions(@NonNull MethodChannel.Result result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error("wifi_unsupported", "Direct Wi-Fi requests require Android 10 or newer.", null);
            return;
        }
        final String permission = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
                ? Manifest.permission.NEARBY_WIFI_DEVICES
                : Manifest.permission.ACCESS_FINE_LOCATION;
        if (ContextCompat.checkSelfPermission(activity, permission) == PackageManager.PERMISSION_GRANTED) {
            result.success(true);
            return;
        }
        if (pendingPermissionResult != null) {
            result.error("invalid_state", "A Wi-Fi permission request is already active.", null);
            return;
        }
        pendingPermissionResult = result;
        ActivityCompat.requestPermissions(activity, new String[]{permission}, PERMISSION_REQUEST);
    }

    boolean onRequestPermissionsResult(int requestCode, @NonNull int[] grantResults) {
        if (requestCode != PERMISSION_REQUEST) return false;
        final MethodChannel.Result result = pendingPermissionResult;
        pendingPermissionResult = null;
        if (result != null) {
            result.success(grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED);
        }
        return true;
    }

    private void joinDirectAp(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error("wifi_unsupported", "Direct Wi-Fi requests require Android 10 or newer.", null);
            return;
        }
        if (connectivityManager == null) {
            result.error("wifi_unsupported", "Connectivity service is unavailable.", null);
            return;
        }
        if (pendingJoinResult != null) {
            result.error("invalid_state", "A Wi-Fi join request is already active.", null);
            return;
        }
        final String ssid = call.argument("ssid");
        final String passphrase = call.argument("passphrase");
        if (ssid == null || ssid.isEmpty() || passphrase == null || passphrase.isEmpty()) {
            result.error("invalid_request", "SSID and passphrase are required.", null);
            return;
        }

        releaseNetwork();
        final WifiNetworkSpecifier specifier;
        final NetworkRequest request;
        try {
            specifier = new WifiNetworkSpecifier.Builder()
                    .setSsid(ssid)
                    .setWpa2Passphrase(passphrase)
                    .build();
            request = new NetworkRequest.Builder()
                    .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                    .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                    .setNetworkSpecifier(specifier)
                    .build();
        } catch (IllegalArgumentException | IllegalStateException error) {
            result.error("invalid_request", "The Wi-Fi request is invalid.", null);
            return;
        }

        pendingJoinResult = result;
        requestedSsid = ssid;
        networkCallback = new ConnectivityManager.NetworkCallback() {
            @Override
            public void onAvailable(@NonNull Network network) {
                requestedNetwork = network;
                final MethodChannel.Result pending = pendingJoinResult;
                pendingJoinResult = null;
                if (pending == null) return;
                final Map<String, Object> response = new LinkedHashMap<>();
                response.put("outcome", "joined");
                response.put("handle", Long.toUnsignedString(network.getNetworkHandle()));
                response.put("ssid", requestedSsid == null ? "" : requestedSsid);
                activity.runOnUiThread(() -> pending.success(response));
            }

            @Override
            public void onUnavailable() {
                completeJoinFailure("system_denied", "wifi_join_denied");
            }

            @Override
            public void onLost(@NonNull Network network) {
                if (network.equals(requestedNetwork)) {
                    connectivityManager.bindProcessToNetwork(null);
                    requestedNetwork = null;
                }
            }
        };
        try {
            connectivityManager.requestNetwork(request, networkCallback, JOIN_TIMEOUT_MS);
        } catch (SecurityException error) {
            completeJoinError("wifi_permission_denied", "Wi-Fi permission was denied.");
        } catch (RuntimeException error) {
            completeJoinError("wifi_join_failed", "Wi-Fi request failed.");
        }
    }

    private void bindProcessToNetwork(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        final Network network = requestedNetwork;
        final String handle = call.argument("handle");
        if (network == null || handle == null || !handle.equals(Long.toUnsignedString(network.getNetworkHandle()))) {
            result.error("invalid_state", "The requested Wi-Fi network is no longer available.", null);
            return;
        }
        if (!connectivityManager.bindProcessToNetwork(network)) {
            result.error("wifi_join_failed", "Process routing could not be bound.", null);
            return;
        }
        result.success(null);
    }

    private void completeJoinFailure(@NonNull String outcome, @NonNull String errorCode) {
        final MethodChannel.Result result = pendingJoinResult;
        pendingJoinResult = null;
        if (result == null) return;
        final Map<String, Object> response = new LinkedHashMap<>();
        response.put("outcome", outcome);
        response.put("errorCode", errorCode);
        activity.runOnUiThread(() -> result.success(response));
    }

    private void completeJoinError(@NonNull String code, @NonNull String message) {
        final MethodChannel.Result result = pendingJoinResult;
        pendingJoinResult = null;
        if (result != null) activity.runOnUiThread(() -> result.error(code, message, null));
        releaseNetwork();
    }

    private void releaseNetwork() {
        if (connectivityManager != null) connectivityManager.bindProcessToNetwork(null);
        final ConnectivityManager.NetworkCallback callback = networkCallback;
        networkCallback = null;
        if (callback != null && connectivityManager != null) {
            try {
                connectivityManager.unregisterNetworkCallback(callback);
            } catch (IllegalArgumentException ignored) {
                // The timed request may already have been automatically released.
            }
        }
        requestedNetwork = null;
        requestedSsid = null;
        final MethodChannel.Result pending = pendingJoinResult;
        pendingJoinResult = null;
        if (pending != null) {
            final Map<String, Object> response = new LinkedHashMap<>();
            response.put("outcome", "user_cancelled");
            activity.runOnUiThread(() -> pending.success(response));
        }
    }

    void dispose() {
        if (disposed) return;
        disposed = true;
        releaseNetwork();
        if (pendingPermissionResult != null) {
            pendingPermissionResult.error("invalid_state", "Wi-Fi bridge was disposed.", null);
            pendingPermissionResult = null;
        }
        channel.setMethodCallHandler(null);
    }
}
