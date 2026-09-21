package deckers.thibault.aves;

import java.util.Arrays;
import java.util.Locale;

/** Produces a bounded, structurally useful scan record without retaining payload secrets. */
final class BirdBoxScanRecordRedactor {
    static final int MAX_RECORD_BYTES = 512;

    private BirdBoxScanRecordRedactor() {}

    static String redactedHex(byte[] value) {
        final byte[] redacted = redact(value);
        final StringBuilder result = new StringBuilder(redacted.length * 2);
        for (byte item : redacted) {
            result.append(String.format(Locale.ROOT, "%02x", item & 0xff));
        }
        return result.toString();
    }

    static byte[] redact(byte[] value) {
        final byte[] result = Arrays.copyOf(value, Math.min(value.length, MAX_RECORD_BYTES));
        int offset = 0;
        while (offset < result.length) {
            final int fieldLength = result[offset] & 0xff;
            if (fieldLength == 0) break;
            final int typeOffset = offset + 1;
            if (typeOffset >= result.length) break;
            final int type = result[typeOffset] & 0xff;
            final int dataOffset = typeOffset + 1;
            final int fieldEnd = Math.min(offset + fieldLength + 1, result.length);
            final int visibleBytes = visiblePayloadBytes(type, fieldEnd - dataOffset);
            for (int index = dataOffset + visibleBytes; index < fieldEnd; index++) {
                result[index] = 0;
            }
            if (offset + fieldLength + 1 <= offset) break;
            offset += fieldLength + 1;
        }
        return result;
    }

    private static int visiblePayloadBytes(int type, int available) {
        // Flags, service UUID lists, local names, TX power and appearance are
        // required to diagnose split advertisement/scan-response callbacks.
        if (type == 0x01
                || (type >= 0x02 && type <= 0x07)
                || type == 0x08
                || type == 0x09
                || type == 0x0a
                || type == 0x19) {
            return available;
        }
        // Keep only the identifier prefix for service/manufacturer data. The
        // remaining application payload is zeroed while AD lengths and types
        // remain parseable.
        if (type == 0xff || type == 0x16) return Math.min(2, available);
        if (type == 0x20) return Math.min(4, available);
        if (type == 0x21) return Math.min(16, available);
        return 0;
    }
}
