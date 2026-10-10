/// One Bluetooth device seen in a scan or currently connected.
class BtDevice {
  const BtDevice({
    required this.address,
    required this.name,
    required this.rssi,
    required this.type,
    required this.lastSeen,
    this.manufacturerId,
    this.txPower,
    this.connectable,
    this.bonded = false,
    this.batteryPercent,
  });

  final String address;
  final String name;
  final int rssi;

  /// 'le', 'classic', 'dual' or 'unknown'.
  final String type;
  final DateTime lastSeen;
  final int? manufacturerId;
  final int? txPower;
  final bool? connectable;
  final bool bonded;

  /// Battery of a connected device, when it reports one (headphones, watches).
  final int? batteryPercent;

  String get displayName => name.isEmpty ? '(unnamed)' : name;
  String? get maker => manufacturerId == null ? null : companyName(manufacturerId!);

  factory BtDevice.fromMap(Map<Object?, Object?> m) => BtDevice(
        address: (m['address'] as String?) ?? '',
        name: (m['name'] as String?) ?? '',
        rssi: (m['rssi'] as num?)?.toInt() ?? -100,
        type: (m['type'] as String?) ?? 'unknown',
        lastSeen: DateTime.fromMillisecondsSinceEpoch(
            (m['timestampMs'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch),
        manufacturerId: (m['manufacturerId'] as num?)?.toInt(),
        txPower: (m['txPower'] as num?)?.toInt(),
        connectable: m['connectable'] as bool?,
        bonded: (m['bonded'] as bool?) ?? false,
        batteryPercent: (m['battery'] as num?)?.toInt(),
      );
}

/// Key used to merge sightings. Many LE devices rotate random addresses every
/// few minutes; a named device with the same maker is treated as one device,
/// unnamed ones fall back to their address.
String groupKey(BtDevice d) =>
    d.name.isNotEmpty ? '${d.name}|${d.manufacturerId ?? ''}' : d.address;

/// Merges a new sighting into [known], keeping the newest data per group and
/// remembering every address the group has used.
void mergeSighting(Map<String, BtGroup> known, BtDevice d) {
  final key = groupKey(d);
  final g = known[key];
  if (g == null) {
    known[key] = BtGroup(d, {d.address});
  } else {
    g.latest = d;
    g.addresses.add(d.address);
  }
}

class BtGroup {
  BtGroup(this.latest, this.addresses);
  BtDevice latest;
  final Set<String> addresses;
}

/// A few common Bluetooth SIG company identifiers; the full list has
/// thousands, unknown ones are shown as their hex id.
const _companies = <int, String>{
  0x0006: 'Microsoft',
  0x000F: 'Broadcom',
  0x004C: 'Apple',
  0x0059: 'Nordic Semiconductor',
  0x0075: 'Samsung',
  0x0087: 'Garmin',
  0x00E0: 'Google',
  0x0157: 'Anhui Huami (Amazfit)',
  0x0171: 'Amazon',
  0x01DA: 'Logitech',
  0x02E5: 'Espressif',
  0x038F: 'Xiaomi',
  0x0499: 'Ruuvi',
  0x05A7: 'Sonos',
  0x00D2: 'Dialog Semiconductor',
  0x0002: 'Intel',
  0x001D: 'Qualcomm',
  0x0046: 'MediaTek',
  0x009E: 'Bose',
  0x012D: 'Sony',
  0x027D: 'Huawei',
  0x00C4: 'LG Electronics',
};

String companyName(int id) =>
    _companies[id] ?? '0x${id.toRadixString(16).padLeft(4, '0').toUpperCase()}';
