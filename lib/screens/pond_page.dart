import 'package:flutter/material.dart';

import '../analytics/individual_trend_chart.dart';
import '../analytics/latest_readings.dart';
import '../analytics/metric_detail_view.dart';
import '../analytics/metric_range_bar.dart';
import '../analytics/metric_type.dart';
import '../analytics/reading_history_table.dart';
import '../analytics/readings_pager.dart';
import '../analytics/timeframe_picker.dart';
import '../analytics/trend_range.dart';
import '../analytics/trend_service.dart';
import '../models/monitored_pond.dart';
import '../theme/app_spacing.dart';
import '../widgets/status_badge.dart';

/// Opens [pond] as a full page (from Monitoring or the Map).
Future<void> openPond(BuildContext context, MonitoredPond pond) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => PondPage(pond: pond)));

/// One monitored pond in full, modelled on the farmer app's pond dashboard
/// and Analytics page: its overall status, latest readings (tap one for its
/// detail view), owner and device, every metric's trend over a chosen
/// timeframe (tap a chart for its detail view), and the readings behind the
/// charts.
class PondPage extends StatefulWidget {
  const PondPage({super.key, required this.pond});

  final MonitoredPond pond;

  @override
  State<PondPage> createState() => _PondPageState();
}

class _PondPageState extends State<PondPage> {
  static const _maxContentWidth = 1280.0;

  var _selection = const TrendSelection.preset(TrendRange.hourly);

  /// Where clearing a custom range goes back to.
  var _lastPreset = TrendRange.hourly;

  late AdminTrendController _trend = AdminTrendController(
    widget.pond.pondId,
    _selection,
  );
  late ReadingsPager _pager = ReadingsPager.forTrend(_trend);

  void _setSelection(TrendSelection selection) {
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

  void _openMetric(MetricType type) => showMetricDetail(
    context,
    pond: widget.pond,
    type: type,
    initialSelection: _selection,
    lastPreset: _lastPreset,
  );

  @override
  void dispose() {
    _trend.dispose();
    _pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pond = widget.pond;
    final latest = latestReadings(pond);
    final width = MediaQuery.sizeOf(context).width;
    final gutter = width >= 600 ? AppSpacing.xl : AppSpacing.lg;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(pond.pondName, overflow: TextOverflow.ellipsis),
            Text(
              pond.ownerName == null
                  ? 'Unknown owner'
                  : 'Owned by ${pond.ownerName}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Reload trends',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(_reload),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final side = (constraints.maxWidth - _maxContentWidth) / 2;
          final wide = constraints.maxWidth >= 1000;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              side > gutter ? side : gutter,
              gutter,
              side > gutter ? side : gutter,
              AppSpacing.xxl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StatusBanner(pond: pond),
                const SizedBox(height: AppSpacing.xl),
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: _LatestSection(
                          pond: pond,
                          latest: latest,
                          onOpen: _openMetric,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xl),
                      Expanded(flex: 2, child: _OwnerCard(pond: pond)),
                    ],
                  )
                else ...[
                  _LatestSection(
                    pond: pond,
                    latest: latest,
                    onOpen: _openMetric,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _OwnerCard(pond: pond),
                ],
                const SizedBox(height: AppSpacing.xxl),
                const _SectionHeader(
                  icon: Icons.show_chart,
                  title: 'Individual trends',
                  subtitle: 'Tap a chart for that reading in depth.',
                ),
                const SizedBox(height: AppSpacing.md),
                TimeframePicker(
                  selection: _selection,
                  lastPreset: _lastPreset,
                  onChanged: _setSelection,
                ),
                const SizedBox(height: AppSpacing.lg),
                ListenableBuilder(
                  listenable: _trend,
                  builder: (context, _) => _Trends(
                    trend: _trend,
                    latest: latest,
                    onOpen: _openMetric,
                    onRetry: () => setState(_reload),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                _SectionHeader(
                  icon: Icons.table_rows_outlined,
                  title: 'Individual readings',
                  subtitle:
                      'Each row averages the readings ${_trend.step.phrase}.',
                ),
                const SizedBox(height: AppSpacing.md),
                ReadingHistoryTable(key: ObjectKey(_pager), pager: _pager),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Every primary metric's trend chart, or the loading / error state.
class _Trends extends StatelessWidget {
  const _Trends({
    required this.trend,
    required this.latest,
    required this.onOpen,
    required this.onRetry,
  });

  final AdminTrendController trend;
  final Map<MetricType, SensorReading> latest;
  final ValueChanged<MetricType> onOpen;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (trend.loading) {
      return const Card(
        child: SizedBox(
          height: 240,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (trend.error != null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.cloud_off),
          title: const Text('Couldn\'t load the trends'),
          subtitle: const Text('Check your connection and try again.'),
          trailing: TextButton(onPressed: onRetry, child: const Text('Retry')),
        ),
      );
    }
    final step = trend.step;
    final span = trend.window.duration;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final type in MetricType.primary) ...[
          IndividualTrendChart(
            type: type,
            history: [for (final p in trend.pointsFor(type)) p.asReading(type)],
            band: [
              for (final p in trend.pointsFor(type)) (min: p.min, max: p.max),
            ],
            latest: latest[type],
            timeFormat: (t) => step.axisLabel(t, span),
            tooltipTimeFormat: step.fullLabel,
            emptyMessage: 'No readings in this timeframe. Try a longer one.',
            onTap: () => onOpen(type),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ],
    );
  }
}

/// Overall status of the pond, in words, tinted by how serious it is — with
/// the device's connection and when it last reported.
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.pond});

  final MonitoredPond pond;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = pond.status;
    final color = status?.colorOf(context) ?? scheme.onSurfaceVariant;
    final flagged = [
      for (final MapEntry(:key, :value) in pond.readings.entries)
        if (key.statusFor(value) != ReadingStatus.normal) key.label,
    ];
    final (title, message) = switch (status) {
      null => (
        'Waiting for the first reading',
        'This device hasn\'t sent any water readings yet.',
      ),
      ReadingStatus.normal => (
        'All readings are normal',
        'Water temperature, dissolved oxygen, pH and free ammonia are all in '
            'the healthy range.',
      ),
      ReadingStatus.warning => (
        'Needs attention',
        'Outside the healthy range: ${flagged.join(', ')}.',
      ),
      ReadingStatus.critical => (
        'Critical',
        'Unsafe for the fish: ${flagged.join(', ')}. The farmer should act now.',
      ),
    };

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
          Icon(status?.icon ?? Icons.hourglass_empty, color: color, size: 28),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(color: color),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(message, style: theme.textTheme.bodyMedium),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ConnectionPill(pond: pond),
                    Text(
                      pond.readingAt == null
                          ? 'Never reported'
                          : 'Last reading ${_relative(pond.readingAt!)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: theme.colorScheme.primary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(title, style: theme.textTheme.titleLarge),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The latest value of every reading the device sent, as tappable tiles.
class _LatestSection extends StatelessWidget {
  const _LatestSection({
    required this.pond,
    required this.latest,
    required this.onOpen,
  });

  final MonitoredPond pond;
  final Map<MetricType, SensorReading> latest;
  final ValueChanged<MetricType> onOpen;

  static const _order = [
    MetricType.temperature,
    MetricType.dissolvedOxygen,
    MetricType.ph,
    MetricType.freeAmmonia,
    MetricType.ammonia,
    MetricType.humidity,
    MetricType.airTemperature,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = [for (final type in _order) ?latest[type]];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          icon: Icons.sensors,
          title: 'Latest readings',
          subtitle: pond.readingAt == null
              ? null
              : 'Read ${_relative(pond.readingAt!)} · tap one for details',
        ),
        const SizedBox(height: AppSpacing.md),
        if (shown.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Text(
                'This device hasn\'t sent any readings yet.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final perRow = constraints.maxWidth >= 640
                  ? 3
                  : constraints.maxWidth >= 360
                  ? 2
                  : 1;
              final tileWidth =
                  (constraints.maxWidth - AppSpacing.md * (perRow - 1)) /
                  perRow;
              return Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  for (final reading in shown)
                    SizedBox(
                      width: tileWidth,
                      child: _LatestTile(
                        reading: reading,
                        onTap: () => onOpen(reading.type),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

/// One reading: value, status (water readings only, as in the farmer app)
/// and where it sits in the healthy range.
class _LatestTile extends StatelessWidget {
  const _LatestTile({required this.reading, required this.onTap});

  final SensorReading reading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final type = reading.type;
    final judged = MetricType.water.contains(type);
    final status = metricBands[type]!.statusFor(reading.value);
    final flagged = judged && status != ReadingStatus.normal;
    final color = judged ? status.colorOf(context) : metricColor(context, type);

    return Card(
      color: flagged ? color.withValues(alpha: 0.08) : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(type.icon, size: 18, color: metricColor(context, type)),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      type.label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
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
                          color: flagged ? color : null,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                  if (judged) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: StatusPill.status(status, context),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              MetricRangeBar(type: type, value: reading.value),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Healthy: ${healthyRangeLabel(type)}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OwnerCard extends StatelessWidget {
  const _OwnerCard({required this.pond});

  final MonitoredPond pond;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row(IconData icon, String label, String? value) => ListTile(
      dense: true,
      leading: Icon(icon),
      title: Text(label),
      subtitle: SelectableText(
        (value == null || value.isEmpty) ? '—' : value,
        style: theme.textTheme.bodyMedium,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader(
          icon: Icons.person_outline,
          title: 'Owner & device',
        ),
        const SizedBox(height: AppSpacing.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                row(Icons.person_outline, 'Owner', pond.ownerName),
                row(Icons.email_outlined, 'Email', pond.ownerEmail),
                row(Icons.phone_outlined, 'Phone', pond.ownerPhone),
                const Divider(height: AppSpacing.lg),
                row(Icons.memory, 'Device ID', pond.deviceId),
                row(
                  Icons.link,
                  'Paired',
                  pond.pairedAt == null ? null : _date(context, pond.pairedAt!),
                ),
                row(
                  Icons.schedule,
                  'Last seen',
                  pond.lastSeenAt == null ? null : _relative(pond.lastSeenAt!),
                ),
                row(
                  Icons.place_outlined,
                  'Location',
                  (pond.latitude == null || pond.longitude == null)
                      ? null
                      : '${pond.latitude!.toStringAsFixed(5)}, '
                            '${pond.longitude!.toStringAsFixed(5)}',
                ),
                row(
                  Icons.set_meal_outlined,
                  'Species',
                  pond.speciesNames.join(', '),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String _date(BuildContext context, DateTime time) =>
    MaterialLocalizations.of(context).formatMediumDate(time);

String _relative(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return '${diff.inDays} d ago';
}
