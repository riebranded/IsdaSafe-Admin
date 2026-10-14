import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/monitored_pond.dart';

class MonitoringRepository {
  const MonitoringRepository._();

  /// Every pond with a paired device and its latest reading. Throws for an
  /// account that isn't an approved admin.
  static Future<List<MonitoredPond>> fetchMonitoredPonds() async {
    final rows =
        await Supabase.instance.client.rpc('admin_monitored_ponds')
            as List<dynamic>;
    return [
      for (final row in rows)
        MonitoredPond.fromRow(row as Map<String, dynamic>),
    ];
  }
}
