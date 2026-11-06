// Metadata-only packs — DIFFERENT EVIDENCE CLASS (flagged for the ship
// report): these three packs bank no runnable bundle, so the ports follow
// the banked page.md + NOTES.md pattern reads and the artifact-page demo
// behavior, not extracted source constants.
//
// #4 SegmentedControl (page/NOTES): radio-group segmented control with an
// animated sliding thumb; NOTES re-skin: track zinc-800 inset, thumb
// zinc-100 with dark label, thumb spring = house (260/24) -> stiffness
// 260, damping 24. MiniX: track = input fill, thumb = primary text,
// selected label = void black.
//
// #10 ChatThreadSkeleton (page/NOTES): avatar circle + alternating
// bubbles + input bar in shimmer skeleton; shimmer sweep slow and dim
// (zinc-700 -> zinc-800). MiniX blocks on panel tones.
//
// #11 ApprovalCard (page/NOTES): human-in-the-loop decision card —
// context up top, decision actions pinned at the bottom; approve is the
// card's single accent action, reject/skip stays ghost.
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'package:flutter/physics.dart';

// --------------------------------------------------------- Segmented (#4)
class MinixSegmented extends StatefulWidget {
  final List<String> options;
  final int index;
  final ValueChanged<int> onChanged;
  const MinixSegmented({
    super.key,
    required this.options,
    required this.index,
    required this.onChanged,
  });

  @override
  State<MinixSegmented> createState() => _MinixSegmentedState();
}

class _MinixSegmentedState extends State<MinixSegmented>
    with SingleTickerProviderStateMixin {
  late final AnimationController _thumb;
  double _pos = 0;

  @override
  void initState() {
    super.initState();
    _pos = widget.index.toDouble();
    _thumb = AnimationController.unbounded(vsync: this, value: _pos);
    _thumb.addListener(() {
      if (mounted) setState(() => _pos = _thumb.value);
    });
  }

  @override
  void didUpdateWidget(MinixSegmented old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      // UI audit 2026-11-06 (Codex P1-11): under Reduce Motion the
      // thumb snaps; the spring runs only when motion is allowed.
      if (MediaQuery.disableAnimationsOf(context)) {
        _thumb.stop();
        _thumb.value = widget.index.toDouble();
        return;
      }
      _thumb.animateWith(
        SpringSimulation(
          const SpringDescription(mass: 1, stiffness: 260, damping: 24),
          _pos,
          widget.index.toDouble(),
          _thumb.velocity,
        ),
      );
    }
  }

  @override
  void dispose() {
    _thumb.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.options.length;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.darkBgInput,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.darkBorderFaint),
      ),
      padding: const EdgeInsets.all(3),
      child: LayoutBuilder(
        builder: (_, box) {
          final segW = box.maxWidth / n;
          // UI audit 2026-11-06: segments get a 44pt hit height.
          return SizedBox(
            height: 44,
            child: Stack(
              children: [
                Positioned(
                  left: _pos * segW,
                  top: 0,
                  child: Container(
                    width: segW,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.darkText,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < n; i++)
                      Expanded(
                        child: GestureDetector(
                          onTap: () => widget.onChanged(i),
                          behavior: HitTestBehavior.opaque,
                          child: Semantics(
                            button: true,
                            selected: i == widget.index,
                            label: widget.options[i],
                            child: Center(
                            child: Text(
                              widget.options[i],
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: (_pos - i).abs() < 0.5
                                    ? const Color(0xFF050506)
                                    : AppColors.darkTextM,
                              ),
                            ),
                          ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------- Skeleton (#10)
class ChatThreadSkeleton extends StatefulWidget {
  const ChatThreadSkeleton({super.key});

  @override
  State<ChatThreadSkeleton> createState() => _ChatThreadSkeletonState();
}

class _ChatThreadSkeletonState extends State<ChatThreadSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void initState() {
    super.initState();
    // UI audit 2026-11-06: the shimmer never starts under Reduce
    // Motion; the blocks render at their resting opacity.
    if (!MediaQuery.disableAnimationsOf(context)) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _block(double w, double h, {bool circle = false}) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final sweep = 0.5 + 0.5 * (1 - (2 * (_c.value - 0.5)).abs());
        final col = Color.lerp(
            const Color(0xFF17171A), const Color(0xFF232328), sweep)!;
        return Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: col,
            shape: circle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: circle ? null : BorderRadius.circular(8),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _block(30, 30, circle: true),
            const SizedBox(width: 10),
            _block(190, 54),
          ],
        ),
        const SizedBox(height: 14),
        Align(alignment: Alignment.centerRight, child: _block(150, 40)),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _block(30, 30, circle: true),
            const SizedBox(width: 10),
            _block(230, 74),
          ],
        ),
        const SizedBox(height: 18),
        _block(double.infinity, 46),
      ],
    );
  }
}

// ---------------------------------------------------------- Approval (#11)
class ApprovalCard extends StatelessWidget {
  final String title;
  final String body;
  final String approveLabel;
  final String rejectLabel;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  const ApprovalCard({
    super.key,
    required this.title,
    required this.body,
    required this.onApprove,
    required this.onReject,
    this.approveLabel = 'Approve',
    this.rejectLabel = 'Reject',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkBgPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.darkText,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(color: AppColors.darkTextM, fontSize: 13),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onReject,
                child: Text(
                  rejectLabel,
                  style: const TextStyle(color: AppColors.darkTextM),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: onApprove,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                ),
                child: Text(approveLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
