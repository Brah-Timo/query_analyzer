# query_analyzer Documentation

Welcome to the `query_analyzer` documentation.

---

## Contents

| Document | Description |
|----------|-------------|
| [getting_started.md](getting_started.md) | Installation, minimal setup in 5 minutes. |
| [api_reference.md](api_reference.md) | Complete reference for all public types, methods, and constants. |
| [architecture.md](architecture.md) | Internal architecture, data-flow diagrams, extension points. |
| [configuration.md](configuration.md) | All `QueryAnalyzerConfig` fields with defaults and environment presets. |
| [detectors.md](detectors.md) | Built-in detectors: full-table scan, missing index, N+1, large result, sub-query. |
| [alerts.md](alerts.md) | Real-time alert delivery: Slack, webhooks, console, custom channels. |
| [reporting.md](reporting.md) | Generating and exporting performance reports (JSON, CSV, HTML, Markdown). |
| [integrations.md](integrations.md) | Database adapters: PostgreSQL, MySQL, SQLite, and schema-less mode. |
| [schema_introspection.md](schema_introspection.md) | Schema model, introspection queries, manual definition, caching. |
| [examples.md](examples.md) | 10 complete runnable code examples. |

---

## Quick Navigation

### I want to…

**Get started quickly** → [getting_started.md](getting_started.md)

**Understand the API** → [api_reference.md](api_reference.md)

**Configure the analyzer** → [configuration.md](configuration.md)

**Set up Slack / webhook alerts** → [alerts.md](alerts.md)

**Connect to PostgreSQL / MySQL / SQLite** → [integrations.md](integrations.md)

**Generate an HTML / CSV / JSON report** → [reporting.md](reporting.md)

**Understand what detectors fire and why** → [detectors.md](detectors.md)

**See a complete code example** → [examples.md](examples.md)

**Understand the internals** → [architecture.md](architecture.md)

---

## Package Overview

```
query_analyzer/
├── lib/
│   ├── constants.dart            ← Global constants
│   ├── query_analyzer.dart       ← Public API barrel + QueryAnalyzerFacade
│   └── src/
│       ├── alerts/               ← AlertManager + AlertChannel implementations
│       ├── analyzer/             ← QueryAnalyzerCore, QueryParser, SuggestionEngine, PatternDetector
│       ├── detectors/            ← 5 detector classes
│       ├── exceptions/           ← Package exception hierarchy
│       ├── integration/          ← PostgresAdapter, MySqlAdapter, SQLiteAdapter
│       ├── models/               ← AnalyzedQuery, ParsedQuery, AnalysisReport, …
│       ├── reporting/            ← ReportGenerator, ReportExporter
│       ├── storage/              ← MetricsStorage, LocalDatabase, CacheManager
│       ├── utils/                ← QueryAnalyzerConfig, QaLogger, ParserUtils, PrecisionTimer
│       └── wrapper/              ← DatabaseWrapper, QueryWrapper, ConnectionPoolWrapper
├── test/
│   ├── fixtures/                 ← Shared test helpers
│   ├── integration/              ← End-to-end tests
│   └── unit/                     ← Unit tests
├── example/                      ← Runnable examples
└── doc/                          ← This documentation
```

---

## Version

Current package version: **1.0.0**

Repository: [https://github.com/Brah-Timo/packages](https://github.com/Brah-Timo/packages)
