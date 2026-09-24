package deckers.thibault.aves.virtualbirdbox;

import java.util.Locale;

final class Ble11ScenarioState {
    enum Scenario {
        SUCCESS,
        AUTO_BOND,
        FALLBACK_ONCE,
        DISCONNECT_ONCE;

        static Scenario parse(String value) {
            if (value == null) return SUCCESS;
            return switch (value.trim().toLowerCase(Locale.ROOT)) {
                case "success" -> SUCCESS;
                case "auto_bond" -> AUTO_BOND;
                case "fallback_once" -> FALLBACK_ONCE;
                case "disconnect_once" -> DISCONNECT_ONCE;
                default -> throw new IllegalArgumentException("Unsupported BLE-11 scenario: " + value);
            };
        }

        String wireValue() {
            return name().toLowerCase(Locale.ROOT);
        }
    }

    enum Action {
        ACCEPT,
        REJECT_SECURITY,
        DISCONNECT
    }

    private final Scenario scenario;
    private boolean injected;

    Ble11ScenarioState(Scenario scenario) {
        this.scenario = scenario;
    }

    Scenario scenario() {
        return scenario;
    }

    boolean requiresEncryptedPermission() {
        return scenario == Scenario.AUTO_BOND;
    }

    Action onCompleteMessage(boolean bonded) {
        if (scenario == Scenario.FALLBACK_ONCE) {
            if (!injected) {
                injected = true;
                return Action.REJECT_SECURITY;
            }
            return bonded ? Action.ACCEPT : Action.REJECT_SECURITY;
        }
        if (scenario == Scenario.DISCONNECT_ONCE && !injected) {
            injected = true;
            return Action.DISCONNECT;
        }
        return Action.ACCEPT;
    }

    boolean injected() {
        return injected;
    }
}
