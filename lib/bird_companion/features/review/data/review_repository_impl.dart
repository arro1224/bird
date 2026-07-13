import 'package:aves/bird_companion/core/models/review_models.dart';
import 'package:aves/bird_companion/features/review/data/review_api.dart';
import 'package:aves/bird_companion/features/review/domain/review_repository.dart';
import 'package:aves/bird_companion/core/network/api_exception.dart';
import 'package:aves/bird_companion/core/network/connectivity_monitor.dart';
import 'package:aves/bird_companion/core/storage/pending_operation_store.dart';
import 'package:aves/bird_companion/core/sync/pending_operation.dart';

class ReviewRepositoryImpl implements ReviewRepository {
  ReviewRepositoryImpl(this._api, this._connectivity, this._pending);
  final ReviewApi _api;
  final ConnectivityMonitor _connectivity;
  final PendingOperationStore _pending;
  @override
  Future<List<BirdGroup>> groups(String id) => _api.groups(id);
  @override
  Future<ReviewDetail> detail(String id) => _api.detail(id);
  @override
  Future<ReviewSaveResult> save(UserDecision v) async {
    try {
      if (!await _connectivity.hasNetwork) return _queue(v, '设备离线，修改将在重新连接后同步');
      await _api.save(v);
      return const ReviewSaveResult();
    } on ApiException catch (error) {
      if (error.statusCode == 409) return ReviewSaveResult(conflict: true, message: error.message);
      return _queue(v, '暂时无法连接盒子，修改已保存在本机');
    }
  }

  Future<ReviewSaveResult> _queue(UserDecision value, String message) async {
    final operation = PendingOperation(id: 'review-${value.fileId}-${DateTime.now().microsecondsSinceEpoch}', type: PendingOperationType.updateReview, payload: value.toJson(), createdAt: DateTime.now(), version: value.version);
    await _pending.save(operation);
    return ReviewSaveResult(queued: true, message: message);
  }
}
