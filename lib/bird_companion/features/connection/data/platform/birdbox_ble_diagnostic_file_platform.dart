import 'package:aves/bird_companion/features/connection/domain/ble_diagnostic_export.dart';
import 'package:flutter/services.dart';

final class BleDiagnosticFile {
  const BleDiagnosticFile({required this.token, required this.fileName, required this.mimeType, required this.bytes, required this.sha256});
  final String token, fileName, mimeType, sha256;
  final int bytes;
}

abstract interface class BirdBoxBleDiagnosticFilePlatform {
  Future<Map<String, dynamic>> buildIdentity();
  Future<BleDiagnosticFile> prepare(BleDiagnosticExport export);
  Future<String> share(BleDiagnosticFile file);
  Future<String> save(BleDiagnosticFile file);
}

final class MethodChannelBirdBoxBleDiagnosticFilePlatform implements BirdBoxBleDiagnosticFilePlatform {
  const MethodChannelBirdBoxBleDiagnosticFilePlatform();
  static const channel = MethodChannel('bird_companion/ble_diagnostic_files');
  @override
  Future<Map<String, dynamic>> buildIdentity() async => Map<String, dynamic>.from(await channel.invokeMapMethod<String, dynamic>('getBuildIdentity') ?? const {});
  @override
  Future<BleDiagnosticFile> prepare(BleDiagnosticExport export) async {
    final value = await channel.invokeMapMethod<String, dynamic>('prepare', {
      'traceId': export.traceId,
      'fullJson': export.fullJson,
      'summaryJson': export.summaryJson,
      'payloadSha256': export.payloadSha256,
    });
    final token = value?['token'], name = value?['fileName'], mime = value?['mimeType'], size = value?['bytes'], digest = value?['sha256'];
    if (token is! String ||
        token.isEmpty ||
        name is! String ||
        name.contains('/') ||
        name.contains('\\') ||
        mime is! String ||
        !const ['application/json', 'application/zip'].contains(mime) ||
        size is! int ||
        size <= 0 ||
        digest is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest) ||
        value?['verified'] != true ||
        value?['payloadSha256'] != export.payloadSha256 ||
        (mime == 'application/json' && digest != export.payloadSha256)) {
      throw PlatformException(code: 'file_verification_failed', message: '诊断文件校验失败');
    }
    return BleDiagnosticFile(token: token, fileName: name, mimeType: mime, bytes: size, sha256: digest);
  }

  @override
  Future<String> share(BleDiagnosticFile file) => _action('share', file);
  @override
  Future<String> save(BleDiagnosticFile file) => _action('save', file);
  Future<String> _action(String method, BleDiagnosticFile file) async {
    final value = await channel.invokeMapMethod<String, dynamic>(method, {'token': file.token, 'sha256': file.sha256});
    final outcome = value?['outcome'];
    if (outcome is! String || !(method == 'share' ? const ['share_opened'] : const ['saved', 'cancelled']).contains(outcome)) throw PlatformException(code: 'invalid_file_result');
    return outcome;
  }
}
