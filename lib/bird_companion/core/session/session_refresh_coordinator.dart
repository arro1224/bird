import 'dart:async';

class SessionRefreshCoordinator {
  final _controller = StreamController<int>.broadcast();
  var _generation = 0;

  Stream<int> get changes => _controller.stream;
  int get generation => _generation;

  void requestRefresh() => _controller.add(++_generation);
  Future<void> dispose() => _controller.close();
}
