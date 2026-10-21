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
import android.bluetooth.le.ScanFilter;
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
import android.os.SystemClock;
import android.provider.Settings;
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
    private static final long CONDITIONAL_BOND_FALLBACK_DELAY_MS =
            BirdBoxConditionalBondFallbackPolicy.GRACE_PERIOD_MS;
    private static final long SECURITY_WRITE_CALLBACK_GUARD_MS = 2000L;
    private static final long SECURITY_DISCONNECT_GUARD_MS = 3000L;
    private static final long SECURITY_DISCONNECT_SETTLE_MS = 1000L;
    private static final int MAX_HELD_LEGACY_REGISTRATIONS = 8;
    // Retire barrier (BLE1019 R1): shared 3 s bound for every parked retire reason.
    private static final long PARKED_RETIRE_DISCONNECT_GUARD_MS = 3000L;
    private static final String FULL_SCAN_PERMISSION_POLICY = "full_scan";

    private static final UUID SERVICE_UUID = UUID.fromString("6f7d0001-7a66-4c45-a1b9-5f4d2e3c1000");
    private static final UUID DEVICE_INFO_UUID = UUID.fromString("6f7d0002-7a66-4c45-a1b9-5f4d2e3c1000");
    private static final UUID NETWORK_STATUS_UUID = UUID.fromString("6f7d0003-7a66-4c45-a1b9-5f4d2e3c1000");
    private static final UUID WIFI_CONFIG_UUID = UUID.fromString("6f7d0004-7a66-4c45-a1b9-5f4d2e3c1000");
    private static final UUID PROVISIONING_COMMAND_UUID = UUID.fromString("6f7d0005-7a66-4c45-a1b9-5f4d2e3c1000");
    private static final UUID SCAN_RESULTS_UUID = UUID.fromString("6f7d0006-7a66-4c45-a1b9-5f4d2e3c1000");
    // Board-deployed pairing preflight (increment 2026-10-19 §3.2): public, writable before
    // the system bond. Old boards never expose it, so it must stay out of REQUIRED_CHARACTERISTICS.
    private static final UUID PAIRING_PREFLIGHT_UUID = UUID.fromString("6f7d0007-7a66-4c45-a1b9-5f4d2e3c1000");
    private static final UUID CLIENT_CONFIGURATION_UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb");
    private static final List<UUID> REQUIRED_CHARACTERISTICS = Arrays.asList(
            DEVICE_INFO_UUID,
            NETWORK_STATUS_UUID,
            WIFI_CONFIG_UUID,
            PROVISIONING_COMMAND_UUID,
            SCAN_RESULTS_UUID
    );

    private final Context applicationContext;
    @Nullable private Activity activity;
    private final Handler mainHandler;
    private final BirdBoxBlePlatform platform;
    private final BirdBoxSecurityWriteStateMachine securityWriteStateMachine =
            new BirdBoxSecurityWriteStateMachine();
    private final BirdBoxConditionalBondFallbackPolicy conditionalBondFallbackPolicy =
            new BirdBoxConditionalBondFallbackPolicy();
    private final BirdBoxSecurityWriteAttemptContext securityWriteAttemptContext =
            new BirdBoxSecurityWriteAttemptContext();
    private final BirdBoxScanStrategyController scanStrategyController =
            new BirdBoxScanStrategyController();
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
    @Nullable private BluetoothGatt retiringGatt;
    private boolean retiringGattDisconnected;
    // Pre-connect reset (155233): a parked old client must observe a real disconnect
    // callback before a new dial; the guard bounds the wait when the stack stays silent.
    @Nullable private BluetoothGatt parkedResetGatt;
    private boolean parkedResetDisconnected;
    @Nullable private Runnable parkedResetGuard;
    // Retire barrier (BLE1019 R1): which teardown parked the old client, and the
    // generation facts captured at park time so late diagnostics can name the retiree.
    @Nullable private String parkedRetireReason;
    private int parkedRetireConnectionGeneration;
    private int parkedRetireGattGeneration;
    // The prepareControlledReconnect caller held until the parked client's real
    // STATE_DISCONNECTED arrives and close() has run; completed exactly once.
    @Nullable private MethodChannel.Result pendingControlledReleaseResult;
    // Idempotency anchor for prepareControlledReconnect after board-side reset.
    private int lastReleasedConnectionGeneration;
    private int lastReleasedGattInstanceId;
    // Fast path: when the link is already known gone, retire barriers close immediately.
    private int lastKnownConnectionState = BluetoothProfile.STATE_DISCONNECTED;
    // The connect call waiting on the parked stale client; it must be completed exactly
    // once — by the dial, by the guard, or by a teardown that supersedes the reset.
    @Nullable private MethodCall pendingPreConnectCall;
    @Nullable private MethodChannel.Result pendingPreConnectResult;
    private final List<BluetoothGatt> heldLegacyRegistrations = new ArrayList<>();
    @Nullable private Runnable retiringGattGuard;
    @Nullable private Runnable securityReconnectGuard;
    private boolean securityMtuResolvedBeforeDiscovery;
    private long securityReconnectNotBefore;
    // 首绑后 1 秒内的首次 rebuild 可能撞上栈收尾 SMP 的瞬态：vivo X20 实测过
    // status 133（20261012-213905-P2-bond_first-3）与连接回调缺失
    // （20261013-140734-P2-bond_first-1）。同一路径在已绑定矩阵 7 场全过，
    // 说明重建机制可靠，窗口只在全新绑定后。对 gatt_connect 阶段的这两类
    // 失败给一次有界重试；第二次仍失败按原样有界终止，两次状态都留证。
    private int securityConnectRetryCount;
    private static final int SECURITY_CONNECT_RETRY_MAX = 1;
    @Nullable private volatile BluetoothDevice connectedDevice;
    @Nullable private MethodChannel.Result pendingPermissionResult;
    @Nullable private MethodChannel.Result pendingOperationResult;
    @Nullable private volatile String pendingOperation;
    @Nullable private Runnable pendingOperationTimeout;
    @Nullable private Runnable scanTimeout;
    @Nullable private Runnable scanStrategyTimeout;
    @Nullable private ScanCallback activeScanCallback;
    @Nullable private Runnable conditionalBondFallback;
    @Nullable private Runnable securityWriteCallbackGuard;
    @Nullable private String activeScanSessionId;
    @Nullable private volatile String activeTraceId;
    @Nullable private BroadcastReceiver bondStateReceiver;
    @Nullable private String activeSecurityRequestId;
    @Nullable private String activeSecurityCommandType;
    @Nullable private String connectedDeviceAddressHash;
    @Nullable private String previousBondState;
    @Nullable private Boolean pendingNotificationEnabled;
    @NonNull private volatile String installedApkSha256 = BuildConfig.APK_SHA256;
    @NonNull private String bondInitiationSource = "none";
    private boolean securityBondingObserved;
    private boolean systemPairingInteraction;
    private boolean gattRebuilt;
    private boolean pairingMetadataResult;
    private boolean systemBondAttempted;
    private volatile long operationToken;
    private int securedGattGeneration = -1;
    private int notificationIndex;
    private String preparationStep;
    private String preparationFailurePhase;
    private long preparationStepStartedAt;
    @Nullable private BluetoothGatt discoveryGatt;
    @Nullable private Boolean discoveryApiAccepted;
    private boolean gattServicesDiscovered;
    private long discoveryStartedAt;
    private int ignoredDiscoveryCallbacks;
    private UUID pendingCharacteristicUuid;
    private Runnable bondTimeout;
    private Runnable preparationTimeout;
    private int scanRawResultCount;
    private boolean locationCompatibilityObserved;
    private final List<UUID> enabledNotifications = new ArrayList<>();
    private final BirdBoxPairingCoordinator pairingCoordinator = new BirdBoxPairingCoordinator(
            securityWriteStateMachine, new BirdBoxPairingCoordinator.Platform() {
        public int bondState() { return connectedDevice == null ? BluetoothDevice.ERROR : platform.bondState(connectedDevice); }
        public boolean gattUsable() {
            return gatt != null && linkReady
                    && enabledNotifications.containsAll(Arrays.asList(NETWORK_STATUS_UUID, SCAN_RESULTS_UUID));
        }
        public void restoreNotificationsAfterBond() {
            // The bonded GATT is alive; refresh notifications so the encrypted gate sees
            // subscriptions tied to the surviving client, then complete the preparation.
            notificationIndex = 0;
            subscribePreparedNotifications();
        }
        public void cancelOldWaits() {
            cancelSecurityWriteCallbackGuard();
            cancelConditionalBondFallback();
            cancelPendingOperationTimeout();
            cancelPreparationTimeout();
            emitDiagnostic("security_old_timers_cancelled", "preparePairing", -1, null, "complete");
        }
        public void registerReceiver(long owner) { registerBondStateReceiver(connectedDevice); }
        public boolean createBond() {
            securityWriteAttemptContext.recordCreateBondInvoked(bondStateName());
            systemBondAttempted = true;
            bondInitiationSource = "user_start_pairing";
            emitDiagnostic("create_bond_invoked", "preparePairing", -1, null, "invoked");
            try {
                boolean value = platform.createBond(connectedDevice);
                securityWriteAttemptContext.recordCreateBondResult(value, bondStateName());
                return value;
            } catch (RuntimeException error) {
                securityWriteAttemptContext.recordCreateBondException(error.getClass().getSimpleName(), bondStateName());
                throw error;
            }
        }
        public void startBondTimeout(long owner, long milliseconds) {
            cancelBondTimeout();
            bondTimeout = () -> pairingCoordinator.timeout(owner);
            mainHandler.postDelayed(bondTimeout, milliseconds);
        }
        public void cancelBondTimeout() { BirdBoxBleChannel.this.cancelBondTimeout(); }
        public void rebuildGatt() { reconnectGattAfterSecurity(); }
        public void event(String name, String result) {
            if ("create_bond_invoked".equals(name)) {
                // The actual Android side-effect boundary records and emits the invocation.
                return;
            }
            if ("system_bond_result".equals(name))
                securityWriteAttemptContext.finishBond(SystemClock.uptimeMillis());
            emitDiagnostic(name, "preparePairing", -1, null, result);
            emitSecurityPhase(result);
        }
        public void fail(String code) { failNativePreparation(code); }
    });
    private boolean scanning;
    private boolean firstScanCallbackEmitted;
    private int currentMtu = 23;
    private int gattGeneration;
    private int connectionGeneration;
    private volatile boolean linkReady;
    private volatile boolean disconnectRequested;
    private volatile boolean securityFailureObserved;
    private volatile boolean securityGattStatusObserved;
    private volatile boolean disposed;

    public BirdBoxBleChannel(@NonNull Context context, @NonNull BinaryMessenger messenger) {
        this(context, messenger, new BirdBoxBlePlatform(), new Handler(Looper.getMainLooper()),
                bluetoothAdapter(context));
    }

    private static BluetoothAdapter bluetoothAdapter(Context context) {
        final BluetoothManager manager = (BluetoothManager) context.getSystemService(Context.BLUETOOTH_SERVICE);
        return manager == null ? null : manager.getAdapter();
    }

    BirdBoxBleChannel(Context context, BinaryMessenger messenger, BirdBoxBlePlatform platform,
                      Handler handler, BluetoothAdapter adapter) {
        this.applicationContext = context.getApplicationContext();
        this.platform = platform;
        this.mainHandler = handler;
        this.adapter = adapter;
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

    void attachActivity(Activity host) {
        activity = host;
        emitDiagnostic("ble_host_attached", pendingOperation, -1, null, "engine_session_preserved");
    }

    void detachActivity(String reason) {
        activity = null;
        emitDiagnostic("ble_host_detached", pendingOperation, -1, null, reason);
        // A permission dialog belongs to its Activity. GATT/bond and their deadlines belong
        // to the Engine, and continue while the UI reattaches or a pairing popup is visible.
        if (pendingPermissionResult != null && !"engine_destroyed".equals(reason)) {
            final MethodChannel.Result result = pendingPermissionResult;
            pendingPermissionResult = null;
            returnError(result, "ensurePermissions", "ble_host_unavailable", "Bluetooth host detached: " + reason);
        }
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            mainHandler.post(() -> onMethodCall(call, result));
            return;
        }
        if (disposed && !"dispose".equals(call.method)) {
            returnError(result, call.method, "invalid_state", "BLE bridge is disposed.");
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
                if (activeSecurityRequestId != null) {
                    returnError(result, call.method, "gatt_busy", "Cancel the owned pairing before replacing its connection.");
                    break;
                }
                connect(call, result);
                break;
            case "disconnect":
                final Number requestedGeneration = call.argument("connectionGeneration");
                if (requestedGeneration != null && requestedGeneration.intValue() != connectionGeneration) {
                    returnError(result, call.method, "invalid_request", "Disconnect belongs to an older connection.");
                    break;
                }
                if (activeSecurityRequestId != null && call.argument("requestId") == null) {
                    returnError(result, call.method, "invalid_request", "Disconnect must name the active pairing owner.");
                    break;
                }
                if (call.argument("requestId") != null && !requireSecurityRequest(call, result)) break;
                disconnectRequested = true;
                failPendingIfActive(
                        "gatt_operation_failed",
                        "GATT operation was interrupted by disconnect."
                );
                // The retire barrier parks the client until its real disconnect callback;
                // the connect gate rejects dials until then. The page Future stays
                // synchronous and the stream event fires at barrier start.
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
            case "openLocationSettings":
                if (activity == null) {
                    returnError(result, call.method, "ble_host_unavailable", "Bluetooth host is unavailable.");
                    break;
                }
                try {
                    activity.startActivity(new Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS));
                    emitDiagnostic("location_settings_opened", "scan", -1, null, "success");
                    result.success(null);
                } catch (RuntimeException error) {
                    returnError(result, call.method, "location_settings_unavailable", "Location settings are unavailable.");
                }
                break;
            case "preparePairing":
                beginSecurityWrite(call, result);
                break;
            case "writePairingPreflight":
                writePairingPreflight(call, result);
                break;
            case "getNativeBondState":
                getNativeBondState(call, result);
                break;
            case "getGattOwnershipState":
                getGattOwnershipState(result);
                break;
            case "prepareControlledReconnect":
                prepareControlledReconnect(call, result);
                break;
            case "cancelPairing":
                if (!requireSecurityRequest(call, result)) break;
                closeGatt(true, "user_cancelled", BluetoothGatt.GATT_SUCCESS);
                result.success(null);
                break;
            case "beginSecurityWrite":
                beginSecurityWrite(call, result);
                break;
            case "recoverPairing":
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
                if (activeSecurityRequestId != null && !requireSecurityRequest(call, result)) break;
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
            returnError(
                    result,
                    "ensurePermissions",
                    "gatt_busy",
                    "A Bluetooth permission request is already active."
            );
            return;
        }
        if (activity == null) {
            returnError(result, "ensurePermissions", "ble_host_unavailable", "Bluetooth host is unavailable.");
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
            if (requiresLocationPermission()) {
                addIfMissing(permissions, Manifest.permission.ACCESS_FINE_LOCATION);
            }
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            addIfMissing(permissions, Manifest.permission.ACCESS_FINE_LOCATION);
        }
        return permissions;
    }

    private void addIfMissing(List<String> permissions, String permission) {
        if (applicationContext.checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED) permissions.add(permission);
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
                requiresLocationPermission(),
                Manifest.permission.ACCESS_FINE_LOCATION
        ));
        addLocationFacts(environment);
        environment.put("locationService", locationServiceState());
        environment.put("manufacturer", Build.MANUFACTURER);
        environment.put("model", Build.MODEL);
        environment.put("androidRelease", Build.VERSION.RELEASE);
        environment.put("sdkInt", Build.VERSION.SDK_INT);
        environment.put("gitCommit", BuildConfig.GIT_SHA);
        environment.put("buildDirty", BuildConfig.BUILD_DIRTY);
        environment.put("buildId", BuildConfig.BUILD_ID);
        environment.put("sourceFingerprint", BuildConfig.SOURCE_FINGERPRINT);
        environment.put("apkSha256", apkSha256());
        environment.put("scanPermissionPolicy", BuildConfig.BLE_SCAN_PERMISSION_POLICY);
        environment.put("scanFlavor", BuildConfig.FLAVOR);
        environment.put(
                "scanStrategyFallbackEnabled",
                BuildConfig.BLE_SCAN_STRATEGY_FALLBACK_ENABLED
        );
        environment.put("scanMode", "low_latency");
        addPackageMetadata(environment);
        return environment;
    }

    @NonNull
    private String permissionState(boolean required, @NonNull String permission) {
        if (!required) return "not_required";
        return applicationContext.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
                ? "granted"
                : "denied";
    }

    @NonNull
    private String locationServiceState() {
        final LocationManager manager = (LocationManager) applicationContext.getSystemService(Context.LOCATION_SERVICE);
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

    private boolean knownLocationCompatibility() {
        return BirdBoxScanCompatibility.knownAffected(Build.MANUFACTURER, Build.MODEL, Build.VERSION.SDK_INT);
    }

    private void addLocationFacts(Map<String, Object> value) {
        value.put("locationService", locationServiceState());
        boolean granted = Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
                && applicationContext.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED;
        value.put("locationPermission", granted ? "granted" : requiresLocationPermission() ? "denied" : "not_requested");
        value.put("locationRequiredByApp", false);
        value.put("locationPermissionRequiredByPlatform", requiresLocationPermission());
        value.put("locationRequiredForDeviceCompatibility", knownLocationCompatibility() || locationCompatibilityObserved);
        value.put("locationCompatibilityRule", knownLocationCompatibility() ? "huawei_mis_al00_sdk31"
                : locationCompatibilityObserved ? "zero_raw_fallback" : "none");
    }

    private boolean usesFullScanPermissionPolicy() {
        return FULL_SCAN_PERMISSION_POLICY.equals(BuildConfig.BLE_SCAN_PERMISSION_POLICY);
    }

    private boolean requiresLocationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false;
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true;
        return Build.VERSION.SDK_INT <= Build.VERSION_CODES.S_V2
                && usesFullScanPermissionPolicy();
    }

    private boolean requiresLocationService() {
        return requiresLocationPermission();
    }

    private boolean requireBluetooth(@NonNull String platformMethod, MethodChannel.Result result) {
        if (adapter == null || !adapter.isEnabled()) {
            returnError(
                    result,
                    platformMethod,
                    "bluetooth_unavailable",
                    "Bluetooth is unavailable or disabled."
            );
            return false;
        }
        if (!missingPermissions().isEmpty()) {
            returnError(
                    result,
                    platformMethod,
                    "bluetooth_permission_denied",
                    "Required Bluetooth permission is missing."
            );
            return false;
        }
        if ("startScan".equals(platformMethod) && "disabled".equals(locationServiceState())
                && (requiresLocationService() || knownLocationCompatibility())) {
            emitDiagnostic("location_compatibility_required", "scan", -1, null, "location_disabled");
            returnError(
                    result,
                    platformMethod,
                    "location_service_disabled",
                    "Location services are needed for nearby BLE scan compatibility. The App does not read or upload your location.",
                    scanEnvironment()
            );
            return false;
        }
        return true;
    }

    private void startScan(MethodCall call, MethodChannel.Result result) {
        if (!requireBluetooth("startScan", result)) return;
        if (scanning) {
            final Map<String, Object> details = new LinkedHashMap<>();
            details.put(
                    "scanSessionId",
                    activeScanSessionId == null ? "native-unknown" : activeScanSessionId
            );
            returnError(
                    result,
                    "startScan",
                    "gatt_busy",
                    "A BLE scan is already active; stop it before starting another session.",
                    details
            );
            return;
        }
        scanner = adapter.getBluetoothLeScanner();
        if (scanner == null) {
            returnError(result, "startScan", "bluetooth_unavailable", "BLE scanner is unavailable.");
            return;
        }
        final Integer timeoutMs = call.argument("timeoutMs");
        final String scanSessionId = call.argument("scanSessionId");
        final long timeout = BirdBoxScanTiming.effectiveTimeoutMs(
                BuildConfig.BLE_SCAN_STRATEGY_FALLBACK_ENABLED,
                timeoutMs
        );
        activeScanSessionId = scanSessionId == null || scanSessionId.isEmpty()
                ? "native-unknown"
                : scanSessionId;
        activeTraceId = activeScanSessionId;
        firstScanCallbackEmitted = false;
        scanRawResultCount = 0;
        locationCompatibilityObserved = false;
        scanning = true;
        final BirdBoxScanStrategyController.Snapshot initialStrategy =
                scanStrategyController.begin();
        try {
            startActiveScanStrategy(initialStrategy, "session_started");
            emitDiagnostic("scan_started", "scan", -1, null, "success");
            scanTimeout = () -> {
                if (BirdBoxScanCompatibility.needsLocationGuidance(knownLocationCompatibility(),
                        locationServiceState(), true, scanRawResultCount)) {
                    locationCompatibilityObserved = true;
                    emitDiagnostic("location_compatibility_required", "scan", -1, null, "zero_raw_results");
                    emitError(scanSink, "location_service_disabled",
                            "Location services are needed for nearby BLE scan compatibility. The App does not read or upload your location.",
                            scanEnvironment());
                }
                stopScan();
            };
            mainHandler.postDelayed(scanTimeout, timeout);
            result.success(null);
        } catch (SecurityException error) {
            emitDiagnostic("scan_start_failed", "scan", -1, null, "bluetooth_permission_denied");
            clearScanStateAfterFailure();
            returnError(
                    result,
                    "startScan",
                    "bluetooth_permission_denied",
                    "Bluetooth scan permission is missing."
            );
        } catch (RuntimeException error) {
            emitDiagnostic("scan_start_failed", "scan", -1, null, "ble_gatt_operation_failed");
            clearScanStateAfterFailure();
            returnError(result, "startScan", "gatt_operation_failed", "BLE scan could not start.");
        }
    }

    private void stopScan() {
        if (scanTimeout != null) mainHandler.removeCallbacks(scanTimeout);
        scanTimeout = null;
        cancelScanStrategyTimeout();
        if (!scanning) {
            activeScanSessionId = null;
            return;
        }
        emitDiagnostic("scan_stopped", "scan", -1, null, "success");
        emitScanStrategyEvent(
                "strategy_stopped",
                scanStrategyController.current(),
                "scan_stopped"
        );
        scanStrategyController.stop();
        stopActiveScanCallback();
        scanning = false;
        scanner = null;
        activeScanSessionId = null;
    }

    private void startActiveScanStrategy(
            @NonNull BirdBoxScanStrategyController.Snapshot strategy,
            @NonNull String reason) {
        final BluetoothLeScanner activeScanner = scanner;
        if (activeScanner == null) throw new IllegalStateException("BLE scanner is unavailable");
        final ScanSettings settings;
        final List<ScanFilter> filters;
        switch (strategy.strategy) {
            case NULL_FILTER_LOW_LATENCY:
                filters = null;
                settings = new ScanSettings.Builder()
                        .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                        .build();
                break;
            case EMPTY_FILTER_LIST_LOW_LATENCY:
                filters = new ArrayList<>();
                settings = new ScanSettings.Builder()
                        .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                        .build();
                break;
            case EMPTY_FILTER_LIST_DEFAULT_SETTINGS:
                filters = new ArrayList<>();
                settings = new ScanSettings.Builder().build();
                break;
            default:
                throw new IllegalStateException("Unknown BLE scan strategy");
        }
        final ScanCallback callback = scanCallback(strategy.generation);
        activeScanCallback = callback;
        activeScanner.startScan(filters, settings, callback);
        emitScanStrategyEvent("strategy_started", strategy, reason);
        if (BuildConfig.BLE_SCAN_STRATEGY_FALLBACK_ENABLED) {
            scheduleScanStrategyTimeout(strategy.generation);
        }
    }

    @NonNull
    private ScanCallback scanCallback(final int generation) {
        return new ScanCallback() {
            @Override
            public void onScanResult(int callbackType, @NonNull ScanResult result) {
                mainHandler.post(() -> emitScanResult(result, generation));
            }

            @Override
            public void onBatchScanResults(@NonNull List<ScanResult> results) {
                final List<ScanResult> copy = new ArrayList<>(results);
                mainHandler.post(() -> { for (ScanResult result : copy) emitScanResult(result, generation); });
            }

            @Override
            public void onScanFailed(int errorCode) {
                mainHandler.post(() -> handleScanFailure(generation, errorCode));
            }
        };
    }

    private void scheduleScanStrategyTimeout(final int generation) {
        cancelScanStrategyTimeout();
        scanStrategyTimeout = () -> onScanStrategyWindowElapsed(generation);
        mainHandler.postDelayed(
                scanStrategyTimeout,
                BirdBoxScanStrategyController.STRATEGY_WINDOW_MS
        );
    }

    private void cancelScanStrategyTimeout() {
        if (scanStrategyTimeout != null) mainHandler.removeCallbacks(scanStrategyTimeout);
        scanStrategyTimeout = null;
    }

    private void onScanStrategyWindowElapsed(final int generation) {
        scanStrategyTimeout = null;
        if (!scanning) return;
        final BirdBoxScanStrategyController.Decision decision =
                scanStrategyController.onWindowElapsed(generation);
        if (decision.type == BirdBoxScanStrategyController.DecisionType.IGNORE_STALE) return;
        emitScanStrategyEvent("strategy_window_elapsed", decision.completed, decision.reason);
        if (decision.type != BirdBoxScanStrategyController.DecisionType.SWITCH
                || decision.next == null) {
            return;
        }
        stopActiveScanCallback();
        try {
            startActiveScanStrategy(decision.next, decision.reason);
        } catch (SecurityException error) {
            handleScanFailure(decision.next.generation, ScanCallback.SCAN_FAILED_INTERNAL_ERROR);
        } catch (RuntimeException error) {
            handleScanFailure(decision.next.generation, ScanCallback.SCAN_FAILED_INTERNAL_ERROR);
        }
    }

    private void stopActiveScanCallback() {
        final ScanCallback callback = activeScanCallback;
        final BluetoothLeScanner activeScanner = scanner;
        activeScanCallback = null;
        if (callback == null || activeScanner == null) return;
        try {
            activeScanner.stopScan(callback);
        } catch (SecurityException ignored) {
            // Permission may have been revoked while the scan was active.
        } catch (RuntimeException ignored) {
            // Vendor stacks may already have removed a failed callback.
        }
    }

    private void handleScanFailure(final int generation, final int errorCode) {
        if (!scanStrategyController.recordAndroidError(generation, errorCode)) return;
        final String failedSessionId = activeScanSessionId;
        emitScanStrategyEvent(
                "strategy_failed",
                scanStrategyController.current(),
                "android_scan_failed"
        );
        if (scanTimeout != null) mainHandler.removeCallbacks(scanTimeout);
        scanTimeout = null;
        cancelScanStrategyTimeout();
        stopActiveScanCallback();
        scanStrategyController.stop();
        scanning = false;
        scanner = null;
        activeScanSessionId = null;
        emitDiagnostic("scan_failed", "scan", errorCode, null, "android_scan_failed");
        final Map<String, Object> diagnostic = new LinkedHashMap<>();
        diagnostic.put("eventType", "scanFailure");
        diagnostic.put("scanSessionId", failedSessionId == null ? "native-unknown" : failedSessionId);
        diagnostic.put("androidScanErrorCode", errorCode);
        emitSuccess(scanSink, diagnostic);
        final Map<String, Object> details = new LinkedHashMap<>();
        details.put("androidScanErrorCode", errorCode);
        details.put("scanSessionId", failedSessionId == null ? "native-unknown" : failedSessionId);
        emitError(scanSink, "ble_gatt_operation_failed", "BLE scan failed.", details);
    }

    private void clearScanStateAfterFailure() {
        cancelScanStrategyTimeout();
        stopActiveScanCallback();
        scanStrategyController.stop();
        scanning = false;
        activeScanSessionId = null;
        scanner = null;
    }

    private void emitScanResult(ScanResult result, int generation) {
        final EventChannel.EventSink sink = scanSink;
        if (!scanStrategyController.accepts(generation)) return;
        final ScanRecord record = result.getScanRecord();
        if (sink == null) return;
        scanRawResultCount++;
        if (!firstScanCallbackEmitted) {
            firstScanCallbackEmitted = true;
            emitDiagnostic("scan_first_callback", "scan", -1, null, "success");
        }
        final List<String> serviceUuids = new ArrayList<>();
        boolean hasBirdBoxService = false;
        final List<ParcelUuid> advertised = record == null ? null : record.getServiceUuids();
        if (advertised != null) {
            for (ParcelUuid value : advertised) {
                final String normalized = value.getUuid().toString().toLowerCase(Locale.ROOT);
                serviceUuids.add(normalized);
                hasBirdBoxService |= SERVICE_UUID.equals(value.getUuid());
            }
        }
        String localName = record == null ? null : record.getDeviceName();
        if (localName == null) localName = "";
        final boolean localNameCandidate = localName.startsWith("BirdBox-");
        final String deviceName = hasBirdBoxService || localNameCandidate
                ? ""
                : safeDeviceName(result.getDevice());
        final boolean deviceNameCandidate = deviceName.startsWith("BirdBox-");
        final boolean accepted = hasBirdBoxService || localNameCandidate || deviceNameCandidate;
        final String decisionReason = hasBirdBoxService
                ? "birdbox_service"
                : localNameCandidate
                ? "birdbox_local_name"
                : deviceNameCandidate
                ? "birdbox_device_name"
                : record == null ? "missing_scan_record" : "non_birdbox";
        if (!scanStrategyController.recordResult(
                generation,
                !deviceName.isEmpty(),
                accepted
        )) return;
        final String displayName = localName.isEmpty() && deviceNameCandidate
                ? deviceName
                : localName;
        final Map<String, Object> event = scanObservation(
                result,
                record,
                accepted,
                decisionReason,
                displayName,
                serviceUuids,
                generation,
                !deviceName.isEmpty()
        );
        if (!accepted) {
            emitSuccess(sink, event);
            return;
        }
        emitDiagnostic("scan_candidate_found", "scan", -1, null, decisionReason);

        final SparseArray<byte[]> manufacturerData = record == null
                ? null
                : record.getManufacturerSpecificData();
        Integer companyIdentifier = null;
        byte[] manufacturerPayload = null;
        if (manufacturerData != null && manufacturerData.size() > 0) {
            final int index = manufacturerData.indexOfKey(0xFFFF) >= 0 ? manufacturerData.indexOfKey(0xFFFF) : 0;
            companyIdentifier = manufacturerData.keyAt(index);
            manufacturerPayload = manufacturerData.valueAt(index);
        }
        event.put("deviceId", result.getDevice().getAddress());
        event.put("localName", displayName);
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
            @NonNull List<String> serviceUuids,
            int generation,
            boolean deviceNamePresent) {
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
        event.put("deviceNamePresent", deviceNamePresent);
        final BirdBoxScanStrategyController.Snapshot strategy =
                scanStrategyController.current();
        if (strategy != null && strategy.generation == generation) {
            event.put("strategyIndex", strategy.index);
            event.put("strategyName", strategy.strategy.name());
            event.put("strategyGeneration", strategy.generation);
        }

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

    @NonNull
    private String safeDeviceName(@NonNull BluetoothDevice device) {
        try {
            final String name = device.getName();
            return name == null ? "" : name;
        } catch (SecurityException ignored) {
            emitDiagnostic(
                    "scan_device_name_unavailable",
                    "scan",
                    -1,
                    null,
                    "bluetooth_permission_denied"
            );
            return "";
        } catch (RuntimeException ignored) {
            return "";
        }
    }

    private void emitScanStrategyEvent(
            @NonNull String event,
        @Nullable BirdBoxScanStrategyController.Snapshot strategy,
        @NonNull String reason) {
        if (strategy == null) return;
        if ("strategy_started".equals(event)
                && !scanStrategyController.markStarted(strategy.generation)) {
            return;
        }
        final Map<String, Object> diagnostic = new LinkedHashMap<>();
        diagnostic.put("eventType", "scanStrategy");
        diagnostic.put("strategyEvent", event);
        diagnostic.put("scanSessionId", activeScanSessionId == null ? "native-unknown" : activeScanSessionId);
        diagnostic.put("scanFlavor", BuildConfig.FLAVOR);
        diagnostic.put("scanPermissionPolicy", BuildConfig.BLE_SCAN_PERMISSION_POLICY);
        addLocationFacts(diagnostic);
        diagnostic.put("locationService", locationServiceState());
        diagnostic.put("strategyFallbackEnabled", BuildConfig.BLE_SCAN_STRATEGY_FALLBACK_ENABLED);
        diagnostic.put("strategyIndex", strategy.index);
        diagnostic.put("strategyName", strategy.strategy.name());
        diagnostic.put("strategyGeneration", strategy.generation);
        diagnostic.put("strategySwitchReason", reason);
        diagnostic.put("strategyRawResultCount", strategy.rawResultCount);
        diagnostic.put("strategyDeviceNameCount", strategy.deviceNameResultCount);
        diagnostic.put("strategyCandidateCount", strategy.candidateCount);
        if (strategy.androidScanErrorCode != null) {
            diagnostic.put("androidScanErrorCode", strategy.androidScanErrorCode);
        }
        emitSuccess(scanSink, diagnostic);
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
        try (FileInputStream input = new FileInputStream(applicationContext.getApplicationInfo().sourceDir)) {
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
        final String traceId = call.argument("traceId");
        if (traceId != null && !traceId.isEmpty()) activeTraceId = traceId;
        if (!requireBluetooth("connect", result)) return;
        if (pendingPreConnectResult != null || pendingControlledReleaseResult != null
                || (parkedResetGatt != null && !parkedResetDisconnected)) {
            returnError(result, "connect", "gatt_busy",
                    "The previous connection is still tearing down; retry after the disconnect event.");
            return;
        }
        if (pendingOperationResult != null) {
            returnError(
                    result,
                    "connect",
                    "gatt_busy",
                    "A GATT operation is still active."
            );
            return;
        }
        if (gatt != null
                || connectedDevice != null
                || linkReady
                || securityWriteStateMachine.isActive()
                || bondStateReceiver != null) {
            disconnectRequested = true;
            emitDiagnostic(
                    "stale_connection_reset",
                    "connect",
                    -1,
                    null,
                    "pre_connect_reset"
            );
            // MIS-AL00 155233: closing the old client synchronously and dialing in the
            // same call left the stale ACL undrained and the fresh dial silent for the
            // full 15 s deadline. Park the old client, wait for its real disconnect
            // callback (bounded), settle, and only then dial the new connection.
            closeGatt(false, "pre_connect_reset", BluetoothGatt.GATT_SUCCESS);
            if (parkedResetGatt != null && !parkedResetDisconnected) {
                emitDiagnostic(
                        "pre_connect_reset_parked",
                        "connect",
                        -1,
                        null,
                        "awaiting_stale_disconnect"
                );
                pendingPreConnectCall = call;
                pendingPreConnectResult = result;
                return;
            }
        }
        // A retire barrier just confirmed its disconnect leaves a bounded settle
        // window before the shared ACL is drained; defer the dial across it.
        final long settleRemaining = securityReconnectNotBefore - android.os.SystemClock.elapsedRealtime();
        if (settleRemaining > 0 && pendingOperationResult == null && gatt == null) {
            pendingPreConnectCall = call;
            pendingPreConnectResult = result;
            dialAfterPreConnectReset();
            return;
        }
        beginDial(call, result);
    }

    /** Continues the pre-connect reset once the stale client finished its teardown. */
    private void dialAfterPreConnectReset() {
        final MethodCall call = pendingPreConnectCall;
        final MethodChannel.Result result = pendingPreConnectResult;
        pendingPreConnectCall = null;
        pendingPreConnectResult = null;
        if (disposed || call == null || result == null) return;
        if (pendingControlledReleaseResult != null) return;
        final long settleRemaining = securityReconnectNotBefore - android.os.SystemClock.elapsedRealtime();
        if (settleRemaining > 0) {
            mainHandler.postDelayed(() -> {
                if (disposed || call == null || result == null) return;
                if (pendingOperationResult != null || gatt != null) {
                    returnError(result, "connect", "gatt_busy", "Another GATT operation is active.");
                    return;
                }
                beginDial(call, result);
            }, settleRemaining);
            return;
        }
        beginDial(call, result);
    }

    private void releaseParkedResetGatt() {
        if (parkedResetGuard != null) mainHandler.removeCallbacks(parkedResetGuard);
        parkedResetGuard = null;
        final BluetoothGatt parked = parkedResetGatt;
        parkedResetGatt = null;
        parkedResetDisconnected = false;
        parkedRetireReason = null;
        parkedRetireConnectionGeneration = 0;
        parkedRetireGattGeneration = 0;
        if (parked != null) {
            try { parked.close(); } catch (RuntimeException ignored) { }
        }
    }

    /** Retire reasons park the old client until its real disconnect callback arrives. */
    private static boolean isRetireBarrierReason(@NonNull String reason) {
        return "pre_connect_reset".equals(reason)
                || "controlled_reconnect".equals(reason)
                || "requested".equals(reason);
    }

    /** Arms the bounded guard that supersedes a parked client whose stack stays silent. */
    private void armParkedRetireGuard() {
        parkedResetGuard = () -> {
            parkedResetGuard = null;
            if (parkedResetGatt == null || parkedResetDisconnected) return;
            final boolean preConnect = "pre_connect_reset".equals(parkedRetireReason);
            emitDiagnostic(
                    preConnect ? "pre_connect_reset_disconnect_timeout"
                            : "controlled_release_disconnect_timeout",
                    pendingOperation,
                    -1,
                    null,
                    "disconnect_callback_missing"
            );
            lastReleasedConnectionGeneration = parkedRetireConnectionGeneration;
            lastReleasedGattInstanceId = parkedRetireGattGeneration;
            releaseParkedResetGatt();
            completeControlledRelease(false);
            dialAfterPreConnectReset();
        };
        mainHandler.postDelayed(parkedResetGuard, PARKED_RETIRE_DISCONNECT_GUARD_MS);
    }

    /** Sole completion point for the held prepareControlledReconnect result. */
    private void completeControlledRelease(boolean confirmed) {
        final MethodChannel.Result release = pendingControlledReleaseResult;
        pendingControlledReleaseResult = null;
        if (release == null) return;
        if (confirmed) {
            release.success(null);
        } else {
            final Map<String, Object> details = new LinkedHashMap<>();
            details.put("connectionGeneration", lastReleasedConnectionGeneration);
            details.put("gattInstanceId", lastReleasedGattInstanceId);
            release.error("gatt_release_unconfirmed",
                    "The retired GATT never confirmed its disconnect; it was force-closed.",
                    details);
        }
    }

    private void beginDial(MethodCall call, MethodChannel.Result result) {
        connectedDeviceAddressHash = null;
        previousBondState = null;
        gattGeneration = 0;
        gattRebuilt = false;
        systemPairingInteraction = false;
        bondInitiationSource = "none";
        currentMtu = 23;
        connectionGeneration++;
        emitDiagnostic("connect_requested", "connect", -1, null, null);
        if (!beginOperation("connect", result)) return;
        securityWriteStateMachine.reset();
        conditionalBondFallbackPolicy.reset();
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
            securityGattStatusObserved = false;
            connectedDevice = adapter.getRemoteDevice(deviceId);
            connectedDeviceAddressHash = saltedAddressHash(connectedDevice.getAddress(), activeTraceId);
            previousBondState = bondStateName(platform.bondState(connectedDevice));
            gatt = platform.connect(applicationContext, connectedDevice, gattCallback);
            if (gatt == null) {
                failPending("gatt_operation_failed", "GATT connection could not start.");
            } else {
                gattGeneration++;
                lastKnownConnectionState = BluetoothProfile.STATE_CONNECTING;
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
        final BluetoothGatt current = requireGatt("requestMtu", result);
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
        final BluetoothGatt current = requireGatt("readCharacteristic", result);
        if (current == null || !beginOperation("read", result)) return;
        final BluetoothGattCharacteristic characteristic = characteristic(call.argument("characteristicUuid"));
        pendingCharacteristicUuid = characteristic == null ? null : characteristic.getUuid();
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
        final BluetoothGatt current = requireGatt("setNotify", result);
        if (current == null || !beginOperation("descriptor", result)) return;
        final BluetoothGattCharacteristic characteristic = characteristic(call.argument("characteristicUuid"));
        final Boolean enabledValue = call.argument("enabled");
        final boolean enabled = Boolean.TRUE.equals(enabledValue);
        pendingNotificationEnabled = enabled;
        pendingCharacteristicUuid = characteristic == null ? null : characteristic.getUuid();
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
        final BluetoothGatt current = requireGatt("writeWithResponse", result);
        if (current == null) return;
        final BluetoothGattCharacteristic characteristic = characteristic(call.argument("characteristicUuid"));
        final byte[] value = call.argument("value");
        if (characteristic == null || value == null || value.length == 0
                || value.length > currentMtu - 3 || value.length > 512) {
            returnError(result, call.method, "invalid_request", "The write must fit the current ATT MTU.");
            return;
        }
        final boolean sensitive = WIFI_CONFIG_UUID.equals(characteristic.getUuid())
                || PROVISIONING_COMMAND_UUID.equals(characteristic.getUuid());
        if (sensitive && (activeSecurityRequestId == null || !linkReady
                || securedGattGeneration != gattGeneration
                || !securityWriteStateMachine.canWrite(gattGeneration)
                || !enabledNotifications.contains(NETWORK_STATUS_UUID)
                || !enabledNotifications.contains(SCAN_RESULTS_UUID))) {
            returnError(result, call.method, "ble_gatt_not_ready", "The current secured GATT and notifications must be ready.");
            return;
        }
        try {
            if (sensitive && platform.bondState(connectedDevice) != BluetoothDevice.BOND_BONDED) {
                returnError(result, call.method, "bond_lost", "System Bluetooth binding was lost.");
                return;
            }
            if (!beginOperation("write", result)) return;
            pendingCharacteristicUuid = characteristic.getUuid();
            if (sensitive) {
                securityWriteStateMachine.beginProtectedWrite(gattGeneration);
                securityWriteAttemptContext.recordCommandAttemptStarted(securityWriteStateMachine.writeAttemptCount());
                securityWriteAttemptContext.beginWriteChild(gattGeneration, characteristic.getUuid(), SystemClock.uptimeMillis());
                emitDiagnostic("security_write_started", "write", -1, characteristic.getUuid(), "submitted");
            }
            boolean accepted;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                if (sensitive) recordProtectedWriteInvocation(characteristic.getUuid());
                accepted = current.writeCharacteristic(characteristic, value,
                        BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT) == BluetoothGatt.GATT_SUCCESS;
            } else {
                characteristic.setWriteType(BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT);
                characteristic.setValue(value);
                if (sensitive) recordProtectedWriteInvocation(characteristic.getUuid());
                accepted = current.writeCharacteristic(characteristic);
            }
            if (!accepted) {
                failPending("ble_gatt_operation_failed", "GATT rejected the write.", gattFailureDetails(-1, characteristic.getUuid()));
            } else if (sensitive) startSecurityWriteCallbackGuard(characteristic.getUuid());
        } catch (SecurityException error) {
            if (pendingOperationResult == result) failPending("bluetooth_permission_denied", "Bluetooth connect permission is missing.");
            else returnError(result, call.method, "bluetooth_permission_denied", "Bluetooth connect permission is missing.");
        } catch (RuntimeException error) {
            if (pendingOperationResult == result) failPending("ble_gatt_operation_failed", "GATT write could not start.");
            else returnError(result, call.method, "ble_gatt_operation_failed", "GATT write could not start.");
        }
    }

    private void recordProtectedWriteInvocation(UUID uuid) {
        securityWriteAttemptContext.recordAttWriteInvoked(securityWriteStateMachine.writeAttemptCount());
        emitDiagnostic("security_write_api_invoked", "write", -1, uuid, "invoked");
    }

    /** Contract A8: real BluetoothAdapter bond state; Dart caches must never stand in. */
    private void getNativeBondState(MethodCall call, MethodChannel.Result result) {
        if (!requireBluetooth("getNativeBondState", result)) return;
        final String deviceId = call.argument("deviceId");
        if (deviceId == null || deviceId.isEmpty()) {
            returnError(result, call.method, "invalid_request", "A platform device handle is required.");
            return;
        }
        try {
            final BluetoothDevice device = adapter.getRemoteDevice(deviceId);
            final int state = platform.bondState(device);
            result.success(bondStateName(state));
        } catch (IllegalArgumentException error) {
            returnError(result, call.method, "invalid_request", "The platform device handle is invalid.");
        } catch (SecurityException error) {
            returnError(result, call.method, "bluetooth_permission_denied", "Bluetooth permission is missing.");
        } catch (RuntimeException error) {
            returnError(result, call.method, "bond_state_unknown", "Bond state could not be read.");
        }
    }

    /** Contract A8: process-unique GATT ownership facts for foreground/background sync. */
    private void getGattOwnershipState(MethodChannel.Result result) {
        final Map<String, Object> state = new LinkedHashMap<>();
        state.put("connected", gatt != null);
        state.put("linkReady", linkReady);
        state.put("connectionGeneration", connectionGeneration);
        state.put("gattInstanceId", gattGeneration);
        state.put("discoveryState", discoveryStateName());
        state.put("inflightRequest", activeSecurityRequestId);
        state.put("preparing", preparing());
        state.put("retiring", retiring());
        result.success(state);
    }

    @NonNull
    private String discoveryStateName() {
        // A ready link must never be reported as a stale "discovering"; discovery
        // callbacks can lag behind link readiness (BLE1019 R3).
        if (linkReady) return "ready";
        if (discoveryGatt == gatt && gatt != null) {
            if (gattServicesDiscovered) return "discovered";
            if (Boolean.TRUE.equals(discoveryApiAccepted)) return "discovering";
        }
        return gatt == null ? "absent" : "connected";
    }

    private boolean retiring() {
        return (parkedResetGatt != null && !parkedResetDisconnected)
                || pendingControlledReleaseResult != null;
    }

    /** Contract A8: retire the current GATT behind a real disconnect barrier; no createBond. */
    private void prepareControlledReconnect(MethodCall call, MethodChannel.Result result) {
        if (activeSecurityRequestId != null) {
            returnError(result, "prepareControlledReconnect", "gatt_busy",
                    "Cancel the owned pairing before rebuilding its connection.");
            return;
        }
        final Number expectedConnection = call.argument("expectedConnectionGeneration");
        final Number expectedInstance = call.argument("expectedGattInstanceId");
        if ((expectedConnection == null) != (expectedInstance == null)) {
            returnError(result, "prepareControlledReconnect", "invalid_request",
                    "Both ownership expectations or neither are required.");
            return;
        }
        if (gatt == null) {
            if (expectedConnection != null
                    && expectedConnection.intValue() == lastReleasedConnectionGeneration
                    && expectedInstance.intValue() == lastReleasedGattInstanceId) {
                emitDiagnostic("controlled_reconnect_already_released",
                        "prepareControlledReconnect", -1, null, "idempotent_release");
                result.success(null);
            } else {
                returnError(result, "prepareControlledReconnect", "invalid_state",
                        "No GATT connection is owned to rebuild.");
            }
            return;
        }
        if (expectedConnection != null && (expectedConnection.intValue() != connectionGeneration
                || expectedInstance.intValue() != gattGeneration)) {
            returnError(result, "prepareControlledReconnect", "gatt_owner_mismatch",
                    "The expected connection generation or GATT instance no longer owns the link.");
            return;
        }
        if (pendingControlledReleaseResult != null) {
            returnError(result, "prepareControlledReconnect", "gatt_busy",
                    "A controlled release is already in flight.");
            return;
        }
        emitDiagnostic("controlled_reconnect_requested", "prepareControlledReconnect", -1, null,
                "teardown_then_redial");
        disconnectRequested = true;
        failPendingIfActive("gatt_operation_failed", "The active GATT operation was cancelled.");
        final BluetoothGatt retiring = gatt;
        closeGatt(false, "controlled_reconnect", BluetoothGatt.GATT_SUCCESS);
        if (retiring != null && parkedResetGatt != null && !parkedResetDisconnected) {
            // Completed once the parked client's real disconnect callback arrives,
            // or by the guard timeout with gatt_release_unconfirmed.
            pendingControlledReleaseResult = result;
            return;
        }
        if (retiring != null) {
            // Fast path: the link was already gone, so close ran without a barrier.
            emitDiagnostic("controlled_release_immediate", "prepareControlledReconnect",
                    -1, null, "already_disconnected");
        }
        result.success(null);
    }

    /**
     * Contract A1/A8: one opaque preflight write to 0007 before any bonding. The channel
     * treats it as a non-sensitive public write: no createBond, no encryption gate, no
     * payload interpretation. Responses arrive as regular 0003 notifications.
     */
    private void writePairingPreflight(MethodCall call, MethodChannel.Result result) {
        if (!requireBluetooth("writePairingPreflight", result)) return;
        if (gatt == null || connectedDevice == null) {
            returnError(result, call.method, "ble_gatt_not_ready", "Connect and discover services first.");
            return;
        }
        if (activeSecurityRequestId != null || securityWriteStateMachine.isActive() || preparing()) {
            returnError(result, call.method, "gatt_busy", "A pairing attempt is active.");
            return;
        }
        // Ownership gate (BLE1019 R2): the caller pins the generation facts it read
        // from getGattOwnershipState; a mismatch must neither write nor disturb the
        // new owner. Both arguments are optional but must arrive as a pair.
        final Number expectedConnection = call.argument("expectedConnectionGeneration");
        final Number expectedInstance = call.argument("expectedGattInstanceId");
        if ((expectedConnection == null) != (expectedInstance == null)) {
            returnError(result, call.method, "invalid_request",
                    "Both ownership expectations or neither are required.");
            return;
        }
        if (expectedConnection != null && (expectedConnection.intValue() != connectionGeneration
                || expectedInstance.intValue() != gattGeneration)) {
            returnError(result, call.method, "gatt_owner_mismatch",
                    "The expected connection generation or GATT instance no longer owns the link.");
            return;
        }
        final BluetoothGattCharacteristic characteristic = characteristic(PAIRING_PREFLIGHT_UUID.toString());
        if (characteristic == null) {
            // Old board without the preflight characteristic; Dart gates on capabilities.
            emitDiagnostic("pairing_preflight_unavailable", "writePairingPreflight", -1,
                    PAIRING_PREFLIGHT_UUID, "characteristic_missing");
            returnError(result, call.method, "pairing_preflight_unsupported",
                    "The board does not expose the pairing preflight characteristic.");
            return;
        }
        final byte[] value = call.argument("value");
        if (value == null || value.length == 0 || value.length > currentMtu - 3 || value.length > 512) {
            returnError(result, call.method, "invalid_request", "The preflight write must fit the current ATT MTU.");
            return;
        }
        // Bond gate (BLE1019 R2): re-read the real system bond right before the public
        // write; bonding/bonded/unknown never write and never trigger createBond here.
        final int bondState;
        try {
            bondState = platform.bondState(connectedDevice);
        } catch (RuntimeException error) {
            returnError(result, call.method, "bond_state_unknown", "Bond state could not be read.");
            return;
        }
        if (bondState != BluetoothDevice.BOND_NONE) {
            emitDiagnostic("pairing_preflight_bond_rejected", call.method, -1,
                    PAIRING_PREFLIGHT_UUID, bondStateName(bondState));
            returnError(result, call.method, "bond_state_not_none",
                    "The public preflight write requires an unbound device.");
            return;
        }
        if (!beginOperation("preflight", result)) return;
        pendingCharacteristicUuid = characteristic.getUuid();
        try {
            final boolean accepted;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                accepted = gatt.writeCharacteristic(characteristic, value,
                        BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT) == BluetoothGatt.GATT_SUCCESS;
            } else {
                characteristic.setWriteType(BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT);
                characteristic.setValue(value);
                accepted = gatt.writeCharacteristic(characteristic);
            }
            if (!accepted) failPending("ble_gatt_operation_failed", "GATT rejected the preflight write.",
                    gattFailureDetails(-1, characteristic.getUuid()));
        } catch (SecurityException error) {
            failPending("bluetooth_permission_denied", "Bluetooth permission is missing.");
        } catch (RuntimeException error) {
            failPending("ble_gatt_operation_failed", "GATT preflight write could not start.");
        }
    }

    private void beginSecurityWrite(MethodCall call, MethodChannel.Result result) {
        if (!requireBluetooth(call.method, result)) return;
        final String request = call.argument("requestId");
        final String command = call.argument("commandType");
        if (request == null || request.isEmpty() || command == null || command.isEmpty()) {
            returnError(result, call.method, "invalid_request", "A request_id and command type are required.");
            return;
        }
        if (gatt == null || connectedDevice == null || !linkReady) {
            returnError(result, call.method, "ble_gatt_not_ready", "Read and validate BirdBox Device Info before pairing.");
            return;
        }
        // Single-flight: a repeated preparePairing with the same request id joins the
        // in-flight attempt instead of starting a second bond chain or failing busy.
        if (securityWriteStateMachine.isActive() && request.equals(activeSecurityRequestId)) {
            emitDiagnostic("pairing_attempt_replayed", call.method, -1, null, "single_flight_reuse");
            result.success(securityReadyMetadata());
            return;
        }
        if (pendingOperationResult != null || securityWriteStateMachine.isActive()) {
            returnError(result, call.method, "gatt_busy", "Another pairing or GATT operation is active.");
            return;
        }
        activeSecurityRequestId = request;
        activeSecurityCommandType = command;
        pairingMetadataResult = "preparePairing".equals(call.method);
        systemBondAttempted = false;
        bondInitiationSource = "none";
        securityConnectRetryCount = 0;
        securityWriteAttemptContext.beginPairing(request, connectionGeneration, gattGeneration, SystemClock.uptimeMillis());
        if ("open_pairing".equals(command))
            emitDiagnostic("user_start_pairing", call.method, -1, null, "requested");
        if (!beginOperation("preparePairing", result)) return;
        // Later commands reuse a confirmed secure GATT rather than bonding/rebuilding each time.
        try {
            if (!"open_pairing".equals(command) && securedGattGeneration == gattGeneration
                    && platform.bondState(connectedDevice) == BluetoothDevice.BOND_BONDED
                    && enabledNotifications.containsAll(Arrays.asList(NETWORK_STATUS_UUID, SCAN_RESULTS_UUID))) {
                securityWriteStateMachine.markGattReady(gattGeneration);
                securityWriteStateMachine.beginReadyRequest(request, gattGeneration);
                succeedPending(pairingMetadataResult ? securityReadyMetadata() : null);
                return;
            }
            gattRebuilt = false;
            pairingCoordinator.start(request, gattGeneration);
        } catch (RuntimeException error) {
            failNativePreparation(error instanceof SecurityException
                    ? "bluetooth_permission_denied" : "bond_start_failed");
        }
    }

    private void startSecurityWriteCallbackGuard(@NonNull UUID uuid) {
        cancelSecurityWriteCallbackGuard();
        final String request = activeSecurityRequestId;
        final int connection = connectionGeneration, generation = gattGeneration;
        final long token = operationToken;
        if (!securityWriteAttemptContext.markApiAccepted(request, connection, generation, uuid)) return;
        securityWriteCallbackGuard = () -> {
            if (token != operationToken || !"write".equals(pendingOperation)
                    || !securityWriteAttemptContext.completeFromCallbackTimeout(request, connection, generation, uuid)) return;
            securityWriteCallbackGuard = null;
            emitDiagnostic("security_write_callback_timeout", "write", -1, uuid, "callback_missing");
            failProtectedWrite(-1, uuid);
        };
        mainHandler.postDelayed(securityWriteCallbackGuard, SECURITY_WRITE_CALLBACK_GUARD_MS);
    }

    private void cancelSecurityWriteCallbackGuard() {
        if (securityWriteCallbackGuard != null) mainHandler.removeCallbacks(securityWriteCallbackGuard);
        securityWriteCallbackGuard = null;
    }

    private void failProtectedWrite(int status, UUID uuid) {
        cancelSecurityWriteCallbackGuard();
        try {
            if (connectedDevice == null || platform.bondState(connectedDevice) != BluetoothDevice.BOND_BONDED) {
                securityWriteStateMachine.failAttempt(BirdBoxSecurityWriteStateMachine.Failure.PAIRING_REJECTED);
                failPending("bond_lost", "Bluetooth binding was lost.", gattFailureDetails(status, uuid));
                closeGatt(true, "bond_lost", status);
                return;
            }
            if (securityWriteStateMachine.phase() == BirdBoxSecurityWriteStateMachine.Phase.RETRYING_ENCRYPTED_WRITE) {
                securityWriteStateMachine.onEncryptedRetryFailed();
                emitDiagnostic("security_write_retry_result", "write", status, uuid, "failed");
                failPending("ble_encrypted_retry_failed", "The single bound write retry failed.", gattFailureDetails(status, uuid));
                closeGatt(true, "encrypted_retry_failed", status);
                return;
            }
            securityWriteStateMachine.beginBondedRecovery();
            // Isolate missing/late callbacks before admitting another request on the same UUID.
            final BluetoothGatt old = gatt;
            if (old != null) closeGattForSecurity(old, true);
            securedGattGeneration = -1;
            enabledNotifications.clear();
            failPending("ble_link_not_encrypted", "The bound GATT requires its single recovery.", gattFailureDetails(status, uuid));
        } catch (SecurityException error) {
            failPending("bluetooth_permission_denied", "Bluetooth connect permission is missing.");
            closeGatt(true, "permission_revoked", status);
        }
    }

    private void awaitSecurityReady(MethodCall call, MethodChannel.Result result) {
        if (!requireSecurityRequest(call, result)) return;
        if (securityWriteStateMachine.phase() != BirdBoxSecurityWriteStateMachine.Phase.BONDED_RECOVERING_GATT) {
            returnError(result, call.method, "ble_encrypted_retry_failed", "No bound recovery is permitted.");
            return;
        }
        pairingMetadataResult = "recoverPairing".equals(call.method);
        if (!beginOperation("securityRecovery", result)) return;
        try {
            if (connectedDevice == null || platform.bondState(connectedDevice) != BluetoothDevice.BOND_BONDED) {
                failNativePreparation("bond_lost");
                return;
            }
            emitDiagnostic("security_write_retry_started", "securityRecovery", -1, null, "single_rebuild");
            reconnectGattAfterSecurity();
        } catch (RuntimeException error) {
            failNativePreparation(error instanceof SecurityException ? "bluetooth_permission_denied" : "ble_gatt_recovery_failed");
        }
    }

    private void beginSecurityRetry(MethodCall call, MethodChannel.Result result) {
        if (!requireSecurityRequest(call, result)) return;
        if (securedGattGeneration != gattGeneration || !linkReady
                || securityWriteStateMachine.phase() != BirdBoxSecurityWriteStateMachine.Phase.RETRYING_ENCRYPTED_WRITE) {
            returnError(result, call.method, "ble_encrypted_retry_failed", "The single retry GATT is not ready.");
            return;
        }
        result.success(null);
    }

    private void markSecurityWriteSent(MethodCall call, MethodChannel.Result result) {
        if (!requireSecurityRequest(call, result)) return;
        try {
            securityWriteStateMachine.onWriteSucceeded();
            emitDiagnostic("security_write_result", "write_command", 0, null, "success");
            emitSecurityPhase("write_with_response_succeeded");
            result.success(null);
        } catch (IllegalStateException error) {
            returnError(
                    result,
                    "markSecurityWriteSent",
                    "ble_encrypted_retry_failed",
                    error.getMessage()
            );
        }
    }

    private void completeSecurityWrite(MethodCall call, MethodChannel.Result result) {
        if (!requireSecurityRequest(call, result)) return;
        final String requestId = call.argument("requestId");
        try {
            if (!securityWriteStateMachine.onResponse(requestId)) {
                returnError(
                        result,
                        "completeSecurityWrite",
                        "invalid_request",
                        "The BirdBox response request_id did not match."
                );
                return;
            }
            emitDiagnostic(
                    "security_write_completed",
                    "write_command",
                    -1,
                    null,
                    (String) call.argument("responseType")
            );
            finishSecuritySession("success");
            result.success(null);
        } catch (IllegalStateException error) {
            returnError(
                    result,
                    "completeSecurityWrite",
                    "invalid_state",
                    error.getMessage()
            );
        }
    }

    private void failSecurityWrite(MethodCall call, MethodChannel.Result result) {
        // MIS-AL00 161410: a late Dart cleanup after the native side already terminated
        // the attempt surfaced as invalid_request and its platform_error overwrote the
        // first error. Cleanup on a finished or absent attempt is an idempotent noop.
        if (activeSecurityRequestId == null) {
            emitDiagnostic("security_write_cleanup_noop", "security_write", -1, null, "already_completed");
            result.success(null);
            return;
        }
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
                } else if ("ble_pairing_timeout".equals(errorCode)) {
                    securityWriteStateMachine.onPairingTimeout();
                } else {
                    securityWriteStateMachine.onPairingNotStartedTimeout();
                }
            }
        } catch (IllegalStateException ignored) {
            // Cleanup is still required when Dart reports a terminal error after a racing callback.
        }
        emitSecurityPhase(errorCode == null ? "failed" : errorCode);
        final boolean wasPreparing = preparing();
        failPendingIfActive(errorCode == null ? "invalid_state" : errorCode,
                "The owned security request was cancelled or failed.");
        if (securityWriteAttemptContext.attemptId() != null && securityWriteAttemptContext.terminalOutcome() == null) {
            securityWriteAttemptContext.markTerminal(
                    errorCode == null ? "failed" : stableErrorCode(errorCode)
            );
        }
        if (wasPreparing || isTerminalTransportFailure(errorCode)) {
            disconnectRequested = true;
            closeGatt(true, "security_failure", BluetoothGatt.GATT_FAILURE);
        } else {
            finishSecuritySession(errorCode == null ? "failed" : errorCode);
        }
        result.success(null);
    }

    private static boolean isTerminalTransportFailure(@Nullable String errorCode) {
        return "ble_link_not_encrypted".equals(errorCode)
                || "ble_le_pairing_not_started".equals(errorCode)
                || "ble_pairing_rejected".equals(errorCode)
                || "ble_pairing_timeout".equals(errorCode)
                || "ble_bond_rejected".equals(errorCode)
                || "ble_bond_failed".equals(errorCode)
                || "ble_bond_timeout".equals(errorCode)
                || "ble_gatt_recovery_failed".equals(errorCode)
                || "ble_security_recovery_failed".equals(errorCode)
                || "ble_encrypted_retry_failed".equals(errorCode)
                || "pairing_open_timeout".equals(errorCode);
    }

    private void registerBondStateReceiver(@NonNull BluetoothDevice device) {
        unregisterBondStateReceiver();
        final long owner = pairingCoordinator.owner();
        final int connection = connectionGeneration;
        final String request = activeSecurityRequestId;
        bondStateReceiver = new BroadcastReceiver() {
            @Override public void onReceive(Context context, Intent intent) {
                if (!BluetoothDevice.ACTION_BOND_STATE_CHANGED.equals(intent.getAction())) return;
                final BluetoothDevice changed = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
                        ? intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice.class)
                        : intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE);
                final int state = intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, BluetoothDevice.ERROR);
                final int previous = intent.getIntExtra(BluetoothDevice.EXTRA_PREVIOUS_BOND_STATE, BluetoothDevice.ERROR);
                mainHandler.post(() -> {
                    if (!pairingCoordinator.owns(owner) || connection != connectionGeneration
                            || !request.equals(activeSecurityRequestId) || changed == null || !device.equals(changed)) return;
                    previousBondState = bondStateName(previous);
                    emitDiagnostic("bond_state_changed", "preparePairing", -1, null,
                            bondStateName(previous) + "_to_" + bondStateName(state));
                    // Protected system broadcast plus actual state prevents stale transitions.
                    try {
                        if (platform.bondState(changed) != state) return;
                        if (state == BluetoothDevice.BOND_NONE && previous == BluetoothDevice.BOND_BONDED
                                && !pairingCoordinator.waitingForBond()) {
                            failPendingIfActive("bond_lost", "Bluetooth binding was lost.");
                            closeGatt(true, "bond_lost", BluetoothGatt.GATT_FAILURE);
                            return;
                        }
                        pairingCoordinator.bondChanged(owner, state, previous);
                    } catch (RuntimeException error) {
                        failNativePreparation(error instanceof SecurityException ? "bluetooth_permission_denied" : "bond_state_unknown");
                    }
                });
            }
        };
        final IntentFilter filter = new IntentFilter(BluetoothDevice.ACTION_BOND_STATE_CHANGED);
        platform.register(applicationContext, bondStateReceiver, filter);
        emitDiagnostic("bond_receiver_registered", "preparePairing", -1, null, "before_create_bond");
    }

    private void unregisterBondStateReceiver() {
        final BroadcastReceiver old = bondStateReceiver;
        bondStateReceiver = null;
        if (old != null) {
            try { platform.unregister(applicationContext, old); }
            catch (RuntimeException ignored) { }
        }
    }

    private void cancelConditionalBondFallback() {
        if (conditionalBondFallback != null) mainHandler.removeCallbacks(conditionalBondFallback);
        conditionalBondFallback = null;
        conditionalBondFallbackPolicy.cancelPending();
    }

    private void cancelBondTimeout() {
        if (bondTimeout != null) mainHandler.removeCallbacks(bondTimeout);
        bondTimeout = null;
    }

    private void cancelPreparationTimeout() {
        if (preparationTimeout != null) mainHandler.removeCallbacks(preparationTimeout);
        preparationTimeout = null;
    }

    private boolean preparing() {
        return "preparePairing".equals(pendingOperation) || "securityRecovery".equals(pendingOperation);
    }

    private void setPreparationStep(String step) {
        cancelPreparationTimeout();
        preparationStep = step;
        preparationStepStartedAt = SystemClock.uptimeMillis();
        final long token = operationToken;
        final int connection = connectionGeneration, generation = gattGeneration;
        preparationTimeout = () -> {
            if (token != operationToken || connection != connectionGeneration || generation != gattGeneration
                    || !preparing() || !step.equals(preparationStep)) return;
            if ("services".equals(step) || "services_wait".equals(step))
                emitDiagnostic("gatt_service_discovery_timeout", pendingOperation, -1, null,
                        discoveryGatt == gatt && Boolean.TRUE.equals(discoveryApiAccepted) ? "callback_missing" : "api_not_invoked");
            if ("mtu_before_services".equals(step))
                emitDiagnostic("gatt_mtu_barrier_timeout", pendingOperation, -1, null, "callback_missing");
            // A fresh-bond first connect that never calls back is one of the two observed
            // post-bond transient shapes (no 133, 15s silence). Same bounded retry as the
            // callback path; the guard inside retrySecurityConnect keeps it single-shot.
            if ("gatt_connect".equals(step) && securityConnectRetryCount < SECURITY_CONNECT_RETRY_MAX) {
                retrySecurityConnect(-1);
                return;
            }
            failNativePreparation("ble_gatt_recovery_failed");
        };
        mainHandler.postDelayed(preparationTimeout, 15_000L);
        emitSecurityPhase(step);
    }

    private void failNativePreparation(String code) {
        failNativePreparation(code, -1);
    }

    private void failNativePreparation(String code, int gattStatus) {
        preparationFailurePhase = securityPhaseName();
        final String failedStep = preparationStep == null ? "system_bond" : preparationStep;
        final Map<String, Object> details = gattFailureDetails(gattStatus, null);
        details.put("preparationStep", failedStep);
        details.put("failurePhase", securityPhaseName());
        details.put("teardownReason", code);
        // First-error fidelity: the first terminal outcome names the root cause; a
        // racing cleanup must not rewrite it (the fact event keeps the original).
        if (securityWriteAttemptContext.terminalOutcome() == null) {
            securityWriteAttemptContext.markTerminal(code);
        }
        if (securityWriteStateMachine.phase() != BirdBoxSecurityWriteStateMachine.Phase.FAILED)
            securityWriteStateMachine.failAttempt(BirdBoxSecurityWriteStateMachine.Failure.GATT_RECOVERY_FAILED);
        emitDiagnostic("security_preparation_failed", pendingOperation, gattStatus, null, code);
        failPending(code, "Bluetooth preparation failed at " + failedStep, details);
        closeGatt(true, code, gattStatus >= 0 ? gattStatus : BluetoothGatt.GATT_FAILURE);
    }

    private void reconnectGattAfterSecurity() {
        cancelBondTimeout();
        cancelSecurityWriteCallbackGuard();
        cancelConditionalBondFallback();
        if (!preparing() || connectedDevice == null) { failNativePreparation("ble_gatt_recovery_failed"); return; }
        // Even a normal bonded preparation can reuse a physical ACL before
        // its previous ATT client has drained. Retire every owned old client
        // through the same bounded disconnect/settle gate.
        if (gatt != null) closeGattForSecurity(gatt, true);
        if (!preparing()) return;
        if (retiringGatt != null && !retiringGattDisconnected) {
            setPreparationStep("old_gatt_disconnect");
            emitDiagnostic("gatt_disconnect_wait_started", pendingOperation, -1, null, "security_gatt_rebuild");
            return;
        }
        final long settleRemaining = securityReconnectNotBefore - android.os.SystemClock.elapsedRealtime();
        if (settleRemaining > 0) {
            setPreparationStep("old_gatt_settle");
            final String owner = activeSecurityRequestId;
            final int connection = connectionGeneration;
            if (securityReconnectGuard != null) mainHandler.removeCallbacks(securityReconnectGuard);
            emitDiagnostic("gatt_disconnect_settle_started", pendingOperation, -1, null, "security_gatt_rebuild");
            securityReconnectGuard = () -> {
                securityReconnectGuard = null;
                if (connection != connectionGeneration || owner == null || !owner.equals(activeSecurityRequestId)
                        || !preparing() || !"old_gatt_settle".equals(preparationStep)) return;
                reconnectGattAfterSecurity();
            };
            mainHandler.postDelayed(securityReconnectGuard, settleRemaining);
            return;
        }
        final BluetoothDevice device = connectedDevice;
        try {
            if (platform.bondState(device) != BluetoothDevice.BOND_BONDED) { failNativePreparation("bond_lost"); return; }
            emitDiagnostic("gatt_rebuild_started", pendingOperation, -1, null, "bonded");
            gatt = null;
            linkReady = false;
            securedGattGeneration = -1;
            enabledNotifications.clear();
            currentMtu = 23;
            gattRebuilt = false;
            gattGeneration++;
            setPreparationStep("gatt_connect");
            gatt = platform.connect(applicationContext, device, gattCallback);
            if (gatt == null) failNativePreparation("ble_gatt_recovery_failed");
        } catch (RuntimeException error) {
            failNativePreparation(error instanceof SecurityException ? "bluetooth_permission_denied" : "ble_gatt_recovery_failed");
        }
    }

    /**
     * Bounded single retry for the first connect attempt right after a fresh bond on
     * legacy stacks (status 133 at connect, or a silent connect with no callback).
     * The failed client keeps its registration — disconnect requested, then held like
     * other disconnected legacy clients — because unregistering it before the retry
     * dial can disturb the vendor address mapping the held-registration policy already
     * guards. One settle gate drains the fresh-bond window before dialing again; a
     * second failure terminates as before, with both statuses in the record.
     */
    private void retrySecurityConnect(int gattStatus) {
        if (securityConnectRetryCount >= SECURITY_CONNECT_RETRY_MAX) {
            failNativePreparation("ble_gatt_recovery_failed", gattStatus);
            return;
        }
        securityConnectRetryCount++;
        emitDiagnostic("gatt_connect_retry_started", pendingOperation, gattStatus, null, "first_post_bond_rebuild");
        final BluetoothGatt failed = gatt;
        if (failed != null) {
            if (heldLegacyRegistrations.size() >= MAX_HELD_LEGACY_REGISTRATIONS) {
                emitDiagnostic("gatt_legacy_registration_limit", pendingOperation, -1, null, "session_reconnect_required");
                failNativePreparation("ble_gatt_recovery_failed", gattStatus);
                return;
            }
            try { failed.disconnect(); } catch (RuntimeException ignored) { }
            heldLegacyRegistrations.add(failed);
        }
        final BluetoothDevice device = connectedDevice;
        try {
            if (device == null || platform.bondState(device) != BluetoothDevice.BOND_BONDED) {
                failNativePreparation("bond_lost", gattStatus);
                return;
            }
            gatt = null;
            linkReady = false;
            securedGattGeneration = -1;
            enabledNotifications.clear();
            currentMtu = 23;
            gattRebuilt = false;
            gattGeneration++;
            securityReconnectNotBefore = android.os.SystemClock.elapsedRealtime() + SECURITY_DISCONNECT_SETTLE_MS;
            setPreparationStep("gatt_connect");
            final String owner = activeSecurityRequestId;
            final int connection = connectionGeneration;
            final long token = operationToken;
            if (securityReconnectGuard != null) mainHandler.removeCallbacks(securityReconnectGuard);
            securityReconnectGuard = () -> {
                securityReconnectGuard = null;
                if (token != operationToken || connection != connectionGeneration || owner == null
                        || !owner.equals(activeSecurityRequestId) || !preparing()
                        || !"gatt_connect".equals(preparationStep)) return;
                reconnectGattAfterSecurity();
            };
            mainHandler.postDelayed(securityReconnectGuard, SECURITY_DISCONNECT_SETTLE_MS);
        } catch (RuntimeException error) {
            failNativePreparation(error instanceof SecurityException ? "bluetooth_permission_denied" : "ble_gatt_recovery_failed", gattStatus);
        }
    }

    private void subscribePreparedNotifications() {
        if (notificationIndex >= 2) {
            cancelPreparationTimeout();
            securityWriteStateMachine.onNotificationsRestored();
            linkReady = true;
            securedGattGeneration = gattGeneration;
            gattRebuilt = true;
            emitDiagnostic("gatt_rebuild_completed", pendingOperation, BluetoothGatt.GATT_SUCCESS, null, "notifications_ready");
            emitSecurityPhase("security_ready");
            succeedPending(pairingMetadataResult ? securityReadyMetadata()
                    : "securityRecovery".equals(pendingOperation) ? Boolean.TRUE : null);
            return;
        }
        final UUID uuid = notificationIndex == 0 ? NETWORK_STATUS_UUID : SCAN_RESULTS_UUID;
        final BluetoothGattCharacteristic c = characteristic(uuid.toString());
        final BluetoothGattDescriptor descriptor = c == null ? null : c.getDescriptor(CLIENT_CONFIGURATION_UUID);
        try {
            if (descriptor == null || !gatt.setCharacteristicNotification(c, true)) {
                failNativePreparation("ble_gatt_recovery_failed"); return;
            }
            final byte[] value = (c.getProperties() & BluetoothGattCharacteristic.PROPERTY_INDICATE) != 0
                    ? BluetoothGattDescriptor.ENABLE_INDICATION_VALUE : BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE;
            pendingCharacteristicUuid = uuid;
            setPreparationStep("notification_" + notificationIndex);
            boolean accepted;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                accepted = gatt.writeDescriptor(descriptor, value) == BluetoothGatt.GATT_SUCCESS;
            } else {
                descriptor.setValue(value);
                accepted = gatt.writeDescriptor(descriptor);
            }
            if (!accepted) failNativePreparation("ble_gatt_recovery_failed");
        } catch (RuntimeException error) {
            failNativePreparation(error instanceof SecurityException ? "bluetooth_permission_denied" : "ble_gatt_recovery_failed");
        }
    }

    private Map<String, Object> securityReadyMetadata() {
        final Map<String, Object> value = new LinkedHashMap<>();
        value.put("requestId", activeSecurityRequestId);
        value.put("attemptId", securityWriteAttemptContext.attemptId());
        value.put("connectionGeneration", connectionGeneration);
        value.put("gattGeneration", gattGeneration);
        value.put("mtu", currentMtu);
        value.put("notificationsReady", linkReady && securedGattGeneration == gattGeneration);
        value.put("gattRebuilt", gattRebuilt);
        return value;
    }

    private boolean requireSecurityRequest(MethodCall call, MethodChannel.Result result) {
        final String requestId = call.argument("requestId");
        final String attempt = call.argument("attemptId");
        final Number connection = call.argument("connectionGeneration");
        if (requestId == null || !requestId.equals(activeSecurityRequestId)
                || (attempt != null && !attempt.equals(securityWriteAttemptContext.attemptId()))
                || (connection != null && connection.intValue() != connectionGeneration)) {
            returnError(
                    result,
                    call.method,
                    "invalid_request",
                    "No matching security-write request is active."
            );
            return false;
        }
        return true;
    }

    private void finishSecuritySession(@NonNull String terminalOutcome) {
        final boolean hadAttempt = securityWriteAttemptContext.attemptId() != null;
        final UUID characteristicUuid = securityWriteAttemptContext.characteristicUuid();
        if (hadAttempt) {
            if (securityWriteAttemptContext.terminalOutcome() == null) {
                securityWriteAttemptContext.markTerminal(terminalOutcome);
            }
            emitDiagnostic(
                    "security_write_terminal",
                    "security_write",
                    -1,
                    characteristicUuid,
                    securityWriteAttemptContext.terminalOutcome()
            );
        }
        cancelSecurityWriteCallbackGuard();
        cancelConditionalBondFallback();
        pairingCoordinator.cancel();
        cancelPreparationTimeout();
        preparationStep = null;
        preparationFailurePhase = null;
        unregisterBondStateReceiver();
        if (hadAttempt) {
            securityWriteAttemptContext.markCleanup("complete");
            // This is the immutable end-of-request evidence event. It is emitted before the
            // active context is reset, so cleanup cannot erase whether createBond() was tried.
            emitDiagnostic(
                    "security_write_fact_finalized",
                    "security_write",
                    -1,
                    characteristicUuid,
                    securityWriteAttemptContext.terminalOutcome()
            );
            emitDiagnostic(
                    "security_write_cleanup_completed",
                    "security_write",
                    -1,
                    characteristicUuid,
                    "complete"
            );
        }
        activeSecurityRequestId = null;
        activeSecurityCommandType = null;
        securityBondingObserved = false;
        securityFailureObserved = false;
        securityGattStatusObserved = false;
        bondInitiationSource = "none";
        securityWriteAttemptContext.reset();
        conditionalBondFallbackPolicy.reset();
        securityWriteStateMachine.reset();
        systemBondAttempted = false;
    }

    @Nullable
    private BluetoothGatt requireGatt(@NonNull String platformMethod, MethodChannel.Result result) {
        if (!requireBluetooth(platformMethod, result)) return null;
        if (preparing()) {
            returnError(result, platformMethod, "ble_gatt_not_ready", "Bluetooth security preparation is still active.");
            return null;
        }
        if (gatt == null) {
            returnError(
                    result,
                    platformMethod,
                    "invalid_state",
                    "BirdBox GATT is not connected."
            );
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
            returnError(result, platformMethodName(operation), "gatt_busy", "Another GATT operation is active.");
            return false;
        }
        pendingOperation = operation;
        pendingOperationResult = result;
        pendingCharacteristicUuid = null;
        final long token = ++operationToken;
        final int connection = connectionGeneration;
        final BluetoothGatt expectedGatt = gatt;
        emitDiagnostic("operation_started", operation, -1, null, null);
        // Preparation owns separate bond and per-stage GATT deadlines, never a generic 60s timer.
        if ("preparePairing".equals(operation) || "securityRecovery".equals(operation)) return true;
        pendingOperationTimeout = () -> {
            if (token != operationToken || connection != connectionGeneration || pendingOperationResult != result
                    || !operation.equals(pendingOperation)
                    || (!"connect".equals(operation) && gatt != expectedGatt)) return;
            if ("connect".equals(operation) && discoveryGatt == gatt && Boolean.TRUE.equals(discoveryApiAccepted))
                emitDiagnostic("gatt_service_discovery_timeout", operation, -1, null, "callback_missing");
            failPending("ble_gatt_operation_failed", "GATT operation timed out.");
            closeGatt(true, "operation_timeout", BluetoothGatt.GATT_FAILURE);
        };
        mainHandler.postDelayed(pendingOperationTimeout, "connect".equals(operation) ? 15_000L : 10_000L);
        return true;
    }

    private synchronized void succeedPending(@Nullable Object value) {
        final String completedOperation = pendingOperation;
        if ("write".equals(completedOperation)) {
            cancelSecurityWriteCallbackGuard();
            securityWriteAttemptContext.cancelActive();
        }
        emitDiagnostic("operation_succeeded", completedOperation, -1, null, "success");
        cancelPendingOperationTimeout();
        final MethodChannel.Result result = pendingOperationResult;
        pendingOperationResult = null;
        pendingOperation = null;
        pendingNotificationEnabled = null;
        pendingCharacteristicUuid = null;
        if (result != null) mainHandler.post(() -> result.success(value));
    }

    private synchronized void failPending(String code, String message) {
        failPending(code, message, null);
    }

    private synchronized void failPendingIfActive(String code, String message) {
        if (pendingOperationResult != null) {
            failPending(code, message);
            return;
        }
        cancelPendingOperationTimeout();
        pendingOperation = null;
        pendingNotificationEnabled = null;
    }

    private synchronized void failPending(String code, String message, @Nullable Object details) {
        final String stableCode = stableErrorCode(code);
        final String failedOperation = pendingOperation;
        if ("write".equals(failedOperation)) {
            cancelSecurityWriteCallbackGuard();
            securityWriteAttemptContext.cancelActive();
        }
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
        final Map<String, Object> failureDetails = failureDetails(
                platformMethodName(failedOperation),
                stableCode,
                message,
                status,
                characteristicUuid,
                details
        );
        emitDiagnostic(
                "operation_failed",
                failedOperation,
                status,
                characteristicUuid,
                stableCode,
                stableCode,
                message
        );
        cancelPendingOperationTimeout();
        final MethodChannel.Result result = pendingOperationResult;
        pendingOperationResult = null;
        pendingOperation = null;
        pendingNotificationEnabled = null;
        pendingCharacteristicUuid = null;
        if (result != null) {
            mainHandler.post(() -> result.error(stableCode, message, failureDetails));
        }
    }

    private synchronized void cancelPendingOperationTimeout() {
        if (pendingOperationTimeout != null) mainHandler.removeCallbacks(pendingOperationTimeout);
        pendingOperationTimeout = null;
    }

    private final BluetoothGattCallback gattCallback = new BluetoothGattCallback() {
        @Override public void onConnectionStateChange(BluetoothGatt current, int status, int state) {
            mainHandler.post(() -> handleConnectionState(current, status, state));
        }
        @Override public void onServicesDiscovered(BluetoothGatt current, int status) {
            mainHandler.post(() -> handleServices(current, status));
        }
        @Override public void onMtuChanged(BluetoothGatt current, int mtu, int status) {
            final long token = operationToken;
            mainHandler.post(() -> {
                if (current != gatt || token != operationToken) return;
                if (preparing() && "mtu_before_services".equals(preparationStep)) {
                    if (status == BluetoothGatt.GATT_SUCCESS) currentMtu = Math.max(23, mtu);
                    emitDiagnostic("gatt_mtu_changed", pendingOperation, status, null, "before_services");
                    securityMtuResolvedBeforeDiscovery = true;
                    setPreparationStep("services");
                    discoverServices(current);
                } else if (preparing() && "mtu".equals(preparationStep)) {
                    // Failed negotiation retains the confirmed default ATT MTU; a missing
                    // callback instead terminates via this stage's deadline.
                    if (status == BluetoothGatt.GATT_SUCCESS) currentMtu = Math.max(23, mtu);
                    emitDiagnostic("gatt_mtu_changed", pendingOperation, status, null, "prepared");
                    notificationIndex = 0;
                    subscribePreparedNotifications();
                } else if ("requestMtu".equals(pendingOperation)) {
                    if (status == BluetoothGatt.GATT_SUCCESS) { currentMtu = mtu; succeedPending(mtu); }
                    else failGattStatus(status, "MTU negotiation failed.");
                }
            });
        }
        @Override public void onCharacteristicRead(BluetoothGatt current, BluetoothGattCharacteristic c, int status) {
            byte[] value = c.getValue();
            dispatchRead(current, c.getUuid(), value == null ? null : Arrays.copyOf(value, value.length), status);
        }
        @Override public void onCharacteristicRead(BluetoothGatt current, BluetoothGattCharacteristic c, byte[] value, int status) {
            dispatchRead(current, c.getUuid(), Arrays.copyOf(value, value.length), status);
        }
        @Override public void onCharacteristicWrite(BluetoothGatt current, BluetoothGattCharacteristic c, int status) {
            final UUID uuid = c.getUuid();
            final long token = operationToken;
            mainHandler.post(() -> {
                if (current != gatt || token != operationToken || !uuid.equals(pendingCharacteristicUuid)) return;
                if ("preflight".equals(pendingOperation)) {
                    emitDiagnostic("pairing_preflight_write_callback", "preflight", status, uuid,
                            status == BluetoothGatt.GATT_SUCCESS ? "success" : gattErrorCode(status));
                    if (status == BluetoothGatt.GATT_SUCCESS) succeedPending(null);
                    else failGattStatus(status, "GATT preflight write failed.", uuid);
                    return;
                }
                if (!"write".equals(pendingOperation)) return;
                final boolean sensitive = WIFI_CONFIG_UUID.equals(uuid) || PROVISIONING_COMMAND_UUID.equals(uuid);
                if (sensitive && !securityWriteAttemptContext.completeFromCallback(
                        connectionGeneration, gattGeneration, uuid, isGattSecurityFailure(status))) return;
                cancelSecurityWriteCallbackGuard();
                emitDiagnostic("gatt_characteristic_write", "write", status, uuid,
                        status == BluetoothGatt.GATT_SUCCESS ? "success" : gattErrorCode(status));
                emitDiagnostic(sensitive ? "security_write_callback_received" : "gatt_characteristic_write",
                        "write", status, uuid, status == BluetoothGatt.GATT_SUCCESS ? "success" : gattErrorCode(status));
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    if (sensitive && securityWriteStateMachine.encryptedRetryCount() > 0)
                        emitDiagnostic("security_write_retry_result", "write", status, uuid, "success");
                    succeedPending(null);
                } else if (sensitive && isGattSecurityFailure(status)) {
                    failProtectedWrite(status, uuid);
                } else failGattStatus(status, "GATT write failed.", uuid);
            });
        }
        @Override public void onDescriptorWrite(BluetoothGatt current, BluetoothGattDescriptor d, int status) {
            final UUID uuid = d.getCharacteristic().getUuid(), descriptorUuid = d.getUuid();
            final long token = operationToken;
            mainHandler.post(() -> {
                if (current != gatt || token != operationToken || !CLIENT_CONFIGURATION_UUID.equals(descriptorUuid)
                        || !uuid.equals(pendingCharacteristicUuid)) return;
                emitDiagnostic("gatt_notification_descriptor_write", pendingOperation, status, uuid,
                        status == BluetoothGatt.GATT_SUCCESS ? "success" : "failed");
                if (preparing() && preparationStep != null && preparationStep.startsWith("notification_")) {
                    if (status != BluetoothGatt.GATT_SUCCESS) { failNativePreparation("ble_gatt_recovery_failed", status); return; }
                    if (!enabledNotifications.contains(uuid)) enabledNotifications.add(uuid);
                    notificationIndex++;
                    subscribePreparedNotifications();
                } else if ("descriptor".equals(pendingOperation)) {
                    if (status == BluetoothGatt.GATT_SUCCESS) {
                        if (Boolean.TRUE.equals(pendingNotificationEnabled)) {
                            if (!enabledNotifications.contains(uuid)) enabledNotifications.add(uuid);
                        } else enabledNotifications.remove(uuid);
                        succeedPending(null);
                    } else failGattStatus(status, "Notification descriptor write failed.", uuid);
                }
            });
        }
        @Override public void onCharacteristicChanged(BluetoothGatt current, BluetoothGattCharacteristic c) {
            byte[] value = c.getValue();
            dispatchNotification(current, c.getUuid(), value == null ? null : Arrays.copyOf(value, value.length));
        }
        @Override public void onCharacteristicChanged(BluetoothGatt current, BluetoothGattCharacteristic c, byte[] value) {
            dispatchNotification(current, c.getUuid(), Arrays.copyOf(value, value.length));
        }
    };

    private void dispatchRead(BluetoothGatt current, UUID uuid, byte[] value, int status) {
        final long token = operationToken;
        mainHandler.post(() -> {
            if (current == gatt && token == operationToken && "read".equals(pendingOperation) && uuid.equals(pendingCharacteristicUuid))
                completeRead(value, status);
        });
    }

    private void dispatchNotification(BluetoothGatt current, UUID uuid, byte[] value) {
        mainHandler.post(() -> { if (current == gatt && linkReady) emitNotification(uuid, value); });
    }

    private void handleConnectionState(BluetoothGatt current, int status, int state) {
        if (current == parkedResetGatt) {
            lastKnownConnectionState = state;
            if (state == BluetoothProfile.STATE_DISCONNECTED) {
                final boolean preConnect = "pre_connect_reset".equals(parkedRetireReason);
                emitDiagnostic(
                        preConnect ? "pre_connect_reset_disconnect_confirmed"
                                : "controlled_release_disconnect_confirmed",
                        pendingOperation,
                        status,
                        null,
                        preConnect ? "stale_gatt_disconnected" : "retired_gatt_disconnected"
                );
                lastReleasedConnectionGeneration = parkedRetireConnectionGeneration;
                lastReleasedGattInstanceId = parkedRetireGattGeneration;
                parkedResetDisconnected = true;
                securityReconnectNotBefore = android.os.SystemClock.elapsedRealtime()
                        + SECURITY_DISCONNECT_SETTLE_MS;
                releaseParkedResetGatt();
                // The live client has now observed its disconnect; historical clients
                // (deferred on legacy stacks) are safe to unregister before the next dial.
                releaseRetiringGatt();
                releaseHeldLegacyRegistrations();
                completeControlledRelease(true);
                dialAfterPreConnectReset();
            }
            return;
        }
        if (heldLegacyRegistrations.contains(current)) return;
        if (current == retiringGatt) {
            if (state == BluetoothProfile.STATE_DISCONNECTED && !retiringGattDisconnected) {
                emitDiagnostic("gatt_old_disconnect_confirmed", pendingOperation, status, null, "old_gatt_disconnected");
                if (Build.VERSION.SDK_INT <= 28 && activeSecurityRequestId != null) {
                    // This vendor stack can remove the new connection mapping
                    // when an older client is unregistered. Hold only disconnected
                    // registrations, bounded, until the BLE session is torn down.
                    retiringGattDisconnected = true;
                    if (retiringGattGuard != null) mainHandler.removeCallbacks(retiringGattGuard);
                    retiringGattGuard = null;
                    emitDiagnostic("gatt_old_client_close_deferred", pendingOperation, -1, null, "legacy_active_session");
                } else releaseRetiringGatt();
                // A client disconnect callback can precede release of the shared
                // ACL. Give the timed-out transaction a bounded drain interval.
                securityReconnectNotBefore = android.os.SystemClock.elapsedRealtime() + SECURITY_DISCONNECT_SETTLE_MS;
                if (preparing() && "old_gatt_disconnect".equals(preparationStep)) reconnectGattAfterSecurity();
            }
            return;
        }
        if (current != gatt) {
            if (state == BluetoothProfile.STATE_DISCONNECTED) {
                try { current.close(); } catch (RuntimeException ignored) { }
            }
            return;
        }
        emitDiagnostic("gatt_connection_state_changed", pendingOperation, status, null, connectionStateName(state));
        lastKnownConnectionState = state;
        if (status == BluetoothGatt.GATT_SUCCESS && state == BluetoothProfile.STATE_CONNECTED) {
            try {
                if (retiringGatt != null && retiringGattDisconnected)
                    emitDiagnostic("gatt_legacy_registration_retained", pendingOperation, -1, null, "until_session_teardown");
                discoveryGatt = current;
                discoveryApiAccepted = null;
                gattServicesDiscovered = false;
                discoveryStartedAt = 0;
                ignoredDiscoveryCallbacks = 0;
                securityMtuResolvedBeforeDiscovery = false;
                current.requestConnectionPriority(BluetoothGatt.CONNECTION_PRIORITY_HIGH);
                if (preparing() && Build.VERSION.SDK_INT <= 28) {
                    // Legacy bonded reconnects may auto-discover the peer cache.
                    // Serialize our discovery behind a completed public ATT MTU
                    // operation rather than racing that discovery after a sleep.
                    setPreparationStep("mtu_before_services");
                    emitDiagnostic("gatt_mtu_barrier_started", pendingOperation, -1, null, "legacy_before_discovery");
                    boolean accepted = current.requestMtu(517);
                    emitDiagnostic("gatt_mtu_barrier_api_returned", pendingOperation, -1, null,
                            accepted ? "accepted" : "rejected_default_mtu");
                    if (!accepted) {
                        // MTU is optional. No callback is owed after API rejection;
                        // preserve MTU 23 and the bounded discovery deadline.
                        securityMtuResolvedBeforeDiscovery = true;
                        setPreparationStep("services");
                        discoverServices(current);
                    }
                    return;
                }
                if (preparing()) setPreparationStep("services");
                discoverServices(current);
            } catch (RuntimeException error) {
                if (preparing()) failNativePreparation(error instanceof SecurityException ? "bluetooth_permission_denied" : "ble_gatt_recovery_failed");
                else { failPending("ble_gatt_operation_failed", "Service discovery failed."); closeGatt(true, "service_discovery_failed", status); }
            }
        } else if (state == BluetoothProfile.STATE_DISCONNECTED || status != BluetoothGatt.GATT_SUCCESS) {
            emitDiagnostic("gatt_disconnected", pendingOperation, status, null, "link_lost");
            if (preparing()) {
                // The first connect attempt right after a fresh bond can fail transiently
                // (status 133 or a missing callback on any stack generation). Retry once,
                // in step; the second failure terminates as before.
                if ("gatt_connect".equals(preparationStep)
                        && securityConnectRetryCount < SECURITY_CONNECT_RETRY_MAX) {
                    retrySecurityConnect(status);
                    return;
                }
                if (pairingCoordinator.waitingForBond()) {
                    // System bond can outlive the old ordinary GATT. Keep the device and its
                    // bond deadline; its successful broadcast will build a fresh connection.
                    closeGattForSecurity(current);
                } else failNativePreparation("ble_gatt_recovery_failed", status);
            } else if ("write".equals(pendingOperation) && isGattSecurityFailure(status)) {
                failProtectedWrite(status, pendingCharacteristicUuid);
            } else {
                failPendingIfActive("ble_gatt_operation_failed", "GATT disconnected.");
                closeGatt(true, disconnectRequested ? "requested" : "link_lost", status);
            }
        }
    }

    private boolean validService(BluetoothGattService service) {
        if (service == null) return false;
        for (UUID uuid : REQUIRED_CHARACTERISTICS) if (service.getCharacteristic(uuid) == null) return false;
        if ((service.getCharacteristic(DEVICE_INFO_UUID).getProperties() & BluetoothGattCharacteristic.PROPERTY_READ) == 0) return false;
        for (UUID uuid : Arrays.asList(WIFI_CONFIG_UUID, PROVISIONING_COMMAND_UUID))
            if ((service.getCharacteristic(uuid).getProperties() & BluetoothGattCharacteristic.PROPERTY_WRITE) == 0) return false;
        for (UUID uuid : Arrays.asList(NETWORK_STATUS_UUID, SCAN_RESULTS_UUID)) {
            BluetoothGattCharacteristic c = service.getCharacteristic(uuid);
            if ((c.getProperties() & (BluetoothGattCharacteristic.PROPERTY_NOTIFY | BluetoothGattCharacteristic.PROPERTY_INDICATE)) == 0
                    || c.getDescriptor(CLIENT_CONFIGURATION_UUID) == null) return false;
        }
        return true;
    }

    private void discoverServices(BluetoothGatt current) {
        discoveryStartedAt = SystemClock.uptimeMillis();
        emitDiagnostic("gatt_service_discovery_api_invoked", pendingOperation, -1, null, "invoked");
        try {
            discoveryApiAccepted = current.discoverServices();
            emitDiagnostic("gatt_service_discovery_api_returned", pendingOperation, -1, null,
                    discoveryApiAccepted ? "accepted" : "rejected");
            if (!discoveryApiAccepted) failServiceDiscovery("ble_gatt_recovery_failed", "api_rejected");
        } catch (RuntimeException error) {
            emitDiagnostic("gatt_service_discovery_api_exception", pendingOperation, -1, null,
                    error instanceof SecurityException ? "permission_denied" : "runtime_exception");
            failServiceDiscovery(error instanceof SecurityException ? "bluetooth_permission_denied" : "ble_gatt_recovery_failed", "api_exception");
        }
    }

    private void failServiceDiscovery(String code, String reason) {
        if (preparing()) failNativePreparation(code);
        else {
            failPending("bluetooth_permission_denied".equals(code) ? code : "ble_gatt_operation_failed", "Service discovery failed: " + reason);
            closeGatt(true, "service_discovery_failed", BluetoothGatt.GATT_FAILURE);
        }
    }

    private void handleServices(BluetoothGatt current, int status) {
        String ignored = current != gatt ? "stale_gatt"
                : !(preparing() || "connect".equals(pendingOperation)) ? "inactive_operation"
                : preparing() && !"services".equals(preparationStep) ? "wrong_step" : null;
        if (ignored != null) {
            if (ignoredDiscoveryCallbacks++ < 8) {
                final Map<String, Object> callback = new LinkedHashMap<>();
                callback.put("callbackGattIdentity", System.identityHashCode(current));
                callback.put("callbackGattIsCurrent", current == gatt);
                emitDiagnostic("gatt_service_discovery_callback_ignored", pendingOperation, status, null, ignored,
                        null, null, callback);
            }
            return;
        }
        emitDiagnostic("gatt_services_discovered", pendingOperation, status, null, status == 0 ? "success" : "failed");
        if (status != BluetoothGatt.GATT_SUCCESS || !validService(current.getService(SERVICE_UUID))) {
            emitDiagnostic("gatt_service_validation_failed", pendingOperation, status, null,
                    status != BluetoothGatt.GATT_SUCCESS ? "callback_error" : "service_properties_invalid");
            if (preparing()) failNativePreparation("ble_gatt_recovery_failed", status);
            else { failPending("invalid_request", "BirdBox service or characteristic properties are invalid."); closeGatt(true, "service_invalid", status); }
            return;
        }
        gattServicesDiscovered = true;
        if (preparing()) {
            securityWriteStateMachine.onGattRecovered(gattGeneration);
            if (securityMtuResolvedBeforeDiscovery) {
                notificationIndex = 0;
                subscribePreparedNotifications();
                return;
            }
            setPreparationStep("mtu");
            try {
                if (!current.requestMtu(517)) { notificationIndex = 0; subscribePreparedNotifications(); }
            } catch (RuntimeException error) { failNativePreparation(error instanceof SecurityException ? "bluetooth_permission_denied" : "ble_gatt_recovery_failed"); }
        } else {
            linkReady = true;
            securityWriteStateMachine.markGattReady(gattGeneration);
            succeedPending(connectionGeneration);
        }
    }

    private void completeRead(@Nullable byte[] value, int status) {
        if (status == BluetoothGatt.GATT_SUCCESS && value != null) succeedPending(value);
        else failGattStatus(status, "GATT read failed.", null);
    }

    private void failGattStatus(int status, @NonNull String message) {
        failGattStatus(status, message, null);
    }

    private void failGattStatus(int status, @NonNull String message, @Nullable UUID characteristicUuid) {
        if (isGattSecurityFailure(status)) {
            securityFailureObserved = true;
            securityGattStatusObserved = true;
        }
        failPending(gattErrorCode(status), message, gattFailureDetails(status, characteristicUuid));
    }

    @NonNull
    private Map<String, Object> gattFailureDetails(int status, @Nullable UUID characteristicUuid) {
        final UUID effectiveCharacteristicUuid = characteristicUuid != null
                ? characteristicUuid
                : securityWriteAttemptContext.characteristicUuid();
        final Map<String, Object> details = new LinkedHashMap<>();
        details.put("gattStatus", status);
        details.put("platformExceptionCode", gattErrorCode(status));
        details.put("bondState", bondStateName());
        details.put(
                "characteristicUuid",
                effectiveCharacteristicUuid == null
                        ? "none"
                        : effectiveCharacteristicUuid.toString().toLowerCase(Locale.ROOT)
        );
        details.put("operationName", diagnosticOperationName(pendingOperation));
        return details;
    }

    private void returnError(
            @NonNull MethodChannel.Result result,
            @NonNull String platformMethod,
            @NonNull String code,
            @Nullable String message) {
        returnError(result, platformMethod, code, message, null);
    }

    private void returnError(
            @NonNull MethodChannel.Result result,
            @NonNull String platformMethod,
            @NonNull String code,
            @Nullable String message,
            @Nullable Object additionalDetails) {
        final String stableCode = stableErrorCode(code);
        final String safeMessage = safeDiagnosticMessage(message);
        final Map<String, Object> details = failureDetails(
                platformMethod,
                stableCode,
                safeMessage,
                -1,
                null,
                additionalDetails
        );
        emitDiagnostic(
                "platform_error",
                platformMethod,
                -1,
                null,
                stableCode,
                stableCode,
                safeMessage
        );
        result.error(stableCode, safeMessage, details);
    }

    @NonNull
    private static String stableErrorCode(@NonNull String code) {
        return switch (code) {
            case "gatt_operation_failed" -> "ble_gatt_operation_failed";

            default -> code;
        };
    }

    @NonNull
    private Map<String, Object> failureDetails(
            @NonNull String platformMethod,
            @NonNull String code,
            @Nullable String message,
            int gattStatus,
            @Nullable UUID characteristicUuid,
            @Nullable Object additionalDetails) {
        final Map<String, Object> details = new LinkedHashMap<>();
        if (additionalDetails instanceof Map) {
            for (Map.Entry<?, ?> entry : ((Map<?, ?>) additionalDetails).entrySet()) {
                if (entry.getKey() instanceof String && entry.getValue() != null) {
                    details.put((String) entry.getKey(), entry.getValue());
                }
            }
        }
        details.put("platformExceptionCode", code);
        details.put("platformMethod", platformMethod);
        if (!details.containsKey("operationName")) {
            details.put("operationName", diagnosticOperationName(platformMethod));
        }
        details.put("pendingOperation", diagnosticOperationName(pendingOperation));
        details.put("nativeState", nativeStateName());
        details.put("securityPhase", securityPhaseName());
        details.put("bondState", bondStateName());
        details.put("actualBondState", bondStateName());
        details.put("gattPresent", gatt != null);
        details.put("linkReady", linkReady);
        details.put("scanning", scanning);
        details.put("connectionGeneration", connectionGeneration);
        details.put("gattInstanceId", gattGeneration);
        details.put("gattGeneration", gattGeneration);
        details.put(
                "conditionalBondFallbackAttempted",
                securityWriteStateMachine.conditionalBondFallbackAttempted()
        );
        details.put("bondInitiationSource", bondInitiationSource);
        details.put("securityGattStatusObserved", securityGattStatusObserved);
        if (securityWriteAttemptContext.trigger()
                != BirdBoxSecurityWriteAttemptContext.Trigger.NONE) {
            details.put(
                    "securityTrigger",
                    securityWriteAttemptContext.trigger().name().toLowerCase(Locale.ROOT)
            );
            details.put(
                    "fallbackTrigger",
                    securityWriteAttemptContext.trigger().name().toLowerCase(Locale.ROOT)
            );
        }
        addSecurityWriteAttemptFacts(details);
        if (activeTraceId != null && !activeTraceId.isEmpty()) details.put("traceId", activeTraceId);
        if (connectedDeviceAddressHash != null) details.put("deviceAddressHash", connectedDeviceAddressHash);
        if (gattStatus >= 0) details.put("gattStatus", gattStatus);
        if (characteristicUuid != null) {
            details.put("characteristicUuid", characteristicUuid.toString().toLowerCase(Locale.ROOT));
        }
        final String safeMessage = safeDiagnosticMessage(message);
        if (!safeMessage.isEmpty()) details.put("sanitizedMessage", safeMessage);
        return details;
    }

    @NonNull
    private String nativeStateName() {
        if (disposed) return "disposed";
        if (gatt == null) return scanning ? "scanning" : "idle";
        if (linkReady) return "link_ready";
        if ("connect".equals(pendingOperation)) return "connecting";
        if ("securityRecovery".equals(pendingOperation)) return "security_recovery";
        return "gatt_present_not_ready";
    }

    @NonNull
    private String securityPhaseName() {
        return securityWriteStateMachine.phase().name().toLowerCase(Locale.ROOT);
    }

    @NonNull
    private static String safeDiagnosticMessage(@Nullable String message) {
        if (message == null) return "";
        String safe = message.replaceAll("[\\r\\n\\t]+", " ").trim();
        safe = safe.replaceAll(
                "(?i)(?:[0-9a-f]{2}:){5}[0-9a-f]{2}",
                "[REDACTED_MAC]"
        );
        safe = safe.replaceAll(
                "(?i)(password|passphrase|token|secret|authorization|pairing[_ -]?code)\\s*[:=]\\s*[^,;\\s]+",
                "$1=[REDACTED]"
        );
        safe = safe.replaceAll("(?i)dpp:[^\\s]+", "[REDACTED_DPP_URI]");
        return safe.length() <= 240 ? safe : safe.substring(0, 240);
    }

    @NonNull
    private String bondStateName() {
        final BluetoothDevice device = connectedDevice;
        if (device == null) return "none";
        try {
            return switch (platform.bondState(device)) {
                case BluetoothDevice.BOND_BONDED -> "bonded";
                case BluetoothDevice.BOND_BONDING -> "bonding";
                default -> "not_bonded";
            };
        } catch (RuntimeException error) {
            return error instanceof SecurityException ? "permission_denied" : "unknown";
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
        closeGattForSecurity(callbackGatt, false);
    }

    private void closeGattForSecurity(@NonNull BluetoothGatt callbackGatt, boolean awaitDisconnect) {
        if (callbackGatt != gatt) return;
        if (retiringGatt != null && retiringGattDisconnected) {
            if (heldLegacyRegistrations.size() >= MAX_HELD_LEGACY_REGISTRATIONS) {
                emitDiagnostic("gatt_legacy_registration_limit", pendingOperation, -1, null, "session_reconnect_required");
                if (preparing()) failNativePreparation("ble_gatt_recovery_failed");
                else closeGatt(true, "legacy_registration_limit", BluetoothGatt.GATT_FAILURE);
                return;
            }
            heldLegacyRegistrations.add(retiringGatt);
            retiringGatt = null;
            retiringGattDisconnected = false;
        }
        gatt = null;
        linkReady = false;
        // Closing only the client registration can leave a timed-out ATT
        // transaction on the shared ACL. Disconnect before creating a new GATT.
        // Invalidate ownership first so old callbacks cannot advance recovery.
        emitDiagnostic("gatt_disconnect_requested", pendingOperation, -1, null, "security_old_gatt");
        if (awaitDisconnect) {
            retiringGatt = callbackGatt;
            retiringGattDisconnected = false;
            retiringGattGuard = () -> {
                if (retiringGatt != callbackGatt) return;
                emitDiagnostic("gatt_old_disconnect_timeout", pendingOperation, -1, null, "disconnect_callback_missing");
                releaseRetiringGatt();
                if (preparing()) failNativePreparation("ble_gatt_recovery_failed");
                else closeGatt(true, "old_gatt_disconnect_timeout", BluetoothGatt.GATT_FAILURE);
            };
            mainHandler.postDelayed(retiringGattGuard, SECURITY_DISCONNECT_GUARD_MS);
        }
        try {
            callbackGatt.disconnect();
            if (awaitDisconnect) return;
        } catch (RuntimeException ignored) {
            // Still close if a vendor stack rejects the disconnect call.
            if (awaitDisconnect) { releaseRetiringGatt(); return; }
        }
        try {
            callbackGatt.close();
        } catch (RuntimeException ignored) {
            // Vendor stack may already have closed the client.
        }
    }

    private void releaseRetiringGatt() {
        if (retiringGattGuard != null) mainHandler.removeCallbacks(retiringGattGuard);
        retiringGattGuard = null;
        final BluetoothGatt retired = retiringGatt;
        retiringGatt = null;
        retiringGattDisconnected = false;
        if (retired != null) {
            try { retired.close(); } catch (RuntimeException ignored) { }
        }
    }

    private void releaseHeldLegacyRegistrations() {
        for (BluetoothGatt held : heldLegacyRegistrations) {
            try { held.close(); } catch (RuntimeException ignored) { }
        }
        heldLegacyRegistrations.clear();
    }

    static boolean isGattSecurityFailure(int status) {
        return status == BluetoothGatt.GATT_INSUFFICIENT_AUTHENTICATION
                || status == GATT_INSUFFICIENT_AUTHORIZATION
                || status == BluetoothGatt.GATT_INSUFFICIENT_ENCRYPTION
                || status == GATT_INSUFFICIENT_ENCRYPTION_KEY_SIZE;
    }

    @NonNull
    static String gattErrorCode(int status) {
        return isGattSecurityFailure(status)
                ? "ble_link_not_encrypted"
                : "ble_gatt_operation_failed";
    }

    private void emitNotification(UUID characteristicUuid, @Nullable byte[] value) {
        if (value == null) return;
        final Map<String, Object> event = new LinkedHashMap<>();
        event.put("characteristicUuid", characteristicUuid.toString().toLowerCase(Locale.ROOT));
        event.put("value", Arrays.copyOf(value, value.length));
        event.put("connectionGeneration", connectionGeneration);
        event.put("gattGeneration", gattGeneration);
        emitSuccess(notificationSink, event);
    }

    private synchronized void closeGatt(boolean emitDisconnect, @NonNull String reason, int status) {
        final boolean hadNativeSession = gatt != null
                || connectedDevice != null
                || linkReady
                || activeSecurityRequestId != null
                || securityWriteStateMachine.isActive()
                || bondStateReceiver != null;
        emitDiagnostic("teardown_started", "disconnect", status, null, reason);
        failPendingIfActive(
                "gatt_operation_failed",
                "The active GATT operation was cancelled while tearing down the BLE session."
        );
        stopScan();
        if (securityReconnectGuard != null) mainHandler.removeCallbacks(securityReconnectGuard);
        securityReconnectGuard = null;
        securityMtuResolvedBeforeDiscovery = false;
        securityReconnectNotBefore = 0;
        final BluetoothGatt current = gatt;
        final int retireConnectionGeneration = connectionGeneration;
        final int retireGattGeneration = gattGeneration;
        gatt = null;
        linkReady = false;
        securedGattGeneration = -1;
        enabledNotifications.clear();
        if (isRetireBarrierReason(reason) && current != null
                && lastKnownConnectionState != BluetoothProfile.STATE_DISCONNECTED) {
            // Park instead of close: the vendor stack keeps the ACL until the client
            // observes STATE_DISCONNECTED. Dialing a new client over an undrained ACL
            // produced the silent 15 s connect of MIS-AL00 155233. The barrier applies
            // to every retire reason (pre_connect_reset, controlled_reconnect, requested).
            releaseParkedResetGatt();
            parkedResetGatt = current;
            parkedRetireReason = reason;
            parkedRetireConnectionGeneration = retireConnectionGeneration;
            parkedRetireGattGeneration = retireGattGeneration;
            securityReconnectNotBefore = android.os.SystemClock.elapsedRealtime()
                    + SECURITY_DISCONNECT_SETTLE_MS;
            try {
                current.disconnect();
            } catch (RuntimeException ignored) {
                // A rejected disconnect leaves the retire guard to time out.
            }
            armParkedRetireGuard();
        } else if (current != null) {
            if (isRetireBarrierReason(reason)) {
                // Fast path: the link was already gone, so no disconnect callback is
                // owed; record the release anchor for prepareControlledReconnect idempotency.
                lastReleasedConnectionGeneration = retireConnectionGeneration;
                lastReleasedGattInstanceId = retireGattGeneration;
            }
            try {
                current.disconnect();
            } catch (RuntimeException ignored) {
                // Closing must still continue after permission revocation.
            }
            try {
                current.close();
            } catch (RuntimeException ignored) {
                // Vendor stacks may already have torn down the client.
            }
        }
        if (!isRetireBarrierReason(reason) || parkedResetGatt == null) {
            // Disconnect the live client before unregistering historical clients:
            // legacy stacks can lose the live address mapping during unregister.
            releaseRetiringGatt();
            releaseHeldLegacyRegistrations();
        }
        if (pendingPreConnectResult != null && !"pre_connect_reset".equals(reason)) {
            // A full teardown supersedes any pending pre-connect reset; its connect
            // caller must not hang past this point.
            final MethodChannel.Result parked = pendingPreConnectResult;
            pendingPreConnectCall = null;
            pendingPreConnectResult = null;
            releaseParkedResetGatt();
            returnError(parked, "connect", "gatt_operation_failed",
                    "The pending connect was cancelled by the disconnect teardown.");
        }
        if (pendingControlledReleaseResult != null && !"controlled_reconnect".equals(reason)) {
            // A newer teardown supersedes a pending controlled release.
            final MethodChannel.Result release = pendingControlledReleaseResult;
            pendingControlledReleaseResult = null;
            returnError(release, "prepareControlledReconnect", "gatt_operation_failed",
                    "The controlled release was superseded by a new teardown.");
        }
        if (emitDisconnect && hadNativeSession) {
            emitDisconnect(reason, status, !disconnectRequested);
        }
        finishSecuritySession(reason);
        connectedDevice = null;
        connectedDeviceAddressHash = null;
        previousBondState = null;
        pendingNotificationEnabled = null;
        securityFailureObserved = false;
        securityGattStatusObserved = false;
        securityBondingObserved = false;
        systemPairingInteraction = false;
        gattRebuilt = false;
        currentMtu = 23;
        gattGeneration = 0;
        disconnectRequested = false;
        securityConnectRetryCount = 0;
        emitDiagnostic("teardown_completed", "disconnect", status, null, reason);
    }

    private void emitDisconnect(@NonNull String reason, int status, boolean unexpected) {
        final Map<String, Object> event = new LinkedHashMap<>();
        event.put("reason", reason);
        event.put("gattStatus", status);
        event.put("unexpected", unexpected);
        event.put("connectionGeneration", connectionGeneration);
        event.put("gattInstanceId", gattGeneration);
        emitSuccess(disconnectSink, event);
        emitDiagnostic("disconnected", "disconnect", status, null, reason);
    }

    private void emitDiagnostic(
            @NonNull String eventType,
            @Nullable String operationName,
            int gattStatus,
            @Nullable UUID characteristicUuid,
            @Nullable String resultCode) {
        emitDiagnostic(
                eventType,
                operationName,
                gattStatus,
                characteristicUuid,
                resultCode,
                null,
                null
        );
    }

    private void emitDiagnostic(
            @NonNull String eventType,
            @Nullable String operationName,
            int gattStatus,
            @Nullable UUID characteristicUuid,
            @Nullable String resultCode,
            @Nullable String errorCode,
            @Nullable String diagnosticMessage) {
        emitDiagnostic(eventType, operationName, gattStatus, characteristicUuid, resultCode, errorCode, diagnosticMessage, null);
    }

    private void emitDiagnostic(
            @NonNull String eventType, @Nullable String operationName, int gattStatus,
            @Nullable UUID characteristicUuid, @Nullable String resultCode,
            @Nullable String errorCode, @Nullable String diagnosticMessage,
            @Nullable Map<String, Object> extra) {
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
        event.put("buildDirty", BuildConfig.BUILD_DIRTY);
        event.put("buildId", BuildConfig.BUILD_ID);
        event.put("sourceFingerprint", BuildConfig.SOURCE_FINGERPRINT);
        event.put("apkSha256", apkSha256());
        if (connectedDeviceAddressHash != null) {
            event.put("deviceAddressHash", connectedDeviceAddressHash);
        }
        if (gattGeneration > 0) event.put("gattInstanceId", gattGeneration);
        if (gattGeneration > 0) event.put("gattGeneration", gattGeneration);
        event.put("connectionGeneration", connectionGeneration);
        if (operationName != null) {
            event.put("operationName", diagnosticOperationName(operationName));
            event.put("platformMethod", platformMethodName(operationName));
        }
        event.put("pendingOperation", diagnosticOperationName(pendingOperation));
        event.put("nativeState", nativeStateName());
        event.put("securityPhase", securityPhaseName());
        event.put("gattPresent", gatt != null);
        event.put("linkReady", linkReady);
        event.put("scanning", scanning);
        if (gattStatus >= 0) event.put("gattStatus", gattStatus);
        event.put("bondState", bondStateName());
        event.put("actualBondState", bondStateName());
        if (previousBondState != null) event.put("previousBondState", previousBondState);
        event.put("systemPairingInteraction", systemPairingInteraction);
        event.put("gattRebuilt", gattRebuilt);
        event.put("retryCount", securityWriteStateMachine.encryptedRetryCount());
        event.put(
                "conditionalBondFallbackAttempted",
                securityWriteStateMachine.conditionalBondFallbackAttempted()
        );
        event.put("bondInitiationSource", bondInitiationSource);
        event.put("systemBondAttempted", systemBondAttempted);
        event.put("securityWriteAttemptCount", securityWriteStateMachine.writeAttemptCount());
        if (preparationStep != null) event.put("preparationStep", preparationStep);
        if (preparationStep != null) event.put("preparationElapsedMs", Math.max(0, SystemClock.uptimeMillis() - preparationStepStartedAt));
        if (discoveryGatt == gatt && discoveryGatt != null) {
            if (discoveryApiAccepted != null) event.put("serviceDiscoveryApiAccepted", discoveryApiAccepted);
            if (discoveryStartedAt > 0) event.put("serviceDiscoveryElapsedMs", Math.max(0, SystemClock.uptimeMillis() - discoveryStartedAt));
        }
        if (preparationFailurePhase != null) event.put("failurePhase", preparationFailurePhase);
        event.put("thread", Thread.currentThread().getName());
        event.put("callSource", operationName == null ? "native_callback" : platformMethodName(operationName));
        if (eventType.startsWith("teardown") || "gatt_disconnect_requested".equals(eventType)) event.put("teardownReason", resultCode);
        addLocationFacts(event);
        event.put("securityGattStatusObserved", securityGattStatusObserved);
        addSecurityWriteAttemptFacts(event);
        if (activeSecurityRequestId != null) {
            event.put("requestId", activeSecurityRequestId);
        }
        if (activeSecurityCommandType != null) {
            event.put("commandType", activeSecurityCommandType);
        }
        event.put("mtu", currentMtu);
        if ("security_write_result".equals(eventType)) event.put("securityWriteResult", resultCode);
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
        if (securityWriteAttemptContext.trigger()
                != BirdBoxSecurityWriteAttemptContext.Trigger.NONE) {
            event.put(
                    "securityTrigger",
                    securityWriteAttemptContext.trigger().name().toLowerCase(Locale.ROOT)
            );
            event.put(
                    "fallbackTrigger",
                    securityWriteAttemptContext.trigger().name().toLowerCase(Locale.ROOT)
            );
        } else if ("write".equals(operationName)
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
        if (errorCode != null) event.put("errorCode", errorCode);
        final String safeMessage = safeDiagnosticMessage(diagnosticMessage);
        if (!safeMessage.isEmpty()) event.put("sanitizedMessage", safeMessage);
        addPackageMetadata(event);
        if (extra != null) event.putAll(extra);
        emitSuccess(diagnosticSink, event);
    }

    /** Adds the secret-safe, request-scoped facts to an event or platform exception map. */
    private void addSecurityWriteAttemptFacts(@NonNull Map<String, Object> target) {
        if (securityWriteAttemptContext.attemptId() == null) return;
        target.put("attemptId", securityWriteAttemptContext.attemptId());
        target.put("writeApiAccepted", securityWriteAttemptContext.apiAccepted());
        target.put("writeCallbackReceived", securityWriteAttemptContext.callbackReceived());
        target.put(
                "securityWriteElapsedMs",
                securityWriteAttemptContext.elapsedMs(SystemClock.uptimeMillis())
        );
        if (securityWriteAttemptContext.bondStateAtTrigger() != null) {
            target.put("bondStateAtTrigger", securityWriteAttemptContext.bondStateAtTrigger());
        }
        target.put("createBondInvoked", securityWriteAttemptContext.createBondInvoked());
        target.put("createBondCallCount", securityWriteAttemptContext.createBondCallCount());
        target.put("commandAttemptCount", securityWriteAttemptContext.commandAttemptCount());
        target.put("attWriteCallCount", securityWriteAttemptContext.attWriteCallCount());
        target.put("writeFragmentIndex", securityWriteAttemptContext.writeFragmentIndex());
        target.put("bondElapsedMs", securityWriteAttemptContext.bondElapsedMs(SystemClock.uptimeMillis()));
        if (securityWriteAttemptContext.createBondReturned() != null) {
            target.put("createBondReturned", securityWriteAttemptContext.createBondReturned());
        }
        if (securityWriteAttemptContext.createBondStateBefore() != null) {
            target.put(
                    "createBondStateBefore",
                    securityWriteAttemptContext.createBondStateBefore()
            );
        }
        if (securityWriteAttemptContext.createBondStateAfter() != null) {
            target.put(
                    "createBondStateAfter",
                    securityWriteAttemptContext.createBondStateAfter()
            );
        }
        if (securityWriteAttemptContext.createBondException() != null) {
            target.put("createBondException", securityWriteAttemptContext.createBondException());
        }
        if (securityWriteAttemptContext.stateBefore() != null) {
            target.put("stateBefore", securityWriteAttemptContext.stateBefore());
        }
        if (securityWriteAttemptContext.stateAfter() != null) {
            target.put("stateAfter", securityWriteAttemptContext.stateAfter());
        }
        if (securityWriteAttemptContext.terminalOutcome() != null) {
            target.put("terminalOutcome", securityWriteAttemptContext.terminalOutcome());
        }
        if (securityWriteAttemptContext.cleanupOutcome() != null) {
            target.put("cleanupOutcome", securityWriteAttemptContext.cleanupOutcome());
        }
    }

    private void addPackageMetadata(@NonNull Map<String, Object> event) {
        event.put("packageId", applicationContext.getPackageName());
        event.put("buildFlavor", BuildConfig.FLAVOR);
        event.put("buildType", BuildConfig.BUILD_TYPE);
        try {
            final PackageInfo packageInfo = applicationContext.getPackageManager().getPackageInfo(applicationContext.getPackageName(), 0);
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

    @NonNull
    private static String platformMethodName(@Nullable String operationName) {
        if (operationName == null) return "none";
        return switch (operationName) {
            case "read" -> "readCharacteristic";
            case "descriptor" -> "setNotify";
            case "write" -> "writeWithResponse";
            case "securityRecovery" -> "awaitSecurityReady";
            case "scan" -> "startScan";
            case "preflight" -> "writePairingPreflight";
            default -> operationName;
        };
    }

    private void emitSecurityPhase(@Nullable String reason) {
        if (securityWriteAttemptContext.attemptId() != null) {
            final String previous = securityWriteAttemptContext.stateAfter();
            securityWriteAttemptContext.recordStateTransition(
                    previous == null ? "none" : previous,
                    securityPhaseName()
            );
        }
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
        dispose("bridge_disposed");
    }

    void dispose(String reason) {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            mainHandler.post(() -> dispose(reason));
            return;
        }
        if (disposed) return;
        emitDiagnostic("ble_engine_session_ended", pendingOperation, -1, null, reason);
        final Map<String, Object> lifecycle = new LinkedHashMap<>();
        lifecycle.put("teardownReason", reason);
        lifecycle.put("preparationStep", preparationStep == null ? "system_bond" : preparationStep);
        failPending("ble_session_ended", "Bluetooth session ended: " + reason, lifecycle);
        disposed = true;
        final MethodChannel.Result release = pendingControlledReleaseResult;
        pendingControlledReleaseResult = null;
        if (release != null) {
            returnError(release, "prepareControlledReconnect", "ble_session_ended",
                    "The controlled release was ended by the session teardown.");
        }
        closeGatt(true, reason, BluetoothGatt.GATT_SUCCESS);
        releaseParkedResetGatt();
        pendingPreConnectCall = null;
        pendingPreConnectResult = null;
        if (pendingPermissionResult != null) {
            returnError(
                    pendingPermissionResult,
                    "ensurePermissions",
                    "ble_session_ended",
                    "BLE bridge was disposed."
            );
            pendingPermissionResult = null;
        }
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
        activity = null;
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
