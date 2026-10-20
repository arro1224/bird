import 'package:dio/dio.dart';

extension ConnectionCancellation on CancelToken {
  void throwIfCancellationRequested() {
    if (isCancelled) throw cancelError!;
  }
}
