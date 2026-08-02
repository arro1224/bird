import 'package:aves/bird_companion/core/models/protocol_validation.dart';

enum CardScanState { detected, scanning, missing, unreadable, empty, unknown }

class CardScanResult {
  const CardScanResult({
    required this.state,
    this.cardId,
    this.cardName,
    this.photoCount = 0,
    this.rawCount = 0,
    this.jpegCount = 0,
    this.requiredBytes = 0,
    this.errorCode,
    this.errorMessage,
  });

  final CardScanState state;
  final String? cardId;
  final String? cardName;
  final int photoCount;
  final int rawCount;
  final int jpegCount;
  final int requiredBytes;
  final String? errorCode;
  final String? errorMessage;

  bool get canCreateProject => state == CardScanState.detected && cardId != null && cardId!.trim().isNotEmpty;

  factory CardScanResult.fromJson(Map<String, dynamic> json) => CardScanResult(
    state: switch (json['scan_state']?.toString()) {
      'detected' => CardScanState.detected,
      'scanning' => CardScanState.scanning,
      'missing' => CardScanState.missing,
      'unreadable' => CardScanState.unreadable,
      'empty' => CardScanState.empty,
      _ => CardScanState.unknown,
    },
    cardId: json['card_id']?.toString(),
    cardName: json['card_name']?.toString(),
    photoCount: ProtocolValidation.nonNegativeInt(json, 'photo_count'),
    rawCount: ProtocolValidation.nonNegativeInt(json, 'raw_count'),
    jpegCount: ProtocolValidation.nonNegativeInt(json, 'jpeg_count'),
    requiredBytes: ProtocolValidation.nonNegativeInt(json, 'required_bytes'),
    errorCode: json['error_code']?.toString(),
    errorMessage: json['error_message']?.toString(),
  );
}
