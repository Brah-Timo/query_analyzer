import 'package:meta/meta.dart';

/// Configures the thresholds that trigger alert delivery.
@immutable
class ThresholdConfig {
  /// Queries slower than this (ms) fire a slow-query alert.
  final int slowQueryMs;

  /// If the slow-query rate (percent) exceeds this in a rolling window,
  /// a rate alert is fired.
  final double slowQueryRatePercent;

  /// If the error rate (percent) exceeds this in a rolling window, an
  /// error-rate alert is fired.
  final double errorRatePercent;

  /// Rolling window duration used for rate calculations.
  final Duration rollingWindow;

  /// Minimum time between two alerts of the same type (debounce).
  final Duration alertCooldown;

  /// Creates a [ThresholdConfig].
  const ThresholdConfig({
    this.slowQueryMs = 1000,
    this.slowQueryRatePercent = 10.0,
    this.errorRatePercent = 5.0,
    this.rollingWindow = const Duration(minutes: 5),
    this.alertCooldown = const Duration(minutes: 15),
  });

  /// Default production-ready thresholds.
  static const ThresholdConfig production = ThresholdConfig();

  /// Relaxed thresholds for development environments.
  static const ThresholdConfig development = ThresholdConfig(
    slowQueryMs: 5000,
    slowQueryRatePercent: 50,
    errorRatePercent: 20,
    alertCooldown: Duration(seconds: 30),
  );
}
