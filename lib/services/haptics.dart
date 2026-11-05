import 'package:flutter/services.dart';

/// Audit #1 (Kai's approved build order, 2026-11-05): the haptics
/// map. Causal only — a buzz must be caused by the user's act or by
/// the event it reports, never decoration.
///   select  — a choice landed (dock tab, picker row, toggle, star)
///   light   — a soft confirm (copy, verify flip)
///   send    — a message left the phone
///   stop    — a run was halted by hand
///   done    — a generation finished clean
///   error   — a generation or action failed
class TapFx {
  TapFx._();

  static void select() => HapticFeedback.selectionClick();
  static void light() => HapticFeedback.lightImpact();
  static void send() => HapticFeedback.mediumImpact();
  static void stop() => HapticFeedback.heavyImpact();
  static void done() => HapticFeedback.lightImpact();
  static void error() => HapticFeedback.heavyImpact();
}
