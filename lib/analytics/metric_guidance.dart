import 'metric_type.dart';

/// Ported from the farmer app (IsdaSafeV2 `models/metric_guidance.dart`), so
/// the admin sees the same advice the farmer is given.
///
/// What to do about [value] of [type] when it's outside the healthy band, or
/// null when it's fine.
String? guidanceFor(MetricType type, double value) {
  final bands = metricBands[type]!;
  final low = bands.warningLow != null && value < bands.warningLow!;
  final high = bands.warningHigh != null && value > bands.warningHigh!;
  if (!low && !high) return null;

  return switch ((type, high)) {
    (MetricType.temperature, true) =>
      'The water is too warm. Shade the pond or add cooler water, run aeration (warm water holds less oxygen), and feed less until it cools down.',
    (MetricType.temperature, false) =>
      'The water is too cold, so fish eat and grow slowly. Feed less, and avoid large water changes with cold water.',
    // Humidity has no limits of its own.
    (MetricType.humidity, _) => null,
    (MetricType.ammonia, _) =>
      'Ammonia is building up. Stop or cut back feeding, change part of the water, and remove uneaten feed and dead fish.',
    (MetricType.dissolvedOxygen, _) =>
      'Oxygen is low. Turn on aerators or add fresh water now, stop feeding until it recovers, and check again at dawn, when it is lowest.',
    (MetricType.ph, false) =>
      'The water is too acidic. Apply agricultural lime and check the pH again after a few hours.',
    (MetricType.ph, true) =>
      'The water is too alkaline, which makes ammonia more toxic. Change part of the water and don\'t add lime.',
    (MetricType.airTemperature, true) =>
      'Hot air will warm the pond. Shade it and keep an eye on the water temperature and oxygen.',
    (MetricType.airTemperature, false) =>
      'Cool air will chill the pond. Feed less until it warms up.',
    (MetricType.freeAmmonia, _) =>
      'Toxic ammonia is high. Stop feeding, change part of the water and aerate. Bringing the pH and water temperature down also lowers it.',
  };
}
