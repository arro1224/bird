package deckers.thibault.aves.virtualbirdbox;

import static org.junit.Assert.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import static org.robolectric.Shadows.shadowOf;
import android.bluetooth.*;
import android.bluetooth.le.*;
import android.content.Context;
import android.os.Looper;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.*;
import org.json.JSONObject;
import org.junit.*;
import org.junit.runner.RunWith;
import org.mockito.ArgumentCaptor;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.*;

/** Actual peripheral callback and frame paths, with controlled Android endpoints. No RF claims. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = {27, 31}, manifest = Config.NONE)
@LooperMode(LooperMode.Mode.PAUSED)
public final class VirtualBirdBoxPeripheralTest {
    private final Context context = mock(Context.class);
    private final BluetoothManager manager = mock(BluetoothManager.class);
    private final BluetoothAdapter adapter = mock(BluetoothAdapter.class);
    private final BluetoothLeAdvertiser advertiser = mock(BluetoothLeAdvertiser.class);
    private final BluetoothGattServer server = mock(BluetoothGattServer.class);
    private final BluetoothDevice device = mock(BluetoothDevice.class);
    private final List<JSONObject> events = new ArrayList<>();
    private VirtualBirdBoxPeripheral peripheral;
    private BluetoothGattServerCallback callback;
    private BluetoothGattService service;
    private final byte[] message = ("{\"protocol_version\":\"1.0-rc4\",\"type\":\"open_pairing\",\"request_id\":\"550e8400-e29b-41d4-a716-446655440110\",\"client_id\":\"a870bcb1-d423-4d66-96f7-f809ce786543\",\"payload\":{}}").getBytes(StandardCharsets.UTF_8);
    @Before public void setup() {
        when(context.getApplicationContext()).thenReturn(context); when(context.getSystemService(BluetoothManager.class)).thenReturn(manager);
        when(manager.getAdapter()).thenReturn(adapter); when(adapter.isEnabled()).thenReturn(true);
        when(adapter.getBluetoothLeAdvertiser()).thenReturn(advertiser);
        when(manager.openGattServer(eq(context), any())).thenReturn(server);
        when(server.addService(any())).thenReturn(true); when(server.sendResponse(any(), anyInt(), anyInt(), anyInt(), any())).thenReturn(true);
        when(server.notifyCharacteristicChanged(any(), any(), eq(false))).thenReturn(true);
        when(device.getAddress()).thenReturn("AA:BB:CC:DD:EE:FF"); when(device.getBondState()).thenReturn(BluetoothDevice.BOND_BONDED);
    }
    @After public void cleanup() { if (peripheral != null) peripheral.stop(); shadowOf(Looper.getMainLooper()).idle(); }
    private void start(Ble11ScenarioState.Scenario scenario) throws Exception { start(new Ble11ScenarioState(scenario)); }
    private void start(Ble11ScenarioState state) throws Exception {
        peripheral = new VirtualBirdBoxPeripheral(context, state, (type, fields) -> {
            try { events.add(new JSONObject().put("event_type", type).put("fields", fields)); }
            catch (Exception error) { throw new IllegalStateException(error); }
        }); peripheral.start();
        ArgumentCaptor<BluetoothGattServerCallback> callbacks = ArgumentCaptor.forClass(BluetoothGattServerCallback.class);
        verify(manager).openGattServer(eq(context), callbacks.capture()); callback = callbacks.getValue();
        ArgumentCaptor<BluetoothGattService> services = ArgumentCaptor.forClass(BluetoothGattService.class);
        verify(server).addService(services.capture()); service = services.getValue();
        callback.onServiceAdded(0, service);
        ArgumentCaptor<AdvertiseCallback> advertise = ArgumentCaptor.forClass(AdvertiseCallback.class);
        verify(advertiser).startAdvertising(any(), any(), any(), advertise.capture()); advertise.getValue().onStartSuccess(null);
        subscribe(3); subscribe(6);
    }
    private void subscribe(int suffix) {
        BluetoothGattDescriptor descriptor = service.getCharacteristic(uuid(suffix)).getDescriptor(VirtualBirdBoxPeripheral.CCCD_UUID);
        callback.onDescriptorWriteRequest(device, 99, descriptor, false, true, 0, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE);
    }
    private static UUID uuid(int suffix) { return UUID.fromString("6f7d000" + suffix + "-7a66-4c45-a1b9-5f4d2e3c1000"); }
    private void send(int limit, int stopAt) {
        List<byte[]> frames = Rc4BleFrameCodec.fragment(message, 11, limit);
        for (int i = 0; i < frames.size() && (stopAt < 0 || i <= stopAt); i++) callback.onCharacteristicWriteRequest(device, i + 1, service.getCharacteristic(uuid(5)), false, true, 0, frames.get(i));
    }
    private long count(String type) { return events.stream().filter(e -> type.equals(e.optString("event_type"))).count(); }
    private void advance(long millis) { shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis)); }
    @Test public void currentRunConnectionObservationHashesOnlyTheActualPeer() throws Exception {
        start(Ble11ScenarioState.Scenario.BOND_FIRST);
        peripheral.setObservationRunId("offline-first-bond");
        callback.onConnectionStateChange(device, 0, BluetoothProfile.STATE_CONNECTED);
        JSONObject fields = events.get(events.size() - 1).getJSONObject("fields");
        assertEquals("offline-first-bond", fields.getString("run_id"));
        byte[] digest = java.security.MessageDigest.getInstance("SHA-256").digest("offline-first-bond:AA:BB:CC:DD:EE:FF".getBytes(StandardCharsets.UTF_8));
        StringBuilder expected = new StringBuilder();
        for (byte item : digest) expected.append(String.format("%02x", item & 0xff));
        assertEquals(expected.toString(), fields.getString("peer_address_hash"));
        assertFalse(fields.toString().contains("AA:BB:CC:DD:EE:FF"));
    }
    @Test public void invalidObservationRunCannotBeInstalled() throws Exception {
        start(Ble11ScenarioState.Scenario.BOND_FIRST);
        assertThrows(IllegalArgumentException.class, () -> peripheral.setObservationRunId("../old-run"));
    }
    @Test public void encryptedSuccessUsesFiveCharacteristicsAndOneBusinessOperation() throws Exception {
        start(Ble11ScenarioState.Scenario.BOND_FIRST);
        assertEquals(5, service.getCharacteristics().size());
        for (int suffix : new int[]{4, 5}) assertEquals(BluetoothGattCharacteristic.PERMISSION_WRITE_ENCRYPTED, service.getCharacteristic(uuid(suffix)).getPermissions());
        send(20, -1); advance(81);
        assertEquals(1, count("business_operation_executed")); assertEquals(1, count("business_response_enqueued"));
    }
    @Test public void largeMtuDeviceInfoReadUsesAtMost512ByteAttributesAndReassembles() throws Exception {
        start(Ble11ScenarioState.Scenario.BOND_FIRST); callback.onMtuChanged(device, 517);
        clearInvocations(server);
        callback.onCharacteristicReadRequest(device, 201, 0, service.getCharacteristic(uuid(2)));
        callback.onCharacteristicReadRequest(device, 202, 0, service.getCharacteristic(uuid(2)));
        ArgumentCaptor<byte[]> values = ArgumentCaptor.forClass(byte[].class);
        verify(server, times(2)).sendResponse(eq(device), anyInt(), eq(0), eq(0), values.capture());
        Rc4BleFrameCodec.Reassembler assembler = new Rc4BleFrameCodec.Reassembler(); byte[] complete = null;
        for (byte[] frame : values.getAllValues()) { assertTrue(frame.length <= 512); complete = assembler.add(frame); }
        assertNotNull(complete);
        assertEquals(VirtualBirdBoxProtocol.DEVICE_ID, new JSONObject(new String(complete, StandardCharsets.UTF_8)).getString("device_id"));
    }
    @Test public void authOnceRecoveryRefragmentsAtNewMtuAndDeduplicatesWholeMessage() throws Exception {
        start(Ble11ScenarioState.Scenario.AUTH_ONCE); send(20, 0);
        assertEquals(1, count("security_failure_injected")); assertEquals(0, count("command_received"));
        callback.onConnectionStateChange(device, 0, BluetoothProfile.STATE_DISCONNECTED);
        callback.onMtuChanged(device, 100); subscribe(3); subscribe(6); send(97, -1); advance(81);
        assertEquals(1, count("command_received")); assertEquals(1, count("business_operation_executed"));
        send(97, -1); advance(81);
        assertEquals(1, count("business_operation_executed")); assertEquals(1, count("business_deduplicated"));
    }
    @Test public void persistentAuthFailureNeverRunsBusiness() throws Exception {
        start(Ble11ScenarioState.Scenario.AUTH_PERSISTENT); send(20, 0);
        callback.onConnectionStateChange(device, 0, BluetoothProfile.STATE_DISCONNECTED); subscribe(3); subscribe(6); send(20, 0);
        assertEquals(2, count("security_failure_injected")); assertEquals(0, count("business_operation_executed"));
    }
    @Test public void authOnceReleasesOnlyAfterBothNotificationsRestoreEvenWithoutAclDisconnect() throws Exception {
        start(Ble11ScenarioState.Scenario.AUTH_ONCE); send(20, 0);
        subscribe(3); send(20, 0);
        assertEquals(2, count("security_failure_injected"));
        subscribe(6); send(20, -1); advance(81);
        assertEquals(1, count("business_operation_executed"));
        assertEquals(2, count("notification_round_restored"));
        assertEquals(0, count("connection_state_changed"));
    }
    @Test public void selectedMiddleFragmentOmitsAttAckBeforeAnyBusinessOperation() throws Exception {
        start(Ble11ScenarioState.Scenario.ATT_TIMEOUT_MIDDLE);
        int target = (Rc4BleFrameCodec.fragment(message, 11, 20).size() + 1) / 2;
        clearInvocations(server); send(20, target - 1);
        verify(server, never()).sendResponse(eq(device), eq(target), anyInt(), anyInt(), any());
        assertEquals(1, count("att_response_omitted")); assertEquals(0, count("command_received"));
    }
    @Test public void businessTimeoutHasAllAttAcksAndNoWriteTimeoutInjection() throws Exception {
        start(Ble11ScenarioState.Scenario.BUSINESS_TIMEOUT); clearInvocations(server); send(20, -1); advance(2000);
        verify(server, times(Rc4BleFrameCodec.fragment(message, 11, 20).size())).sendResponse(eq(device), anyInt(), eq(0), eq(0), isNull());
        assertEquals(1, count("business_response_omitted")); assertEquals(0, count("att_response_omitted"));
    }
    @Test public void delayedAndDuplicateResponsesRespectTheConfiguredBusinessDelay() throws Exception {
        start(Ble11ScenarioState.Scenario.RESPONSE_DUPLICATE); send(20, -1);
        assertEquals(0, count("business_response_enqueued")); advance(81);
        assertEquals(1, count("duplicate_business_response_injected")); assertEquals(1, count("business_operation_executed"));
    }
    @Test public void notificationFaultAndDisconnectedEpochRejectStaleScheduledResponses() throws Exception {
        start(Ble11ScenarioState.Scenario.NOTIFICATION_FAILURE);
        assertEquals(0, count("notification_failure_injected"));
        assertEquals(1, count("notification_round_restored"));
        subscribe(3); subscribe(6);
        assertEquals(1, count("notification_failure_injected"));
        send(20, -1); callback.onConnectionStateChange(device, 0, BluetoothProfile.STATE_DISCONNECTED); advance(81);
        verify(server, never()).notifyCharacteristicChanged(any(), any(), anyBoolean());
        assertEquals(0, count("business_response_enqueued"));
    }
}
