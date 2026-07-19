import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Measures the actual on-disk image cache instead of estimating unrelated
/// Hive metadata. Missing/inaccessible cache directories are treated as empty.
class CacheMetricsService {
  Future<int> imageCacheBytes() async {
    try {
      final temporary = await getTemporaryDirectory();
      final directory = Directory('${temporary.path}${Platform.pathSeparator}libCachedImageData');
      if (!await directory.exists()) return 0;
      var bytes = 0;
      await for (final entity in directory.list(recursive: true, followLinks: false)) {
        if (entity is File) bytes += await entity.length();
      }
      return bytes;
    } on FileSystemException {
      return 0;
    }
  }
}
