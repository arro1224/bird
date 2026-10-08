package deckers.thibault.aves;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

public final class BirdBoxScanTimingTest {
    @Test
    public void fallbackKeepsAllThreeStrategyWindowsEvenWhenCallerRequestsLess() {
        assertEquals(
                15000L,
                BirdBoxScanTiming.effectiveTimeoutMs(true, 10000)
        );
        assertEquals(
                15000L,
                BirdBoxScanTiming.effectiveTimeoutMs(true, null)
        );
    }

    @Test
    public void callerMayRequestALongerFallbackWindow() {
        assertEquals(
                20000L,
                BirdBoxScanTiming.effectiveTimeoutMs(true, 20000)
        );
    }

    @Test
    public void nonFallbackTimeoutRetainsExistingMinimumRules() {
        assertEquals(
                1000L,
                BirdBoxScanTiming.effectiveTimeoutMs(false, 10)
        );
        assertEquals(
                10000L,
                BirdBoxScanTiming.effectiveTimeoutMs(false, null)
        );
    }
}
