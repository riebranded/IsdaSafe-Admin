import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'metric_type.dart';
import 'trend_range.dart';

/// One step of a trend: the readings taken from [time] until the next step.
/// Same as the farmer app's `TrendPoint`.
@immutable
class TrendPoint {
  const TrendPoint({
    required this.time,
    required this.avg,
    required this.min,
    required this.max,
    required this.count,
  });

  /// When the step starts.
  final DateTime time;
  final double avg;
  final double min;
  final double max;

  /// How many readings it's based on.
  final int count;

  /// The step as a single value (its average), for the chart's line.
  SensorReading asReading(MetricType type) =>
      SensorReading(type: type, value: avg, timestamp: time);
}

/// Lowest, average and highest of a series, and how many readings it covers.
typedef TrendStats = ({
  TrendPoint lowest,
  TrendPoint highest,
  double average,
  int readings,
});

/// Same as the farmer app's `statsOf`.
TrendStats? statsOf(List<TrendPoint> points) {
  if (points.isEmpty) return null;
  var lowest = points.first, highest = points.first;
  var sum = 0.0;
  var count = 0;
  for (final p in points) {
    if (p.min < lowest.min) lowest = p;
    if (p.max > highest.max) highest = p;
    sum += p.avg * p.count;
    count += p.count;
  }
  return (
    lowest: lowest,
    highest: highest,
    average: count == 0 ? points.first.avg : sum / count,
    readings: count,
  );
}

/// One monitored pond's trend for one [TrendSelection], grouped on the server
/// by `admin_pond_reading_trend` (the admin twin of the farmer app's
/// `pond_reading_trend`). Loads once; [error] is set if that fails.
class AdminTrendController extends ChangeNotifier {
  AdminTrendController(this.pondId, this.selection)
    : window = selection.window(),
      step = selection.step {
    unawaited(_load());
  }

  static const _metricOf = {
    'water_temperature': MetricType.temperature,
    'humidity': MetricType.humidity,
    'ammonia': MetricType.ammonia,
    'dissolved_oxygen': MetricType.dissolvedOxygen,
    'ph': MetricType.ph,
    'air_temperature': MetricType.airTemperature,
    'free_ammonia': MetricType.freeAmmonia,
  };

  final String pondId;
  final TrendSelection selection;
  final DateTimeRange window;
  final TrendStep step;

  Map<MetricType, List<TrendPoint>>? _series;
  Object? _error;
  final _loaded = Completer<Map<MetricType, List<TrendPoint>>>();

  /// Completes with every metric's steps once loaded (rethrows a failure).
  Future<Map<MetricType, List<TrendPoint>>> get loaded => _loaded.future;
  var _disposed = false;

  bool get loading => _series == null && _error == null;
  Object? get error => _error;

  List<TrendPoint> pointsFor(MetricType type) => _series?[type] ?? const [];

  /// Replaces the RPC in tests: returns its rows for a pond and window.
  @visibleForTesting
  static Future<List<dynamic>> Function(
    String pondId,
    DateTimeRange window,
    TrendStep step,
  )?
  debugFetch;

  Future<void> _load() async {
    try {
      final rows =
          await debugFetch?.call(pondId, window, step) ??
          await Supabase.instance.client.rpc(
                'admin_pond_reading_trend',
                params: {
                  'p_pond_id': pondId,
                  'p_start': window.start.toUtc().toIso8601String(),
                  'p_end': window.end.toUtc().toIso8601String(),
                  'p_step': step.rpcName,
                },
              )
              as List<dynamic>;
      final series = <MetricType, List<TrendPoint>>{};
      for (final row in rows.cast<Map<String, dynamic>>()) {
        final type = _metricOf[row['metric']];
        if (type == null) continue;
        (series[type] ??= []).add(
          TrendPoint(
            time: DateTime.parse(row['bucket'] as String).toLocal(),
            avg: (row['avg_value'] as num).toDouble(),
            min: (row['min_value'] as num).toDouble(),
            max: (row['max_value'] as num).toDouble(),
            count: (row['readings'] as num).toInt(),
          ),
        );
      }
      _series = series;
      _loaded.complete(series);
    } catch (e) {
      debugPrint('AdminTrendController: load failed $e');
      _error = e;
      _loaded.completeError(e);
      // Nobody may be waiting on [loaded]; don't report it as unhandled.
      unawaited(_loaded.future.then((_) {}, onError: (_) {}));
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
