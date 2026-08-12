import 'package:aves/bird_companion/app/bird_companion_app.dart';
import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('first install and unavailable saved device start on device tab', () {
    expect(initialBirdTabFor(const DeviceSessionState()), 2);
    expect(
      initialBirdTabFor(
        DeviceSessionState(
          device: DeviceConnection(
            id: 'box-1',
            name: 'K7',
            baseUri: Uri.parse('http://192.168.7.1'),
            networkMode: NetworkMode.hotspot,
          ),
        ),
      ),
      2,
    );
  });

  test('restored connected session starts directly on album tab', () {
    expect(
      initialBirdTabFor(
        DeviceSessionState(
          phase: DeviceSessionPhase.connected,
          device: DeviceConnection(
            id: 'box-1',
            name: 'K7',
            baseUri: Uri.parse('http://192.168.7.1'),
            networkMode: NetworkMode.hotspot,
          ),
        ),
      ),
      0,
    );
  });
}
