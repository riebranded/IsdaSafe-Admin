import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../analytics/reading_history_table.dart';
import '../analytics/reading_days.dart';
import '../analytics/readings_pager.dart';
import '../analytics/timeframe_picker.dart';
import '../analytics/trend_range.dart';
import '../models/monitored_pond.dart';
import '../services/device_repository.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../widgets/map_support.dart';
import '../widgets/status_badge.dart';

/// The web build and Android show the map (as on the Map tab).
bool get _mapSupported => isMapViewSupported;

/// The Philippines, for when nothing has a location yet.
const _defaultCenter = LatLng(12.8797, 121.7740);
const _focusedZoom = 16.0;

/// The admin Devices tab, modelled on the farmer app's: it opens on a device
/// chooser, and a chosen device is laid out like the Map tab — the map with
/// a numbered pin per spot it has been, a panel listing the ponds it was in,
/// and the chosen pond's visits and complete readings.
///
/// Unlike the farmer app, which lists only the devices the signed-in account
/// itself paired, an admin sees every device IsdaSafe knows about: paired or
/// not, whoever owns it now or did before, and devices that haven't sent a
/// reading yet (`admin_device_list`).
///
/// It stays mounted in the dashboard, so it reloads whenever it becomes
/// [active], and on pull-to-refresh or the refresh button.
class DevicesView extends StatefulWidget {
  const DevicesView({super.key, this.active = true});

  /// Whether the tab is the one on screen.
  final bool active;

  @override
  State<DevicesView> createState() => _DevicesViewState();
}

enum _Filter { all, paired, unpaired, online }

class _DevicesViewState extends State<DevicesView> {
  Future<List<AdminDevice>>? _devices;

  /// The chosen device; null shows the chooser.
  String? _deviceId;
  Future<List<_Place>>? _places;

  /// The pond whose readings are shown under the map.
  String? _selectedKey;
  final _map = GlobalKey<_HistoryMapState>();

  /// On a phone the map can be folded away to leave the room to the ponds.
  var _mapShown = true;

  final _search = TextEditingController();
  var _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    if (widget.active) _reload();
  }

  @override
  void didUpdateWidget(DevicesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _reload();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Reloads the device list and, if one is open, its history.
  Future<void> _reload() {
    final devices = DeviceRepository.devices();
    setState(() {
      _devices = devices;
      if (_deviceId != null) _places = _loadPlaces(_deviceId!);
    });
    return Future.wait([devices, ?_places]).then((_) {}, onError: (_) {});
  }

  Future<List<_Place>> _loadPlaces(String deviceId) async {
    final places = _Place.group(await DeviceRepository.stays(deviceId));
    if (mounted && !places.any((p) => p.key == _selectedKey)) {
      setState(() => _selectedKey = null);
    }
    return places;
  }

  void _chooseDevice(String? deviceId) => setState(() {
    _deviceId = deviceId;
    _selectedKey = null;
    _places = deviceId == null ? null : _loadPlaces(deviceId);
  });

  void _openPlace(_Place place) {
    _map.currentState?.focus(place);
    setState(() => _selectedKey = place.key);
  }

  void _closePlace() => setState(() => _selectedKey = null);

  bool _matches(AdminDevice d) {
    final ok = switch (_filter) {
      _Filter.all => true,
      _Filter.paired => d.isPaired,
      _Filter.unpaired => !d.isPaired,
      _Filter.online => d.connection == DeviceConnection.online,
    };
    if (!ok) return false;
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [
      d.id,
      d.ownerName ?? '',
      d.ownerEmail ?? '',
      d.pondName ?? '',
    ].any((s) => s.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    if (_devices == null) return const SizedBox.shrink();
    return FutureBuilder<List<AdminDevice>>(
      future: _devices,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        Widget message(IconData icon, String title, String text) =>
            RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [_Message(icon: icon, title: title, text: text)],
              ),
            );
        if (snapshot.hasError) {
          return message(
            Icons.cloud_off,
            'Couldn\'t load the devices',
            'Check your connection and try again.',
          );
        }
        final devices = snapshot.data!;
        if (devices.isEmpty) {
          return message(
            Icons.sensors_off_outlined,
            'No devices yet',
            'Devices appear here once they are registered or paired.',
          );
        }
        final device = devices.where((d) => d.id == _deviceId).firstOrNull;
        if (device == null) {
          return _DeviceChooser(
            devices: devices,
            visible: devices.where(_matches).toList(),
            search: _search,
            filter: _filter,
            onFilter: (f) => setState(() => _filter = f),
            onRefresh: _reload,
            onChoose: _chooseDevice,
          );
        }
        return FutureBuilder<List<_Place>>(
          future: _places,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done && !snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return _Panel(
                device: device,
                onBack: () => _chooseDevice(null),
                onRefresh: _reload,
                child: const _Message(
                  icon: Icons.cloud_off,
                  title: 'Couldn\'t load this device\'s history',
                  text: 'Check your connection and try again.',
                ),
              );
            }
            return _deviceView(device, snap.data!);
          },
        );
      },
    );
  }

  /// The chosen device: map, pond list, and the chosen pond's readings.
  Widget _deviceView(AdminDevice device, List<_Place> places) {
    final selected = places.where((p) => p.key == _selectedKey).firstOrNull;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= kWideLayoutBreakpoint - 232;

        Widget detail(_Place place) => _PlaceDetail(
          key: ValueKey(place.key),
          deviceId: device.id,
          place: place,
          onClose: _closePlace,
        );
        Widget panel({required bool showSelected, bool mapToggle = false}) =>
            _Panel(
              device: device,
              onBack: () => _chooseDevice(null),
              onRefresh: _reload,
              compact: !isWide,
              mapShown: mapToggle ? _mapShown : null,
              onToggleMap: mapToggle
                  ? () => setState(() => _mapShown = !_mapShown)
                  : null,
              child: places.isEmpty
                  ? const _Message(
                      icon: Icons.location_off_outlined,
                      title: 'No location history yet',
                      text:
                          'Ponds appear here once this device sends a complete '
                          'reading (every sensor) from a pond.',
                    )
                  : showSelected && selected != null
                  ? detail(selected)
                  : _PlaceList(
                      places: places,
                      selectedKey: selected?.key,
                      onRefresh: _reload,
                      onOpen: _openPlace,
                    ),
            );

        final located = [
          for (final p in places)
            if (p.hasLocation) p,
        ];
        if (!_mapSupported || located.isEmpty) {
          return panel(showSelected: true);
        }
        final map = _HistoryMap(
          key: _map,
          mapKey: ValueKey(device.id),
          places: located,
          selectedKey: selected?.key,
          onOpen: _openPlace,
        );

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: map),
                    if (selected != null) ...[
                      const Divider(height: 1),
                      SizedBox(
                        height: constraints.maxHeight * 0.5,
                        child: detail(selected),
                      ),
                    ],
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              SizedBox(width: 380, child: panel(showSelected: false)),
            ],
          );
        }
        // A phone: a short map (that can be folded away) so the ponds below
        // get most of the screen.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_mapShown) ...[
              SizedBox(
                height: (constraints.maxHeight * 0.3).clamp(150.0, 240.0),
                child: map,
              ),
              const Divider(height: 1),
            ],
            Expanded(
              child: selected != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _MapToggleBar(
                          shown: _mapShown,
                          onToggle: () =>
                              setState(() => _mapShown = !_mapShown),
                        ),
                        Expanded(child: detail(selected)),
                      ],
                    )
                  : panel(showSelected: false, mapToggle: true),
            ),
          ],
        );
      },
    );
  }
}

/// The first thing the tab shows: every device, with search and filters.
class _DeviceChooser extends StatelessWidget {
  const _DeviceChooser({
    required this.devices,
    required this.visible,
    required this.search,
    required this.filter,
    required this.onFilter,
    required this.onRefresh,
    required this.onChoose,
  });

  final List<AdminDevice> devices;
  final List<AdminDevice> visible;
  final TextEditingController search;
  final _Filter filter;
  final ValueChanged<_Filter> onFilter;
  final Future<void> Function() onRefresh;
  final ValueChanged<String> onChoose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    int count(_Filter f) => switch (f) {
      _Filter.all => devices.length,
      _Filter.paired => devices.where((d) => d.isPaired).length,
      _Filter.unpaired => devices.where((d) => !d.isPaired).length,
      _Filter.online =>
        devices.where((d) => d.connection == DeviceConnection.online).length,
    };
    const labels = {
      _Filter.all: 'All',
      _Filter.paired: 'Paired',
      _Filter.unpaired: 'Not paired',
      _Filter.online: 'Online',
    };
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'DEVICES',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              'Choose a device',
                              style: theme.textTheme.headlineSmall,
                            ),
                            Text(
                              'Every IsdaSafe device, whoever has it. See '
                              'every pond it has been in and the readings it '
                              'took there.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Refresh',
                        onPressed: onRefresh,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    controller: search,
                    decoration: InputDecoration(
                      hintText: 'Search device ID, owner, email or pond',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              icon: const Icon(Icons.close),
                              onPressed: search.clear,
                            ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final f in _Filter.values)
                        ChoiceChip(
                          label: Text('${labels[f]} (${count(f)})'),
                          selected: filter == f,
                          onSelected: (_) => onFilter(f),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (visible.isEmpty)
                    const _Message(
                      icon: Icons.search_off,
                      title: 'No devices match',
                      text: 'Try a different search or filter.',
                    )
                  else
                    for (final device in visible)
                      _DeviceCard(
                        device: device,
                        onTap: () => onChoose(device.id),
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device, required this.onTap});

  final AdminDevice device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: device.isPaired
                      ? scheme.primaryContainer
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  Icons.sensors,
                  color: device.isPaired
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Device ${device.id}',
                          style: theme.textTheme.titleMedium,
                        ),
                        _ConnectionPill(device: device),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        Icon(
                          device.pondName == null
                              ? Icons.location_off_outlined
                              : Icons.location_on,
                          size: 16,
                          color: device.pondName == null
                              ? scheme.onSurfaceVariant
                              : scheme.primary,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Flexible(
                          child: Text(
                            !device.isPaired
                                ? 'Not paired to any account'
                                : device.pondName == null
                                ? 'Owned by ${device.ownerName ?? 'an account'} · '
                                      'no pond'
                                : 'On ${device.pondName} · '
                                      '${device.ownerName ?? 'Unknown owner'}',
                            style: theme.textTheme.bodyMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      device.hasHistory
                          ? '${device.placeCount == 1 ? '1 pond' : '${device.placeCount} ponds'}'
                                ' · ${_readingsLabel(device.readingCount)}'
                          : 'No complete readings yet',
                      style: muted,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionPill extends StatelessWidget {
  const _ConnectionPill({required this.device});

  final AdminDevice device;

  @override
  Widget build(BuildContext context) {
    final colors = context.statusColors;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return switch (device.connection) {
      DeviceConnection.online => StatusPill(
        label: 'Online',
        icon: Icons.wifi,
        color: colors.good,
      ),
      DeviceConnection.offline => StatusPill(
        label: 'Offline',
        icon: Icons.wifi_off,
        color: colors.critical,
      ),
      DeviceConnection.neverConnected => StatusPill(
        label: 'Never connected',
        icon: Icons.sensors_off,
        color: muted,
      ),
    };
  }
}

/// One pond (at one spot) the device was in, with every visit there.
/// [number] is its order of first visit, used to draw the map's path.
class _Place {
  _Place({required this.key, required this.stays, required this.number});

  final String key;

  /// Newest first.
  final List<DeviceStay> stays;
  final int number;

  DeviceStay get latest => stays.first;
  String get label => latest.pondName ?? 'Unnamed pond';
  bool get isCurrent => latest.isCurrent;
  bool get hasLocation => latest.hasLocation;
  LatLng get position => LatLng(latest.latitude!, latest.longitude!);
  int get readingCount => stays.fold(0, (sum, s) => sum + s.readingCount);

  /// The accounts that had the device here (newest first, no repeats).
  List<String> get owners => {
    for (final s in stays) s.ownerName ?? s.ownerEmail ?? 'Unknown account',
  }.toList();

  static List<_Place> group(List<DeviceStay> stays) {
    final byKey = <String, List<DeviceStay>>{};
    for (final s in stays) {
      final key = s.pondId == null
          ? 'stay-${s.id}'
          : '${s.pondId}@${s.latitude?.toStringAsFixed(5)},'
                '${s.longitude?.toStringAsFixed(5)}';
      (byKey[key] ??= []).add(s);
    }
    final firstVisits = byKey.keys.toList()
      ..sort(
        (a, b) => byKey[a]!.last.startedAt.compareTo(byKey[b]!.last.startedAt),
      );
    return [
      for (final e in byKey.entries)
        _Place(
          key: e.key,
          stays: e.value,
          number: firstVisits.indexOf(e.key) + 1,
        ),
    ];
  }
}

/// The map: one numbered pin per spot (ponds within a few meters share a
/// pin), joined in the order the device moved between them. Tapping a pin
/// pops up a [_SpotCard]; tapping the map closes it.
class _HistoryMap extends StatefulWidget {
  const _HistoryMap({
    super.key,
    required this.mapKey,
    required this.places,
    required this.selectedKey,
    required this.onOpen,
  });

  final Key mapKey;

  /// Each with a location.
  final List<_Place> places;
  final String? selectedKey;
  final ValueChanged<_Place> onOpen;

  @override
  State<_HistoryMap> createState() => _HistoryMapState();
}

class _HistoryMapState extends State<_HistoryMap> {
  GoogleMapController? _controller;
  String? _popupKey;

  void focus(_Place place) {
    if (!place.hasLocation) return;
    _controller?.animateCamera(
      CameraUpdate.newLatLngZoom(place.position, _focusedZoom),
    );
  }

  /// Places within about 15 m of each other, together.
  List<List<_Place>> _spots() {
    const near = 0.00015;
    final spots = <List<_Place>>[];
    for (final place in [
      ...widget.places,
    ]..sort((a, b) => a.number.compareTo(b.number))) {
      final spot = spots.where((s) {
        final p = s.first.position;
        return (p.latitude - place.position.latitude).abs() < near &&
            (p.longitude - place.position.longitude).abs() < near;
      }).firstOrNull;
      spot == null ? spots.add([place]) : spot.add(place);
    }
    return spots;
  }

  void _fit(GoogleMapController controller, List<LatLng> points) {
    if (points.length < 2) return;
    var south = points.first.latitude, north = south;
    var west = points.first.longitude, east = west;
    for (final p in points) {
      if (p.latitude < south) south = p.latitude;
      if (p.latitude > north) north = p.latitude;
      if (p.longitude < west) west = p.longitude;
      if (p.longitude > east) east = p.longitude;
    }
    if (north - south < 1e-6 && east - west < 1e-6) return;
    controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(south, west),
          northeast: LatLng(north, east),
        ),
        64,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final spots = _spots();
    final spotOf = {
      for (final spot in spots)
        for (final place in spot) place.key: spot,
    };
    // The device's path: every visit in order, by spot.
    final visits = [
      for (final place in widget.places)
        for (final stay in place.stays) (stay.startedAt, spotOf[place.key]!),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    final path = <LatLng>[];
    for (final (_, spot) in visits) {
      final p = spot.first.position;
      if (path.isEmpty || path.last != p) path.add(p);
    }
    final popup = _popupKey == null
        ? null
        : spots.where((s) => s.any((p) => p.key == _popupKey)).firstOrNull;

    return Stack(
      children: [
        GoogleMap(
          key: widget.mapKey,
          initialCameraPosition: CameraPosition(
            target: path.isEmpty ? _defaultCenter : path.last,
            zoom: _focusedZoom,
          ),
          myLocationButtonEnabled: false,
          onMapCreated: (controller) {
            _controller = controller;
            _fit(controller, [for (final s in spots) s.first.position]);
          },
          onTap: (_) {
            if (_popupKey != null) setState(() => _popupKey = null);
          },
          markers: {
            for (final spot in spots)
              Marker(
                markerId: MarkerId(spot.first.key),
                position: spot.first.position,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  spot.any((p) => p.key == widget.selectedKey)
                      ? BitmapDescriptor.hueRed
                      : spot.any((p) => p.isCurrent)
                      ? BitmapDescriptor.hueGreen
                      : BitmapDescriptor.hueAzure,
                ),
                onTap: () => setState(() => _popupKey = spot.first.key),
              ),
          },
          polylines: {
            if (path.length > 1)
              Polyline(
                polylineId: const PolylineId('path'),
                points: path,
                width: 3,
                color: Theme.of(context).colorScheme.primary,
                patterns: [PatternItem.dash(16), PatternItem.gap(8)],
              ),
          },
        ),
        if (popup != null)
          Positioned(
            top: AppSpacing.md,
            left: AppSpacing.md,
            right: AppSpacing.md,
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: _SpotCard(
                  key: ValueKey(popup.first.key),
                  spot: popup,
                  selectedKey: widget.selectedKey,
                  onClose: () => setState(() => _popupKey = null),
                  onOpen: (place) {
                    setState(() => _popupKey = null);
                    widget.onOpen(place);
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The card over the map when a pin is tapped: every pond at that spot with
/// its owner, visits, dates and complete readings.
class _SpotCard extends StatelessWidget {
  const _SpotCard({
    super.key,
    required this.spot,
    required this.selectedKey,
    required this.onClose,
    required this.onOpen,
  });

  final List<_Place> spot;
  final String? selectedKey;
  final VoidCallback onClose;
  final ValueChanged<_Place> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    return Material(
      elevation: 6,
      color: scheme.surface,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.xs,
              0,
            ),
            child: Row(
              children: [
                Icon(Icons.place_outlined, size: 18, color: scheme.primary),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    spot.length == 1
                        ? 'Pond'
                        : '${spot.length} ponds at the same spot',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.primary,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  visualDensity: VisualDensity.compact,
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
          ),
          for (final (i, place) in spot.indexed) ...[
            if (i > 0) const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xs,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _PondIcon(place: place),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          place.label,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  _Tags(place: place),
                  const SizedBox(height: AppSpacing.sm),
                  _InfoLine(
                    icon: Icons.person_outline,
                    text: place.owners.join(', '),
                    style: muted,
                  ),
                  _InfoLine(
                    icon: Icons.event_outlined,
                    text: _rangeLabel(place.latest),
                    style: muted,
                  ),
                  _InfoLine(
                    icon: Icons.repeat,
                    text: _visitsLabel(place),
                    style: muted,
                  ),
                  _InfoLine(
                    icon: Icons.table_rows_outlined,
                    text: _readingsLabel(place.readingCount),
                    style: muted,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    width: double.infinity,
                    child: place.key == selectedKey
                        ? OutlinedButton.icon(
                            onPressed: () => onOpen(place),
                            icon: const Icon(Icons.check, size: 18),
                            label: const Text('Showing readings below'),
                          )
                        : FilledButton.icon(
                            onPressed: () => onOpen(place),
                            icon: const Icon(
                              Icons.table_chart_outlined,
                              size: 18,
                            ),
                            label: const Text('View readings'),
                          ),
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

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text, this.style});

  final IconData icon;
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Row(
      children: [
        Icon(icon, size: 14, color: style?.color),
        const SizedBox(width: AppSpacing.xs),
        Expanded(child: Text(text, style: style)),
      ],
    ),
  );
}

/// The right-hand panel (under the map on narrow layouts): the chosen
/// device and what's known about it now, a way back to the chooser, and a
/// refresh button above [child].
class _Panel extends StatelessWidget {
  const _Panel({
    required this.device,
    required this.onBack,
    required this.onRefresh,
    required this.child,
    this.compact = false,
    this.mapShown,
    this.onToggleMap,
  });

  final AdminDevice device;
  final VoidCallback onBack;
  final Future<void> Function() onRefresh;
  final Widget child;

  /// On a phone: the device's details start folded to a line or two.
  final bool compact;

  /// Whether the map is showing, and a way to fold it away (phones only).
  final bool? mapShown;
  final VoidCallback? onToggleMap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xs,
            AppSpacing.sm,
            AppSpacing.sm,
            0,
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: 'All devices',
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: Text(
                  'Device ${device.id}',
                  style: theme.textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onToggleMap != null)
                IconButton(
                  tooltip: mapShown == true ? 'Hide map' : 'Show map',
                  isSelected: mapShown == true,
                  onPressed: onToggleMap,
                  icon: const Icon(Icons.map_outlined),
                  selectedIcon: const Icon(Icons.map),
                ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        _DeviceSummary(device: device, compact: compact),
        Expanded(child: child),
      ],
    );
  }
}

/// The chosen device's details. On a phone it folds to its status and owner
/// (tap for the rest) so the ponds below stay in view.
class _DeviceSummary extends StatefulWidget {
  const _DeviceSummary({required this.device, required this.compact});

  final AdminDevice device;
  final bool compact;

  @override
  State<_DeviceSummary> createState() => _DeviceSummaryState();
}

class _DeviceSummaryState extends State<_DeviceSummary> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    String date(DateTime? t) =>
        t == null ? '—' : MaterialLocalizations.of(context).formatMediumDate(t);
    final folded = widget.compact && !_expanded;
    final owner = device.isPaired
        ? '${device.ownerName ?? 'Unknown owner'}'
              '${device.ownerEmail == null ? '' : ' · ${device.ownerEmail}'}'
        : 'Not paired to any account';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.compact
              ? () => setState(() => _expanded = !_expanded)
              : null,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _ConnectionPill(device: device),
                    const Spacer(),
                    if (widget.compact)
                      Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        size: 20,
                        color: scheme.onSurfaceVariant,
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                _InfoLine(
                  icon: Icons.person_outline,
                  text: owner,
                  style: theme.textTheme.bodySmall,
                ),
                _InfoLine(
                  icon: Icons.water_drop_outlined,
                  text: device.pondName == null
                      ? 'Not on a pond'
                      : 'On ${device.pondName}',
                  style: theme.textTheme.bodySmall,
                ),
                if (!folded) ...[
                  _InfoLine(
                    icon: Icons.schedule,
                    text: device.lastSeenAt == null
                        ? 'Never uploaded'
                        : 'Last upload ${_ago(device.lastSeenAt!)}',
                    style: muted,
                  ),
                  _InfoLine(
                    icon: Icons.link,
                    text:
                        'Paired ${date(device.pairedAt)} · registered '
                        '${date(device.manufacturedAt)}',
                    style: muted,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Above the readings of a chosen pond on a phone: folds the map away or
/// brings it back.
class _MapToggleBar extends StatelessWidget {
  const _MapToggleBar({required this.shown, required this.onToggle});

  final bool shown;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: TextButton.icon(
      onPressed: onToggle,
      icon: Icon(shown ? Icons.expand_less : Icons.map_outlined, size: 18),
      label: Text(shown ? 'Hide map' : 'Show map'),
    ),
  );
}

class _PlaceList extends StatelessWidget {
  const _PlaceList({
    required this.places,
    required this.selectedKey,
    required this.onRefresh,
    required this.onOpen,
  });

  final List<_Place> places;
  final String? selectedKey;
  final Future<void> Function() onRefresh;
  final ValueChanged<_Place> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        children: [
          Text(
            '${places.length == 1 ? '1 pond' : '${places.length} ponds'} · '
            'tap one to see the complete readings taken there',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final place in places)
            _PlaceCard(
              place: place,
              selected: place.key == selectedKey,
              onTap: () => onOpen(place),
            ),
        ],
      ),
    );
  }
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({
    required this.place,
    required this.selected,
    required this.onTap,
  });

  final _Place place;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      color: selected ? scheme.secondaryContainer : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PondIcon(place: place),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(place.label, style: theme.textTheme.titleSmall),
                    _Tags(place: place),
                    const SizedBox(height: 2),
                    Text(place.owners.join(', '), style: muted),
                    Text(_visitsLabel(place), style: muted),
                    Text(_rangeLabel(place.latest), style: muted),
                    Text(_readingsLabel(place.readingCount), style: muted),
                    if (!place.hasLocation)
                      Text('No location recorded', style: muted),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// A pond's visits and, for the chosen visit, the complete readings the
/// device took there.
class _PlaceDetail extends StatefulWidget {
  const _PlaceDetail({
    super.key,
    required this.deviceId,
    required this.place,
    required this.onClose,
  });

  final String deviceId;
  final _Place place;
  final VoidCallback onClose;

  @override
  State<_PlaceDetail> createState() => _PlaceDetailState();
}

class _PlaceDetailState extends State<_PlaceDetail> {
  late DeviceStay _visit = widget.place.latest;

  /// The timeframe the readings are limited to; ignored while [_whole].
  var _selection = const TrendSelection.preset(TrendRange.hourly);
  var _lastPreset = TrendRange.hourly;

  /// The whole visit, not a timeframe (the default): every reading the
  /// device sent (about one a minute), each row dated.
  var _whole = true;

  late ReadingsPager _pager = _pagerFor();

  /// The visit's readings, or only those inside the timeframe.
  ///
  /// One averaged row per 15 minutes, hour, day, week, month or year,
  /// whichever the timeframe uses.
  ReadingsPager _pagerFor() => DeviceRepository.stayReadings(
    _visit.id,
    window: _window,
    step: _whole || _selection.single ? null : _selection.step,
    withDates: _whole || _selection.single,
  );

  /// When the visit ended, or now while the device is still there.
  DateTime get _visitEnd => _visit.endedAt ?? DateTime.now();

  /// The timeframe within the visit; null for the whole visit.
  ///
  /// The presets count back from the visit's own end, not from today: a visit
  /// that finished last week is otherwise outside every preset (or swallows
  /// whole ones), so tapping a timeframe wouldn't change these readings.
  DateTimeRange? get _window {
    if (_whole) return null;
    final visitEnd = _visitEnd;
    final w = _selection.window(visitEnd);
    final start = w.start.isAfter(_visit.startedAt)
        ? w.start
        : _visit.startedAt;
    final end = w.end.isBefore(visitEnd) ? w.end : visitEnd;
    // No overlap: an empty window, so the table says there's nothing.
    return end.isBefore(start)
        ? DateTimeRange(start: start, end: start)
        : DateTimeRange(start: start, end: end);
  }

  void _reload(VoidCallback change) {
    setState(() {
      change();
      _pager.dispose();
      _pager = _pagerFor();
    });
  }

  void _show(DeviceStay stay) {
    if (stay.id == _visit.id) return;
    _reload(() => _visit = stay);
  }

  void _setSelection(TrendSelection selection) => _reload(() {
    _whole = false;
    _selection = selection;
    if (selection.range case final range?) _lastPreset = range;
  });

  /// "Whole visit", or the timeframe and how it meets the visit.
  String get _timeframeNote {
    if (_whole) {
      return 'Whole visit · ${_rangeLabel(_visit)} · every reading';
    }
    final window = _window!;
    final span = _selection.custom == null
        ? _selection.range!.span
        : _selection.customLabel!;
    if (!window.end.isAfter(window.start)) {
      return '$span · outside this visit';
    }
    final grouping = _selection.single
        ? 'every reading'
        : 'average ${_selection.step.phrase}';
    return '$span · of this visit · $grouping';
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final place = widget.place;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    int visitNumber(DeviceStay stay) =>
        place.stays.length - place.stays.indexOf(stay);
    final timeThere = place.stays.fold(
      Duration.zero,
      (sum, s) => sum + (s.endedAt ?? DateTime.now()).difference(s.startedAt),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.lg,
      ),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: _PondIcon(place: place),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(place.label, style: theme.textTheme.titleLarge),
                      ..._tagPills(place),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        place.hasLocation
                            ? Icons.place_outlined
                            : Icons.location_off_outlined,
                        size: 14,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        child: Text(
                          place.hasLocation
                              ? '${place.latest.latitude!.toStringAsFixed(5)}, '
                                    '${place.latest.longitude!.toStringAsFixed(5)}'
                              : 'No location recorded',
                          style: muted?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Close',
              onPressed: widget.onClose,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(right: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.md),
              _Notice(
                icon: Icons.person_outline,
                text:
                    'Owned during this visit by '
                    '${_visit.ownerName ?? 'an unknown account'}'
                    '${_visit.ownerEmail == null ? '' : ' (${_visit.ownerEmail})'}.',
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  _Stat(
                    icon: Icons.repeat,
                    value: '${place.stays.length}',
                    label: place.stays.length == 1 ? 'Visit' : 'Visits',
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _Stat(
                    icon: Icons.table_rows_outlined,
                    value: groupThousands(place.readingCount),
                    label: 'Complete readings',
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _Stat(
                    icon: Icons.schedule,
                    value: _durationLabel(timeThere),
                    label: 'Time here',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              if (place.stays.length > 1) ...[
                Text('Visits', style: theme.textTheme.titleSmall),
                Text('Pick a visit to see its readings.', style: muted),
                const SizedBox(height: AppSpacing.sm),
              ],
            ],
          ),
        ),
        SizedBox(
          height: 104,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: place.stays.length,
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (context, i) {
              final stay = place.stays[i];
              return _VisitCard(
                stay: stay,
                number: visitNumber(stay),
                latest: i == 0,
                selected: stay.id == _visit.id,
                onTap: () => _show(stay),
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Padding(
          padding: const EdgeInsets.only(right: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                place.stays.length == 1
                    ? 'Complete readings'
                    : 'Complete readings · visit ${visitNumber(_visit)}',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              TimeframePicker(
                selection: _selection,
                lastPreset: _lastPreset,
                onChanged: _setSelection,
                allLabel: 'Whole visit',
                allSelected: _whole,
                onAll: () => _reload(() => _whole = true),
                showGroupBy: true,
                singleLabel: 'Whole visit',
                readingDays: place.latest.pondId == null
                    ? null
                    : () => ReadingDays.load(
                        place.latest.pondId!,
                        deviceId: widget.deviceId,
                        completeOnly: true,
                      ),
                description: _timeframeNote,
              ),
              const SizedBox(height: AppSpacing.md),
              ReadingHistoryTable(key: ObjectKey(_pager), pager: _pager),
            ],
          ),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: scheme.onSecondaryContainer),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.value, required this.label});

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: scheme.primary),
            const SizedBox(height: AppSpacing.xs),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VisitCard extends StatelessWidget {
  const _VisitCard({
    required this.stay,
    required this.number,
    required this.latest,
    required this.selected,
    required this.onTap,
  });

  final DeviceStay stay;
  final int number;
  final bool latest;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = selected ? scheme.onPrimaryContainer : scheme.onSurface;
    final muted = selected
        ? scheme.onPrimaryContainer.withValues(alpha: 0.8)
        : scheme.onSurfaceVariant;
    final duration = (stay.endedAt ?? DateTime.now()).difference(
      stay.startedAt,
    );
    return SizedBox(
      width: 250,
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Visit $number',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(color: fg),
                      ),
                    ),
                    if (stay.isCurrent || latest) ...[
                      const SizedBox(width: AppSpacing.sm),
                      _Pill(
                        label: stay.isCurrent ? 'Current' : 'Latest',
                        color: scheme.primary,
                      ),
                    ],
                    const Spacer(),
                    if (selected)
                      Icon(Icons.check_circle, size: 18, color: scheme.primary),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _compactRange(stay),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(color: fg),
                ),
                Text(
                  stay.ownerName ?? stay.ownerEmail ?? 'Unknown account',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
                const Spacer(),
                Text(
                  '${_durationLabel(duration)} · '
                  '${_readingsLabel(stay.readingCount)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A pond's "Current" pill, and "N accounts" when more than one account had
/// the device there.
List<Widget> _tagPills(_Place place) => [
  if (place.isCurrent)
    Builder(
      builder: (context) => _Pill(
        label: 'Current',
        color: Theme.of(context).colorScheme.primary,
        icon: Icons.sensors,
      ),
    ),
  if (place.owners.length > 1)
    Builder(
      builder: (context) => _Pill(
        label: '${place.owners.length} accounts',
        color: Theme.of(context).colorScheme.tertiary,
        icon: Icons.people_outline,
      ),
    ),
];

class _PondIcon extends StatelessWidget {
  const _PondIcon({required this.place});

  final _Place place;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: 16,
      backgroundColor: place.isCurrent
          ? scheme.primary
          : scheme.surfaceContainerHighest,
      foregroundColor: place.isCurrent
          ? scheme.onPrimary
          : scheme.onSurfaceVariant,
      child: const Icon(Icons.water_drop_outlined, size: 18),
    );
  }
}

class _Tags extends StatelessWidget {
  const _Tags({required this.place});

  final _Place place;

  @override
  Widget build(BuildContext context) {
    final pills = _tagPills(place);
    if (pills.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        children: pills,
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 30, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

String _ago(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return '${diff.inDays} d ago';
}

String _readingsLabel(int count) => count == 1
    ? '1 complete reading'
    : '${groupThousands(count)} complete readings';

String _visitsLabel(_Place place) =>
    place.stays.length == 1 ? '1 visit' : '${place.stays.length} visits';

/// "Oct 9, 3:15 PM – Oct 11, 8:13 AM", or "Since Oct 9, 3:15 PM" while the
/// device is still there.
String _rangeLabel(DeviceStay stay) {
  String when(DateTime t) {
    final label = TrendStep.fifteenMinutes.fullLabel(t);
    return t.year == DateTime.now().year ? label : '$label, ${t.year}';
  }

  final end = stay.endedAt;
  return end == null
      ? 'Since ${when(stay.startedAt)}'
      : '${when(stay.startedAt)} – ${when(end)}';
}

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _dateLabel(DateTime t) {
  final label = '${_monthNames[t.month - 1]} ${t.day}';
  return t.year == DateTime.now().year ? label : '$label, ${t.year}';
}

/// "Oct 14 · 12:13 PM – 2:46 PM", "Oct 11, 10:48 PM – Oct 14, 3:25 AM", or
/// "Since Oct 14, 12:13 PM".
String _compactRange(DeviceStay stay) {
  final start = stay.startedAt;
  final end = stay.endedAt;
  if (end == null) return 'Since ${_dateLabel(start)}, ${clockLabel(start)}';
  if (DateUtils.isSameDay(start, end)) {
    return '${_dateLabel(start)} · ${clockLabel(start)} – ${clockLabel(end)}';
  }
  return '${_dateLabel(start)}, ${clockLabel(start)} – '
      '${_dateLabel(end)}, ${clockLabel(end)}';
}

/// "Under 1 min", "45 min", "2 h 33 min", "3 d 4 h".
String _durationLabel(Duration d) {
  if (d.inMinutes < 1) return 'Under 1 min';
  if (d.inHours < 1) return '${d.inMinutes} min';
  if (d.inDays < 1) {
    final m = d.inMinutes % 60;
    return m == 0 ? '${d.inHours} h' : '${d.inHours} h $m min';
  }
  final h = d.inHours % 24;
  return h == 0 ? '${d.inDays} d' : '${d.inDays} d $h h';
}
