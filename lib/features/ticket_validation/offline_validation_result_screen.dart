import 'package:flutter/material.dart';
import 'package:myapp/core/services/offline_validation_service.dart';
import 'package:myapp/data/services/sync_service.dart';

/// Enhanced Validation Result Screen with Offline Support
///
/// Displays different states:
/// - ✅ Valid (Green) - Entry granted
/// - ❌ Already Used (Red) - Entry denied
/// - ⚠️ Conflict Detected (Yellow) - Validation conflict
/// - ❌ Invalid (Red) - Invalid ticket/signature
/// - ⚠️ Event Not Cached (Yellow) - Need to sync
class OfflineValidationResultScreen extends StatefulWidget {
  final String qrContent;
  final int matcheId;

  const OfflineValidationResultScreen({
    super.key,
    required this.qrContent,
    required this.matcheId,
  });

  @override
  State<OfflineValidationResultScreen> createState() =>
      _OfflineValidationResultScreenState();
}

class _OfflineValidationResultScreenState
    extends State<OfflineValidationResultScreen>
    with SingleTickerProviderStateMixin {
  final OfflineValidationService _validationService =
      OfflineValidationService();
  final SyncService _syncService = SyncService();

  ValidationResult? _result;
  bool _isValidating = true;
  String? _error;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    );
    _validateTicket();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _validateTicket() async {
    setState(() {
      _isValidating = true;
      _error = null;
    });

    try {
      final result = await _validationService.validateTicket(
        qrContent: widget.qrContent,
        matcheId: widget.matcheId,
      );

      setState(() {
        _result = result;
        _isValidating = false;
      });

      // Trigger animation
      _animationController.forward();

      // Auto-sync if there are pending validations
      if (result.isSuccess) {
        _syncService.syncNow().catchError((_) {
          // Silent fail - sync will retry later
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Validation error: $e';
        _isValidating = false;
      });
    }
  }

  Future<void> _bootstrapEvent() async {
    setState(() {
      _isValidating = true;
    });

    try {
      final success = await _syncService.bootstrapEvent(widget.matcheId);
      if (success) {
        // Retry validation after bootstrap
        await _validateTicket();
      } else {
        setState(() {
          _error = 'Failed to sync event data. Check internet connection.';
          _isValidating = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Sync error: $e';
        _isValidating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ticket Validation'),
        actions: [
          if (_result != null && _result!.validationTimeMs != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '${_result!.validationTimeMs}ms',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ),
            ),
        ],
      ),
      body: _isValidating
          ? _buildLoading()
          : _error != null
          ? _buildError()
          : _buildResult(),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Validating ticket...',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 80),
            const SizedBox(height: 24),
            Text(
              _error!,
              style: const TextStyle(color: Colors.red, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _validateTicket,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
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

    // Determine UI state
    final ValidationUIState uiState = _getUIState(result);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          // Animated Icon
          ScaleTransition(
            scale: _scaleAnimation,
            child: Icon(uiState.icon, color: uiState.color, size: 120),
          ),
          const SizedBox(height: 32),
          // Main Status Text
          Text(
            uiState.title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: uiState.color,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          // Status Card
          _buildStatusCard(result, uiState),
          const SizedBox(height: 24),
          // Ticket Details (if available)
          if (result.ticketData != null) _buildTicketDetails(result),
          // Conflict Info (if applicable)
          if (result.isAlreadyUsed && result.previousValidationTime != null)
            _buildConflictInfo(result),
          // Event Not Cached Action
          if (result.needsEventSync) _buildSyncAction(),
          const SizedBox(height: 32),
          // Action Button
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan Another Ticket'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: uiState.color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(ValidationResult result, ValidationUIState uiState) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: uiState.color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: uiState.color.withOpacity(0.3), width: 2),
      ),
      child: Column(
        children: [
          Text(
            'Status: ${result.status.name.toUpperCase()}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: uiState.color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            result.message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          if (result.ticketId != null) ...[
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              'Ticket ID',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Text(
              result.ticketId!,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTicketDetails(ValidationResult result) {
    final data = result.ticketData!;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ticket Details',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildDetailRow('Customer', result.customerName ?? 'N/A'),
            _buildDetailRow('Match ID', data['matche_id']?.toString() ?? 'N/A'),
            _buildDetailRow(
              'Ticket Type',
              data['ticket_types_id']?.toString() ?? 'N/A',
            ),
            _buildDetailRow('Amount', data['amount']?.toString() ?? 'N/A'),
            _buildDetailRow('Issued', data['issued_at']?.toString() ?? 'N/A'),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConflictInfo(ValidationResult result) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                Text(
                  'Already Validated',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'This ticket was previously validated at:',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 4),
            Text(
              result.previousValidationTime!.toLocal().toString(),
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncAction() {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.cloud_off, color: Colors.amber.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Event data not available offline',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.amber.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'You need to sync event data before validating tickets offline.',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _bootstrapEvent,
              icon: const Icon(Icons.cloud_download),
              label: const Text('Sync Event Data'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  ValidationUIState _getUIState(ValidationResult result) {
    switch (result.status) {
      case ValidationStatus.valid:
        return ValidationUIState(
          icon: Icons.check_circle,
          color: Colors.green,
          title: 'ENTRY GRANTED',
        );
      case ValidationStatus.alreadyUsed:
        return ValidationUIState(
          icon: Icons.cancel,
          color: Colors.red,
          title: 'ENTRY DENIED',
        );
      case ValidationStatus.invalid:
        return ValidationUIState(
          icon: Icons.error,
          color: Colors.red,
          title: 'INVALID TICKET',
        );
      case ValidationStatus.eventNotCached:
        return ValidationUIState(
          icon: Icons.cloud_off,
          color: Colors.amber,
          title: 'SYNC REQUIRED',
        );
      case ValidationStatus.invalidConfig:
      case ValidationStatus.systemError:
        return ValidationUIState(
          icon: Icons.error_outline,
          color: Colors.red,
          title: 'ERROR',
        );
    }
  }
}

/// UI state configuration for different validation results
class ValidationUIState {
  final IconData icon;
  final Color color;
  final String title;

  ValidationUIState({
    required this.icon,
    required this.color,
    required this.title,
  });
}
