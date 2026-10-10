package deckers.thibault.aves;

import org.junit.Test;
import static org.junit.Assert.*;

public final class BirdBoxScanCompatibilityTest {
    @Test public void onlyConfirmedDeviceIsPreemptivelyGuided() {
        assertTrue(BirdBoxScanCompatibility.knownAffected("Huawei", "MIS-AL00",31));
        assertFalse(BirdBoxScanCompatibility.knownAffected("HUAWEI","other",31));
        assertFalse(BirdBoxScanCompatibility.knownAffected("vivo","MIS-AL00",31));
        assertFalse(BirdBoxScanCompatibility.knownAffected("HUAWEI","MIS-AL00",33));
    }
    @Test public void unknownDeviceRequiresCompletedZeroResultAndDisabledSwitch() {
        assertTrue(BirdBoxScanCompatibility.needsLocationGuidance(false,"disabled",true,0));
        assertFalse(BirdBoxScanCompatibility.needsLocationGuidance(false,"disabled",false,0));
        assertFalse(BirdBoxScanCompatibility.needsLocationGuidance(false,"disabled",true,1));
        assertFalse(BirdBoxScanCompatibility.needsLocationGuidance(false,"enabled",true,0));
        assertFalse(BirdBoxScanCompatibility.needsLocationGuidance(false,"unknown",true,0));
    }
}
