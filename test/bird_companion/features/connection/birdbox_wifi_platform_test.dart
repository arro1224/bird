import 'dart:async';

import 'package:aves/bird_companion/features/connection/data/platform/birdbox_wifi_platform.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('bird_companion/birdbox_wifi/test');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('N06 distinguishes an APK configuration error from permission denial', () async {
    var code = 'wifi_change_network_state_missing';
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'joinDirectAp') throw PlatformException(code: code);
      return null;
    });
    final platform = MethodChannelBirdBoxWifiPlatform(channel: channel, networkEvents: const Stream.empty());
    Future<WifiJoinResult> join() => platform.joinDirectAp(ssid: 'Exact-Box', passphrase: 'TEST_ONLY_PASSWORD', security: WifiSecurity.wpa2Personal);
    await expectLater(join(), throwsA(isA<ProvisioningException>()
      .having((error) => error.code, 'code', ProvisioningErrorCode.localNetworkPermissionMisconfigured)
      .having((error) => error.code.origin, 'origin', ProvisioningErrorOrigin.app)));
    code = 'wifi_permission_denied';
    await expectLater(join(), throwsA(isA<ProvisioningException>()
      .having((error) => error.code, 'code', ProvisioningErrorCode.localNetworkPermissionDenied)));
    await platform.dispose();
  });

  test('passes exact AP security and distinguishes unavailable from explicit cancellation', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'joinDirectAp' ? {'outcome': 'unavailable', 'errorCode': 'wifi_request_unavailable'} : null;
    });
    final platform = MethodChannelBirdBoxWifiPlatform(channel: channel, networkEvents: const Stream.empty());
    final result = await platform.joinDirectAp(ssid: 'Exact-Box', passphrase: 'TEST_ONLY_PASSWORD', security: WifiSecurity.wpa3Personal);
    expect(result.outcome, WifiJoinOutcome.unavailable);
    expect(calls.single.arguments['ssid'], 'Exact-Box');
    expect(calls.single.arguments['security'], 'wpa3_personal');
    await platform.releaseNetwork(reason: 'sta_connected');
    expect(calls.last.arguments, {'reason': 'sta_connected'});
    await platform.dispose();
  });

  test('reports native network loss and clears matching bound network', () async {
    final nativeEvents = StreamController<Object?>.broadcast(sync: true);
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    final platform = MethodChannelBirdBoxWifiPlatform(
      channel: channel,
      networkEvents: nativeEvents.stream,
    );
    const network = BirdBoxWifiNetwork(handle: '42', ssid: 'BirdBox-1234');
    await platform.bindProcessToNetwork(network);
    final lossFuture = platform.networkLosses.first;

    nativeEvents.add(<String, Object>{
      'type': 'lost',
      'handle': '42',
      'ssid': 'BirdBox-1234',
      'reason': 'network_lost',
    });

    final loss = await lossFuture;
    expect(loss.handle, '42');
    expect(loss.reason, 'network_lost');
    expect(platform.boundNetwork, isNull);
    await platform.dispose();
    await nativeEvents.close();
  });

  test('rejects malformed network events at the Dart boundary', () async {
    final nativeEvents = StreamController<Object?>.broadcast(sync: true);
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    final platform = MethodChannelBirdBoxWifiPlatform(
      channel: channel,
      networkEvents: nativeEvents.stream,
    );
    final errorExpectation = expectLater(
      platform.networkLosses,
      emitsError(isA<ProvisioningProtocolException>()),
    );

    nativeEvents.add(<String, Object>{'type': 'lost', 'handle': ''});

    await errorExpectation;
    await platform.dispose();
    await nativeEvents.close();
  });

  test('maps process binding failure to a retryable network switch error', () async {
    final nativeEvents = StreamController<Object?>.broadcast(sync: true);
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'bindProcessToNetwork') {
        throw PlatformException(code: 'wifi_bind_failed');
      }
      return null;
    });
    final platform = MethodChannelBirdBoxWifiPlatform(
      channel: channel,
      networkEvents: nativeEvents.stream,
    );

    await expectLater(
      platform.bindProcessToNetwork(const BirdBoxWifiNetwork(handle: '7', ssid: 'BirdBox-5678')),
      throwsA(
        isA<ProvisioningException>().having((error) => error.code, 'code', ProvisioningErrorCode.networkSwitchFailed).having((error) => error.retryable, 'retryable', isTrue),
      ),
    );

    await platform.dispose();
    await nativeEvents.close();
  });
}
