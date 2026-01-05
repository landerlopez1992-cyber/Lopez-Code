import 'package:flutter/material.dart';

class CursorTheme {
  // Colores principales de Cursor
  static const Color background = Color(0xFF1E1E1E);
  static const Color surface = Color(0xFF252526);
  static const Color surfaceHover = Color(0xFF2A2D2E);
  static const Color border = Color(0xFF3E3E42);
  static const Color primary = Color(0xFF007ACC);
  static const Color primaryHover = Color(0xFF1A8CD8);
  static const Color textPrimary = Color(0xFFCCCCCC);
  static const Color textSecondary = Color(0xFF858585);
  static const Color textDisabled = Color(0xFF6A6A6A);
  
  // Colores para código
  static const Color codeBackground = Color(0xFF1E1E1E);
  static const Color codeBorder = Color(0xFF3E3E42);
  static const Color codeText = Color(0xFFD4D4D4);
  
  // Colores para mensajes
  static const Color userMessageBg = Color(0xFF0E639C);
  static const Color assistantMessageBg = Color(0xFF2D2D30);
  static const Color assistantMessageBorder = Color(0xFF3E3E42);
  
  // Colores para el explorador
  static const Color explorerBackground = Color(0xFF252526);
  static const Color explorerItemHover = Color(0xFF2A2D2E);
  static const Color explorerItemSelected = Color(0xFF37373D);
  
  // Colores para el editor
  static const Color editorBackground = Color(0xFF1E1E1E);
  static const Color editorLineNumber = Color(0xFF858585);
  static const Color editorCursor = Color(0xFFAEAFAD);
  
  // Tema de Cursor
  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        surface: surface,
        background: background,
        onPrimary: Colors.white,
        onSurface: textPrimary,
        onBackground: textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        elevation: 0,
        iconTheme: IconThemeData(color: textPrimary),
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: primary, width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: textPrimary, fontSize: 13),
        bodyMedium: TextStyle(color: textPrimary, fontSize: 13),
        bodySmall: TextStyle(color: textSecondary, fontSize: 12),
        titleMedium: TextStyle(color: textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}

