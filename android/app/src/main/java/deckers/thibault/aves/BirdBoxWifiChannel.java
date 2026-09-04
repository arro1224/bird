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
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import java.util.LinkedHashMap;
import java.util.Map;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/** Android 10+ local-only Wi-Fi request and process routing bridge. */
final class BirdBoxWifiChannel implements MethodChannel.MethodCallHandler {
    private static final String METHOD_CHANNEL = "bird_companion/birdbox_wifi/methods";
    private static final String NETWORK_EVENTS_CHANNEL = "bird_companion/birdbox_wifi/network_events";
    private static final int PERMISSION_REQUEST = 0xB172;
    private static final int JOIN_TIMEOUT_MS = 30000;

    private final Activity activity;
    private final ConnectivityManager connectivityManager;
    private final MethodChannel channel;
    private final EventChannel networkEventsChannel;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final Object stateLock = new Object();

    @Nullable private EventChannel.EventSink networkEventsSink;
    @Nullable private MethodChannel.Result pendingPermissionResult;
    @Nullable private MethodChannel.Result pendingJoinResult;
    @Nullable private ConnectivityManager.NetworkCallback networkCallback;
    @Nullable private Network requestedNetwork;
    @Nullable private String requestedSsid;
    private long requestGeneration;
    private boolean disposed;

    BirdBoxWifiChannel(
            @NonNull Activity activity,
            @NonNull BinaryMessenger messenger
    ) {
        this.activity = activity;
        this.connectivityManager = (ConnectivityManager) activity.getSystemService(Context.CONNECTIVITY_SERVICE);
        this.channel = new MethodChannel(messenger, METHOD_CHANNEL);
        this.networkEventsChannel = new EventChannel(messenger, NETWORK_EVENTS_CHANNEL);
        this.channel.setMethodCallHandler(this);
        this.networkEventsChannel.setStreamHandler(new EventChannel.StreamHandler() {
            @Override
            public void onListen(Object arguments, EventChannel.EventSink events) {
                networkEventsSink = events;
            }

            @Override
            public void onCancel(Object arguments) {
                networkEventsSink = null;
            }
        });
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
                releaseNetwork(true);
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

        releaseNetwork(false);
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

        final long generation;
        synchronized (stateLock) {
            pendingJoinResult = result;
            requestedSsid = ssid;
            generation = ++requestGeneration;
        }
        networkCallback = new ConnectivityManager.NetworkCallback() {
            @Override
            public void onAvailable(@NonNull Network network) {
                final MethodChannel.Result pending;
                final String responseSsid;
                synchronized (stateLock) {
                    if (!isActiveCallback(this, generation)) return;
                    requestedNetwork = network;
                    pending = pendingJoinResult;
                    pendingJoinResult = null;
                    responseSsid = requestedSsid;
                }
                if (pending == null) return;
                final Map<String, Object> response = new LinkedHashMap<>();
                response.put("outcome", "joined");
                response.put("handle", Long.toUnsignedString(network.getNetworkHandle()));
                response.put("ssid", responseSsid == null ? "" : responseSsid);
                mainHandler.post(() -> pending.success(response));
            }

            @Override
            public void onUnavailable() {
                completeJoinFailure(this, generation, "system_denied", "wifi_request_unavailable");
            }

            @Override
            public void onLost(@NonNull Network network) {
                final String handle;
                final String ssid;
                synchronized (stateLock) {
                    if (!isActiveCallback(this, generation) || !network.equals(requestedNetwork)) return;
                    handle = Long.toUnsignedString(network.getNetworkHandle());
                    ssid = requestedSsid;
                    requestedNetwork = null;
                }
                unbindProcess();
                emitNetworkLost(handle, ssid, "network_lost");
                releaseCallback(this, generation);
            }
        };
        try {
            connectivityManager.requestNetwork(request, networkCallback, JOIN_TIMEOUT_MS);
        } catch (SecurityException error) {
            completeJoinError(generation, "wifi_permission_denied", "Wi-Fi permission was denied.");
        } catch (RuntimeException error) {
            completeJoinError(generation, "wifi_join_failed", "Wi-Fi request failed.");
        }
    }

    private void bindProcessToNetwork(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        if (connectivityManager == null) {
            result.error("wifi_unsupported", "Connectivity service is unavailable.", null);
            return;
        }
        final Network network = requestedNetwork;
        final String handle = call.argument("handle");
        if (network == null || handle == null || !handle.equals(Long.toUnsignedString(network.getNetworkHandle()))) {
            result.error("invalid_state", "The requested Wi-Fi network is no longer available.", null);
            return;
        }
        try {
            if (!connectivityManager.bindProcessToNetwork(network)) {
                result.error("wifi_bind_failed", "Process routing could not be bound.", null);
                return;
            }
        } catch (SecurityException error) {
            result.error("wifi_permission_denied", "Wi-Fi routing permission was denied.", null);
            return;
        } catch (RuntimeException error) {
            result.error("wifi_bind_failed", "Process routing could not be bound.", null);
            return;
        }
        result.success(null);
    }

    private void completeJoinFailure(
            @NonNull ConnectivityManager.NetworkCallback callback,
            long generation,
            @NonNull String outcome,
            @NonNull String errorCode
    ) {
        final MethodChannel.Result result;
        synchronized (stateLock) {
            if (!isActiveCallback(callback, generation)) return;
            result = pendingJoinResult;
            pendingJoinResult = null;
        }
        releaseCallback(callback, generation);
        if (result != null) {
            final Map<String, Object> response = new LinkedHashMap<>();
            response.put("outcome", outcome);
            response.put("errorCode", errorCode);
            mainHandler.post(() -> result.success(response));
        }
    }

    private void completeJoinError(long generation, @NonNull String code, @NonNull String message) {
        final MethodChannel.Result result;
        synchronized (stateLock) {
            if (generation != requestGeneration) return;
            result = pendingJoinResult;
            pendingJoinResult = null;
        }
        if (result != null) mainHandler.post(() -> result.error(code, message, null));
        releaseNetwork(false);
    }

    private boolean isActiveCallback(
            @NonNull ConnectivityManager.NetworkCallback callback,
            long generation
    ) {
        return !disposed && generation == requestGeneration && callback == networkCallback;
    }

    private void releaseCallback(
            @NonNull ConnectivityManager.NetworkCallback callback,
            long generation
    ) {
        synchronized (stateLock) {
            if (generation != requestGeneration || callback != networkCallback) return;
            networkCallback = null;
            requestedSsid = null;
            requestGeneration++;
        }
        unregisterCallback(callback);
    }

    private void releaseNetwork(boolean userInitiated) {
        unbindProcess();
        final ConnectivityManager.NetworkCallback callback;
        final MethodChannel.Result pending;
        synchronized (stateLock) {
            callback = networkCallback;
            networkCallback = null;
            requestedNetwork = null;
            requestedSsid = null;
            pending = pendingJoinResult;
            pendingJoinResult = null;
            requestGeneration++;
        }
        unregisterCallback(callback);
        if (pending != null) {
            final Map<String, Object> response = new LinkedHashMap<>();
            response.put("outcome", userInitiated ? "user_cancelled" : "failed");
            response.put("errorCode", userInitiated ? "wifi_join_cancelled" : "wifi_request_released");
            mainHandler.post(() -> pending.success(response));
        }
    }

    private void unbindProcess() {
        if (connectivityManager == null) return;
        try {
            connectivityManager.bindProcessToNetwork(null);
        } catch (RuntimeException ignored) {
            // Cleanup is idempotent even if connectivity service state changed.
        }
    }

    private void unregisterCallback(@Nullable ConnectivityManager.NetworkCallback callback) {
        if (callback != null && connectivityManager != null) {
            try {
                connectivityManager.unregisterNetworkCallback(callback);
            } catch (IllegalArgumentException | SecurityException ignored) {
                // The timed request may already have been automatically released.
            }
        }
    }

    private void emitNetworkLost(
            @NonNull String handle,
            @Nullable String ssid,
            @NonNull String reason
    ) {
        final EventChannel.EventSink sink = networkEventsSink;
        if (sink == null || disposed) return;
        final Map<String, Object> event = networkLostEvent(handle, ssid, reason);
        mainHandler.post(() -> {
            if (!disposed && sink == networkEventsSink) sink.success(event);
        });
    }

    @NonNull
    static Map<String, Object> networkLostEvent(
            @NonNull String handle,
            @Nullable String ssid,
            @NonNull String reason
    ) {
        final Map<String, Object> event = new LinkedHashMap<>();
        event.put("type", "lost");
        event.put("handle", handle);
        event.put("ssid", ssid == null ? "" : ssid);
        event.put("reason", reason);
        return event;
    }

    void dispose() {
        if (disposed) return;
        disposed = true;
        releaseNetwork(false);
        if (pendingPermissionResult != null) {
            pendingPermissionResult.error("invalid_state", "Wi-Fi bridge was disposed.", null);
            pendingPermissionResult = null;
        }
        channel.setMethodCallHandler(null);
        networkEventsChannel.setStreamHandler(null);
        networkEventsSink = null;
    }
}
