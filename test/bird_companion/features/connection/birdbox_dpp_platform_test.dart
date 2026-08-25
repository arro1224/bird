import 'package:aves/bird_companion/features/connection/data/platform/birdbox_dpp_platform.dart';
import 'package:aves/bird_companion/features/connection/domain/provisioning_error.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('bird_companion/birdbox_dpp/test');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('maps Android capability and launch results without logging the URI', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return switch (call.method) {
        'checkCapability' => <String, Object>{
          'apiLevelSupported': true,
          'easyConnectSupported': true,
          'activityAvailable': true,
        },
        'launchEasyConnect' => <String, Object>{
          'outcome': 'system_accepted',
          'systemResultCode': '-1',
        },
        'clearTransientUri' => null,
        _ => throw MissingPluginException(),
      };
    });
    final platform = MethodChannelBirdBoxDppPlatform(channel: channel);

    final capability = await platform.checkCapability();
    final result = await platform.launchEasyConnect(
      Uri.parse('DPP:K:TEST_PUBLIC_BOOTSTRAP_KEY;C:81/1;;'),
    );
    await platform.clearTransientUri();

    expect(capability.supported, isTrue);
    expect(result.outcome, DppLaunchOutcome.systemAccepted);
    expect(result.systemResultCode, '-1');
    expect(calls, [
      'checkCapability',
      'launchEasyConnect',
      'clearTransientUri',
    ]);
  });

  test('rejects malformed DPP URI before invoking Android', () async {
    var invoked = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      invoked = true;
      return null;
    });
    final platform = MethodChannelBirdBoxDppPlatform(channel: channel);

    await expectLater(
      platform.launchEasyConnect(Uri.parse('https://example.test/not-dpp')),
      throwsA(
        isA<ProvisioningException>().having(
          (error) => error.code,
          'code',
          ProvisioningErrorCode.systemDppInvalidUri,
        ),
      ),
    );
    expect(invoked, isFalse);
  });

  test('maps unavailable Android channel to phone unsupported', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) => throw MissingPluginException(),
    );
    final platform = MethodChannelBirdBoxDppPlatform(channel: channel);

    await expectLater(
      platform.checkCapability(),
      throwsA(
        isA<ProvisioningException>().having(
          (error) => error.code,
          'code',
          ProvisioningErrorCode.phoneDppNotSupported,
        ),
      ),
    );
  });
}
