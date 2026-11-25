package deckers.thibault.aves;

import static org.junit.Assert.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.pm.PackageManager;
import android.location.LocationManager;
import android.net.wifi.SupplicantState;
import android.net.wifi.WifiInfo;
import android.net.wifi.WifiManager;
import android.os.Build;
import java.util.Map;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/** Exercises the production read-only channel; no hotspot or RF detection claims. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = {27, 31}, manifest = Config.NONE)
public final class BirdBoxWifiSsidTest {
    private final Activity activity = mock(Activity.class);
    private final Context application = mock(Context.class);
    private final WifiManager manager = mock(WifiManager.class);
    private final WifiInfo info = mock(WifiInfo.class);
    private final LocationManager location = mock(LocationManager.class);
    private BirdBoxWifiChannel channel;
    private boolean fine = true, coarse = true;

    @Before public void setUp() {
        when(activity.getApplicationContext()).thenReturn(application);
        when(application.getSystemService(Context.WIFI_SERVICE)).thenReturn(manager);
        when(activity.getSystemService(Context.LOCATION_SERVICE)).thenReturn(location);
        when(activity.checkPermission(anyString(), anyInt(), anyInt())).thenAnswer(invocation -> {
            String permission = invocation.getArgument(0);
            boolean granted = Manifest.permission.ACCESS_FINE_LOCATION.equals(permission) ? fine : coarse;
            return granted ? PackageManager.PERMISSION_GRANTED : PackageManager.PERMISSION_DENIED;
        });
        if (Build.VERSION.SDK_INT >= 28) when(location.isLocationEnabled()).thenReturn(true);
        when(location.isProviderEnabled(anyString())).thenReturn(true);
        when(manager.getConnectionInfo()).thenReturn(info);
        when(info.getNetworkId()).thenReturn(7);
        when(info.getSupplicantState()).thenReturn(SupplicantState.COMPLETED);
        when(info.getSSID()).thenReturn("\"Phone-network\"");
        channel = new BirdBoxWifiChannel(activity, mock(BinaryMessenger.class));
    }

    private Map<?, ?> read() {
        final Object[] value = {null};
        channel.onMethodCall(new MethodCall("currentSsid", null), new MethodChannel.Result() {
            @Override public void success(Object result) { value[0] = result; }
            @Override public void error(String code, String message, Object details) { fail(code); }
            @Override public void notImplemented() { fail("currentSsid must be implemented"); }
        });
        assertTrue(value[0] instanceof Map);
        return (Map<?, ?>) value[0];
    }

    @Test public void completedAssociationReturnsOnlyReadableName() {
        Map<?, ?> result = read();
        assertEquals("Phone-network", result.get("ssid"));
        assertNull(result.get("reason"));
        verify(activity, never()).startActivity(any());
        verify(manager, never()).startScan();
    }

    @Test public void disconnectedStaleNameIsNeverUsedAsCurrentName() {
        when(info.getSupplicantState()).thenReturn(SupplicantState.DISCONNECTED);
        Map<?, ?> result = read();
        assertNull(result.get("ssid"));
        assertEquals("not_connected", result.get("reason"));
    }

    @Test public void missingNetworkIdDoesNotProvePhoneHotspot() {
        when(info.getNetworkId()).thenReturn(-1);
        assertEquals("not_connected", read().get("reason"));
    }

    @Test public void absentConnectionDoesNotProvePhoneHotspot() {
        when(manager.getConnectionInfo()).thenReturn(null);
        assertEquals("not_connected", read().get("reason"));
    }

    @Test public void unknownNameWithAssociationRemainsUnavailable() {
        when(info.getSSID()).thenReturn("<unknown ssid>");
        assertEquals("unavailable", read().get("reason"));
    }

    @Test public void deniedLocationDoesNotReadWifiOrOpenPermissionUi() {
        fine = false; coarse = false;
        assertEquals("permission_denied", read().get("reason"));
        verify(manager, never()).getConnectionInfo();
        verify(activity, never()).requestPermissions(any(), anyInt());
    }

    @Test public void approximatePermissionRemainsExplicit() {
        fine = false;
        assertEquals("permission_approximate", read().get("reason"));
    }

    @Test public void locationDisabledRemainsExplicit() {
        if (Build.VERSION.SDK_INT >= 28) when(location.isLocationEnabled()).thenReturn(false);
        when(location.isProviderEnabled(anyString())).thenReturn(false);
        assertEquals("location_disabled", read().get("reason"));
        verify(manager, never()).getConnectionInfo();
    }

    @Test public void permissionRevokedDuringReadIsSafe() {
        when(manager.getConnectionInfo()).thenThrow(new SecurityException("synthetic"));
        assertEquals("permission_denied", read().get("reason"));
    }
}
