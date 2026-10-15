import 'dart:async';

import 'package:flutter/foundation.dart';

import 'metric_type.dart';
import 'trend_range.dart';
import 'trend_service.dart';

/// One row of the readings list: a time and each metric's value then.
typedef ReadingRow = ({DateTime time, Map<MetricType, double> values});

/// Rows [offset]..[offset] + [limit] of a list, newest first.
typedef ReadingsPageLoader =
    Future<List<ReadingRow>> Function(int offset, int limit);

/// Ported from the farmer app's `ReadingsPager`: a list of readings handed
/// out a page at a time, as the list is scrolled to its end.
///
/// [ReadingsPager.forTrend] pages a trend's steps (each metric's average over
/// the step) so the readings list matches the chart, at no extra request;
/// the plain constructor pages any [ReadingsPageLoader], e.g. a device
/// visit's single readings from the database.
class ReadingsPager extends ChangeNotifier {
  ReadingsPager(
    this._load, {
    this.step,
    this.withDates = false,
    this.pageSize = 20,
  });

  factory ReadingsPager.forTrend(AdminTrendController trend) {
    List<ReadingRow>? all;
    Future<List<ReadingRow>> allRows() async {
      if (all case final rows?) return rows;
      final series = await trend.loaded;
      final byTime = <DateTime, Map<MetricType, double>>{};
      for (final entry in series.entries) {
        for (final point in entry.value) {
          (byTime[point.time] ??= {})[entry.key] = point.avg;
        }
      }
      final times = byTime.keys.toList()..sort((a, b) => b.compareTo(a));
      return all = [for (final t in times) (time: t, values: byTime[t]!)];
    }

    return ReadingsPager(
      (offset, limit) async =>
          (await allRows()).skip(offset).take(limit).toList(),
      step: trend.step,
    );
  }

  final ReadingsPageLoader _load;
  final int pageSize;

  /// What each row averages; null when rows are single readings.
  final TrendStep? step;

  /// Whether every row carries its own date ("Oct 12, 3 PM", "Mon, Oct 12")
  /// instead of sitting under a day header, for lists spanning many days.
  final bool withDates;

  final List<ReadingRow> _rows = [];
  var _loading = false;
  var _exhausted = false;
  String? _error;
  var _disposed = false;

  /// Loaded so far, newest first.
  List<ReadingRow> get rows => _rows;
  bool get loading => _loading;
  String? get error => _error;

  /// For [LazyLoadFooter]: a page's worth while there may be more.
  int get remaining => _exhausted ? 0 : pageSize;

  /// Shows the next page. Ignored while one is loading or when there's
  /// nothing left.
  Future<void> loadMore() async {
    if (_loading || remaining <= 0) return;
    _loading = true;
    _error = null;
    _notify();
    try {
      final page = await _load(_rows.length, pageSize);
      _rows.addAll(page);
      if (page.length < pageSize) _exhausted = true;
    } catch (e) {
      _error = e.toString();
      debugPrint('ReadingsPager: page failed: $e');
    } finally {
      _loading = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
