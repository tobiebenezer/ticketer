import 'package:flutter/material.dart';
import 'package:myapp/data/services/sync_service.dart';
import 'package:myapp/data/local/database_helper.dart';

/// Sync Status Widget - Shows sync state and pending items
///
/// Displays:
/// - Sync status (idle, syncing, completed, failed)
/// - Number of pending tickets and validations
/// - Manual sync trigger
class SyncStatusWidget extends StatefulWidget {
  const SyncStatusWidget({super.key});

  @override
  State<SyncStatusWidget> createState() => _SyncStatusWidgetState();
}

class _SyncStatusWidgetState extends State<SyncStatusWidget> {
  final SyncService _syncService = SyncService();
  final DatabaseHelper _db = DatabaseHelper();

  SyncStatus _status = SyncStatus.idle;
  Map<String, int> _stats = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _syncService.onSyncStatusChanged = _onSyncStatusChanged;
    _loadStats();
  }

  @override
  void dispose() {
    _syncService.onSyncStatusChanged = null;
    super.dispose();
  }

  void _onSyncStatusChanged(SyncStatus status) {
    if (mounted) {
      setState(() {
        _status = status;
      });
      if (status == SyncStatus.completed || status == SyncStatus.failed) {
        _loadStats();
      }
    }
  }

  Future<void> _loadStats() async {
    final stats = await _db.getSyncStats();
    if (mounted) {
      setState(() {
        _stats = stats;
        _isLoading = false;
      });
    }
  }

  Future<void> _triggerSync() async {
    setState(() {
      _status = SyncStatus.syncing;
    });
    await _syncService.syncNow();
    await _loadStats();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox.shrink();
    }

    final hasPending =
        (_stats['unsynced_tickets'] ?? 0) > 0 ||
        (_stats['unsynced_validations'] ?? 0) > 0;

    if (!hasPending && _status == SyncStatus.idle) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.all(16),
      color: _getStatusColor().withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _buildStatusIcon(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getStatusText(),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (hasPending) ...[
                        const SizedBox(height: 4),
                        Text(
                          _getPendingText(),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_status != SyncStatus.syncing && hasPending)
                  IconButton(
                    icon: const Icon(Icons.sync),
                    onPressed: _triggerSync,
                    tooltip: 'Sync Now',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon() {
    switch (_status) {
      case SyncStatus.idle:
        return Icon(Icons.cloud_queue, color: Colors.grey.shade600);
      case SyncStatus.syncing:
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case SyncStatus.completed:
        return const Icon(Icons.cloud_done, color: Colors.green);
      case SyncStatus.failed:
        return const Icon(Icons.cloud_off, color: Colors.red);
    }
  }

  Color _getStatusColor() {
    switch (_status) {
      case SyncStatus.idle:
        return Colors.grey;
      case SyncStatus.syncing:
        return Colors.blue;
      case SyncStatus.completed:
        return Colors.green;
      case SyncStatus.failed:
        return Colors.red;
    }
  }

  String _getStatusText() {
    switch (_status) {
      case SyncStatus.idle:
        return 'Pending Sync';
      case SyncStatus.syncing:
        return 'Syncing...';
      case SyncStatus.completed:
        return 'Sync Complete';
      case SyncStatus.failed:
        return 'Sync Failed';
    }
  }

  String _getPendingText() {
    final tickets = _stats['unsynced_tickets'] ?? 0;
    final validations = _stats['unsynced_validations'] ?? 0;
    final parts = <String>[];
    if (tickets > 0) parts.add('$tickets ticket${tickets > 1 ? 's' : ''}');
    if (validations > 0) {
      parts.add('$validations validation${validations > 1 ? 's' : ''}');
    }
    return parts.join(', ');
  }
}

/// Compact Sync Indicator for AppBar
class SyncIndicator extends StatefulWidget {
  const SyncIndicator({super.key});

  @override
  State<SyncIndicator> createState() => _SyncIndicatorState();
}

class _SyncIndicatorState extends State<SyncIndicator> {
  final SyncService _syncService = SyncService();
  final DatabaseHelper _db = DatabaseHelper();

  SyncStatus _status = SyncStatus.idle;
  int _pendingCount = 0;

  @override
  void initState() {
    super.initState();
    _syncService.onSyncStatusChanged = _onSyncStatusChanged;
    _loadPendingCount();
  }

  @override
  void dispose() {
    _syncService.onSyncStatusChanged = null;
    super.dispose();
  }

  void _onSyncStatusChanged(SyncStatus status) {
    if (mounted) {
      setState(() {
        _status = status;
      });
      if (status == SyncStatus.completed || status == SyncStatus.failed) {
        _loadPendingCount();
      }
    }
  }

  Future<void> _loadPendingCount() async {
    final stats = await _db.getSyncStats();
    if (mounted) {
      setState(() {
        _pendingCount =
            (stats['unsynced_tickets'] ?? 0) +
            (stats['unsynced_validations'] ?? 0);
      });
    }
  }

  Future<void> _showSyncDialog() async {
    final stats = await _db.getSyncStats();
    final tickets = stats['unsynced_tickets'] ?? 0;
    final validations = stats['unsynced_validations'] ?? 0;

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(_getIcon(), color: _getColor()),
            const SizedBox(width: 12),
            const Text('Sync Status'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _getStatusMessage(),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (tickets > 0) ...[
              Row(
                children: [
                  const Icon(Icons.confirmation_number, size: 20),
                  const SizedBox(width: 8),
                  Text('$tickets pending ticket${tickets > 1 ? 's' : ''}'),
                ],
              ),
              const SizedBox(height: 8),
            ],
            if (validations > 0) ...[
              Row(
                children: [
                  const Icon(Icons.verified, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '$validations pending validation${validations > 1 ? 's' : ''}',
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            if (tickets == 0 && validations == 0)
              const Text('All data is synced!'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (_pendingCount > 0 && _status != SyncStatus.syncing)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _triggerSync();
              },
              icon: const Icon(Icons.sync),
              label: const Text('Sync Now'),
            ),
        ],
      ),
    );
  }

  Future<void> _triggerSync() async {
    setState(() {
      _status = SyncStatus.syncing;
    });
    await _syncService.syncNow();
    await _loadPendingCount();
  }

  String _getStatusMessage() {
    switch (_status) {
      case SyncStatus.idle:
        return _pendingCount > 0
            ? 'You have pending items to sync'
            : 'Everything is up to date';
      case SyncStatus.syncing:
        return 'Syncing data...';
      case SyncStatus.completed:
        return 'Sync completed successfully!';
      case SyncStatus.failed:
        return 'Sync failed. Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_pendingCount == 0 && _status == SyncStatus.idle) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Stack(
        alignment: Alignment.center,
        children: [
          IconButton(
            icon: Icon(_getIcon()),
            color: _getColor(),
            onPressed: _showSyncDialog,
            tooltip: 'Sync Status',
          ),
          if (_pendingCount > 0 && _status != SyncStatus.syncing)
            Positioned(
              right: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  _pendingCount > 99 ? '99+' : '$_pendingCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }

  IconData _getIcon() {
    switch (_status) {
      case SyncStatus.idle:
        return Icons.cloud_queue;
      case SyncStatus.syncing:
        return Icons.cloud_sync;
      case SyncStatus.completed:
        return Icons.cloud_done;
      case SyncStatus.failed:
        return Icons.cloud_off;
    }
  }

  Color _getColor() {
    switch (_status) {
      case SyncStatus.idle:
        return Colors.grey;
      case SyncStatus.syncing:
        return Colors.blue;
      case SyncStatus.completed:
        return Colors.green;
      case SyncStatus.failed:
        return Colors.red;
    }
  }
}
