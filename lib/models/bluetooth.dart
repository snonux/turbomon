import '../services/bluetooth_vendors.dart';

/// A device seen by an LE scan or classic discovery.
class BluetoothSighting {
  const BluetoothSighting({
    required this.address,
    this.name,
    this.rssi,
    this.type = 'unknown',
    this.kind,
    this.companyId,
    this.source = 'le',
    required this.lastSeen,
  });

  factory BluetoothSighting.fromJson(
    Map<String, Object?> json,
    DateTime seen,
  ) => BluetoothSighting(
    address: json['address'] as String? ?? '',
    name: (json['name'] as String?)?.trim().isEmpty ?? true
        ? null
        : (json['name'] as String).trim(),
    rssi: (json['rssi'] as num?)?.toInt(),
    type: json['type'] as String? ?? 'unknown',
    kind: json['kind'] as String?,
    companyId: (json['companyId'] as num?)?.toInt(),
    source: json['source'] as String? ?? 'le',
    lastSeen: seen,
  );

  final String address;
  final String? name;
  final int? rssi;
  final String type;
  final String? kind;
  final int? companyId;
  final String source;
  final DateTime lastSeen;

  String? get maker => companyName(companyId);

  String get displayName => name ?? maker ?? 'Unknown device';

  /// Devices with random, rotating addresses show up once per address. Named
  /// devices (or ones with maker data) are grouped by name and maker; the
  /// rest stay keyed by address.
  String get groupKey => name != null ? 'n:$name|$companyId' : 'a:$address';

  Map<String, Object?> toJson({bool includeAddress = false}) => {
    'name': displayName,
    if (includeAddress) 'address': address,
    'rssi': rssi,
    'type': type,
    if (kind != null) 'kind': kind,
    if (maker != null) 'maker': maker,
    'source': source,
  };
}

/// A paired device and whether it is connected right now.
class PairedDevice {
  const PairedDevice({
    required this.address,
    this.name,
    this.type = 'unknown',
    this.kind,
    this.connected = false,
    this.profiles = const [],
  });

  factory PairedDevice.fromJson(Map<String, Object?> json) => PairedDevice(
    address: json['address'] as String? ?? '',
    name: json['name'] as String?,
    type: json['type'] as String? ?? 'unknown',
    kind: json['kind'] as String?,
    connected: json['connected'] as bool? ?? false,
    profiles: [
      for (final p in json['profiles'] as List? ?? const []) p as String,
    ],
  );

  final String address;
  final String? name;
  final String type;
  final String? kind;
  final bool connected;
  final List<String> profiles;

  Map<String, Object?> toJson({bool includeAddress = false}) => {
    'name': name ?? 'Unknown',
    if (includeAddress) 'address': address,
    'connected': connected,
    'profiles': profiles,
    if (kind != null) 'kind': kind,
  };
}
