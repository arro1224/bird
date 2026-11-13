import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_job_models.dart';
import 'package:aves/bird_companion/features/smart_follow/domain/smart_follow_models.dart';

/// A grouped history entry is either a real ordinary copy or an authoritative
/// parent session. Never manufacture a copy_job_id from a session ID.
class GroupedCopyHistoryItem {
  GroupedCopyHistoryItem.fromJson(Map<String, dynamic> json)
      : kind = ProtocolValidation.requiredId(json, 'kind'),
        copy = json['kind'] == 'copy' ? CopyJobListItem.fromJson(json) : null,
        session = json['kind'] == 'smart_follow' && json['data'] is Map
            ? SmartFollowSession.fromJson(Map<String, dynamic>.from(json['data'] as Map)) : null {
    if (kind != 'copy' && kind != 'smart_follow') throw const ProtocolCompatibilityException('kind', '不支持的复制历史类型');
    if (kind == 'smart_follow' && (session == null || session!.sessionId != json['session_id'])) {
      throw const ProtocolCompatibilityException('session_id', '分组历史与会话归属不一致');
    }
  }
  final String kind;
  final CopyJobListItem? copy;
  final SmartFollowSession? session;
  String get key => '$kind:${session?.sessionId ?? copy!.copyJobId}';
}

class GroupedCopyHistoryPage {
  GroupedCopyHistoryPage.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    final more = json['has_more'];
    final cursor = json['next_cursor'];
    if (raw is! List || more is! bool || (more && (cursor is! String || cursor.isEmpty))) {
      throw const ProtocolCompatibilityException('items', '分组任务历史或分页不完整');
    }
    items = List.unmodifiable(raw.map((item) {
      if (item is! Map) throw const ProtocolCompatibilityException('items', '分组历史必须是对象');
      return GroupedCopyHistoryItem.fromJson(Map<String, dynamic>.from(item));
    }));
    hasMore = more;
    nextCursor = cursor is String ? cursor : null;
  }
  late final List<GroupedCopyHistoryItem> items;
  late final bool hasMore;
  late final String? nextCursor;
}

class SmartFollowSessionPage {
  SmartFollowSessionPage.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    final more = json['has_more'];
    final cursor = json['next_cursor'];
    if (raw is! List || more is! bool || (more && (cursor is! String || cursor.isEmpty))) {
      throw const ProtocolCompatibilityException('items', '会话列表或分页不完整');
    }
    items = List.unmodifiable(raw.map((item) {
      if (item is! Map) throw const ProtocolCompatibilityException('items', '会话必须是对象');
      return SmartFollowSession.fromJson(Map<String, dynamic>.from(item));
    }));
    hasMore = more;
    nextCursor = cursor is String ? cursor : null;
  }
  late final List<SmartFollowSession> items;
  late final bool hasMore;
  late final String? nextCursor;
}

class SmartFollowFileItem {
  SmartFollowFileItem.fromJson(Map<String, dynamic> json)
      : itemId = ProtocolValidation.requiredId(json, 'item_id'),
        fileId = ProtocolValidation.requiredId(json, 'file_id'),
        name = ProtocolValidation.requiredId(json, 'name'),
        state = ProtocolValidation.requiredId(json, 'state'),
        attemptCount = ProtocolValidation.nonNegativeInt(json, 'attempt_count'),
        errorCode = json['error_code'] as String?,
        errorMessage = json['error_message'] as String?,
        targetRelativePath = json['target_relative_path'] as String?;

  final String itemId, fileId, name, state;
  final int attemptCount;
  final String? errorCode, errorMessage, targetRelativePath;
  String get stateLabel => stateLabels[state] ?? '未知状态（$state）';
  static const stateLabels = {
    'queued': '排队中', 'copying': '复制中', 'retry_wait': '等待重试',
    'blocked': '受阻待处理', 'copied': '已复制', 'skipped_conflict': '同名跳过',
    'failed': '复制失败', 'not_applicable': '不适用', 'stopped': '已停止未复制',
  };
}

class SmartFollowFilePage {
  const SmartFollowFilePage({required this.items, required this.hasMore, this.nextCursor});
  final List<SmartFollowFileItem> items;
  final bool hasMore;
  final String? nextCursor;

  factory SmartFollowFilePage.fromJson(Map<String, dynamic> json) {
    final list = json['items'];
    final hasMore = json['has_more'];
    final cursor = json['next_cursor'];
    if (list is! List || hasMore is! bool || (hasMore && (cursor is! String || cursor.trim().isEmpty))) {
      throw const ProtocolCompatibilityException('items', '文件明细或分页信息不完整');
    }
    return SmartFollowFilePage(
      items: List.unmodifiable(list.map((item) {
        if (item is! Map) throw const ProtocolCompatibilityException('items', '文件项必须是对象');
        return SmartFollowFileItem.fromJson(Map<String, dynamic>.from(item));
      })),
      hasMore: hasMore,
      nextCursor: cursor is String && cursor.isNotEmpty ? cursor : null,
    );
  }
}
