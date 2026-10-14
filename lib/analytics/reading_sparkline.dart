import 'package:flutter/material.dart';

import '../widgets/status_badge.dart';
import 'metric_type.dart';

/// Ported from the farmer app (IsdaSafeV2 `widgets/reading_sparkline.dart`).
///
/// A bare trend line for one metric's recent [values] (oldest first), on the
/// metric's display range so a dip toward unsafe looks like one. Colored by
/// the last value's status for water readings, by the metric's own color
/// otherwise. No axes or labels: a stat-tile sparkline, not a chart.
class ReadingSparkline extends StatelessWidget {
  const ReadingSparkline({
    super.key,
    required this.type,
    required this.values,
    this.height = 32,
    this.color,
  });

  final MetricType type;
  final List<double> values;
  final double height;

  /// Overrides the line's color (e.g. the current reading's status, when
  /// the last point is an average).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final bands = metricBands[type]!;
    final color =
        this.color ??
        (MetricType.water.contains(type) && values.isNotEmpty
            ? bands.statusFor(values.last).colorOf(context)
            : metricColor(context, type));
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparklinePainter(
          positions: [for (final v in values) bands.positionOf(v)],
          color: color,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.positions, required this.color});

  final List<double> positions;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (positions.length < 2) return;

    // 0 (display min) .. 1 (display max), flipped so higher sits higher,
    // inset so the line never clips.
    const inset = 4.0;
    final dx = size.width / (positions.length - 1);
    Offset pointAt(int i) =>
        Offset(dx * i, inset + (1 - positions[i]) * (size.height - inset * 2));

    final line = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var i = 1; i < positions.length; i++) {
      final p = pointAt(i);
      line.lineTo(p.dx, p.dy);
    }
    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(pointAt(positions.length - 1), 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.positions != positions || oldDelegate.color != color;
}
