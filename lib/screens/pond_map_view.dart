import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/monitored_pond.dart';
import '../services/monitoring_repository.dart';
import '../theme/app_spacing.dart';
import '../widgets/status_badge.dart';
import 'pond_page.dart';

/// The Philippines, for when no pond has a location yet (same as the farmer
/// app's `kDefaultMapCenter` / `kDefaultMapZoom`).
const _defaultCenter = LatLng(12.8797, 121.7740);
const _defaultZoom = 5.5;

/// Only the web build loads the Maps JavaScript API (web/index.html); the
/// admin app has no native Maps key, so other platforms get a list instead.
bool get _mapSupported => kIsWeb;

/// Every pond with a paired device pinned on one map, colored by its water
/// status, with the owner in the marker's bubble — the admin take on the
/// farmer app's `PondMapScreen`. Tapping a pond opens it full screen
/// ([PondPage]). Refreshes every minute, like Monitoring.
class PondMapView extends StatefulWidget {
  const PondMapView({super.key});

  @override
  State<PondMapView> createState() => _PondMapViewState();
}

class _PondMapViewState extends State<PondMapView> {
  static const _refreshInterval = Duration(minutes: 1);

  List<MonitoredPond>? _ponds;
  Object? _error;
  String? _selectedId;
  var _loading = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(_refreshInterval, (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      final ponds = await MonitoringRepository.fetchMonitoredPonds();
      if (mounted) {
        setState(() {
          _ponds = ponds;
          _error = null;
        });
      }
    } catch (e) {
      debugPrint('PondMapView: load failed $e');
      if (mounted) setState(() => _error = e);
    } finally {
      _loading = false;
    }
  }

  Future<void> _select(MonitoredPond pond) async {
    // Highlighted on the map while its page is open, and after coming back.
    setState(() => _selectedId = pond.pondId);
    await openPond(context, pond);
  }

  @override
  Widget build(BuildContext context) {
    final ponds = _ponds;
    if (ponds == null) {
      if (_error != null) {
        return _CenteredMessage(
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
      return const Center(child: CircularProgressIndicator());
    }
    if (ponds.isEmpty) {
      return const _CenteredMessage(
        icon: Icons.sensors_off_outlined,
        title: 'No devices paired yet',
        message: 'Ponds appear here once a farmer pairs an IsdaSafe device.',
      );
    }

    return _mapSupported
        ? _PondMap(ponds: ponds, selectedId: _selectedId, onSelect: _select)
        : _PondList(ponds: ponds, selectedId: _selectedId, onSelect: _select);
  }
}

class _PondMap extends StatelessWidget {
  const _PondMap({
    required this.ponds,
    required this.selectedId,
    required this.onSelect,
  });

  final List<MonitoredPond> ponds;
  final String? selectedId;
  final ValueChanged<MonitoredPond> onSelect;

  static double _hueFor(ReadingStatus? status) => switch (status) {
    // Paired, but no reading yet.
    null => BitmapDescriptor.hueAzure,
    ReadingStatus.normal => BitmapDescriptor.hueGreen,
    ReadingStatus.warning => BitmapDescriptor.hueOrange,
    ReadingStatus.critical => BitmapDescriptor.hueRed,
  };

  /// One marker per located pond. The bubble names the owner and the status
  /// (title + snippet, so it lays out as a normal card, like the farmer
  /// app's markers); tapping the marker or the bubble opens the pond.
  Marker _markerFor(MonitoredPond pond) {
    final status = pond.status;
    return Marker(
      markerId: MarkerId(pond.pondId),
      position: LatLng(pond.latitude!, pond.longitude!),
      infoWindow: InfoWindow(
        title: pond.pondName,
        snippet:
            'Owner: ${pond.ownerName ?? 'Unknown'} · '
            '${status == null ? 'No readings yet' : status.label}',
        onTap: () => onSelect(pond),
      ),
      icon: BitmapDescriptor.defaultMarkerWithHue(_hueFor(status)),
      zIndexInt: pond.pondId == selectedId ? 1 : 0,
      onTap: () => onSelect(pond),
    );
  }

  @override
  Widget build(BuildContext context) {
    final located = ponds
        .where((p) => p.latitude != null && p.longitude != null)
        .toList();
    final unlocated = ponds.length - located.length;
    final initialTarget = located.isNotEmpty
        ? LatLng(located.first.latitude!, located.first.longitude!)
        : _defaultCenter;

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: initialTarget,
            zoom: located.isNotEmpty ? 12 : _defaultZoom,
          ),
          myLocationButtonEnabled: false,
          markers: {for (final pond in located) _markerFor(pond)},
          onMapCreated: (controller) {
            if (located.length < 2) return;
            // Fit every pond in view.
            var south = located.first.latitude!, north = south;
            var west = located.first.longitude!, east = west;
            for (final p in located) {
              if (p.latitude! < south) south = p.latitude!;
              if (p.latitude! > north) north = p.latitude!;
              if (p.longitude! < west) west = p.longitude!;
              if (p.longitude! > east) east = p.longitude!;
            }
            controller.moveCamera(
              CameraUpdate.newLatLngBounds(
                LatLngBounds(
                  southwest: LatLng(south, west),
                  northeast: LatLng(north, east),
                ),
                64,
              ),
            );
          },
        ),
        Positioned(
          left: AppSpacing.md,
          bottom: AppSpacing.xl,
          child: _Legend(unlocated: unlocated),
        ),
      ],
    );
  }
}

/// What the marker colors mean (status is also named in each bubble, so
/// color is never the only cue).
class _Legend extends StatelessWidget {
  const _Legend({required this.unlocated});

  final int unlocated;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = [
      (ReadingStatus.normal.colorOf(context), 'Normal'),
      (ReadingStatus.warning.colorOf(context), 'Warning'),
      (ReadingStatus.critical.colorOf(context), 'Critical'),
      (Colors.lightBlue, 'No readings yet'),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (color, label) in colors)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.place, size: 16, color: color),
                    const SizedBox(width: AppSpacing.xs),
                    Text(label, style: theme.textTheme.labelMedium),
                  ],
                ),
              ),
            if (unlocated > 0) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                unlocated == 1
                    ? '1 pond has no location'
                    : '$unlocated ponds have no location',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Where there's no map view: the same ponds as a list.
class _PondList extends StatelessWidget {
  const _PondList({
    required this.ponds,
    required this.selectedId,
    required this.onSelect,
  });

  final List<MonitoredPond> ponds;
  final String? selectedId;
  final ValueChanged<MonitoredPond> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text(
          'The map is only available in the web version. Select a pond to '
          'see its readings.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        for (final pond in ponds) ...[
          Card(
            child: ListTile(
              selected: pond.pondId == selectedId,
              leading: const Icon(Icons.water_drop_outlined),
              title: Text(pond.pondName),
              subtitle: Text(pond.ownerName ?? 'Unknown owner'),
              trailing: pond.status == null
                  ? null
                  : StatusPill.status(pond.status!, context),
              onTap: () => onSelect(pond),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
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
