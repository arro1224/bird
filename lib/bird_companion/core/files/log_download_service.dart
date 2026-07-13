import 'dart:io';
import 'dart:typed_data';

import 'package:aves/bird_companion/core/network/api_client.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

class DownloadedLog {
  const DownloadedLog(this.file);
  final File file;
}

/// Downloads a box-produced diagnostic archive into this application's private
/// cache. The returned path is valid on a physical Android device and can later
/// be handed to a share/save action without exposing a box-local URL to users.
class LogDownloadService {
  LogDownloadService(this._client, {Dio? dio}) : _dio = dio ?? Dio();
  final ApiClient _client;
  final Dio _dio;

  Future<DownloadedLog> download(String downloadUrl) async {
    final url = Uri.tryParse(downloadUrl);
    final base = _client.baseUri;
    final resolved = url == null ? null : (url.hasScheme ? url : base?.resolveUri(url));
    if (resolved == null) throw ArgumentError('盒子未返回有效的日志下载地址。');
    final response = await _dio.getUri<List<int>>(resolved, options: Options(responseType: ResponseType.bytes));
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) throw StateError('下载的日志文件为空。');
    final dir = await getTemporaryDirectory();
    final filename = _filename(response.headers.value('content-disposition'));
    final file = File('${dir.path}${Platform.pathSeparator}$filename');
    await file.writeAsBytes(Uint8List.fromList(bytes), flush: true);
    return DownloadedLog(file);
  }

  String _filename(String? header) {
    final match = RegExp(r'filename="?([^";]+)').firstMatch(header ?? '');
    return match?.group(1) ?? 'bird-companion-log-${DateTime.now().millisecondsSinceEpoch}.txt';
  }
}
