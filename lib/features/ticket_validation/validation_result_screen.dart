import 'package:flutter/material.dart';
import 'package:myapp/data/models/ticket_validation_result.dart';
import 'package:myapp/data/services/ticket_api.dart';

class ValidationResultScreen extends StatefulWidget {
  final String scanData;

  const ValidationResultScreen({super.key, required this.scanData});

  @override
  State<ValidationResultScreen> createState() => _ValidationResultScreenState();
}

class _ValidationResultScreenState extends State<ValidationResultScreen> {
  final TicketApi _ticketApi = TicketApi();
  TicketValidationResult? _result;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _validateTicket();
  }

  Future<void> _validateTicket() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final ref = _extractReference(widget.scanData);
      final res = await _ticketApi.validateTicket(ref);
      setState(() {
        _result = res;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to validate ticket. Please try again.';
        _isLoading = false;
      });
    }
  }

  Future<void> _markTicket() async {
    if (_result == null) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final ref = _extractReference(widget.scanData);
      final res = await _ticketApi.markTicket(ref);
      setState(() {
        _result = res;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to update ticket status. Please try again.';
        _isLoading = false;
      });
    }
  }

  String _extractReference(String data) {
    try {
      // Quick substring approach
      const key = 'validate/';
      final idx = data.lastIndexOf(key);
      if (idx != -1) {
        final after = data.substring(idx + key.length);
        // stop at next '/', '?', or '#'
        final stop = RegExp(r'[/?#]');
        final match = stop.firstMatch(after);
        return match == null ? after : after.substring(0, match.start);
      }

      // URI pathSegments approach
      final uri = Uri.tryParse(data);
      if (uri != null && uri.pathSegments.isNotEmpty) {
        final i = uri.pathSegments.indexOf('validate');
        if (i != -1 && i + 1 < uri.pathSegments.length) {
          return uri.pathSegments[i + 1];
        }
      }
    } catch (_) {}
    // fallback: assume raw reference was scanned
    return data;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Validation Result'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildResult(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _validateTicket,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResult() {
    final result = _result!;
    final isSuccess = result.type.toLowerCase() == 'success';
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            isSuccess ? Icons.check_circle_outline : Icons.cancel_outlined,
            color: isSuccess ? Colors.green : Colors.red,
            size: 96,
          ),
          const SizedBox(height: 24),
          Text(
            result.message,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(color: isSuccess ? Colors.green : Colors.red),
          ),
          const SizedBox(height: 16),
          Text(
            'Status: ${result.status}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Reference: ${result.id}',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _markTicket,
            child: const Text('Mark Ticket'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Scan Another'),
          ),
        ],
      ),
    );
  }
}
