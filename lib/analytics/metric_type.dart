import 'package:flutter/material.dart';

import '../models/monitored_pond.dart';

// Ported from the farmer app (IsdaSafeV2 `models/metric_type.dart`,
// `models/reading_bands.dart`, `models/sensor_reading.dart` and its
// `MetricPalette`) so the admin's pond charts read exactly like the farmer's.

enum MetricType {
  temperature,
  humidity,
  ammonia,
  dissolvedOxygen,
  ph,

  /// Air temperature around the device (the firmware's `AirT`). Shown with
  /// [humidity]; not one of the pond's [primary] water metrics.
  airTemperature,

  /// Un-ionised (free) ammonia, NH3: the toxic part of [ammonia], worked out
  /// from it, pH and water temperature (see `free_ammonia.dart`). It's the
  /// ammonia the pond shows ([primary]) and judges ([water]).
  freeAmmonia;

  /// The pond's five main readings: the reading cards and trend charts.
  /// Ammonia is shown as [freeAmmonia], the part that's toxic to fish. The
  /// others (air temperature, total [ammonia]) are shown alongside one of
  /// these (see [MetricTypeInfo.companions]).
  static const primary = [
    temperature,
    humidity,
    freeAmmonia,
    dissolvedOxygen,
    ph,
  ];

  /// The water readings: these alone decide the pond's status and alerts.
  /// Ammonia counts as [freeAmmonia], the part that's toxic to fish, not the
  /// total [ammonia]. [humidity] and [airTemperature] describe the weather,
  /// which only matters through what it does to these (see
  /// `weather_context.dart`).
  static const water = [temperature, freeAmmonia, dissolvedOxygen, ph];
}

extension MetricTypeInfo on MetricType {
  String get label => switch (this) {
    MetricType.temperature => 'Water Temperature',
    MetricType.humidity => 'Humidity',
    MetricType.ammonia => 'Ammonia',
    MetricType.dissolvedOxygen => 'Dissolved Oxygen',
    MetricType.ph => 'pH Level',
    MetricType.airTemperature => 'Air Temperature',
    MetricType.freeAmmonia => 'Free Ammonia',
  };

  String get unit => switch (this) {
    MetricType.temperature || MetricType.airTemperature => '°C',
    MetricType.humidity => '%',
    MetricType.ammonia ||
    MetricType.dissolvedOxygen ||
    MetricType.freeAmmonia => 'mg/L',
    MetricType.ph => '',
  };

  IconData get icon => switch (this) {
    MetricType.temperature => Icons.thermostat,
    MetricType.humidity => Icons.water_drop,
    MetricType.ammonia => Icons.science,
    MetricType.dissolvedOxygen => Icons.bubble_chart,
    MetricType.ph => Icons.opacity,
    MetricType.airTemperature => Icons.air,
    MetricType.freeAmmonia => Icons.warning_amber_rounded,
  };

  /// What the reading is and why it matters to the fish, for the metric's
  /// detail view.
  String get description => switch (this) {
    MetricType.temperature =>
      'How warm the pond water is. Fish are cold-blooded, so it sets how fast they eat, grow and use oxygen. Warm water holds less oxygen and makes ammonia more toxic.',
    MetricType.humidity =>
      "How much moisture is in the air around the device. It doesn't affect the fish directly, so it never changes the pond's status on its own. IsdaSafe reads it with the air and water temperature to warn about weather that changes the water: muggy nights that lower oxygen, air that keeps the pond warm, dry heat that evaporates it, and rain that lowers the pH.",
    MetricType.ammonia =>
      'Total ammonia nitrogen dissolved in the water, from fish waste and uneaten feed. It rises when the pond is overstocked or overfed and builds up when water isn\'t exchanged.',
    MetricType.dissolvedOxygen =>
      'How much oxygen is dissolved in the water for the fish to breathe. It drops at night, in hot weather and after overfeeding; low levels stress fish and can kill them.',
    MetricType.ph =>
      'How acidic or alkaline the water is. Most pond fish do best near neutral. pH swings during the day with algae, and a high pH makes ammonia far more toxic.',
    MetricType.airTemperature =>
      'How warm the air is around the device. It drives the water temperature: hot air warms the pond within hours.',
    MetricType.freeAmmonia =>
      'The toxic part of the ammonia (un-ionised NH3), calculated from the total ammonia, pH and water temperature. Even small amounts damage the gills; it rises sharply when the water is warm or the pH is high.',
  };

  /// Readings shown together with this one in its detail view.
  List<MetricType> get companions => switch (this) {
    MetricType.humidity => const [MetricType.airTemperature],
    MetricType.freeAmmonia => const [MetricType.ammonia],
    MetricType.ammonia => const [MetricType.freeAmmonia],
    _ => const [],
  };

  /// Numeric-only rendering, e.g. "27.4" — no unit, for space-constrained UI
  /// like per-point chart labels. [format] is the full display form.
  String formatValue(double value) => value.toStringAsFixed(switch (this) {
    MetricType.freeAmmonia => 3,
    MetricType.ammonia => 2,
    _ => 1,
  });

  /// Formats [value] the way it should be displayed, e.g. "27.4°C" or "6.8".
  String format(double value) {
    final formatted = formatValue(value);
    return unit.isEmpty ? formatted : '$formatted$unit';
  }
}

class SensorReading {
  const SensorReading({
    required this.type,
    required this.value,
    required this.timestamp,
  });

  final MetricType type;
  final double value;
  final DateTime timestamp;
}

/// Per-metric pond-health bands — independent from, and wider than, any
/// single fish species' optimal range. These answer "is this pond healthy
/// overall", while the AI species recommendation answers "which fish fit it".
class MetricBands {
  const MetricBands({
    this.criticalLow,
    this.warningLow,
    this.warningHigh,
    this.criticalHigh,
    required this.displayMin,
    required this.displayMax,
  });

  /// Null when this metric has no meaningful lower/upper bound (e.g.
  /// ammonia is only ever a problem when too *high*).
  final double? criticalLow;
  final double? warningLow;
  final double? warningHigh;
  final double? criticalHigh;

  /// Range used by [positionOf] to place a marker on a range bar — wider
  /// than the critical bounds so the marker never sits flush at the edge.
  final double displayMin;
  final double displayMax;

  ReadingStatus statusFor(double value) {
    final lo = criticalLow, hi = criticalHigh;
    if ((lo != null && value < lo) || (hi != null && value > hi)) {
      return ReadingStatus.critical;
    }
    final warnLo = warningLow, warnHi = warningHigh;
    if ((warnLo != null && value < warnLo) ||
        (warnHi != null && value > warnHi)) {
      return ReadingStatus.warning;
    }
    return ReadingStatus.normal;
  }

  /// Value's position within [displayMin]..[displayMax], clamped to 0..1.
  double positionOf(double value) {
    return ((value - displayMin) / (displayMax - displayMin)).clamp(0.0, 1.0);
  }

  /// 0 = safely inside the normal band, 1 = at/beyond the critical
  /// threshold, on either side — direction-agnostic so "rising" always
  /// means "toward trouble," unlike [positionOf] (which just reflects
  /// display-range position and reads backwards for metrics where high is
  /// good, e.g. dissolved oxygen). Used to put every metric on one shared,
  /// comparable axis for cross-metric status logic (e.g. [overallStatus]).
  double riskOf(double value) {
    final safeLo = warningLow ?? displayMin;
    final safeHi = warningHigh ?? displayMax;

    if (value < safeLo) {
      final critLo = criticalLow ?? displayMin;
      if (safeLo == critLo) return 1.0;
      return ((safeLo - value) / (safeLo - critLo)).clamp(0.0, 1.0);
    }
    if (value > safeHi) {
      final critHi = criticalHigh ?? displayMax;
      if (safeHi == critHi) return 1.0;
      return ((value - safeHi) / (critHi - safeHi)).clamp(0.0, 1.0);
    }
    return 0.0;
  }
}

const Map<MetricType, MetricBands> metricBands = {
  MetricType.temperature: MetricBands(
    criticalLow: 22,
    warningLow: 25,
    warningHigh: 29,
    criticalHigh: 32,
    displayMin: 18,
    displayMax: 36,
  ),
  // Weather, not water: no limits of its own (tropical air is often 85%+).
  // It matters through `weatherInsights`, which judge it together with the
  // water readings.
  MetricType.humidity: MetricBands(displayMin: 30, displayMax: 100),
  MetricType.ammonia: MetricBands(
    warningHigh: 0.05,
    criticalHigh: 0.15,
    displayMin: 0,
    displayMax: 0.3,
  ),
  MetricType.dissolvedOxygen: MetricBands(
    warningLow: 4,
    criticalLow: 2,
    displayMin: 0,
    displayMax: 9,
  ),
  MetricType.ph: MetricBands(
    criticalLow: 6.0,
    warningLow: 6.5,
    warningHigh: 8.5,
    criticalHigh: 9.0,
    displayMin: 4.5,
    displayMax: 10.5,
  ),
  // Air around the device; comfortable for tropical ponds in between.
  MetricType.airTemperature: MetricBands(
    criticalLow: 18,
    warningLow: 22,
    warningHigh: 33,
    criticalHigh: 37,
    displayMin: 15,
    displayMax: 42,
  ),
  // Un-ionised NH3: harmful to most farmed fish above ~0.05 mg/L.
  MetricType.freeAmmonia: MetricBands(
    warningHigh: 0.02,
    criticalHigh: 0.05,
    displayMin: 0,
    displayMax: 0.1,
  ),
};

/// Each metric's chart color — the farmer app's `MetricPalette`, light and
/// dark.
Color metricColor(BuildContext context, MetricType type) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return Color(switch (type) {
    MetricType.temperature => dark ? 0xFF3987E5 : 0xFF2A78D6,
    MetricType.humidity => dark ? 0xFFD95926 : 0xFFEB6834,
    MetricType.ammonia => dark ? 0xFF199E70 : 0xFF1BAF7A,
    MetricType.dissolvedOxygen => dark ? 0xFFC98500 : 0xFFEDA100,
    MetricType.ph => dark ? 0xFFD55181 : 0xFFE87BA4,
    MetricType.airTemperature => dark ? 0xFF9C86E0 : 0xFF7B61C8,
    MetricType.freeAmmonia => dark ? 0xFFB98552 : 0xFF8A5A2B,
  });
}
