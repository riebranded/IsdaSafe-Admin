import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:isdasafe_admin/analytics/metric_type.dart';
import 'package:isdasafe_admin/analytics/reading_days.dart';
import 'package:isdasafe_admin/analytics/trend_range.dart';
import 'package:isdasafe_admin/screens/devices_view.dart';
import 'package:isdasafe_admin/services/device_repository.dart';
import 'package:isdasafe_admin/theme/app_theme.dart';

AdminDevice _device(
  String id, {
  String? owner,
  String? pond,
  int places = 0,
  int readings = 0,
  Duration? seenAgo,
}) => AdminDevice(
  id: id,
  manufacturedAt: DateTime(2026, 9, 1),
  ownerName: owner,
  ownerEmail: owner == null ? null : '${owner.toLowerCase()}@example.com',
  pondName: pond,
  pairedAt: owner == null ? null : DateTime(2026, 9, 10),
  lastSeenAt: seenAgo == null ? null : DateTime.now().subtract(seenAgo),
  placeCount: places,
  readingCount: readings,
  lastPlacedAt: places == 0 ? null : DateTime(2026, 10, 1),
  isPaired: owner != null,
);

final _devices = [
  _device(
    '6C383B124B00',
    owner: 'Jose',
    pond: 'Tilapia Pen A',
    places: 2,
    readings: 2531,
    seenAgo: const Duration(seconds: 30),
  ),
  _device('AABBCCDDEEFF'),
];

List<DeviceStay> _stays() {
  final now = DateTime.now();
  DeviceStay stay(
    int id,
    String pond,
    String owner,
    int startDays,
    int? endDays,
    int readings,
  ) => DeviceStay(
    id: id,
    pondId: 'pond-$pond',
    pondName: pond,
    ownerId: 'u-$owner',
    ownerName: owner,
    ownerEmail: '${owner.toLowerCase()}@example.com',
    latitude: null,
    longitude: null,
    startedAt: now.subtract(Duration(days: startDays)),
    endedAt: endDays == null ? null : now.subtract(Duration(days: endDays)),
    readingCount: readings,
  );
  return [
    stay(3, 'Tilapia Pen A', 'Jose', 2, null, 1200),
    stay(2, 'Old Pond', 'Maria', 9, 3, 1100),
    stay(1, 'Tilapia Pen A', 'Jose', 20, 10, 231),
  ];
}

/// The time windows the readings table asked for (null = whole visit).
final requestedWindows = <DateTimeRange?>[];

/// Fake data for the repository (also used by screenshot tests).
void installFakes() {
  DeviceRepository.debugDevices = () async => _devices;
  DeviceRepository.debugStays = (id) async =>
      id == '6C383B124B00' ? _stays() : const [];
  DeviceRepository.debugStayReadings = (stayId, window, step) {
    requestedWindows.add(window);
    return (offset, limit) async {
      if (offset > 0) return const [];
      final now = DateTime.now();
      return [
        for (var i = 0; i < 5; i++)
          (
            time: now.subtract(Duration(minutes: i * 3)),
            values: {
              MetricType.temperature: 28.0 + i / 10,
              MetricType.dissolvedOxygen: 5.2,
              MetricType.ph: 7.3,
              MetricType.freeAmmonia: 0.01,
            },
          ),
      ];
    };
  };
}

Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  installFakes();
  addTearDown(() {
    DeviceRepository.debugDevices = null;
    DeviceRepository.debugStays = null;
    DeviceRepository.debugStayReadings = null;
  });

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF0F7490),
        extensions: const [StatusColors.light],
      ),
      home: const Scaffold(body: DevicesView()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final size in const [Size(1400, 1000), Size(390, 1600)]) {
    testWidgets('lists every device at ${size.width.toInt()}px', (
      tester,
    ) async {
      await _pump(tester, size);
      expect(find.text('Device 6C383B124B00'), findsOneWidget);
      // Never paired, no history: still listed for admins.
      expect(find.text('Device AABBCCDDEEFF'), findsOneWidget);
      expect(find.text('Not paired to any account'), findsOneWidget);
      expect(find.text('No complete readings yet'), findsOneWidget);
      expect(find.text('2 ponds · 2,531 complete readings'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('on a phone the ponds stay in view under a folded summary', (
    tester,
  ) async {
    const size = Size(390, 700);
    await _pump(tester, size);
    await tester.tap(find.text('Device 6C383B124B00'));
    await tester.pumpAndSettle();

    // The device's details are folded to its status, owner and pond ...
    expect(find.textContaining('Last upload'), findsNothing);
    // ... so a pond is on screen without scrolling.
    final pond = tester.getRect(find.text('Old Pond'));
    expect(pond.bottom, lessThan(size.height - 100));

    // Tapping the summary unfolds the rest.
    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();
    expect(find.textContaining('Last upload'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('on a phone the readings are the wide table, scrolled sideways', (
    tester,
  ) async {
    await _pump(tester, const Size(390, 1600));
    await tester.tap(find.text('Device 6C383B124B00'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Old Pond'));
    await tester.pumpAndSettle();

    expect(find.text('Time'), findsOneWidget);
    final sideways = find.byWidgetPredicate(
      (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
    );
    expect(sideways, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filters and searches', (tester) async {
    await _pump(tester, const Size(1400, 1000));
    await tester.tap(find.text('Not paired (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Device AABBCCDDEEFF'), findsOneWidget);
    expect(find.text('Device 6C383B124B00'), findsNothing);

    await tester.tap(find.text('All (2)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'jose');
    await tester.pumpAndSettle();
    expect(find.text('Device 6C383B124B00'), findsOneWidget);
    expect(find.text('Device AABBCCDDEEFF'), findsNothing);
  });

  testWidgets('opens a device, its ponds and a visit\'s readings', (
    tester,
  ) async {
    await _pump(tester, const Size(1400, 1000));
    await tester.tap(find.text('Device 6C383B124B00'));
    await tester.pumpAndSettle();
    // Grouped by pond: Tilapia Pen A (2 visits) and Old Pond.
    expect(find.text('Tilapia Pen A'), findsOneWidget);
    expect(find.text('Old Pond'), findsOneWidget);
    expect(find.text('Jose · jose@example.com'), findsOneWidget);

    await tester.tap(find.text('Old Pond'));
    await tester.pumpAndSettle();
    expect(
      find.text('Owned during this visit by Maria (maria@example.com).'),
      findsOneWidget,
    );
    expect(find.text('Complete readings'), findsWidgets);
    expect(find.text('Time'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a device without history explains itself', (tester) async {
    await _pump(tester, const Size(1400, 1000));
    await tester.tap(find.text('Device AABBCCDDEEFF'));
    await tester.pumpAndSettle();
    expect(find.text('No location history yet'), findsOneWidget);
    expect(find.text('Not on a pond'), findsOneWidget);
  });

  testWidgets('limits a visit\'s readings to a timeframe', (tester) async {
    await _pump(tester, const Size(1400, 1000));
    await tester.tap(find.text('Device 6C383B124B00'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tilapia Pen A'));
    await tester.pumpAndSettle();
    requestedWindows.clear();

    // Whole visit is the default; the presets and Custom sit beside it.
    expect(find.text('Whole visit'), findsOneWidget);
    expect(find.text('Daily'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);
    expect(find.textContaining('Whole visit · Since'), findsOneWidget);

    await tester.tap(find.text('Daily'));
    await tester.pumpAndSettle();
    expect(requestedWindows.last, isNotNull);
    final window = requestedWindows.last!;
    expect(window.end.isAfter(window.start), isTrue);
    expect(find.textContaining('of this visit'), findsOneWidget);

    await tester.tap(find.text('Whole visit'));
    await tester.pumpAndSettle();
    expect(requestedWindows.last, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a past visit\'s timeframe is counted back from the visit', (
    tester,
  ) async {
    final stays = _stays();
    final visit = stays.firstWhere((s) => s.id == 2);
    final visitEnd = visit.endedAt!;
    // One reading in the visit's last hour, one three days before it ended.
    final recent = visitEnd.subtract(const Duration(hours: 1));
    final older = visitEnd.subtract(const Duration(days: 3, minutes: 20));
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    installFakes();
    addTearDown(() {
      DeviceRepository.debugDevices = null;
      DeviceRepository.debugStays = null;
      DeviceRepository.debugStayReadings = null;
    });
    DeviceRepository.debugStays = (id) async =>
        id == '6C383B124B00' ? stays : const [];
    final windows = <DateTimeRange?>[];
    final steps = <TrendStep?>[];
    // Like the database: only the readings inside the asked-for window.
    DeviceRepository.debugStayReadings = (stayId, window, step) =>
        (offset, limit) {
          windows.add(window);
          steps.add(step);
          if (offset > 0) return Future.value(const []);
          return Future.value([
            for (final time in [recent, older])
              if (window == null ||
                  (!time.isBefore(window.start) && !time.isAfter(window.end)))
                (time: time, values: {MetricType.temperature: 28.0}),
          ]);
        };

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF0F7490),
          extensions: const [StatusColors.light],
        ),
        home: const Scaffold(body: DevicesView()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Device 6C383B124B00'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Old Pond'));
    await tester.pumpAndSettle();

    // The whole visit shows every reading (not averaged), each with its date.
    expect(
      find.text(TrendStep.fifteenMinutes.fullLabel(recent)),
      findsOneWidget,
    );
    expect(
      find.text(TrendStep.fifteenMinutes.fullLabel(older)),
      findsOneWidget,
    );
    expect(steps.last, isNull);

    // No "Group by" choice while the whole visit is shown.
    expect(find.text('Group by'), findsNothing);

    // Its last 24 hours — not today's — leave just the recent one.
    await tester.tap(find.text('Hourly'));
    await tester.pumpAndSettle();
    expect(windows.last, isNotNull);
    expect(windows.last!.end, visitEnd);
    expect(
      windows.last!.start.isAfter(visitEnd.subtract(const Duration(days: 1))),
      isTrue,
    );
    expect(find.text(clockLabel(recent)), findsOneWidget);
    expect(find.text(clockLabel(older)), findsNothing);
    expect(steps.last, TrendStep.hour);

    // Daily asks for one row per day.
    await tester.tap(find.text('Daily'));
    await tester.pumpAndSettle();
    expect(steps.last, TrendStep.day);

    // A pond with no readings can't have custom dates picked.
    ReadingDays.debugLoad = (pond, device, complete) async => {};
    addTearDown(() => ReadingDays.debugLoad = null);
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    expect(find.text('No readings yet for this pond'), findsOneWidget);
    expect(find.text('Select start date'), findsNothing);
    ReadingDays.debugLoad = null;

    // Custom dates: after picking them, the grouping is asked for — the
    // visit's single readings or an average per step.
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Show the readings as'), findsOneWidget);
    for (final text in [
      'Whole visit',
      'Every 15 minutes',
      'Hourly',
      'Daily',
      'Weekly',
      'Monthly',
      'Yearly',
    ]) {
      expect(
        find.descendant(
          of: find.byType(SimpleDialog),
          matching: find.text(text),
        ),
        findsOneWidget,
      );
    }
    await tester.tap(
      find.descendant(
        of: find.byType(SimpleDialog),
        matching: find.text('Whole visit'),
      ),
    );
    await tester.pumpAndSettle();
    expect(steps.last, isNull);
    // Whole visit chosen for custom dates: no "Group by" row either.
    expect(find.text('Group by'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
