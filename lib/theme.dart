import 'package:flutter/material.dart';

/// Brand colours from the icon: deep blue with an orange accent.
const turboBlue = Color(0xFF0B1E3F);
const turboOrange = Color(0xFFFF7A1A);

ThemeData turboTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF1E4D9B),
    brightness: brightness,
  ).copyWith(tertiary: turboOrange);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: brightness == Brightness.dark
        ? const Color(0xFF07142B)
        : null,
    cardTheme: const CardThemeData(margin: EdgeInsets.symmetric(vertical: 4)),
  );
}

/// Green under 50 %, amber to 80 %, red above: the load colour of every
/// graph and bar.
Color loadColor(double? percent) {
  if (percent == null) return Colors.blueGrey;
  if (percent < 50) return const Color(0xFF43A047);
  if (percent < 80) return const Color(0xFFFFB300);
  return const Color(0xFFE53935);
}

/// Wi-Fi and Bluetooth signal colour by dBm.
Color signalColor(int dbm) {
  if (dbm >= -60) return const Color(0xFF43A047);
  if (dbm >= -75) return const Color(0xFFFFB300);
  return const Color(0xFFE53935);
}
