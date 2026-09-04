import 'dart:async';

import 'package:aves/bird_companion/features/connection/data/platform/birdbox_wifi_platform.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('bird_companion/birdbox_wifi/test');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

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
