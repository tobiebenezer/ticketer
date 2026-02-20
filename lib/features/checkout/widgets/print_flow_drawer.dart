import 'package:flutter/material.dart';

enum PrintFlowStatus { queued, sending, sent, failed, pdfFallback }

class PrintFlowJob {
  final String id;
  final String ticketId;
  final String customerName;
  final int ticketNumber;
  final int totalTickets;
  final String? purchaseBatchId;
  final int? purchaseIndex;
  final int? purchaseQuantity;
  final int? displayTicketId;
  PrintFlowStatus status;
  int attemptCount;
  String? lastError;
  String? pdfPath;
  DateTime createdAt;
  DateTime updatedAt;
  bool selected;

  PrintFlowJob({
    required this.id,
    required this.ticketId,
    required this.customerName,
    required this.ticketNumber,
    required this.totalTickets,
    this.purchaseBatchId,
    this.purchaseIndex,
    this.purchaseQuantity,
    this.displayTicketId,
    this.status = PrintFlowStatus.queued,
    this.attemptCount = 0,
    this.lastError,
    this.pdfPath,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.selected = false,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  factory PrintFlowJob.fromMap(Map<String, dynamic> map) {
    final rawStatus = (map['status'] ?? 'queued').toString();
    return PrintFlowJob(
      id: (map['id'] ?? '').toString(),
      ticketId: (map['ticket_id'] ?? '').toString(),
      customerName: (map['customer_name'] ?? '').toString(),
      ticketNumber: (map['ticket_number'] as num?)?.toInt() ?? 1,
      totalTickets: (map['total_tickets'] as num?)?.toInt() ?? 1,
      purchaseBatchId: map['purchase_batch_id']?.toString(),
      purchaseIndex: (map['purchase_index'] as num?)?.toInt(),
      purchaseQuantity: (map['purchase_quantity'] as num?)?.toInt(),
      displayTicketId: (map['display_ticket_id'] as num?)?.toInt(),
      status: _statusFromDb(rawStatus),
      attemptCount: (map['attempt_count'] as num?)?.toInt() ?? 0,
      lastError: map['last_error']?.toString(),
      pdfPath: map['pdf_path']?.toString(),
      createdAt: DateTime.tryParse((map['created_at'] ?? '').toString()),
      updatedAt: DateTime.tryParse((map['updated_at'] ?? '').toString()),
      selected: ((map['selected'] as num?)?.toInt() ?? 0) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'ticket_id': ticketId,
      'customer_name': customerName,
      'ticket_number': ticketNumber,
      'total_tickets': totalTickets,
      'purchase_batch_id': purchaseBatchId,
      'purchase_index': purchaseIndex,
      'purchase_quantity': purchaseQuantity,
      'display_ticket_id': displayTicketId,
      'status': _statusToDb(status),
      'attempt_count': attemptCount,
      'last_error': lastError,
      'pdf_path': pdfPath,
      'selected': selected ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  static PrintFlowStatus _statusFromDb(String status) {
    switch (status) {
      case 'sending':
        return PrintFlowStatus.sending;
      case 'sent':
        return PrintFlowStatus.sent;
      case 'failed':
        return PrintFlowStatus.failed;
      case 'pdf_fallback':
        return PrintFlowStatus.pdfFallback;
      case 'queued':
      default:
        return PrintFlowStatus.queued;
    }
  }

  static String _statusToDb(PrintFlowStatus status) {
    switch (status) {
      case PrintFlowStatus.queued:
        return 'queued';
      case PrintFlowStatus.sending:
        return 'sending';
      case PrintFlowStatus.sent:
        return 'sent';
      case PrintFlowStatus.failed:
        return 'failed';
      case PrintFlowStatus.pdfFallback:
        return 'pdf_fallback';
    }
  }

  int get effectiveTicketNumber => purchaseIndex ?? ticketNumber;
  int get effectiveTotalTickets => purchaseQuantity ?? totalTickets;
}

class PrintFlowDrawer extends StatefulWidget {
  final List<PrintFlowJob> jobs;
  final bool isProcessing;
  final bool isSyncingReady;
  final int syncReadyCount;
  final int syncBlockedCount;
  final VoidCallback onSyncReadyNow;
  final VoidCallback onRetryFailed;
  final VoidCallback onResendSelected;
  final VoidCallback onClearCompleted;
  final ValueChanged<String> onToggleSelected;

  const PrintFlowDrawer({
    super.key,
    required this.jobs,
    required this.isProcessing,
    required this.isSyncingReady,
    required this.syncReadyCount,
    required this.syncBlockedCount,
    required this.onSyncReadyNow,
    required this.onRetryFailed,
    required this.onResendSelected,
    required this.onClearCompleted,
    required this.onToggleSelected,
  });

  @override
  State<PrintFlowDrawer> createState() => _PrintFlowDrawerState();
}

class _PrintFlowDrawerState extends State<PrintFlowDrawer> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final queuedCount = widget.jobs
        .where(
          (j) =>
              j.status == PrintFlowStatus.queued ||
              j.status == PrintFlowStatus.sending,
        )
        .length;
    final sentCount = widget.jobs
        .where((j) => j.status == PrintFlowStatus.sent)
        .length;
    final failedCount = widget.jobs
        .where(
          (j) =>
              j.status == PrintFlowStatus.failed ||
              j.status == PrintFlowStatus.pdfFallback,
        )
        .length;
    final selectedCount = widget.jobs.where((j) => j.selected).length;
    final visibleJobs = _visibleJobs(widget.jobs, _searchQuery);
    final nextJobId = _nextUnsentJobId(widget.jobs);

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            ListTile(
              title: const Text(
                'Print Flow',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '$queuedCount queued • $sentCount sent • $failedCount failed',
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: widget.isProcessing
                              ? null
                              : widget.onRetryFailed,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Retry Failed'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: widget.isProcessing || selectedCount == 0
                              ? null
                              : widget.onResendSelected,
                          icon: const Icon(Icons.send, size: 16),
                          label: Text('Resend ($selectedCount)'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed:
                          widget.syncReadyCount > 0 && !widget.isSyncingReady
                          ? widget.onSyncReadyNow
                          : null,
                      icon: widget.isSyncingReady
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_upload, size: 16),
                      label: Text('Sync Ready (${widget.syncReadyCount})'),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Sync eligibility: ${widget.syncReadyCount} ready • ${widget.syncBlockedCount} blocked',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.blueGrey.shade700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: widget.isProcessing
                          ? null
                          : widget.onClearCompleted,
                      icon: const Icon(Icons.clear_all, size: 16),
                      label: const Text('Clear Sent'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Search by code, customer, ticket',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      isDense: true,
                      border: const OutlineInputBorder(),
                      suffixIcon: _searchQuery.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                });
                              },
                              icon: const Icon(Icons.clear, size: 18),
                              tooltip: 'Clear search',
                            ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 20),
            Expanded(
              child: widget.jobs.isEmpty
                  ? const Center(child: Text('No print jobs yet'))
                  : visibleJobs.isEmpty
                  ? const Center(child: Text('No matching print jobs'))
                  : ListView.builder(
                      itemCount: visibleJobs.length,
                      itemBuilder: (context, index) {
                        final job = visibleJobs[index];
                        final isNextToPrint = job.id == nextJobId;
                        return CheckboxListTile(
                          value: job.selected,
                          onChanged: (_) => widget.onToggleSelected(job.id),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Ticket ${job.effectiveTicketNumber}/${job.effectiveTotalTickets}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (isNextToPrint)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade100,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Colors.amber.shade700,
                                    ),
                                  ),
                                  child: Text(
                                    'Next',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.amber.shade900,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Text(
                            [
                              'Code: ${_shortCode(job.ticketId)}',
                              'Status: ${_statusLabel(job.status)}',
                              'Attempts: ${job.attemptCount}',
                              if (job.lastError != null &&
                                  job.lastError!.isNotEmpty)
                                'Error: ${job.lastError}',
                            ].join('\n'),
                          ),
                          secondary: Icon(
                            _statusIcon(job.status),
                            color: _statusColor(job.status),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          isThreeLine: true,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static List<PrintFlowJob> _visibleJobs(
    List<PrintFlowJob> jobs,
    String query,
  ) {
    final normalizedQuery = query.trim().toLowerCase();
    final filtered = normalizedQuery.isEmpty
        ? List<PrintFlowJob>.from(jobs)
        : jobs.where((job) {
            final haystack = [
              job.ticketId,
              _shortCode(job.ticketId),
              job.customerName,
              job.ticketNumber.toString(),
              job.totalTickets.toString(),
              job.effectiveTicketNumber.toString(),
              job.effectiveTotalTickets.toString(),
              _statusLabel(job.status),
            ].join(' ').toLowerCase();
            return haystack.contains(normalizedQuery);
          }).toList();

    filtered.sort((a, b) {
      final aUnsent = a.status != PrintFlowStatus.sent;
      final bUnsent = b.status != PrintFlowStatus.sent;
      if (aUnsent != bUnsent) {
        return aUnsent ? -1 : 1;
      }
      return a.createdAt.compareTo(b.createdAt);
    });

    return filtered;
  }

  static String? _nextUnsentJobId(List<PrintFlowJob> jobs) {
    final unsent = jobs.where((j) => j.status != PrintFlowStatus.sent).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return unsent.isEmpty ? null : unsent.first.id;
  }

  static String _statusLabel(PrintFlowStatus status) {
    switch (status) {
      case PrintFlowStatus.queued:
        return 'Queued';
      case PrintFlowStatus.sending:
        return 'Sending';
      case PrintFlowStatus.sent:
        return 'Sent';
      case PrintFlowStatus.failed:
        return 'Failed';
      case PrintFlowStatus.pdfFallback:
        return 'PDF Fallback';
    }
  }

  static IconData _statusIcon(PrintFlowStatus status) {
    switch (status) {
      case PrintFlowStatus.queued:
        return Icons.schedule;
      case PrintFlowStatus.sending:
        return Icons.sync;
      case PrintFlowStatus.sent:
        return Icons.check_circle;
      case PrintFlowStatus.failed:
        return Icons.error;
      case PrintFlowStatus.pdfFallback:
        return Icons.picture_as_pdf;
    }
  }

  static Color _statusColor(PrintFlowStatus status) {
    switch (status) {
      case PrintFlowStatus.queued:
        return Colors.blueGrey;
      case PrintFlowStatus.sending:
        return Colors.blue;
      case PrintFlowStatus.sent:
        return Colors.green;
      case PrintFlowStatus.failed:
        return Colors.red;
      case PrintFlowStatus.pdfFallback:
        return Colors.orange;
    }
  }

  static String _shortCode(String value) {
    if (value.length <= 8) return value;
    return value.substring(value.length - 8).toUpperCase();
  }
}
