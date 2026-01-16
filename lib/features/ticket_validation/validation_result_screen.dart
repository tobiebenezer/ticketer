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
  bool _isMarking = false;
  String? _error;
  String? _validatedRef;

  @override
  void initState() {
    super.initState();
    _validateAndMarkTicket();
  }

  /// Validate and immediately mark the ticket as entered
  Future<void> _validateAndMarkTicket() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final ref = _extractReference(widget.scanData);

      // First validate to check current status
      final validateResult = await _ticketApi.validateTicket(ref);

      // If ticket is valid and not already used, immediately mark it as entered
      if (validateResult.type.toLowerCase() == 'success' &&
          validateResult.status.toLowerCase() != 'used') {
        setState(() {
          _isMarking = true;
        });

        // Mark the ticket as entered immediately
        final markResult = await _ticketApi.markTicket(ref);
        setState(() {
          _result = markResult;
          _isLoading = false;
          _isMarking = false;
          _validatedRef = markResult.type.toLowerCase() == 'success' ? ref : null;
        });
      } else {
        // Ticket is invalid or already used, just show the validation result
        setState(() {
          _result = validateResult;
          _isLoading = false;
          _validatedRef = null;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to validate ticket. Please try again.';
        _isLoading = false;
        _isMarking = false;
        _validatedRef = null;
      });
    }
  }

  // Keep this method in case it's needed in the future
  // Future<void> _markTicket() async {
  //   if (_result == null) return;
  //   setState(() {
  //     _isLoading = true;
  //     _error = null;
  //   });
  //   try {
  //     final ref = _extractReference(widget.scanData);
  //     final res = await _ticketApi.markTicket(ref);
  //     setState(() {
  //       _result = res;
  //       _isLoading = false;
  //     });
  //   } catch (e) {
  //     setState(() {
  //       _error = 'Failed to update ticket status. Please try again.';
  //       _isLoading = false;
  //     });
  //   }
  // }

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
      appBar: AppBar(title: const Text('Validation Result')),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    _isMarking
                        ? 'Marking ticket as entered...'
                        : 'Validating ticket...',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            )
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
            const Icon(Icons.error_outline, color: Colors.red, size: 64),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(color: Colors.red, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _validateAndMarkTicket,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(_validatedRef),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan Another'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResult() {
    final result = _result!;
    final isSuccess = result.type.toLowerCase() == 'success';
    final statusLower = result.status.toLowerCase();
    final isEntered = statusLower == 'used' || statusLower == 'entered';

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            isSuccess ? Icons.check_circle : Icons.cancel,
            color: isSuccess ? Colors.green : Colors.red,
            size: 120,
          ),
          const SizedBox(height: 24),
          Text(
            isSuccess
                ? (isEntered ? 'ENTRY GRANTED' : result.message)
                : 'ENTRY DENIED',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: isSuccess ? Colors.green : Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: isSuccess
                  ? Colors.green.withValues(alpha: 0.1)
                  : Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Text(
                  'Status: ${result.status.toUpperCase()}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  result.message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Ref: ${result.id}',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 40),

          // Only "Scan Another" button - Mark button commented out
          // ElevatedButton(
          //   onPressed: _markTicket,
          //   child: const Text('Mark Ticket'),
          // ),
          // const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pop(_validatedRef),
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan Another Ticket'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ],
      ),
    );
  }
}
