import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'kiosk_bridge.dart';

class DeviceInfoPage extends StatefulWidget {
  const DeviceInfoPage({super.key});

  @override
  State<DeviceInfoPage> createState() => _DeviceInfoPageState();
}

class _DeviceInfoPageState extends State<DeviceInfoPage> {
  Map<String, String> _info = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final info = await KioskBridge.getDeviceInfo();
      setState(() { _info = info; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _copy(BuildContext ctx, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(ctx).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Info'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _InfoSection(
                      title: 'Identity',
                      rows: [
                        _InfoRow(
                          label: 'Android ID',
                          value: _info['androidId'] ?? 'N/A',
                          copyable: true,
                          onCopy: (v) => _copy(context, v),
                        ),
                        _InfoRow(
                          label: 'Enrollment ID',
                          value: _info['enrollmentId'] ?? 'N/A',
                          copyable: true,
                          onCopy: (v) => _copy(context, v),
                        ),
                        _InfoRow(
                          label: 'IMEI',
                          value: _info['imei'] ?? 'N/A',
                          copyable: true,
                          onCopy: (v) => _copy(context, v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _InfoSection(
                      title: 'Hardware',
                      rows: [
                        _InfoRow(label: 'Manufacturer', value: _info['manufacturer'] ?? 'N/A'),
                        _InfoRow(label: 'Model', value: _info['model'] ?? 'N/A'),
                        _InfoRow(
                          label: 'Android',
                          value: '${_info['androidVersion'] ?? '?'} (SDK ${_info['sdkVersion'] ?? '?'})',
                        ),
                      ],
                    ),
                  ],
                ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({required this.title, required this.rows});

  final String title;
  final List<_InfoRow> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (int i = 0; i < rows.length; i++) ...[
                rows[i],
                if (i < rows.length - 1)
                  const Divider(height: 1, indent: 16, endIndent: 16),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.copyable = false,
    this.onCopy,
  });

  final String label;
  final String value;
  final bool copyable;
  final void Function(String)? onCopy;

  bool get _isUnavailable => value.startsWith('N/A') || value.isEmpty;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: (!_isUnavailable && copyable) ? 'monospace' : null,
                fontSize: 13,
                fontWeight: _isUnavailable ? FontWeight.normal : FontWeight.w500,
                color: _isUnavailable ? Colors.white30 : null,
                fontStyle: _isUnavailable ? FontStyle.italic : null,
              ),
            ),
          ),
          if (copyable && !_isUnavailable)
            GestureDetector(
              onTap: () => onCopy?.call(value),
              child: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.copy, size: 16, color: Colors.white38),
              ),
            ),
        ],
      ),
    );
  }
}
