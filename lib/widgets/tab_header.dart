import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../theme/app_colors.dart';
import 'faithful/textfx.dart';

/// UI audit 2026-11-06 (Claude P2-10): Models and Settings carried a
/// 52pt bordered top bar while Image Gen and Previous Gens floated
/// bare 19pt title rows. One shared bar now: same height, same
/// border, same title treatment on every tab and pushed page.
class TabHeader extends StatelessWidget {
  final String title;
  final bool showBackButton;
  final double topInset;
  final VoidCallback? onBack;
  final List<Widget> trailing;

  const TabHeader({
    super.key,
    required this.title,
    this.showBackButton = false,
    this.topInset = 0,
    this.onBack,
    this.trailing = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(top: topInset, left: 4, right: 4),
      decoration: BoxDecoration(
        color: context.bg,
        border: Border(
          bottom: BorderSide(color: context.border, width: 0.5),
        ),
      ),
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            if (showBackButton)
              IconButton(
                tooltip: 'Back',
                icon: Icon(Icons.arrow_back_rounded, color: context.text),
                onPressed: onBack ?? () => Get.back(),
              ),
            if (!showBackButton) const SizedBox(width: 12),
            BlurReveal(
              text: title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: context.text,
              ),
            ),
            const Spacer(),
            ...trailing,
          ],
        ),
      ),
    );
  }
}
