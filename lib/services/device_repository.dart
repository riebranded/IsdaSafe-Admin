import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../analytics/metric_type.dart';
import '../analytics/readings_pager.dart';
import '../analytics/trend_range.dart';
import '../models/monitored_pond.dart';

/// A device IsdaSafe knows about, as `admin_device_list` returns it: every
/// manufactured, paired or previously paired device, whoever owns it.
class AdminDevice {
  const AdminDevice({
    required this.id,
    required this.manufacturedAt,
    required this.ownerName,
    required this.ownerEmail,
    required this.pondName,
    required this.pairedAt,
    required this.lastSeenAt,
    required this.placeCount,
    required this.readingCount,
    required this.lastPlacedAt,
    required this.isPaired,
  });

  factory AdminDevice.fromRow(Map<String, dynamic> row) {
    DateTime? time(String key) => row[key] is String
        ? DateTime.parse(row[key] as String).toLocal()
        : null;
    return AdminDevice(
      id: row['device_id'] as String,
      manufacturedAt: time('manufactured_at'),
      ownerName: row['owner_name'] as String?,
      ownerEmail: row['owner_email'] as String?,
      pondName: row['pond_name'] as String?,
      pairedAt: time('paired_at'),
      lastSeenAt: time('last_seen_at'),
      placeCount: (row['place_count'] as num?)?.toInt() ?? 0,
      readingCount: (row['reading_count'] as num?)?.toInt() ?? 0,
      lastPlacedAt: time('last_placed_at'),
      isPaired: row['owner_id'] != null,
    );
  }

  final String id;

  /// When its factory credentials were registered; null for devices that
  /// only appear in pairings.
  final DateTime? manufacturedAt;

  /// The account that has it now (null when nobody does).
  final String? ownerName;
  final String? ownerEmail;
  final bool isPaired;

  /// The pond it's on now.
  final String? pondName;
  final DateTime? pairedAt;
  final DateTime? lastSeenAt;

  /// Ponds (that still exist) where it sent at least one complete reading,
  /// and how many complete readings it sent there in all.
  final int placeCount;
  final int readingCount;
  final DateTime? lastPlacedAt;

  bool get hasHistory => placeCount > 0;

  /// Same rule as the ponds: three missed once-a-minute uploads is offline.
  DeviceConnection get connection {
    final last = lastSeenAt;
    if (last == null) return DeviceConnection.neverConnected;
    return DateTime.now().difference(last) <= MonitoredPond.offlineAfter
        ? DeviceConnection.online
        : DeviceConnection.offline;
  }
}

/// One stay of a device at a pond, under whichever account had the device
/// then (`admin_device_location_history`). Only stays at ponds that still
/// exist and with at least one complete reading are listed.
class DeviceStay {
  const DeviceStay({
    required this.id,
    required this.pondId,
    required this.pondName,
    required this.ownerId,
    required this.ownerName,
    required this.ownerEmail,
    required this.latitude,
    required this.longitude,
    required this.startedAt,
    required this.endedAt,
    required this.readingCount,
  });

  final int id;
  final String? pondId;
  final String? pondName;
  final String? ownerId;
  final String? ownerName;
  final String? ownerEmail;
  final double? latitude;
  final double? longitude;
  final DateTime startedAt;

  /// Null while the device is still there.
  final DateTime? endedAt;
  final int readingCount;

  bool get isCurrent => endedAt == null;
  bool get hasLocation => latitude != null && longitude != null;
}

/// The admin Devices tab's data. Every call is refused for accounts that
/// aren't approved admins.
class DeviceRepository {
  const DeviceRepository._();

  static SupabaseClient get _client => Supabase.instance.client;

  /// Replace the database calls in tests.
  @visibleForTesting
  static Future<List<AdminDevice>> Function()? debugDevices;
  @visibleForTesting
  static Future<List<DeviceStay>> Function(String deviceId)? debugStays;
  @visibleForTesting
  static ReadingsPageLoader Function(
    int stayId,
    DateTimeRange? window,
    TrendStep? step,
  )?
  debugStayReadings;

  /// Every device, most recently active first.
  static Future<List<AdminDevice>> devices() async {
    if (debugDevices case final fake?) return fake();
    final rows = await _client.rpc('admin_device_list') as List<dynamic>;
    return [
      for (final row in rows) AdminDevice.fromRow(row as Map<String, dynamic>),
    ];
  }

  /// [deviceId]'s stays, newest first.
  static Future<List<DeviceStay>> stays(String deviceId) async {
    if (debugStays case final fake?) return fake(deviceId);
    final rows =
        await _client.rpc(
              'admin_device_location_history',
              params: {'p_device_id': deviceId},
            )
            as List<dynamic>;
    DateTime? time(Object? value) =>
        value is String ? DateTime.parse(value).toLocal() : null;
    return [
      for (final row in rows.cast<Map<String, dynamic>>())
        DeviceStay(
          id: (row['id'] as num).toInt(),
          pondId: row['pond_id'] as String?,
          pondName: row['pond_name'] as String?,
          ownerId: row['owner_id'] as String?,
          ownerName: row['owner_name'] as String?,
          ownerEmail: row['owner_email'] as String?,
          latitude: (row['latitude'] as num?)?.toDouble(),
          longitude: (row['longitude'] as num?)?.toDouble(),
          startedAt: time(row['started_at'])!,
          endedAt: time(row['ended_at']),
          readingCount: (row['reading_count'] as num).toInt(),
        ),
    ];
  }

  static const _columns = {
    'water_temperature': MetricType.temperature,
    'dissolved_oxygen': MetricType.dissolvedOxygen,
    'ph': MetricType.ph,
    'free_ammonia': MetricType.freeAmmonia,
    'ammonia': MetricType.ammonia,
    'humidity': MetricType.humidity,
    'air_temperature': MetricType.airTemperature,
  };

  /// A visit's complete readings, a page at a time (newest first).
  /// [window] limits them to a timeframe; null is the whole visit.
  ///
  /// With a [step], each row is that period's average (dated by the period's
  /// start) instead of a single reading.
  static ReadingsPager stayReadings(
    int stayId, {
    DateTimeRange? window,
    TrendStep? step,
    bool withDates = false,
  }) {
    return ReadingsPager(
      debugStayReadings?.call(stayId, window, step) ??
          _stayPage(stayId, window, step),
      step: step,
      withDates: withDates,
    );
  }

  /// When [stayId]'s newest complete reading was taken; null if it has none.
  static Future<DateTime?> lastStayReading(int stayId) async {
    final load =
        debugStayReadings?.call(stayId, null, null) ??
        _stayPage(stayId, null, null);
    final rows = await load(0, 1);
    return rows.isEmpty ? null : rows.first.time;
  }

  static ReadingsPageLoader _stayPage(
    int stayId,
    DateTimeRange? window,
    TrendStep? step,
  ) => (offset, limit) async {
    final rows =
        await _client.rpc(
              'admin_device_stay_readings',
              params: {
                'p_stay_id': stayId,
                'p_offset': offset,
                'p_limit': limit,
                'p_from': ?window?.start.toUtc().toIso8601String(),
                'p_to': ?window?.end.toUtc().toIso8601String(),
                'p_step': ?step?.rpcName,
                if (step != null)
                  'p_utc_offset_minutes':
                      DateTime.now().timeZoneOffset.inMinutes,
              },
            )
            as List<dynamic>;
    return [
      for (final row in rows.cast<Map<String, dynamic>>())
        (
          time: DateTime.parse(row['created_at'] as String).toLocal(),
          values: {
            for (final MapEntry(:key, :value) in _columns.entries)
              if (row[key] case final num v) value: v.toDouble(),
          },
        ),
    ];
  };
}
