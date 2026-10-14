import 'package:flutter/material.dart';

import '../models/monitored_pond.dart';
import '../widgets/status_badge.dart';
import 'metric_type.dart';

/// Ported from the farmer app (IsdaSafeV2 `widgets/metric_range_bar.dart`).
///
/// Compact "value vs. healthy range" bar: a track split into
/// critical/warning/normal zones with a marker at the reading's position. The
/// value itself is always shown as text too; this only adds context.
class MetricRangeBar extends StatelessWidget {
  const MetricRangeBar({super.key, required this.type, required this.value});

  final MetricType type;
  final double value;

  @override
  Widget build(BuildContext context) {
    final bands = metricBands[type]!;
    final status = bands.statusFor(value);
    final position = bands.positionOf(value);
    final markerColor = status.colorOf(context);
    final segments = _segments(bands);

    return SizedBox(
      height: 14,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: SizedBox(
                  height: 6,
                  width: width,
                  child: Row(
                    // The zones are empty boxes: without stretch they'd
                    // have no height.
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final segment in segments)
                        Expanded(
                          flex: (segment.$2 * 1000).round().clamp(1, 1000),
                          child: ColoredBox(
                            color: segment.$1
                                .colorOf(context)
                                .withValues(alpha: 0.35),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: (width - 10).clamp(0, double.infinity) * position,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: markerColor,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.surface,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Zone widths (as a fraction of the display range), left to right:
  /// critical-low, warning-low, normal, warning-high, critical-high. Zones
  /// with no threshold on that side collapse to nothing.
  List<(ReadingStatus, double)> _segments(MetricBands bands) {
    final span = bands.displayMax - bands.displayMin;
    double frac(double from, double to) => ((to - from) / span).clamp(0.0, 1.0);

    final criticalLowEnd = bands.criticalLow ?? bands.displayMin;
    final warningLowEnd = bands.warningLow ?? criticalLowEnd;
    final warningHighStart = bands.warningHigh ?? bands.displayMax;
    final criticalHighStart = bands.criticalHigh ?? warningHighStart;

    return [
      (ReadingStatus.critical, frac(bands.displayMin, criticalLowEnd)),
      (ReadingStatus.warning, frac(criticalLowEnd, warningLowEnd)),
      (ReadingStatus.normal, frac(warningLowEnd, warningHighStart)),
      (ReadingStatus.warning, frac(warningHighStart, criticalHighStart)),
      (ReadingStatus.critical, frac(criticalHighStart, bands.displayMax)),
    ];
  }
}
