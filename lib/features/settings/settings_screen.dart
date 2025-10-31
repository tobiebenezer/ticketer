import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/material.dart';
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
    if (_wifiIp != null) await prefs.setString('kPreferredWifiPrinterIp', _wifiIp!);
    if (_btAddress != null) await prefs.setString('kPreferredBtAddress', _btAddress!);
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
      final bonded = await inst.getBondedDevices().timeout(const Duration(seconds: 3));
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
    final futures = candidates.map((ip) => _checkPort9100(ip).then((ok) {
          if (ok) results.add(ip);
        }));
    await Future.wait(futures);
    setState(() {
      _wifiFound = results;
      _scanningWifi = false;
    });
  }

  Future<bool> _checkPort9100(String ip) async {
    try {
      final socket = await Socket.connect(ip, 9100, timeout: const Duration(milliseconds: 200));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _ipController.dispose();
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
              title: Text((_user!['name'] ?? _user!['username'] ?? 'User').toString()),
              subtitle: Text((_user!['email'] ?? '').toString()),
            ),
            const Divider(),
          ],
          const Text('Preferred Print Path'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: RadioListTile<String>(
                  value: 'wifi',
                  groupValue: _preferredPath,
                  onChanged: (v) => setState(() => _preferredPath = v!),
                  title: const Text('Wi‑Fi (TCP)')
                ),
              ),
              Expanded(
                child: RadioListTile<String>(
                  value: 'bluetooth',
                  groupValue: _preferredPath,
                  onChanged: (v) => setState(() => _preferredPath = v!),
                  title: const Text('Bluetooth')
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
                    setState(() {
                      _wifiIp = ip;
                    });
                    await _save();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Wi‑Fi printer saved')));
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot reach printer on 9100')));
                  }
                  },
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _scanWifiQuick,
            icon: _scanningWifi ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.wifi_tethering),
            label: const Text('Quick Scan (common ranges)'),
          ),
          if (_wifiFound.isNotEmpty) ...[
            const SizedBox(height: 8),
            ..._wifiFound.map((ip) => ListTile(
                  leading: const Icon(Icons.print),
                  title: Text(ip),
                  trailing: Radio<String>(
                    value: ip,
                    groupValue: _wifiIp,
                    onChanged: (v) async {
                      setState(() => _wifiIp = v);
                      await _save();
                    },
                  ),
                )),
          ],
          const Divider(height: 32),
          const Text('Bluetooth Printers'),
          const SizedBox(height: 8),
          if (_btDevices.isEmpty)
            const Text('No bonded Bluetooth printers found')
          else
            ..._btDevices.map((d) => ListTile(
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
                )),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              await _save();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved')));
            },
            child: const Text('Save Settings'),
          ),
        ],
      ),
    );
  }
}
