package deckers.thibault.aves;

import static org.junit.Assert.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import static org.robolectric.Shadows.shadowOf;

import android.Manifest;
import android.app.Activity;
import android.app.Application;
import android.bluetooth.*;
import android.content.*;
import android.location.LocationManager;
import android.os.Handler;
import android.os.Looper;
import android.os.Build;
import android.provider.Settings;
import java.time.Duration;
import java.util.*;
import org.junit.*;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.LooperMode;
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.*;

/** Executes production MethodCall, Android callback, timeout and Engine-plugin paths. No RF claims. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = {27, 31}, manifest = Config.NONE)
@LooperMode(LooperMode.Mode.PAUSED)
public final class BirdBoxBleBridgeTest {
    private static UUID uuid(int suffix) {
        return UUID.fromString(String.format("6f7d000%d-7a66-4c45-a1b9-5f4d2e3c1000", suffix));
    }
    private static final UUID CCCD = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb");
    private final BluetoothDevice device = mock(BluetoothDevice.class);
    private final BluetoothAdapter adapter = mock(BluetoothAdapter.class);
    private final BluetoothGatt oldGatt = mock(BluetoothGatt.class);
    private final BluetoothGatt freshGatt = mock(BluetoothGatt.class);
    private final BluetoothGatt recoveryGatt = mock(BluetoothGatt.class);
    private final BinaryMessenger messenger = mock(BinaryMessenger.class);
    private final TestPlatform platform = new TestPlatform();
    private BirdBoxBleChannel channel;
    private Application app;
    private BluetoothGattService service;
    private final List<Map<?, ?>> diagnostics = new ArrayList<>();
    private Map<?, ?> lastEvent(String type) {
        return diagnostics.stream().filter(e -> type.equals(e.get("eventType"))).reduce((a, b) -> b).orElseThrow();
    }
    private Map<?, ?> findEvent(String type) {
        return diagnostics.stream().filter(e -> type.equals(e.get("eventType"))).findFirst().orElse(null);
    }

    private final class TestPlatform extends BirdBoxBlePlatform {
        int bond = BluetoothDevice.BOND_NONE, connections, creates, unregisters, afterRegister = -1;
        boolean accepted = true, connectFails;
        RuntimeException bondError;
        BroadcastReceiver receiver;
        BluetoothGattCallback callback;
        final List<String> calls = new ArrayList<>();
        @Override int bondState(BluetoothDevice ignored) { return bond; }
        @Override boolean createBond(BluetoothDevice ignored) {
            calls.add("create"); creates++;
            assertNotNull("receiver must precede createBond", receiver);
            if (bondError != null) throw bondError;
            return accepted;
        }
        @Override void register(Context context, BroadcastReceiver value, IntentFilter filter) {
            receiver = value; calls.add("register");
            if (afterRegister != -1) bond = afterRegister;
        }
        @Override void unregister(Context context, BroadcastReceiver ignored) { receiver = null; unregisters++; }
        @Override BluetoothGatt connect(Context context, BluetoothDevice ignored, BluetoothGattCallback value) {
            assertSame(app, context); callback = value; connections++;
            calls.add("connect");
            return connections == 1 ? oldGatt : connectFails ? null : connections == 2 ? freshGatt : recoveryGatt;
        }
        void bonded() {
            bond = BluetoothDevice.BOND_BONDED;
            Intent intent = new Intent(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
                    .putExtra(BluetoothDevice.EXTRA_DEVICE, device)
                    .putExtra(BluetoothDevice.EXTRA_BOND_STATE, bond)
                    .putExtra(BluetoothDevice.EXTRA_PREVIOUS_BOND_STATE, BluetoothDevice.BOND_BONDING);
            receiver.onReceive(app, intent); drain(); retire(oldGatt);
        }
    }

    private static final class Result implements MethodChannel.Result {
        int completions;
        Object value, details;
        String code;
        public void success(Object value) { completions++; this.value = value; }
        public void error(String code, String message, Object details) { completions++; this.code = code; this.details = details; }
        public void notImplemented() { fail("Unexpected unimplemented method"); }
        void failed(String expected) { assertEquals(1, completions); assertEquals(expected, code); }
    }
    private static void drain() { shadowOf(Looper.getMainLooper()).idle(); }
    private static void advance(long millis) { shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis)); }
    private Result call(String name, Map<String, Object> args) {
        Result result = new Result(); channel.onMethodCall(new MethodCall(name, args), result); drain(); return result;
    }
    private Map<String, Object> owner() { return Collections.singletonMap("requestId", "request"); }
    private Result prepare() { return call("preparePairing", Map.of("requestId", "request", "commandType", "open_pairing")); }
    private Result write() { return call("writeWithResponse", Map.of("characteristicUuid", uuid(5).toString(), "value", new byte[]{1})); }
    private BluetoothGattDescriptor descriptor(int suffix) { return service.getCharacteristic(uuid(suffix)).getDescriptor(CCCD); }
    private void retire(BluetoothGatt old) {
        platform.callback.onConnectionStateChange(old, 0, BluetoothProfile.STATE_DISCONNECTED); drain(); advance(1_001);
    }
    private void connected(BluetoothGatt gatt) {
        if (gatt == freshGatt) retire(oldGatt);
        if (gatt == recoveryGatt) retire(freshGatt);
        platform.callback.onConnectionStateChange(gatt, 0, BluetoothProfile.STATE_CONNECTED); drain();
        if (Build.VERSION.SDK_INT <= 28 && gatt != oldGatt) {
            platform.callback.onMtuChanged(gatt, 100, 0); drain();
        }
        platform.callback.onServicesDiscovered(gatt, 0); drain();
    }
    private void mtu() { platform.callback.onMtuChanged(freshGatt, 100, 0); drain(); }
    private void notification(int suffix, int status) { platform.callback.onDescriptorWrite(freshGatt, descriptor(suffix), status); drain(); }
    private void ready() { platform.bonded(); connected(freshGatt); mtu(); notification(3, 0); notification(6, 0); }

    @Before public void setup() {
        app = RuntimeEnvironment.getApplication();
        shadowOf(app).grantPermissions(Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT);
        when(adapter.isEnabled()).thenReturn(true);
        when(adapter.getRemoteDevice(anyString())).thenReturn(device);
        when(device.getAddress()).thenReturn("AA:BB:CC:DD:EE:FF");
        service = new BluetoothGattService(uuid(1), BluetoothGattService.SERVICE_TYPE_PRIMARY);
        for (int suffix = 2; suffix <= 6; suffix++) {
            int properties = suffix == 2 ? BluetoothGattCharacteristic.PROPERTY_READ
                    : suffix == 3 || suffix == 6 ? BluetoothGattCharacteristic.PROPERTY_NOTIFY
                    : BluetoothGattCharacteristic.PROPERTY_WRITE;
            BluetoothGattCharacteristic c = new BluetoothGattCharacteristic(uuid(suffix), properties, 0);
            if (suffix == 3 || suffix == 6) c.addDescriptor(new BluetoothGattDescriptor(CCCD, BluetoothGattDescriptor.PERMISSION_WRITE));
            service.addCharacteristic(c);
        }
        for (BluetoothGatt gatt : new BluetoothGatt[]{oldGatt, freshGatt, recoveryGatt}) {
            when(gatt.discoverServices()).thenReturn(true);
            when(gatt.getService(uuid(1))).thenReturn(service);
            when(gatt.requestMtu(anyInt())).thenReturn(true);
            when(gatt.setCharacteristicNotification(any(), eq(true))).thenReturn(true);
            when(gatt.writeDescriptor(any(BluetoothGattDescriptor.class))).thenReturn(true);
            when(gatt.writeCharacteristic(any(BluetoothGattCharacteristic.class))).thenReturn(true);
            if (Build.VERSION.SDK_INT >= 33) {
                when(gatt.writeDescriptor(any(BluetoothGattDescriptor.class), any(byte[].class))).thenReturn(0);
                when(gatt.writeCharacteristic(any(BluetoothGattCharacteristic.class), any(byte[].class), anyInt())).thenReturn(0);
            }
        }
        channel = new BirdBoxBleChannel(app, messenger, platform, new Handler(Looper.getMainLooper()), adapter);
        String diagnosticChannel = "bird_companion/birdbox_ble/diagnostics";
        doAnswer(invocation -> {
            java.nio.ByteBuffer bytes = ((java.nio.ByteBuffer) invocation.getArgument(1)).duplicate(); bytes.flip();
            diagnostics.add((Map<?, ?>) StandardMethodCodec.INSTANCE.decodeEnvelope(bytes));
            return null;
        }).when(messenger).send(eq(diagnosticChannel), any(java.nio.ByteBuffer.class));
        org.mockito.ArgumentCaptor<BinaryMessenger.BinaryMessageHandler> listener = org.mockito.ArgumentCaptor.forClass(BinaryMessenger.BinaryMessageHandler.class);
        verify(messenger).setMessageHandler(eq(diagnosticChannel), listener.capture());
        java.nio.ByteBuffer listen = StandardMethodCodec.INSTANCE.encodeMethodCall(new MethodCall("listen", null)); listen.flip();
        listener.getValue().onMessage(listen, reply -> {});
        Result connection = call("connect", Map.of("deviceId", "AA:BB:CC:DD:EE:FF", "traceId", "test-trace"));
        connected(oldGatt); assertEquals(1, connection.completions); assertNull(connection.code);
    }
    @After public void cleanup() { channel.dispose(); drain(); }

    @Test public void ordinaryConnectWithoutCallbackTerminatesAtNativeDeadline() {
        call("disconnect", Collections.emptyMap());
        Result result = call("connect", Map.of("deviceId", "AA:BB:CC:DD:EE:FF"));
        advance(14_999); assertEquals(0, result.completions);
        advance(2); result.failed("ble_gatt_operation_failed");
        verify(freshGatt).disconnect(); verify(freshGatt).close();
        connected(freshGatt); advance(16_000);
        assertEquals(1, result.completions);
    }

    @Test public void ordinaryDiscoveryWithoutCallbackTerminatesAndIgnoresLateSuccess() {
        call("disconnect", Collections.emptyMap());
        Result result = call("connect", Map.of("deviceId", "AA:BB:CC:DD:EE:FF"));
        platform.callback.onConnectionStateChange(freshGatt, 0, BluetoothProfile.STATE_CONNECTED); drain();
        advance(15_001); result.failed("ble_gatt_operation_failed");
        assertEquals("callback_missing", lastEvent("gatt_service_discovery_timeout").get("resultCode"));
        platform.callback.onServicesDiscovered(freshGatt, 0); drain();
        assertEquals(1, result.completions);
    }

    /** Overrides final Build fields for the known-affected device check; restores them afterwards. */
    private static void setDeviceIdentity(String manufacturer, String model) throws Exception {
        java.lang.reflect.Field manufacturerField = Build.class.getField("MANUFACTURER");
        java.lang.reflect.Field modelField = Build.class.getField("MODEL");
        manufacturerField.setAccessible(true);
        modelField.setAccessible(true);
        manufacturerField.set(null, manufacturer);
        modelField.set(null, model);
    }

    @Test public void startScanWithLocationOffGuidesKnownAffectedDevicesAndStampsLocationFacts() throws Exception {
        Settings.Secure.putInt(app.getContentResolver(), Settings.Secure.LOCATION_MODE,
                Settings.Secure.LOCATION_MODE_OFF);
        String originalManufacturer = Build.MANUFACTURER, originalModel = Build.MODEL;
        setDeviceIdentity("HUAWEI", "MIS-AL00");
        try {
            Result scan = call("startScan", Map.of("scanSessionId", "scan-loc", "timeoutMs", 1_000));
            scan.failed("location_service_disabled");
            Map<?, ?> gate = lastEvent("location_compatibility_required");
            assertEquals("location_disabled", gate.get("resultCode"));
            assertEquals("disabled", gate.get("locationService"));
            assertEquals(Boolean.FALSE, gate.get("locationRequiredByApp"));
            if (Build.VERSION.SDK_INT == 31) {
                assertEquals("huawei_mis_al00_sdk31", gate.get("locationCompatibilityRule"));
                assertEquals(Boolean.TRUE, gate.get("locationRequiredForDeviceCompatibility"));
            } else {
                // Pre-S devices hit the same gate through the platform location
                // permission requirement, not the OEM compatibility rule.
                assertEquals("none", gate.get("locationCompatibilityRule"));
                assertEquals(Boolean.FALSE, gate.get("locationRequiredForDeviceCompatibility"));
            }
        } finally {
            setDeviceIdentity(originalManufacturer, originalModel);
        }
        // With location re-enabled the same known-affected device scans without the gate.
        Settings.Secure.putInt(app.getContentResolver(), Settings.Secure.LOCATION_MODE,
                Settings.Secure.LOCATION_MODE_HIGH_ACCURACY);
        long before = diagnostics.size();
        call("startScan", Map.of("scanSessionId", "scan-ok", "timeoutMs", 1_000));
        call("stopScan", Collections.emptyMap());
        assertTrue(diagnostics.stream().skip(before)
                .noneMatch(e -> "location_compatibility_required".equals(e.get("eventType"))));
    }

    @Test public void realBridgeIsolatesOldGattAndRequiresBothCccdsBeforeProtectedWrite() {        Result result = prepare();
        assertTrue(platform.calls.indexOf("register") < platform.calls.indexOf("create"));
        write().failed("ble_gatt_not_ready");
        platform.bonded();
        verify(oldGatt).disconnect();
        if (Build.VERSION.SDK_INT <= 28) verify(oldGatt, never()).close(); else verify(oldGatt).close();
        // Late callbacks from the old connection must not advance the fresh connection.
        connected(oldGatt); platform.callback.onMtuChanged(oldGatt, 517, 0); drain();
        assertEquals(0, result.completions);
        connected(freshGatt);
        if (Build.VERSION.SDK_INT <= 28) verify(oldGatt, never()).close(); else verify(oldGatt, atLeastOnce()).close();
        mtu(); notification(3, 0);
        write().failed("ble_gatt_not_ready"); assertEquals(0, result.completions);
        notification(6, 0); assertEquals(1, result.completions); assertNull(result.code);
        assertEquals(100, ((Map<?, ?>) result.value).get("mtu"));
        Result written = write(); assertEquals(0, written.completions);
        if (Build.VERSION.SDK_INT >= 33) verify(freshGatt).writeCharacteristic(eq(service.getCharacteristic(uuid(5))), any(byte[].class), eq(2));
        else verify(freshGatt).writeCharacteristic(service.getCharacteristic(uuid(5)));
        platform.callback.onCharacteristicWrite(freshGatt, service.getCharacteristic(uuid(5)), 0); drain();
        assertEquals(1, written.completions); advance(31_000); assertEquals(1, result.completions);
    }

    @Test @Config(sdk = 33) public void android33DescriptorAndWriteApisUseTheSameReadinessGate() {
        realBridgeIsolatesOldGattAndRequiresBothCccdsBeforeProtectedWrite();
        verify(freshGatt).writeDescriptor(eq(descriptor(3)), any(byte[].class));
        verify(freshGatt).writeDescriptor(eq(descriptor(6)), any(byte[].class));
    }
    @Test @Config(sdk = 33) public void largeMtuCannotBypassAndroidAttributeSizeLimit() {
        prepare(); ready(); call("requestMtu", Map.of("mtu", 517));
        platform.callback.onMtuChanged(freshGatt, 517, 0); drain();
        call("writeWithResponse", Map.of("characteristicUuid", uuid(5).toString(), "value", new byte[513])).failed("invalid_request");
        verify(freshGatt, never()).writeCharacteristic(any(BluetoothGattCharacteristic.class), any(byte[].class), anyInt());
        Result valid = call("writeWithResponse", Map.of("characteristicUuid", uuid(5).toString(), "value", new byte[512]));
        assertEquals(0, valid.completions);
        verify(freshGatt).writeCharacteristic(any(BluetoothGattCharacteristic.class), any(byte[].class), eq(2));
    }

    @Test public void falseAndMissingBroadcastTerminateWithoutProtectedBytes() {
        platform.accepted = false; Result failed = prepare(); failed.failed("bond_start_failed");
        assertEquals(1, ((Map<?, ?>) failed.details).get("createBondCallCount"));
        assertEquals(0, ((Map<?, ?>) failed.details).get("attWriteCallCount"));
        advance(31_000); assertEquals(1, failed.completions);
        verify(oldGatt, never()).writeCharacteristic(any()); verify(freshGatt, never()).writeCharacteristic(any());
    }
    @Test public void noBroadcastHitsBondDeadlineExactlyOnce() {
        Result result = prepare(); advance(30_001); result.failed("bond_timeout");
        advance(30_001); assertEquals(1, result.completions); assertEquals(1, platform.creates);
    }
    @Test public void oldBondLostBroadcastCannotCancelTheNewBondStartedFromRegisteredNone() {
        platform.bond = 12; platform.afterRegister = 10;
        Result result = prepare(); assertEquals(1, platform.creates);
        platform.receiver.onReceive(app, new Intent(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
                .putExtra(BluetoothDevice.EXTRA_DEVICE, device).putExtra(BluetoothDevice.EXTRA_BOND_STATE, 10)
                .putExtra(BluetoothDevice.EXTRA_PREVIOUS_BOND_STATE, 12));
        drain(); assertEquals(0, result.completions);
        ready(); assertEquals(1, result.completions); assertNull(result.code);
    }
    @Test public void permissionExceptionKeepsItsClassification() {
        platform.bondError = new SecurityException(); prepare().failed("bluetooth_permission_denied");
    }
    @Test public void vendorExceptionKeepsItsClassification() {
        platform.bondError = new IllegalStateException(); prepare().failed("bond_start_failed");
    }
    @Test public void oldGattDisconnectDuringBondingKeepsBondDeadlineAndCanRecover() {
        Result result = prepare();
        platform.callback.onConnectionStateChange(oldGatt, 133, BluetoothProfile.STATE_DISCONNECTED); drain();
        assertEquals(0, result.completions); ready(); assertEquals(1, result.completions); assertNull(result.code);
    }
    @Test public void freshConnectFailureCompletesPreparationOnce() {
        platform.connectFails = true; Result result = prepare(); platform.bonded();
        result.failed("ble_gatt_recovery_failed"); advance(31_000); assertEquals(1, result.completions);
    }
    @Test @Config(sdk = 31) public void connectionCallbackFailureTerminates() {
        // SDK 31：现代栈不重试，133 立即有界终止（SDK 27 的重试路径另测）。
        Result result = prepare(); platform.bonded();
        platform.callback.onConnectionStateChange(freshGatt, 133, BluetoothProfile.STATE_DISCONNECTED); drain();
        result.failed("ble_gatt_recovery_failed");
        assertEquals(133, ((Map<?, ?>) result.details).get("gattStatus"));
        assertEquals("gatt_connect", ((Map<?, ?>) result.details).get("preparationStep"));
        assertEquals(133, lastEvent("security_preparation_failed").get("gattStatus"));
        platform.callback.onConnectionStateChange(freshGatt, 0, BluetoothProfile.STATE_CONNECTED); drain();
        advance(16_000);
        assertEquals(1, result.completions);
        assertEquals(133, ((Map<?, ?>) result.details).get("gattStatus"));
        verify(freshGatt, never()).writeCharacteristic(any(BluetoothGattCharacteristic.class));
    }
    @Test @Config(sdk = 27) public void legacyFirstPostBondConnectFailureRetriesOnceThenSucceeds() {
        Result result = prepare(); platform.bonded();
        // 与 20261012-213905-P2-bond_first-3 同形：rebuild 拨号后 48ms 即回 133。
        platform.callback.onConnectionStateChange(freshGatt, 133, BluetoothProfile.STATE_DISCONNECTED); drain();
        assertEquals(0, result.completions);
        assertEquals("first_post_bond_rebuild", lastEvent("gatt_connect_retry_started").get("resultCode"));
        // settle gate 内不重拨，确认拨号发生在 settle 之后且是新客户端。
        advance(500); assertEquals(2, platform.connections);
        advance(501); assertEquals(3, platform.connections); assertEquals(0, result.completions);
        platform.callback.onConnectionStateChange(recoveryGatt, 0, BluetoothProfile.STATE_CONNECTED); drain();
        platform.callback.onMtuChanged(recoveryGatt, 100, 0); drain();
        platform.callback.onServicesDiscovered(recoveryGatt, 0); drain();
        platform.callback.onDescriptorWrite(recoveryGatt, descriptor(3), 0); drain();
        platform.callback.onDescriptorWrite(recoveryGatt, descriptor(6), 0); drain();
        assertEquals(1, result.completions); assertNull(result.code);
        // 失败客户端按既有纪律保留登记，不 close。
        verify(freshGatt, never()).close();
    }
    @Test @Config(sdk = 27) public void legacySecondPostBondConnectFailureTerminatesWithoutThirdDial() {
        Result result = prepare(); platform.bonded();
        platform.callback.onConnectionStateChange(freshGatt, 133, BluetoothProfile.STATE_DISCONNECTED); drain();
        advance(1_001);
        assertEquals(3, platform.connections);
        platform.callback.onConnectionStateChange(recoveryGatt, 133, BluetoothProfile.STATE_DISCONNECTED); drain();
        result.failed("ble_gatt_recovery_failed");
        assertEquals(133, ((Map<?, ?>) result.details).get("gattStatus"));
        advance(16_000);
        assertEquals(3, platform.connections); assertEquals(1, result.completions);
    }
    @Test @Config(sdk = 31) public void freshConnectFailureOnModernSdkTerminatesWithoutRetry() {
        Result result = prepare(); platform.bonded();
        platform.callback.onConnectionStateChange(freshGatt, 133, BluetoothProfile.STATE_DISCONNECTED); drain();
        result.failed("ble_gatt_recovery_failed");
        assertEquals(2, platform.connections);
        assertNull(findEvent("gatt_connect_retry_started"));
    }
    @Test @Config(sdk = 27) public void legacyPostBondRetryFailureAfterBondLostTerminatesAsBondLost() {
        Result result = prepare(); platform.bonded();
        platform.callback.onConnectionStateChange(freshGatt, 133, BluetoothProfile.STATE_DISCONNECTED); drain();
        platform.bond = BluetoothDevice.BOND_NONE;
        advance(1_001);
        result.failed("bond_lost");
        assertEquals(2, platform.connections);
    }
    @Test public void serviceCallbackFailurePreservesItsActualStatusAndStage() {
        Result result = prepare(); platform.bonded();
        platform.callback.onConnectionStateChange(freshGatt, 0, BluetoothProfile.STATE_CONNECTED); drain();
        if (Build.VERSION.SDK_INT <= 28) { platform.callback.onMtuChanged(freshGatt, 100, 0); drain(); }
        platform.callback.onServicesDiscovered(freshGatt, 133); drain();
        result.failed("ble_gatt_recovery_failed");
        assertEquals(133, ((Map<?, ?>) result.details).get("gattStatus"));
        assertEquals("services", ((Map<?, ?>) result.details).get("preparationStep"));
        verify(freshGatt, never()).writeDescriptor(any(BluetoothGattDescriptor.class));
    }
    @Test public void invalidServicesTerminateWithoutSubscriptionOrWrite() {
        when(freshGatt.getService(uuid(1))).thenReturn(null);
        Result result = prepare(); platform.bonded(); connected(freshGatt); result.failed("ble_gatt_recovery_failed");
        verify(freshGatt, never()).writeDescriptor(any(BluetoothGattDescriptor.class));
        assertEquals("service_properties_invalid", lastEvent("gatt_service_validation_failed").get("resultCode"));
    }

    @Test public void rejectedDiscoveryIsRecordedBeforeBoundedFailure() {
        when(freshGatt.discoverServices()).thenReturn(false);
        Result result = prepare(); platform.bonded(); connected(freshGatt);
        result.failed("ble_gatt_recovery_failed");
        Map<?, ?> event = lastEvent("gatt_service_discovery_api_returned");
        assertEquals(false, event.get("serviceDiscoveryApiAccepted"));
        assertEquals("rejected", event.get("resultCode"));
        assertEquals("request", event.get("requestId"));
        advance(31_000); assertEquals(1, result.completions);
        verify(freshGatt, never()).writeCharacteristic(any());
    }
    @Test public void discoveryExceptionIsSecretSafeAndKeepsPermissionClassification() {
        when(freshGatt.discoverServices()).thenThrow(new SecurityException("private-code-246810"));
        Result result = prepare(); platform.bonded(); connected(freshGatt);
        result.failed("bluetooth_permission_denied");
        assertEquals("permission_denied", lastEvent("gatt_service_discovery_api_exception").get("resultCode"));
        assertFalse(diagnostics.toString().contains("private-code-246810"));
    }
    @Test public void vendorDiscoveryExceptionIsDistinctFromRejectedApi() {
        when(freshGatt.discoverServices()).thenThrow(new IllegalStateException());
        Result result = prepare(); platform.bonded(); connected(freshGatt);
        result.failed("ble_gatt_recovery_failed");
        assertEquals("runtime_exception", lastEvent("gatt_service_discovery_api_exception").get("resultCode"));
    }
    @Test public void acceptedDiscoveryWithoutCallbackHasItsOwnEvidenceAndCannotBeRevived() {
        Result result = prepare(); platform.bonded();
        platform.callback.onConnectionStateChange(freshGatt, 0, BluetoothProfile.STATE_CONNECTED); drain();
        if (Build.VERSION.SDK_INT <= 28) { platform.callback.onMtuChanged(freshGatt, 100, 0); drain(); }
        advance(15_001); result.failed("ble_gatt_recovery_failed");
        Map<?, ?> event = lastEvent("gatt_service_discovery_timeout");
        assertEquals("callback_missing", event.get("resultCode"));
        assertEquals(true, event.get("serviceDiscoveryApiAccepted"));
        assertTrue(((Number) event.get("serviceDiscoveryElapsedMs")).longValue() >= 15_000);
        platform.callback.onServicesDiscovered(freshGatt, 0); drain();
        assertEquals("stale_gatt", lastEvent("gatt_service_discovery_callback_ignored").get("resultCode"));
        assertEquals(1, result.completions);
        if (Build.VERSION.SDK_INT <= 28) verify(freshGatt, times(1)).requestMtu(517);
        else verify(freshGatt, never()).requestMtu(anyInt());
        verify(freshGatt, never()).writeDescriptor(any(BluetoothGattDescriptor.class));
    }
    @Test public void staleDiscoveryCallbacksAreBoundedAndCannotAdvanceCurrentPreparation() {
        Result result = prepare(); platform.bonded();
        for (int i = 0; i < 20; i++) platform.callback.onServicesDiscovered(oldGatt, 0);
        drain();
        assertEquals(8, diagnostics.stream().filter(e -> "gatt_service_discovery_callback_ignored".equals(e.get("eventType"))).count());
        assertEquals(false, lastEvent("gatt_service_discovery_callback_ignored").get("callbackGattIsCurrent"));
        assertEquals(0, result.completions); verify(freshGatt, never()).requestMtu(anyInt());
    }
    @Test public void missingMtuCallbackHasItsOwnDeadlineAndLateCallbackCannotReviveIt() {
        Result result = prepare(); platform.bonded();
        if (Build.VERSION.SDK_INT <= 28) {
            platform.callback.onConnectionStateChange(freshGatt, 0, BluetoothProfile.STATE_CONNECTED); drain();
        } else connected(freshGatt);
        advance(15_001);
        result.failed("ble_gatt_recovery_failed"); mtu(); notification(3, 0); assertEquals(1, result.completions);
        assertTrue(((String) ((Map<?, ?>) result.details).get("sanitizedMessage")).contains("mtu"));
    }
    @Test public void firstCccdFailurePreventsSecondSubscription() {
        Result result = prepare(); platform.bonded(); connected(freshGatt); mtu(); notification(3, 133);
        result.failed("ble_gatt_recovery_failed"); verify(freshGatt, never()).writeDescriptor(descriptor(6));
    }
    @Test public void secondCccdFailureNeverBecomesSecurityReady() {
        Result result = prepare(); platform.bonded(); connected(freshGatt); mtu(); notification(3, 0); notification(6, 133);
        result.failed("ble_gatt_recovery_failed"); verify(freshGatt, never()).writeCharacteristic(any());
    }
    @Test public void revokedPermissionAtDiscoveryTerminates() {
        when(freshGatt.discoverServices()).thenThrow(new SecurityException());
        Result result = prepare(); platform.bonded(); connected(freshGatt); result.failed("bluetooth_permission_denied");
    }
    @Test public void cancelRacingQueuedBondBroadcastCompletesOnceAndRejectsStaleOwner() {
        Result result = prepare();
        BroadcastReceiver old = platform.receiver;
        Result stale = call("cancelPairing", Map.of("requestId", "old-request")); stale.failed("invalid_request");
        assertEquals(0, result.completions);
        call("cancelPairing", owner()); assertEquals(1, result.completions);
        platform.bond = 12;
        old.onReceive(app, new Intent(BluetoothDevice.ACTION_BOND_STATE_CHANGED).putExtra(BluetoothDevice.EXTRA_DEVICE, device)
                .putExtra(BluetoothDevice.EXTRA_BOND_STATE, 12).putExtra(BluetoothDevice.EXTRA_PREVIOUS_BOND_STATE, 11));
        drain(); advance(31_000); assertEquals(1, result.completions); assertEquals(1, platform.connections);
    }
    @Test public void writeTimeoutIsolatesLateWriteCallbackAndPermitsOnlyOneRecovery() {
        prepare(); ready(); Result written = write(); advance(2_001); written.failed("ble_link_not_encrypted");
        assertEquals(1, ((Map<?, ?>) written.details).get("attWriteCallCount"));
        assertEquals(1, ((Map<?, ?>) written.details).get("commandAttemptCount"));
        platform.callback.onCharacteristicWrite(freshGatt, service.getCharacteristic(uuid(5)), 0); drain();
        assertEquals(1, written.completions);
        verify(freshGatt, never()).close();
        Result recovery = call("recoverPairing", owner());
        assertEquals(2, platform.connections);
        assertEquals(0, recovery.completions);
        platform.callback.onConnectionStateChange(freshGatt, 0, BluetoothProfile.STATE_DISCONNECTED); drain();
        org.mockito.InOrder shutdown = inOrder(freshGatt);
        shutdown.verify(freshGatt).disconnect();
        assertEquals(2, platform.connections);
        advance(1_001);
        connected(recoveryGatt);
        if (Build.VERSION.SDK_INT <= 28) verify(freshGatt, never()).close(); else shutdown.verify(freshGatt, atLeastOnce()).close();
        platform.callback.onMtuChanged(recoveryGatt, 100, 0); drain();
        platform.callback.onDescriptorWrite(recoveryGatt, descriptor(3), 0); drain();
        platform.callback.onDescriptorWrite(recoveryGatt, descriptor(6), 0); drain();
        assertEquals(1, recovery.completions); assertNull(recovery.code);
        Result retry = write(); advance(2_001); retry.failed("ble_encrypted_retry_failed");
        assertEquals(2, ((Map<?, ?>) retry.details).get("attWriteCallCount"));
        assertEquals(2, ((Map<?, ?>) retry.details).get("commandAttemptCount"));
        assertEquals(1, ((Map<?, ?>) retry.details).get("writeFragmentIndex"));
        assertEquals(3, platform.connections); assertEquals(1, platform.creates);
        platform.callback.onCharacteristicWrite(recoveryGatt, service.getCharacteristic(uuid(5)), 0); drain();
        assertEquals(1, retry.completions);
    }
    @Test public void missingOldDisconnectCallbackFailsWithinBoundAndCannotReviveRecovery() {
        prepare(); ready(); Result written = write(); advance(2_001);
        written.failed("ble_link_not_encrypted");
        Result recovery = call("recoverPairing", owner());
        assertEquals(2, platform.connections);
        advance(3_001); recovery.failed("ble_gatt_recovery_failed");
        assertEquals("old_gatt_disconnect", ((Map<?, ?>) recovery.details).get("preparationStep"));
        verify(freshGatt).close();
        platform.callback.onConnectionStateChange(freshGatt, 0, BluetoothProfile.STATE_DISCONNECTED); drain();
        assertEquals(2, platform.connections); assertEquals(1, recovery.completions);
    }
    @Test public void existingBondPreparationWaitsForOldDisconnectAndDrainBeforeNewClient() {
        platform.bond = BluetoothDevice.BOND_BONDED;
        Result preparation = prepare();
        assertEquals(0, platform.creates); assertEquals(1, platform.connections);
        verify(oldGatt).disconnect(); verify(oldGatt, never()).close();
        platform.callback.onConnectionStateChange(oldGatt, 0, BluetoothProfile.STATE_DISCONNECTED); drain();
        if (Build.VERSION.SDK_INT <= 28) verify(oldGatt, never()).close(); else verify(oldGatt).close();
        advance(500); assertEquals(1, platform.connections);
        advance(501); assertEquals(2, platform.connections); assertEquals(0, preparation.completions);
        connected(freshGatt); mtu(); notification(3, 0); notification(6, 0);
        assertEquals(1, preparation.completions); assertNull(preparation.code);
    }
    @Test public void existingBondMissingOldDisconnectTerminatesWithoutCreatingFreshClient() {
        platform.bond = BluetoothDevice.BOND_BONDED;
        Result preparation = prepare(); advance(3_001);
        preparation.failed("ble_gatt_recovery_failed"); assertEquals(1, platform.connections);
        retire(oldGatt); assertEquals(1, platform.connections); assertEquals(1, preparation.completions);
    }
    @Test @Config(sdk = 27) public void legacySecuredConnectionRequiresMtuCallbackBeforeDiscovery() {
        prepare(); platform.bonded();
        platform.callback.onConnectionStateChange(freshGatt, 0, BluetoothProfile.STATE_CONNECTED); drain();
        verify(freshGatt, never()).discoverServices(); advance(1_001);
        verify(freshGatt, never()).discoverServices();
        platform.callback.onMtuChanged(freshGatt, 100, 0); drain();
        verify(freshGatt).discoverServices();
        platform.callback.onServicesDiscovered(freshGatt, 0); drain();
        verify(freshGatt, times(1)).requestMtu(517);
        verify(freshGatt).writeDescriptor(descriptor(3));
    }
    @Test @Config(sdk = 27) public void cancelDuringLegacyMtuBarrierCannotStartLateDiscovery() {
        Result preparation = prepare(); platform.bonded();
        platform.callback.onConnectionStateChange(freshGatt, 0, BluetoothProfile.STATE_CONNECTED); drain();
        call("cancelPairing", owner()); drain();
        platform.callback.onMtuChanged(freshGatt, 100, 0); drain(); advance(16_000);
        verify(freshGatt, never()).discoverServices();
        assertEquals(1, preparation.completions); assertNotNull(preparation.code);
    }
    @Test @Config(sdk = 27) public void legacyRejectedMtuUsesDefaultWithoutInventingCallback() {
        when(freshGatt.requestMtu(517)).thenReturn(false);
        Result preparation = prepare(); platform.bonded(); connected(freshGatt);
        notification(3, 0); notification(6, 0);
        assertEquals(1, preparation.completions); assertNull(preparation.code);
        assertEquals(23, ((Map<?, ?>) preparation.value).get("mtu"));
        assertEquals("rejected_default_mtu", lastEvent("gatt_mtu_barrier_api_returned").get("resultCode"));
        verify(freshGatt, times(1)).requestMtu(517);
    }
    @Test @Config(sdk = 27) public void legacyFailedMtuCallbackKeepsDefaultAndDiscoversOnce() {
        Result preparation = prepare(); platform.bonded();
        platform.callback.onConnectionStateChange(freshGatt, 0, BluetoothProfile.STATE_CONNECTED); drain();
        platform.callback.onMtuChanged(freshGatt, 100, 133); drain();
        platform.callback.onServicesDiscovered(freshGatt, 0); drain();
        notification(3, 0); notification(6, 0);
        assertEquals(1, preparation.completions); assertNull(preparation.code);
        assertEquals(23, ((Map<?, ?>) preparation.value).get("mtu"));
        verify(freshGatt, times(1)).discoverServices();
    }
    @Test @Config(sdk = 27) public void legacyMissingMtuCannotDiscoverOrWriteAndLateMtuCannotRevive() {
        Result preparation = prepare(); platform.bonded();
        platform.callback.onConnectionStateChange(freshGatt, 0, BluetoothProfile.STATE_CONNECTED); drain(); advance(15_001);
        preparation.failed("ble_gatt_recovery_failed");
        assertEquals("mtu_before_services", ((Map<?, ?>) preparation.details).get("preparationStep"));
        assertEquals("callback_missing", lastEvent("gatt_mtu_barrier_timeout").get("resultCode"));
        platform.callback.onMtuChanged(freshGatt, 100, 0); drain();
        verify(freshGatt, never()).discoverServices(); verify(freshGatt, never()).writeCharacteristic(any());
        assertEquals(1, preparation.completions);
    }
    @Test @Config(sdk = 27) public void legacyMtuPermissionExceptionKeepsClassification() {
        when(freshGatt.requestMtu(517)).thenThrow(new SecurityException());
        Result preparation = prepare(); platform.bonded();
        platform.callback.onConnectionStateChange(freshGatt, 0, BluetoothProfile.STATE_CONNECTED); drain();
        preparation.failed("bluetooth_permission_denied"); verify(freshGatt, never()).discoverServices();
    }
    @Test @Config(sdk = 27) public void legacyReservesDisconnectedRegistrationUntilFreshClientConnected() {
        Result preparation = prepare(); platform.bonded();
        verify(oldGatt).disconnect(); verify(oldGatt, never()).close();
        assertEquals(2, platform.connections); assertEquals(0, preparation.completions);
        assertEquals("legacy_active_session", lastEvent("gatt_old_client_close_deferred").get("resultCode"));
        platform.callback.onConnectionStateChange(oldGatt, 0, BluetoothProfile.STATE_DISCONNECTED); drain();
        assertEquals(2, platform.connections);
        platform.callback.onConnectionStateChange(freshGatt, 0, BluetoothProfile.STATE_CONNECTED); drain();
        verify(oldGatt, never()).close(); verify(freshGatt).requestMtu(517);
        call("disconnect", owner());
        verify(oldGatt).close(); verify(freshGatt).close();
    }
    @Test @Config(sdk = 27) public void cancelledLegacyHandoverClosesBothClientsAndRejectsLateConnection() {
        Result preparation = prepare(); platform.bonded();
        call("cancelPairing", owner()); drain();
        verify(oldGatt).close(); verify(freshGatt).close();
        platform.callback.onConnectionStateChange(freshGatt, 0, BluetoothProfile.STATE_CONNECTED); drain(); advance(31_000);
        assertEquals(2, platform.connections); assertEquals(1, preparation.completions);
        verify(freshGatt, never()).requestMtu(anyInt());
    }
    @Test @Config(sdk = 27) public void missingFreshConnectionRetriesOnceThenSecondSilenceTerminates() {
        // 与 20261013-140734-P2-bond_first-1 同形：rebuild 后约 15 秒无任何连接回调。
        Result preparation = prepare(); platform.bonded(); advance(15_001);
        assertEquals(0, preparation.completions);
        assertEquals("first_post_bond_rebuild", lastEvent("gatt_connect_retry_started").get("resultCode"));
        advance(1_001); // settle 后重拨
        assertEquals(3, platform.connections);
        advance(15_001); // 第二次同样静默 → 有界终止
        preparation.failed("ble_gatt_recovery_failed");
        assertEquals("gatt_connect", ((Map<?, ?>) preparation.details).get("preparationStep"));
        assertEquals(3, platform.connections);
    }
    @Test @Config(sdk = 27) public void legacySessionTeardownReleasesEveryHeldRegistrationAfterRecovery() {
        prepare(); ready(); write(); advance(2_001);
        call("recoverPairing", owner()); connected(recoveryGatt);
        verify(oldGatt, never()).close(); verify(freshGatt, never()).close();
        platform.callback.onConnectionStateChange(oldGatt, 0, BluetoothProfile.STATE_DISCONNECTED); drain();
        verify(oldGatt, never()).close();
        call("disconnect", owner());
        verify(oldGatt).close(); verify(freshGatt).close(); verify(recoveryGatt).close();
        org.mockito.InOrder teardown = inOrder(recoveryGatt, oldGatt, freshGatt);
        teardown.verify(recoveryGatt).disconnect();
        teardown.verify(recoveryGatt).close();
        teardown.verify(freshGatt).close();
        teardown.verify(oldGatt).close();
    }
    @Test @Config(sdk = 27) public void legacyAckBeforeDartRecoveryCannotUnregisterActiveSession() {
        prepare(); ready(); write(); advance(2_001);
        platform.callback.onConnectionStateChange(freshGatt, 0, BluetoothProfile.STATE_DISCONNECTED); drain();
        verify(freshGatt, never()).close();
        call("recoverPairing", owner()); advance(1_001);
        assertEquals(3, platform.connections); verify(oldGatt, never()).close();
        call("disconnect", owner()); verify(oldGatt).close(); verify(freshGatt).close();
    }
    @Test @Config(sdk = 27) @SuppressWarnings("unchecked") public void legacyRegistrationLimitTerminatesAndClosesEveryOwnedClient() throws Exception {
        prepare(); ready();
        java.lang.reflect.Field heldField = BirdBoxBleChannel.class.getDeclaredField("heldLegacyRegistrations");
        heldField.setAccessible(true);
        List<BluetoothGatt> held = (List<BluetoothGatt>) heldField.get(channel);
        List<BluetoothGatt> owned = new ArrayList<>();
        for (int i = 0; i < 8; i++) { BluetoothGatt extra = mock(BluetoothGatt.class); held.add(extra); owned.add(extra); }
        Result written = write(); advance(2_001);
        assertEquals(1, written.completions); assertNotNull(written.code);
        assertEquals("session_reconnect_required", lastEvent("gatt_legacy_registration_limit").get("resultCode"));
        assertEquals(2, platform.connections); verify(oldGatt).close(); verify(freshGatt).close();
        for (BluetoothGatt extra : owned) verify(extra).close();
        advance(31_000); assertEquals(1, written.completions);
    }
    @Test public void ownedCancelDuringOldGattWaitPreventsLateCallbackFromReconnecting() {
        prepare(); ready(); write(); advance(2_001);
        Result recovery = call("recoverPairing", owner());
        call("cancelPairing", owner());
        drain();
        assertEquals(1, recovery.completions); assertNotNull(recovery.code);
        platform.callback.onConnectionStateChange(freshGatt, 0, BluetoothProfile.STATE_DISCONNECTED); drain();
        advance(16_000); assertEquals(2, platform.connections); assertEquals(1, recovery.completions);
    }
    @Test public void cancelDuringDisconnectDrainCancelsScheduledReconnect() {
        prepare(); ready(); write(); advance(2_001);
        Result recovery = call("recoverPairing", owner());
        platform.callback.onConnectionStateChange(freshGatt, 0, BluetoothProfile.STATE_DISCONNECTED); drain();
        advance(500); assertEquals(2, platform.connections);
        call("cancelPairing", owner()); drain();
        advance(16_000); assertEquals(2, platform.connections);
        assertEquals(1, recovery.completions); assertNotNull(recovery.code);
    }
    @Test public void timeoutClosesOldClientEvenWhenVendorDisconnectThrows() {
        prepare(); ready();
        doThrow(new IllegalStateException("vendor disconnect failure")).when(freshGatt).disconnect();
        Result written = write(); advance(2_001);
        written.failed("ble_link_not_encrypted");
        verify(freshGatt).disconnect(); verify(freshGatt).close();
        platform.callback.onCharacteristicWrite(freshGatt, service.getCharacteristic(uuid(5)), 0); drain();
        assertEquals(1, written.completions);
        Result recovery = call("recoverPairing", owner());
        assertEquals(3, platform.connections);
        assertEquals(0, recovery.completions);
    }
    @Test public void multipleFragmentsAndRejectedApiRemainOneCommandAttempt() {
        prepare(); ready();
        for (int fragment = 0; fragment < 2; fragment++) {
            Result written = write();
            platform.callback.onCharacteristicWrite(freshGatt, service.getCharacteristic(uuid(5)), 0); drain();
            assertEquals(1, written.completions); assertNull(written.code);
        }
        when(freshGatt.writeCharacteristic(any(BluetoothGattCharacteristic.class))).thenReturn(false);
        Result rejected = write(); rejected.failed("ble_gatt_operation_failed");
        Map<?, ?> facts = (Map<?, ?>) rejected.details;
        assertEquals(3, facts.get("attWriteCallCount"));
        assertEquals(1, facts.get("commandAttemptCount"));
        assertEquals(3, facts.get("writeFragmentIndex"));
        assertEquals(1, facts.get("createBondCallCount"));
    }
    @Test public void retainedEnginePluginReattachesActivityAndEngineDestructionTerminatesOnce() {
        BirdBoxBlePlugin plugin = new BirdBoxBlePlugin((context, binaryMessenger) -> channel);
        FlutterPluginBinding engine = mock(FlutterPluginBinding.class);
        when(engine.getApplicationContext()).thenReturn(app); when(engine.getBinaryMessenger()).thenReturn(messenger);
        ActivityPluginBinding first = mock(ActivityPluginBinding.class), replacement = mock(ActivityPluginBinding.class);
        when(first.getActivity()).thenReturn(mock(Activity.class)); when(replacement.getActivity()).thenReturn(mock(Activity.class));
        plugin.onAttachedToEngine(engine); plugin.onAttachedToActivity(first);
        Result result = prepare(); plugin.onDetachedFromActivityForConfigChanges();
        assertEquals(0, result.completions); verify(oldGatt, never()).disconnect();
        plugin.onReattachedToActivityForConfigChanges(replacement); ready(); assertEquals(1, result.completions);
        Result written = write(); plugin.onDetachedFromEngine(engine); plugin.onDetachedFromEngine(engine); drain();
        written.failed("ble_session_ended");
        assertEquals("engine_destroyed", ((Map<?, ?>) written.details).get("teardownReason"));
        advance(31_000); assertEquals(1, written.completions); assertEquals(1, platform.unregisters);
        verify(first).removeRequestPermissionsResultListener(any()); verify(replacement).removeRequestPermissionsResultListener(any());
    }

    @Test public void detachedHostEndsPermissionWaitAndLateActivityReplyCannotCompleteItTwice() {
        Activity host = mock(Activity.class); channel.attachActivity(host);
        shadowOf(app).denyPermissions(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.BLUETOOTH_SCAN);
        Result permission = call("ensurePermissions", Collections.emptyMap());
        assertEquals(0, permission.completions);
        channel.detachActivity("activity_recreating"); permission.failed("ble_host_unavailable");
        channel.onRequestPermissionsResult(6204, new int[]{0}); assertEquals(1, permission.completions);
        channel.attachActivity(mock(Activity.class));
        shadowOf(app).grantPermissions(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.BLUETOOTH_SCAN);
        Result replacement = call("ensurePermissions", Collections.emptyMap());
        assertEquals(1, replacement.completions); assertEquals(Boolean.TRUE, replacement.value);
    }

    @Test public void freshProcessSessionUsesActualExistingBondWithoutReusingPriorRequest() {
        channel.dispose("engine_destroyed"); drain();
        channel = new BirdBoxBleChannel(app, messenger, platform, new Handler(Looper.getMainLooper()), adapter);
        platform.bond = 12;
        Result connection = call("connect", Map.of("deviceId", "AA:BB:CC:DD:EE:FF"));
        connected(freshGatt); assertEquals(1, connection.completions);
        Result preparation = prepare(); connected(recoveryGatt);
        platform.callback.onMtuChanged(recoveryGatt, 100, 0); drain();
        platform.callback.onDescriptorWrite(recoveryGatt, descriptor(3), 0); drain();
        platform.callback.onDescriptorWrite(recoveryGatt, descriptor(6), 0); drain();
        assertEquals(1, preparation.completions); assertNull(preparation.code); assertEquals(0, platform.creates);
    }
}
