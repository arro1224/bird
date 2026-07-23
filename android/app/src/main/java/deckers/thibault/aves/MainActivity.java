package deckers.thibault.aves;

import android.content.Context;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;

import java.net.InetAddress;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public final class MainActivity extends FlutterActivity {
    private static final String DISCOVERY_CHANNEL = "bird_companion/device_discovery";

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), DISCOVERY_CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    if ("discover".equals(call.method)) {
                        discover(call, result);
                    } else {
                        result.notImplemented();
                    }
                });
    }

    private void discover(MethodCall call, MethodChannel.Result result) {
        final String serviceType = call.argument("serviceType");
        final Integer timeoutMs = call.argument("timeoutMs");
        if (serviceType == null || serviceType.isEmpty()) {
            result.error("invalid_service_type", "A service type is required.", null);
            return;
        }

        final NsdManager manager = (NsdManager) getSystemService(Context.NSD_SERVICE);
        if (manager == null) {
            result.error("nsd_unavailable", "Network service discovery is unavailable.", null);
            return;
        }

        final Handler handler = new Handler(Looper.getMainLooper());
        final List<Map<String, Object>> devices = new ArrayList<>();
        final Set<String> resolvedServices = new HashSet<>();
        final boolean[] finished = {false};
        final NsdManager.DiscoveryListener[] listener = new NsdManager.DiscoveryListener[1];

        final Runnable finish = () -> {
            if (finished[0]) return;
            finished[0] = true;
            try {
                manager.stopServiceDiscovery(listener[0]);
            } catch (IllegalArgumentException ignored) {
                // Discovery may have failed before it started.
            }
            result.success(devices);
        };

        listener[0] = new NsdManager.DiscoveryListener() {
            @Override public void onDiscoveryStarted(String type) {}

            @Override public void onServiceFound(NsdServiceInfo service) {
                if (finished[0] || !serviceType.equals(service.getServiceType())) return;
                final String key = service.getServiceName() + "@" + service.getServiceType();
                if (!resolvedServices.add(key)) return;
                manager.resolveService(service, new NsdManager.ResolveListener() {
                    @Override public void onResolveFailed(NsdServiceInfo ignored, int errorCode) {}

                    @Override public void onServiceResolved(NsdServiceInfo resolved) {
                        final InetAddress host = resolved.getHost();
                        final int port = resolved.getPort();
                        if (finished[0] || host == null || port < 1) return;
                        final Map<String, Object> device = new LinkedHashMap<>();
                        device.put("name", resolved.getServiceName());
                        device.put("host", host.getHostAddress());
                        device.put("port", port);
                        devices.add(device);
                    }
                });
            }

            @Override public void onServiceLost(NsdServiceInfo service) {}

            @Override public void onDiscoveryStopped(String type) {}

            @Override public void onStartDiscoveryFailed(String type, int errorCode) {
                finish.run();
            }

            @Override public void onStopDiscoveryFailed(String type, int errorCode) {
                finish.run();
            }
        };

        try {
            manager.discoverServices(serviceType, NsdManager.PROTOCOL_DNS_SD, listener[0]);
            handler.postDelayed(finish, timeoutMs == null ? 3000 : Math.max(timeoutMs, 1000));
        } catch (IllegalArgumentException error) {
            result.error("nsd_start_failed", error.getMessage(), null);
        }
    }
}
