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
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.ParcelUuid;
import android.util.SparseArray;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

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
    private static final int PERMISSION_REQUEST_CODE = 6204;
    // ATT error 0x0c is not exposed as a BluetoothGatt constant on all SDKs.
    static final int GATT_INSUFFICIENT_ENCRYPTION_KEY_SIZE = 0x0c;

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
    private final BluetoothAdapter adapter;
    private final MethodChannel methodChannel;
    private final EventChannel scanEventChannel;
    private final EventChannel notificationEventChannel;
    private final EventChannel disconnectEventChannel;

    @Nullable private EventChannel.EventSink scanSink;
    @Nullable private EventChannel.EventSink notificationSink;
    @Nullable private EventChannel.EventSink disconnectSink;
    @Nullable private BluetoothLeScanner scanner;
    @Nullable private volatile BluetoothGatt gatt;
    @Nullable private volatile BluetoothDevice connectedDevice;
    @Nullable private MethodChannel.Result pendingPermissionResult;
    @Nullable private MethodChannel.Result pendingOperationResult;
    @Nullable private volatile String pendingOperation;
    @Nullable private Runnable pendingOperationTimeout;
    @Nullable private Runnable scanTimeout;
    @Nullable private String activeScanSessionId;
    @Nullable private BroadcastReceiver bondStateReceiver;
    private boolean bondReconnectRequired;
    private boolean scanning;
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
        methodChannel.setMethodCallHandler(this);
        scanEventChannel.setStreamHandler(streamHandler(sink -> scanSink = sink, () -> scanSink = null));
        notificationEventChannel.setStreamHandler(streamHandler(sink -> notificationSink = sink, () -> notificationSink = null));
        disconnectEventChannel.setStreamHandler(streamHandler(sink -> disconnectSink = sink, () -> disconnectSink = null));
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
            case "ensureBonded":
                ensureBonded(result);
                break;
            case "isLinkEncrypted":
                // Android does not expose a trustworthy per-link encryption bit. Bond
                // state is only a preflight signal; characteristic permissions and
                // GATT security failures remain authoritative at both endpoints.
                result.success(connectedDevice != null
                        && connectedDevice.getBondState() == BluetoothDevice.BOND_BONDED
                        && !securityFailureObserved);
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
        return environment;
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
            result.success(null);
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
            scanner.startScan(null, settings, scanCallback);
            scanning = true;
            scanTimeout = this::stopScan;
            mainHandler.postDelayed(scanTimeout, timeout);
            result.success(null);
        } catch (SecurityException error) {
            activeScanSessionId = null;
            scanner = null;
            result.error("bluetooth_permission_denied", "Bluetooth scan permission is missing.", null);
        } catch (RuntimeException error) {
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
        if (record == null) {
            emitScanObservation(sink, false, "missing_scan_record");
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
        if (!accepted) {
            emitScanObservation(sink, false, decisionReason);
            return;
        }

        final SparseArray<byte[]> manufacturerData = record.getManufacturerSpecificData();
        Integer companyIdentifier = null;
        byte[] manufacturerPayload = null;
        if (manufacturerData != null && manufacturerData.size() > 0) {
            final int index = manufacturerData.indexOfKey(0xFFFF) >= 0 ? manufacturerData.indexOfKey(0xFFFF) : 0;
            companyIdentifier = manufacturerData.keyAt(index);
            manufacturerPayload = manufacturerData.valueAt(index);
        }
        final Map<String, Object> event = new LinkedHashMap<>();
        event.put("eventType", "advertisement");
        event.put("scanSessionId", activeScanSessionId == null ? "native-unknown" : activeScanSessionId);
        event.put("accepted", true);
        event.put("decisionReason", decisionReason);
        event.put("deviceId", result.getDevice().getAddress());
        event.put("localName", localName);
        event.put("serviceUuids", serviceUuids);
        event.put("rssi", result.getRssi());
        event.put("companyIdentifier", companyIdentifier);
        event.put("manufacturerPayload", manufacturerPayload);
        emitSuccess(sink, event);
    }

    private void emitScanObservation(
            @NonNull EventChannel.EventSink sink,
            boolean accepted,
            @NonNull String decisionReason) {
        final Map<String, Object> event = new LinkedHashMap<>();
        event.put("eventType", "advertisement");
        event.put("scanSessionId", activeScanSessionId == null ? "native-unknown" : activeScanSessionId);
        event.put("accepted", accepted);
        event.put("decisionReason", decisionReason);
        emitSuccess(sink, event);
    }

    private void connect(MethodCall call, MethodChannel.Result result) {
        if (!requireBluetooth(result)) return;
        if (gatt != null) {
            result.error("invalid_state", "BirdBox GATT is already connected.", null);
            return;
        }
        if (!beginOperation("connect", result)) return;
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
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                gatt = connectedDevice.connectGatt(activity, false, gattCallback, BluetoothDevice.TRANSPORT_LE);
            } else {
                gatt = connectedDevice.connectGatt(activity, false, gattCallback);
            }
            if (gatt == null) failPending("gatt_operation_failed", "GATT connection could not start.");
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
        if ((WIFI_CONFIG_UUID.equals(characteristic.getUuid())
                || PROVISIONING_COMMAND_UUID.equals(characteristic.getUuid()))
                && (connectedDevice == null || connectedDevice.getBondState() != BluetoothDevice.BOND_BONDED)) {
            failPending(
                    "ble_link_not_encrypted",
                    "Sensitive GATT write requires an authenticated encrypted link.",
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
            if (!started) failPending("gatt_operation_failed", "GATT write was rejected.");
        } catch (SecurityException error) {
            failPending("bluetooth_permission_denied", "Bluetooth connect permission is missing.");
        }
    }

    /**
     * Establishes the Android Bluetooth bond required by both rc4 encrypted-write
     * characteristics.  The returned boolean tells Dart whether GATT had to be
     * reconnected and notification subscriptions therefore need restoring.
     */
    private void ensureBonded(MethodChannel.Result result) {
        if (!requireBluetooth(result)) return;
        final BluetoothDevice device = connectedDevice;
        if (device == null) {
            result.error("invalid_state", "BirdBox GATT is not connected.", null);
            return;
        }
        if (!beginOperation("bond", result)) return;
        try {
            if (device.getBondState() == BluetoothDevice.BOND_BONDED) {
                if (securityFailureObserved || gatt == null || !linkReady) {
                    bondReconnectRequired = true;
                    reconnectGattAfterBond();
                } else {
                    succeedPending(false);
                }
                return;
            }
            registerBondStateReceiver(device);
            if (device.getBondState() != BluetoothDevice.BOND_BONDING
                    && !device.createBond()) {
                failPending(
                        "ble_bond_failed",
                        "Android rejected the Bluetooth bond request.",
                        gattFailureDetails(-1, null)
                );
            }
        } catch (SecurityException error) {
            failPending(
                    "bluetooth_permission_denied",
                    "Bluetooth connect permission is missing.",
                    gattFailureDetails(-1, null)
            );
        } catch (RuntimeException error) {
            failPending(
                    "ble_bond_failed",
                    "Bluetooth bonding could not start.",
                    gattFailureDetails(-1, null)
            );
        }
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
                if (state == BluetoothDevice.BOND_BONDED) {
                    unregisterBondStateReceiver();
                    securityFailureObserved = false;
                    if (gatt == null || !linkReady) {
                        bondReconnectRequired = true;
                        reconnectGattAfterBond();
                    } else {
                        succeedPending(false);
                    }
                } else if (state == BluetoothDevice.BOND_NONE
                        && previous == BluetoothDevice.BOND_BONDING) {
                    failPending(
                            "ble_bond_rejected",
                            "Bluetooth bonding was rejected or cancelled.",
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

    private void reconnectGattAfterBond() {
        final BluetoothDevice device = connectedDevice;
        if (device == null) {
            failPending("invalid_state", "BirdBox device is unavailable after bonding.");
            return;
        }
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
                failPending("gatt_operation_failed", "GATT reconnect after bonding could not start.");
            }
        } catch (SecurityException error) {
            failPending("bluetooth_permission_denied", "Bluetooth connect permission is missing.");
        } catch (RuntimeException error) {
            failPending("gatt_operation_failed", "GATT reconnect after bonding could not start.");
        }
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
        pendingOperationTimeout = () -> {
            final boolean connectionTimedOut = "connect".equals(pendingOperation);
            final boolean bondTimedOut = "bond".equals(pendingOperation);
            failPending(
                    bondTimedOut ? "ble_bond_timeout" : "gatt_operation_failed",
                    bondTimedOut ? "Bluetooth bonding timed out." : "GATT operation timed out.",
                    gattFailureDetails(-1, null)
            );
            if (connectionTimedOut) closeGatt(false, "timeout", BluetoothGatt.GATT_FAILURE);
        };
        final long timeoutMs = "bond".equals(operation) ? 45000L : "connect".equals(operation) ? 15000L : 10000L;
        mainHandler.postDelayed(pendingOperationTimeout, timeoutMs);
        return true;
    }

    private synchronized void succeedPending(@Nullable Object value) {
        final String completedOperation = pendingOperation;
        cancelPendingOperationTimeout();
        final MethodChannel.Result result = pendingOperationResult;
        pendingOperationResult = null;
        pendingOperation = null;
        if ("bond".equals(completedOperation)) {
            unregisterBondStateReceiver();
            bondReconnectRequired = false;
        }
        if (result != null) mainHandler.post(() -> result.success(value));
    }

    private synchronized void failPending(String code, String message) {
        failPending(code, message, null);
    }

    private synchronized void failPending(String code, String message, @Nullable Object details) {
        final String failedOperation = pendingOperation;
        cancelPendingOperationTimeout();
        final MethodChannel.Result result = pendingOperationResult;
        pendingOperationResult = null;
        pendingOperation = null;
        if ("bond".equals(failedOperation)) {
            unregisterBondStateReceiver();
            bondReconnectRequired = false;
        }
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
            if (status == BluetoothGatt.GATT_SUCCESS && newState == BluetoothProfile.STATE_CONNECTED) {
                try {
                    callbackGatt.requestConnectionPriority(BluetoothGatt.CONNECTION_PRIORITY_HIGH);
                    if (!callbackGatt.discoverServices()) failPending("gatt_operation_failed", "Service discovery could not start.");
                } catch (SecurityException error) {
                    failPending("bluetooth_permission_denied", "Bluetooth connect permission is missing.");
                }
                return;
            }
            if (newState == BluetoothProfile.STATE_DISCONNECTED || status != BluetoothGatt.GATT_SUCCESS) {
                if ("bond".equals(pendingOperation)) {
                    closeGattForBond(callbackGatt);
                    if (connectedDevice != null
                            && connectedDevice.getBondState() == BluetoothDevice.BOND_BONDED) {
                        bondReconnectRequired = true;
                        reconnectGattAfterBond();
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
                    || !("connect".equals(pendingOperation) || "bond".equals(pendingOperation))) return;
            if (status != BluetoothGatt.GATT_SUCCESS) {
                failGattStatus(status, "GATT service discovery failed.");
                closeGatt(false, "service_discovery_failed", status);
                return;
            }
            final BluetoothGattService service = callbackGatt.getService(SERVICE_UUID);
            if (service == null) {
                failPending("invalid_request", "BirdBox network service is unavailable.");
                closeGatt(false, "service_unavailable", status);
                return;
            }
            for (UUID uuid : REQUIRED_CHARACTERISTICS) {
                if (service.getCharacteristic(uuid) == null) {
                    failPending("invalid_request", "A required BirdBox characteristic is unavailable.");
                    closeGatt(false, "service_invalid", status);
                    return;
                }
            }
            linkReady = true;
            if ("bond".equals(pendingOperation)) {
                securityFailureObserved = false;
                succeedPending(bondReconnectRequired);
            } else {
                succeedPending(null);
            }
        }

        @Override
        public void onMtuChanged(@NonNull BluetoothGatt callbackGatt, int mtu, int status) {
            if (callbackGatt != gatt || !"requestMtu".equals(pendingOperation)) return;
            if (status == BluetoothGatt.GATT_SUCCESS) succeedPending(mtu);
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
            if (status == BluetoothGatt.GATT_SUCCESS) succeedPending(null);
            else failGattStatus(status, "GATT write failed.", characteristic.getUuid());
        }

        @Override
        public void onDescriptorWrite(@NonNull BluetoothGatt callbackGatt, @NonNull BluetoothGattDescriptor descriptor, int status) {
            if (callbackGatt != gatt || !"descriptor".equals(pendingOperation)) return;
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
        details.put("operationName", pendingOperation == null ? "none" : pendingOperation);
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

    private void closeGattForBond(@NonNull BluetoothGatt callbackGatt) {
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
    }

    public void dispose() {
        if (disposed) return;
        disposed = true;
        unregisterBondStateReceiver();
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
        scanSink = null;
        notificationSink = null;
        disconnectSink = null;
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
