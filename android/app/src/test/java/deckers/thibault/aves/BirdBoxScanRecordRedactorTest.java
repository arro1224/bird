package deckers.thibault.aves;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;

import org.junit.Test;

public final class BirdBoxScanRecordRedactorTest {
    @Test
    public void preservesNamesAndUuidsButZerosManufacturerPayload() {
        final byte[] record = new byte[] {
                3, 0x03, 0x01, 0x02,
                4, 0x09, 'B', 'o', 'x',
                6, (byte) 0xff, 0x34, 0x12, 0x55, 0x66, 0x77
        };

        assertArrayEquals(
                new byte[] {
                        3, 0x03, 0x01, 0x02,
                        4, 0x09, 'B', 'o', 'x',
                        6, (byte) 0xff, 0x34, 0x12, 0, 0, 0
                },
                BirdBoxScanRecordRedactor.redact(record)
        );
        assertEquals(
                "030301020409426f7806ff3412000000",
                BirdBoxScanRecordRedactor.redactedHex(record)
        );
    }

    @Test
    public void boundsExtendedAdvertisements() {
        final byte[] record = new byte[700];
        assertEquals(
                BirdBoxScanRecordRedactor.MAX_RECORD_BYTES * 2,
                BirdBoxScanRecordRedactor.redactedHex(record).length()
        );
    }
}
