import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'kiosk_bridge.dart';
import 'device_info_page.dart';
import 'sentry_config.dart';

Future<void> main() async {
  if (!sentryEnabled) {
    // No DSN provided — run the app normally without Sentry.
    runApp(const MdmTestApp());
    return;
  }

  await SentryFlutter.init(
    configureSentry,
    appRunner: () => runApp(SentryWidget(child: const MdmTestApp())),
  );

  // TEMP: verify Sentry transport works. Remove after confirming on dashboard.
  // await Sentry.captureMessage('Sentry smoke test from mdm_test_app');
}

class MdmTestApp extends StatelessWidget {
  const MdmTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MDM Sandbox',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _launchReason = '...';
  bool _isDeviceOwner = false;
  bool _isAdminActive = false;
  String _versionName = '...';
  String _versionCode = '...';
  Map<String, String> _managedConfig = {};
  String _log = '';
  bool _loading = true;
  StreamSubscription<Map<String, dynamic>>? _eventSub;
  final _pkgController = TextEditingController(text: 'com.mdm.test');
  final _logController = TextEditingController(text: 'MDM sandbox test log');
  SentryLogLevel _logLevel = SentryLogLevel.info;

  @override
  void initState() {
    super.initState();
    _loadStatus();
    _listenMdmEvents();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _pkgController.dispose();
    _logController.dispose();
    super.dispose();
  }

  void _listenMdmEvents() {
    _eventSub = KioskBridge.mdmEventStream.listen(
      (event) {
        final type = event['event'] as String?;
        switch (type) {
          case 'managed_config_changed':
            final config = Map<String, String>.from(event['config'] as Map? ?? {});
            setState(() => _managedConfig = config);
            _appendLog('MDM config changed: $config');
          case 'launch_reason_changed':
            final reason = event['reason'] as String? ?? 'unknown';
            setState(() => _launchReason = reason);
            _appendLog('Launch reason updated: $reason');
          case 'mdm_command':
            _handleMdmCommand(event);
        }
      },
      onError: (e, st) {
        _appendLog('EventChannel error: $e');
        _report(e, st);
      },
    );
  }

  Future<void> _loadStatus() async {
    setState(() => _loading = true);
    try {
      final reason = await KioskBridge.getLaunchReason();
      final owner = await KioskBridge.isDeviceOwner();
      final admin = await KioskBridge.isAdminActive();
      final ver = await KioskBridge.getAppVersion();
      final config = await KioskBridge.getManagedConfig();
      setState(() {
        _launchReason = reason;
        _isDeviceOwner = owner;
        _isAdminActive = admin;
        _versionName = ver['versionName'] ?? '?';
        _versionCode = ver['versionCode'] ?? '?';
        _managedConfig = config;
        _loading = false;
      });
    } catch (e, st) {
      _appendLog('Error loading status: $e');
      _report(e, st);
      setState(() => _loading = false);
    }
  }

  /// Reports a caught error to Sentry (no-op when DSN is not configured).
  void _report(Object error, [StackTrace? stack]) {
    if (!sentryEnabled) return;
    unawaited(Sentry.captureException(error, stackTrace: stack));
  }

  /// Sends a structured log to Sentry at the selected level.
  /// Requires `enableLogs = true` (see sentry_config.dart) and a configured DSN.
  Future<void> _sendLogToSentry() async {
    final msg = _logController.text.trim();
    if (msg.isEmpty) return;
    if (!sentryEnabled) {
      _appendLog('Sentry disabled (no DSN) — log not sent');
      return;
    }

    final attributes = {
      'source': SentryAttribute.string('mdm_sandbox_ui'),
      'launch_reason': SentryAttribute.string(_launchReason),
      'is_device_owner': SentryAttribute.bool(_isDeviceOwner),
    };

    switch (_logLevel) {
      case SentryLogLevel.trace:
        Sentry.logger.trace(msg, attributes: attributes);
      case SentryLogLevel.debug:
        Sentry.logger.debug(msg, attributes: attributes);
      case SentryLogLevel.info:
        Sentry.logger.info(msg, attributes: attributes);
      case SentryLogLevel.warn:
        Sentry.logger.warn(msg, attributes: attributes);
      case SentryLogLevel.error:
        Sentry.logger.error(msg, attributes: attributes);
      case SentryLogLevel.fatal:
        Sentry.logger.fatal(msg, attributes: attributes);
    }

    _appendLog('Sent ${_logLevel.name} log to Sentry: "$msg"');
  }

  void _appendLog(String msg) {
    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    setState(() => _log = '[$ts] $msg\n$_log');
  }

  Future<void> _testLaunchApp() async {
    final pkg = _pkgController.text.trim();
    if (pkg.isEmpty) return;
    try {
      await KioskBridge.launchApp(pkg);
      _appendLog('launch_app OK: $pkg');
    } catch (e, st) {
      _appendLog('launch_app FAILED: $e');
      _report(e, st);
    }
  }

  Future<void> _handleMdmCommand(Map<String, dynamic> event) async {
    final action = event['action'] as String?;
    final config = Map<String, String>.from(event['config'] as Map? ?? {});
    setState(() => _managedConfig = config);
    _appendLog('MDM command received: action=$action | config=$config');
    switch (action) {
      case 'launch_app':
        final pkg = config['target_package'];
        if (pkg != null && pkg.isNotEmpty) {
          try {
            await KioskBridge.launchApp(pkg);
            _appendLog('launch_app: started $pkg');
          } catch (e, st) {
            _appendLog('launch_app FAILED: $e');
            _report(e, st);
          }
        } else {
          _appendLog('launch_app: missing target_package');
        }
    }
  }

  Future<void> _enterKiosk() async {
    try {
      await KioskBridge.enterKiosk();
      _appendLog('enterKiosk OK');
    } catch (e, st) {
      _appendLog('enterKiosk FAILED: $e');
      _report(e, st);
    }
  }

  Future<void> _exitKiosk() async {
    try {
      await KioskBridge.exitKiosk();
      _appendLog('exitKiosk OK');
    } catch (e, st) {
      _appendLog('exitKiosk FAILED: $e');
      _report(e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MDM Sandbox App'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadStatus),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DeviceInfoPage()),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatusCard(
                    launchReason: _launchReason,
                    isDeviceOwner: _isDeviceOwner,
                    isAdminActive: _isAdminActive,
                    versionName: _versionName,
                    versionCode: _versionCode,
                  ),
                  const SizedBox(height: 8),
                  _ManagedConfigCard(config: _managedConfig),
                  const SizedBox(height: 8),
                  _LaunchTestSection(
                    controller: _pkgController,
                    onLaunch: _testLaunchApp,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _enterKiosk,
                          child: const Text('Enter Kiosk'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _exitKiosk,
                          child: const Text('Exit Kiosk'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _SendLogSection(
                    controller: _logController,
                    level: _logLevel,
                    onLevelChanged: (l) => setState(() => _logLevel = l),
                    onSend: _sendLogToSentry,
                  ),
                  const SizedBox(height: 8),
                  const Text('Log:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      color: Colors.black26,
                      child: SingleChildScrollView(
                        child: Text(
                          _log.isEmpty ? '(empty)' : _log,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.launchReason,
    required this.isDeviceOwner,
    required this.isAdminActive,
    required this.versionName,
    required this.versionCode,
  });

  final String launchReason;
  final bool isDeviceOwner;
  final bool isAdminActive;
  final String versionName;
  final String versionCode;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('Launch reason', launchReason,
                highlight: launchReason == 'app_updated' || launchReason == 'managed_config'),
            _row('Version', '$versionName ($versionCode)'),
            _row('Device Owner', isDeviceOwner ? 'YES' : 'NO', ok: isDeviceOwner),
            _row('Admin Active', isAdminActive ? 'YES' : 'NO', ok: isAdminActive),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool? ok, bool highlight = false}) {
    Color? color;
    if (highlight) color = Colors.amber;
    if (ok == true) color = Colors.greenAccent;
    if (ok == false) color = Colors.redAccent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 130, child: Text(label, style: const TextStyle(color: Colors.white60))),
          Expanded(child: Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color))),
        ],
      ),
    );
  }
}

class _ManagedConfigCard extends StatelessWidget {
  const _ManagedConfigCard({required this.config});

  final Map<String, String> config;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Managed Config', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: config.isEmpty ? Colors.grey : Colors.teal,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    config.isEmpty ? 'empty' : '${config.length} keys',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
            if (config.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...config.entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 130,
                        child: Text(e.key, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                      ),
                      Expanded(
                        child: Text(e.value,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SendLogSection extends StatelessWidget {
  const _SendLogSection({
    required this.controller,
    required this.level,
    required this.onLevelChanged,
    required this.onSend,
  });

  final TextEditingController controller;
  final SentryLogLevel level;
  final ValueChanged<SentryLogLevel> onLevelChanged;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Send Log to Sentry', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Log message',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<SentryLogLevel>(
                  value: level,
                  onChanged: (l) => l != null ? onLevelChanged(l) : null,
                  items: SentryLogLevel.values
                      .map((l) => DropdownMenuItem(value: l, child: Text(l.name)))
                      .toList(),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: onSend,
                  child: const Text('Send'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Hiện trong Sentry dashboard → Logs (cần enableLogs + DSN)',
              style: TextStyle(fontSize: 11, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
}

class _LaunchTestSection extends StatelessWidget {
  const _LaunchTestSection({required this.controller, required this.onLaunch});

  final TextEditingController controller;
  final VoidCallback onLaunch;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Test Launch App', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Package name',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: onLaunch,
                  child: const Text('Launch'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'com.mdm.test = self  •  thay bằng package app khác để test',
              style: TextStyle(fontSize: 11, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
}
