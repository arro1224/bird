bool isBatchTagAction(String operation) => operation == 'add_tags' || operation == 'remove_tags';

class BatchTagActionResult {
  BatchTagActionResult.fromResponse(List<String> ids, Map<String, dynamic> response) {
    final requested = ids.toSet();
    final reportedFailures = <String, String>{};
    for (final entry in (response['failed'] as List? ?? const []).whereType<Map>()) {
      final id = entry['file_id']?.toString();
      if (id != null && requested.contains(id)) {
        reportedFailures[id] = entry['reason']?.toString() ?? '操作失败';
      }
    }
    final reportedSuccesses = (response['succeeded_ids'] as List? ?? const []).map((id) => id.toString()).toSet();
    succeededIds = [
      for (final id in requested)
        if (reportedSuccesses.contains(id) && !reportedFailures.containsKey(id)) id,
    ];
    final succeeded = succeededIds.toSet();
    failed = {
      for (final id in requested)
        if (!succeeded.contains(id)) id: reportedFailures[id] ?? '盒子未确认标签修改',
    };
  }

  late final List<String> succeededIds;
  late final Map<String, String> failed;
}
