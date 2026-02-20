import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/material.dart';
import 'package:myapp/core/services/app_settings_service.dart';
import 'package:myapp/data/services/sync_service.dart';
import 'package:myapp/features/ticket_printing/reprint_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _preferredPath = 'wifi';
  String? _wifiIp;
  String? _btAddress;
  List<String> _wifiFound = [];
  List<BluetoothDevice> _btDevices = [];
  bool _scanningWifi = false;
  bool _loading = true;
  Map<String, dynamic>? _user;
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _printerDelayController = TextEditingController();
  final AppSettingsService _appSettings = AppSettingsService();

  // Offline mode settings
  bool _preferOfflineSales = true;
  bool _preferOfflineValidation = true;
  bool _autoSync = true;
  bool _fastCheckoutMode = false;
  bool _autoPrint = true;
  bool _validationSoundEnabled = true;
  int _validationPopupTimeoutSeconds = 5;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _preferredPath = prefs.getString('kPreferredPrintPath') ?? 'wifi';
      _wifiIp = prefs.getString('kPreferredWifiPrinterIp');
      _btAddress = prefs.getString('kPreferredBtAddress');
      final userJson = prefs.getString('kUserProfileJson');
      if (userJson != null) {
        _user = _tryDecode(userJson);
      }
      _ipController.text = _wifiIp ?? '';
      _loading = false;
    });

    // Load offline settings
    final preferOfflineSales = await _appSettings.getPreferOfflineSales();
    final preferOfflineValidation = await _appSettings
        .getPreferOfflineValidation();
    final autoSync = await _appSettings.getAutoSyncEnabled();
    final fastCheckoutMode = await _appSettings.getFastCheckoutMode();
    final autoPrint = await _appSettings.getAutoPrintEnabled();
    final validationSoundEnabled = await _appSettings
        .getValidationSoundEnabled();
    final validationPopupTimeout = await _appSettings
        .getValidationPopupTimeoutSeconds();
    final printerDelay = await _appSettings.getPrinterDelayMs();

    _printerDelayController.text = printerDelay.toString();

    if (!mounted) return;
    setState(() {
      _preferOfflineSales = preferOfflineSales;
      _preferOfflineValidation = preferOfflineValidation;
      _autoSync = autoSync;
      _fastCheckoutMode = fastCheckoutMode;
      _autoPrint = autoPrint;
      _validationSoundEnabled = validationSoundEnabled;
      _validationPopupTimeoutSeconds = validationPopupTimeout;
    });

    await _loadBt();
  }

  Map<String, dynamic>? _tryDecode(String s) {
    try {
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('kPreferredPrintPath', _preferredPath);
    if (_wifiIp != null)
      await prefs.setString('kPreferredWifiPrinterIp', _wifiIp!);
    if (_btAddress != null)
      await prefs.setString('kPreferredBtAddress', _btAddress!);
  }

  Future<void> _updateOfflineSetting(String key, bool value) async {
    switch (key) {
      case 'offline_sales':
        await _appSettings.setPreferOfflineSales(value);
        setState(() => _preferOfflineSales = value);
        break;
      case 'offline_validation':
        await _appSettings.setPreferOfflineValidation(value);
        setState(() => _preferOfflineValidation = value);
        break;
      case 'auto_sync':
        await _appSettings.setAutoSyncEnabled(value);
        setState(() => _autoSync = value);

        // Reinitialize or dispose sync service based on setting
        if (value) {
          // Enable auto-sync
          final syncService = SyncService();
          await syncService.initialize();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Auto-sync enabled'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          // Disable auto-sync (service will check setting before syncing)
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Auto-sync disabled'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
        break;
      case 'fast_checkout':
        await _appSettings.setFastCheckoutMode(value);
        setState(() => _fastCheckoutMode = value);
        break;
      case 'auto_print':
        await _appSettings.setAutoPrintEnabled(value);
        setState(() => _autoPrint = value);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                value
                    ? 'Auto-print enabled - tickets will print after sale'
                    : 'Auto-print disabled - use reprint screen to print',
              ),
              backgroundColor: value ? Colors.green : Colors.orange,
            ),
          );
        }
        break;
      case 'validation_popup_timeout':
        await _appSettings.setValidationPopupTimeoutSeconds(value as int);
        setState(() => _validationPopupTimeoutSeconds = value as int);
        break;
      case 'validation_sound':
        await _appSettings.setValidationSoundEnabled(value);
        setState(() => _validationSoundEnabled = value);
        break;
    }
  }

  Future<void> _loadBt() async {
    try {
      await [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();

      final inst = BlueThermalPrinter.instance;
      final bonded = await inst.getBondedDevices().timeout(
        const Duration(seconds: 3),
      );
      if (!mounted) return;
      setState(() {
        _btDevices = bonded;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _btDevices = [];
      });
    }
  }

  Future<void> _scanWifiQuick() async {
    if (_scanningWifi) return;
    // Request necessary permissions for Wi‑Fi scanning
    await [
      Permission.nearbyWifiDevices, // Android 13+
      Permission.locationWhenInUse, // Required on some older Android versions
    ].request();
    setState(() {
      _scanningWifi = true;
      _wifiFound = [];
    });
    final candidates = <String>[];
    for (int i = 2; i <= 50; i++) {
      candidates.add('192.168.1.$i');
    }
    for (int i = 2; i <= 20; i++) {
      candidates.add('192.168.0.$i');
    }
    final results = <String>[];
    final futures = candidates.map(
      (ip) => _checkPort9100(ip).then((ok) {
        if (ok) results.add(ip);
      }),
    );
    await Future.wait(futures);
    setState(() {
      _wifiFound = results;
      _scanningWifi = false;
    });
  }

  Future<bool> _checkPort9100(String ip) async {
    try {
      final socket = await Socket.connect(
        ip,
        9100,
        timeout: const Duration(milliseconds: 200),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _ipController.dispose();
    _printerDelayController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_user != null) ...[
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(
                (_user!['name'] ?? _user!['username'] ?? 'User').toString(),
              ),
              subtitle: Text((_user!['email'] ?? '').toString()),
            ),
            const Divider(),
          ],

          // Offline Mode Settings
          const Text(
            'Offline Mode',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Prefer Offline Sales'),
            subtitle: const Text('Try offline sales first, fallback to API'),
            value: _preferOfflineSales,
            contentPadding: EdgeInsets.zero,
            onChanged: (value) => _updateOfflineSetting('offline_sales', value),
          ),
          SwitchListTile(
            title: const Text('Prefer Offline Validation'),
            subtitle: const Text('Use offline validation when possible'),
            value: _preferOfflineValidation,
            contentPadding: EdgeInsets.zero,
            onChanged: (value) =>
                _updateOfflineSetting('offline_validation', value),
          ),
          SwitchListTile(
            title: const Text('Auto-Sync'),
            subtitle: const Text('Automatically sync data when online'),
            value: _autoSync,
            contentPadding: EdgeInsets.zero,
            onChanged: (value) => _updateOfflineSetting('auto_sync', value),
          ),
          SwitchListTile(
            title: const Text('Fast Checkout Mode'),
            subtitle: const Text('Streamlined UI for rapid ticket sales'),
            value: _fastCheckoutMode,
            contentPadding: EdgeInsets.zero,
            onChanged: (value) => _updateOfflineSetting('fast_checkout', value),
          ),
          SwitchListTile(
            title: const Text('Auto-Print Tickets'),
            subtitle: const Text('Automatically print tickets after sale'),
            value: _autoPrint,
            contentPadding: EdgeInsets.zero,
            onChanged: (value) => _updateOfflineSetting('auto_print', value),
          ),
          SwitchListTile(
            title: const Text('Validation Sounds'),
            subtitle: const Text('Play different sounds for pass and fail'),
            value: _validationSoundEnabled,
            contentPadding: EdgeInsets.zero,
            onChanged: (value) =>
                _updateOfflineSetting('validation_sound', value),
          ),
          const SizedBox(height: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Validation Popup Timeout',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Auto-dismiss after $_validationPopupTimeoutSeconds seconds',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
              Slider(
                value: _validationPopupTimeoutSeconds.toDouble(),
                min: 1,
                max: 30,
                divisions: 29,
                label: '$_validationPopupTimeoutSeconds s',
                onChanged: (value) {
                  setState(
                    () => _validationPopupTimeoutSeconds = value.round(),
                  );
                },
                onChangeEnd: (value) async {
                  await _appSettings.setValidationPopupTimeoutSeconds(
                    value.round(),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Printer Delay Between Tickets',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Delay in milliseconds between each ticket print',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _printerDelayController,
                      decoration: const InputDecoration(
                        labelText: 'Delay (ms)',
                        hintText: '1500',
                        border: OutlineInputBorder(),
                        suffixText: 'ms',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (value) async {
                        final delay = int.tryParse(value) ?? 1500;
                        await _appSettings.setPrinterDelayMs(delay);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Divider(height: 32),

          // Tools Section
          Text('Tools', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.print),
            title: const Text('Reprint Tickets'),
            subtitle: const Text('Search and reprint previously sold tickets'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ReprintScreen()),
              );
            },
          ),
          const Divider(height: 32),

          const Text('Preferred Print Path'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: RadioListTile<String>(
                  value: 'wifi',
                  groupValue: _preferredPath,
                  onChanged: (v) async {
                    setState(() => _preferredPath = v!);
                    await _save();
                  },
                  title: const Text('Wi‑Fi (TCP)'),
                ),
              ),
              Expanded(
                child: RadioListTile<String>(
                  value: 'bluetooth',
                  groupValue: _preferredPath,
                  onChanged: (v) async {
                    setState(() => _preferredPath = v!);
                    await _save();
                  },
                  title: const Text('Bluetooth'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Wi‑Fi Printer'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ipController,
                  decoration: const InputDecoration(
                    labelText: 'Printer IP (port 9100)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) async {
                    final ip = value.trim();
                    if (ip.isNotEmpty) {
                      _wifiIp = ip;
                      await _save();
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
                child: FilledButton(
                  onPressed: () async {
                    final ip = _ipController.text.trim();
                    if (ip.isEmpty) return;
                    final ok = await _checkPort9100(ip);
                    if (!mounted) return;
                    if (ok) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Printer reachable')),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Cannot reach printer on 9100'),
                        ),
                      );
                    }
                  },
                  child: const Text('Test'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _scanWifiQuick,
            icon: _scanningWifi
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_tethering),
            label: const Text('Quick Scan (common ranges)'),
          ),
          if (_wifiFound.isNotEmpty) ...[
            const SizedBox(height: 8),
            ..._wifiFound.map(
              (ip) => ListTile(
                leading: const Icon(Icons.print),
                title: Text(ip),
                trailing: Radio<String>(
                  value: ip,
                  groupValue: _wifiIp,
                  onChanged: (v) async {
                    setState(() => _wifiIp = v);
                    _ipController.text = v!;
                    await _save();
                  },
                ),
              ),
            ),
          ],
          const Divider(height: 32),
          const Text('Bluetooth Printers'),
          const SizedBox(height: 8),
          if (_btDevices.isEmpty)
            const Text('No bonded Bluetooth printers found')
          else
            ..._btDevices.map(
              (d) => ListTile(
                leading: const Icon(Icons.bluetooth),
                title: Text(d.name ?? 'Unknown'),
                subtitle: Text(d.address ?? ''),
                trailing: Radio<String>(
                  value: d.address ?? '',
                  groupValue: _btAddress,
                  onChanged: (v) async {
                    setState(() => _btAddress = v);
                    await _save();
                  },
                ),
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
