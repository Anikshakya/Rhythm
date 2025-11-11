import 'package:flutter/material.dart';

class AppTheme {
  // ====================================================
  // LIGHT THEME
  // ====================================================
  static final ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: Colors.white,
    primaryColor: Colors.black,
    iconTheme: const IconThemeData(color: Colors.black87),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black87,
      elevation: 0,
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: Colors.black87,
      inactiveTrackColor: Colors.black26,
      thumbColor: Colors.black87,
      overlayColor: Colors.black12,
      trackHeight: 3,
    ),
    cardColor: Colors.white,
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Colors.black87,
    ),
  );

  // ====================================================
  // DARK THEME
  // ====================================================
  static final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF1E1E1E),
    primaryColor: Colors.white,
    iconTheme: const IconThemeData(color: Colors.white70),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1E1E1E),
      foregroundColor: Colors.white70,
      elevation: 0,
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: Colors.white,
      inactiveTrackColor: Colors.white24,
      thumbColor: Colors.white,
      overlayColor: Colors.white12,
      trackHeight: 3,
    ),
    cardColor: const Color(0xFF2C2C2C),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Colors.white70,
    ),
  );
}
