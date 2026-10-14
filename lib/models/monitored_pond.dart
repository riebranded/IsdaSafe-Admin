import 'package:flutter/material.dart';

enum ReadingStatus { normal, warning, critical }

extension ReadingStatusInfo on ReadingStatus {
  IconData get icon => switch (this) {
    ReadingStatus.normal => Icons.check_circle,
    ReadingStatus.warning => Icons.warning_rounded,
    ReadingStatus.critical => Icons.error,
  };

  String get label => switch (this) {
    ReadingStatus.normal => 'Normal',
    ReadingStatus.warning => 'Warning',
    ReadingStatus.critical => 'Critical',
  };
}

/// The water readings that decide a pond's status — same set as the farmer
/// app's `MetricType.water` (ammonia counts as free ammonia, the toxic part).
enum WaterMetric {
  temperature('Water Temp', '°C', Icons.thermostat, 1),
  dissolvedOxygen('Dissolved O₂', 'mg/L', Icons.bubble_chart, 1),
  ph('pH', '', Icons.opacity, 1),
  freeAmmonia('Free Ammonia', 'mg/L', Icons.warning_amber_rounded, 3);

  const WaterMetric(this.label, this.unit, this.icon, this.decimals);

  final String label;
  final String unit;
  final IconData icon;
  final int decimals;

  String format(double value) {
    final formatted = value.toStringAsFixed(decimals);
    return unit.isEmpty ? formatted : '$formatted $unit';
  }

  /// Pond-health bands copied from the farmer app's `reading_bands.dart`, so
  /// both apps call the same reading Normal/Warning/Critical.
  ReadingStatus statusFor(double value) {
    final (critLo, warnLo, warnHi, critHi) = switch (this) {
      WaterMetric.temperature => (22.0, 25.0, 29.0, 32.0),
      WaterMetric.dissolvedOxygen => (2.0, 4.0, null, null),
      WaterMetric.ph => (6.0, 6.5, 8.5, 9.0),
      WaterMetric.freeAmmonia => (null, null, 0.02, 0.05),
    };
    if ((critLo != null && value < critLo) ||
        (critHi != null && value > critHi)) {
      return ReadingStatus.critical;
    }
    if ((warnLo != null && value < warnLo) ||
        (warnHi != null && value > warnHi)) {
      return ReadingStatus.warning;
    }
    return ReadingStatus.normal;
  }
}

enum DeviceConnection { online, offline, neverConnected }

/// A pond with a paired IsdaSafe device, as returned by the
/// `admin_monitored_ponds` RPC.
class MonitoredPond {
  const MonitoredPond({
    required this.pondId,
    required this.pondName,
    required this.deviceId,
    required this.speciesNames,
    required this.readings,
    this.latitude,
    this.longitude,
    this.verificationStatus,
    this.ownerName,
    this.ownerEmail,
    this.ownerPhone,
    this.pairedAt,
    this.lastSeenAt,
    this.readingAt,
    this.humidity,
    this.airTemperature,
    this.ammonia,
  });

  factory MonitoredPond.fromRow(Map<String, dynamic> row) {
    double? number(String key) => (row[key] as num?)?.toDouble();
    DateTime? time(String key) =>
        row[key] == null ? null : DateTime.parse(row[key] as String).toLocal();

    final readings = <WaterMetric, double>{
      WaterMetric.temperature: ?number('water_temperature'),
      WaterMetric.dissolvedOxygen: ?number('dissolved_oxygen'),
      WaterMetric.ph: ?number('ph'),
      WaterMetric.freeAmmonia: ?number('free_ammonia'),
    };

    return MonitoredPond(
      pondId: row['pond_id'] as String,
      pondName: row['pond_name'] as String,
      deviceId: row['device_id'] as String,
      speciesNames: [
        for (final s in (row['species_names'] as List<dynamic>? ?? const []))
          s as String,
      ],
      readings: readings,
      latitude: number('latitude'),
      longitude: number('longitude'),
      verificationStatus: row['verification_status'] as String?,
      ownerName: row['owner_name'] as String?,
      ownerEmail: row['owner_email'] as String?,
      ownerPhone: row['owner_phone'] as String?,
      pairedAt: time('paired_at'),
      lastSeenAt: time('last_seen_at'),
      readingAt: time('reading_at'),
      humidity: number('humidity'),
      airTemperature: number('air_temperature'),
      ammonia: number('ammonia'),
    );
  }

  /// Same threshold as the farmer app's `PondReadingsStore.minOfflineAfter`:
  /// three missed once-a-minute uploads.
  static const offlineAfter = Duration(minutes: 3);

  final String pondId;
  final String pondName;
  final String deviceId;
  final List<String> speciesNames;
  final Map<WaterMetric, double> readings;
  final double? latitude;
  final double? longitude;
  final String? verificationStatus;
  final String? ownerName;
  final String? ownerEmail;
  final String? ownerPhone;
  final DateTime? pairedAt;
  final DateTime? lastSeenAt;
  final DateTime? readingAt;
  final double? humidity;
  final double? airTemperature;

  /// Total ammonia; [readings] holds the free (toxic) part.
  final double? ammonia;

  DeviceConnection connection([DateTime? now]) {
    final last = lastSeenAt ?? readingAt;
    if (last == null) return DeviceConnection.neverConnected;
    return (now ?? DateTime.now()).difference(last) <= offlineAfter
        ? DeviceConnection.online
        : DeviceConnection.offline;
  }

  /// Worst status across the latest water readings; null when the device
  /// hasn't reported any yet.
  ReadingStatus? get status {
    if (readings.isEmpty) return null;
    var worst = ReadingStatus.normal;
    for (final MapEntry(:key, :value) in readings.entries) {
      final s = key.statusFor(value);
      if (s.index > worst.index) worst = s;
    }
    return worst;
  }
}
