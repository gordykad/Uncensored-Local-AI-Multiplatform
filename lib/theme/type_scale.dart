import 'package:flutter/material.dart';

/// Audit #2/#9 (Kai's approved build order, 2026-11-05): a role type
/// scale that honors the system text size (Dynamic Type).
///
/// Claude x Codex audit 2026-11-06 (P1-1): TS must NOT pre-scale.
/// Flutter's Text applies the MediaQuery text scaler itself, so a
/// pre-scaled fontSize was scaled twice. TS now returns the base
/// size untouched; the single clamp lives at the app root via
/// MediaQuery.withClampedTextScaling (0.85x .. 1.35x) in main.dart.
class TS {
  TS._();

  static double of(BuildContext c, double base) => base;

  static TextStyle display(BuildContext c, {Color? color}) => TextStyle(
    fontSize: of(c, 22),
    fontWeight: FontWeight.w700,
    color: color,
    height: 1.25,
  );

  static TextStyle title(BuildContext c, {Color? color}) => TextStyle(
    fontSize: of(c, 16),
    fontWeight: FontWeight.w600,
    color: color,
    height: 1.3,
  );

  static TextStyle body(BuildContext c, {Color? color, double? height}) =>
      TextStyle(fontSize: of(c, 15), color: color, height: height ?? 1.6);

  static TextStyle label(BuildContext c, {Color? color, FontWeight? weight}) =>
      TextStyle(
        fontSize: of(c, 13),
        fontWeight: weight,
        color: color,
        height: 1.35,
      );

  static TextStyle caption(BuildContext c, {Color? color}) =>
      TextStyle(fontSize: of(c, 11), color: color, height: 1.4);

  static TextStyle micro(BuildContext c, {Color? color}) =>
      TextStyle(fontSize: of(c, 10), color: color, height: 1.3);
}

/// Audit #3 app-wide: one read for the Reduce Motion setting so every
/// animated surface honors the same switch the MorphOrb already does.
class RM {
  RM._();
  static bool off(BuildContext c) => MediaQuery.disableAnimationsOf(c);
}
