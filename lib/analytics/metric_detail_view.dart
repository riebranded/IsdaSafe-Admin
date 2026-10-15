import 'reading_days.dart';
import 'package:flutter/material.dart';

import '../models/monitored_pond.dart';
import '../theme/app_spacing.dart';
import '../widgets/status_badge.dart';
import 'individual_trend_chart.dart';
import 'latest_readings.dart';
import 'metric_guidance.dart';
import 'metric_range_bar.dart';
import 'metric_type.dart';
import 'reading_history_table.dart';
import 'readings_pager.dart';
import 'timeframe_picker.dart';
import 'trend_range.dart';
import 'trend_service.dart';

/// Opens [MetricDetailView] for [type]: a dialog on wide windows, its own
/// page on phones — as in the farmer app.
Future<void> showMetricDetail(
  BuildContext context, {
  required MonitoredPond pond,
  required MetricType type,
  required TrendSelection initialSelection,
  required TrendRange lastPreset,
}) {
  MetricDetailView view({required bool showHeader}) => MetricDetailView(
    pond: pond,
    type: type,
    initialSelection: initialSelection,
    lastPreset: lastPreset,
    showHeader: showHeader,
  );
  if (MediaQuery.sizeOf(context).width >= kWideLayoutBreakpoint) {
    return showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880, maxHeight: 860),
          child: view(showHeader: true),
        ),
      ),
    );
  }
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        appBar: AppBar(
          title: Text(type.label),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(20),
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                pond.pondName,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
        body: SafeArea(child: view(showHeader: false)),
      ),
    ),
  );
}

/// Ported from the farmer app (IsdaSafeV2 `widgets/metric_detail_view.dart`).
///
/// One metric in depth, top to bottom: its current value(s) with status and
/// where they sit in the healthy range; what the farmer should do when it's
/// out of range; its trend over a timeframe with the lowest / average /
/// highest; every step's reading (folded away until asked for); and what it
/// measures. Humidity and free ammonia show their companion reading (air
/// temperature, total ammonia) alongside.
class MetricDetailView extends StatefulWidget {
  const MetricDetailView({
    super.key,
    required this.pond,
    required this.type,
    required this.initialSelection,
    required this.lastPreset,
    this.showHeader = true,
  });

  final MonitoredPond pond;
  final MetricType type;
  final TrendSelection initialSelection;
  final TrendRange lastPreset;

  /// The title and close button; off when a page's app bar shows them.
  final bool showHeader;

  @override
  State<MetricDetailView> createState() => _MetricDetailViewState();
}

class _MetricDetailViewState extends State<MetricDetailView> {
  late TrendSelection _selection = widget.initialSelection;
  late TrendRange _lastPreset = widget.lastPreset;

  /// Which series the trend shows (the metric or a companion).
  late MetricType _trendOf = widget.type;

  late AdminTrendController _trend = AdminTrendController(
    widget.pond.pondId,
    _selection,
  );
  late ReadingsPager _pager = ReadingsPager.forTrend(_trend);

  void _select(TrendSelection selection) {
    if (selection == _selection) return;
    setState(() {
      _selection = selection;
      if (selection.range case final range?) _lastPreset = range;
      _reload();
    });
  }

  void _reload() {
    _trend.dispose();
    _pager.dispose();
    _trend = AdminTrendController(widget.pond.pondId, _selection);
    _pager = ReadingsPager.forTrend(_trend);
  }

  @override
  void dispose() {
    _trend.dispose();
    _pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.type;
    final series = [type, ...type.companions];
    final all = latestReadings(widget.pond);
    final latest = {for (final t in series) t: ?all[t]};
    final guidance = [
      for (final t in series)
        if (latest[t] case final reading?)
          if (guidanceFor(t, reading.value) case final text?)
            (type: t, reading: reading, text: text),
    ];

    final body = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Now: the current value(s), and what to do about them.
          _NowTiles(types: series, latest: latest),
          for (final g in guidance) ...[
            const SizedBox(height: AppSpacing.md),
            _GuidanceCallout(type: g.type, reading: g.reading, text: g.text),
          ],
          // 2. How it's been: the trend, its summary, and the readings.
          const SizedBox(height: AppSpacing.xl),
          const _SectionTitle(icon: Icons.show_chart, title: 'Trend'),
          const SizedBox(height: AppSpacing.md),
          TimeframePicker(
            selection: _selection,
            lastPreset: _lastPreset,
            onChanged: _select,
            readingDays: () => ReadingDays.load(widget.pond.pondId),
          ),
          if (series.length > 1) ...[
            const SizedBox(height: AppSpacing.md),
            _SeriesPicker(
              types: series,
              selected: _trendOf,
              onSelected: (t) => setState(() => _trendOf = t),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          ListenableBuilder(
            listenable: _trend,
            builder: (context, _) => _TrendBlock(
              type: _trendOf,
              trend: _trend,
              latest: latest[_trendOf],
              onRetry: () => setState(_reload),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _ReadingsSection(
            key: ValueKey(_selection),
            pager: _pager,
            child: ReadingHistoryTable(pager: _pager, types: series),
          ),
          // 3. Context: what the metric is.
          const SizedBox(height: AppSpacing.xl),
          _AboutCard(types: series),
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHeader) ...[
          _Header(pond: widget.pond, type: type),
          const Divider(height: 1),
        ],
        Flexible(child: body),
      ],
    );
  }
}

/// The chart for the timeframe and its lowest / average / highest.
class _TrendBlock extends StatelessWidget {
  const _TrendBlock({
    required this.type,
    required this.trend,
    required this.latest,
    required this.onRetry,
  });

  final MetricType type;
  final AdminTrendController trend;
  final SensorReading? latest;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (trend.loading) {
      return const Card(
        child: SizedBox(
          height: 220,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (trend.error != null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.cloud_off),
          title: const Text('Couldn\'t load the trend'),
          subtitle: const Text('Check your connection and try again.'),
          trailing: TextButton(onPressed: onRetry, child: const Text('Retry')),
        ),
      );
    }
    final points = trend.pointsFor(type);
    final step = trend.step;
    final span = trend.window.duration;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IndividualTrendChart(
          type: type,
          history: [for (final p in points) p.asReading(type)],
          band: [for (final p in points) (min: p.min, max: p.max)],
          latest: latest,
          timeFormat: (t) => step.axisLabel(t, span),
          tooltipTimeFormat: step.fullLabel,
          showDetails: false,
          emptyMessage: 'No readings in this timeframe. Try a longer one.',
        ),
        if (points.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            points.any((p) => p.min != p.max)
                ? 'Line: average per step. Shaded: lowest to highest.'
                : 'Line: average per step.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TrendSummary(type: type, points: points, step: step),
        ],
      ],
    );
  }
}

/// The modal's title bar: the metric, its pond, and a close button.
class _Header extends StatelessWidget {
  const _Header({required this.pond, required this.type});

  final MonitoredPond pond;
  final MetricType type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = metricColor(context, type);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(type.icon, color: color, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(type.label, style: theme.textTheme.titleLarge),
                Text(
                  pond.ownerName == null
                      ? pond.pondName
                      : '${pond.pondName} · ${pond.ownerName}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Text(title, style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }
}

/// The current value of each of [types], side by side when there's room.
class _NowTiles extends StatelessWidget {
  const _NowTiles({required this.types, required this.latest});

  final List<MetricType> types;
  final Map<MetricType, SensorReading> latest;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      for (final type in types) _NowTile(type: type, reading: latest[type]),
    ];
    if (tiles.length == 1) return tiles.single;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, tile) in tiles.indexed) ...[
                if (i > 0) const SizedBox(height: AppSpacing.md),
                tile,
              ],
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, tile) in tiles.indexed) ...[
                if (i > 0) const SizedBox(width: AppSpacing.md),
                Expanded(child: tile),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// One metric's latest value, big, with its status, where it sits in the
/// healthy range, and how long ago it was read.
class _NowTile extends StatelessWidget {
  const _NowTile({required this.type, required this.reading});

  final MetricType type;
  final SensorReading? reading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    final reading = this.reading;
    // Humidity, air temperature and total ammonia don't decide the pond's
    // status, so they get no status pill (as in the farmer app).
    final judged = MetricType.water.contains(type);
    final status = reading == null
        ? null
        : metricBands[type]!.statusFor(reading.value);
    final accent =
        (judged ? status?.colorOf(context) : null) ?? scheme.outlineVariant;

    return Card(
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          type.icon,
                          size: 18,
                          color: metricColor(context, type),
                        ),
                        const SizedBox(width: AppSpacing.xs + 2),
                        Expanded(
                          child: Text(
                            type.label,
                            style: theme.textTheme.labelLarge,
                          ),
                        ),
                        if (judged && status != null)
                          StatusPill.status(status, context),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      reading == null ? '—' : type.format(reading.value),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: reading == null ? muted : null,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (reading != null) ...[
                      MetricRangeBar(type: type, value: reading.value),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    Text(
                      reading == null
                          ? 'No reading yet'
                          : '${_ago(reading.timestamp)} · '
                                'Healthy: ${healthyRangeLabel(type)}',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
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

String _ago(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'Updated just now';
  if (diff.inMinutes < 60) return 'Updated ${diff.inMinutes} min ago';
  if (diff.inHours < 24) return 'Updated ${diff.inHours} h ago';
  return 'Updated ${diff.inDays} d ago';
}

/// What the farmer should do about a value outside the healthy range,
/// tinted by how serious it is.
class _GuidanceCallout extends StatelessWidget {
  const _GuidanceCallout({
    required this.type,
    required this.reading,
    required this.text,
  });

  final MetricType type;
  final SensorReading reading;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = metricBands[type]!.statusFor(reading.value);
    final color = status.colorOf(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(status.icon, color: color),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What the farmer should do: ${type.label}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(text, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What each of [types] measures. The metric's own is open; its
/// companions' fold open on tap.
class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.types});

  final List<MetricType> types;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final main = types.first;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'What is ${main.label}?',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(main.description, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
          for (final companion in types.skip(1)) ...[
            const Divider(height: 1),
            Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                ),
                childrenPadding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                expandedAlignment: Alignment.centerLeft,
                leading: Icon(
                  companion.icon,
                  size: 20,
                  color: metricColor(context, companion),
                ),
                title: Text(
                  'What is ${companion.label}?',
                  style: theme.textTheme.titleSmall,
                ),
                children: [
                  Text(
                    companion.description,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Switches the trend between the metric and its companions.
class _SeriesPicker extends StatelessWidget {
  const _SeriesPicker({
    required this.types,
    required this.selected,
    required this.onSelected,
  });

  final List<MetricType> types;
  final MetricType selected;
  final ValueChanged<MetricType> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<MetricType>(
        showSelectedIcon: false,
        segments: [
          for (final t in types)
            ButtonSegment(
              value: t,
              icon: Icon(t.icon, size: 18, color: metricColor(context, t)),
              label: Text(t.label),
            ),
        ],
        selected: {selected},
        onSelectionChanged: (s) => onSelected(s.first),
      ),
    );
  }
}

/// The timeframe's lowest, average and highest value, with when the lowest
/// and highest happened, over every reading in it.
class TrendSummary extends StatelessWidget {
  const TrendSummary({
    super.key,
    required this.type,
    required this.points,
    required this.step,
  });

  final MetricType type;
  final List<TrendPoint> points;
  final TrendStep step;

  @override
  Widget build(BuildContext context) {
    final stats = statsOf(points);
    if (stats == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final judged = MetricType.water.contains(type);

    Widget stat(String label, double value, String? when) {
      final status = metricBands[type]!.statusFor(value);
      return Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelSmall),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    type.format(value),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: !judged || status == ReadingStatus.normal
                          ? null
                          : status.colorOf(context),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                if (when != null)
                  Text(
                    when,
                    maxLines: 2,
                    style: theme.textTheme.labelSmall?.copyWith(color: muted),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              stat(
                'Lowest',
                stats.lowest.min,
                step.fullLabel(stats.lowest.time),
              ),
              const SizedBox(width: AppSpacing.sm),
              stat('Average', stats.average, null),
              const SizedBox(width: AppSpacing.sm),
              stat(
                'Highest',
                stats.highest.max,
                step.fullLabel(stats.highest.time),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          stats.readings == 1
              ? 'Based on 1 reading in this timeframe'
              : 'Based on ${groupThousands(stats.readings)} readings in this '
                    'timeframe',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
      ],
    );
  }
}

/// The timeframe's readings, folded away until asked for so the trend stays
/// in view. Nothing is paged in until it's opened.
class _ReadingsSection extends StatelessWidget {
  const _ReadingsSection({super.key, required this.pager, required this.child});

  final ReadingsPager pager;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          childrenPadding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.md,
          ),
          leading: Icon(
            Icons.table_rows_outlined,
            color: theme.colorScheme.primary,
          ),
          title: Text('Show readings', style: theme.textTheme.titleSmall),
          subtitle: pager.step == null
              ? null
              : Text('Averages ${pager.step!.phrase}'),
          expandedAlignment: Alignment.topCenter,
          children: [child],
        ),
      ),
    );
  }
}
