import 'dart:async';

import 'package:flutter/foundation.dart';

import 'metric_type.dart';
import 'trend_range.dart';
import 'trend_service.dart';

/// One row of the readings list: a time and each metric's value then.
typedef ReadingRow = ({DateTime time, Map<MetricType, double> values});

/// Ported from the farmer app's `ReadingsPager.forTrend`: a trend's steps as
/// rows (each metric's average over the step), newest first, handed out a
/// page at a time — so the readings list matches the chart: one row per
/// 15 minutes, hour, day, ... The steps are already loaded for the chart, so
/// paging costs no extra requests.
class ReadingsPager extends ChangeNotifier {
  ReadingsPager.forTrend(this._trend, {this.pageSize = 20});

  final AdminTrendController _trend;
  final int pageSize;

  List<ReadingRow>? _all;
  final List<ReadingRow> _rows = [];
  var _loading = false;
  var _exhausted = false;
  String? _error;
  var _disposed = false;

  /// What each row covers (its average).
  TrendStep get step => _trend.step;

  /// Loaded so far, newest first.
  List<ReadingRow> get rows => _rows;
  bool get loading => _loading;
  String? get error => _error;

  /// For [LazyLoadFooter]: a page's worth while there may be more.
  int get remaining => _exhausted ? 0 : pageSize;

  Future<List<ReadingRow>> _allRows() async {
    if (_all case final all?) return all;
    final series = await _trend.loaded;
    final byTime = <DateTime, Map<MetricType, double>>{};
    for (final entry in series.entries) {
      for (final point in entry.value) {
        (byTime[point.time] ??= {})[entry.key] = point.avg;
      }
    }
    final times = byTime.keys.toList()..sort((a, b) => b.compareTo(a));
    return _all = [for (final t in times) (time: t, values: byTime[t]!)];
  }

  /// Shows the next page. Ignored while one is loading or when there's
  /// nothing left.
  Future<void> loadMore() async {
    if (_loading || remaining <= 0) return;
    _loading = true;
    _error = null;
    _notify();
    try {
      final page = (await _allRows())
          .skip(_rows.length)
          .take(pageSize)
          .toList();
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
