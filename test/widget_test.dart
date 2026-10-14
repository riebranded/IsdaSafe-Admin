import 'package:flutter_test/flutter_test.dart';

import 'package:isdasafe_admin/models/monitored_pond.dart';

void main() {
  group('WaterMetric.statusFor', () {
    test('matches the farmer app bands', () {
      expect(WaterMetric.ph.statusFor(7.2), ReadingStatus.normal);
      expect(WaterMetric.ph.statusFor(6.3), ReadingStatus.warning);
      expect(WaterMetric.ph.statusFor(9.5), ReadingStatus.critical);
      expect(WaterMetric.dissolvedOxygen.statusFor(3), ReadingStatus.warning);
      expect(WaterMetric.freeAmmonia.statusFor(0.06), ReadingStatus.critical);
    });
  });

  group('MonitoredPond', () {
    Map<String, dynamic> row({String? lastSeen, double? ph}) => {
      'pond_id': 'p1',
      'pond_name': 'Pond',
      'device_id': 'ABC',
      'species_names': ['Tilapia'],
      'last_seen_at': lastSeen,
      'ph': ph,
    };

    test('connection follows last upload', () {
      final now = DateTime.now();
      final online = MonitoredPond.fromRow(
        row(
          lastSeen: now
              .subtract(const Duration(minutes: 1))
              .toUtc()
              .toIso8601String(),
        ),
      );
      final offline = MonitoredPond.fromRow(
        row(
          lastSeen: now
              .subtract(const Duration(minutes: 10))
              .toUtc()
              .toIso8601String(),
        ),
      );
      expect(online.connection(now), DeviceConnection.online);
      expect(offline.connection(now), DeviceConnection.offline);
      expect(
        MonitoredPond.fromRow(row()).connection(now),
        DeviceConnection.neverConnected,
      );
    });

    test('status is the worst water reading, null without readings', () {
      expect(MonitoredPond.fromRow(row()).status, isNull);
      expect(
        MonitoredPond.fromRow(row(ph: 9.5)).status,
        ReadingStatus.critical,
      );
    });
  });
}
