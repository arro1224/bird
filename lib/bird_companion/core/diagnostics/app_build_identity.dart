import 'package:aves/bird_companion/features/connection/data/platform/birdbox_ble_diagnostic_file_platform.dart';
import 'package:package_info_plus/package_info_plus.dart';

final class AppBuildIdentity {
  AppBuildIdentity({this.files = const MethodChannelBirdBoxBleDiagnosticFilePlatform()});
  final BirdBoxBleDiagnosticFilePlatform files;
  Future<Map<String, dynamic>>? _reading;
  Future<Map<String, dynamic>> read() => _reading ??= _read();
  Future<Map<String, dynamic>> _read() async {
    try {
      final identity = await files.buildIdentity();
      if (identity.isNotEmpty) return Map.unmodifiable(identity);
    } catch (_) {
      /* Package metadata is still useful on older hosts. */
    }
    try {
      final package = await PackageInfo.fromPlatform();
      return {'package_id': package.packageName, 'version_name': package.version, 'version_code': package.buildNumber, 'identity_status': 'package_metadata_only'};
    } catch (_) {
      return const {'identity_status': 'unavailable'};
    }
  }

  static String version(Map<String, dynamic>? build) {
    final name = build?['version_name'];
    final code = build?['version_code'];
    return name == null || name.toString().isEmpty ? '版本读取中或不可用' : '$name${code == null ? '' : ' ($code)'}';
  }
}
