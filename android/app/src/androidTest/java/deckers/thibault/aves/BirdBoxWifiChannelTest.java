package deckers.thibault.aves;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;

import androidx.test.ext.junit.runners.AndroidJUnit4;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.util.Map;

@RunWith(AndroidJUnit4.class)
public final class BirdBoxWifiChannelTest {
    @Test
    public void networkLostEventCarriesOnlyRoutingMetadata() {
        final Map<String, Object> event = BirdBoxWifiChannel.networkLostEvent(
                "18446744073709551615",
                "BirdBox-1234",
                "network_lost"
        );

        assertEquals("lost", event.get("type"));
        assertEquals("18446744073709551615", event.get("handle"));
        assertEquals("BirdBox-1234", event.get("ssid"));
        assertEquals("network_lost", event.get("reason"));
        assertFalse(event.containsKey("passphrase"));
        assertFalse(event.containsKey("deviceId"));
    }

    @Test
    public void networkLostEventNormalizesMissingSsid() {
        assertEquals("", BirdBoxWifiChannel.networkLostEvent("1", null, "network_lost").get("ssid"));
    }
}
