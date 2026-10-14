import '../models/monitored_pond.dart';
import 'metric_type.dart';

/// The pond's latest reading per metric, as the charts' [SensorReading]s.
Map<MetricType, SensorReading> latestReadings(MonitoredPond pond) {
  final at = pond.readingAt;
  if (at == null) return const {};
  final values = <MetricType, double?>{
    MetricType.temperature: pond.readings[WaterMetric.temperature],
    MetricType.humidity: pond.humidity,
    MetricType.freeAmmonia: pond.readings[WaterMetric.freeAmmonia],
    MetricType.dissolvedOxygen: pond.readings[WaterMetric.dissolvedOxygen],
    MetricType.ph: pond.readings[WaterMetric.ph],
    MetricType.airTemperature: pond.airTemperature,
    MetricType.ammonia: pond.ammonia,
  };
  return {
    for (final MapEntry(:key, :value) in values.entries)
      if (value != null)
        key: SensorReading(type: key, value: value, timestamp: at),
  };
}
