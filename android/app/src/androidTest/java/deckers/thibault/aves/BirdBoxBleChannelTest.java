package deckers.thibault.aves;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import android.bluetooth.BluetoothGatt;

import androidx.test.ext.junit.runners.AndroidJUnit4;

import org.junit.Test;
import org.junit.runner.RunWith;

@RunWith(AndroidJUnit4.class)
public final class BirdBoxBleChannelTest {
    @Test
    public void classifiesAuthenticationAndEncryptionFailures() {
        assertTrue(BirdBoxBleChannel.isGattSecurityFailure(BluetoothGatt.GATT_INSUFFICIENT_AUTHENTICATION));
        assertTrue(BirdBoxBleChannel.isGattSecurityFailure(BluetoothGatt.GATT_INSUFFICIENT_ENCRYPTION));
        assertTrue(BirdBoxBleChannel.isGattSecurityFailure(BirdBoxBleChannel.GATT_INSUFFICIENT_ENCRYPTION_KEY_SIZE));
        assertEquals("ble_link_not_encrypted", BirdBoxBleChannel.gattErrorCode(BluetoothGatt.GATT_INSUFFICIENT_ENCRYPTION));
    }

    @Test
    public void keepsTransportFailuresSeparateFromSecurityFailures() {
        assertFalse(BirdBoxBleChannel.isGattSecurityFailure(BluetoothGatt.GATT_FAILURE));
        assertEquals("gatt_operation_failed", BirdBoxBleChannel.gattErrorCode(BluetoothGatt.GATT_FAILURE));
    }
}
