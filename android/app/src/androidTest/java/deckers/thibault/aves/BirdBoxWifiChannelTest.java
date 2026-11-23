package deckers.thibault.aves;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.assertNotNull;

import android.os.Build;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.filters.SdkSuppress;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.util.Map;

@RunWith(AndroidJUnit4.class)
public final class BirdBoxWifiChannelTest {
    @Test
    @SdkSuppress(minSdkVersion = Build.VERSION_CODES.Q)
    public void exactApRequestsUseTheDeclaredSecurity() {
        assertNotNull(BirdBoxWifiChannel.directApSpecifier("BirdBox-Test", "TEST_ONLY_PASSWORD", "wpa2_personal"));
        assertNotNull(BirdBoxWifiChannel.directApSpecifier("BirdBox-Test", "TEST_ONLY_PASSWORD", "wpa3_personal"));
        assertNotNull(BirdBoxWifiChannel.directApSpecifier("BirdBox-Test", "TEST_ONLY_PASSWORD", "wpa2_wpa3_transition"));
        assertTrue(BirdBoxWifiChannel.isSupportedDirectApSecurity("wpa3_personal"));
        assertFalse(BirdBoxWifiChannel.isSupportedDirectApSecurity(null));
        assertFalse(BirdBoxWifiChannel.isSupportedDirectApSecurity("unknown"));
        assertFalse(BirdBoxWifiChannel.isSupportedDirectApSecurity("open"));
    }

    @Test(expected = IllegalArgumentException.class)
    @SdkSuppress(minSdkVersion = Build.VERSION_CODES.Q)
    public void unsupportedSecurityCannotSilentlyBecomeWpa2() {
        BirdBoxWifiChannel.directApSpecifier("BirdBox-Test", "TEST_ONLY_PASSWORD", "unknown");
    }
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
