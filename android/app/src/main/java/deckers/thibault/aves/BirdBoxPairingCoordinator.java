package deckers.thibault.aves;

/** Side-effect ordering used by the real channel. All calls belong to its serial executor. */
final class BirdBoxPairingCoordinator {
    static final int NONE = 10, BONDING = 11, BONDED = 12;
    static final long BOND_TIMEOUT_MS = 30_000L;

    interface Platform {
        int bondState();
        void cancelOldWaits();
        void registerReceiver(long owner);
        boolean createBond();
        void startBondTimeout(long owner, long milliseconds);
        void cancelBondTimeout();
        void rebuildGatt();
        void event(String name, String result);
        void fail(String code);
    }

    private final BirdBoxSecurityWriteStateMachine state;
    private final Platform platform;
    private long owner;
    private boolean active;
    private boolean invoked;

    BirdBoxPairingCoordinator(BirdBoxSecurityWriteStateMachine state, Platform platform) {
        this.state = state;
        this.platform = platform;
    }

    long owner() { return owner; }
    boolean owns(long candidate) { return active && candidate == owner; }

    void start(String requestId, long gattGeneration) {
        if (active) throw new IllegalStateException("Pairing is already active");
        owner++;
        active = true;
        invoked = false;
        try {
            platform.cancelOldWaits();
            int bond = platform.bondState();
            if (bond != NONE && bond != BONDING && bond != BONDED) {
                fail("bond_state_unknown");
                return;
            }
            state.markGattReady(gattGeneration);
            state.beginPairing(requestId, gattGeneration, bond);
            platform.registerReceiver(owner);
            // Registration precedes the second read and createBond; rapid broadcasts cannot
            // leave us waiting for a transition that already happened.
            bond = platform.bondState();
            if (bond == BONDED) {
                bonded();
                return;
            }
            platform.startBondTimeout(owner, BOND_TIMEOUT_MS);
            if (bond == BONDING) {
                state.onBonding();
                platform.event("system_bond_started", "already_bonding");
                return;
            }
            if (bond != NONE) { fail("bond_state_unknown"); return; }
            platform.event("system_bond_starting", "user_start_pairing");
            invoked = true;
            platform.event("create_bond_invoked", "invoked");
            boolean accepted = platform.createBond();
            platform.event("create_bond_returned", Boolean.toString(accepted));
            if (!accepted) { fail("bond_start_failed"); return; }
            platform.event("system_bond_started", "accepted_waiting_for_broadcast");
            // Some stacks have completed pairing before returning true. Read the actual state.
            bondChanged(owner, platform.bondState(), NONE);
        } catch (SecurityException error) {
            platform.event(invoked ? "create_bond_exception" : "system_bond_result",
                    error.getClass().getSimpleName());
            fail("bluetooth_permission_denied");
        } catch (RuntimeException error) {
            platform.event(invoked ? "create_bond_exception" : "system_bond_result",
                    error.getClass().getSimpleName());
            fail("bond_start_failed");
        }
    }

    void bondChanged(long candidate, int bond, int previous) {
        if (!owns(candidate)) return;
        if (!state.isWaitingForBond()) return;
        if (bond == BONDED) bonded();
        else if (bond == BONDING) state.onBonding();
        else if (bond == NONE && previous == BONDING) fail("bond_rejected");
    }

    void timeout(long candidate) {
        if (!owns(candidate) || !state.isWaitingForBond()) return;
        fail("bond_timeout");
    }

    void cancel() {
        active = false;
        platform.cancelBondTimeout();
    }

    private void bonded() {
        platform.cancelBondTimeout();
        if (state.phase() != BirdBoxSecurityWriteStateMachine.Phase.BONDED_RECOVERING_GATT) {
            state.onBonded(false);
        }
        platform.event("system_bond_result", "bonded");
        platform.rebuildGatt();
    }

    private void fail(String code) {
        if (!active) return;
        active = false;
        platform.cancelBondTimeout();
        state.failAttempt(code.equals("bond_timeout")
                ? BirdBoxSecurityWriteStateMachine.Failure.PAIRING_TIMEOUT
                : BirdBoxSecurityWriteStateMachine.Failure.PAIRING_REJECTED);
        platform.event("system_bond_result", code);
        platform.fail(code);
    }
}
