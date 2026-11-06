// Dock Tabs (@designali-in) as MiniX's bottom navigation - founder
// foundation pick, ticket 28 Amendment 7/8. Faithful mechanics: each tile's
// WIDTH animates from pointer distance (siblings reflow, never transform
// scale); tiles are the source's colored macOS-style squares with white
// glyphs. Founder color ruling: full purple, light to dark left to right.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/type_scale.dart';

class DockNav extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  const DockNav({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
  });

  @override
  State<DockNav> createState() => _DockNavState();
}

class _DockNavState extends State<DockNav> {
  double? _pointerX;
  final List<GlobalKey> _keys = List.generate(4, (_) => GlobalKey());

  // Founder ramp, light -> dark (Amendment 8). Previous Gens is NOT
  // a dock tab - it is a button inside Image Gen (Kai, 2026-11-04).
  static const _tiles = [
    (AppIcons.chat, Color(0xFFC084FC), 'Chat'),
    (AppIcons.models, Color(0xFFA855F7), 'Models'),
    (AppIcons.imageGen, Color(0xFF9333EA), 'Image Gen'),
    (AppIcons.settings, Color(0xFF7E22CE), 'Settings'),
  ];

  // 1.13.0 (Kai): the dock runs ~15% wider than the 1.12.0 build —
  // tile 52 -> 58, gaps and padding scaled to match (267 -> 306 px).
  double _sizeFor(int i) {
    // UI audit 2026-11-06 P3-4: Reduce Motion freezes the magnify.
    if (RM.off(context)) return 58;
    if (_pointerX == null) return 58;
    final ctx = _keys[i].currentContext;
    if (ctx == null) return 58;
    final tileBox = ctx.findRenderObject() as RenderBox?;
    final dockBox = context.findRenderObject() as RenderBox?;
    if (tileBox == null || dockBox == null) return 58;
    final center = tileBox.localToGlobal(Offset(tileBox.size.width / 2, 0));
    final local = dockBox.globalToLocal(center);
    final d = (_pointerX! - local.dx).abs();
    final f = (1 - d / 145).clamp(0.0, 1.0);
    return 58 + 40 * f;
  }

  @override
  Widget build(BuildContext context) {
    // NO Center/Align root here: inside Scaffold.bottomNavigationBar an
    // expanding widget takes the full screen height and starves the body
    // (the 1.9.0 dock-only bug). The host centers the pill horizontally.
    return Listener(
      onPointerMove: (e) => setState(() => _pointerX = e.localPosition.dx),
      onPointerDown: (e) => setState(() => _pointerX = e.localPosition.dx),
      onPointerUp: (_) => setState(() => _pointerX = null),
      onPointerCancel: (_) => setState(() => _pointerX = null),
      // Audit #6 (approved 2026-11-05): the dock is a material too —
      // same translucent fill, now with the blur behind it. The
      // shadow lives OUTSIDE the clip so it survives.
      child: Container(
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(26)),
          boxShadow: [
            BoxShadow(
              color: Color(0x8C000000),
              blurRadius: 38,
              offset: Offset(0, 16),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xB818181C),
                border: Border.all(color: AppColors.darkBorder),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < _tiles.length; i++) ...[
                    if (i > 0) const SizedBox(width: 14),
                    _cell(i),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cell(int i) {
    final (icon, color, label) = _tiles[i];
    final size = _sizeFor(i);
    final selected = widget.selectedIndex == i;
    // UI audit 2026-11-06 P1-9: tiles announce as selectable buttons.
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: () => widget.onSelect(i),
      child: GestureDetector(
        onTap: () => widget.onSelect(i),
      child: Column(
        key: _keys[i],
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            // Audit #7: tile motion rides a damped spring; audit #3:
            // Reduce Motion snaps instead.
            duration: RM.off(context)
                ? Duration.zero
                : const Duration(milliseconds: 300),
            curve: const _SpringCurve(),
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x73000000),
                  blurRadius: 16,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: size * 0.52),
          ),
          const SizedBox(height: 3),
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? AppColors.darkTextM : Colors.transparent,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: TS.of(context, 9),
              color: selected ? AppColors.darkTextM : AppColors.darkTextD,
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// Audit #7: a damped-spring curve (settle ~300ms, a breath of
/// overshoot) for the dock's tile motion — the macOS dock feel the
/// source component implies but never encoded.
class _SpringCurve extends Curve {
  const _SpringCurve();

  @override
  double transformInternal(double t) {
    if (t <= 0) return 0;
    if (t >= 1) return 1;
    final v = 1 - math.exp(-7 * t) * (math.cos(9 * t) + 0.78 * math.sin(9 * t));
    return v.clamp(-0.1, 1.12).toDouble();
  }
}
