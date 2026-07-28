import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/features/device/presentation/widgets/device_status_pills.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('设备状态点击区域在紧凑宽度下不少于 48dp', (tester) async {
    final connection = DeviceConnection(
      id: 'box-a',
      name: 'K7',
      baseUri: Uri.parse('http://127.0.0.1'),
      networkMode: NetworkMode.manual,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: DeviceStatusPills(
              status: DeviceStatus(
                connection: connection,
                card: const CardStatus(inserted: true, readable: true),
                batteryPercent: 78,
                storageFreeBytes: 338 * 1024 * 1024 * 1024,
              ),
              session: DeviceSessionState(
                phase: DeviceSessionPhase.connected,
                device: connection,
              ),
              onTap: () {},
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(InkWell)).height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });
}
