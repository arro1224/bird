package deckers.thibault.aves.virtualbirdbox;

import android.annotation.SuppressLint;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothGatt;
import android.bluetooth.BluetoothGattCharacteristic;
import android.bluetooth.BluetoothGattDescriptor;
import android.bluetooth.BluetoothGattServer;
import android.bluetooth.BluetoothGattServerCallback;
import android.bluetooth.BluetoothGattService;
import android.bluetooth.BluetoothManager;
import android.bluetooth.BluetoothProfile;
import android.bluetooth.le.AdvertiseCallback;
import android.bluetooth.le.AdvertiseData;
import android.bluetooth.le.AdvertiseSettings;
import android.bluetooth.le.BluetoothLeAdvertiser;
import android.content.Context;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.ParcelUuid;

import org.json.JSONException;
import org.json.JSONObject;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

@SuppressLint("MissingPermission")
final class VirtualBirdBoxPeripheral {
    interface EventSink {
        void record(String eventType, JSONObject fields);
    }

    static final UUID SERVICE_UUID = UUID.fromString("6f7d0001-7a66-4c45-a1b9-5f4d2e3c1000");
    static final UUID DEVICE_INFO_UUID = UUID.fromString("6f7d0002-7a66-4c45-a1b9-5f4d2e3c1000");
    static final UUID NETWORK_STATUS_UUID = UUID.fromString("6f7d0003-7a66-4c45-a1b9-5f4d2e3c1000");
    static final UUID WIFI_CONFIG_UUID = UUID.fromString("6f7d0004-7a66-4c45-a1b9-5f4d2e3c1000");
    static final UUID PROVISIONING_COMMAND_UUID = UUID.fromString("6f7d0005-7a66-4c45-a1b9-5f4D2E3C1000");
    static final UUID SCAN_RESULTS_UUID = UUID.fromString("6f7d0006-7a66-4c45-a1b9-5f4d2e3c1000");
    static final UUID CCCD_UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb");

    private static final int DEFAULT_MTU = 23;
    private static final int MAXIMUM_ATT_PAYLOAD = 514;
    private static final int COMPANY_IDENTIFIER = 0xFFFF;

    private final Context context;
    private final EventSink eventSink;
    private final Ble11ScenarioState scenarioState;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Map<String, Integer> mtuByDevice = new HashMap<>();
    private final Map<String, ArrayDeque<byte[]>> readFrames = new HashMap<>();
    private final Map<String, Rc4BleFrameCodec.Reassembler> writeReassemblers = new HashMap<>();
    private final Map<String, ArrayDeque<byte[]>> notificationQueues = new HashMap<>();
    private final Set<String> notificationInFlight = new HashSet<>();
    private final Set<String> enabledNotifications = new HashSet<>();

    private BluetoothAdapter adapter;
    private BluetoothLeAdvertiser advertiser;
    private BluetoothGattServer gattServer;
    private BluetoothGattCharacteristic networkStatusCharacteristic;
    private AdvertiseCallback advertiseCallback;
    private int responseMessageId = 0xB100;
    private String rejectedMessageHash;
    private byte[] staleResponse;
    private int securityRejectCount;

    VirtualBirdBoxPeripheral(
            Context context,
            Ble11ScenarioState.Scenario scenario,
            EventSink eventSink) {
        this.context = context.getApplicationContext();
        this.eventSink = eventSink;
        scenarioState = new Ble11ScenarioState(scenario);
    }

    void start() {
        final BluetoothManager manager = context.getSystemService(BluetoothManager.class);
        adapter = manager == null ? null : manager.getAdapter();
        if (adapter == null || !adapter.isEnabled()) {
            event("startup_failed", "reason", "bluetooth_unavailable");
            throw new IllegalStateException("Bluetooth is unavailable or disabled");
        }
        advertiser = adapter.getBluetoothLeAdvertiser();
        if (advertiser == null) {
            event("startup_failed", "reason", "ble_advertiser_unavailable");
            throw new IllegalStateException("BLE advertiser is unavailable");
        }
        adapter.setName(VirtualBirdBoxProtocol.DEVICE_NAME);
        gattServer = manager.openGattServer(context, callback);
        if (gattServer == null) {
            event("startup_failed", "reason", "gatt_server_unavailable");
            throw new IllegalStateException("GATT server is unavailable");
        }
        if (!gattServer.addService(buildService())) {
            event("startup_failed", "reason", "service_add_rejected");
            throw new IllegalStateException("GATT service registration was rejected");
        }
        event("server_starting", "scenario", scenarioState.scenario().wireValue());
    }

    void stop() {
        if (advertiser != null && advertiseCallback != null) {
            advertiser.stopAdvertising(advertiseCallback);
        }
        advertiseCallback = null;
        if (gattServer != null) {
            gattServer.clearServices();
            gattServer.close();
        }
        gattServer = null;
        readFrames.clear();
        writeReassemblers.clear();
        notificationQueues.clear();
        notificationInFlight.clear();
        enabledNotifications.clear();
        event("server_stopped");
    }

    private BluetoothGattService buildService() {
        final BluetoothGattService service = new BluetoothGattService(
                SERVICE_UUID,
                BluetoothGattService.SERVICE_TYPE_PRIMARY
        );
        final BluetoothGattCharacteristic deviceInfo = new BluetoothGattCharacteristic(
                DEVICE_INFO_UUID,
                BluetoothGattCharacteristic.PROPERTY_READ,
                BluetoothGattCharacteristic.PERMISSION_READ
        );
        networkStatusCharacteristic = notifyCharacteristic(NETWORK_STATUS_UUID, true);
        final int writePermission = scenarioState.requiresEncryptedPermission()
                ? BluetoothGattCharacteristic.PERMISSION_WRITE_ENCRYPTED
                : BluetoothGattCharacteristic.PERMISSION_WRITE;
        final BluetoothGattCharacteristic wifiConfig = new BluetoothGattCharacteristic(
                WIFI_CONFIG_UUID,
                BluetoothGattCharacteristic.PROPERTY_WRITE,
                writePermission
        );
        final BluetoothGattCharacteristic provisioning = new BluetoothGattCharacteristic(
                PROVISIONING_COMMAND_UUID,
                BluetoothGattCharacteristic.PROPERTY_WRITE,
                writePermission
        );
        final BluetoothGattCharacteristic scanResults = notifyCharacteristic(SCAN_RESULTS_UUID, false);
        service.addCharacteristic(deviceInfo);
        service.addCharacteristic(networkStatusCharacteristic);
        service.addCharacteristic(wifiConfig);
        service.addCharacteristic(provisioning);
        service.addCharacteristic(scanResults);
        return service;
    }

    private static BluetoothGattCharacteristic notifyCharacteristic(UUID uuid, boolean readable) {
        final BluetoothGattCharacteristic characteristic = new BluetoothGattCharacteristic(
                uuid,
                BluetoothGattCharacteristic.PROPERTY_NOTIFY
                        | (readable ? BluetoothGattCharacteristic.PROPERTY_READ : 0),
                readable ? BluetoothGattCharacteristic.PERMISSION_READ : 0
        );
        characteristic.addDescriptor(new BluetoothGattDescriptor(
                CCCD_UUID,
                BluetoothGattDescriptor.PERMISSION_READ | BluetoothGattDescriptor.PERMISSION_WRITE
        ));
        return characteristic;
    }

    private void startAdvertising() {
        final AdvertiseSettings settings = new AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
                .setConnectable(true)
                .setTimeout(0)
                .build();
        final AdvertiseData primary = new AdvertiseData.Builder()
                .addServiceUuid(new ParcelUuid(SERVICE_UUID))
                .build();
        final AdvertiseData scanResponse = new AdvertiseData.Builder()
                .setIncludeDeviceName(true)
                .addManufacturerData(
                        COMPANY_IDENTIFIER,
                        new byte[]{0x01, 0x01, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00}
                )
                .build();
        advertiseCallback = new AdvertiseCallback() {
            @Override
            public void onStartSuccess(AdvertiseSettings settingsInEffect) {
                event("advertising_started", "scenario", scenarioState.scenario().wireValue());
            }

            @Override
            public void onStartFailure(int errorCode) {
                event("advertising_failed", "error_code", errorCode);
            }
        };
        advertiser.startAdvertising(settings, primary, scanResponse, advertiseCallback);
    }

    private final BluetoothGattServerCallback callback = new BluetoothGattServerCallback() {
        @Override
        public void onServiceAdded(int status, BluetoothGattService service) {
            event("service_added", "status", status, "characteristic_count", service.getCharacteristics().size());
            if (status == BluetoothGatt.GATT_SUCCESS) startAdvertising();
        }

        @Override
        public void onConnectionStateChange(BluetoothDevice device, int status, int newState) {
            event(
                    "connection_state_changed",
                    "status", status,
                    "state", newState,
                    "bond_state", bondState(device.getBondState())
            );
            if (newState == BluetoothProfile.STATE_DISCONNECTED) clearDeviceState(device);
        }

        @Override
        public void onMtuChanged(BluetoothDevice device, int mtu) {
            mtuByDevice.put(device.getAddress(), mtu);
            event("mtu_changed", "mtu", mtu);
        }

        @Override
        public void onCharacteristicReadRequest(
                BluetoothDevice device,
                int requestId,
                int offset,
                BluetoothGattCharacteristic characteristic) {
            if (offset != 0) {
                gattServer.sendResponse(device, requestId, BluetoothGatt.GATT_INVALID_OFFSET, offset, null);
                return;
            }
            final byte[] message;
            if (DEVICE_INFO_UUID.equals(characteristic.getUuid())) {
                message = VirtualBirdBoxProtocol.deviceInfo();
            } else if (NETWORK_STATUS_UUID.equals(characteristic.getUuid())) {
                message = VirtualBirdBoxProtocol.networkStatusRead();
            } else {
                gattServer.sendResponse(device, requestId, BluetoothGatt.GATT_READ_NOT_PERMITTED, 0, null);
                return;
            }
            final String key = device.getAddress() + "/" + characteristic.getUuid();
            ArrayDeque<byte[]> frames = readFrames.get(key);
            if (frames == null || frames.isEmpty()) {
                frames = new ArrayDeque<>(Rc4BleFrameCodec.fragment(
                        message,
                        nextMessageId(),
                        maximumFragmentBytes(device)
                ));
                readFrames.put(key, frames);
            }
            final byte[] frame = frames.removeFirst();
            if (frames.isEmpty()) readFrames.remove(key);
            gattServer.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, frame);
            event(
                    "characteristic_read",
                    "characteristic", shortUuid(characteristic.getUuid()),
                    "frame_length", frame.length
            );
        }

        @Override
        public void onDescriptorReadRequest(
                BluetoothDevice device,
                int requestId,
                int offset,
                BluetoothGattDescriptor descriptor) {
            final String key = notificationKey(device, descriptor.getCharacteristic().getUuid());
            final byte[] value = enabledNotifications.contains(key)
                    ? BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                    : BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE;
            gattServer.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, value);
        }

        @Override
        public void onDescriptorWriteRequest(
                BluetoothDevice device,
                int requestId,
                BluetoothGattDescriptor descriptor,
                boolean preparedWrite,
                boolean responseNeeded,
                int offset,
                byte[] value) {
            final UUID characteristicUuid = descriptor.getCharacteristic().getUuid();
            final String key = notificationKey(device, characteristicUuid);
            final boolean enabled = java.util.Arrays.equals(
                    value,
                    BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
            );
            if (enabled) enabledNotifications.add(key); else enabledNotifications.remove(key);
            if (responseNeeded) {
                gattServer.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, value);
            }
            event(
                    "notification_subscription",
                    "characteristic", shortUuid(characteristicUuid),
                    "enabled", enabled
            );
        }

        @Override
        public void onCharacteristicWriteRequest(
                BluetoothDevice device,
                int requestId,
                BluetoothGattCharacteristic characteristic,
                boolean preparedWrite,
                boolean responseNeeded,
                int offset,
                byte[] value) {
            if (preparedWrite || offset != 0 || value == null) {
                if (responseNeeded) {
                    gattServer.sendResponse(device, requestId, BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED, offset, null);
                }
                return;
            }
            final UUID uuid = characteristic.getUuid();
            if (!WIFI_CONFIG_UUID.equals(uuid) && !PROVISIONING_COMMAND_UUID.equals(uuid)) {
                if (responseNeeded) {
                    gattServer.sendResponse(device, requestId, BluetoothGatt.GATT_WRITE_NOT_PERMITTED, 0, null);
                }
                return;
            }
            final String key = device.getAddress() + "/" + uuid;
            final Rc4BleFrameCodec.Reassembler reassembler = writeReassemblers.computeIfAbsent(
                    key,
                    ignored -> new Rc4BleFrameCodec.Reassembler()
            );
            final byte[] message;
            try {
                message = reassembler.add(value);
            } catch (IllegalArgumentException error) {
                writeReassemblers.remove(key);
                if (responseNeeded) {
                    gattServer.sendResponse(device, requestId, BluetoothGatt.GATT_FAILURE, 0, null);
                }
                event("write_rejected", "reason", "invalid_rc4_frame");
                return;
            }
            if (message == null) {
                if (responseNeeded) {
                    gattServer.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null);
                }
                return;
            }
            writeReassemblers.remove(key);
            handleCompleteWrite(device, requestId, responseNeeded, uuid, message);
        }

        @Override
        public void onNotificationSent(BluetoothDevice device, int status) {
            final String key = device.getAddress();
            notificationInFlight.remove(key);
            event("notification_sent", "status", status);
            sendNextNotification(device);
        }
    };

    private void handleCompleteWrite(
            BluetoothDevice device,
            int requestId,
            boolean responseNeeded,
            UUID characteristicUuid,
            byte[] message) {
        final JSONObject request;
        final String requestIdValue;
        final String commandType;
        try {
            request = new JSONObject(new String(message, StandardCharsets.UTF_8));
            requestIdValue = request.getString("request_id");
            commandType = request.getString("type");
        } catch (JSONException error) {
            if (responseNeeded) {
                gattServer.sendResponse(device, requestId, BluetoothGatt.GATT_FAILURE, 0, null);
            }
            event("write_rejected", "reason", "invalid_json");
            return;
        }
        final String messageHash = sha256(message);
        final boolean bonded = device.getBondState() == BluetoothDevice.BOND_BONDED;
        final Ble11ScenarioState.Action action = scenarioState.onCompleteMessage(bonded);
        event(
                "command_received",
                "request_id", requestIdValue,
                "command_type", commandType,
                "characteristic", shortUuid(characteristicUuid),
                "payload_sha256", messageHash,
                "bonded", bonded,
                "action", action.name().toLowerCase(java.util.Locale.ROOT)
        );
        if (action == Ble11ScenarioState.Action.REJECT_SECURITY) {
            securityRejectCount++;
            if (rejectedMessageHash == null) rejectedMessageHash = messageHash;
            if (responseNeeded) {
                gattServer.sendResponse(
                        device,
                        requestId,
                        BluetoothGatt.GATT_INSUFFICIENT_AUTHENTICATION,
                        0,
                        null
                );
            }
            event(
                    "security_failure_injected",
                    "count", securityRejectCount,
                    "payload_sha256", messageHash,
                    "retry_matches_original", rejectedMessageHash.equals(messageHash)
            );
            return;
        }
        if (action == Ble11ScenarioState.Action.DISCONNECT) {
            if (responseNeeded) {
                gattServer.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null);
            }
            try {
                staleResponse = VirtualBirdBoxProtocol.responseFor(request);
            } catch (JSONException error) {
                event("response_failed", "reason", "invalid_request");
            }
            event("disconnect_injected", "request_id", requestIdValue);
            handler.postDelayed(() -> gattServer.cancelConnection(device), 80L);
            return;
        }
        if (responseNeeded) {
            gattServer.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null);
        }
        if (rejectedMessageHash != null) {
            event(
                    "encrypted_retry_observed",
                    "payload_sha256", messageHash,
                    "matches_original", rejectedMessageHash.equals(messageHash),
                    "bonded", bonded
            );
        }
        final byte[] response;
        try {
            response = VirtualBirdBoxProtocol.responseFor(request);
        } catch (JSONException error) {
            event("response_failed", "reason", "invalid_request");
            return;
        }
        final byte[] delayedStaleResponse = staleResponse;
        staleResponse = null;
        handler.postDelayed(() -> {
            if (delayedStaleResponse != null) {
                event("stale_notification_injected", "before_request_id", requestIdValue);
                enqueueNotifications(device, delayedStaleResponse);
            }
            enqueueNotifications(device, response);
        }, 80L);
    }

    private void enqueueNotifications(BluetoothDevice device, byte[] response) {
        final String subscription = notificationKey(device, NETWORK_STATUS_UUID);
        if (!enabledNotifications.contains(subscription)) {
            event("response_failed", "reason", "network_notification_not_enabled");
            return;
        }
        final String key = device.getAddress();
        final ArrayDeque<byte[]> queue = notificationQueues.computeIfAbsent(key, ignored -> new ArrayDeque<>());
        queue.addAll(Rc4BleFrameCodec.fragment(response, nextMessageId(), maximumFragmentBytes(device)));
        sendNextNotification(device);
    }

    private void sendNextNotification(BluetoothDevice device) {
        final String key = device.getAddress();
        if (notificationInFlight.contains(key)) return;
        final ArrayDeque<byte[]> queue = notificationQueues.get(key);
        if (queue == null || queue.isEmpty()) {
            notificationQueues.remove(key);
            return;
        }
        final byte[] value = queue.removeFirst();
        final boolean started;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            started = gattServer.notifyCharacteristicChanged(
                    device,
                    networkStatusCharacteristic,
                    false,
                    value
            ) == BluetoothGatt.GATT_SUCCESS;
        } else {
            networkStatusCharacteristic.setValue(value);
            started = gattServer.notifyCharacteristicChanged(device, networkStatusCharacteristic, false);
        }
        if (started) {
            notificationInFlight.add(key);
        } else {
            event("notification_failed", "reason", "notify_rejected");
            notificationQueues.remove(key);
        }
    }

    private int nextMessageId() {
        final int current = responseMessageId;
        responseMessageId = (responseMessageId + 1) & 0xFFFF;
        return current;
    }

    private int maximumFragmentBytes(BluetoothDevice device) {
        final int mtu = mtuByDevice.getOrDefault(device.getAddress(), DEFAULT_MTU);
        return Math.max(Rc4BleFrameCodec.HEADER_LENGTH + 1, Math.min(MAXIMUM_ATT_PAYLOAD, mtu - 3));
    }

    private void clearDeviceState(BluetoothDevice device) {
        final String address = device.getAddress();
        mtuByDevice.remove(address);
        readFrames.keySet().removeIf(key -> key.startsWith(address + "/"));
        writeReassemblers.keySet().removeIf(key -> key.startsWith(address + "/"));
        enabledNotifications.removeIf(key -> key.startsWith(address + "/"));
        notificationQueues.remove(address);
        notificationInFlight.remove(address);
    }

    private static String notificationKey(BluetoothDevice device, UUID uuid) {
        return device.getAddress() + "/" + uuid;
    }

    private static String shortUuid(UUID uuid) {
        final String value = uuid.toString();
        return value.substring(0, 8);
    }

    private static String bondState(int state) {
        return switch (state) {
            case BluetoothDevice.BOND_NONE -> "none";
            case BluetoothDevice.BOND_BONDING -> "bonding";
            case BluetoothDevice.BOND_BONDED -> "bonded";
            default -> "unknown";
        };
    }

    private static String sha256(byte[] value) {
        try {
            final byte[] digest = MessageDigest.getInstance("SHA-256").digest(value);
            final StringBuilder output = new StringBuilder(digest.length * 2);
            for (byte item : digest) output.append(String.format("%02x", item & 0xFF));
            return output.toString();
        } catch (NoSuchAlgorithmException error) {
            throw new IllegalStateException(error);
        }
    }

    private void event(String eventType, Object... pairs) {
        final JSONObject fields = new JSONObject();
        try {
            fields.put("scenario", scenarioState.scenario().wireValue());
            for (int index = 0; index + 1 < pairs.length; index += 2) {
                fields.put(String.valueOf(pairs[index]), pairs[index + 1]);
            }
        } catch (JSONException error) {
            throw new IllegalStateException(error);
        }
        eventSink.record(eventType, fields);
    }
}
