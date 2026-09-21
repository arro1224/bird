package deckers.thibault.aves;

import android.Manifest;
import android.app.Activity;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothGatt;
import android.bluetooth.BluetoothGattCallback;
import android.bluetooth.BluetoothGattCharacteristic;
import android.bluetooth.BluetoothGattDescriptor;
import android.bluetooth.BluetoothGattService;
import android.bluetooth.BluetoothManager;
import android.bluetooth.BluetoothProfile;
import android.bluetooth.le.BluetoothLeScanner;
import android.bluetooth.le.ScanCallback;
import android.bluetooth.le.ScanRecord;
import android.bluetooth.le.ScanResult;
import android.bluetooth.le.ScanSettings;
import android.content.Context;
import android.content.BroadcastReceiver;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.content.pm.PackageInfo;
import android.location.LocationManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.ParcelUuid;
import android.util.SparseArray;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import java.io.FileInputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/** Raw, secret-safe Android BLE bridge for the rc4 BirdBox network service. */
public final class BirdBoxBleChannel implements MethodChannel.MethodCallHandler {
    private static final String METHOD_CHANNEL = "bird_companion/birdbox_ble/methods";
    private static final String SCAN_CHANNEL = "bird_companion/birdbox_ble/scan";
    private static final String NOTIFICATION_CHANNEL = "bird_companion/birdbox_ble/notifications";
    private static final String DISCONNECT_CHANNEL = "bird_companion/birdbox_ble/disconnects";
    private static final String DIAGNOSTIC_CHANNEL = "bird_companion/birdbox_ble/diagnostics";
    private static final int PERMISSION_REQUEST_CODE = 6204;
    // ATT error 0x0c is not exposed as a BluetoothGatt constant on all SDKs.
    static final int GATT_INSUFFICIENT_ENCRYPTION_KEY_SIZE = 0x0c;
    // ATT error 0x08 may be surfaced as a raw authorization failure by vendor stacks.
    static final int GATT_INSUFFICIENT_AUTHORIZATION = 0x08;

    private static final UUID SERVICE_UUID = UUID.fromString("6f7d0001-7a66-4c45-a1b9-5f4d2e3c1000");
    private static final UUID DEVICE_INFO_UUID = UUID.fromString("6f7d0002-7a66-4c45-a1b9-5f4d2e3c1000");
    private static final UUID NETWORK_STATUS_UUID = UUID.fromString("6f7d0003-7a66-4c45-a1b9-5f4d2e3c1000");
    private static final UUID WIFI_CONFIG_UUID = UUID.fromString("6f7d0004-7a66-4c45-a1b9-5f4d2e3c1000");
    private static final UUID PROVISIONING_COMMAND_UUID = UUID.fromString("6f7d0005-7a66-4c45-a1b9-5f4d2e3c1000");
    private static final UUID SCAN_RESULTS_UUID = UUID.fromString("6f7d0006-7a66-4c45-a1b9-5f4d2e3c1000");
    private static final UUID CLIENT_CONFIGURATION_UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb");
    private static final List<UUID> REQUIRED_CHARACTERISTICS = Arrays.asList(
            DEVICE_INFO_UUID,
            NETWORK_STATUS_UUID,
            WIFI_CONFIG_UUID,
            PROVISIONING_COMMAND_UUID,
            SCAN_RESULTS_UUID
    );

    private final Activity activity;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final BirdBoxSecurityWriteStateMachine securityWriteStateMachine =
            new BirdBoxSecurityWriteStateMachine();
    private final BluetoothAdapter adapter;
    private final MethodChannel methodChannel;
    private final EventChannel scanEventChannel;
    private final EventChannel notificationEventChannel;
    private final EventChannel disconnectEventChannel;
    private final EventChannel diagnosticEventChannel;

    @Nullable private EventChannel.EventSink scanSink;
    @Nullable private EventChannel.EventSink notificationSink;
    @Nullable private EventChannel.EventSink disconnectSink;
    @Nullable private EventChannel.EventSink diagnosticSink;
    @Nullable private BluetoothLeScanner scanner;
    @Nullable private volatile BluetoothGatt gatt;
    @Nullable private volatile BluetoothDevice connectedDevice;
    @Nullable private MethodChannel.Result pendingPermissionResult;
    @Nullable private MethodChannel.Result pendingOperationResult;
    @Nullable private volatile String pendingOperation;
    @Nullable private Runnable pendingOperationTimeout;
    @Nullable private Runnable scanTimeout;
    @Nullable private String activeScanSessionId;
    @Nullable private volatile String activeTraceId;
    @Nullable private BroadcastReceiver bondStateReceiver;
    @Nullable private String activeSecurityRequestId;
    @Nullable private String activeSecurityCommandType;
    @Nullable private String connectedDeviceAddressHash;
    @Nullable private String previousBondState;
    @Nullable private Boolean pendingNotificationEnabled;
    @NonNull private volatile String installedApkSha256 = BuildConfig.APK_SHA256;
    private boolean securityBondingObserved;
    private boolean systemPairingInteraction;
    private boolean gattRebuilt;
    private boolean scanning;
    private boolean firstScanCallbackEmitted;
    private int currentMtu = 23;
    private int gattGeneration;
    private volatile boolean linkReady;
    private volatile boolean disconnectRequested;
    private volatile boolean securityFailureObserved;
    private volatile boolean disposed;

    public BirdBoxBleChannel(@NonNull Activity activity, @NonNull BinaryMessenger messenger) {
        this.activity = activity;
        final BluetoothManager manager = (BluetoothManager) activity.getSystemService(Context.BLUETOOTH_SERVICE);
        adapter = manager == null ? null : manager.getAdapter();
        methodChannel = new MethodChannel(messenger, METHOD_CHANNEL);
        scanEventChannel = new EventChannel(messenger, SCAN_CHANNEL);
        notificationEventChannel = new EventChannel(messenger, NOTIFICATION_CHANNEL);
        disconnectEventChannel = new EventChannel(messenger, DISCONNECT_CHANNEL);
        diagnosticEventChannel = new EventChannel(messenger, DIAGNOSTIC_CHANNEL);
        methodChannel.setMethodCallHandler(this);
        scanEventChannel.setStreamHandler(streamHandler(sink -> scanSink = sink, () -> scanSink = null));
        notificationEventChannel.setStreamHandler(streamHandler(sink -> notificationSink = sink, () -> notificationSink = null));
        disconnectEventChannel.setStreamHandler(streamHandler(sink -> disconnectSink = sink, () -> disconnectSink = null));
        diagnosticEventChannel.setStreamHandler(streamHandler(sink -> diagnosticSink = sink, () -> diagnosticSink = null));
        startApkDigest();
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        if (disposed && !"dispose".equals(call.method)) {
            result.error("invalid_state", "BLE bridge is disposed.", null);
            return;
        }
        switch (call.method) {
            case "getScanEnvironment":
                result.success(scanEnvironment());
                break;
            case "ensurePermissions":
                ensurePermissions(result);
                break;
            case "startScan":
                startScan(call, result);
                break;
            case "stopScan":
                stopScan();
                result.success(null);
                break;
            case "connect":
                connect(call, result);
                break;
            case "disconnect":
                failPending("gatt_operation_failed", "GATT operation was interrupted by disconnect.");
                disconnectRequested = true;
                closeGatt(true, "requested", BluetoothGatt.GATT_SUCCESS);
                result.success(null);
                break;
            case "requestMtu":
                requestMtu(call, result);
                break;
            case "readCharacteristic":
                readCharacteristic(call, result);
                break;
            case "setNotify":
                setNotify(call, result);
                break;
            case "writeWithResponse":
                writeWithResponse(call, result);
                break;
            case "beginSecurityWrite":
                beginSecurityWrite(call, result);
                break;
            case "awaitSecurityReady":
                awaitSecurityReady(call, result);
                break;
            case "beginSecurityRetry":
                beginSecurityRetry(call, result);
                break;
            case "markSecurityWriteSent":
                markSecurityWriteSent(call, result);
                break;
            case "completeSecurityWrite":
                completeSecurityWrite(call, result);
                break;
            case "failSecurityWrite":
                failSecurityWrite(call, result);
                break;
            case "dispose":
                dispose();
                result.success(null);
                break;
            default:
                result.notImplemented();
        }
    }

    private void ensurePermissions(MethodChannel.Result result) {
        final List<String> missing = missingPermissions();
        if (missing.isEmpty()) {
            result.success(true);
            return;
        }
        if (pendingPermissionResult != null) {
            result.error("gatt_busy", "A Bluetooth permission request is already active.", null);
            return;
        }
        pendingPermissionResult = result;
        activity.requestPermissions(missing.toArray(new String[0]), PERMISSION_REQUEST_CODE);
    }

    public boolean onRequestPermissionsResult(int requestCode, @NonNull int[] grantResults) {
        if (requestCode != PERMISSION_REQUEST_CODE) return false;
        final MethodChannel.Result result = pendingPermissionResult;
        pendingPermissionResult = null;
        if (result != null) {
            boolean granted = grantResults.length > 0;
            for (int grantResult : grantResults) granted &= grantResult == PackageManager.PERMISSION_GRANTED;
            result.success(granted);
        }
        return true;
    }

    private List<String> missingPermissions() {
        final List<String> permissions = new ArrayList<>();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            addIfMissing(permissions, Manifest.permission.BLUETOOTH_SCAN);
            addIfMissing(permissions, Manifest.permission.BLUETOOTH_CONNECT);
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            addIfMissing(permissions, Manifest.permission.ACCESS_FINE_LOCATION);
        }
        return permissions;
    }

    private void addIfMissing(List<String> permissions, String permission) {
        if (activity.checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED) permissions.add(permission);
    }

    @NonNull
    private Map<String, Object> scanEnvironment() {
        final Map<String, Object> environment = new LinkedHashMap<>();
        environment.put("permissionGranted", missingPermissions().isEmpty());
        environment.put("adapterState", adapter == null ? "unavailable" : adapter.isEnabled() ? "enabled" : "disabled");
        environment.put("scanPermission", permissionState(
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.S,
                Manifest.permission.BLUETOOTH_SCAN
        ));
        environment.put("connectPermission", permissionState(
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.S,
                Manifest.permission.BLUETOOTH_CONNECT
        ));
        environment.put("locationPermission", permissionState(
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && Build.VERSION.SDK_INT < Build.VERSION_CODES.S,
                Manifest.permission.ACCESS_FINE_LOCATION
        ));
        environment.put("locationService", locationServiceState());
        environment.put("manufacturer", Build.MANUFACTURER);
        environment.put("model", Build.MODEL);
        environment.put("androidRelease", Build.VERSION.RELEASE);
        environment.put("sdkInt", Build.VERSION.SDK_INT);
        environment.put("gitCommit", BuildConfig.GIT_SHA);
        environment.put("apkSha256", apkSha256());
        environment.put("scanPermissionPolicy", BuildConfig.BLE_SCAN_PERMISSION_POLICY);
        environment.put("scanMode", "low_latency");
        addPackageMetadata(environment);
        return environment;
    }

    @NonNull
    private String permissionState(boolean required, @NonNull String permission) {
        if (!required) return "not_required";
        return activity.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
                ? "granted"
                : "denied";
    }

    @NonNull
    private String locationServiceState() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return "not_required";
        }
        final LocationManager manager = (LocationManager) activity.getSystemService(Context.LOCATION_SERVICE);
        if (manager == null) return "unknown";
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                return manager.isLocationEnabled() ? "enabled" : "disabled";
            }
            return manager.isProviderEnabled(LocationManager.GPS_PROVIDER)
                    || manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
                    ? "enabled"
                    : "disabled";
        } catch (RuntimeException ignored) {
            return "unknown";
        }
    }

    private boolean requireBluetooth(MethodChannel.Result result) {
        if (adapter == null || !adapter.isEnabled()) {
            result.error("bluetooth_unavailable", "Bluetooth is unavailable or disabled.", null);
            return false;
        }
        if (!missingPermissions().isEmpty()) {
            result.error("bluetooth_permission_denied", "Required Bluetooth permission is missing.", null);
            return false;
        }
        return true;
    }

    private void startScan(MethodCall call, MethodChannel.Result result) {
        if (!requireBluetooth(result)) return;
        if (scanning) {
            final Map<String, Object> details = new LinkedHashMap<>();
            details.put(
                    "scanSessionId",
                    activeScanSessionId == null ? "native-unknown" : activeScanSessionId
            );
            result.error(
                    "gatt_busy",
                    "A BLE scan is already active; stop it before starting another session.",
                    details
            );
            return;
        }
        scanner = adapter.getBluetoothLeScanner();
        if (scanner == null) {
            result.error("bluetooth_unavailable", "BLE scanner is unavailable.", null);
            return;
        }
        final Integer timeoutMs = call.argument("timeoutMs");
        final String scanSessionId = call.argument("scanSessionId");
        final long timeout = timeoutMs == null ? 10000L : Math.max(1000L, timeoutMs.longValue());
        try {
            final ScanSettings settings = new ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build();
            // An unfiltered scan permits the Local Name compatibility fallback. Results
            // containing the frozen Service UUID remain the primary accepted path.
            activeScanSessionId = scanSessionId == null || scanSessionId.isEmpty() ? "native-unknown" : scanSessionId;
            activeTraceId = activeScanSessionId;
            firstScanCallbackEmitted = false;
            scanner.startScan(null, settings, scanCallback);
            scanning = true;
            emitDiagnostic("scan_started", "scan", -1, null, "success");
            scanTimeout = this::stopScan;
            mainHandler.postDelayed(scanTimeout, timeout);
            result.success(null);
        } catch (SecurityException error) {
            emitDiagnostic("scan_start_failed", "scan", -1, null, "bluetooth_permission_denied");
            activeScanSessionId = null;
            scanner = null;
            result.error("bluetooth_permission_denied", "Bluetooth scan permission is missing.", null);
        } catch (RuntimeException error) {
            emitDiagnostic("scan_start_failed", "scan", -1, null, "gatt_operation_failed");
            activeScanSessionId = null;
            scanner = null;
            result.error("gatt_operation_failed", "BLE scan could not start.", null);
        }
    }

    private void stopScan() {
        if (scanTimeout != null) mainHandler.removeCallbacks(scanTimeout);
        scanTimeout = null;
        if (!scanning || scanner == null) {
            activeScanSessionId = null;
            return;
        }
        emitDiagnostic("scan_stopped", "scan", -1, null, "success");
        try {
            scanner.stopScan(scanCallback);
        } catch (SecurityException ignored) {
            // Permission may have been revoked while the scan was active.
        }
        scanning = false;
        scanner = null;
        activeScanSessionId = null;
    }

    private final ScanCallback scanCallback = new ScanCallback() {
        @Override
        public void onScanResult(int callbackType, @NonNull ScanResult result) {
            emitScanResult(result);
        }

        @Override
        public void onBatchScanResults(@NonNull List<ScanResult> results) {
            for (ScanResult result : results) emitScanResult(result);
        }

        @Override
        public void onScanFailed(int errorCode) {
            final String failedSessionId = activeScanSessionId;
            scanning = false;
            scanner = null;
            activeScanSessionId = null;
            if (scanTimeout != null) mainHandler.removeCallbacks(scanTimeout);
            scanTimeout = null;
            emitDiagnostic("scan_failed", "scan", errorCode, null, "android_scan_failed");
            final Map<String, Object> diagnostic = new LinkedHashMap<>();
            diagnostic.put("eventType", "scanFailure");
            diagnostic.put("scanSessionId", failedSessionId == null ? "native-unknown" : failedSessionId);
            diagnostic.put("androidScanErrorCode", errorCode);
            emitSuccess(scanSink, diagnostic);
            final Map<String, Object> details = new LinkedHashMap<>();
            details.put("androidScanErrorCode", errorCode);
            details.put("scanSessionId", failedSessionId == null ? "native-unknown" : failedSessionId);
            emitError(scanSink, "gatt_operation_failed", "BLE scan failed.", details);
        }
    };

    private void emitScanResult(ScanResult result) {
        final EventChannel.EventSink sink = scanSink;
        final ScanRecord record = result.getScanRecord();
        if (sink == null) return;
        if (!firstScanCallbackEmitted) {
            firstScanCallbackEmitted = true;
            emitDiagnostic("scan_first_callback", "scan", -1, null, "success");
        }
        if (record == null) {
            emitSuccess(sink, scanObservation(
                    result,
                    null,
                    false,
                    "missing_scan_record",
                    "",
                    new ArrayList<>()
            ));
            return;
        }
        final List<String> serviceUuids = new ArrayList<>();
        boolean hasBirdBoxService = false;
        final List<ParcelUuid> advertised = record.getServiceUuids();
        if (advertised != null) {
            for (ParcelUuid value : advertised) {
                final String normalized = value.getUuid().toString().toLowerCase(Locale.ROOT);
                serviceUuids.add(normalized);
                hasBirdBoxService |= SERVICE_UUID.equals(value.getUuid());
            }
        }
        String localName = record.getDeviceName();
        if (localName == null) localName = "";
        final boolean accepted = hasBirdBoxService || localName.startsWith("BirdBox-");
        final String decisionReason = hasBirdBoxService
                ? "birdbox_service"
                : accepted ? "birdbox_local_name" : "non_birdbox";
        final Map<String, Object> event = scanObservation(
                result,
                record,
                accepted,
                decisionReason,
                localName,
                serviceUuids
        );
        if (!accepted) {
            emitSuccess(sink, event);
            return;
        }
        emitDiagnostic("scan_candidate_found", "scan", -1, null, decisionReason);

        final SparseArray<byte[]> manufacturerData = record.getManufacturerSpecificData();
        Integer companyIdentifier = null;
        byte[] manufacturerPayload = null;
        if (manufacturerData != null && manufacturerData.size() > 0) {
            final int index = manufacturerData.indexOfKey(0xFFFF) >= 0 ? manufacturerData.indexOfKey(0xFFFF) : 0;
            companyIdentifier = manufacturerData.keyAt(index);
            manufacturerPayload = manufacturerData.valueAt(index);
        }
        event.put("deviceId", result.getDevice().getAddress());
        event.put("localName", localName);
        event.put("companyIdentifier", companyIdentifier);
        event.put("manufacturerPayload", manufacturerPayload);
        emitSuccess(sink, event);
    }

    @NonNull
    private Map<String, Object> scanObservation(
            @NonNull ScanResult result,
            @Nullable ScanRecord record,
            boolean accepted,
            @NonNull String decisionReason,
            @NonNull String localName,
            @NonNull List<String> serviceUuids) {
        final Map<String, Object> event = new LinkedHashMap<>();
        event.put("eventType", "advertisement");
        event.put("scanSessionId", activeScanSessionId == null ? "native-unknown" : activeScanSessionId);
        event.put("accepted", accepted);
        event.put("decisionReason", decisionReason);
        event.put("addressHash", saltedAddressHash(result.getDevice().getAddress(), activeScanSessionId));
        if (!localName.isEmpty()) event.put("diagnosticName", localName);
        final String alias = deviceAlias(result.getDevice());
        if (alias != null && !alias.isEmpty()) event.put("diagnosticAlias", alias);
        event.put("rssi", result.getRssi());
        event.put("serviceUuids", serviceUuids);

        int manufacturerDataLength = 0;
        boolean manufacturerDataPresent = false;
        if (record != null) {
            final SparseArray<byte[]> manufacturerData = record.getManufacturerSpecificData();
            if (manufacturerData != null) {
                manufacturerDataPresent = manufacturerData.size() > 0;
                for (int index = 0; index < manufacturerData.size(); index++) {
                    final byte[] value = manufacturerData.valueAt(index);
                    if (value != null) manufacturerDataLength += value.length;
                }
            }
            final byte[] bytes = record.getBytes();
            if (bytes != null) {
                event.put("scanRecordLength", bytes.length);
                event.put("scanRecordSha256", sha256(bytes));
                event.put(
                        "scanRecordRedactedHex",
                        BirdBoxScanRecordRedactor.redactedHex(bytes)
                );
                event.put(
                        "scanRecordTruncated",
                        bytes.length > BirdBoxScanRecordRedactor.MAX_RECORD_BYTES
                );
            }
        }
        event.put("manufacturerDataPresent", manufacturerDataPresent);
        event.put("manufacturerDataLength", manufacturerDataLength);
        return event;
    }

    @Nullable
    private String deviceAlias(@NonNull BluetoothDevice device) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null;
        try {
            return device.getAlias();
        } catch (SecurityException ignored) {
            return null;
        }
    }

    @NonNull
    private static String saltedAddressHash(@Nullable String address, @Nullable String salt) {
        final String safeAddress = address == null ? "unavailable" : address.toLowerCase(Locale.ROOT);
        final String safeSalt = salt == null || salt.isEmpty() ? "no-trace" : salt;
        return sha256((safeSalt + ":" + safeAddress).getBytes(StandardCharsets.UTF_8));
    }

    @NonNull
    private static String sha256(@NonNull byte[] value) {
        try {
            final byte[] digest = MessageDigest.getInstance("SHA-256").digest(value);
            return toHex(digest);
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException("SHA-256 is unavailable", impossible);
        }
    }

    @NonNull
    private String apkSha256() {
        return installedApkSha256;
    }

    private void startApkDigest() {
        final Thread worker = new Thread(() -> {
            final String digest = computeInstalledApkSha256();
            if (!digest.isEmpty()) installedApkSha256 = digest;
        }, "birdbox-apk-digest");
        worker.setDaemon(true);
        worker.start();
    }

    @NonNull
    private String computeInstalledApkSha256() {
        try (FileInputStream input = new FileInputStream(activity.getApplicationInfo().sourceDir)) {
            final MessageDigest digest = MessageDigest.getInstance("SHA-256");
            final byte[] buffer = new byte[16 * 1024];
            int read;
            while ((read = input.read(buffer)) >= 0) {
                if (read > 0) digest.update(buffer, 0, read);
            }
            return toHex(digest.digest());
        } catch (IOException | NoSuchAlgorithmException ignored) {
            return "";
        }
    }

    @NonNull
    private static String toHex(@NonNull byte[] value) {
        final StringBuilder hex = new StringBuilder(value.length * 2);
        for (byte item : value) hex.append(String.format(Locale.ROOT, "%02x", item & 0xff));
        return hex.toString();
    }

    private void connect(MethodCall call, MethodChannel.Result result) {
        if (!requireBluetooth(result)) return;
        if (gatt != null) {
            result.error("invalid_state", "BirdBox GATT is already connected.", null);
            return;
        }
        final String traceId = call.argument("traceId");
        if (traceId != null && !traceId.isEmpty()) activeTraceId = traceId;
        connectedDeviceAddressHash = null;
        previousBondState = null;
        gattGeneration = 0;
        gattRebuilt = false;
        systemPairingInteraction = false;
        currentMtu = 23;
        emitDiagnostic("connect_requested", "connect", -1, null, null);
        if (!beginOperation("connect", result)) return;
        securityWriteStateMachine.reset();
        activeSecurityRequestId = null;
        activeSecurityCommandType = null;
        securityBondingObserved = false;
        final String deviceId = call.argument("deviceId");
        if (deviceId == null || deviceId.isEmpty()) {
            failPending("invalid_request", "A platform device handle is required.");
            return;
        }
        stopScan();
        try {
            disconnectRequested = false;
            linkReady = false;
            securityFailureObserved = false;
            connectedDevice = adapter.getRemoteDevice(deviceId);
            connectedDeviceAddressHash = saltedAddressHash(connectedDevice.getAddress(), activeTraceId);
            previousBondState = bondStateName(connectedDevice.getBondState());
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                gatt = connectedDevice.connectGatt(activity, false, gattCallback, BluetoothDevice.TRANSPORT_LE);
            } else {
                gatt = connectedDevice.connectGatt(activity, false, gattCallback);
            }
            if (gatt == null) {
                failPending("gatt_operation_failed", "GATT connection could not start.");
            } else {
                gattGeneration++;
            }
        } catch (SecurityException error) {
            failPending("bluetooth_permission_denied", "Bluetooth connect permission is missing.");
        } catch (IllegalArgumentException error) {
            failPending("invalid_request", "The platform device handle is invalid.");
        } catch (RuntimeException error) {
            failPending("gatt_operation_failed", "GATT connection could not start.");
        }
    }

    private void requestMtu(MethodCall call, MethodChannel.Result result) {
        final BluetoothGatt current = requireGatt(result);
        if (current == null || !beginOperation("requestMtu", result)) return;
        final Integer requested = call.argument("mtu");
        final int mtu = requested == null ? 517 : Math.max(23, Math.min(517, requested));
        try {
            if (!current.requestMtu(mtu)) failPending("gatt_operation_failed", "MTU request was rejected.");
        } catch (SecurityException error) {
            failPending("bluetooth_permission_denied", "Bluetooth connect permission is missing.");
        }
    }

    private void readCharacteristic(MethodCall call, MethodChannel.Result result) {
        final BluetoothGatt current = requireGatt(result);
        if (current == null || !beginOperation("read", result)) return;
        final BluetoothGattCharacteristic characteristic = characteristic(call.argument("characteristicUuid"));
        if (characteristic == null) {
            failPending("invalid_request", "Required GATT characteristic is unavailable.");
            return;
        }
        try {
            if (!current.readCharacteristic(characteristic)) failPending("gatt_operation_failed", "GATT read was rejected.");
        } catch (SecurityException error) {
            failPending("bluetooth_permission_denied", "Bluetooth connect permission is missing.");
        }
    }

    private void setNotify(MethodCall call, MethodChannel.Result result) {
        final BluetoothGatt current = requireGatt(result);
        if (current == null || !beginOperation("descriptor", result)) return;
        final BluetoothGattCharacteristic characteristic = characteristic(call.argument("characteristicUuid"));
        final Boolean enabledValue = call.argument("enabled");
        final boolean enabled = Boolean.TRUE.equals(enabledValue);
        pendingNotificationEnabled = enabled;
        if (characteristic == null) {
            failPending("invalid_request", "Required GATT characteristic is unavailable.");
            return;
        }
        final BluetoothGattDescriptor descriptor = characteristic.getDescriptor(CLIENT_CONFIGURATION_UUID);
        if (descriptor == null) {
            failPending("gatt_operation_failed", "Notification descriptor is unavailable.");
            return;
        }
        try {
            if (!current.setCharacteristicNotification(characteristic, enabled)) {
                failPending("gatt_operation_failed", "Notification registration was rejected.");
                return;
            }
            final byte[] value = enabled
                    ? ((characteristic.getProperties() & BluetoothGattCharacteristic.PROPERTY_INDICATE) != 0
                    ? BluetoothGattDescriptor.ENABLE_INDICATION_VALUE
                    : BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
                    : BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE;
            final boolean started;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                started = current.writeDescriptor(descriptor, value) == BluetoothGatt.GATT_SUCCESS;
            } else {
                descriptor.setValue(value);
                started = current.writeDescriptor(descriptor);
            }
            if (!started) failPending("gatt_operation_failed", "Notification descriptor write was rejected.");
        } catch (SecurityException error) {
            failPending("bluetooth_permission_denied", "Bluetooth connect permission is missing.");
        }
    }

    private void writeWithResponse(MethodCall call, MethodChannel.Result result) {
        final BluetoothGatt current = requireGatt(result);
        if (current == null || !beginOperation("write", result)) return;
        final BluetoothGattCharacteristic characteristic = characteristic(call.argument("characteristicUuid"));
        final byte[] value = call.argument("value");
        if (characteristic == null || value == null || value.length == 0) {
            failPending("invalid_request", "A writable characteristic and non-empty value are required.");
            return;
        }
        final boolean sensitiveWrite = WIFI_CONFIG_UUID.equals(characteristic.getUuid())
                || PROVISIONING_COMMAND_UUID.equals(characteristic.getUuid());
        if (sensitiveWrite && activeSecurityRequestId == null) {
            failPending(
                    "ble_gatt_not_ready",
                    "An encrypted BirdBox request must start a security-write session first.",
                    gattFailureDetails(-1, characteristic.getUuid())
            );
            return;
        }
        try {
            final boolean started;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                started = current.writeCharacteristic(characteristic, value, BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT) == BluetoothGatt.GATT_SUCCESS;
            } else {
                characteristic.setWriteType(BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT);
                characteristic.setValue(value);
                started = current.writeCharacteristic(characteristic);
            }
            if (!started) {
                if (sensitiveWrite
                        && securityWriteStateMachine.phase()
                        == BirdBoxSecurityWriteStateMachine.Phase.RETRYING_ENCRYPTED_WRITE) {
                    securityWriteStateMachine.onEncryptedRetryFailed();
                    failPending(
                            "ble_encrypted_retry_failed",
                            "The encrypted BirdBox request retry could not start.",
                            gattFailureDetails(-1, characteristic.getUuid())
                    );
                } else if (sensitiveWrite
                        && connectedDevice != null
                        && connectedDevice.getBondState() != BluetoothDevice.BOND_BONDED) {
                    securityWriteStateMachine.onSecurityRequired();
                    securityFailureObserved = true;
                    failPending(
                            "ble_link_not_encrypted",
                            "The encrypted write started BLE link security.",
                            gattFailureDetails(-1, characteristic.getUuid())
                    );
                } else {
                    failPending("gatt_operation_failed", "GATT write was rejected.");
                }
            }
        } catch (SecurityException error) {
            failPending("bluetooth_permission_denied", "Bluetooth connect permission is missing.");
        }
    }

    private void beginSecurityWrite(MethodCall call, MethodChannel.Result result) {
        if (!requireBluetooth(result)) return;
        final String requestId = call.argument("requestId");
        final String commandType = call.argument("commandType");
        if (requestId == null || requestId.isEmpty()
                || commandType == null || commandType.isEmpty()) {
            result.error("invalid_request", "A request_id and command type are required.", null);
            return;
        }
        if (gatt == null || connectedDevice == null || !linkReady) {
            result.error(
                    "ble_gatt_not_ready",
                    "BirdBox services and notifications must be ready before the security write.",
                    gattFailureDetails(-1, null)
            );
            return;
        }
        if (pendingOperationResult != null || securityWriteStateMachine.isActive()) {
            result.error("gatt_busy", "Another GATT or security-write operation is active.", null);
            return;
        }
        try {
            securityWriteStateMachine.markGattReady(gattGeneration);
            securityWriteStateMachine.beginSecurityWrite(requestId, gattGeneration);
            activeSecurityRequestId = requestId;
            activeSecurityCommandType = commandType;
            securityBondingObserved = false;
            securityFailureObserved = false;
            gattRebuilt = false;
            registerBondStateReceiver(connectedDevice);
            emitSecurityPhase("encrypted_characteristic_write");
            result.success(null);
        } catch (SecurityException error) {
            activeSecurityRequestId = null;
            activeSecurityCommandType = null;
            securityWriteStateMachine.reset();
            unregisterBondStateReceiver();
            result.error(
                    "bluetooth_permission_denied",
                    "Bluetooth connect permission is missing.",
                    gattFailureDetails(-1, null)
            );
        } catch (IllegalArgumentException | IllegalStateException error) {
            activeSecurityRequestId = null;
            activeSecurityCommandType = null;
            securityWriteStateMachine.reset();
            unregisterBondStateReceiver();
            result.error("ble_gatt_not_ready", error.getMessage(), gattFailureDetails(-1, null));
        } catch (RuntimeException error) {
            activeSecurityRequestId = null;
            activeSecurityCommandType = null;
            securityWriteStateMachine.reset();
            unregisterBondStateReceiver();
            result.error(
                    "ble_gatt_not_ready",
                    "Android could not register the BLE pairing listener.",
                    gattFailureDetails(-1, null)
            );
        }
    }

    private void awaitSecurityReady(MethodCall call, MethodChannel.Result result) {
        if (!requireSecurityRequest(call, result)) return;
        if (!beginOperation("securityRecovery", result)) return;
        emitSecurityPhase("await_bond_and_gatt");
        if (securityWriteStateMachine.phase() == BirdBoxSecurityWriteStateMachine.Phase.FAILED) {
            final boolean rejected = securityWriteStateMachine.failure()
                    == BirdBoxSecurityWriteStateMachine.Failure.PAIRING_REJECTED;
            failPending(
                    rejected ? "ble_pairing_rejected" : "ble_gatt_recovery_failed",
                    rejected
                            ? "BLE link pairing was rejected or cancelled."
                            : "Security recovery had already failed.",
                    gattFailureDetails(-1, null)
            );
            return;
        }
        final BluetoothDevice device = connectedDevice;
        if (device == null) {
            failSecurityRecovery("ble_gatt_recovery_failed", "BirdBox device is unavailable after security negotiation.");
            return;
        }
        try {
            if (device.getBondState() == BluetoothDevice.BOND_BONDED
                    && (securityWriteStateMachine.phase()
                    == BirdBoxSecurityWriteStateMachine.Phase.SECURITY_WRITE_STARTING
                    || securityWriteStateMachine.phase()
                    == BirdBoxSecurityWriteStateMachine.Phase.BONDING)) {
                securityWriteStateMachine.onBonded(gatt != null && linkReady);
            }
            continueSecurityRecovery();
        } catch (SecurityException error) {
            failPending(
                    "bluetooth_permission_denied",
                    "Bluetooth connect permission is missing.",
                    gattFailureDetails(-1, null)
            );
        } catch (IllegalStateException error) {
            failSecurityRecovery("ble_gatt_recovery_failed", error.getMessage());
        }
    }

    private void beginSecurityRetry(MethodCall call, MethodChannel.Result result) {
        if (!requireSecurityRequest(call, result)) return;
        if (gatt == null || !linkReady) {
            result.error("ble_gatt_recovery_failed", "Recovered GATT is not ready.", gattFailureDetails(-1, null));
            return;
        }
        try {
            securityWriteStateMachine.onNotificationsRestored();
            emitSecurityPhase("notifications_restored");
            result.success(null);
        } catch (IllegalStateException error) {
            result.error("ble_gatt_recovery_failed", error.getMessage(), gattFailureDetails(-1, null));
        }
    }

    private void markSecurityWriteSent(MethodCall call, MethodChannel.Result result) {
        if (!requireSecurityRequest(call, result)) return;
        try {
            securityWriteStateMachine.onWriteSucceeded();
            emitSecurityPhase("write_with_response_succeeded");
            result.success(null);
        } catch (IllegalStateException error) {
            result.error("ble_encrypted_retry_failed", error.getMessage(), gattFailureDetails(-1, null));
        }
    }

    private void completeSecurityWrite(MethodCall call, MethodChannel.Result result) {
        if (!requireSecurityRequest(call, result)) return;
        final String requestId = call.argument("requestId");
        try {
            if (!securityWriteStateMachine.onResponse(requestId)) {
                result.error("invalid_request", "The BirdBox response request_id did not match.", null);
                return;
            }
            emitDiagnostic(
                    "security_write_completed",
                    "write_command",
                    -1,
                    null,
                    (String) call.argument("responseType")
            );
            finishSecuritySession();
            result.success(null);
        } catch (IllegalStateException error) {
            result.error("invalid_state", error.getMessage(), null);
        }
    }

    private void failSecurityWrite(MethodCall call, MethodChannel.Result result) {
        if (!requireSecurityRequest(call, result)) return;
        final String errorCode = call.argument("errorCode");
        final BirdBoxSecurityWriteStateMachine.Phase phase = securityWriteStateMachine.phase();
        try {
            if (phase == BirdBoxSecurityWriteStateMachine.Phase.WAITING_RESPONSE
                    && "pairing_open_timeout".equals(errorCode)) {
                securityWriteStateMachine.onResponseTimeout();
            } else if (phase == BirdBoxSecurityWriteStateMachine.Phase.RETRYING_ENCRYPTED_WRITE) {
                securityWriteStateMachine.onEncryptedRetryFailed();
            } else if (phase == BirdBoxSecurityWriteStateMachine.Phase.BONDED_RECOVERING_GATT
                    || phase == BirdBoxSecurityWriteStateMachine.Phase.RESTORING_NOTIFICATIONS) {
                securityWriteStateMachine.onGattRecoveryFailed();
            } else if (phase == BirdBoxSecurityWriteStateMachine.Phase.SECURITY_WRITE_STARTING
                    || phase == BirdBoxSecurityWriteStateMachine.Phase.BONDING) {
                if ("ble_pairing_rejected".equals(errorCode)) {
                    securityWriteStateMachine.onPairingRejected();
                } else {
                    securityWriteStateMachine.onPairingNotStartedTimeout();
                }
            }
        } catch (IllegalStateException ignored) {
            // Cleanup is still required when Dart reports a terminal error after a racing callback.
        }
        emitSecurityPhase(errorCode == null ? "failed" : errorCode);
        finishSecuritySession();
        result.success(null);
    }

    private void registerBondStateReceiver(@NonNull BluetoothDevice expectedDevice) {
        unregisterBondStateReceiver();
        bondStateReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                if (!BluetoothDevice.ACTION_BOND_STATE_CHANGED.equals(intent.getAction())) return;
                final BluetoothDevice changed = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
                        ? intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice.class)
                        : intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE);
                if (changed == null || !expectedDevice.getAddress().equals(changed.getAddress())) return;
                final int state = intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, BluetoothDevice.ERROR);
                final int previous = intent.getIntExtra(BluetoothDevice.EXTRA_PREVIOUS_BOND_STATE, BluetoothDevice.ERROR);
                previousBondState = bondStateName(previous);
                if (state == BluetoothDevice.BOND_BONDING || state == BluetoothDevice.BOND_BONDED) {
                    systemPairingInteraction = true;
                }
                emitDiagnostic(
                        "bond_state_changed",
                        "security_write",
                        -1,
                        null,
                        bondStateName(previous) + "_to_" + bondStateName(state)
                );
                if (state == BluetoothDevice.BOND_BONDED) {
                    securityFailureObserved = false;
                    securityBondingObserved = true;
                    final BirdBoxSecurityWriteStateMachine.Phase previousPhase =
                            securityWriteStateMachine.phase();
                    try {
                        securityWriteStateMachine.onBonded(gatt != null && linkReady);
                        emitSecurityPhase("bonded");
                        if ("securityRecovery".equals(pendingOperation)
                                && (previousPhase
                                == BirdBoxSecurityWriteStateMachine.Phase.SECURITY_WRITE_STARTING
                                || previousPhase
                                == BirdBoxSecurityWriteStateMachine.Phase.BONDING)) {
                            continueSecurityRecovery();
                        }
                    } catch (IllegalStateException ignored) {
                        // A terminal request may receive a duplicate vendor Bond broadcast.
                    }
                } else if (state == BluetoothDevice.BOND_BONDING) {
                    securityBondingObserved = true;
                    try {
                        securityWriteStateMachine.onBonding();
                        emitSecurityPhase("bonding");
                    } catch (IllegalStateException ignored) {
                        // Ignore stale callbacks after the request has completed.
                    }
                } else if (state == BluetoothDevice.BOND_NONE
                        && previous == BluetoothDevice.BOND_BONDING) {
                    try {
                        securityWriteStateMachine.onPairingRejected();
                    } catch (IllegalStateException ignored) {
                        // failPending below still releases a waiting bridge call.
                    }
                    failPending(
                            "ble_pairing_rejected",
                            "BLE link pairing was rejected or cancelled.",
                            gattFailureDetails(-1, null)
                    );
                }
            }
        };
        final IntentFilter filter = new IntentFilter(BluetoothDevice.ACTION_BOND_STATE_CHANGED);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.registerReceiver(bondStateReceiver, filter, Context.RECEIVER_NOT_EXPORTED);
        } else {
            activity.registerReceiver(bondStateReceiver, filter);
        }
    }

    private void unregisterBondStateReceiver() {
        final BroadcastReceiver receiver = bondStateReceiver;
        bondStateReceiver = null;
        if (receiver == null) return;
        try {
            activity.unregisterReceiver(receiver);
        } catch (IllegalArgumentException ignored) {
            // Receiver may already have been removed during Activity teardown.
        }
    }

    private void continueSecurityRecovery() {
        final BirdBoxSecurityWriteStateMachine.Phase phase = securityWriteStateMachine.phase();
        if (phase == BirdBoxSecurityWriteStateMachine.Phase.SECURITY_WRITE_STARTING
                || phase == BirdBoxSecurityWriteStateMachine.Phase.BONDING) {
            return;
        }
        if (phase == BirdBoxSecurityWriteStateMachine.Phase.BONDED_RECOVERING_GATT) {
            reconnectGattAfterSecurity();
            return;
        }
        if (phase != BirdBoxSecurityWriteStateMachine.Phase.RESTORING_NOTIFICATIONS) {
            failSecurityRecovery("ble_gatt_recovery_failed", "Security recovery entered an invalid state.");
            return;
        }
        final BluetoothGatt current = gatt;
        if (current == null || !linkReady) {
            try {
                securityWriteStateMachine.onGattLostAfterBond();
                reconnectGattAfterSecurity();
            } catch (IllegalStateException error) {
                failSecurityRecovery("ble_gatt_recovery_failed", error.getMessage());
            }
            return;
        }
        try {
            linkReady = false;
            if (!current.discoverServices()) {
                failSecurityRecovery(
                        "ble_gatt_recovery_failed",
                        "GATT service confirmation after pairing could not start."
                );
            }
        } catch (SecurityException error) {
            failPending(
                    "bluetooth_permission_denied",
                    "Bluetooth connect permission is missing.",
                    gattFailureDetails(-1, null)
            );
        }
    }

    private void reconnectGattAfterSecurity() {
        final BluetoothDevice device = connectedDevice;
        if (device == null) {
            failSecurityRecovery("ble_gatt_recovery_failed", "BirdBox device is unavailable after pairing.");
            return;
        }
        emitSecurityPhase("gatt_reconnect_started");
        gattRebuilt = true;
        final BluetoothGatt previous = gatt;
        gatt = null;
        linkReady = false;
        if (previous != null) {
            try {
                previous.disconnect();
            } catch (SecurityException ignored) {
                // Reconnect still continues using the retained BluetoothDevice.
            }
            previous.close();
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                gatt = device.connectGatt(activity, false, gattCallback, BluetoothDevice.TRANSPORT_LE);
            } else {
                gatt = device.connectGatt(activity, false, gattCallback);
            }
            if (gatt == null) {
                failSecurityRecovery("ble_gatt_recovery_failed", "GATT reconnect after pairing could not start.");
            } else {
                gattGeneration++;
            }
        } catch (SecurityException error) {
            failPending("bluetooth_permission_denied", "Bluetooth connect permission is missing.");
        } catch (RuntimeException error) {
            failSecurityRecovery("ble_gatt_recovery_failed", "GATT reconnect after pairing could not start.");
        }
    }

    private boolean requireSecurityRequest(MethodCall call, MethodChannel.Result result) {
        final String requestId = call.argument("requestId");
        if (requestId == null || !requestId.equals(activeSecurityRequestId)) {
            result.error("invalid_request", "No matching security-write request is active.", null);
            return false;
        }
        return true;
    }

    private void failSecurityRecovery(@NonNull String code, @NonNull String message) {
        try {
            final BirdBoxSecurityWriteStateMachine.Phase phase = securityWriteStateMachine.phase();
            if (phase == BirdBoxSecurityWriteStateMachine.Phase.BONDED_RECOVERING_GATT
                    || phase == BirdBoxSecurityWriteStateMachine.Phase.RESTORING_NOTIFICATIONS) {
                securityWriteStateMachine.onGattRecoveryFailed();
            }
        } catch (IllegalStateException ignored) {
            // The platform error remains authoritative for the waiting Dart call.
        }
        failPending(code, message, gattFailureDetails(-1, null));
    }

    private void finishSecuritySession() {
        unregisterBondStateReceiver();
        activeSecurityRequestId = null;
        activeSecurityCommandType = null;
        securityBondingObserved = false;
        securityWriteStateMachine.reset();
    }

    @Nullable
    private BluetoothGatt requireGatt(MethodChannel.Result result) {
        if (!requireBluetooth(result)) return null;
        if (gatt == null) {
            result.error("invalid_state", "BirdBox GATT is not connected.", null);
            return null;
        }
        return gatt;
    }

    @Nullable
    private BluetoothGattCharacteristic characteristic(@Nullable String value) {
        if (value == null || gatt == null) return null;
        try {
            final BluetoothGattService service = gatt.getService(SERVICE_UUID);
            return service == null ? null : service.getCharacteristic(UUID.fromString(value.toLowerCase(Locale.ROOT)));
        } catch (IllegalArgumentException error) {
            return null;
        }
    }

    private synchronized boolean beginOperation(String operation, MethodChannel.Result result) {
        if (pendingOperationResult != null) {
            result.error("gatt_busy", "Another GATT operation is active.", null);
            return false;
        }
        pendingOperation = operation;
        pendingOperationResult = result;
        emitDiagnostic("operation_started", operation, -1, null, null);
        pendingOperationTimeout = () -> {
            final boolean connectionTimedOut = "connect".equals(pendingOperation);
            final boolean securityRecoveryTimedOut = "securityRecovery".equals(pendingOperation);
            if (securityRecoveryTimedOut) {
                final String code;
                final String message;
                try {
                    final BirdBoxSecurityWriteStateMachine.Phase phase = securityWriteStateMachine.phase();
                    if ((phase == BirdBoxSecurityWriteStateMachine.Phase.SECURITY_WRITE_STARTING
                            || phase == BirdBoxSecurityWriteStateMachine.Phase.BONDING)
                            && !securityBondingObserved) {
                        securityWriteStateMachine.onPairingNotStartedTimeout();
                        code = "ble_le_pairing_not_started";
                        message = "The encrypted write did not start Android LE pairing within 60 seconds.";
                    } else if (phase == BirdBoxSecurityWriteStateMachine.Phase.SECURITY_WRITE_STARTING
                            || phase == BirdBoxSecurityWriteStateMachine.Phase.BONDING) {
                        securityWriteStateMachine.onPairingRejected();
                        code = "ble_pairing_rejected";
                        message = "Android LE pairing did not complete within 60 seconds.";
                    } else {
                        securityWriteStateMachine.onGattRecoveryFailed();
                        code = "ble_gatt_recovery_failed";
                        message = "GATT recovery after pairing timed out.";
                    }
                } catch (IllegalStateException error) {
                    failPending(
                            "ble_gatt_recovery_failed",
                            "Security recovery timed out in an invalid state.",
                            gattFailureDetails(-1, null)
                    );
                    return;
                }
                failPending(code, message, gattFailureDetails(-1, null));
            } else {
                failPending(
                        "gatt_operation_failed",
                        "GATT operation timed out.",
                        gattFailureDetails(-1, null)
                );
            }
            if (connectionTimedOut) closeGatt(false, "timeout", BluetoothGatt.GATT_FAILURE);
        };
        final long timeoutMs = "securityRecovery".equals(operation)
                ? 60000L
                : "connect".equals(operation) ? 15000L : 10000L;
        mainHandler.postDelayed(pendingOperationTimeout, timeoutMs);
        return true;
    }

    private synchronized void succeedPending(@Nullable Object value) {
        final String completedOperation = pendingOperation;
        emitDiagnostic("operation_succeeded", completedOperation, -1, null, "success");
        cancelPendingOperationTimeout();
        final MethodChannel.Result result = pendingOperationResult;
        pendingOperationResult = null;
        pendingOperation = null;
        pendingNotificationEnabled = null;
        if (result != null) mainHandler.post(() -> result.success(value));
    }

    private synchronized void failPending(String code, String message) {
        failPending(code, message, null);
    }

    private synchronized void failPending(String code, String message, @Nullable Object details) {
        final String failedOperation = pendingOperation;
        int status = -1;
        UUID characteristicUuid = null;
        if (details instanceof Map) {
            final Object rawStatus = ((Map<?, ?>) details).get("gattStatus");
            if (rawStatus instanceof Integer) status = (Integer) rawStatus;
            final Object rawUuid = ((Map<?, ?>) details).get("characteristicUuid");
            if (rawUuid instanceof String && !"none".equals(rawUuid)) {
                try {
                    characteristicUuid = UUID.fromString((String) rawUuid);
                } catch (IllegalArgumentException ignored) {
                    // The diagnostic remains useful without an invalid UUID.
                }
            }
        }
        emitDiagnostic("operation_failed", failedOperation, status, characteristicUuid, code);
        cancelPendingOperationTimeout();
        final MethodChannel.Result result = pendingOperationResult;
        pendingOperationResult = null;
        pendingOperation = null;
        pendingNotificationEnabled = null;
        if (result != null) mainHandler.post(() -> result.error(code, message, details));
    }

    private synchronized void cancelPendingOperationTimeout() {
        if (pendingOperationTimeout != null) mainHandler.removeCallbacks(pendingOperationTimeout);
        pendingOperationTimeout = null;
    }

    private final BluetoothGattCallback gattCallback = new BluetoothGattCallback() {
        @Override
        public void onConnectionStateChange(@NonNull BluetoothGatt callbackGatt, int status, int newState) {
            if (callbackGatt != gatt) {
                callbackGatt.close();
                return;
            }
            emitDiagnostic(
                    "gatt_connection_state_changed",
                    pendingOperation,
                    status,
                    null,
                    connectionStateName(newState)
            );
            if (status == BluetoothGatt.GATT_SUCCESS && newState == BluetoothProfile.STATE_CONNECTED) {
                try {
                    callbackGatt.requestConnectionPriority(BluetoothGatt.CONNECTION_PRIORITY_HIGH);
                    if ("securityRecovery".equals(pendingOperation)) {
                        emitSecurityPhase("gatt_connected");
                    }
                    if (!callbackGatt.discoverServices()) {
                        if ("securityRecovery".equals(pendingOperation)) {
                            failSecurityRecovery(
                                    "ble_gatt_recovery_failed",
                                    "Service discovery after pairing could not start."
                            );
                        } else {
                            failPending("gatt_operation_failed", "Service discovery could not start.");
                        }
                    }
                } catch (SecurityException error) {
                    failPending("bluetooth_permission_denied", "Bluetooth connect permission is missing.");
                }
                return;
            }
            if (newState == BluetoothProfile.STATE_DISCONNECTED || status != BluetoothGatt.GATT_SUCCESS) {
                if (activeSecurityRequestId != null
                        && securityWriteStateMachine.isActive()
                        && securityWriteStateMachine.phase()
                        != BirdBoxSecurityWriteStateMachine.Phase.WAITING_RESPONSE) {
                    final BirdBoxSecurityWriteStateMachine.Phase phase =
                            securityWriteStateMachine.phase();
                    closeGattForSecurity(callbackGatt);
                    try {
                        if (phase == BirdBoxSecurityWriteStateMachine.Phase.RETRYING_ENCRYPTED_WRITE) {
                            securityWriteStateMachine.onEncryptedRetryFailed();
                        } else if (phase == BirdBoxSecurityWriteStateMachine.Phase.RESTORING_NOTIFICATIONS) {
                            securityWriteStateMachine.onGattLostAfterBond();
                        } else if (connectedDevice != null
                                && connectedDevice.getBondState() == BluetoothDevice.BOND_BONDED) {
                            securityWriteStateMachine.onBonded(false);
                        } else {
                            securityWriteStateMachine.onSecurityRequired();
                        }
                    } catch (IllegalStateException ignored) {
                        // The operation-specific failure below remains deterministic.
                    }
                    final String interruptedOperation = pendingOperation;
                    if ("write".equals(interruptedOperation)) {
                        final boolean retry = phase
                                == BirdBoxSecurityWriteStateMachine.Phase.RETRYING_ENCRYPTED_WRITE;
                        failPending(
                                retry ? "ble_encrypted_retry_failed" : "ble_link_not_encrypted",
                                retry
                                        ? "The encrypted request retry lost its GATT connection."
                                        : "The security-trigger write interrupted the GATT connection.",
                                gattFailureDetails(status, null)
                        );
                    } else if ("requestMtu".equals(interruptedOperation)
                            || "descriptor".equals(interruptedOperation)) {
                        failPending(
                                "ble_gatt_recovery_failed",
                                "GATT disconnected while restoring the secured connection.",
                                gattFailureDetails(status, null)
                        );
                    }
                    if ("securityRecovery".equals(interruptedOperation)
                            && connectedDevice != null
                            && connectedDevice.getBondState() == BluetoothDevice.BOND_BONDED) {
                        continueSecurityRecovery();
                    }
                    return;
                }
                final boolean connecting = "connect".equals(pendingOperation);
                final boolean wasReady = linkReady;
                final boolean expected = disconnectRequested;
                final Map<String, Object> details = gattFailureDetails(status, null);
                if (connecting) failPending(gattErrorCode(status), "BirdBox GATT connection failed.", details);
                else failPending(gattErrorCode(status), "BirdBox GATT disconnected during an operation.", details);
                closeGatt(false, expected ? "requested" : "link_lost", status);
                if (wasReady && !expected) emitDisconnect("link_lost", status, true);
            }
        }

        @Override
        public void onServicesDiscovered(@NonNull BluetoothGatt callbackGatt, int status) {
            if (callbackGatt != gatt
                    || !("connect".equals(pendingOperation)
                    || "securityRecovery".equals(pendingOperation))) return;
            emitDiagnostic(
                    "gatt_services_discovered",
                    pendingOperation,
                    status,
                    null,
                    status == BluetoothGatt.GATT_SUCCESS ? "success" : "failed"
            );
            if (status != BluetoothGatt.GATT_SUCCESS) {
                if ("securityRecovery".equals(pendingOperation)) {
                    failSecurityRecovery(
                            "ble_gatt_recovery_failed",
                            "GATT service discovery after pairing failed."
                    );
                    closeGattForSecurity(callbackGatt);
                } else {
                    failGattStatus(status, "GATT service discovery failed.");
                    closeGatt(false, "service_discovery_failed", status);
                }
                return;
            }
            final BluetoothGattService service = callbackGatt.getService(SERVICE_UUID);
            if (service == null) {
                if ("securityRecovery".equals(pendingOperation)) {
                    failSecurityRecovery("ble_gatt_recovery_failed", "BirdBox network service is unavailable after pairing.");
                    closeGattForSecurity(callbackGatt);
                } else {
                    failPending("invalid_request", "BirdBox network service is unavailable.");
                    closeGatt(false, "service_unavailable", status);
                }
                return;
            }
            for (UUID uuid : REQUIRED_CHARACTERISTICS) {
                if (service.getCharacteristic(uuid) == null) {
                    if ("securityRecovery".equals(pendingOperation)) {
                        failSecurityRecovery(
                                "ble_gatt_recovery_failed",
                                "A required BirdBox characteristic is unavailable after pairing."
                        );
                        closeGattForSecurity(callbackGatt);
                    } else {
                        failPending("invalid_request", "A required BirdBox characteristic is unavailable.");
                        closeGatt(false, "service_invalid", status);
                    }
                    return;
                }
            }
            linkReady = true;
            if ("securityRecovery".equals(pendingOperation)) {
                securityFailureObserved = false;
                if (securityWriteStateMachine.phase()
                        == BirdBoxSecurityWriteStateMachine.Phase.BONDED_RECOVERING_GATT) {
                    securityWriteStateMachine.onGattRecovered(gattGeneration);
                }
                emitSecurityPhase("services_ready");
                succeedPending(gattRebuilt);
            } else {
                securityWriteStateMachine.markGattReady(gattGeneration);
                succeedPending(null);
            }
        }

        @Override
        public void onMtuChanged(@NonNull BluetoothGatt callbackGatt, int mtu, int status) {
            if (callbackGatt != gatt || !"requestMtu".equals(pendingOperation)) return;
            emitDiagnostic(
                    "gatt_mtu_changed",
                    pendingOperation,
                    status,
                    null,
                    status == BluetoothGatt.GATT_SUCCESS ? "success" : "failed"
            );
            if (status == BluetoothGatt.GATT_SUCCESS) {
                currentMtu = mtu;
                succeedPending(mtu);
            }
            else failGattStatus(status, "MTU negotiation failed.");
        }

        @Override
        public void onCharacteristicRead(@NonNull BluetoothGatt callbackGatt, @NonNull BluetoothGattCharacteristic characteristic, int status) {
            if (callbackGatt != gatt || !"read".equals(pendingOperation)) return;
            completeRead(characteristic.getValue(), status);
        }

        @Override
        public void onCharacteristicRead(@NonNull BluetoothGatt callbackGatt, @NonNull BluetoothGattCharacteristic characteristic, @NonNull byte[] value, int status) {
            if (callbackGatt != gatt || !"read".equals(pendingOperation)) return;
            completeRead(value, status);
        }

        @Override
        public void onCharacteristicWrite(@NonNull BluetoothGatt callbackGatt, @NonNull BluetoothGattCharacteristic characteristic, int status) {
            if (callbackGatt != gatt || !"write".equals(pendingOperation)) return;
            emitDiagnostic(
                    "gatt_characteristic_write",
                    pendingOperation,
                    status,
                    characteristic.getUuid(),
                    status == BluetoothGatt.GATT_SUCCESS ? "success" : gattErrorCode(status)
            );
            if (status == BluetoothGatt.GATT_SUCCESS) {
                succeedPending(null);
            } else if (activeSecurityRequestId != null
                    && (WIFI_CONFIG_UUID.equals(characteristic.getUuid())
                    || PROVISIONING_COMMAND_UUID.equals(characteristic.getUuid()))) {
                securityFailureObserved |= isGattSecurityFailure(status);
                if (securityWriteStateMachine.phase()
                        == BirdBoxSecurityWriteStateMachine.Phase.RETRYING_ENCRYPTED_WRITE) {
                    securityWriteStateMachine.onEncryptedRetryFailed();
                    failPending(
                            "ble_encrypted_retry_failed",
                            "The encrypted BirdBox request retry failed.",
                            gattFailureDetails(status, characteristic.getUuid())
                    );
                } else if (isGattSecurityFailure(status)) {
                    securityWriteStateMachine.onSecurityRequired();
                    failPending(
                            "ble_link_not_encrypted",
                            "The encrypted write requires BLE link security.",
                            gattFailureDetails(status, characteristic.getUuid())
                    );
                } else {
                    failGattStatus(status, "GATT write failed.", characteristic.getUuid());
                }
            } else {
                failGattStatus(status, "GATT write failed.", characteristic.getUuid());
            }
        }

        @Override
        public void onDescriptorWrite(@NonNull BluetoothGatt callbackGatt, @NonNull BluetoothGattDescriptor descriptor, int status) {
            if (callbackGatt != gatt || !"descriptor".equals(pendingOperation)) return;
            emitDiagnostic(
                    "gatt_notification_descriptor_write",
                    pendingOperation,
                    status,
                    descriptor.getCharacteristic().getUuid(),
                    status == BluetoothGatt.GATT_SUCCESS ? "success" : gattErrorCode(status)
            );
            if (status == BluetoothGatt.GATT_SUCCESS) succeedPending(null);
            else failGattStatus(status, "Notification descriptor write failed.", descriptor.getCharacteristic().getUuid());
        }

        @Override
        public void onCharacteristicChanged(@NonNull BluetoothGatt callbackGatt, @NonNull BluetoothGattCharacteristic characteristic) {
            if (callbackGatt != gatt || !linkReady) return;
            emitNotification(characteristic.getUuid(), characteristic.getValue());
        }

        @Override
        public void onCharacteristicChanged(@NonNull BluetoothGatt callbackGatt, @NonNull BluetoothGattCharacteristic characteristic, @NonNull byte[] value) {
            if (callbackGatt != gatt || !linkReady) return;
            emitNotification(characteristic.getUuid(), value);
        }
    };

    private void completeRead(@Nullable byte[] value, int status) {
        if (status == BluetoothGatt.GATT_SUCCESS && value != null) succeedPending(value);
        else failGattStatus(status, "GATT read failed.", null);
    }

    private void failGattStatus(int status, @NonNull String message) {
        failGattStatus(status, message, null);
    }

    private void failGattStatus(int status, @NonNull String message, @Nullable UUID characteristicUuid) {
        if (isGattSecurityFailure(status)) securityFailureObserved = true;
        failPending(gattErrorCode(status), message, gattFailureDetails(status, characteristicUuid));
    }

    @NonNull
    private Map<String, Object> gattFailureDetails(int status, @Nullable UUID characteristicUuid) {
        final Map<String, Object> details = new LinkedHashMap<>();
        details.put("gattStatus", status);
        details.put("platformExceptionCode", gattErrorCode(status));
        details.put("bondState", bondStateName());
        details.put("characteristicUuid", characteristicUuid == null ? "none" : characteristicUuid.toString().toLowerCase(Locale.ROOT));
        details.put("operationName", diagnosticOperationName(pendingOperation));
        return details;
    }

    @NonNull
    private String bondStateName() {
        final BluetoothDevice device = connectedDevice;
        if (device == null) return "none";
        try {
            return switch (device.getBondState()) {
                case BluetoothDevice.BOND_BONDED -> "bonded";
                case BluetoothDevice.BOND_BONDING -> "bonding";
                default -> "not_bonded";
            };
        } catch (SecurityException ignored) {
            return "permission_denied";
        }
    }

    @NonNull
    private static String bondStateName(int state) {
        return switch (state) {
            case BluetoothDevice.BOND_BONDED -> "bonded";
            case BluetoothDevice.BOND_BONDING -> "bonding";
            case BluetoothDevice.BOND_NONE -> "not_bonded";
            default -> "unknown";
        };
    }

    @NonNull
    private static String connectionStateName(int state) {
        return switch (state) {
            case BluetoothProfile.STATE_CONNECTED -> "connected";
            case BluetoothProfile.STATE_CONNECTING -> "connecting";
            case BluetoothProfile.STATE_DISCONNECTING -> "disconnecting";
            case BluetoothProfile.STATE_DISCONNECTED -> "disconnected";
            default -> "unknown";
        };
    }

    private void closeGattForSecurity(@NonNull BluetoothGatt callbackGatt) {
        if (callbackGatt != gatt) return;
        gatt = null;
        linkReady = false;
        try {
            callbackGatt.close();
        } catch (RuntimeException ignored) {
            // Vendor stack may already have closed the client.
        }
    }

    static boolean isGattSecurityFailure(int status) {
        return status == BluetoothGatt.GATT_INSUFFICIENT_AUTHENTICATION
                || status == GATT_INSUFFICIENT_AUTHORIZATION
                || status == BluetoothGatt.GATT_INSUFFICIENT_ENCRYPTION
                || status == GATT_INSUFFICIENT_ENCRYPTION_KEY_SIZE;
    }

    @NonNull
    static String gattErrorCode(int status) {
        return isGattSecurityFailure(status) ? "ble_link_not_encrypted" : "gatt_operation_failed";
    }

    private void emitNotification(UUID characteristicUuid, @Nullable byte[] value) {
        if (value == null) return;
        final Map<String, Object> event = new LinkedHashMap<>();
        event.put("characteristicUuid", characteristicUuid.toString().toLowerCase(Locale.ROOT));
        event.put("value", Arrays.copyOf(value, value.length));
        emitSuccess(notificationSink, event);
    }

    private synchronized void closeGatt(boolean emitDisconnect, @NonNull String reason, int status) {
        stopScan();
        final BluetoothGatt current = gatt;
        gatt = null;
        connectedDevice = null;
        linkReady = false;
        if (current != null) {
            try {
                current.disconnect();
            } catch (SecurityException ignored) {
                // Closing must still continue after permission revocation.
            }
            try {
                current.close();
            } catch (RuntimeException ignored) {
                // Vendor stacks may already have torn down the client.
            }
            if (emitDisconnect) emitDisconnect(reason, status, !disconnectRequested);
        }
        disconnectRequested = false;
    }

    private void emitDisconnect(@NonNull String reason, int status, boolean unexpected) {
        final Map<String, Object> event = new LinkedHashMap<>();
        event.put("reason", reason);
        event.put("gattStatus", status);
        event.put("unexpected", unexpected);
        emitSuccess(disconnectSink, event);
        emitDiagnostic("disconnected", "disconnect", status, null, reason);
    }

    private void emitDiagnostic(
            @NonNull String eventType,
            @Nullable String operationName,
            int gattStatus,
            @Nullable UUID characteristicUuid,
            @Nullable String resultCode) {
        final String traceId = activeTraceId;
        if (traceId == null || traceId.isEmpty()) return;
        final Map<String, Object> event = new LinkedHashMap<>();
        event.put("traceId", traceId);
        event.put("occurredAtMs", System.currentTimeMillis());
        event.put("eventType", eventType);
        event.put("manufacturer", Build.MANUFACTURER);
        event.put("model", Build.MODEL);
        event.put("androidRelease", Build.VERSION.RELEASE);
        event.put("sdkInt", Build.VERSION.SDK_INT);
        event.put("gitCommit", BuildConfig.GIT_SHA);
        event.put("apkSha256", apkSha256());
        if (connectedDeviceAddressHash != null) {
            event.put("deviceAddressHash", connectedDeviceAddressHash);
        }
        if (gattGeneration > 0) event.put("gattInstanceId", gattGeneration);
        if (operationName != null) event.put("operationName", diagnosticOperationName(operationName));
        if (gattStatus >= 0) event.put("gattStatus", gattStatus);
        event.put("bondState", bondStateName());
        if (previousBondState != null) event.put("previousBondState", previousBondState);
        event.put("systemPairingInteraction", systemPairingInteraction);
        event.put("gattRebuilt", gattRebuilt);
        event.put("retryCount", securityWriteStateMachine.encryptedRetryCount());
        if (activeSecurityRequestId != null) {
            event.put("requestId", activeSecurityRequestId);
        }
        if (activeSecurityCommandType != null) {
            event.put("commandType", activeSecurityCommandType);
        }
        event.put("mtu", currentMtu);
        if ("gatt_connection_state_changed".equals(eventType) && resultCode != null) {
            event.put("connectionState", resultCode);
        }
        if ("gatt_services_discovered".equals(eventType) && resultCode != null) {
            event.put("serviceDiscoveryResult", resultCode);
        }
        if ("descriptor".equals(operationName) && pendingNotificationEnabled != null) {
            event.put("notificationState", pendingNotificationEnabled ? "enabled" : "disabled");
        }
        if ("write".equals(operationName)) event.put("writeType", "with_response");
        if ("gatt_characteristic_write".equals(eventType) && gattStatus >= 0) {
            event.put("writeCallbackStatus", gattStatus);
        }
        if ("write".equals(operationName)
                && activeSecurityRequestId != null
                && (isGattSecurityFailure(gattStatus) || securityFailureObserved)) {
            event.put("securityTrigger", "encrypted_characteristic_write");
        }
        if (characteristicUuid != null) {
            event.put("characteristicUuid", characteristicUuid.toString().toLowerCase(Locale.ROOT));
        }
        if ("security_write_completed".equals(eventType) && resultCode != null) {
            event.put("responseType", resultCode);
        }
        if (resultCode != null) event.put("resultCode", resultCode);
        addPackageMetadata(event);
        emitSuccess(diagnosticSink, event);
    }

    private void addPackageMetadata(@NonNull Map<String, Object> event) {
        try {
            final PackageInfo packageInfo = activity.getPackageManager().getPackageInfo(activity.getPackageName(), 0);
            if (packageInfo.versionName != null) event.put("appVersionName", packageInfo.versionName);
            final long versionCode = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P
                    ? packageInfo.getLongVersionCode()
                    : packageInfo.versionCode;
            event.put("appVersionCode", Long.toString(versionCode));
        } catch (PackageManager.NameNotFoundException ignored) {
            // Package metadata is optional; the event remains attributable.
        }
    }

    @NonNull
    private String diagnosticOperationName(@Nullable String operationName) {
        if ("write".equals(operationName) && activeSecurityCommandType != null) {
            return "write_" + activeSecurityCommandType;
        }
        return operationName == null ? "none" : operationName;
    }

    private void emitSecurityPhase(@Nullable String reason) {
        emitDiagnostic(
                "security_phase_changed",
                "security_write",
                -1,
                null,
                securityWriteStateMachine.phase().name().toLowerCase(Locale.ROOT)
                        + (reason == null ? "" : ":" + reason)
        );
    }

    public void dispose() {
        if (disposed) return;
        disposed = true;
        finishSecuritySession();
        closeGatt(false, "disposed", BluetoothGatt.GATT_SUCCESS);
        if (pendingPermissionResult != null) {
            pendingPermissionResult.error("invalid_state", "BLE bridge was disposed.", null);
            pendingPermissionResult = null;
        }
        failPending("invalid_state", "BLE bridge was disposed.");
        methodChannel.setMethodCallHandler(null);
        scanEventChannel.setStreamHandler(null);
        notificationEventChannel.setStreamHandler(null);
        disconnectEventChannel.setStreamHandler(null);
        diagnosticEventChannel.setStreamHandler(null);
        scanSink = null;
        notificationSink = null;
        disconnectSink = null;
        diagnosticSink = null;
        activeTraceId = null;
    }

    private static void emitSuccess(@Nullable EventChannel.EventSink sink, Object event) {
        if (sink == null) return;
        new Handler(Looper.getMainLooper()).post(() -> sink.success(event));
    }

    private static void emitError(@Nullable EventChannel.EventSink sink, String code, String message) {
        emitError(sink, code, message, null);
    }

    private static void emitError(
            @Nullable EventChannel.EventSink sink,
            String code,
            String message,
            @Nullable Object details) {
        if (sink == null) return;
        new Handler(Looper.getMainLooper()).post(() -> sink.error(code, message, details));
    }

    private interface SinkConsumer {
        void accept(EventChannel.EventSink sink);
    }

    private static EventChannel.StreamHandler streamHandler(SinkConsumer onListen, Runnable onCancel) {
        return new EventChannel.StreamHandler() {
            @Override
            public void onListen(Object arguments, EventChannel.EventSink events) {
                onListen.accept(events);
            }

            @Override
            public void onCancel(Object arguments) {
                onCancel.run();
            }
        };
    }
}
