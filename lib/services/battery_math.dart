/// Vendors disagree on the unit and sign of BATTERY_PROPERTY_CURRENT_NOW:
/// most report µA, some mA; some report discharge as positive. This returns
/// mA with the sign taken from the charging state, so positive always means
/// charging and negative draining.
double? normaliseCurrentMa(num? raw, {required bool charging}) {
  if (raw == null || raw == 0) return null;
  final magnitude = raw.abs();
  // A phone drawing 10 mA or more reports at least 10000 in µA; values below
  // that are taken as mA. 10 A in mA would be needed to break the heuristic.
  final ma = magnitude >= 10000 ? magnitude / 1000 : magnitude.toDouble();
  return charging ? ma : -ma;
}
