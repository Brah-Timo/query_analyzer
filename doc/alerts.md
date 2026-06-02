# Alerts & Webhooks

`query_analyzer` delivers real-time alerts when queries cross configured
performance thresholds.  The alert system is built on the `QueryListener`
interface and is fully extensible.

---

## Quick Setup

```dart
import 'package:query_analyzer/query_analyzer.dart';

final core = QueryAnalyzerFacade.create(
  config: QueryAnalyzerConfig.custom(slowQueryThresholdMs: 500),
);

// Add an AlertManager with a Slack channel
core.addListener(
  AlertManager(
    channels: [
      SlackAlertChannel(webhookUrl: 'https://hooks.slack.com/…'),
      ConsoleAlertChannel(),
    ],
    thresholds: const ThresholdConfig(
      slowQueryMs: 500,
      alertCooldown: Duration(minutes: 5),
    ),
  ),
);
```

---

## AlertManager

`AlertManager` implements `QueryListener` and is the central dispatcher.
It receives every analyzed query and decides whether to deliver an alert
based on `ThresholdConfig` rules.

```dart
class AlertManager implements QueryListener {
  AlertManager({
    required List<AlertChannel> channels,
    ThresholdConfig thresholds = const ThresholdConfig(),
  });
}
```

### Alert conditions

Currently an alert is dispatched when:

1. `query.isSlowQuery == true` (execution time ≥ `thresholds.slowQueryMs`), OR
2. `query.detectionResult.hasIssues == true`

### Cooldown

Each channel tracks the timestamp of its last successful delivery.  A
channel that sent an alert less than `thresholds.alertCooldown` ago is
skipped for subsequent alerts.  This prevents alert storms during database
degradation events.

---

## Built-in Channels

### ConsoleAlertChannel

Prints a formatted alert to `stdout`.  Best for development.

```dart
ConsoleAlertChannel()
```

Output example:
```
⚠️  [QueryAnalyzer SLOW QUERY ALERT]
  ID       : a1b2c3d4-…
  Time     : 1423 ms
  Impact   : 72/100
  Query    : SELECT * FROM orders WHERE created_at > '2025-01-01'
  Issues   : 3
  Top fix  : Add index on orders(created_at)
```

---

### LoggingAlertChannel

Routes alerts through the package logger at `WARNING` level.
Integrates with any Dart logging handler (file, Stackdriver, etc.).

```dart
LoggingAlertChannel()

// Enable console output for the logger:
QaLogger.enableConsoleOutput();
```

---

### SlackAlertChannel

Posts a rich message to a Slack incoming webhook.

```dart
SlackAlertChannel(
  webhookUrl: 'https://hooks.slack.com/services/T…/B…/…',
  channel: '#db-alerts',   // optional — overrides the webhook default
)
```

The payload includes execution time, impact score, the query snippet, and
the top suggestion.

**Security note:** Never commit the `webhookUrl` to version control.  Use
environment variables:

```dart
SlackAlertChannel(webhookUrl: Platform.environment['SLACK_WEBHOOK_URL']!)
```

---

### WebhookAlertChannel

Posts a JSON payload to any HTTP endpoint.

```dart
WebhookAlertChannel(
  url: 'https://my-monitoring.example.com/api/query-alerts',
  headers: {
    'Authorization': 'Bearer ${Platform.environment["MONITOR_TOKEN"]!}',
  },
  name: 'monitoring',
)
```

JSON payload shape:

```json
{
  "event": "slow_query",
  "timestamp": "2025-06-01T10:23:45.000Z",
  "queryId": "a1b2c3d4-…",
  "executionTimeMs": 1423,
  "impactScore": 72,
  "isSlowQuery": true,
  "issueCount": 3,
  "topSuggestion": "Add index on orders(created_at)",
  "query": "SELECT * FROM orders WHERE created_at > ?"
}
```

Both `SlackAlertChannel` and `WebhookAlertChannel` respect a
`kWebhookTimeoutSeconds` (10 s) HTTP timeout and throw
`AlertDeliveryException` on HTTP 4xx / 5xx responses.

---

## ThresholdConfig

Controls when `AlertManager` dispatches alerts.

```dart
const ThresholdConfig({
  int slowQueryMs = 1000,
  double slowQueryRatePercent = 10.0,
  double errorRatePercent = 5.0,
  Duration rollingWindow = const Duration(minutes: 5),
  Duration alertCooldown = const Duration(minutes: 15),
});
```

| Field | Description |
|-------|-------------|
| `slowQueryMs` | Queries above this threshold trigger an alert. |
| `slowQueryRatePercent` | If ≥ this percent of queries are slow in the rolling window, fire a rate alert. *(Future feature)* |
| `errorRatePercent` | Error-rate threshold. *(Future feature)* |
| `rollingWindow` | Window used for rate calculations. |
| `alertCooldown` | Minimum time between two alerts on the same channel. |

### Pre-built presets

```dart
ThresholdConfig.production   // default values above
ThresholdConfig.development  // slowQueryMs: 5000, cooldown: 30s
```

---

## Custom Alert Channels

Implement the two-method `AlertChannel` interface:

```dart
abstract class AlertChannel {
  String get name;
  Future<void> sendAlert(AnalyzedQuery query);
}
```

Example — PagerDuty integration:

```dart
class PagerDutyChannel implements AlertChannel {
  final String routingKey;
  PagerDutyChannel({required this.routingKey});

  @override
  String get name => 'pagerduty';

  @override
  Future<void> sendAlert(AnalyzedQuery query) async {
    if (query.impactScore < 80) return;  // only critical queries

    await http.post(
      Uri.parse('https://events.pagerduty.com/v2/enqueue'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'routing_key': routingKey,
        'event_action': 'trigger',
        'payload': {
          'summary': 'Slow query: ${query.executionTimeMs}ms',
          'severity': 'critical',
          'custom_details': query.toJson(),
        },
      }),
    );
  }
}
```

---

## Stream-Based Alerting

For maximum flexibility, subscribe to `QueryAnalyzerCore.slowQueryStream`:

```dart
core.slowQueryStream.listen((query) {
  myTelemetry.record(
    metric: 'db.slow_query',
    value: query.executionTimeMs,
    tags: {'table': query.parsed.tables.firstOrNull ?? 'unknown'},
  );
});
```

Or to all queries:

```dart
core.queryStream.listen((query) {
  if (query.impactScore > 50) {
    myDashboard.addDataPoint(query);
  }
});
```

---

## Managing Channels at Runtime

```dart
final manager = AlertManager(channels: [ConsoleAlertChannel()]);

// Add a channel at runtime
manager.addChannel(
  SlackAlertChannel(webhookUrl: '…'),
);

// Remove a channel
manager.removeChannel('console');

// List active channels
print(manager.channelNames);  // ['slack']
```

---

## Error Handling

If a channel throws an exception, `AlertManager` catches it, logs an error
via `QaLogger`, and continues delivering to remaining channels.  A single
failing channel never blocks the others.

```
AlertManager: channel "slack" failed to deliver alert
  AlertDeliveryException[slack]: HTTP error: SocketException: …
```
