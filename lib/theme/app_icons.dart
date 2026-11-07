import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// UI audit 2026-11-06 (Claude P2-1, Codex P2-28): the app face is
/// Lucide-style by house law, but the code carried 60+ stock Material
/// glyphs. New icon picks go through this mapping so the family stays
/// one voice; the heaviest offenders (dock, status checks, pins, the
/// drawer bolt, the person avatar) were converted first.
abstract final class AppIcons {
  static const IconData chat = LucideIcons.messageCircle;
  static const IconData models = LucideIcons.boxes;
  static const IconData imageGen = LucideIcons.sparkles;
  static const IconData settings = LucideIcons.settings;
  static const IconData star = LucideIcons.star;
  static const IconData pin = LucideIcons.pin;
  static const IconData play = LucideIcons.play;
  static const IconData stop = LucideIcons.square;
  static const IconData zap = LucideIcons.zap;
  static const IconData user = LucideIcons.user;
  static const IconData check = LucideIcons.check;
  static const IconData checkCircle = LucideIcons.circleCheck;
  static const IconData errorCircle = LucideIcons.circleAlert;
  static const IconData download = LucideIcons.download;
  static const IconData trash = LucideIcons.trash2;
  static const IconData copy = LucideIcons.copy;
  static const IconData share = LucideIcons.share2;
  static const IconData regenerate = LucideIcons.refreshCw;
  static const IconData close = LucideIcons.x;
  static const IconData add = LucideIcons.plus;
  static const IconData search = LucideIcons.search;
  static const IconData wifi = LucideIcons.wifi;
  static const IconData wifiOff = LucideIcons.wifiOff;
  static const IconData more = LucideIcons.moreHorizontal;
  static const IconData send = LucideIcons.send;
  static const IconData sliders = LucideIcons.slidersHorizontal;
  static const IconData warning = LucideIcons.triangleAlert;
}
