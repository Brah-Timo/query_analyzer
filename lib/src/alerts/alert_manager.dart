import '../analyzer/query_analyzer_core.dart';
import '../models/analyzed_query.dart';
import '../utils/logger.dart';
import 'alert_channels.dart';
import 'threshold_config.dart';

/// Listens to [QueryAnalyzerCore] events and dispatches alerts to configured
/// [AlertChannel]s according to [ThresholdConfig] rules.
class AlertManager implements QueryListener {
  final List<AlertChannel> _channels;
  final ThresholdConfig _thresholds;

  /// Timestamps of the last alert sent per channel name (for cooldown).
  final Map<String, DateTime> _lastAlertAt = {};

  /// Creates an [AlertManager].
  AlertManager({
    required List<AlertChannel> channels,
    ThresholdConfig thresholds = const ThresholdConfig(),
  })  : _channels = channels,
        _thresholds = thresholds;

  // ── QueryListener ─────────────────────────────────────────────────────────

  @override
  Future<void> onQueryAnalyzed(AnalyzedQuery query) async {
    if (!_shouldAlert(query)) return;

    QaLogger.debug(
      'AlertManager: dispatching alert for query ${query.id} '
      '(${query.executionTimeMs}ms) to ${_channels.length} channel(s)',
    );

    await Future.wait(
      _channels.map((ch) => _deliverSafely(ch, query)),
    );
  }

  // ── Private ───────────────────────────────────────────────────────────────

  bool _shouldAlert(AnalyzedQuery query) {
    if (!query.isSlowQuery && !query.detectionResult.hasIssues) return false;
    return true;
  }

  Future<void> _deliverSafely(AlertChannel channel, AnalyzedQuery query) async {
    // Cooldown check
    final lastSent = _lastAlertAt[channel.name];
    if (lastSent != null &&
        DateTime.now().difference(lastSent) < _thresholds.alertCooldown) {
      QaLogger.debug(
        'AlertManager: channel "${channel.name}" in cooldown — skipping.',
      );
      return;
    }

    try {
      await channel.sendAlert(query);
      _lastAlertAt[channel.name] = DateTime.now();
    } catch (e, st) {
      QaLogger.error(
        'AlertManager: channel "${channel.name}" failed to deliver alert',
        e,
        st,
      );
    }
  }

  /// Adds a new [AlertChannel] at runtime.
  void addChannel(AlertChannel channel) => _channels.add(channel);

  /// Removes an [AlertChannel] by name.
  void removeChannel(String channelName) =>
      _channels.removeWhere((c) => c.name == channelName);

  /// Returns the current list of channel names.
  List<String> get channelNames =>
      _channels.map((c) => c.name).toList();
}
