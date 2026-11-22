import 'package:aves/bird_companion/features/connection/domain/wifi_qr_credentials.dart';
import 'package:aves/bird_companion/features/connection/domain/wifi_qr_parser.dart';

/// Why an imported/ scanned image did not yield exactly one usable Wi-Fi QR code.
enum WifiQrImportFailure { empty, multipleCodes, notWifiQr }

/// Outcome of evaluating the barcodes found in one camera frame or one picked photo.
///
/// Both entries (camera and gallery) share this evaluation so a code accepted by one is
/// accepted by the other, and a picture with several codes is never reduced silently to
/// the first one.
final class WifiQrImportOutcome {
  const WifiQrImportOutcome.accepted(this.credentials) : failure = null;
  const WifiQrImportOutcome.rejected(this.failure) : credentials = null;

  final WifiQrCredentials? credentials;
  final WifiQrImportFailure? failure;

  bool get isAccepted => credentials != null;

  /// User-facing explanation. Never contains the code payload.
  String get message => switch (failure) {
    WifiQrImportFailure.empty => '这张图片里没有识别到二维码，请重新选择或改用扫描入口。',
    WifiQrImportFailure.multipleCodes => '检测到多个二维码，请只保留一个 Wi-Fi 二维码后重试。',
    WifiQrImportFailure.notWifiQr => '这不是受支持的标准 Wi-Fi 二维码，请重新选择或重新扫描。',
    null => '',
  };
}

/// Evaluates the raw barcode payloads of a single frame or image.
///
/// Identical payloads are folded together (the same code may be reported twice for one
/// physical QR), but genuinely different codes are rejected instead of picking the first.
WifiQrImportOutcome evaluateWifiQrCodes(Iterable<String?> rawValues) {
  final codes = <String>[];
  for (final raw in rawValues) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) continue;
    if (!codes.contains(value)) codes.add(value);
  }
  if (codes.isEmpty) return const WifiQrImportOutcome.rejected(WifiQrImportFailure.empty);
  if (codes.length > 1) return const WifiQrImportOutcome.rejected(WifiQrImportFailure.multipleCodes);
  final credentials = tryParseWifiQrCredentials(codes.single);
  if (credentials == null) return const WifiQrImportOutcome.rejected(WifiQrImportFailure.notWifiQr);
  return WifiQrImportOutcome.accepted(credentials);
}
