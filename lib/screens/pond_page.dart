import 'package:flutter/material.dart';

import '../analytics/individual_trend_chart.dart';
import '../analytics/latest_readings.dart';
import '../analytics/metric_detail_view.dart';
import '../analytics/metric_type.dart';
import '../analytics/reading_history_table.dart';
import '../analytics/readings_pager.dart';
import '../analytics/timeframe_picker.dart';
import '../analytics/trend_range.dart';
import '../analytics/trend_service.dart';
import '../models/monitored_pond.dart';
import '../theme/app_spacing.dart';
import '../widgets/status_badge.dart';
import 'pond_latest_readings.dart';

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
                LatestReadingsSection(
                  pond: pond,
                  latest: latest,
                  trend: _trend,
                  onOpen: _openMetric,
                ),
                const SizedBox(height: AppSpacing.xxl),
                _OwnerCard(pond: pond),
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

/// The owner and the device, as two cards side by side on wide screens.
class _OwnerCard extends StatelessWidget {
  const _OwnerCard({required this.pond});

  final MonitoredPond pond;

  @override
  Widget build(BuildContext context) {
    final owner = _FactsCard(
      title: 'Owner',
      icon: Icons.person_outline,
      facts: [
        (Icons.badge_outlined, 'Name', pond.ownerName),
        (Icons.email_outlined, 'Email', pond.ownerEmail),
        (Icons.phone_outlined, 'Phone', pond.ownerPhone),
      ],
    );
    final device = _FactsCard(
      title: 'Pond & device',
      icon: Icons.memory,
      facts: [
        (Icons.memory, 'Device ID', pond.deviceId),
        (
          Icons.link,
          'Paired',
          pond.pairedAt == null ? null : _date(context, pond.pairedAt!),
        ),
        (
          Icons.schedule,
          'Last seen',
          pond.lastSeenAt == null ? null : _relative(pond.lastSeenAt!),
        ),
        (
          Icons.place_outlined,
          'Location',
          (pond.latitude == null || pond.longitude == null)
              ? null
              : '${pond.latitude!.toStringAsFixed(5)}, '
                    '${pond.longitude!.toStringAsFixed(5)}',
        ),
        (Icons.set_meal_outlined, 'Species', pond.speciesNames.join(', ')),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader(icon: Icons.info_outline, title: 'Owner & device'),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 760) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  owner,
                  const SizedBox(height: AppSpacing.md),
                  device,
                ],
              );
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: owner),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: device),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _FactsCard extends StatelessWidget {
  const _FactsCard({
    required this.title,
    required this.icon,
    required this.facts,
  });

  final String title;
  final IconData icon;
  final List<(IconData, String, String?)> facts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final (i, (factIcon, label, value)) in facts.indexed) ...[
              if (i > 0) const Divider(height: AppSpacing.lg),
              Row(
                children: [
                  Icon(factIcon, size: 20, color: muted),
                  const SizedBox(width: AppSpacing.md),
                  SizedBox(
                    width: 88,
                    child: Text(
                      label,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      (value == null || value.isEmpty) ? '—' : value,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
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
