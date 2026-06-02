import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/analyzed_query.dart';
import '../exceptions/analyzer_exception.dart';
import '../utils/logger.dart';
import '../../constants.dart';

/// Defines a destination where alerts can be delivered.
abstract class AlertChannel {
  /// Human-readable name for this channel.
  String get name;

  /// Sends an alert for the given [query].
  Future<void> sendAlert(AnalyzedQuery query);
}

// ── Console ───────────────────────────────────────────────────────────────

/// Prints alerts to stdout — useful for development.
class ConsoleAlertChannel implements AlertChannel {
  @override
  String get name => 'console';

  @override
  Future<void> sendAlert(AnalyzedQuery query) async {
    // ignore: avoid_print
    print(
      '\n⚠️  [QueryAnalyzer SLOW QUERY ALERT]\n'
      '  ID       : ${query.id}\n'
      '  Time     : ${query.executionTimeMs} ms\n'
      '  Impact   : ${query.impactScore}/100\n'
      '  Query    : ${query.originalQuery.length > 100 ? "${query.originalQuery.substring(0, 97)}..." : query.originalQuery}\n'
      '  Issues   : ${query.detectionResult.issues.length}\n'
      '  Top fix  : ${query.suggestions.isNotEmpty ? query.suggestions.first.title : "—"}\n',
    );
  }
}

// ── Logging ───────────────────────────────────────────────────────────────

/// Routes alerts to the package logger as WARNING records.
class LoggingAlertChannel implements AlertChannel {
  @override
  String get name => 'logging';

  @override
  Future<void> sendAlert(AnalyzedQuery query) async {
    QaLogger.warn(
      'ALERT | ${query.executionTimeMs}ms | impact=${query.impactScore} '
      '| ${query.originalQuery.length > 80 ? "${query.originalQuery.substring(0, 77)}..." : query.originalQuery}',
    );
  }
}

// ── Slack ─────────────────────────────────────────────────────────────────

/// Delivers alerts to a Slack incoming webhook.
class SlackAlertChannel implements AlertChannel {
  /// Slack webhook URL (kept secret — never commit this value).
  final String webhookUrl;

  /// Optional channel override (e.g. `#db-alerts`).
  final String? channel;

  /// Creates a [SlackAlertChannel].
  const SlackAlertChannel({required this.webhookUrl, this.channel});

  @override
  String get name => 'slack';

  @override
  Future<void> sendAlert(AnalyzedQuery query) async {
    final payload = _buildPayload(query);
    try {
      final response = await http
          .post(
            Uri.parse(webhookUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(Duration(seconds: kWebhookTimeoutSeconds));

      if (response.statusCode >= 400) {
        throw AlertDeliveryException(
          'Slack webhook returned ${response.statusCode}: ${response.body}',
          channel: name,
        );
      }
    } catch (e, st) {
      QaLogger.error('Failed to deliver Slack alert', e, st);
      if (e is AlertDeliveryException) rethrow;
      throw AlertDeliveryException(
        'HTTP error: $e',
        channel: name,
        cause: e,
        stackTrace: st,
      );
    }
  }

  Map<String, dynamic> _buildPayload(AnalyzedQuery query) {
    final topSuggestion = query.suggestions.isNotEmpty
        ? query.suggestions.first.title
        : 'Review the query manually';

    return {
      if (channel != null) 'channel': channel,
      'text': ':warning: *Query Analyzer — Slow Query Detected*',
      'attachments': [
        {
          'color': '#FF0000',
          'fields': [
            {'title': 'Execution Time', 'value': '${query.executionTimeMs} ms', 'short': true},
            {'title': 'Impact Score', 'value': '${query.impactScore}/100', 'short': true},
            {
              'title': 'Query',
              'value': '```${query.originalQuery.length > 300 ? "${query.originalQuery.substring(0, 297)}..." : query.originalQuery}```',
              'short': false,
            },
            {'title': 'Top Suggestion', 'value': topSuggestion, 'short': false},
          ],
          'footer': 'QueryAnalyzer v1.0.0',
          'ts': query.executedAt.millisecondsSinceEpoch ~/ 1000,
        }
      ],
    };
  }
}

// ── Generic Webhook ───────────────────────────────────────────────────────

/// Posts a JSON payload to any HTTP endpoint.
class WebhookAlertChannel implements AlertChannel {
  /// Target URL.
  final String url;

  /// Custom HTTP headers (e.g. for authorization).
  final Map<String, String> headers;

  @override
  final String name;

  /// Creates a [WebhookAlertChannel].
  const WebhookAlertChannel({
    required this.url,
    this.headers = const {},
    this.name = 'webhook',
  });

  @override
  Future<void> sendAlert(AnalyzedQuery query) async {
    final payload = {
      'event': 'slow_query',
      'timestamp': query.executedAt.toIso8601String(),
      'queryId': query.id,
      'executionTimeMs': query.executionTimeMs,
      'impactScore': query.impactScore,
      'isSlowQuery': query.isSlowQuery,
      'issueCount': query.detectionResult.issues.length,
      'topSuggestion': query.suggestions.isNotEmpty
          ? query.suggestions.first.title
          : null,
      'query': query.originalQuery,
    };

    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              ...headers,
            },
            body: jsonEncode(payload),
          )
          .timeout(Duration(seconds: kWebhookTimeoutSeconds));

      if (response.statusCode >= 400) {
        throw AlertDeliveryException(
          'Webhook [$name] returned ${response.statusCode}',
          channel: name,
        );
      }
    } catch (e, st) {
      QaLogger.error('Failed to deliver webhook alert [$name]', e, st);
      if (e is AlertDeliveryException) rethrow;
      throw AlertDeliveryException(
        'Webhook error: $e',
        channel: name,
        cause: e,
        stackTrace: st,
      );
    }
  }
}
