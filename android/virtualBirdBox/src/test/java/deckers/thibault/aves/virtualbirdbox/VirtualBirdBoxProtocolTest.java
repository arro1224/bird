package deckers.thibault.aves.virtualbirdbox;

import static org.junit.Assert.*;
import org.json.JSONObject;
import org.json.JSONArray;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicLong;

/** Application authorization and simulated operations; no radio or IP routing proof. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 31, manifest = Config.NONE)
public final class VirtualBirdBoxProtocolTest {
    private final AtomicLong now = new AtomicLong(1_800_000_000_000L);
    private final VirtualBirdBoxProtocol protocol = new VirtualBirdBoxProtocol(now::get, "http://127.0.0.1:8787", "success");
    private int sequence;
    private JSONObject send(String type, JSONObject payload) throws Exception {
        return decode(protocol.responseFor(new JSONObject().put("protocol_version", "1.0-rc4").put("type", type)
                .put("request_id", String.format("10000000-0000-4000-8000-%012d", ++sequence))
                .put("client_id", "a870bcb1-d423-4d66-96f7-f809ce786543").put("payload", payload)));
    }
    private static JSONObject decode(byte[] value) throws Exception { return new JSONObject(new String(value, StandardCharsets.UTF_8)); }
    private JSONObject code(String code) throws Exception { return new JSONObject().put("pairing_code", code); }
    private JSONObject authorize() throws Exception {
        send("open_pairing", new JSONObject());
        String session = send("authorize_pairing", code("246810")).getJSONObject("payload").getString("pairing_session_id");
        return new JSONObject().put("authorization", new JSONObject().put("type", "pairing_session").put("value", session));
    }
    private static void error(JSONObject response, String expected) throws Exception {
        assertFalse(response.getBoolean("ok")); assertEquals("error", response.getString("type"));
        assertEquals(expected, response.getJSONObject("error").getString("code"));
        assertEquals(4, response.getJSONObject("error").length());
    }
    @Test public void closedWindowAndWrongCodeFail() throws Exception {
        error(send("authorize_pairing", code("246810")), "PAIRING_NOT_OPEN");
        send("open_pairing", new JSONObject()); error(send("authorize_pairing", code("000000")), "PAIRING_CODE_INVALID");
        assertTrue(send("authorize_pairing", code("246810")).getBoolean("ok"));
        error(send("authorize_pairing", code("246810")), "PAIRING_NOT_OPEN");
    }
    @Test public void attemptsCannotBeResetByOpeningAgain() throws Exception {
        send("open_pairing", new JSONObject());
        error(send("authorize_pairing", code("000000")), "PAIRING_CODE_INVALID");
        assertEquals(4, send("open_pairing", new JSONObject()).getJSONObject("payload").getInt("attempts_remaining"));
        for (int i = 0; i < 4; i++) error(send("authorize_pairing", code("000000")), "PAIRING_CODE_INVALID");
        error(send("authorize_pairing", code("246810")), "PAIRING_RATE_LIMITED");
        error(send("open_pairing", new JSONObject()), "PAIRING_RATE_LIMITED");
        now.addAndGet(600_000); assertTrue(send("open_pairing", new JSONObject()).getBoolean("ok"));
    }
    @Test public void expiryUsesExactBoundary() throws Exception {
        send("open_pairing", new JSONObject()); now.addAndGet(600_000);
        error(send("authorize_pairing", code("246810")), "PAIRING_CODE_EXPIRED");
    }
    @Test public void authorizationIsRequiredAndExpires() throws Exception {
        error(send("start_direct_ap", new JSONObject()), "AUTHORIZATION_REQUIRED");
        JSONObject auth = authorize(); now.addAndGet(600_000);
        error(send("start_direct_ap", auth), "PAIRING_SESSION_EXPIRED");
    }
    @Test public void freshWindowInvalidatesPriorSession() throws Exception {
        JSONObject auth = authorize(); send("open_pairing", new JSONObject());
        error(send("start_direct_ap", auth), "PAIRING_SESSION_INVALID");
    }
    @Test public void acceptedIsBusyUntilTerminalAndEachOperationIsIndependent() throws Exception {
        JSONObject auth = authorize();
        String first = send("start_direct_ap", auth).getJSONObject("payload").getString("operation_id");
        assertTrue(decode(protocol.networkStatusRead()).getJSONObject("payload").getBoolean("busy"));
        assertNull(protocol.terminalEvent()); error(send("start_direct_ap", auth), "NETWORK_OPERATION_BUSY");
        now.addAndGet(1300); JSONObject ready = decode(protocol.terminalEvent());
        assertEquals("direct_ap_ready", ready.getString("type")); assertEquals(first, ready.getJSONObject("payload").getString("operation_id"));
        assertNull(protocol.terminalEvent());
        String second = send("stop_direct_ap", auth).getJSONObject("payload").getString("operation_id"); assertNotEquals(first, second);
        now.addAndGet(1300); assertEquals("direct_ap_stopped", decode(protocol.terminalEvent()).getString("type"));
    }
    @Test public void staStatusSurvivesReadAndTerminalPollOrder() throws Exception {
        JSONObject auth = authorize().put("ssid", "BLE21-Test").put("provisioning_method", "ble_manual").put("network_kind", "router");
        send("set_sta_config", auth); now.addAndGet(1300);
        JSONObject status = decode(protocol.networkStatusRead()).getJSONObject("payload");
        assertEquals("sta_connected", status.getString("operation_state")); assertFalse(status.getBoolean("busy"));
        assertEquals(status.getString("operation_id"), decode(protocol.terminalEvent()).getJSONObject("payload").getString("operation_id"));
        assertEquals(status.getString("operation_id"), decode(protocol.networkStatusRead()).getJSONObject("payload").getString("operation_id"));
    }
    @Test public void operationFailureAndHoldNeverClaimSuccess() throws Exception {
        for (String outcome : new String[]{"failure", "hold"}) {
            VirtualBirdBoxProtocol box = new VirtualBirdBoxProtocol(now::get, "http://127.0.0.1:8787", outcome);
            JSONObject request = new JSONObject().put("protocol_version", "1.0-rc4").put("client_id", "a870bcb1-d423-4d66-96f7-f809ce786543").put("request_id", "10000000-0000-4000-8000-000000000001");
            box.responseFor(request.put("type", "open_pairing").put("payload", new JSONObject()));
            String session = decode(box.responseFor(request.put("type", "authorize_pairing").put("payload", code("246810")))).getJSONObject("payload").getString("pairing_session_id");
            box.responseFor(request.put("type", "start_direct_ap").put("payload", new JSONObject().put("authorization", new JSONObject().put("type", "pairing_session").put("value", session))));
            now.addAndGet(1300);
            if (outcome.equals("hold")) { assertNull(box.terminalEvent()); assertTrue(decode(box.networkStatusRead()).getJSONObject("payload").getBoolean("busy")); }
            else { error(decode(box.terminalEvent()), "AP_START_FAILED"); assertEquals("failed", decode(box.networkStatusRead()).getJSONObject("payload").getString("operation_state")); }
        }
    }

    @Test public void exportsActualNativeMessagesForStrictDartContractGate() throws Exception {
        JSONArray samples = new JSONArray();
        samples.put(new JSONObject().put("kind", "device_info").put("message", decode(VirtualBirdBoxProtocol.deviceInfo())));
        samples.put(new JSONObject().put("kind", "event").put("message", send("authorize_pairing", code("246810"))));
        samples.put(new JSONObject().put("kind", "event").put("message", send("open_pairing", new JSONObject())));
        JSONObject authorization = send("authorize_pairing", code("246810"));
        samples.put(new JSONObject().put("kind", "event").put("message", authorization));
        JSONObject auth = new JSONObject().put("authorization", new JSONObject().put("type", "pairing_session").put("value", authorization.getJSONObject("payload").getString("pairing_session_id")));
        for (String type : new String[]{"start_direct_ap", "stop_direct_ap", "set_sta_config"}) {
            samples.put(new JSONObject().put("kind", "event").put("message", send(type, auth)));
            samples.put(new JSONObject().put("kind", "event").put("message", decode(protocol.networkStatusRead())));
            now.addAndGet(1300);
            samples.put(new JSONObject().put("kind", "event").put("message", decode(protocol.terminalEvent())));
            samples.put(new JSONObject().put("kind", "event").put("message", decode(protocol.networkStatusRead())));
        }
        java.nio.file.Path path = java.nio.file.Paths.get("..", "..", "build", "ble21-protocol-samples.json");
        java.nio.file.Files.createDirectories(path.getParent());
        java.nio.file.Files.writeString(path, new JSONObject().put("evidence_kind", "native_simulated_protocol_messages").put("samples", samples).toString(2), StandardCharsets.UTF_8);
    }
}
