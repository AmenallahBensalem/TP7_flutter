import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData build(Brightness brightness) {
    final colors = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6743B7),
      brightness: brightness,
      surface: brightness == Brightness.light ? Colors.white : null,
    );
    OutlineInputBorder border(BorderSide side) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: side,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: colors);
    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: colors.onSurface,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          color: colors.onSurfaceVariant,
          height: 1.45,
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: colors.surfaceContainerLow,
        prefixIconColor: colors.primary,
        suffixIconColor: colors.onSurfaceVariant,
        labelStyle: TextStyle(color: colors.onSurfaceVariant),
        floatingLabelStyle: TextStyle(color: colors.primary),
        errorStyle: TextStyle(color: colors.error),
        errorMaxLines: 2,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: border(BorderSide.none),
        enabledBorder: border(BorderSide.none),
        focusedBorder: border(BorderSide(color: colors.primary, width: 1.5)),
        errorBorder: border(BorderSide(color: colors.error)),
        focusedErrorBorder: border(BorderSide(color: colors.error, width: 1.5)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
