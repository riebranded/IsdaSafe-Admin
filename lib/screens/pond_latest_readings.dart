import 'package:flutter/material.dart';

import '../analytics/individual_trend_chart.dart';
import '../analytics/metric_range_bar.dart';
import '../analytics/metric_type.dart';
import '../analytics/reading_sparkline.dart';
import '../analytics/trend_range.dart';
import '../analytics/trend_service.dart';
import '../models/monitored_pond.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../widgets/status_badge.dart';

/// The pond page's "Latest readings", modelled on the farmer app's reading
/// cards: the water readings that decide the pond's status first, then the
/// weather and other readings for context. Each card shows the value, how
/// it moved since the previous step, a sparkline over the page's timeframe,
/// where it sits in the healthy range and, when it's outside, by how much.
/// Tapping one opens its detail view.
class LatestReadingsSection extends StatelessWidget {
  const LatestReadingsSection({
    super.key,
    required this.pond,
    required this.latest,
    required this.trend,
    required this.onOpen,
  });

  final MonitoredPond pond;
  final Map<MetricType, SensorReading> latest;

  /// The page's trend (its timeframe): the sparklines and "since the
  /// previous step" come from it.
  final AdminTrendController trend;
  final ValueChanged<MetricType> onOpen;

  static const _water = [
    MetricType.temperature,
    MetricType.dissolvedOxygen,
    MetricType.ph,
    MetricType.freeAmmonia,
  ];
  static const _other = [
    MetricType.humidity,
    MetricType.airTemperature,
    MetricType.ammonia,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final readingAt = pond.readingAt;
    final flagged = [
      for (final type in _water)
        if (latest[type] case final r?)
          if (metricBands[type]!.statusFor(r.value) != ReadingStatus.normal)
            type,
    ];
    final others = [for (final type in _other) ?latest[type]];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.sensors, size: 22, color: theme.colorScheme.primary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'Latest readings',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  Text(
                    readingAt == null
                        ? 'No readings yet'
                        : 'Read ${_relative(readingAt)} · tap a reading for '
                              'details',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                  if (latest.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _Summary(flagged: flagged),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (readingAt != null &&
            pond.connection() != DeviceConnection.online) ...[
          const SizedBox(height: AppSpacing.md),
          _StaleNotice(readingAt: readingAt),
        ],
        const SizedBox(height: AppSpacing.lg),
        if (latest.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Row(
                children: [
                  Icon(Icons.hourglass_empty, color: muted),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      'This device hasn\'t sent any readings yet.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ListenableBuilder(
            listenable: trend,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _GroupLabel(
                  title: 'Water quality',
                  caption: 'These decide the pond\'s status',
                ),
                const SizedBox(height: AppSpacing.sm),
                _CardGrid(
                  maxColumns: 4,
                  children: [
                    for (final type in _water)
                      _ReadingCard(
                        type: type,
                        reading: latest[type],
                        trend: trend,
                        onTap: () => onOpen(type),
                      ),
                  ],
                ),
                if (others.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  const _GroupLabel(
                    title: 'Weather & other readings',
                    caption: 'For context; they don\'t change the status',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _CardGrid(
                    maxColumns: 3,
                    children: [
                      for (final reading in others)
                        _ReadingCard(
                          type: reading.type,
                          reading: reading,
                          trend: trend,
                          onTap: () => onOpen(reading.type),
                        ),
                    ],
                  ),
                ],
                if (!trend.loading && trend.error == null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Sparklines: ${trend.selection.description}. Arrows compare '
                    'with the previous ${trend.step.label.toLowerCase()}. '
                    'Change the timeframe under Individual trends.',
                    style: theme.textTheme.labelSmall?.copyWith(color: muted),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// "2 need attention" or "All water readings normal".
class _Summary extends StatelessWidget {
  const _Summary({required this.flagged});

  final List<MetricType> flagged;

  @override
  Widget build(BuildContext context) {
    final colors = context.statusColors;
    return flagged.isEmpty
        ? StatusPill(
            label: 'All water readings normal',
            icon: Icons.check_circle,
            color: colors.good,
          )
        : StatusPill(
            label: flagged.length == 1
                ? '1 needs attention'
                : '${flagged.length} need attention',
            icon: Icons.warning_rounded,
            color: colors.warning,
          );
  }
}

class _StaleNotice extends StatelessWidget {
  const _StaleNotice({required this.readingAt});

  final DateTime readingAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = context.statusColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_off, size: 18, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'The device is offline, so these readings are from '
              '${_relative(readingAt)}. The water may have changed since.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.title, required this.caption});

  final String title;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        Text(
          title.toUpperCase(),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
        Text(
          caption,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Equal-width, equal-height cards: up to [maxColumns] per row on wide
/// screens, two on tablets, one on phones.
class _CardGrid extends StatelessWidget {
  const _CardGrid({required this.maxColumns, required this.children});

  final int maxColumns;
  final List<Widget> children;

  static const _cardHeight = 228.0;
  static const _phoneCardHeight = 184.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 960
            ? maxColumns
            : width >= 520
            ? 2
            : 1;
        final cardWidth = (width - AppSpacing.md * (columns - 1)) / columns;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final child in children)
              SizedBox(
                width: cardWidth,
                // One per row on phones: wide enough for a shorter card.
                height: columns == 1 ? _phoneCardHeight : _cardHeight,
                child: child,
              ),
          ],
        );
      },
    );
  }
}

class _ReadingCard extends StatelessWidget {
  const _ReadingCard({
    required this.type,
    required this.reading,
    required this.trend,
    required this.onTap,
  });

  final MetricType type;
  final SensorReading? reading;
  final AdminTrendController trend;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    final reading = this.reading;
    final judged = MetricType.water.contains(type);
    final status = reading == null
        ? null
        : metricBands[type]!.statusFor(reading.value);
    final flagged = judged && status != null && status != ReadingStatus.normal;
    final stripe = judged && status != null
        ? status.colorOf(context)
        : scheme.outlineVariant;
    final points = trend.loading || trend.error != null
        ? const <TrendPoint>[]
        : trend.pointsFor(type);

    return Card(
      color: flagged ? stripe.withValues(alpha: 0.06) : null,
      child: InkWell(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: stripe),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: metricColor(
                              context,
                              type,
                            ).withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Icon(
                            type.icon,
                            size: 16,
                            color: metricColor(context, type),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            type.label,
                            style: theme.textTheme.labelLarge,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (judged && status != null)
                          StatusPill.status(status, context),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (reading == null) ...[
                      Text(
                        '—',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: muted,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'No reading from this sensor',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                    ] else ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                type.format(reading.value),
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: flagged ? stripe : null,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Flexible(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: _Change(
                                type: type,
                                value: reading.value,
                                points: points,
                                step: trend.step,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Expanded(
                        child: trend.loading
                            ? Center(
                                child: Container(
                                  height: 2,
                                  color: scheme.surfaceContainerHighest,
                                ),
                              )
                            : points.length < 2
                            ? const SizedBox.shrink()
                            : ReadingSparkline(
                                type: type,
                                values: [for (final p in points) p.avg],
                                height: double.infinity,
                                // The reading's own status, not the last
                                // step's average.
                                color: judged ? stripe : null,
                              ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      MetricRangeBar(type: type, value: reading.value),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        flagged
                            ? _outOfRange(type, reading.value)
                            : _rangeNote(type),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: flagged ? stripe : muted,
                          fontWeight: flagged ? FontWeight.w700 : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How far the latest value moved from the previous step's average:
/// "▲ 0.4°C", or "No change".
class _Change extends StatelessWidget {
  const _Change({
    required this.type,
    required this.value,
    required this.points,
    required this.step,
  });

  final MetricType type;
  final double value;
  final List<TrendPoint> points;
  final TrendStep step;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final previous = points[points.length - 2].avg;
    // At display precision, so "+0.0" never shows as a change.
    final delta =
        double.parse(type.formatValue(value)) -
        double.parse(type.formatValue(previous));
    final since = step == TrendStep.fifteenMinutes
        ? 'the 15 minutes before'
        : 'the previous ${step.label.toLowerCase()}';
    return Tooltip(
      message: delta == 0
          ? 'Same as $since (average ${type.format(previous)})'
          : '${delta > 0 ? 'Up' : 'Down'} ${type.format(delta.abs())} from '
                '$since (average ${type.format(previous)})',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (delta != 0)
            Icon(
              delta > 0 ? Icons.arrow_drop_up : Icons.arrow_drop_down,
              size: 20,
              color: muted,
            ),
          Flexible(
            child: Text(
              delta == 0 ? 'No change' : type.format(delta.abs()),
              style: theme.textTheme.labelSmall?.copyWith(color: muted),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Healthy: 25.0 – 29.0 °C", or what a reading without a healthy range
/// is (humidity is weather).
String _rangeNote(MetricType type) => switch (healthyRangeLabel(type)) {
  '—' => 'Weather reading, no healthy range',
  final range => 'Healthy: $range',
};

/// "1.4°C above healthy", "1.2mg/L below healthy".
String _outOfRange(MetricType type, double value) {
  final bands = metricBands[type]!;
  if (bands.warningHigh case final high? when value > high) {
    return '${type.format(value - high)} above healthy';
  }
  if (bands.warningLow case final low? when value < low) {
    return '${type.format(low - value)} below healthy';
  }
  return _rangeNote(type);
}

String _relative(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return '${diff.inDays} d ago';
}
