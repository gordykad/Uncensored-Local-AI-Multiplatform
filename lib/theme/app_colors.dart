import 'package:flutter/material.dart';

extension ThemeExt on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  Color get bg => Theme.of(this).scaffoldBackgroundColor;
  Color get bgSidebar =>
      isDark ? AppColors.darkBgSidebar : AppColors.lightBgSidebar;
  Color get bgPanel => Theme.of(this).colorScheme.surface;
  Color get bgInput => isDark ? AppColors.darkBgInput : AppColors.lightBgInput;
  Color get bgMsgAi => isDark ? AppColors.darkBgMsgAi : AppColors.lightBgMsgAi;
  Color get bgHover => isDark ? AppColors.darkBgHover : AppColors.lightBgHover;
  Color get border => Theme.of(this).dividerColor;
  Color get borderFaint =>
      isDark ? AppColors.darkBorderFaint : AppColors.lightBorderFaint;

  Color get text => isDark ? AppColors.darkText : AppColors.lightText;
  Color get textM => isDark ? AppColors.darkTextM : AppColors.lightTextM;
  Color get textD => isDark ? AppColors.darkTextD : AppColors.lightTextD;
}

/// Astro MiniX black-box tokens (ticket 08; source: .scratch/minix-v2/design/tokens.json).
class AppColors {
  AppColors._();

  // ── Common Colors ──────────────────────────────────────────────
  static const accent = Color(
    0xFF9333EA,
  ); // Astro purple (founder FINAL 2026-11-02)
  static const accentDim = Color(0xFF7E22CE);
  static const accentHi = Color(0xFFA855F7);
  static const green = Color(0xFF3FB950);
  static const red = Color(0xFFF85149);
  static const orange = Color(0xFFE3B341);

  // ── Dark Theme Colors ──────────────────────────────────────────
  static const darkBg = Color(0xFF050506); // void
  static const darkBgSidebar = Color(0xFF050506);
  static const darkBgPanel = Color(0xFF0C0C0E); // panel
  static const darkBgInput = Color(0xFF121214); // input
  static const darkBgMsgAi = Color(0xFF0C0C0E);
  static const darkBgHover = Color(0xFF17171A); // hover
  static const darkBorder = Color(0xFF26262B); // strong
  static const darkBorderFaint = Color(0xFF1A1A1E); // faint
  static const darkText = Color(0xFFF2F2F0);
  static const darkTextM = Color(0xFF9C9CA3);
  static const darkTextD = Color(
    0xFF8E8E96,
  ); // audit #5 lift (was 0xFF5C5C64, ~3.0:1)

  // ── Light Theme Colors ─────────────────────────────────────────
  static const lightBg = Color(0xFF050506);
  static const lightBgSidebar = Color(0xFF050506);
  static const lightBgPanel = Color(0xFF0C0C0E);
  static const lightBgInput = Color(0xFF121214);
  static const lightBgMsgAi = Color(0xFF0C0C0E);
  static const lightBgHover = Color(0xFF17171A);
  static const lightBorder = Color(0xFF26262B);
  static const lightBorderFaint = Color(0xFF1A1A1E);
  static const lightText = Color(0xFFF2F2F0);
  static const lightTextM = Color(0xFF9C9CA3);
  static const lightTextD = Color(0xFF8E8E96);

  // ── Label colours ────────────────────────────────────────────
  static const uncensored = Color(
    0xFF9333EA,
  ); // red label retired — purple IS the mark
  static const standard = Color(0xFF9C9CA3);
  static const custom = Color(0xFFA855F7);

  // ── Gradients ────────────────────────────────────────────────
  static const accentGradient = LinearGradient(
    colors: [accent, Color(0xFF6D28D9)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
