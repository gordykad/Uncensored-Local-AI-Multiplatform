// Dock Tabs (@designali-in) as MiniX's bottom navigation - founder
// foundation pick, ticket 28 Amendment 7/8. Faithful mechanics: each tile's
// WIDTH animates from pointer distance (siblings reflow, never transform
// scale); tiles are the source's colored macOS-style squares with white
// glyphs. Founder color ruling: full purple, light to dark left to right.
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

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
    (Icons.chat_bubble_rounded, Color(0xFFC084FC), 'Chat'),
    (Icons.layers_rounded, Color(0xFFA855F7), 'Models'),
    (Icons.auto_awesome_rounded, Color(0xFF9333EA), 'Image Gen'),
    (Icons.settings_rounded, Color(0xFF7E22CE), 'Settings'),
  ];

  double _sizeFor(int i) {
    if (_pointerX == null) return 52;
    final ctx = _keys[i].currentContext;
    if (ctx == null) return 52;
    final tileBox = ctx.findRenderObject() as RenderBox?;
    final dockBox = context.findRenderObject() as RenderBox?;
    if (tileBox == null || dockBox == null) return 52;
    final center = tileBox.localToGlobal(Offset(tileBox.size.width / 2, 0));
    final local = dockBox.globalToLocal(center);
    final d = (_pointerX! - local.dx).abs();
    final f = (1 - d / 130).clamp(0.0, 1.0);
    return 52 + 36 * f;
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
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xB818181C),
            border: Border.all(color: AppColors.darkBorder),
            borderRadius: BorderRadius.circular(26),
            boxShadow: const [
              BoxShadow(
                color: Color(0x8C000000),
                blurRadius: 38,
                offset: Offset(0, 16),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < _tiles.length; i++) ...[
                if (i > 0) const SizedBox(width: 11),
                _cell(i),
              ],
            ],
          ),
        ),
      );
  }

  Widget _cell(int i) {
    final (icon, color, label) = _tiles[i];
    final size = _sizeFor(i);
    final selected = widget.selectedIndex == i;
    return GestureDetector(
      onTap: () => widget.onSelect(i),
      child: Column(
        key: _keys[i],
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
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
              color: selected
                  ? AppColors.darkTextM
                  : Colors.transparent,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              color: selected ? AppColors.darkTextM : AppColors.darkTextD,
            ),
          ),
        ],
      ),
    );
  }
}
