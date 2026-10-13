package deckers.thibault.aves.virtualbirdbox;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.nio.charset.StandardCharsets;
import java.util.UUID;

final class VirtualBirdBoxProtocol {
    static final String PROTOCOL_VERSION = "1.0-rc4";
    static final String DEVICE_ID = "bbx-b1e11001b1e11001b1e11001b1e11001";
    static final String DEVICE_NAME = "BirdBox-B1E11001";

    interface MillisClock { long getAsLong(); }
    private final MillisClock clock;
    private final String baseUri;
    private final String outcome;
    private long windowExpiresAt;
    private int attempts;
    private boolean windowOpen;
    private String session;
    private String sessionClient;
    private long sessionExpiresAt;
    private JSONObject network;
    private String operationRequest;
    private String operationType;
    private String operationId;
    private long operationReadyAt;
    private boolean terminalEmitted;
    private JSONObject operationPayload;

    VirtualBirdBoxProtocol() { this(System::currentTimeMillis, "http://192.0.2.1:8080", "success"); }
    VirtualBirdBoxProtocol(MillisClock clock, String baseUri, String outcome) {
        if (!java.util.Arrays.asList("success", "failure", "hold").contains(outcome)) throw new IllegalArgumentException("Unknown business outcome");
        java.net.URI uri = java.net.URI.create(baseUri);
        if (!"http".equals(uri.getScheme()) || uri.getHost() == null || uri.getUserInfo() != null || uri.getQuery() != null) throw new IllegalArgumentException("Invalid business base URI");
        this.clock = clock; this.baseUri = baseUri; this.outcome = outcome;
        try { network = networkStatusPayload(); } catch (JSONException error) { throw new IllegalStateException(error); }
    }

    static byte[] deviceInfo() {
        try {
            final JSONObject capabilities = new JSONObject()
                    .put("direct_ap", true)
                    .put("infrastructure_sta", true)
                    .put("wifi_scan", false)
                    .put("wifi_manual", true)
                    .put("dpp_enrollee_supported", false)
                    .put("dpp_supported_akm", new JSONArray())
                    .put("mode_switch", true)
                    .put("network_recovery", true)
                    .put("ble_fragmentation_v1", true)
                    .put("wifi_ap_sta_concurrency", false)
                    .put("ap_band_2_4_ghz", true)
                    .put("ap_band_5_ghz", false);
            return bytes(new JSONObject()
                    .put("protocol_version", PROTOCOL_VERSION)
                    .put("min_app_protocol_version", PROTOCOL_VERSION)
                    .put("device_id", DEVICE_ID)
                    .put("device_name", DEVICE_NAME)
                    .put("firmware_version", "ble21-simulated")
                    .put("api_version", "v1")
                    .put("pairing_code_mode", "fixed_dev")
                    .put("pairing_code_length", 6)
                    .put("pairing_code_ttl_seconds", 600)
                    .put("display_available", false)
                    .put("capabilities", capabilities));
        } catch (JSONException error) {
            throw new IllegalStateException(error);
        }
    }

    byte[] networkStatusRead() {
        try {
            return response(
                    "00000000-0000-4000-8000-000000000011",
                    "network_status",
                    currentNetwork()
            );
        } catch (JSONException error) {
            throw new IllegalStateException(error);
        }
    }

    byte[] responseFor(JSONObject request) throws JSONException {
        final String requestId = request.getString("request_id");
        final String type = request.getString("type");
        final String client = request.optString("client_id");
        if (!PROTOCOL_VERSION.equals(request.optString("protocol_version")) || !client.matches("(?i)[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}")) return error(requestId, "INVALID_REQUEST", false);
        final JSONObject payload = request.optJSONObject("payload");
        if (payload == null) return error(requestId, "INVALID_REQUEST", false);
        if (type.equals("get_network_status")) return response(requestId, "network_status", currentNetwork());
        if (type.equals("open_pairing")) {
            // Exhausted attempts remain locked until this window expires.
            if (windowOpen && attempts == 0 && clock.getAsLong() < windowExpiresAt) return error(requestId, "PAIRING_RATE_LIMITED", true);
            if (!windowOpen || clock.getAsLong() >= windowExpiresAt) {
                windowOpen = true; attempts = 5; windowExpiresAt = clock.getAsLong() + 600_000; session = null;
            }
            return response(requestId, "pairing_opened", new JSONObject().put("pairing_code_mode", "fixed_dev").put("code_expires_in", Math.max(1, (windowExpiresAt - clock.getAsLong()) / 1000)).put("attempts_remaining", attempts));
        }
        if (type.equals("authorize_pairing")) {
            if (!windowOpen) return error(requestId, "PAIRING_NOT_OPEN", false);
            if (clock.getAsLong() >= windowExpiresAt) return error(requestId, "PAIRING_CODE_EXPIRED", false);
            if (attempts == 0) return error(requestId, "PAIRING_RATE_LIMITED", true);
            if (!"246810".equals(payload.optString("pairing_code"))) { attempts--; return error(requestId, "PAIRING_CODE_INVALID", true); }
            windowOpen = false; session = "ps_" + UUID.randomUUID(); sessionClient = client; sessionExpiresAt = clock.getAsLong() + 600_000;
            return response(requestId, "pairing_authorized", new JSONObject().put("pairing_session_id", session).put("expires_in", 600));
        }
        if (!java.util.Arrays.asList("start_direct_ap", "stop_direct_ap", "set_sta_config").contains(type)) return error(requestId, "CAPABILITY_UNSUPPORTED", false);
        JSONObject auth = payload.optJSONObject("authorization");
        if (auth == null) return error(requestId, "AUTHORIZATION_REQUIRED", false);
        if (!"pairing_session".equals(auth.optString("type"))) return error(requestId, "TOKEN_INVALID", false);
        if (session == null || !session.equals(auth.optString("value")) || !client.equals(sessionClient)) return error(requestId, "PAIRING_SESSION_INVALID", false);
        if (clock.getAsLong() >= sessionExpiresAt) return error(requestId, "PAIRING_SESSION_EXPIRED", false);
        currentNetwork();
        if (network.getBoolean("busy")) return error(requestId, "NETWORK_OPERATION_BUSY", true);
        operationId = "op_" + UUID.randomUUID(); operationRequest = requestId; operationType = type;
        operationPayload = new JSONObject().put("ssid", payload.optString("ssid", "BLE21-Test"))
                .put("network_kind", payload.optString("network_kind", "router"))
                .put("provisioning_method", payload.optString("provisioning_method", "ble_manual"));
        operationReadyAt = clock.getAsLong() + 1200; terminalEmitted = false;
        network.put("operation_id", operationId).put("desired_mode", desiredMode(type)).put("busy", true)
                .put("operation_state", type.equals("start_direct_ap") ? "starting_ap" : type.equals("stop_direct_ap") ? "stopping_ap" : "connecting_sta");
        return response(requestId, "command_accepted", new JSONObject().put("operation_id", operationId).put("desired_mode", desiredMode(type)).put("provisioning_method", type.equals("set_sta_config") ? payload.optString("provisioning_method", "ble_manual") : JSONObject.NULL));
    }

    private JSONObject currentNetwork() throws JSONException {
        if (network.getBoolean("busy") && !outcome.equals("hold") && clock.getAsLong() >= operationReadyAt) {
            network.put("busy", false);
            if (outcome.equals("failure")) network.put("operation_state", "failed").put("last_error", errorPayload(operationType.equals("start_direct_ap") ? "AP_START_FAILED" : operationType.equals("stop_direct_ap") ? "AP_STOP_FAILED" : "STA_CONNECT_TIMEOUT", true));
            else if (operationType.equals("stop_direct_ap")) network.put("active_mode", "none").put("operation_state", "idle").put("base_uri", JSONObject.NULL);
            else {
                boolean ap = operationType.equals("start_direct_ap");
                network.put("active_mode", ap ? "direct_ap" : "infrastructure_sta").put("operation_state", ap ? "ap_ready" : "sta_connected").put("base_uri", baseUri).put("last_error", JSONObject.NULL);
                if (ap) network.put("direct_ap", new JSONObject().put("ssid", DEVICE_NAME).put("security", "wpa2_personal").put("gateway_ipv4", "192.0.2.1").put("prefix_length", 24).put("client_count", 0));
                else network.put("infrastructure_sta", new JSONObject().put("ssid", operationPayload.optString("ssid", "BLE21-Test")).put("bssid", JSONObject.NULL).put("ipv4", "192.0.2.2").put("prefix_length", 24).put("gateway_ipv4", "192.0.2.1").put("network_kind", operationPayload.optString("network_kind", "router")).put("provisioning_method", operationPayload.optString("provisioning_method", "ble_manual")).put("saved", true));
            }
        }
        return new JSONObject(network.toString()).put("updated_at", timestamp(clock.getAsLong()));
    }

    byte[] terminalEvent() throws JSONException {
        JSONObject status = currentNetwork();
        if (operationId == null || status.getBoolean("busy") || terminalEmitted) return null;
        terminalEmitted = true;
        if (outcome.equals("failure")) return error(operationRequest, status.getJSONObject("last_error").getString("code"), true);
        JSONObject payload = new JSONObject().put("operation_id", operationId);
        if (operationType.equals("stop_direct_ap")) return response(operationRequest, "direct_ap_stopped", payload.put("active_mode", "none").put("operation_state", "idle").put("restored_sta", false).put("reason", "user_requested"));
        boolean ap = operationType.equals("start_direct_ap");
        payload.put("active_mode", ap ? "direct_ap" : "infrastructure_sta").put("ssid", ap ? DEVICE_NAME : operationPayload.optString("ssid", "BLE21-Test")).put("gateway_ipv4", "192.0.2.1").put("prefix_length", 24).put("base_uri", baseUri);
        if (ap) payload.put("security", "wpa2_personal").put("passphrase", "BLE21-SYNTHETIC-ONLY");
        else payload.put("bssid", JSONObject.NULL).put("ipv4", "192.0.2.2").put("network_kind", operationPayload.optString("network_kind", "router")).put("provisioning_method", operationPayload.optString("provisioning_method", "ble_manual"));
        return response(operationRequest, ap ? "direct_ap_ready" : "sta_connected", payload);
    }

    private static JSONObject errorPayload(String code, boolean retryable) throws JSONException {
        return new JSONObject().put("code", code).put("message", "Simulated application protocol failure").put("retryable", retryable).put("retry_after_ms", 0);
    }
    private static byte[] error(String requestId, String code, boolean retryable) throws JSONException {
        return bytes(new JSONObject().put("protocol_version", PROTOCOL_VERSION).put("type", "error").put("request_id", requestId).put("device_id", DEVICE_ID).put("ok", false).put("error", errorPayload(code, retryable)));
    }

    private static JSONObject networkStatusPayload() throws JSONException {
        return new JSONObject()
                .put("active_mode", "none")
                .put("desired_mode", "none")
                .put("operation_state", "idle")
                .put("operation_id", JSONObject.NULL)
                .put("busy", false)
                .put("base_uri", JSONObject.NULL)
                .put("direct_ap", new JSONObject()
                        .put("ssid", JSONObject.NULL)
                        .put("security", JSONObject.NULL)
                        .put("gateway_ipv4", JSONObject.NULL)
                        .put("prefix_length", JSONObject.NULL)
                        .put("client_count", JSONObject.NULL))
                .put("infrastructure_sta", new JSONObject()
                        .put("ssid", JSONObject.NULL)
                        .put("bssid", JSONObject.NULL)
                        .put("ipv4", JSONObject.NULL)
                        .put("prefix_length", JSONObject.NULL)
                        .put("gateway_ipv4", JSONObject.NULL)
                        .put("network_kind", JSONObject.NULL)
                        .put("provisioning_method", JSONObject.NULL)
                        .put("saved", false))
                .put("last_error", JSONObject.NULL)
                .put("updated_at", timestamp(System.currentTimeMillis()));
    }

    private static String timestamp(long millis) {
        java.text.SimpleDateFormat format = new java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", java.util.Locale.US);
        format.setTimeZone(java.util.TimeZone.getTimeZone("UTC"));
        return format.format(new java.util.Date(millis));
    }

    private static String desiredMode(String type) {
        return switch (type) {
            case "start_direct_ap" -> "direct_ap";
            case "stop_direct_ap" -> "none";
            default -> "infrastructure_sta";
        };
    }

    private static byte[] response(String requestId, String type, JSONObject payload) {
        try {
            return bytes(new JSONObject()
                    .put("protocol_version", PROTOCOL_VERSION)
                    .put("type", type)
                    .put("request_id", requestId)
                    .put("device_id", DEVICE_ID)
                    .put("ok", true)
                    .put("payload", payload));
        } catch (JSONException error) {
            throw new IllegalStateException(error);
        }
    }

    private static byte[] bytes(JSONObject value) {
        return value.toString().getBytes(StandardCharsets.UTF_8);
    }
}
