// RedactionBars — DESIGN.md motif (not a 21st component): pure-black bars
// with a 1px strong-border edge, used on splash / About / empty states.
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class RedactionBars extends StatelessWidget {
  final List<double> widths;
  final double barHeight;
  const RedactionBars({
    super.key,
    this.widths = const [120, 84, 142, 64],
    this.barHeight = 10,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < widths.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          Container(
            width: widths[i],
            height: barHeight,
            decoration: BoxDecoration(
              color: Colors.black,
              border: Border.all(color: AppColors.darkBorder, width: 1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ],
    );
  }
}
