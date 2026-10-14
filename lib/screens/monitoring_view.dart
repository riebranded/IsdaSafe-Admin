import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/monitored_pond.dart';
import '../services/admin_auth_service.dart';
import '../services/monitoring_repository.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../widgets/status_badge.dart';
import 'pond_page.dart';

enum _Filter { all, attention, online, offline }

enum _Sort {
  urgency('Most urgent first', Icons.priority_high),
  name('Name (A–Z)', Icons.sort_by_alpha),
  latest('Latest reading', Icons.schedule);

  const _Sort(this.label, this.icon);

  final String label;
  final IconData icon;
}

enum _Layout { grid, list }

/// Every pond that has an IsdaSafe device paired, with the device's
/// connection and the latest water readings. Refreshes every minute (the
/// firmware uploads about once a minute).
class MonitoringView extends StatefulWidget {
  const MonitoringView({
    super.key,
    this.onAttentionCountChanged,
    this.loader = MonitoringRepository.fetchMonitoredPonds,
  });

  /// Called after each load with how many ponds have Warning or Critical
  /// readings (the sidebar's badge).
  final ValueChanged<int>? onAttentionCountChanged;

  /// Where the ponds come from (replaced in tests).
  final Future<List<MonitoredPond>> Function() loader;

  @override
  State<MonitoringView> createState() => _MonitoringViewState();
}

class _MonitoringViewState extends State<MonitoringView> {
  static const _refreshInterval = Duration(minutes: 1);
  static const _maxContentWidth = 1440.0;

  final _search = TextEditingController();
  List<MonitoredPond>? _ponds;
  Object? _error;
  DateTime? _updatedAt;
  var _loading = false;
  var _filter = _Filter.all;
  var _sort = _Sort.urgency;
  var _layout = _Layout.grid;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _load();
    _timer = Timer.periodic(_refreshInterval, (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final ponds = await widget.loader();
      if (!mounted) return;
      setState(() {
        _ponds = ponds;
        _error = null;
        _updatedAt = DateTime.now();
      });
      widget.onAttentionCountChanged?.call(ponds.where(_needsAttention).length);
    } catch (e) {
      debugPrint('MonitoringView: load failed $e');
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static bool _needsAttention(MonitoredPond pond) =>
      pond.status != null && pond.status != ReadingStatus.normal;

  bool _matchesFilter(MonitoredPond pond, _Filter filter) => switch (filter) {
    _Filter.all => true,
    _Filter.attention => _needsAttention(pond),
    _Filter.online => pond.connection() == DeviceConnection.online,
    _Filter.offline => pond.connection() != DeviceConnection.online,
  };

  bool _matchesQuery(MonitoredPond pond) {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [
      pond.pondName,
      pond.deviceId,
      pond.ownerName ?? '',
      pond.ownerEmail ?? '',
    ].any((s) => s.toLowerCase().contains(q));
  }

  /// Critical, then Warning, then devices that stopped reporting, then the
  /// rest — so the ponds that need someone come first.
  static int _urgency(MonitoredPond pond) => switch (pond.status) {
    ReadingStatus.critical => 0,
    ReadingStatus.warning => 1,
    _ => switch (pond.connection()) {
      DeviceConnection.offline => 2,
      DeviceConnection.neverConnected => 3,
      DeviceConnection.online => 4,
    },
  };

  int _compare(MonitoredPond a, MonitoredPond b) {
    int byName() =>
        a.pondName.toLowerCase().compareTo(b.pondName.toLowerCase());
    return switch (_sort) {
      _Sort.urgency => switch (_urgency(a).compareTo(_urgency(b))) {
        0 => byName(),
        final c => c,
      },
      _Sort.name => byName(),
      _Sort.latest => switch ((a.readingAt, b.readingAt)) {
        (null, null) => byName(),
        (null, _) => 1,
        (_, null) => -1,
        (final x?, final y?) => y.compareTo(x),
      },
    };
  }

  void _clearFilters() {
    _search.clear();
    setState(() => _filter = _Filter.all);
  }

  void _openPond(MonitoredPond pond) => openPond(context, pond);

  @override
  Widget build(BuildContext context) {
    final ponds = _ponds;
    if (ponds == null && _error != null) {
      return _Message(
        icon: Icons.cloud_off,
        title: 'Couldn\'t load ponds',
        message: 'Check your connection and try again.',
        action: FilledButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    final gutter = width >= 600 ? AppSpacing.xl : AppSpacing.lg;
    final visible = ponds == null
        ? const <MonitoredPond>[]
        : (ponds
              .where((p) => _matchesFilter(p, _filter) && _matchesQuery(p))
              .toList()
            ..sort(_compare));
    final filtered = _filter != _Filter.all || _search.text.trim().isNotEmpty;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Centres the content at most _maxContentWidth wide on big screens.
        final side = math.max(
          gutter,
          (constraints.maxWidth - _maxContentWidth) / 2,
        );
        return _buildScroll(ponds, visible, filtered, gutter, side);
      },
    );
  }

  Widget _buildScroll(
    List<MonitoredPond>? ponds,
    List<MonitoredPond> visible,
    bool filtered,
    double gutter,
    double side,
  ) {
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(side, gutter, side, AppSpacing.lg),
            sliver: SliverList.list(
              children: [
                _Header(
                  ponds: ponds,
                  updatedAt: _updatedAt,
                  loading: _loading,
                  onRefresh: _load,
                ),
                if (_error != null && ponds != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _StaleDataBanner(onRetry: _load),
                ],
                const SizedBox(height: AppSpacing.xl),
                if (ponds == null)
                  const _SummarySkeleton()
                else
                  _SummaryRow(
                    ponds: ponds,
                    selected: _filter,
                    countFor: (f) =>
                        ponds.where((p) => _matchesFilter(p, f)).length,
                    onSelected: (f) => setState(
                      () => _filter = _filter == f ? _Filter.all : f,
                    ),
                  ),
                const SizedBox(height: AppSpacing.xl),
                _Toolbar(
                  search: _search,
                  sort: _sort,
                  layout: _layout,
                  onSortChanged: (s) => setState(() => _sort = s),
                  onLayoutChanged: (l) => setState(() => _layout = l),
                ),
                if (ponds != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _ResultLine(
                    shown: visible.length,
                    total: ponds.length,
                    filter: _filter,
                    filtered: filtered,
                    onClear: _clearFilters,
                  ),
                ],
              ],
            ),
          ),
          if (ponds == null)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, 0, side, gutter),
              sliver: SliverGrid.builder(
                gridDelegate: _cardGridDelegate,
                itemCount: 6,
                itemBuilder: (_, _) => const _PondCardSkeleton(),
              ),
            )
          else if (visible.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _Message(
                icon: ponds.isEmpty
                    ? Icons.sensors_off_outlined
                    : Icons.search_off,
                title: ponds.isEmpty
                    ? 'No devices paired yet'
                    : 'No ponds match',
                message: ponds.isEmpty
                    ? 'Ponds appear here once a farmer pairs an IsdaSafe device.'
                    : 'Try a different search or filter.',
                action: ponds.isEmpty
                    ? null
                    : OutlinedButton.icon(
                        onPressed: _clearFilters,
                        icon: const Icon(Icons.filter_alt_off_outlined),
                        label: const Text('Clear filters'),
                      ),
              ),
            )
          else if (_layout == _Layout.grid)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, 0, side, gutter),
              sliver: SliverGrid.builder(
                gridDelegate: _cardGridDelegate,
                itemCount: visible.length,
                itemBuilder: (context, i) => _PondCard(
                  pond: visible[i],
                  onTap: () => _openPond(visible[i]),
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, 0, side, gutter),
              sliver: SliverToBoxAdapter(
                child: _PondTable(ponds: visible, onOpen: _openPond),
              ),
            ),
        ],
      ),
    );
  }
}

const _cardGridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 420,
  mainAxisExtent: 236,
  crossAxisSpacing: AppSpacing.lg,
  mainAxisSpacing: AppSpacing.lg,
);

class _Header extends StatelessWidget {
  const _Header({
    required this.ponds,
    required this.updatedAt,
    required this.loading,
    required this.onRefresh,
  });

  /// Null while the first load is running.
  final List<MonitoredPond>? ponds;
  final DateTime? updatedAt;
  final bool loading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final good = context.statusColors.good;
    final refreshIcon = loading
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.refresh);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'POND MONITORING',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              ValueListenableBuilder(
                valueListenable: AdminAuthService.ownProfile,
                builder: (context, _, _) {
                  final name = AdminAuthService.ownFirstName;
                  final greeting = _greeting(DateTime.now());
                  return Text(
                    name.isEmpty ? greeting : '$greeting, $name',
                    style: theme.textTheme.headlineSmall,
                  );
                },
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _statusLine(ponds),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: good,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      updatedAt == null
                          ? 'Live · refreshes every minute'
                          : 'Live · updated '
                                '${_timeOfDay(context, updatedAt!)}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        if (MediaQuery.sizeOf(context).width < 600)
          IconButton.filledTonal(
            tooltip: 'Refresh',
            onPressed: loading ? null : onRefresh,
            icon: refreshIcon,
          )
        else
          FilledButton.tonalIcon(
            onPressed: loading ? null : onRefresh,
            icon: refreshIcon,
            label: const Text('Refresh'),
          ),
      ],
    );
  }
}

class _StaleDataBanner extends StatelessWidget {
  const _StaleDataBanner({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.xs,
        AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off, size: 20, color: scheme.onErrorContainer),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'The last refresh failed — showing earlier data.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onErrorContainer,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              foregroundColor: scheme.onErrorContainer,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

/// Overview tiles that double as the filter: tapping one shows only those
/// ponds, tapping it again shows all.
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.ponds,
    required this.selected,
    required this.countFor,
    required this.onSelected,
  });

  final List<MonitoredPond> ponds;
  final _Filter selected;
  final int Function(_Filter filter) countFor;
  final ValueChanged<_Filter> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.statusColors;
    final scheme = Theme.of(context).colorScheme;
    final critical = ponds
        .where((p) => p.status == ReadingStatus.critical)
        .length;
    final online = countFor(_Filter.online);
    final attention = countFor(_Filter.attention);
    final offline = countFor(_Filter.offline);

    final tiles = [
      _StatTile(
        filter: _Filter.all,
        icon: Icons.water,
        label: 'All ponds',
        value: '${ponds.length}',
        caption: 'with a paired device',
        color: scheme.primary,
      ),
      _StatTile(
        filter: _Filter.attention,
        icon: Icons.warning_rounded,
        label: 'Needs attention',
        value: '$attention',
        caption: attention == 0
            ? 'all readings normal'
            : '$critical critical · ${attention - critical} warning',
        color: attention == 0
            ? colors.good
            : critical > 0
            ? colors.critical
            : colors.warning,
      ),
      _StatTile(
        filter: _Filter.online,
        icon: Icons.wifi,
        label: 'Devices online',
        value: '$online',
        caption: ponds.isEmpty
            ? 'no devices'
            : '${(online * 100 / ponds.length).round()}% of devices',
        color: colors.good,
      ),
      _StatTile(
        filter: _Filter.offline,
        icon: Icons.wifi_off,
        label: 'Offline',
        value: '$offline',
        caption: 'no upload in 3+ min',
        color: offline == 0 ? scheme.onSurfaceVariant : colors.critical,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final perRow = constraints.maxWidth >= 840 ? 4 : 2;
        final width =
            (constraints.maxWidth - AppSpacing.md * (perRow - 1)) / perRow;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final tile in tiles)
              SizedBox(
                width: width,
                child: _StatTileButton(
                  tile: tile,
                  selected: selected == tile.filter,
                  onTap: () => onSelected(tile.filter),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StatTile {
  const _StatTile({
    required this.filter,
    required this.icon,
    required this.label,
    required this.value,
    required this.caption,
    required this.color,
  });

  final _Filter filter;
  final IconData icon;
  final String label;
  final String value;
  final String caption;
  final Color color;
}

class _StatTileButton extends StatelessWidget {
  const _StatTileButton({
    required this.tile,
    required this.selected,
    required this.onTap,
  });

  final _StatTile tile;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      button: true,
      selected: selected,
      label: '${tile.label}: ${tile.value}, ${tile.caption}',
      excludeSemantics: true,
      child: Tooltip(
        message: selected ? 'Show all ponds' : 'Show only these ponds',
        waitDuration: const Duration(milliseconds: 600),
        child: AnimatedContainer(
          duration: AppMotion.fast,
          decoration: BoxDecoration(
            color: selected
                ? scheme.primaryContainer.withValues(alpha: 0.45)
                : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 200;
                    final icon = Container(
                      width: narrow ? 36 : 44,
                      height: narrow ? 36 : 44,
                      decoration: BoxDecoration(
                        color: tile.color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Icon(
                        tile.icon,
                        color: tile.color,
                        size: narrow ? 20 : 24,
                      ),
                    );
                    final text = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tile.label,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                          maxLines: narrow ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          tile.value,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            height: 1.2,
                          ),
                        ),
                        Text(
                          tile.caption,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                          maxLines: narrow ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    );
                    if (narrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          icon,
                          const SizedBox(height: AppSpacing.sm),
                          text,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        icon,
                        const SizedBox(width: AppSpacing.md),
                        Expanded(child: text),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.search,
    required this.sort,
    required this.layout,
    required this.onSortChanged,
    required this.onLayoutChanged,
  });

  final TextEditingController search;
  final _Sort sort;
  final _Layout layout;
  final ValueChanged<_Sort> onSortChanged;
  final ValueChanged<_Layout> onLayoutChanged;

  @override
  Widget build(BuildContext context) {
    final searchField = TextField(
      controller: search,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search pond, owner, email or device ID',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: search.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close),
                onPressed: search.clear,
              ),
      ),
    );

    final sortMenu = MenuAnchor(
      alignmentOffset: const Offset(0, AppSpacing.xs),
      menuChildren: [
        for (final s in _Sort.values)
          MenuItemButton(
            leadingIcon: Icon(s.icon),
            trailingIcon: s == sort ? const Icon(Icons.check) : null,
            onPressed: () => onSortChanged(s),
            child: Text(s.label),
          ),
      ],
      builder: (context, controller, _) => OutlinedButton.icon(
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.swap_vert),
        label: Text(sort.label),
      ),
    );

    final layoutToggle = SegmentedButton<_Layout>(
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(minimumSize: const Size(48, 48)),
      segments: const [
        ButtonSegment(
          value: _Layout.grid,
          icon: Icon(Icons.grid_view),
          tooltip: 'Cards',
        ),
        ButtonSegment(
          value: _Layout.list,
          icon: Icon(Icons.view_list),
          tooltip: 'List',
        ),
      ],
      selected: {layout},
      onSelectionChanged: (s) => onLayoutChanged(s.first),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 640) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              searchField,
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(child: sortMenu),
                  const SizedBox(width: AppSpacing.sm),
                  layoutToggle,
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: searchField,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            sortMenu,
            const SizedBox(width: AppSpacing.sm),
            layoutToggle,
          ],
        );
      },
    );
  }
}

class _ResultLine extends StatelessWidget {
  const _ResultLine({
    required this.shown,
    required this.total,
    required this.filter,
    required this.filtered,
    required this.onClear,
  });

  final int shown;
  final int total;
  final _Filter filter;
  final bool filtered;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filterName = switch (filter) {
      _Filter.all => null,
      _Filter.attention => 'Needs attention',
      _Filter.online => 'Online',
      _Filter.offline => 'Offline',
    };
    return Row(
      children: [
        Flexible(
          child: Text(
            filtered
                ? 'Showing $shown of $total ponds'
                : '$total ${total == 1 ? 'pond' : 'ponds'}',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (filterName != null) ...[
          const SizedBox(width: AppSpacing.sm),
          InputChip(
            label: Text(filterName),
            onDeleted: onClear,
            deleteButtonTooltipMessage: 'Clear filter',
            visualDensity: VisualDensity.compact,
          ),
        ] else if (filtered) ...[
          const SizedBox(width: AppSpacing.sm),
          TextButton(onPressed: onClear, child: const Text('Clear search')),
        ],
      ],
    );
  }
}

Color _accentFor(BuildContext context, MonitoredPond pond) {
  if (pond.status case final status?) return status.colorOf(context);
  return Theme.of(context).colorScheme.outline;
}

class _PondCard extends StatelessWidget {
  const _PondCard({required this.pond, required this.onTap});

  final MonitoredPond pond;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = pond.status;
    final accent = _accentFor(context, pond);

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: accent, width: 4)),
          ),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pond.pondName,
                          style: theme.textTheme.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              Icons.person_outline,
                              size: 14,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Flexible(
                              child: Text(
                                pond.ownerName ?? 'Unknown owner',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  if (status != null)
                    StatusPill.status(status, context)
                  else
                    StatusPill(
                      label: 'No data',
                      icon: Icons.remove_circle_outline,
                      color: scheme.onSurfaceVariant,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: pond.readings.isEmpty
                    ? Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(
                            alpha: 0.5,
                          ),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.hourglass_empty,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              'Waiting for the first reading',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      )
                    : GridView(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisExtent: 52,
                              mainAxisSpacing: AppSpacing.sm,
                              crossAxisSpacing: AppSpacing.sm,
                            ),
                        physics: const NeverScrollableScrollPhysics(),
                        padding: EdgeInsets.zero,
                        children: [
                          for (final metric in WaterMetric.values)
                            _MetricTile(
                              metric: metric,
                              value: pond.readings[metric],
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: ConnectionPill(pond: pond),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      pond.readingAt == null
                          ? 'Never reported'
                          : 'Read ${_relative(pond.readingAt!)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: scheme.primary,
                    semanticLabel: 'Open details',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.metric, required this.value});

  final WaterMetric metric;
  final double? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final v = value;
    final status = v == null ? null : metric.statusFor(v);
    final color = status?.colorOf(context) ?? scheme.onSurfaceVariant;
    final flagged = status != null && status != ReadingStatus.normal;

    return Tooltip(
      message: status == null
          ? '${metric.label}: no reading'
          : '${metric.label}: ${status.label}',
      waitDuration: const Duration(milliseconds: 500),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        decoration: BoxDecoration(
          color: flagged
              ? color.withValues(alpha: 0.10)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          children: [
            Icon(flagged ? status.icon : metric.icon, size: 18, color: color),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    metric.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    v == null ? '—' : metric.format(v),
                    style: theme.textTheme.titleSmall?.copyWith(color: color),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact list layout: one row per pond. Narrow widths drop the reading
/// columns (the card layout shows them better there).
class _PondTable extends StatelessWidget {
  const _PondTable({required this.ponds, required this.onOpen});

  final List<MonitoredPond> ponds;
  final ValueChanged<MonitoredPond> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final headerStyle = theme.textTheme.labelMedium?.copyWith(
      color: scheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final showMetrics = constraints.maxWidth >= 900;
        final showDevice = constraints.maxWidth >= 640;

        Widget cells({
          required Widget pond,
          required Widget status,
          required List<Widget> metrics,
          required Widget device,
          required Widget lastReading,
          Widget? trailing,
        }) => Row(
          children: [
            Expanded(flex: 3, child: pond),
            SizedBox(width: 120, child: status),
            if (showMetrics)
              for (final m in metrics) Expanded(child: m),
            if (showDevice) SizedBox(width: 150, child: device),
            SizedBox(width: 96, child: lastReading),
            SizedBox(width: 32, child: trailing),
          ],
        );

        return Card(
          child: Column(
            children: [
              Container(
                color: scheme.surfaceContainer,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                child: cells(
                  pond: Text('Pond', style: headerStyle),
                  status: Text('Status', style: headerStyle),
                  metrics: [
                    for (final m in WaterMetric.values)
                      Text(
                        m.label,
                        style: headerStyle,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                  device: Text('Device', style: headerStyle),
                  lastReading: Text('Last reading', style: headerStyle),
                ),
              ),
              for (final (i, pond) in ponds.indexed) ...[
                if (i > 0) const Divider(height: 1),
                InkWell(
                  onTap: () => onOpen(pond),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: _accentFor(context, pond),
                          width: 4,
                        ),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.md,
                    ),
                    child: cells(
                      pond: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pond.pondName,
                            style: theme.textTheme.titleSmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            pond.ownerName ?? 'Unknown owner',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                      status: Align(
                        alignment: Alignment.centerLeft,
                        child: pond.status == null
                            ? Text(
                                'No data',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              )
                            : StatusPill.status(pond.status!, context),
                      ),
                      metrics: [
                        for (final m in WaterMetric.values)
                          _MetricCell(metric: m, value: pond.readings[m]),
                      ],
                      device: Align(
                        alignment: Alignment.centerLeft,
                        child: ConnectionPill(pond: pond),
                      ),
                      lastReading: Text(
                        pond.readingAt == null
                            ? 'Never'
                            : _relative(pond.readingAt!),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.metric, required this.value});

  final WaterMetric metric;
  final double? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = value;
    if (v == null) {
      return Text(
        '—',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    final status = metric.statusFor(v);
    final color = status.colorOf(context);
    return Row(
      children: [
        if (status != ReadingStatus.normal) ...[
          Icon(status.icon, size: 14, color: color),
          const SizedBox(width: 2),
        ],
        Flexible(
          child: Text(
            metric.format(v),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: status == ReadingStatus.normal ? null : color,
              fontWeight: status == ReadingStatus.normal
                  ? null
                  : FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({
    this.width,
    this.height = 12,
    this.radius = AppRadius.sm,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _SummarySkeleton extends StatelessWidget {
  const _SummarySkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final perRow = constraints.maxWidth >= 840 ? 4 : 2;
        final width =
            (constraints.maxWidth - AppSpacing.md * (perRow - 1)) / perRow;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (var i = 0; i < 4; i++)
              SizedBox(
                width: width,
                child: const Card(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: Row(
                      children: [
                        _SkeletonBox(
                          width: 44,
                          height: 44,
                          radius: AppRadius.md,
                        ),
                        SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SkeletonBox(width: 90),
                              SizedBox(height: AppSpacing.sm),
                              _SkeletonBox(width: 40, height: 22),
                              SizedBox(height: AppSpacing.sm),
                              _SkeletonBox(width: 110, height: 10),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PondCardSkeleton extends StatelessWidget {
  const _PondCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading pond',
      child: const Card(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SkeletonBox(width: 140, height: 16),
                        SizedBox(height: AppSpacing.sm),
                        _SkeletonBox(width: 90, height: 10),
                      ],
                    ),
                  ),
                  _SkeletonBox(width: 64, height: 22, radius: AppRadius.pill),
                ],
              ),
              SizedBox(height: AppSpacing.md),
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: _SkeletonBox(height: double.infinity)),
                    SizedBox(width: AppSpacing.sm),
                    Expanded(child: _SkeletonBox(height: double.infinity)),
                  ],
                ),
              ),
              SizedBox(height: AppSpacing.md),
              _SkeletonBox(width: 160, height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: AppSpacing.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

String _greeting(DateTime now) => switch (now.hour) {
  < 12 => 'Good morning',
  < 18 => 'Good afternoon',
  _ => 'Good evening',
};

/// One sentence on how the ponds are doing, under the greeting.
String _statusLine(List<MonitoredPond>? ponds) {
  if (ponds == null) return 'Checking on your ponds…';
  if (ponds.isEmpty) return 'No IsdaSafe devices are paired yet.';
  String plural(int n, String one, String many) => n == 1 ? one : many;
  final critical = ponds
      .where((p) => p.status == ReadingStatus.critical)
      .length;
  final warning = ponds.where((p) => p.status == ReadingStatus.warning).length;
  final offline = ponds
      .where((p) => p.connection() != DeviceConnection.online)
      .length;
  final attention = critical + warning;
  final offlinePart = offline == 0
      ? ''
      : ' · $offline ${plural(offline, 'device', 'devices')} offline';
  if (attention == 0) {
    return 'All ${ponds.length} ${plural(ponds.length, 'pond reads', 'ponds read')} '
        'normal$offlinePart.';
  }
  final parts = [
    if (critical > 0) '$critical critical',
    if (warning > 0) '$warning warning',
  ].join(', ');
  return '$attention ${plural(attention, 'pond needs', 'ponds need')} '
      'attention ($parts)$offlinePart.';
}

String _relative(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return '${diff.inDays} d ago';
}

String _timeOfDay(BuildContext context, DateTime time) =>
    MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(time));
