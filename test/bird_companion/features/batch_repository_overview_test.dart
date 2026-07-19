import 'package:aves/bird_companion/core/models/batch_models.dart';
import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:aves/bird_companion/features/batches/data/batch_api.dart';
import 'package:aves/bird_companion/features/batches/data/batch_repository_impl.dart';
import 'package:aves/bird_companion/features/batches/domain/batch_page.dart';
import 'package:flutter_test/flutter_test.dart';

final _active = BatchSummary(
  id: 'active',
  name: '活动批次',
  createdAt: DateTime.utc(2026, 7, 15),
  totalFiles: 10,
  analyzedCount: 8,
  reviewCount: 2,
  keepCount: 1,
  discardCount: 0,
  pendingCopyCount: 1,
  copyState: 'pending',
);

final _latest = BatchSummary(
  id: 'latest',
  name: '最近批次',
  createdAt: DateTime.utc(2026, 7, 14),
  totalFiles: 20,
  analyzedCount: 20,
  reviewCount: 0,
  keepCount: 5,
  discardCount: 2,
  pendingCopyCount: 3,
  copyState: 'pending',
);

class _BatchApi extends BatchApi {
  _BatchApi({this.active, this.currentError, this.pageError, this.items = const []}) : super(ApiClient());

  final BatchSummary? active;
  final Object? currentError;
  final Object? pageError;
  final List<BatchSummary> items;

  @override
  Future<BatchSummary?> current() async {
    if (currentError != null) throw currentError!;
    return active;
  }

  @override
  Future<BatchPage> page({String? state, String? sort, String? cursor}) async {
    if (pageError != null) throw pageError!;
    expect(sort, 'created_at_desc');
    return BatchPage(items: items, hasMore: false);
  }
}

void main() {
  test('批次概览同时保留活动批次和最近批次语义', () async {
    final overview = await BatchRepositoryImpl(_BatchApi(active: _active, items: [_latest])).overview();

    expect(overview.active, _active);
    expect(overview.latest, _latest);
    expect(overview.primary, _active);
    expect(overview.primaryIsActive, isTrue);
  });

  test('没有活动批次时使用最近批次作为设备页摘要', () async {
    final overview = await BatchRepositoryImpl(_BatchApi(items: [_latest])).overview();

    expect(overview.active, isNull);
    expect(overview.primary, _latest);
    expect(overview.primaryIsActive, isFalse);
  });

  test('活动批次接口失败不影响最近批次回退', () async {
    final overview = await BatchRepositoryImpl(_BatchApi(currentError: StateError('current failed'), items: [_latest])).overview();

    expect(overview.active, isNull);
    expect(overview.primary, _latest);
  });

  test('最近批次接口失败时仍返回已加载的活动批次', () async {
    final overview = await BatchRepositoryImpl(_BatchApi(active: _active, pageError: StateError('page failed'))).overview();

    expect(overview.primary, _active);
    expect(overview.primaryIsActive, isTrue);
  });
}
