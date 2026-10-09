import 'package:flutter/material.dart';

/// Resolves engine theme colors into readable desktop surfaces. The terminal's
/// default ANSI theme has no RGB colors, so it keeps the desktop's own palette.
class DesktopPalette {
  const DesktopPalette({
    this.background = const Color(0xff101217),
    this.surface = const Color(0xff191c24),
    this.sidebar = const Color(0xff14161d),
    this.foreground = const Color(0xfff4f5f8),
    this.muted = const Color(0xff9da4b6),
    this.accent = const Color(0xff81e6cd),
    this.secondary = const Color(0xffa29bfe),
    this.brightness = Brightness.dark,
  });

  factory DesktopPalette.fromEngine(Map<String, dynamic> theme) {
    final background = _hex(theme['bg']);
    if (background == null) return const DesktopPalette();
    final brightness = ThemeData.estimateBrightnessForColor(background);
    final fallback = brightness == Brightness.dark
        ? Colors.white
        : Colors.black;
    final foreground = _readable(
      _hex(theme['bright_fg']) ?? _hex(theme['fg']) ?? fallback,
      background,
      fallback,
      4.5,
    );
    final surface = Color.lerp(background, foreground, .045)!;
    final accent = _readable(
      _hex(theme['accent']) ?? _hex(theme['green']) ?? foreground,
      surface,
      fallback,
      3,
    );
    return DesktopPalette(
      background: background,
      surface: surface,
      sidebar: Color.lerp(background, foreground, .02)!,
      foreground: foreground,
      muted: _readable(
        _hex(theme['fg']) ?? Color.lerp(background, foreground, .65)!,
        surface,
        foreground,
        4.5,
      ),
      accent: accent,
      secondary: _readable(
        _hex(theme['green']) ?? accent,
        surface,
        foreground,
        3,
      ),
      brightness: brightness,
    );
  }

  final Color background,
      surface,
      sidebar,
      foreground,
      muted,
      accent,
      secondary;
  final Brightness brightness;
  Color get onAccent =>
      accent.computeLuminance() > .179 ? Colors.black : Colors.white;
  List<Color> get headerGradient => [
    Color.lerp(surface, accent, .13)!,
    Color.lerp(surface, secondary, .10)!,
    surface,
  ];

  ThemeData get theme {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: brightness,
        ).copyWith(
          primary: accent,
          onPrimary: onAccent,
          secondary: secondary,
          surface: surface,
          onSurface: foreground,
          onSurfaceVariant: muted,
        );
    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: background,
      colorScheme: scheme,
      fontFamily: 'Inter',
      useMaterial3: true,
      dividerColor: foreground.withValues(alpha: .07),
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 400),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: foreground.withValues(alpha: .045),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        hintStyle: TextStyle(color: muted, fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        ),
      ),
      textTheme: TextTheme(
        bodyMedium: TextStyle(color: foreground, fontSize: 13, height: 1.5),
        bodySmall: TextStyle(color: muted, fontSize: 12, height: 1.5),
        titleLarge: TextStyle(
          color: foreground,
          fontSize: 25,
          fontWeight: FontWeight.w700,
          letterSpacing: -.7,
        ),
        titleMedium: TextStyle(
          color: foreground,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  static Color? _hex(dynamic value) {
    final text = value?.toString() ?? '';
    if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(text)) return null;
    return Color(0xff000000 | int.parse(text.substring(1), radix: 16));
  }

  static Color _readable(
    Color color,
    Color background,
    Color fallback,
    double ratio,
  ) {
    double contrast(Color candidate) {
      final a = candidate.computeLuminance();
      final b = background.computeLuminance();
      return (a > b ? a + .05 : b + .05) / (a > b ? b + .05 : a + .05);
    }

    if (contrast(color) >= ratio) return color;
    for (var i = 1; i <= 20; i++) {
      final candidate = Color.lerp(color, fallback, i / 20)!;
      if (contrast(candidate) >= ratio) return candidate;
    }
    return fallback;
  }
}
