package deckers.thibault.aves;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import java.util.UUID;

import org.junit.Test;

/**
 * Framework-free native integration contract for the callback-missing recovery path.
 *
 * <p>The Android bridge supplies the real BluetoothDevice. This test intentionally uses a
 * counting substitute so that it can assert the contract without an OPPO handset or K7.</p>
 */
public final class BirdBoxSecurityWriteRecoveryIntegrationTest {
    private static final UUID CHARACTERISTIC_UUID =
            UUID.fromString("6f7d0005-7a66-4c45-a1b9-5f4d2e3c1000");

    @Test
    public void acceptedWriteWithoutCallbackStartsOneFallbackAndRejectsOldCallback() {
        final BirdBoxSecurityWriteAttemptContext context = new BirdBoxSecurityWriteAttemptContext();
        final BirdBoxConditionalBondFallbackPolicy policy =
                new BirdBoxConditionalBondFallbackPolicy();
        final BirdBoxSecurityWriteStateMachine state = new BirdBoxSecurityWriteStateMachine();
        final CountingBondStarter bondStarter = new CountingBondStarter(true);

        state.markGattReady(7);
        state.beginSecurityWrite("request-1", 7);
        policy.begin("request-1", 3);
        context.begin("request-1", 3, 7, CHARACTERISTIC_UUID, 1000L);
        assertTrue(context.markApiAccepted("request-1", 3, 7, CHARACTERISTIC_UUID));

        // The write API accepted the packet, but two seconds later Android has not supplied a
        // callback. The timeout must own this generation before pairing can begin.
        assertTrue(context.completeFromCallbackTimeout(
                "request-1", 3, 7, CHARACTERISTIC_UUID
        ));
        state.onWriteCallbackTimeout();
        assertEquals(
                BirdBoxConditionalBondFallbackPolicy.Decision.START_CONDITIONAL_FALLBACK,
                policy.arm(
                        "request-1",
                        3,
                        3000L,
                        false,
                        state.phase() == BirdBoxSecurityWriteStateMachine.Phase.BONDING,
                        context.trigger(),
                        false,
                        BirdBoxConditionalBondFallbackPolicy.BondState.NONE
                )
        );

        assertTrue(context.tryMarkFallbackStarted());
        assertTrue(state.tryMarkConditionalBondFallbackAttempted());
        context.recordCreateBondInvoked("not_bonded");
        final boolean started = bondStarter.createBond();
        context.recordCreateBondResult(started, "bonding");

        assertEquals(1, bondStarter.invocations);
        assertTrue(context.createBondInvoked());
        assertEquals(Boolean.TRUE, context.createBondReturned());
        assertEquals("not_bonded", context.createBondStateBefore());
        assertEquals("bonding", context.createBondStateAfter());
        // Duplicate timeout/scheduled work cannot issue a second request.
        assertFalse(context.tryMarkFallbackStarted());
        assertFalse(state.tryMarkConditionalBondFallbackAttempted());
        assertEquals(1, bondStarter.invocations);

        // A write callback from the old GATT generation cannot rewind the recovery sequence.
        assertFalse(context.completeFromCallback(3, 7, CHARACTERISTIC_UUID, false));
        state.onBonding();
        state.onBonded(false);
        state.onGattRecovered(8);
        state.onNotificationsRestored();
        assertEquals(1, state.encryptedRetryCount());
        assertEquals(BirdBoxSecurityWriteStateMachine.Phase.RETRYING_ENCRYPTED_WRITE, state.phase());
    }

    @Test
    public void rejectedCreateBondIsRecordedAndCannotScheduleAnotherFallback() {
        final BirdBoxSecurityWriteAttemptContext context = new BirdBoxSecurityWriteAttemptContext();
        final BirdBoxConditionalBondFallbackPolicy policy =
                new BirdBoxConditionalBondFallbackPolicy();
        final BirdBoxSecurityWriteStateMachine state = new BirdBoxSecurityWriteStateMachine();
        final CountingBondStarter bondStarter = new CountingBondStarter(false);

        state.markGattReady(7);
        state.beginSecurityWrite("request-2", 7);
        policy.begin("request-2", 3);
        context.begin("request-2", 3, 7, CHARACTERISTIC_UUID, 1000L);
        assertTrue(context.markApiAccepted("request-2", 3, 7, CHARACTERISTIC_UUID));
        assertTrue(context.completeFromCallbackTimeout(
                "request-2", 3, 7, CHARACTERISTIC_UUID
        ));
        state.onWriteCallbackTimeout();
        assertEquals(
                BirdBoxConditionalBondFallbackPolicy.Decision.START_CONDITIONAL_FALLBACK,
                policy.arm(
                        "request-2",
                        3,
                        3000L,
                        false,
                        true,
                        context.trigger(),
                        false,
                        BirdBoxConditionalBondFallbackPolicy.BondState.NONE
                )
        );

        assertTrue(context.tryMarkFallbackStarted());
        assertTrue(state.tryMarkConditionalBondFallbackAttempted());
        context.recordCreateBondInvoked("not_bonded");
        context.recordCreateBondResult(bondStarter.createBond(), "not_bonded");

        assertEquals(1, bondStarter.invocations);
        assertEquals(Boolean.FALSE, context.createBondReturned());
        assertFalse(context.tryMarkFallbackStarted());
        assertFalse(state.tryMarkConditionalBondFallbackAttempted());
        state.onPairingNotStartedTimeout();
        assertEquals(BirdBoxSecurityWriteStateMachine.Phase.FAILED, state.phase());
    }

    private static final class CountingBondStarter {
        private final boolean returnValue;
        private int invocations;

        private CountingBondStarter(boolean returnValue) {
            this.returnValue = returnValue;
        }

        private boolean createBond() {
            invocations++;
            return returnValue;
        }
    }
}
