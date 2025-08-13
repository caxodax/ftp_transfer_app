// lib/app_theme.dart

import 'package:flutter/material.dart'; // ¡ESTA ES LA LÍNEA CRUCIAL QUE FALTABA!
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // --- IDENTIDAD DE MARCA DEL CLIENTE (OXXO) ---
  static const Color primaryColor = Color(0xFFEE3224);
  static const Color accentColor = Color(0xFFF3B329);
  static const String logoAsset = 'assets/oxxo_logo.png';

  // --- TEMA GLOBAL DE LA APLICACIÓN ---
  static final ThemeData globalTheme = ThemeData(
    useMaterial3: true,
    
    textTheme: GoogleFonts.montserratTextTheme(),

    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryColor,
      primary: primaryColor,
      secondary: accentColor,
      surface: const Color(0xFFF5F5F5),
      onPrimary: Colors.white,
      onSurface: const Color(0xFF333333),
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: primaryColor,
      foregroundColor: Colors.white,
      elevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: 'Montserrat',
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: Colors.white
      ),
    ),

    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primaryColor,
      foregroundColor: Colors.white,
    ),

    tabBarTheme: const TabBarThemeData(
      labelColor: Colors.white,
      unselectedLabelColor: Colors.white70,
      indicatorColor: accentColor,
      indicatorSize: TabBarIndicatorSize.tab,
      labelStyle: TextStyle(fontFamily: 'Montserrat', fontWeight: FontWeight.bold),
      unselectedLabelStyle: TextStyle(fontFamily: 'Montserrat'),
    ),
    
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30.0)),
        textStyle: const TextStyle(fontFamily: 'Montserrat', fontWeight: FontWeight.bold, fontSize: 16),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 18.0, horizontal: 20.0),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30.0),
        borderSide: const BorderSide(color: Colors.grey, width: 0.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30.0),
        borderSide: BorderSide(color: Colors.grey.shade300, width: 1.0),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30.0),
        borderSide: const BorderSide(color: accentColor, width: 2.0),
      ),
      labelStyle: const TextStyle(color: Colors.grey),
    ),

    cardTheme: CardThemeData(
      elevation: 2.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      clipBehavior: Clip.antiAlias,
    ),
  );
}