import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// DSN injected at build/run time via `--dart-define=SENTRY_DSN=...`.
/// Kept out of source so the credential never lands in git.
const String _dsn = String.fromEnvironment('SENTRY_DSN');

/// Optional environment override, e.g. `--dart-define=SENTRY_ENV=staging`.
/// Falls back to release/debug detection.
const String _envOverride = String.fromEnvironment('SENTRY_ENV');

bool get sentryEnabled => _dsn.isNotEmpty;

String get _environment {
  if (_envOverride.isNotEmpty) return _envOverride;
  return kReleaseMode ? 'production' : 'development';
}

/// Applies the shared Sentry options. Called from [SentryFlutter.init].
void configureSentry(SentryFlutterOptions options) {
  options.dsn = _dsn;
  options.environment = _environment;

  // Structured logs (Sentry.logger.*). Visible under "Logs" in the dashboard.
  options.enableLogs = true;

  // TEMP debug: proves a log actually reaches the capture pipeline.
  // If this never prints, enableLogs isn't active in the running build.
  // Return the log unchanged so it's still sent. Remove once logs are verified.
  if (!kReleaseMode) {
    options.beforeSendLog = (log) {
      debugPrint('[SentryLog] captured: level=${log.level} body="${log.body}"');
      return log;
    };
  }

  // Performance tracing. Lower in production to control event volume.
  options.tracesSampleRate = kReleaseMode ? 0.2 : 1.0;

  // Attach useful context automatically.
  options.attachScreenshot = true;
  options.sendDefaultPii = false; // never ship customer PII

  // Don't spam Sentry while developing locally.
  options.debug = !kReleaseMode;
}
