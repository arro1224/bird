package deckers.thibault.aves;

/** Side-effect ordering used by the real channel. All calls belong to its serial executor. */
final class BirdBoxPairingCoordinator {
    static final int NONE = 10, BONDING = 11, BONDED = 12;
    static final long BOND_TIMEOUT_MS = 30_000L;

    interface Platform {
        int bondState();
        /** True when the current GATT link is alive, ready and already subscribed. */
        boolean gattUsable();
        void cancelOldWaits();
        void registerReceiver(long owner);
        boolean createBond();
        void startBondTimeout(long owner, long milliseconds);
        void cancelBondTimeout();
        void rebuildGatt();
        /** Re-confirms notifications on the still-usable bonded link instead of rebuilding. */
        void restoreNotificationsAfterBond();
        void event(String name, String result);
        void fail(String code);
    }

    private final BirdBoxSecurityWriteStateMachine state;
    private final Platform platform;
    private long owner;
    private boolean active;
    private boolean invoked;
    private boolean waitingForBond;

    BirdBoxPairingCoordinator(BirdBoxSecurityWriteStateMachine state, Platform platform) {
        this.state = state;
        this.platform = platform;
    }

    long owner() { return owner; }
    boolean owns(long candidate) { return active && candidate == owner; }
    boolean waitingForBond() { return active && waitingForBond; }

    void start(String requestId, long gattGeneration) {
        if (active) throw new IllegalStateException("Pairing is already active");
        owner++;
        active = true;
        invoked = false;
        waitingForBond = true;
        try {
            platform.cancelOldWaits();
            platform.registerReceiver(owner);
            // One authoritative read initializes both the phase and the action. In particular,
            // BONDED -> NONE during registration must not leave a new bond in a GATT phase.
            int bond = platform.bondState();
            if (bond != NONE && bond != BONDING && bond != BONDED) {
                fail("bond_state_unknown");
                return;
            }
            state.markGattReady(gattGeneration);
            state.beginPairing(requestId, gattGeneration, bond);
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
            if (!active || !waitingForBond) return;
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
        if (!waitingForBond) return;
        if (bond == BONDED) bonded();
        else if (bond == BONDING) state.onBonding();
        else if (bond == NONE && previous == BONDING) fail("bond_rejected");
        else if (bond == NONE && previous == BONDED && state.isWaitingForBond()
                && state.phase() == BirdBoxSecurityWriteStateMachine.Phase.SYSTEM_BOND_WAITING) {
            // The stack reported BONDING earlier in this attempt and then rolled the bond
            // back; that is a lost bond, not a stale pre-createBond broadcast.
            fail("bond_lost_during_bonding");
        }
        else if (bond != NONE && bond != BONDING) fail("bond_state_unknown");
    }

    void timeout(long candidate) {
        if (!owns(candidate) || !waitingForBond) return;
        fail("bond_timeout");
    }

    void cancel() {
        active = false;
        waitingForBond = false;
        platform.cancelBondTimeout();
    }

    private void bonded() {
        if (!active || !waitingForBond) return;
        waitingForBond = false;
        platform.cancelBondTimeout();
        // Reuse only applies to a bond completed during this attempt: the ordinary
        // GATT that carried the pairing often survives the system bond, and tearing
        // it down for a second dial left the rebuild hanging (MIS-AL00 161410).
        // An attempt that entered already BONDED keeps the controlled rebuild path.
        final boolean reuse = state.isWaitingForBond() && platform.gattUsable();
        if (state.phase() != BirdBoxSecurityWriteStateMachine.Phase.BONDED_RECOVERING_GATT) {
            state.onBonded(reuse);
        }
        platform.event("system_bond_result", "bonded");
        if (reuse) {
            platform.event("gatt_rebuild_decision", "reuse_live_gatt");
            platform.restoreNotificationsAfterBond();
            return;
        }
        platform.event("gatt_rebuild_decision", "rebuild_required");
        platform.rebuildGatt();
    }

    private void fail(String code) {
        if (!active) return;
        active = false;
        waitingForBond = false;
        platform.cancelBondTimeout();
        state.failAttempt(code.equals("bond_timeout")
                ? BirdBoxSecurityWriteStateMachine.Failure.PAIRING_TIMEOUT
                : BirdBoxSecurityWriteStateMachine.Failure.PAIRING_REJECTED);
        platform.event("system_bond_result", code);
        platform.fail(code);
    }
}
