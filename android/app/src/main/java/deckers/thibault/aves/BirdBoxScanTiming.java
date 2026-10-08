package deckers.thibault.aves;

/** Timeout policy shared by the Android BLE bridge and its framework-free tests. */
final class BirdBoxScanTiming {
    static final long DEFAULT_TIMEOUT_MS = 10000L;
    static final long MIN_REQUESTED_TIMEOUT_MS = 1000L;
    static final long MIN_FALLBACK_TIMEOUT_MS = 15000L;

    private BirdBoxScanTiming() {}

    static long effectiveTimeoutMs(boolean strategyFallbackEnabled, Integer requestedTimeoutMs) {
        final long requested = requestedTimeoutMs == null
                ? DEFAULT_TIMEOUT_MS
                : Math.max(MIN_REQUESTED_TIMEOUT_MS, requestedTimeoutMs.longValue());
        return strategyFallbackEnabled
                ? Math.max(MIN_FALLBACK_TIMEOUT_MS, requested)
                : requested;
    }
}
