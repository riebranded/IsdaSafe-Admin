import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:isdasafe_admin/screens/dashboard_screen.dart';
import 'package:isdasafe_admin/theme/app_theme.dart';
import 'package:isdasafe_admin/widgets/app_tour.dart';

void main() {
  // The dashboard's tabs call Supabase as they build. Initialize it with
  // throwaway credentials so those calls fail fast (no session, nothing
  // listening) instead of asserting it was never initialized.
  setUpAll(() async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      (call) async => call.method == 'getAll' ? <String, Object>{} : null,
    );
    await Supabase.initialize(
      url: 'http://localhost',
      publishableKey: 'test-key',
    );
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => AppTour.autoStartEnabled = true);

  Future<void> pumpDashboard(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const DashboardScreen()),
    );
    // Past the tour's start-up delay.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  /// Disposes the dashboard so its refresh timers stop with the test.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  /// Presses Next (Finish on the last step) until the tour closes,
  /// returning how many steps were shown.
  Future<int> runThrough(WidgetTester tester) async {
    var steps = 0;
    while (find.byKey(const ValueKey('tour-next')).evaluate().isNotEmpty) {
      steps++;
      await tester.tap(find.byKey(const ValueKey('tour-next')));
      await tester.pumpAndSettle();
    }
    return steps;
  }

  testWidgets(
    'the tour starts on first sign-in, visits every tab and is not shown again',
    (tester) async {
      await pumpDashboard(tester, const Size(1366, 768));

      expect(find.text('Welcome to the Isda Safe admin panel'), findsOneWidget);
      expect(find.text('1 of 9'), findsOneWidget);
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(const ValueKey('tour-next')));
        await tester.pumpAndSettle();
      }
      expect(find.text('5 of 9'), findsOneWidget);
      expect(
        find.textContaining('Every device IsdaSafe knows'),
        findsOneWidget,
      );

      expect(await runThrough(tester), 5);
      expect(AppTour.isShowing, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('admin_tour_seen_v1'), isTrue);
      expect(await AppTour.shouldAutoStart(), isFalse);
      await unmount(tester);
    },
  );

  testWidgets('Settings → Help → Tutorial replays the tour on a phone', (
    tester,
  ) async {
    AppTour.autoStartEnabled = false;
    await pumpDashboard(tester, const Size(390, 844));
    expect(AppTour.isShowing, isFalse);

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    final tile = find.byKey(const ValueKey('settings-tutorial'));
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(find.text('Welcome to the Isda Safe admin panel'), findsOneWidget);
    expect(await runThrough(tester), 9);
    expect(AppTour.isShowing, isFalse);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('tapping the sidebar logo goes back to Monitoring', (
    tester,
  ) async {
    AppTour.autoStartEnabled = false;
    await pumpDashboard(tester, const Size(1366, 768));

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Tutorial'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('brand-home')));
    await tester.pumpAndSettle();
    // Settings is still mounted (IndexedStack) but no longer on screen.
    expect(find.text('Tutorial'), findsNothing);
    expect(find.text('Tutorial', skipOffstage: false), findsOneWidget);

    // Collapsed, the logo alone still goes home.
    await tester.tap(find.byTooltip('Collapse sidebar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('brand-home')));
    await tester.pumpAndSettle();
    expect(find.text('Tutorial'), findsNothing);
    await unmount(tester);
  });
}
