package deckers.thibault.aves;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public final class BirdBoxScanStrategyControllerTest {
    @Test
    public void rawZeroSwitchesThroughStrategiesInOrder() {
        final BirdBoxScanStrategyController controller = new BirdBoxScanStrategyController();
        final BirdBoxScanStrategyController.Snapshot first = controller.begin();

        assertEquals(0, first.index);
        assertEquals(
                BirdBoxScanStrategyController.Strategy.NULL_FILTER_LOW_LATENCY,
                first.strategy
        );

        final BirdBoxScanStrategyController.Decision second =
                controller.onWindowElapsed(first.generation);
        assertEquals(BirdBoxScanStrategyController.DecisionType.SWITCH, second.type);
        assertEquals("raw_zero_after_4000ms", second.reason);
        assertEquals(
                BirdBoxScanStrategyController.Strategy.EMPTY_FILTER_LIST_LOW_LATENCY,
                second.next.strategy
        );

        final BirdBoxScanStrategyController.Decision third =
                controller.onWindowElapsed(second.next.generation);
        assertEquals(BirdBoxScanStrategyController.DecisionType.SWITCH, third.type);
        assertEquals(
                BirdBoxScanStrategyController.Strategy.EMPTY_FILTER_LIST_DEFAULT_SETTINGS,
                third.next.strategy
        );

        final BirdBoxScanStrategyController.Decision exhausted =
                controller.onWindowElapsed(third.next.generation);
        assertEquals(
                BirdBoxScanStrategyController.DecisionType.FALLBACK_EXHAUSTED,
                exhausted.type
        );
        assertNull(exhausted.next);
    }

    @Test
    public void anyRawResultKeepsCurrentStrategyEvenWithoutCandidate() {
        final BirdBoxScanStrategyController controller = new BirdBoxScanStrategyController();
        final BirdBoxScanStrategyController.Snapshot first = controller.begin();

        assertTrue(controller.recordResult(first.generation, true, false));
        final BirdBoxScanStrategyController.Decision decision =
                controller.onWindowElapsed(first.generation);

        assertEquals(BirdBoxScanStrategyController.DecisionType.KEEP_CURRENT, decision.type);
        assertEquals(1, decision.completed.rawResultCount);
        assertEquals(1, decision.completed.deviceNameResultCount);
        assertEquals(0, decision.completed.candidateCount);
    }

    @Test
    public void staleGenerationCannotRecordOrAdvance() {
        final BirdBoxScanStrategyController controller = new BirdBoxScanStrategyController();
        final BirdBoxScanStrategyController.Snapshot first = controller.begin();
        final BirdBoxScanStrategyController.Decision second =
                controller.onWindowElapsed(first.generation);

        assertFalse(controller.recordResult(first.generation, true, true));
        assertFalse(controller.recordAndroidError(first.generation, 2));
        assertEquals(
                BirdBoxScanStrategyController.DecisionType.IGNORE_STALE,
                controller.onWindowElapsed(first.generation).type
        );
        assertEquals(second.next.generation, controller.current().generation);
    }

    @Test
    public void stopInvalidatesOutstandingCallback() {
        final BirdBoxScanStrategyController controller = new BirdBoxScanStrategyController();
        final BirdBoxScanStrategyController.Snapshot first = controller.begin();

        controller.stop();

        assertFalse(controller.accepts(first.generation));
        assertFalse(controller.recordResult(first.generation, false, true));
        assertNull(controller.current());
    }

    @Test
    public void androidErrorIsAttributedToActiveStrategyOnly() {
        final BirdBoxScanStrategyController controller = new BirdBoxScanStrategyController();
        final BirdBoxScanStrategyController.Snapshot first = controller.begin();

        assertTrue(controller.recordAndroidError(first.generation, 3));
        assertEquals(Integer.valueOf(3), controller.current().androidScanErrorCode);
    }

    @Test
    public void startedEventIsRecordedOnceForEachActiveGeneration() {
        final BirdBoxScanStrategyController controller = new BirdBoxScanStrategyController();
        final BirdBoxScanStrategyController.Snapshot first = controller.begin();

        assertTrue(controller.markStarted(first.generation));
        assertFalse(controller.markStarted(first.generation));

        final BirdBoxScanStrategyController.Decision second =
                controller.onWindowElapsed(first.generation);
        assertTrue(controller.markStarted(second.next.generation));
        assertFalse(controller.markStarted(first.generation));
    }
}
