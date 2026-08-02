import 'dart:io';
import 'dart:typed_data';

import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:path_provider/path_provider.dart';

class DownloadedLog {
  const DownloadedLog(this.file);
  final File file;
}

/// Downloads a box-produced diagnostic archive to a persistent, user-visible
/// downloads/documents location when the platform exposes one.
class LogDownloadService {
  LogDownloadService(
    this._client, {
    this.directoryProvider,
  });
  final ApiClient _client;
  final Future<Directory> Function()? directoryProvider;

  Future<DownloadedLog> download(String downloadUrl) async {
    final url = Uri.tryParse(downloadUrl);
    final base = _client.baseUri;
    final resolved = url == null ? null : (url.hasScheme ? url : base?.resolveUri(url));
    if (resolved == null) throw ArgumentError('盒子未返回有效的日志下载地址。');
    final response = await _client.downloadSignedBytes(resolved);
    final bytes = response.bytes;
    final dir = await directoryProvider?.call() ?? await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    final filename = _filename(response.contentDisposition);
    final file = File('${dir.path}${Platform.pathSeparator}${DateTime.now().millisecondsSinceEpoch}-$filename');
    await file.writeAsBytes(Uint8List.fromList(bytes), flush: true);
    return DownloadedLog(file);
  }

  Future<DownloadedLog> downloadWithRefresh(
    Future<String?> Function() requestSignedUrl,
  ) async {
    final first = await requestSignedUrl();
    if (first == null || first.isEmpty) {
      throw StateError('日志正在生成，请稍后重试。');
    }
    try {
      return await download(first);
    } on SignedAssetDownloadException catch (error) {
      if (!error.isExpired) rethrow;
      final refreshed = await requestSignedUrl();
      if (refreshed == null || refreshed.isEmpty) rethrow;
      return download(refreshed);
    }
  }

  String _filename(String? header) {
    final match = RegExp(r'filename="?([^";]+)').firstMatch(header ?? '');
    return match?.group(1) ?? 'bird-companion-log-${DateTime.now().millisecondsSinceEpoch}.txt';
  }
}
