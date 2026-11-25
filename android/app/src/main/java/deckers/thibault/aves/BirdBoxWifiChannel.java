package deckers.thibault.aves;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.location.LocationManager;
import android.net.Uri;
import android.net.wifi.WifiInfo;
import android.net.wifi.WifiManager;
import android.provider.MediaStore;
import android.provider.Settings;
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
import androidx.annotation.RequiresApi;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import androidx.core.location.LocationManagerCompat;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
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
    private static final int PICK_IMAGE_REQUEST = 0xB173;
    private static final int JOIN_TIMEOUT_MS = 30000;
    /** Local-only guard: a QR photo is a few megabytes at most and is deleted after parsing. */
    private static final long MAX_PICKED_IMAGE_BYTES = 32L * 1024L * 1024L;

    private final Activity activity;
    private final ConnectivityManager connectivityManager;
    private final MethodChannel channel;
    private final EventChannel networkEventsChannel;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final Object stateLock = new Object();

    @Nullable private EventChannel.EventSink networkEventsSink;
    @Nullable private MethodChannel.Result pendingPermissionResult;
    @Nullable private MethodChannel.Result pendingPickResult;
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
            case "networkSnapshot":
                final Map<String, Object> snapshot = new LinkedHashMap<>();
                final Network active = connectivityManager == null ? null : connectivityManager.getActiveNetwork();
                final NetworkCapabilities caps = active == null ? null : connectivityManager.getNetworkCapabilities(active);
                snapshot.put("transport", caps == null ? "unknown" : caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ? "wifi" : caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) ? "cellular" : "other");
                boolean ssidAvailable = false;
                try {
                    final android.net.wifi.WifiManager manager = (android.net.wifi.WifiManager) activity.getApplicationContext().getSystemService(Context.WIFI_SERVICE);
                    final String ssid = manager == null || manager.getConnectionInfo() == null ? null : manager.getConnectionInfo().getSSID();
                    ssidAvailable = ssid != null && !"<unknown ssid>".equals(ssid);
                } catch (SecurityException ignored) {
                    // Diagnostics do not request additional location permissions.
                }
                snapshot.put("ssid_available", ssidAvailable);
                result.success(snapshot);
                return;
            case "openWifiSettings":
                try {
                    activity.startActivity(new Intent(Settings.ACTION_WIFI_SETTINGS));
                    result.success(null);
                } catch (Exception error) {
                    result.error("wifi_settings_unavailable", "Open WLAN settings manually.", null);
                }
                return;
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
                releaseNetwork("user_cancelled".equals(call.argument("reason")));
                result.success(null);
                return;
            case "currentSsid":
                currentSsid(result);
                return;
            case "pickWifiQrImage":
                pickWifiQrImage(result);
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

    /**
     * Read-only hint used to pre-fill the provisioning form. The SSID is returned to the page
     * only and is never cached, logged or forwarded to diagnostics; when it cannot be read the
     * caller gets an explicit reason instead of an empty string.
     */
    private void currentSsid(@NonNull MethodChannel.Result result) {
        final Map<String, Object> response = new LinkedHashMap<>();
        response.put("ssid", null);
        response.put("reason", null);
        // Android still gates SSID visibility on location permission; NEARBY_WIFI_DEVICES is not enough.
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            // Android 12+ lets the user grant only an approximate location, which is not enough to read the SSID.
            final boolean approximate = ContextCompat.checkSelfPermission(activity, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED;
            response.put("reason", approximate ? "permission_approximate" : "permission_denied");
            result.success(response);
            return;
        }
        if (!isLocationEnabled()) {
            response.put("reason", "location_disabled");
            result.success(response);
            return;
        }
        try {
            final WifiManager manager = (WifiManager) activity.getApplicationContext().getSystemService(Context.WIFI_SERVICE);
            final WifiInfo info = manager == null ? null : manager.getConnectionInfo();
            final String ssid = normalizeSsid(info == null ? null : info.getSSID());
            if (ssid == null) {
                response.put("reason", "unavailable");
            } else {
                response.put("ssid", ssid);
            }
        } catch (SecurityException error) {
            response.put("reason", "permission_denied");
        } catch (RuntimeException error) {
            response.put("reason", "unavailable");
        }
        result.success(response);
    }

    @Nullable
    private static String normalizeSsid(@Nullable String raw) {
        if (raw == null) return null;
        String value = raw.trim();
        if (value.length() >= 2 && value.startsWith("\"") && value.endsWith("\"")) {
            value = value.substring(1, value.length() - 1);
        }
        if (value.isEmpty() || "0x".equalsIgnoreCase(value) || "<unknown ssid>".equalsIgnoreCase(value)) return null;
        return value;
    }

    private boolean isLocationEnabled() {
        try {
            final LocationManager manager = (LocationManager) activity.getSystemService(Context.LOCATION_SERVICE);
            if (manager == null) return true;
            return LocationManagerCompat.isLocationEnabled(manager);
        } catch (RuntimeException error) {
            // Diagnostics must not fail when the setting is unreadable.
            return true;
        }
    }

    /** Opens the system image picker so a standard Wi-Fi QR photo can be imported (D1). */
    private void pickWifiQrImage(@NonNull MethodChannel.Result result) {
        if (pendingPickResult != null) {
            result.error("invalid_state", "An image picker is already active.", null);
            return;
        }
        final Intent selected = resolveImagePickerIntent();
        if (selected == null) {
            result.error("picker_unavailable", "No system image picker is available.", null);
            return;
        }
        pendingPickResult = result;
        try {
            activity.startActivityForResult(selected, PICK_IMAGE_REQUEST);
        } catch (RuntimeException error) {
            pendingPickResult = null;
            result.error("picker_unavailable", "The system image picker could not be opened.", null);
        }
    }

    @Nullable
    private Intent resolveImagePickerIntent() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            final Intent photoPicker = new Intent(MediaStore.ACTION_PICK_IMAGES);
            photoPicker.setType("image/*");
            photoPicker.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            if (photoPicker.resolveActivity(activity.getPackageManager()) != null) return photoPicker;
        }
        final Intent documents = new Intent(Intent.ACTION_GET_CONTENT);
        documents.addCategory(Intent.CATEGORY_OPENABLE);
        documents.setType("image/*");
        documents.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        return documents.resolveActivity(activity.getPackageManager()) == null ? null : documents;
    }

    boolean onActivityResult(int requestCode, int resultCode, @Nullable Intent data) {
        if (requestCode != PICK_IMAGE_REQUEST) return false;
        final MethodChannel.Result result = pendingPickResult;
        pendingPickResult = null;
        if (result == null) return true;
        final Uri picked = resultCode == Activity.RESULT_OK && data != null ? data.getData() : null;
        if (picked == null) {
            // Cancelling the picker is a normal outcome: the page keeps its state and can retry.
            result.success(null);
            return true;
        }
        copyPickedImage(picked, result);
        return true;
    }

    private void copyPickedImage(@NonNull Uri uri, @NonNull MethodChannel.Result result) {
        final Thread worker = new Thread(() -> {
            File target = null;
            String path = null;
            String failure = null;
            try {
                final File directory = new File(activity.getCacheDir(), "wifi_qr_import");
                if (!directory.isDirectory() && !directory.mkdirs()) throw new IOException("cache directory unavailable");
                deleteChildren(directory);
                target = new File(directory, "qr-" + System.nanoTime() + guessImageExtension(uri));
                long total = 0L;
                try (InputStream source = activity.getContentResolver().openInputStream(uri);
                     OutputStream sink = new FileOutputStream(target)) {
                    if (source == null) throw new IOException("selected image cannot be opened");
                    final byte[] buffer = new byte[16 * 1024];
                    int read;
                    while ((read = source.read(buffer)) > 0) {
                        total += read;
                        if (total > MAX_PICKED_IMAGE_BYTES) throw new IOException("selected image is too large");
                        sink.write(buffer, 0, read);
                    }
                }
                if (total == 0L) throw new IOException("selected image is empty");
                path = target.getAbsolutePath();
            } catch (IOException | SecurityException error) {
                failure = "The selected image could not be read.";
            }
            if (failure != null && target != null) {
                try {
                    deleteCachedImage(target);
                } catch (IOException | SecurityException cleanupError) {
                    failure = "The selected image could not be removed from temporary storage.";
                }
            }
            final String resolvedPath = path;
            final String failureReason = failure;
            mainHandler.post(() -> {
                if (failureReason != null) {
                    result.error("picker_read_failed", failureReason, null);
                } else {
                    result.success(resolvedPath);
                }
            });
        }, "birdbox-wifi-qr-import");
        worker.setDaemon(true);
        worker.start();
    }

    @NonNull
    private String guessImageExtension(@NonNull Uri uri) {
        final String type;
        try {
            type = activity.getContentResolver().getType(uri);
        } catch (RuntimeException error) {
            return ".img";
        }
        if (type == null) return ".img";
        return switch (type) {
            case "image/jpeg" -> ".jpg";
            case "image/png" -> ".png";
            case "image/webp" -> ".webp";
            case "image/gif" -> ".gif";
            case "image/heic", "image/heif" -> ".heic";
            default -> ".img";
        };
    }

    private static void deleteChildren(@NonNull File directory) throws IOException {
        final File[] children = directory.listFiles();
        if (children == null) return;
        for (File child : children) {
            // Only copies written by this channel live in the directory.
            if (child.isFile()) deleteCachedImage(child);
        }
    }

    private static void deleteCachedImage(@NonNull File image) throws IOException {
        if (!image.delete() && image.exists()) {
            // Do not silently accumulate QR images that may contain credentials.
            // The existing picker_read_failed path reports a generic failure.
            throw new IOException("QR cache cleanup did not complete");
        }
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
        // Normal permission: only the packaged manifest can grant it.
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.CHANGE_NETWORK_STATE) != PackageManager.PERMISSION_GRANTED) {
            result.error("wifi_change_network_state_missing", "APK missing android.permission.CHANGE_NETWORK_STATE.", null);
            return;
        }
        if (pendingJoinResult != null) {
            result.error("invalid_state", "A Wi-Fi join request is already active.", null);
            return;
        }
        final String ssid = call.argument("ssid");
        final String passphrase = call.argument("passphrase");
        final String security = call.argument("security");
        if (ssid == null || ssid.isEmpty() || passphrase == null || passphrase.isEmpty()) {
            result.error("invalid_request", "SSID and passphrase are required.", null);
            return;
        }

        if (!isSupportedDirectApSecurity(security)) {
            result.error("wifi_security_unsupported", "The box Wi-Fi security type is unsupported.", null);
            return;
        }
        final WifiManager wifiManager = (WifiManager) activity.getApplicationContext().getSystemService(Context.WIFI_SERVICE);
        if ("wpa3_personal".equals(security) && (wifiManager == null || !wifiManager.isWpa3SaeSupported())) {
            result.error("wifi_security_unsupported", "WPA3 is unavailable on this phone.", null);
            return;
        }
        final WifiNetworkSpecifier specifier;
        final NetworkRequest request;
        try {
            specifier = directApSpecifier(ssid, passphrase, security);
            request = new NetworkRequest.Builder()
                    .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                    .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                    .setNetworkSpecifier(specifier)
                    .build();
        } catch (IllegalArgumentException | IllegalStateException error) {
            result.error("invalid_request", "The Wi-Fi request is invalid.", null);
            return;
        }

        releaseNetwork(false);
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
                    if (isStaleCallback(this, generation)) return;
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
                // Android uses the same callback for denial and connection
                // failure. Without stronger evidence do not call it rejection.
                completeJoinUnavailable(this, generation);
            }

            @Override
            public void onLost(@NonNull Network network) {
                final String handle;
                final String ssid;
                synchronized (stateLock) {
                    if (isStaleCallback(this, generation) || !network.equals(requestedNetwork)) return;
                    handle = Long.toUnsignedString(network.getNetworkHandle());
                    ssid = requestedSsid;
                    requestedNetwork = null;
                    unbindProcess();
                }
                emitNetworkLost(handle, ssid);
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

    static boolean isSupportedDirectApSecurity(@Nullable String security) {
        return "wpa2_personal".equals(security) || "wpa3_personal".equals(security)
                || "wpa2_wpa3_transition".equals(security);
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    static WifiNetworkSpecifier directApSpecifier(String ssid, String passphrase, String security) {
        if (!isSupportedDirectApSecurity(security)) throw new IllegalArgumentException("Unsupported AP security");
        final WifiNetworkSpecifier.Builder builder = new WifiNetworkSpecifier.Builder().setSsid(ssid);
        if ("wpa3_personal".equals(security)) builder.setWpa3Passphrase(passphrase);
        // Transition mode explicitly permits WPA2; never silently map an
        // unknown or WPA3-only AP to a WPA2 request.
        else builder.setWpa2Passphrase(passphrase);
        return builder.build();
    }

    private void bindProcessToNetwork(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        if (connectivityManager == null) {
            result.error("wifi_unsupported", "Connectivity service is unavailable.", null);
            return;
        }
        synchronized (stateLock) {
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
    }

    private void completeJoinUnavailable(
            @NonNull ConnectivityManager.NetworkCallback callback,
            long generation
    ) {
        final MethodChannel.Result result;
        synchronized (stateLock) {
            if (isStaleCallback(callback, generation)) return;
            result = pendingJoinResult;
            pendingJoinResult = null;
        }
        releaseCallback(callback, generation);
        if (result != null) {
            final Map<String, Object> response = new LinkedHashMap<>();
            response.put("outcome", "unavailable");
            response.put("errorCode", "wifi_request_unavailable");
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

    private boolean isStaleCallback(
            @NonNull ConnectivityManager.NetworkCallback callback,
            long generation
    ) {
        return disposed || generation != requestGeneration || callback != networkCallback;
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
        final ConnectivityManager.NetworkCallback callback;
        final MethodChannel.Result pending;
        synchronized (stateLock) {
            unbindProcess();
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
            @Nullable String ssid
    ) {
        final EventChannel.EventSink sink = networkEventsSink;
        if (sink == null || disposed) return;
        final Map<String, Object> event = networkLostEvent(handle, ssid, "network_lost");
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
        if (pendingPickResult != null) {
            pendingPickResult.error("invalid_state", "Wi-Fi bridge was disposed.", null);
            pendingPickResult = null;
        }
        channel.setMethodCallHandler(null);
        networkEventsChannel.setStreamHandler(null);
        networkEventsSink = null;
    }
}
