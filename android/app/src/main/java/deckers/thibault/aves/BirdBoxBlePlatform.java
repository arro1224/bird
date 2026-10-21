package deckers.thibault.aves;

import android.Manifest;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothGatt;
import android.bluetooth.BluetoothGattCallback;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.IntentFilter;
import android.os.Build;
import androidx.annotation.RequiresPermission;

/** Small injectable Android boundary. Callback delivery is queued by the channel's Handler. */
class BirdBoxBlePlatform {
    @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
    int bondState(BluetoothDevice device) { return device.getBondState(); }
    @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
    boolean createBond(BluetoothDevice device) { return device.createBond(); }
    @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
    BluetoothGatt connect(Context context, BluetoothDevice device, BluetoothGattCallback callback) {
        return device.connectGatt(context, false, callback, BluetoothDevice.TRANSPORT_LE);
    }
    void register(Context context, BroadcastReceiver receiver, IntentFilter filter) {
        if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED);
        else context.registerReceiver(receiver, filter);
    }
    void unregister(Context context, BroadcastReceiver receiver) { context.unregisterReceiver(receiver); }
}
