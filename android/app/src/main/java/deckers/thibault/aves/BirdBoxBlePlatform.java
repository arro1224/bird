package deckers.thibault.aves;

import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothGatt;
import android.bluetooth.BluetoothGattCallback;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.IntentFilter;
import android.os.Build;

/** Small injectable Android boundary. Callback delivery is queued by the channel's Handler. */
class BirdBoxBlePlatform {
    int bondState(BluetoothDevice device) { return device.getBondState(); }
    boolean createBond(BluetoothDevice device) { return device.createBond(); }
    BluetoothGatt connect(Context context, BluetoothDevice device, BluetoothGattCallback callback) {
        return Build.VERSION.SDK_INT >= 23
                ? device.connectGatt(context, false, callback, BluetoothDevice.TRANSPORT_LE)
                : device.connectGatt(context, false, callback);
    }
    void register(Context context, BroadcastReceiver receiver, IntentFilter filter) {
        if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED);
        else context.registerReceiver(receiver, filter);
    }
    void unregister(Context context, BroadcastReceiver receiver) { context.unregisterReceiver(receiver); }
}
