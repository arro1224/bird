package deckers.thibault.aves.virtualbirdbox;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.nio.charset.StandardCharsets;
import java.time.Instant;

final class VirtualBirdBoxProtocol {
    static final String PROTOCOL_VERSION = "1.0-rc4";
    static final String DEVICE_ID = "bbx-b1e11001b1e11001b1e11001b1e11001";
    static final String DEVICE_NAME = "BirdBox-B1E11001";

    private VirtualBirdBoxProtocol() {}

    static byte[] deviceInfo() {
        try {
            final JSONObject capabilities = new JSONObject()
                    .put("direct_ap", true)
                    .put("infrastructure_sta", true)
                    .put("wifi_scan", true)
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
                    .put("firmware_version", "ble11-simulated")
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

    static byte[] networkStatusRead() {
        try {
            return response(
                    "00000000-0000-4000-8000-000000000011",
                    "network_status",
                    networkStatusPayload()
            );
        } catch (JSONException error) {
            throw new IllegalStateException(error);
        }
    }

    static byte[] responseFor(JSONObject request) throws JSONException {
        final String requestId = request.getString("request_id");
        final String type = request.getString("type");
        return switch (type) {
            case "open_pairing" -> response(
                    requestId,
                    "pairing_opened",
                    new JSONObject()
                            .put("pairing_code_mode", "fixed_dev")
                            .put("code_expires_in", 600)
                            .put("attempts_remaining", 5)
            );
            case "authorize_pairing" -> response(
                    requestId,
                    "pairing_authorized",
                    new JSONObject()
                            .put("pairing_session_id", "ble11-simulated-session")
                            .put("expires_in", 600)
            );
            case "get_network_status" -> response(requestId, "network_status", networkStatusPayload());
            default -> response(
                    requestId,
                    "command_accepted",
                    new JSONObject()
                            .put("operation_id", "op-ble11-0001")
                            .put("desired_mode", desiredMode(type))
            );
        };
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
                .put("updated_at", Instant.now().toString());
    }

    private static String desiredMode(String type) {
        return switch (type) {
            case "start_direct_ap", "stop_direct_ap" -> "direct_ap";
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
