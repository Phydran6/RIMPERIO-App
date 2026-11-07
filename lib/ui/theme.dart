// ---------------------------------------------------------------------------
// Datei:        lib/ui/theme.dart
// Projekt:      RIMPERIO-App
// Autor:        Phydran6
// Version:      2026.11.07.12.00.00
//
// Beschreibung: Erscheinungsbild — Material 3, Nachtblau mit Gold, hell und
//               dunkel nach Systemeinstellung.
// ---------------------------------------------------------------------------
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RimTheme {
  static const gold = Color(0xFFD4AF37);
  static const navy = Color(0xFF0A1222);
  static const navyDeep = Color(0xFF030B1A);

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: gold,
      brightness: Brightness.dark,
      primary: gold,
      surface: navy,
    );
    return _base(scheme).copyWith(
      scaffoldBackgroundColor: navy,
      appBarTheme: const AppBarTheme(
        backgroundColor: navy,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
    );
  }

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: gold, brightness: Brightness.light);
    return _base(scheme);
  }

  static ThemeData _base(ColorScheme scheme) => ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        visualDensity: VisualDensity.standard,
        cardTheme: CardThemeData(
          elevation: 0,
          color: scheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
        snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      );
}

/// Farbe und Symbol je Schweregrad (Logs, Meldungen).
class Severity {
  static Color color(String? level, ColorScheme cs) {
    switch ((level ?? '').toLowerCase()) {
      case 'emergency' || 'emerg' || 'panic' || 'alert' || 'critical' || 'crit':
        return const Color(0xFFE5484D);
      case 'error' || 'err' || 'failed':
        return const Color(0xFFF2555A);
      case 'warning' || 'warn':
        return const Color(0xFFF5A524);
      case 'notice':
        return const Color(0xFF3E9BF5);
      case 'debug':
        return cs.outline;
      default:
        return const Color(0xFF30A46C);
    }
  }

  static IconData icon(String? level) {
    switch ((level ?? '').toLowerCase()) {
      case 'emergency' || 'emerg' || 'panic' || 'alert' || 'critical' || 'crit':
        return Icons.dangerous_rounded;
      case 'error' || 'err':
        return Icons.error_rounded;
      case 'warning' || 'warn':
        return Icons.warning_amber_rounded;
      case 'debug':
        return Icons.bug_report_outlined;
      default:
        return Icons.info_outline_rounded;
    }
  }

  static String label(String? level) => switch ((level ?? '').toLowerCase()) {
        'emergency' || 'emerg' || 'panic' => 'Notfall',
        'alert' => 'Alarm',
        'critical' || 'crit' => 'Kritisch',
        'error' || 'err' => 'Fehler',
        'warning' || 'warn' => 'Warnung',
        'notice' => 'Hinweis',
        'info' || 'informational' => 'Info',
        'debug' => 'Debug',
        _ => level ?? '–',
      };
}
