import 'package:aves/bird_companion/core/session/client_identity_store.dart';
import 'package:aves/bird_companion/features/connection/domain/request_id_factory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('installation client id is stable and independent from a device', () async {
    final ids = _SequenceRequestIdFactory([
      'a870bcb1-d423-4d66-96f7-f809ce786543',
      '550e8400-e29b-41d4-a716-446655440000',
    ]);
    final store = MemoryClientIdentityStore(idFactory: ids);

    final first = await store.readOrCreate();
    final second = await store.readOrCreate();

    expect(first, second);
    expect(isUuidV4(first), isTrue);

    await store.clear();
    expect(await store.readOrCreate(), isNot(first));
  });

  test('invalid persisted client id is replaced with UUID v4', () async {
    final store = MemoryClientIdentityStore(
      initialValue: 'bbx-device-id-is-not-an-installation-id',
      idFactory: _SequenceRequestIdFactory([
        'a870bcb1-d423-4d66-96f7-f809ce786543',
      ]),
    );

    expect(
      await store.readOrCreate(),
      'a870bcb1-d423-4d66-96f7-f809ce786543',
    );
  });
}

final class _SequenceRequestIdFactory implements RequestIdFactory {
  _SequenceRequestIdFactory(this._values);

  final List<String> _values;
  var _index = 0;

  @override
  String create() => _values[_index++];
}
