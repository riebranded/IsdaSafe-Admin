import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:isdasafe_admin/models/monitored_pond.dart';
import 'package:isdasafe_admin/screens/monitoring_view.dart';
import 'package:isdasafe_admin/services/admin_auth_service.dart';
import 'package:isdasafe_admin/theme/app_theme.dart';

/// Ponds covering every state a card or row can show.
List<MonitoredPond> _fakePonds() {
  final now = DateTime.now().toUtc();
  String ago(Duration d) => now.subtract(d).toIso8601String();
  MonitoredPond pond(
    String name, {
    String? seen,
    double? temp,
    double? oxygen,
    double? ph,
    double? freeAmmonia,
    String? owner = 'Juan dela Cruz',
  }) => MonitoredPond.fromRow({
    'pond_id': name,
    'pond_name': name,
    'device_id': 'ISDA-${name.hashCode.abs()}',
    'species_names': ['Tilapia'],
    'owner_name': owner,
    'owner_email': 'owner@example.com',
    'last_seen_at': seen,
    'reading_at': seen,
    'water_temperature': temp,
    'dissolved_oxygen': oxygen,
    'ph': ph,
    'free_ammonia': freeAmmonia,
  });

  return [
    pond(
      'North pond',
      seen: ago(const Duration(seconds: 30)),
      temp: 27.4,
      oxygen: 6.1,
      ph: 7.2,
      freeAmmonia: 0.004,
    ),
    pond(
      'A very long pond name that should be truncated nicely in every layout',
      seen: ago(const Duration(minutes: 1)),
      temp: 33.2,
      oxygen: 1.5,
      ph: 9.4,
      freeAmmonia: 0.09,
      owner: 'An owner with an equally long name to stress the layout',
    ),
    pond(
      'Warning pond',
      seen: ago(const Duration(minutes: 2)),
      temp: 30,
      oxygen: 3.5,
      ph: 7,
      freeAmmonia: 0.01,
    ),
    pond(
      'Offline pond',
      seen: ago(const Duration(hours: 5)),
      temp: 26,
      oxygen: 5,
      ph: 7.5,
      freeAmmonia: 0.01,
    ),
    pond('New pond', owner: null),
  ];
}

Future<void> _pump(WidgetTester tester, double width, double height) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final theme = ThemeData(
    useMaterial3: true,
    colorSchemeSeed: const Color(0xFF0F7490),
    extensions: const [StatusColors.light],
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(body: MonitoringView(loader: () async => _fakePonds())),
    ),
  );
  await tester.pumpAndSettle();
}

/// Disposes the view so its refresh timer doesn't outlive the test.
Future<void> _unmount(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox());

void main() {
  for (final (width, height) in const [
    (1600.0, 1000.0),
    (1000.0, 900.0),
    (700.0, 2400.0),
    (390.0, 3200.0),
  ]) {
    testWidgets('lays out without overflow at ${width.toInt()}px', (
      tester,
    ) async {
      await _pump(tester, width, height);
      expect(find.text('POND MONITORING'), findsOneWidget);
      expect(find.text('North pond'), findsOneWidget);

      // List layout.
      await tester.tap(find.byIcon(Icons.view_list));
      await tester.pumpAndSettle();
      expect(find.text('North pond'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _unmount(tester);
    });
  }

  testWidgets('stat tiles filter and urgent ponds sort first', (tester) async {
    await _pump(tester, 1600, 1000);

    // Default sort: the critical pond comes before the normal one.
    final critical = tester.getTopLeft(
      find.textContaining('A very long pond name').first,
    );
    final normal = tester.getTopLeft(find.text('North pond'));
    expect(
      critical.dy < normal.dy ||
          (critical.dy == normal.dy && critical.dx < normal.dx),
      isTrue,
    );

    await tester.tap(find.text('Offline').first);
    await tester.pumpAndSettle();
    expect(find.text('Offline pond'), findsOneWidget);
    expect(find.text('New pond'), findsOneWidget);
    expect(find.text('North pond'), findsNothing);
    expect(find.text('Showing 2 of 5 ponds'), findsOneWidget);

    // Tapping the selected tile again shows everything.
    await tester.tap(find.text('Offline').first);
    await tester.pumpAndSettle();
    expect(find.text('North pond'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No ponds match'), findsOneWidget);
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.text('North pond'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('greets the admin by first name with a pond summary', (
    tester,
  ) async {
    AdminAuthService.ownProfile.value = AdminProfile(
      userId: 'u1',
      fullName: 'Juan dela Cruz',
      firstName: 'Juan',
      lastName: 'dela Cruz',
      email: 'juan@example.com',
      phone: null,
      phoneVerified: true,
      status: AdminStatus.approved,
      createdAt: DateTime(2026),
    );
    addTearDown(() => AdminAuthService.ownProfile.value = null);

    await _pump(tester, 1600, 1000);
    expect(
      find.textContaining(RegExp(r'^Good (morning|afternoon|evening), Juan$')),
      findsOneWidget,
    );
    expect(
      find.text(
        '2 ponds need attention (1 critical, 1 warning) · 2 devices offline.',
      ),
      findsOneWidget,
    );

    await _unmount(tester);
  });
}
