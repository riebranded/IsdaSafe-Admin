import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:isdasafe_admin/analytics/trend_service.dart';
import 'package:isdasafe_admin/models/monitored_pond.dart';
import 'package:isdasafe_admin/screens/pond_page.dart';
import 'package:isdasafe_admin/theme/app_theme.dart';

MonitoredPond fakePond() {
  final now = DateTime.now().toUtc().toIso8601String();
  return MonitoredPond.fromRow({
    'pond_id': 'p1',
    'pond_name': 'Tilapia Pen A',
    'device_id': 'ISDA-001',
    'species_names': ['Tilapia'],
    'owner_name': 'Jose Rizal',
    'owner_email': 'jose@example.com',
    'owner_phone': '+639171234567',
    'last_seen_at': now,
    'reading_at': now,
    'water_temperature': 30.4,
    'dissolved_oxygen': 3.2,
    'ph': 7.4,
    'ammonia': 0.4,
    'free_ammonia': 0.012,
    'humidity': 82,
    'air_temperature': 31,
  });
}

/// A gentle wave per metric, one step per hour for the last day.
List<dynamic> fakeTrend(String pondId, DateTimeRange window, _) {
  const metrics = {
    'water_temperature': (28.0, 2.0),
    'dissolved_oxygen': (5.0, 1.5),
    'ph': (7.4, 0.4),
    'ammonia': (0.3, 0.1),
    'free_ammonia': (0.01, 0.005),
    'humidity': (80.0, 8.0),
    'air_temperature': (30.0, 3.0),
  };
  final rows = <Map<String, dynamic>>[];
  for (var h = 0; h < 24; h++) {
    final bucket = window.end.subtract(Duration(hours: 24 - h));
    if (bucket.isBefore(window.start)) continue;
    for (final MapEntry(key: metric, value: (base, amp)) in metrics.entries) {
      final v = base + amp * math.sin(h / 4);
      rows.add({
        'bucket': DateTime(
          bucket.year,
          bucket.month,
          bucket.day,
          bucket.hour,
        ).toUtc().toIso8601String(),
        'metric': metric,
        'readings': 60,
        'avg_value': v,
        'min_value': v - amp * 0.2,
        'max_value': v + amp * 0.2,
      });
    }
  }
  return rows;
}

Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  AdminTrendController.debugFetch = (id, window, step) async =>
      fakeTrend(id, window, step);
  addTearDown(() => AdminTrendController.debugFetch = null);

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF0F7490),
        extensions: const [StatusColors.light],
      ),
      home: PondPage(pond: fakePond()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final size in const [Size(1440, 3200), Size(390, 5200)]) {
    testWidgets('pond page lays out at ${size.width.toInt()}px', (
      tester,
    ) async {
      await _pump(tester, size);
      expect(find.text('Tilapia Pen A'), findsOneWidget);
      expect(find.text('Needs attention'), findsOneWidget);
      expect(find.text('Latest readings'), findsOneWidget);
      expect(find.text('Individual trends'), findsOneWidget);
      expect(find.text('Individual readings'), findsOneWidget);
      expect(find.text('Owner & device'), findsOneWidget);
      // The readings table's first page.
      expect(find.text('All within healthy range so far'), findsNothing);
      expect(find.textContaining('outside healthy range'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('tapping a reading opens its detail view', (tester) async {
    await _pump(tester, const Size(1440, 3200));

    await tester.tap(find.text('Dissolved Oxygen').first);
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.textContaining('What the farmer should do'), findsOneWidget);
    expect(find.text('Lowest'), findsOneWidget);
    expect(find.text('Average'), findsOneWidget);
    expect(find.text('Highest'), findsOneWidget);
    expect(find.text('What is Dissolved Oxygen?'), findsOneWidget);

    await tester.ensureVisible(find.text('Show readings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show readings'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text('Time')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
