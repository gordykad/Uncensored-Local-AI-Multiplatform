import 'package:flutter/material.dart';

/// Audit #2/#9 (Kai's approved build order, 2026-11-05): a role type
/// scale that honors the system text size (Dynamic Type). The base
/// sizes are the app's existing design sizes; every rendered size is
/// multiplied by the platform text scaler, clamped so layouts hold
/// at the extremes (0.85x .. 1.35x).
class TS {
  TS._();

  static double of(BuildContext c, double base) {
    final scaled = MediaQuery.textScalerOf(c).scale(base);
    return scaled.clamp(base * 0.85, base * 1.35).toDouble();
  }

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
