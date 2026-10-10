/// Bluetooth SIG company identifiers of common makers, for labelling devices
/// by the manufacturer data they advertise. Unknown ids show as hex.
const Map<int, String> bluetoothCompanies = {
  0x0002: 'Intel',
  0x0006: 'Microsoft',
  0x000A: 'Qualcomm',
  0x000D: 'Texas Instruments',
  0x000F: 'Broadcom',
  0x001D: 'Qualcomm',
  0x004C: 'Apple',
  0x0059: 'Nordic Semiconductor',
  0x0075: 'Samsung',
  0x0087: 'Garmin',
  0x009E: 'Bose',
  0x00E0: 'Google',
  0x012D: 'Sony',
  0x0171: 'Amazon',
  0x01DA: 'Logitech',
  0x027D: 'Huawei',
  0x02E5: 'Espressif',
  0x038F: 'Xiaomi',
  0x0499: 'Ruuvi',
  0x05A7: 'Sonos',
};

String? companyName(int? id) {
  if (id == null) return null;
  return bluetoothCompanies[id] ??
      '0x${id.toRadixString(16).padLeft(4, '0').toUpperCase()}';
}
