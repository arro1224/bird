package deckers.thibault.aves;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import androidx.test.ext.junit.runners.AndroidJUnit4;

import org.junit.Test;
import org.junit.runner.RunWith;

@RunWith(AndroidJUnit4.class)
public final class BirdBoxBondStateMachineTest {
    @Test
    public void alreadyBondedHealthyLinkUsesTheOnlyFastPath() {
        final BirdBoxBondStateMachine machine = new BirdBoxBondStateMachine();

        assertEquals(
                BirdBoxBondStateMachine.StartAction.USE_HEALTHY_LINK,
                machine.begin(true, true)
        );
        assertEquals(BirdBoxBondStateMachine.Phase.READY_TO_WRITE, machine.phase());
        assertFalse(machine.newBondRequired());
    }

    @Test
    public void newBondAlwaysTransitionsThroughGattRebuildAndNotificationRestore() {
        final BirdBoxBondStateMachine machine = new BirdBoxBondStateMachine();

        assertEquals(
                BirdBoxBondStateMachine.StartAction.CREATE_OR_WAIT_FOR_BOND,
                machine.begin(false, true)
        );
        assertTrue(machine.newBondRequired());
        assertEquals(BirdBoxBondStateMachine.Phase.REQUESTING, machine.phase());

        machine.bondRequestAccepted();
        assertEquals(BirdBoxBondStateMachine.Phase.BONDING, machine.phase());
        machine.bonded();
        assertEquals(BirdBoxBondStateMachine.Phase.BONDED, machine.phase());
        machine.reconnectingGatt();
        assertEquals(BirdBoxBondStateMachine.Phase.RECONNECTING_GATT, machine.phase());
        machine.discoveringServices();
        assertEquals(BirdBoxBondStateMachine.Phase.DISCOVERING_SERVICES, machine.phase());
        machine.nativeRecoveryComplete();
        assertEquals(BirdBoxBondStateMachine.Phase.RESTORING_NOTIFICATIONS, machine.phase());
        machine.readyToWrite();
        assertEquals(BirdBoxBondStateMachine.Phase.READY_TO_WRITE, machine.phase());
    }

    @Test
    public void unhealthyExistingBondRebuildsGattWithoutCreatingAnotherBond() {
        final BirdBoxBondStateMachine machine = new BirdBoxBondStateMachine();

        assertEquals(
                BirdBoxBondStateMachine.StartAction.RECONNECT_GATT,
                machine.begin(true, false)
        );
        assertEquals(BirdBoxBondStateMachine.Phase.RECONNECTING_GATT, machine.phase());
        assertFalse(machine.newBondRequired());
    }

    @Test
    public void failureIsTerminalUntilTheNextExplicitReset() {
        final BirdBoxBondStateMachine machine = new BirdBoxBondStateMachine();
        machine.begin(false, false);
        machine.fail();
        assertEquals(BirdBoxBondStateMachine.Phase.FAILED, machine.phase());

        machine.reset();
        assertEquals(BirdBoxBondStateMachine.Phase.IDLE, machine.phase());
        assertFalse(machine.newBondRequired());
    }
}
