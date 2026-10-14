import 'package:flutter/material.dart';

import '../models/monitored_pond.dart';
import '../theme/app_theme.dart';

extension ReadingStatusColor on ReadingStatus {
  Color colorOf(BuildContext context) {
    final colors = context.statusColors;
    return switch (this) {
      ReadingStatus.normal => colors.good,
      ReadingStatus.warning => colors.warning,
      ReadingStatus.critical => colors.critical,
    };
  }
}

/// A small icon + text pill so status is never conveyed by color alone
/// (same treatment as the farmer app's StatusBadge).
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
  });

  StatusPill.status(ReadingStatus status, BuildContext context, {Key? key})
    : this(
        key: key,
        label: status.label,
        icon: status.icon,
        color: status.colorOf(context),
      );

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final labelStyle =
        Theme.of(context).textTheme.labelMedium ??
        const TextStyle(fontSize: 12);

    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: labelStyle.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A device's connection (online / offline / never connected) as a pill.
class ConnectionPill extends StatelessWidget {
  const ConnectionPill({super.key, required this.pond});

  final MonitoredPond pond;

  @override
  Widget build(BuildContext context) {
    final colors = context.statusColors;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return switch (pond.connection()) {
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
