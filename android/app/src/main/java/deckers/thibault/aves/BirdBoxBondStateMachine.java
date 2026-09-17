package deckers.thibault.aves;

import androidx.annotation.NonNull;

/**
 * Deterministic, Android-framework-free state for one Bond/GATT recovery.
 *
 * The Bluetooth callbacks remain in {@link BirdBoxBleChannel}; this class owns
 * the transition decisions so new-Bond and already-Bonded paths cannot be
 * accidentally conflated by a vendor stack that keeps the old GATT object.
 */
final class BirdBoxBondStateMachine {
    enum Phase {
        IDLE,
        REQUESTING,
        BONDING,
        BONDED,
        RECONNECTING_GATT,
        DISCOVERING_SERVICES,
        RESTORING_NOTIFICATIONS,
        READY_TO_WRITE,
        FAILED
    }

    enum StartAction {
        USE_HEALTHY_LINK,
        CREATE_OR_WAIT_FOR_BOND,
        RECONNECT_GATT
    }

    private Phase phase = Phase.IDLE;
    private boolean newBondRequired;

    @NonNull
    Phase phase() {
        return phase;
    }

    boolean newBondRequired() {
        return newBondRequired;
    }

    @NonNull
    StartAction begin(boolean alreadyBonded, boolean linkHealthy) {
        newBondRequired = !alreadyBonded;
        if (alreadyBonded && linkHealthy) {
            phase = Phase.READY_TO_WRITE;
            return StartAction.USE_HEALTHY_LINK;
        }
        if (alreadyBonded) {
            phase = Phase.RECONNECTING_GATT;
            return StartAction.RECONNECT_GATT;
        }
        phase = Phase.REQUESTING;
        return StartAction.CREATE_OR_WAIT_FOR_BOND;
    }

    void bondRequestAccepted() {
        phase = Phase.BONDING;
    }

    void waitingForBond() {
        phase = Phase.BONDING;
    }

    void bonded() {
        phase = Phase.BONDED;
    }

    void reconnectingGatt() {
        phase = Phase.RECONNECTING_GATT;
    }

    void discoveringServices() {
        phase = Phase.DISCOVERING_SERVICES;
    }

    void nativeRecoveryComplete() {
        phase = Phase.RESTORING_NOTIFICATIONS;
    }

    void readyToWrite() {
        phase = Phase.READY_TO_WRITE;
    }

    void fail() {
        phase = Phase.FAILED;
    }

    void reset() {
        phase = Phase.IDLE;
        newBondRequired = false;
    }
}
