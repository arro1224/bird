import 'package:aves/bird_companion/core/models/job_models.dart';
import 'package:aves/bird_companion/core/models/json_value.dart';
import 'package:aves/bird_companion/core/models/protocol_validation.dart';
import 'package:equatable/equatable.dart';

enum NetworkMode {
  directAp,
  infrastructureSta,
  none,

  /// Legacy UI entry modes kept source-compatible while persisted values use
  /// the rc4 network identity contract.
  hotspot,
  lan,
  manual,
  qr,
  unknown,
}

extension NetworkModeWireValue on NetworkMode {
  static NetworkMode fromWire(String? value) => switch (value) {
    'direct_ap' || 'hotspot' => NetworkMode.directAp,
    'infrastructure_sta' || 'lan' || 'manual' || 'qr' => NetworkMode.infrastructureSta,
    'none' => NetworkMode.none,
    _ => NetworkMode.unknown,
  };

  String get wireValue => switch (this) {
    NetworkMode.directAp || NetworkMode.hotspot => 'direct_ap',
    NetworkMode.infrastructureSta || NetworkMode.lan || NetworkMode.manual || NetworkMode.qr => 'infrastructure_sta',
    NetworkMode.none || NetworkMode.unknown => 'none',
  };

  String get label => switch (this) {
    NetworkMode.directAp || NetworkMode.hotspot => '盒子热点',
    NetworkMode.infrastructureSta || NetworkMode.lan => '同一个 Wi-Fi',
    NetworkMode.manual => '手动地址',
    NetworkMode.qr => '扫码连接',
    NetworkMode.none || NetworkMode.unknown => '未知连接方式',
  };
}

class DeviceConnection extends Equatable {
  const DeviceConnection({
    required this.id,
    required this.name,
    required this.baseUri,
    required this.networkMode,
    this.apiVersion,
    this.signalStrength,
    this.isPaired = false,
  });

  final String id;
  final String name;
  final Uri baseUri;
  final NetworkMode networkMode;
  final String? apiVersion;
  final int? signalStrength;
  final bool isPaired;

  Map<String, dynamic> toJson() => {
    'device_id': id,
    'device_name': name,
    // The address is only a reconnect hint. Stable identity always comes from
    // device_id and must be revalidated by /health or the device status API.
    'address_hint': baseUri.toString(),
    'network_mode': networkMode.wireValue,
    'api_version': apiVersion,
    'signal_strength': signalStrength,
    'is_paired': isPaired,
  };

  factory DeviceConnection.fromJson(Map<String, dynamic> json) {
    final rawUri = json.stringOrNull('address_hint') ?? json.stringOrNull('base_uri') ?? json.stringOrNull('ip_address') ?? '';
    return DeviceConnection(
      id: json.stringOrNull('device_id') ?? rawUri,
      name: json.stringOrNull('device_name') ?? '拍鸟盒子',
      baseUri: Uri.tryParse(rawUri) ?? Uri(),
      networkMode: NetworkModeWireValue.fromWire(json.stringOrNull('network_mode')),
      apiVersion: json.stringOrNull('api_version'),
      signalStrength: json.intOrNull('signal_strength'),
      isPaired: json.boolOrNull('is_paired') ?? false,
    );
  }

  DeviceConnection copyWith({
    Uri? baseUri,
    NetworkMode? networkMode,
    String? apiVersion,
    int? signalStrength,
    bool? isPaired,
  }) => DeviceConnection(
    id: id,
    name: name,
    baseUri: baseUri ?? this.baseUri,
    networkMode: networkMode ?? this.networkMode,
    apiVersion: apiVersion ?? this.apiVersion,
    signalStrength: signalStrength ?? this.signalStrength,
    isPaired: isPaired ?? this.isPaired,
  );

  @override
  List<Object?> get props => [id, name, baseUri, networkMode, apiVersion, signalStrength, isPaired];
}

class CardStatus extends Equatable {
  const CardStatus({required this.inserted, this.readable = false, this.name, this.errorCode, this.errorMessage});

  final bool inserted;
  final bool readable;
  final String? name;
  final String? errorCode;
  final String? errorMessage;

  factory CardStatus.fromJson(Map<String, dynamic> json) => CardStatus(
    inserted: json.boolOrNull('card_inserted') ?? json.boolOrNull('inserted') ?? false,
    readable: json.boolOrNull('card_readable') ?? json.boolOrNull('readable') ?? false,
    name: json.stringOrNull('card_name') ?? json.stringOrNull('name'),
    errorCode: json.stringOrNull('error_code'),
    errorMessage: json.stringOrNull('error_message'),
  );

  @override
  List<Object?> get props => [inserted, readable, name, errorCode, errorMessage];
}

class DeviceStatus extends Equatable {
  const DeviceStatus({
    required this.connection,
    required this.card,
    this.batteryPercent,
    this.isExternalPower = false,
    this.temperatureCelsius,
    this.storageTotalBytes,
    this.storageFreeBytes,
    this.currentJob,
    this.errorCode,
    this.errorMessage,
    this.softwareVersion,
    this.modelVersion,
    this.updatedAt,
  });

  final DeviceConnection connection;
  final CardStatus card;
  final int? batteryPercent;
  final bool isExternalPower;
  final double? temperatureCelsius;
  final int? storageTotalBytes;
  final int? storageFreeBytes;
  final BirdJobStatus? currentJob;
  final String? errorCode;
  final String? errorMessage;
  final String? softwareVersion;
  final String? modelVersion;
  final DateTime? updatedAt;

  bool get hasError => errorCode != null || errorMessage != null;

  factory DeviceStatus.fromJson(Map<String, dynamic> json, {Uri? fallbackBaseUri, NetworkMode fallbackNetworkMode = NetworkMode.unknown}) {
    final connectionJson = json.mapOrNull('connection') ?? json;
    final baseUri = fallbackBaseUri ?? Uri.tryParse(connectionJson.stringOrNull('base_uri') ?? connectionJson.stringOrNull('ip_address') ?? '') ?? Uri();
    final connection = DeviceConnection.fromJson({...connectionJson, 'base_uri': baseUri.toString(), 'network_mode': connectionJson.stringOrNull('network_mode') ?? fallbackNetworkMode.wireValue});
    final cardJson = json.mapOrNull('card') ?? json;
    final jobJson = json.mapOrNull('current_task') ?? json.mapOrNull('current_job');
    return DeviceStatus(
      connection: connection,
      card: CardStatus.fromJson(cardJson),
      batteryPercent: json.intOrNull('battery_percent'),
      isExternalPower: json.boolOrNull('external_power') ?? json.boolOrNull('is_external_power') ?? false,
      temperatureCelsius: json.doubleOrNull('temperature') ?? json.doubleOrNull('temperature_celsius'),
      storageTotalBytes: ProtocolValidation.optionalNonNegativeInt(
        json,
        'storage_total',
      ),
      storageFreeBytes: ProtocolValidation.optionalNonNegativeInt(
        json,
        'storage_free',
      ),
      currentJob: jobJson == null ? null : BirdJobStatus.fromJson(jobJson),
      errorCode: json.stringOrNull('error_code'),
      errorMessage: json.stringOrNull('error_message'),
      softwareVersion: json.stringOrNull('software_version'),
      modelVersion: json.stringOrNull('model_version'),
      updatedAt: ProtocolValidation.optionalDateTime(json, 'updated_at'),
    );
  }

  @override
  List<Object?> get props => [connection, card, batteryPercent, isExternalPower, temperatureCelsius, storageTotalBytes, storageFreeBytes, currentJob, errorCode, errorMessage, softwareVersion, modelVersion, updatedAt];
}
