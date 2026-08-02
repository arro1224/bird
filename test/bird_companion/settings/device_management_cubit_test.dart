import 'dart:async';

import 'package:aves/bird_companion/core/models/device_models.dart';
import 'package:aves/bird_companion/core/session/device_session.dart';
import 'package:aves/bird_companion/core/session/device_session_cubit.dart';
import 'package:aves/bird_companion/features/connection/domain/connection_repository.dart';
import 'package:aves/bird_companion/features/settings/presentation/device_management_cubit.dart';
import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('device search exits searching state after timeout', () async {
    final repository = _ConnectionRepository(
      discover: Completer<List<DeviceConnection>>().future,
    );
    final session = _TestSession();
    final cubit = DeviceManagementCubit(
      repository,
      session,
      searchTimeout: const Duration(milliseconds: 10),
    );
    addTearDown(cubit.close);
    addTearDown(session.close);

    await cubit.search();

    expect(cubit.state.searching, isFalse);
    expect(cubit.state.error, isA<TimeoutException>());
  });

  test('cancelled search cannot leave the page searching', () async {
    final completer = Completer<List<DeviceConnection>>();
    final session = _TestSession();
    final cubit = DeviceManagementCubit(
      _ConnectionRepository(discover: completer.future),
      session,
    );
    addTearDown(cubit.close);
    addTearDown(session.close);

    final search = cubit.search();
    await Future<void>.delayed(Duration.zero);
    cubit.cancelSearch();
    completer.complete(const []);
    await search;

    expect(cubit.state.searching, isFalse);
  });

  test('selected discovery result connects through the shared session', () async {
    final device = _device('box-b');
    final session = _TestSession();
    final repository = _ConnectionRepository(
      discover: Future.value([device]),
      connectStatus: DeviceStatus(
        connection: device,
        card: const CardStatus(inserted: true, readable: true),
      ),
    );
    final cubit = DeviceManagementCubit(repository, session);
    addTearDown(cubit.close);
    addTearDown(session.close);

    expect(await cubit.connect(device), isTrue);
    expect(session.connectedDevice?.id, 'box-b');
    expect(cubit.state.connectingDeviceId, isNull);
  });
}

class _ConnectionRepository implements ConnectionRepository {
  _ConnectionRepository({
    required Future<List<DeviceConnection>> discover,
    this.connectStatus,
  }) : discoverFuture = discover;

  final Future<List<DeviceConnection>> discoverFuture;
  final DeviceStatus? connectStatus;

  @override
  Future<List<DeviceConnection>> discover() => discoverFuture;

  @override
  Future<List<DeviceConnection>> recentDevices() async => const [];

  @override
  Future<DeviceStatus> connect(
    Uri baseUri, {
    required NetworkMode networkMode,
    CancelToken? cancelToken,
  }) async => connectStatus!;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSession extends Cubit<DeviceSessionState> implements DeviceSessionCubit {
  _TestSession() : super(const DeviceSessionState());

  DeviceConnection? connectedDevice;

  @override
  Future<void> setConnectedFromStatus(dynamic status) async {
    connectedDevice = (status as DeviceStatus).connection;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DeviceConnection _device(String id) => DeviceConnection(
  id: id,
  name: 'Bird Box $id',
  baseUri: Uri.parse('http://192.168.4.1:8080'),
  networkMode: NetworkMode.hotspot,
);
