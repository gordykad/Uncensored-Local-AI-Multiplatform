// StatisticsCard (#9) — port from the banked source (pack
// statistics-card-10, ReUI). The component is a stat-first card: small
// label, one big value, a delta pill (trend arrow + %, green/red), and a
// supporting sparkline. Its motion is the library's enter treatment
// (fade + rise, tailwindcss-animate) and the sparkline's stroke draw-in.
// Values are ALWAYS the app's real numbers (founder rule from ticket 08:
// never the demo's sample data).
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class MinixStatsCard extends StatefulWidget {
  final String label;
  final String value;
  final String? delta; // e.g. "+5.4x"
  final bool deltaUp;
  final List<double>? spark;
  const MinixStatsCard({
    super.key,
    required this.label,
    required this.value,
    this.delta,
    this.deltaUp = true,
    this.spark,
  });

  @override
  State<MinixStatsCard> createState() => _MinixStatsCardState();
}

class _MinixStatsCardState extends State<MinixStatsCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final enter = Curves.easeOut.transform((_c.value / 0.5).clamp(0, 1));
        return Opacity(
          opacity: enter,
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - enter)),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0C0C0E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1A1A1E)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        widget.label.toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFF9C9CA3),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.1,
                        ),
                      ),
                      if (widget.delta != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: (widget.deltaUp
                                    ? const Color(0xFF3FB950)
                                    : const Color(0xFFF85149))
                                .withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                widget.deltaUp
                                    ? Icons.arrow_upward
                                    : Icons.arrow_downward,
                                size: 10,
                                color: widget.deltaUp
                                    ? const Color(0xFF3FB950)
                                    : const Color(0xFFF85149),
                              ),
                              const SizedBox(width: 2),
                              Text(
                                widget.delta!,
                                style: TextStyle(
                                  color: widget.deltaUp
                                      ? const Color(0xFF3FB950)
                                      : const Color(0xFFF85149),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.value,
                    style: const TextStyle(
                      color: Color(0xFFF2F2F0),
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                    ),
                  ),
                  if (widget.spark != null && widget.spark!.length > 1) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 28,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: _SparkPainter(
                          values: widget.spark!,
                          progress: Curves.easeOut.transform(_c.value),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SparkPainter extends CustomPainter {
  final List<double> values;
  final double progress;
  _SparkPainter({required this.values, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final range = (maxV - minV) == 0 ? 1.0 : maxV - minV;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = size.height -
          3 -
          (size.height - 6) * (values[i] - minV) / range;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final metric = path.computeMetrics().first;
    final partial = metric.extractPath(0, metric.length * progress);
    final fillPath = Path.from(partial)
      ..lineTo(size.width * progress, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, size.height),
          [
            const Color(0xFF9333EA).withValues(alpha: 0.30),
            const Color(0xFF9333EA).withValues(alpha: 0),
          ],
        ),
    );
    canvas.drawPath(
      partial,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFA855F7),
    );
  }

  @override
  bool shouldRepaint(_SparkPainter old) => progress != old.progress;
}
