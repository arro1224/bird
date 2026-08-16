import 'package:aves/bird_companion/app/bird_companion_app.dart';
import 'package:aves/bird_companion/app/app_shell.dart';
import 'package:aves/bird_companion/app/bird_route_args.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/features/connection/presentation/connection_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('users without device history start in initial device setup', () {
    final home = birdStartupHome(const DeviceSessionState());

    expect(home, isA<ConnectionPage>());
    expect((home as ConnectionPage).entryMode, ConnectionEntryMode.initialSetup);
  });

  test('users with a connected saved device start in the album', () {
    final home = birdStartupHome(
      DeviceSessionState(
        phase: DeviceSessionPhase.connected,
        device: _savedDevice,
      ),
    );

    expect(home, isA<BirdAppShell>());
    expect((home as BirdAppShell).initialIndex, 0);
  });

  test('users with an offline saved device still start in the album', () {
    final home = birdStartupHome(
      DeviceSessionState(
        phase: DeviceSessionPhase.disconnected,
        device: _savedDevice,
      ),
    );

    expect(home, isA<BirdAppShell>());
    expect((home as BirdAppShell).initialIndex, 0);
  });
}

final _savedDevice = DeviceConnection(
  id: 'saved-k7',
  name: '拍鸟伴侣 K7',
  baseUri: Uri.parse('http://192.168.1.7:8787'),
  networkMode: NetworkMode.lan,
  isPaired: true,
);
