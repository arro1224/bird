package deckers.thibault.aves;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.os.Handler;
import android.os.Looper;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;

import androidx.annotation.NonNull;

import java.net.InetAddress;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public final class MainActivity extends FlutterActivity {
    private static final String DISCOVERY_CHANNEL = "bird_companion/device_discovery";
    private static final String SECURE_SESSION_CHANNEL = "bird_companion/secure_session";
    private static final String CLIENT_IDENTITY_CHANNEL = "bird_companion/client_identity";
    private static final String SESSION_PREFERENCES = "bird_companion_secure_sessions";
    private static final String SESSION_KEY_ALIAS = "bird_companion_session_key_v1";
    private static final String CLIENT_IDENTITY_PREFERENCE = "installation_client_identity";
    private BirdBoxBleChannel birdBoxBleChannel;
    private BirdBoxWifiChannel birdBoxWifiChannel;
    private BirdBoxDppChannel birdBoxDppChannel;

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        birdBoxBleChannel = new BirdBoxBleChannel(this, flutterEngine.getDartExecutor().getBinaryMessenger());
        birdBoxWifiChannel = new BirdBoxWifiChannel(this, flutterEngine.getDartExecutor().getBinaryMessenger());
        birdBoxDppChannel = new BirdBoxDppChannel(this, flutterEngine.getDartExecutor().getBinaryMessenger());
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), DISCOVERY_CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    if ("discover".equals(call.method)) {
                        discover(call, result);
                    } else {
                        result.notImplemented();
                    }
                });
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), SECURE_SESSION_CHANNEL)
                .setMethodCallHandler(this::handleSecureSession);
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CLIENT_IDENTITY_CHANNEL)
                .setMethodCallHandler(this::handleClientIdentity);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        final boolean handledByDpp = birdBoxDppChannel != null
                && birdBoxDppChannel.onActivityResult(requestCode, resultCode);
        if (!handledByDpp) {
            super.onActivityResult(requestCode, resultCode, data);
        }
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, @NonNull String[] permissions, @NonNull int[] grantResults) {
        final boolean handledByBle = birdBoxBleChannel != null && birdBoxBleChannel.onRequestPermissionsResult(requestCode, grantResults);
        final boolean handledByWifi = birdBoxWifiChannel != null && birdBoxWifiChannel.onRequestPermissionsResult(requestCode, grantResults);
        if (!handledByBle && !handledByWifi) {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        }
    }

    @Override
    public void cleanUpFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        if (birdBoxBleChannel != null) {
            birdBoxBleChannel.dispose();
            birdBoxBleChannel = null;
        }
        if (birdBoxWifiChannel != null) {
            birdBoxWifiChannel.dispose();
            birdBoxWifiChannel = null;
        }
        if (birdBoxDppChannel != null) {
            birdBoxDppChannel.dispose();
            birdBoxDppChannel = null;
        }
        super.cleanUpFlutterEngine(flutterEngine);
    }

    @Override
    protected void onDestroy() {
        if (birdBoxDppChannel != null) {
            birdBoxDppChannel.onHostDestroying(isChangingConfigurations());
        }
        super.onDestroy();
    }

    private void handleClientIdentity(MethodCall call, MethodChannel.Result result) {
        try {
            final SharedPreferences preferences = getSharedPreferences(
                    SESSION_PREFERENCES,
                    Context.MODE_PRIVATE
            );
            switch (call.method) {
                case "read":
                    final String encrypted = preferences.getString(CLIENT_IDENTITY_PREFERENCE, null);
                    if (encrypted == null) {
                        result.success(null);
                        return;
                    }
                    try {
                        result.success(decryptSession(encrypted));
                    } catch (Exception corruptIdentity) {
                        preferences.edit().remove(CLIENT_IDENTITY_PREFERENCE).apply();
                        result.success(null);
                    }
                    return;
                case "write":
                    final String clientId = call.argument("clientId");
                    if (clientId == null || clientId.isEmpty()) {
                        result.error("invalid_client_id", "A client id is required.", null);
                        return;
                    }
                    preferences.edit()
                            .putString(CLIENT_IDENTITY_PREFERENCE, encryptSession(clientId))
                            .apply();
                    result.success(null);
                    return;
                case "delete":
                    preferences.edit().remove(CLIENT_IDENTITY_PREFERENCE).apply();
                    result.success(null);
                    return;
                default:
                    result.notImplemented();
            }
        } catch (Exception error) {
            result.error("client_identity_failed", "Client identity operation failed.", null);
        }
    }

    private void handleSecureSession(MethodCall call, MethodChannel.Result result) {
        final String deviceId = call.argument("deviceId");
        if (deviceId == null || deviceId.trim().isEmpty()) {
            result.error("invalid_device_id", "A device id is required.", null);
            return;
        }
        try {
            final SharedPreferences preferences = getSharedPreferences(
                    SESSION_PREFERENCES,
                    Context.MODE_PRIVATE
            );
            final String preferenceKey = securePreferenceKey(deviceId);
            switch (call.method) {
                case "read":
                    final String encrypted = preferences.getString(preferenceKey, null);
                    if (encrypted == null) {
                        result.success(null);
                        return;
                    }
                    try {
                        result.success(decryptSession(encrypted));
                    } catch (Exception corruptSession) {
                        preferences.edit().remove(preferenceKey).apply();
                        result.error("secure_session_unreadable", "The saved session cannot be restored.", null);
                    }
                    return;
                case "write":
                    final String payload = call.argument("payload");
                    if (payload == null || payload.isEmpty()) {
                        result.error("invalid_payload", "A session payload is required.", null);
                        return;
                    }
                    preferences.edit().putString(preferenceKey, encryptSession(payload)).apply();
                    result.success(null);
                    return;
                case "delete":
                    preferences.edit().remove(preferenceKey).apply();
                    result.success(null);
                    return;
                default:
                    result.notImplemented();
            }
        } catch (Exception error) {
            // Never return token material, plaintext payloads, or pairing data
            // in platform errors.
            result.error("secure_session_failed", "Secure session operation failed.", null);
        }
    }

    private String encryptSession(String payload) throws Exception {
        final Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE, sessionKey());
        final String iv = Base64.encodeToString(cipher.getIV(), Base64.NO_WRAP);
        final String ciphertext = Base64.encodeToString(
                cipher.doFinal(payload.getBytes(StandardCharsets.UTF_8)),
                Base64.NO_WRAP
        );
        return iv + ":" + ciphertext;
    }

    private String decryptSession(String encrypted) throws Exception {
        final String[] parts = encrypted.split(":", 2);
        if (parts.length != 2) throw new IllegalArgumentException("Invalid encrypted session.");
        final byte[] iv = Base64.decode(parts[0], Base64.NO_WRAP);
        final byte[] ciphertext = Base64.decode(parts[1], Base64.NO_WRAP);
        final Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.DECRYPT_MODE, sessionKey(), new GCMParameterSpec(128, iv));
        return new String(cipher.doFinal(ciphertext), StandardCharsets.UTF_8);
    }

    private SecretKey sessionKey() throws Exception {
        final KeyStore keyStore = KeyStore.getInstance("AndroidKeyStore");
        keyStore.load(null);
        final KeyStore.Entry existing = keyStore.getEntry(SESSION_KEY_ALIAS, null);
        if (existing instanceof KeyStore.SecretKeyEntry) {
            return ((KeyStore.SecretKeyEntry) existing).getSecretKey();
        }
        final KeyGenerator generator = KeyGenerator.getInstance(
                KeyProperties.KEY_ALGORITHM_AES,
                "AndroidKeyStore"
        );
        generator.init(new KeyGenParameterSpec.Builder(
                SESSION_KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT
        ).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build());
        return generator.generateKey();
    }

    private String securePreferenceKey(String deviceId) throws Exception {
        final byte[] digest = MessageDigest.getInstance("SHA-256")
                .digest(deviceId.getBytes(StandardCharsets.UTF_8));
        return "session_" + Base64.encodeToString(
                digest,
                Base64.URL_SAFE | Base64.NO_WRAP | Base64.NO_PADDING
        );
    }

    private void discover(MethodCall call, MethodChannel.Result result) {
        final String serviceType = call.argument("serviceType");
        final Integer timeoutMs = call.argument("timeoutMs");
        if (serviceType == null || serviceType.isEmpty()) {
            result.error("invalid_service_type", "A service type is required.", null);
            return;
        }

        final NsdManager manager = (NsdManager) getSystemService(Context.NSD_SERVICE);
        if (manager == null) {
            result.error("nsd_unavailable", "Network service discovery is unavailable.", null);
            return;
        }

        final Handler handler = new Handler(Looper.getMainLooper());
        final List<Map<String, Object>> devices = new ArrayList<>();
        final Set<String> resolvedServices = new HashSet<>();
        final boolean[] finished = {false};
        final NsdManager.DiscoveryListener[] listener = new NsdManager.DiscoveryListener[1];

        final Runnable finish = () -> {
            if (finished[0]) return;
            finished[0] = true;
            try {
                manager.stopServiceDiscovery(listener[0]);
            } catch (IllegalArgumentException ignored) {
                // Discovery may have failed before it started.
            }
            result.success(devices);
        };

        listener[0] = new NsdManager.DiscoveryListener() {
            @Override public void onDiscoveryStarted(String type) {}

            @Override public void onServiceFound(NsdServiceInfo service) {
                if (finished[0] || !serviceType.equals(service.getServiceType())) return;
                final String key = service.getServiceName() + "@" + service.getServiceType();
                if (!resolvedServices.add(key)) return;
                manager.resolveService(service, new NsdManager.ResolveListener() {
                    @Override public void onResolveFailed(NsdServiceInfo ignored, int errorCode) {}

                    @Override public void onServiceResolved(NsdServiceInfo resolved) {
                        final InetAddress host = resolved.getHost();
                        final int port = resolved.getPort();
                        if (finished[0] || host == null || port < 1) return;
                        final Map<String, Object> device = new LinkedHashMap<>();
                        device.put("name", resolved.getServiceName());
                        device.put("host", host.getHostAddress());
                        device.put("port", port);
                        devices.add(device);
                    }
                });
            }

            @Override public void onServiceLost(NsdServiceInfo service) {}

            @Override public void onDiscoveryStopped(String type) {}

            @Override public void onStartDiscoveryFailed(String type, int errorCode) {
                finish.run();
            }

            @Override public void onStopDiscoveryFailed(String type, int errorCode) {
                finish.run();
            }
        };

        try {
            manager.discoverServices(serviceType, NsdManager.PROTOCOL_DNS_SD, listener[0]);
            handler.postDelayed(finish, timeoutMs == null ? 3000 : Math.max(timeoutMs, 1000));
        } catch (IllegalArgumentException error) {
            result.error("nsd_start_failed", error.getMessage(), null);
        }
    }
}
