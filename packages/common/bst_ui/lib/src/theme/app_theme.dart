import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFF0F0E17),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF7F5AF0),
        brightness: Brightness.dark,
        primary: const Color(0xFF7F5AF0),
        secondary: const Color(0xFF2EC4B6),
      ),
      textTheme: GoogleFonts.notoSansKrTextTheme(ThemeData.dark().textTheme),
    );
  }
}
