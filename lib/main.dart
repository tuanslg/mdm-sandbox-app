import 'dart:async';
import 'package:flutter/material.dart';
import 'kiosk_bridge.dart';

void main() {
  runApp(const MdmTestApp());
}

class MdmTestApp extends StatelessWidget {
  const MdmTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MDM Test',
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

  @override
  void initState() {
    super.initState();
    _loadStatus();
    _listenMdmEvents();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
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
        }
      },
      onError: (e) => _appendLog('EventChannel error: $e'),
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
    } catch (e) {
      _appendLog('Error loading status: $e');
      setState(() => _loading = false);
    }
  }

  void _appendLog(String msg) {
    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    setState(() => _log = '[$ts] $msg\n$_log');
  }

  Future<void> _enterKiosk() async {
    try {
      await KioskBridge.enterKiosk();
      _appendLog('enterKiosk OK');
    } catch (e) {
      _appendLog('enterKiosk FAILED: $e');
    }
  }

  Future<void> _exitKiosk() async {
    try {
      await KioskBridge.exitKiosk();
      _appendLog('exitKiosk OK');
    } catch (e) {
      _appendLog('exitKiosk FAILED: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MDM Test App'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadStatus),
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
