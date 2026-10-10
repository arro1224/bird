package deckers.thibault.aves;

import org.junit.Test;
import java.util.ArrayList;
import java.util.List;
import static org.junit.Assert.*;

/** Executes the same side-effect coordinator used by BirdBoxBleChannel, without handset claims. */
public final class BirdBoxPairingCoordinatorTest {
    private static final class Harness implements BirdBoxPairingCoordinator.Platform {
        final BirdBoxSecurityWriteStateMachine state = new BirdBoxSecurityWriteStateMachine();
        final BirdBoxPairingCoordinator coordinator = new BirdBoxPairingCoordinator(state, this);
        final List<String> calls = new ArrayList<>();
        int bond = 10, afterRegister = -1, bondCalls, rebuilds;
        boolean accepted = true, deadline;
        RuntimeException exception;
        String failure;
        public int bondState() { return bond; }
        public void cancelOldWaits() { calls.add("cancel_old_waits"); }
        public void registerReceiver(long owner) {
            calls.add("register_receiver");
            if (afterRegister != -1) bond = afterRegister;
        }
        public boolean createBond() {
            calls.add("create_bond"); bondCalls++;
            if (exception != null) throw exception;
            return accepted;
        }
        public void startBondTimeout(long owner, long milliseconds) {
            assertEquals(30_000L, milliseconds); deadline = true;
        }
        public void cancelBondTimeout() { deadline = false; }
        public void rebuildGatt() { rebuilds++; calls.add("rebuild"); }
        public void event(String name, String result) { calls.add(name + ":" + result); }
        public void fail(String code) { failure = code; }
        void start() { coordinator.start("request", 7); }
    }

    @Test public void noneBindsBeforeWriteAndInitialReadinessDoesNotConsumeRetry() {
        Harness h = new Harness(); h.start();
        assertEquals(1, h.bondCalls);
        assertTrue(h.calls.indexOf("cancel_old_waits") < h.calls.indexOf("register_receiver"));
        assertTrue(h.calls.indexOf("register_receiver") < h.calls.indexOf("create_bond"));
        assertFalse(h.state.canWrite(7));
        assertEquals(0, h.rebuilds);
        h.coordinator.bondChanged(h.coordinator.owner(), 11, 10);
        h.coordinator.bondChanged(h.coordinator.owner(), 12, 11);
        assertEquals(1, h.rebuilds);
        assertFalse(h.deadline);
        h.state.onGattRecovered(8);
        assertFalse(h.state.canWrite(8));
        h.state.onNotificationsRestored();
        assertTrue(h.state.canWrite(8));
        assertFalse(h.state.canWrite(7));
        assertEquals(0, h.state.encryptedRetryCount());
        h.state.beginProtectedWrite(8);
        assertEquals(1, h.state.writeAttemptCount());
    }

    @Test public void existingBondingWaitsWithoutCreateBond() {
        Harness h = new Harness(); h.bond = 11; h.start();
        assertEquals(0, h.bondCalls); assertTrue(h.deadline);
        h.coordinator.bondChanged(h.coordinator.owner(), 12, 11);
        assertEquals(1, h.rebuilds);
    }

    @Test public void existingBondRebuildsWithoutFabricatedBondInvocation() {
        Harness h = new Harness(); h.bond = 12; h.start();
        assertEquals(0, h.bondCalls); assertEquals(1, h.rebuilds);
        assertFalse(h.calls.contains("create_bond_invoked:invoked"));
    }

    @Test public void registerThenRecheckHandlesFastBondingOrBonded() {
        for (int state : new int[]{11,12}) {
            Harness h = new Harness(); h.afterRegister = state; h.start();
            assertEquals(0, h.bondCalls);
            assertEquals(state == 12 ? 1 : 0, h.rebuilds);
        }
    }

    @Test public void falseFailsImmediatelyAndCancelsDeadline() {
        Harness h = new Harness(); h.accepted = false; h.start();
        assertEquals("bond_start_failed", h.failure);
        assertFalse(h.deadline); assertEquals(0, h.rebuilds);
        h.coordinator.bondChanged(h.coordinator.owner(),12,11);
        assertEquals(0,h.rebuilds);
    }

    @Test public void exceptionsAreObservableAndNeverPretendBonded() {
        for (RuntimeException error : new RuntimeException[]{new SecurityException(),new IllegalStateException()}) {
            Harness h=new Harness(); h.exception=error; h.start();
            assertEquals(error instanceof SecurityException ? "bluetooth_permission_denied" : "bond_start_failed",h.failure);
            assertTrue(h.calls.contains("create_bond_exception:"+error.getClass().getSimpleName()));
            assertFalse(h.deadline); assertEquals(0,h.rebuilds);
        }
    }

    @Test public void timeoutAndUserRejectionAreDistinct() {
        Harness timeout=new Harness(); timeout.start();
        timeout.coordinator.timeout(timeout.coordinator.owner());
        assertEquals("bond_timeout",timeout.failure);
        Harness reject=new Harness(); reject.start();
        reject.coordinator.bondChanged(reject.coordinator.owner(),10,11);
        assertEquals("bond_rejected",reject.failure);
    }

    @Test public void oldDeadlineAndBroadcastCannotAdvanceReplacementAttempt() {
        Harness h=new Harness(); h.start(); long old=h.coordinator.owner();
        h.coordinator.cancel(); h.state.reset(); h.start();
        h.coordinator.timeout(old); h.coordinator.bondChanged(old,12,11);
        assertNull(h.failure); assertEquals(0,h.rebuilds);
        assertTrue(h.coordinator.owns(h.coordinator.owner()));
    }

    @Test public void duplicateBondedCannotRebuildTwice() {
        Harness h=new Harness(); h.start();
        h.coordinator.bondChanged(h.coordinator.owner(),12,11);
        h.coordinator.bondChanged(h.coordinator.owner(),12,11);
        assertEquals(1,h.rebuilds);
    }

    @Test public void bondedRetryIsSingleAndNeverRestartsBond() {
        Harness h=new Harness(); h.bond=12; h.start();
        h.state.onGattRecovered(8); h.state.onNotificationsRestored(); h.state.beginProtectedWrite(8);
        h.state.beginBondedRecovery(); h.state.onGattRecovered(9); h.state.onNotificationsRestored();
        h.state.beginProtectedWrite(9); assertEquals(2,h.state.writeAttemptCount());
        h.state.onEncryptedRetryFailed();
        assertEquals(BirdBoxSecurityWriteStateMachine.Phase.FAILED,h.state.phase());
        assertEquals(0,h.bondCalls);
        assertThrows(IllegalStateException.class,h.state::beginBondedRecovery);
    }
}
