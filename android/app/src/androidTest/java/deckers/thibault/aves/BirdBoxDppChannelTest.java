package deckers.thibault.aves;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import android.app.Activity;

import androidx.test.ext.junit.runners.AndroidJUnit4;

import org.junit.Test;
import org.junit.runner.RunWith;

@RunWith(AndroidJUnit4.class)
public final class BirdBoxDppChannelTest {
    @Test
    public void validatesOnlyStandardDppUris() {
        assertTrue(BirdBoxDppChannel.isValidDppUri("DPP:K:PUBLIC_BOOTSTRAP_KEY;C:81/1;;"));
        assertFalse(BirdBoxDppChannel.isValidDppUri(null));
        assertFalse(BirdBoxDppChannel.isValidDppUri("https://example.test"));
        assertFalse(BirdBoxDppChannel.isValidDppUri("DPP:;;"));
    }

    @Test
    public void mapsSystemActivityResultsWithoutReturningUriData() {
        assertEquals("system_accepted", BirdBoxDppChannel.mapActivityResult(Activity.RESULT_OK));
        assertEquals("user_cancelled", BirdBoxDppChannel.mapActivityResult(Activity.RESULT_CANCELED));
        assertEquals("failed", BirdBoxDppChannel.mapActivityResult(42));
    }
}
