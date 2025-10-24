import 'package:flutter/material.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'print_service.dart';

class PrinterSelectionDialog extends StatefulWidget {
  @override
  State<PrinterSelectionDialog> createState() => _PrinterSelectionDialogState();
}

class _PrinterSelectionDialogState extends State<PrinterSelectionDialog> {
  final PrintService _printService = PrintService();
  List<BluetoothDevice> _devices = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPrinters();
  }

  Future<void> _loadPrinters() async {
    final devices = await _printService.getPairedPrinters();
    setState(() {
      _devices = devices;
      _isLoading = false;
    });
  }

  Future<void> _connectToPrinter(BluetoothDevice device) async {
    final success = await _printService.connectToSpecificPrinter(device);
    if (success && mounted) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connected to ${device.name}')),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to connect'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Printer'),
      content: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _devices.isEmpty
              ? const Text('No paired Bluetooth printers found.\n\nPlease pair a printer in Bluetooth settings.')
              : SizedBox(
                  width: double.maxFinite,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _devices.length,
                    itemBuilder: (context, index) {
                      final device = _devices[index];
                      return ListTile(
                        leading: const Icon(Icons.print),
                        title: Text(device.name ?? 'Unknown Printer'),
                        subtitle: Text(device.address ?? ''),
                        onTap: () => _connectToPrinter(device),
                      );
                    },
                  ),
                ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        if (_devices.isEmpty)
          ElevatedButton(
            onPressed: _loadPrinters,
            child: const Text('Refresh'),
          ),
      ],
    );
  }
}

// Usage:
Future<void> showPrinterSelection(BuildContext context) async {
  await showDialog(
    context: context,
    builder: (context) => PrinterSelectionDialog(),
  );
}
