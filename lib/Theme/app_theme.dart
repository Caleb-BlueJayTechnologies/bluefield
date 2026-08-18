import 'package:flutter/material.dart';

class AppTheme {
  static const Color blue = Color(0xFF1565C0);
  static const Color darkText = Color(0xFF12324A);
  static const Color mutedText = Color(0xFF6B7C8F);
  static const Color background = Color(0xFFF4F7FB);

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: blue,
    ),
    scaffoldBackgroundColor: background,
  );
}