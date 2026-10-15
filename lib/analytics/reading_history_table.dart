import 'package:flutter/material.dart';

import '../models/monitored_pond.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../widgets/status_badge.dart';
import 'lazy_load_footer.dart';
import 'metric_type.dart';
import 'readings_pager.dart';
import 'trend_range.dart';

/// Ported from the farmer app (IsdaSafeV2 `widgets/reading_history_table.dart`).
///
/// The timeframe's readings, newest first and grouped by day, with a column
/// per metric the device sent. Values outside the healthy range are colored
/// by status. Wide screens get a table, narrow ones a card per row. Rows come
/// from a [ReadingsPager], a page at a time as the list is scrolled to its
/// end; give it a key per pond and timeframe so it starts over.
class ReadingHistoryTable extends StatefulWidget {
  const ReadingHistoryTable({super.key, required this.pager, this.types});

  final ReadingsPager pager;

  /// Only these metrics' columns; by default every metric with a value.
  final List<MetricType>? types;

  @override
  State<ReadingHistoryTable> createState() => _ReadingHistoryTableState();
}

class _ReadingHistoryTableState extends State<ReadingHistoryTable> {
  @override
  void initState() {
    super.initState();
    widget.pager.loadMore();
  }

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: widget.pager, builder: _build);

  Widget _build(BuildContext context, Widget? _) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final pager = widget.pager;
    final wanted = widget.types ?? _defaultOrder;

    final byTime = <DateTime, Map<MetricType, double>>{};
    for (final row in pager.rows) {
      final values = {
        for (final e in row.values.entries)
          if (wanted.contains(e.key)) e.key: e.value,
      };
      if (values.isNotEmpty) byTime[row.time] = values;
    }
    // Leave out metrics the device never sent, rather than a column of
    // dashes.
    final types = [
      for (final type in wanted)
        if (byTime.values.any((v) => v.containsKey(type))) type,
    ];
    final times = byTime.keys.toList()..sort((a, b) => b.compareTo(a));

    if (times.isEmpty) {
      if (pager.loading || (pager.remaining > 0 && pager.error == null)) {
        return const Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Row(
            children: [
              Icon(Icons.table_rows_outlined, color: muted),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  pager.error == null
                      ? 'No readings in this timeframe'
                      : 'Couldn\'t load the readings.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
              ),
              if (pager.error != null)
                TextButton.icon(
                  onPressed: pager.loadMore,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
            ],
          ),
        ),
      );
    }

    final outOfRange = times
        .where(
          (t) => byTime[t]!.entries.any(
            (e) =>
                metricBands[e.key]!.statusFor(e.value) != ReadingStatus.normal,
          ),
        )
        .length;
    final remaining = pager.remaining;
    final colors = context.statusColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              outOfRange == 0
                  ? Icons.check_circle_outline
                  : Icons.warning_amber_outlined,
              size: 16,
              color: outOfRange == 0 ? colors.good : colors.warning,
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                // Counted over the rows loaded so far.
                outOfRange == 0
                    ? (remaining > 0
                          ? 'None outside healthy range so far'
                          : 'All within healthy range')
                    : (remaining > 0
                          ? '$outOfRange outside healthy range so far'
                          : '$outOfRange outside healthy range'),
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Card(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final rows = <Widget>[];
              rows.add(_HeaderRow(types: types));
              DateTime? currentDay;
              for (final time in times) {
                final day = DateUtils.dateOnly(time);
                if (!pager.withDates &&
                    day != currentDay &&
                    (pager.step?.withinDay ?? true)) {
                  currentDay = day;
                  rows.add(_DayHeader(label: _dayLabel(time)));
                } else if (time != times.first) {
                  rows.add(const Divider(height: 1));
                }
                final label = pager.withDates
                    ? (pager.step?.fullLabel(time) ??
                          TrendStep.fifteenMinutes.fullLabel(time))
                    : pager.step?.rowLabel(time) ?? clockLabel(time);
                rows.add(
                  _TableRow(time: label, types: types, values: byTime[time]!),
                );
              }
              final table = Column(children: rows);
              // The same table as on a wide screen; a phone scrolls it
              // sideways instead of squeezing it.
              final tableWidth =
                  _timeColumnWidth +
                  AppSpacing.lg * 2 +
                  types.length * _metricColumnWidth;
              if (constraints.maxWidth >= tableWidth) return table;
              return _SidewaysScroll(width: tableWidth, child: table);
            },
          ),
        ),
        if (pager.loading)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Center(
              child: SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (pager.error != null)
          Center(
            child: TextButton.icon(
              onPressed: pager.loadMore,
              icon: const Icon(Icons.refresh),
              label: const Text('Couldn\'t load more readings. Retry'),
            ),
          )
        else
          LazyLoadFooter(remaining: remaining, onLoadMore: pager.loadMore),
      ],
    );
  }

  static const _defaultOrder = [
    MetricType.temperature,
    MetricType.dissolvedOxygen,
    MetricType.ph,
    MetricType.freeAmmonia,
    MetricType.ammonia,
    MetricType.humidity,
    MetricType.airTemperature,
  ];

  String _dayLabel(DateTime t) {
    final today = DateUtils.dateOnly(DateTime.now());
    final day = DateUtils.dateOnly(t);
    if (day == today) return 'Today';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return '${t.month}/${t.day}/${t.year}';
  }
}

const _timeColumnWidth = 128.0;

/// The narrowest a metric's column gets before the table scrolls sideways.
const _metricColumnWidth = 104.0;

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.types});

  final List<MetricType> types;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );
    return Container(
      color: theme.colorScheme.surfaceContainer,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          SizedBox(
            width: _timeColumnWidth,
            child: Text('Time', style: style),
          ),
          for (final type in types)
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(type.icon, size: 14, color: metricColor(context, type)),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      type.unit.isEmpty
                          ? type.label
                          : '${type.label} (${type.unit})',
                      style: style,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs + 2,
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.time,
    required this.types,
    required this.values,
  });

  final String time;
  final List<MetricType> types;
  final Map<MetricType, double> values;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm + 2,
      ),
      child: Row(
        children: [
          SizedBox(
            width: _timeColumnWidth,
            child: Text(
              time,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          for (final type in types)
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: _Value(type: type, value: values[type], showUnit: false),
              ),
            ),
        ],
      ),
    );
  }
}

/// The table scrolled sideways on a phone, with cues that it can be: a hint
/// above while it's still at the start, a fading arrow on the right edge
/// until the last column is reached, and a visible scrollbar.
class _SidewaysScroll extends StatefulWidget {
  const _SidewaysScroll({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  State<_SidewaysScroll> createState() => _SidewaysScrollState();
}

class _SidewaysScrollState extends State<_SidewaysScroll> {
  final _controller = ScrollController();
  var _atStart = true;
  var _atEnd = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _onNotification(Notification n) {
    final metrics = switch (n) {
      ScrollNotification() => n.metrics,
      ScrollMetricsNotification() => n.metrics,
      _ => null,
    };
    if (metrics == null || metrics.axis != Axis.horizontal) return false;
    final atStart = metrics.pixels <= metrics.minScrollExtent + 4;
    final atEnd = metrics.pixels >= metrics.maxScrollExtent - 4;
    if (atStart != _atStart || atEnd != _atEnd) {
      // Notifications can arrive mid-layout; update after the frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _atStart = atStart;
            _atEnd = atEnd;
          });
        }
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: _atStart
              ? Container(
                  color: scheme.secondaryContainer.withValues(alpha: 0.5),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.xs + 2,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.swipe,
                        size: 16,
                        color: scheme.onSecondaryContainer,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Swipe sideways to see every sensor',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        Stack(
          children: [
            NotificationListener<Notification>(
              onNotification: _onNotification,
              child: Scrollbar(
                controller: _controller,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _controller,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(width: widget.width, child: widget.child),
                ),
              ),
            ),
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _atEnd ? 0 : 1,
                  duration: const Duration(milliseconds: 150),
                  child: Container(
                    width: 36,
                    alignment: Alignment.centerRight,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          scheme.surface.withValues(alpha: 0),
                          scheme.surface.withValues(alpha: 0.95),
                        ],
                      ),
                    ),
                    child: Icon(
                      Icons.chevron_right,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A value colored by its status (with a dot when outside the healthy
/// range), or "—" when the sensor had nothing then.
class _Value extends StatelessWidget {
  const _Value({
    required this.type,
    required this.value,
    required this.showUnit,
  });

  final MetricType type;
  final double? value;
  final bool showUnit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = this.value;
    final base = theme.textTheme.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    if (value == null) {
      return Text(
        '—',
        style: base?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      );
    }
    final status = metricBands[type]!.statusFor(value);
    final normal = status == ReadingStatus.normal;
    final color = status.colorOf(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!normal) ...[
          Tooltip(
            message: status.label,
            child: Icon(Icons.circle, size: 8, color: color),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              showUnit ? type.format(value) : type.formatValue(value),
              style: base?.copyWith(
                color: normal ? null : color,
                fontWeight: normal ? null : FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
