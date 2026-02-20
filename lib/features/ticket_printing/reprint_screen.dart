import 'package:flutter/material.dart';
import 'package:myapp/data/local/database_helper.dart';
import 'package:myapp/features/ticket_printing/print_service.dart';

/// Reprint Screen - Search and reprint tickets
///
/// Allows users to:
/// - Search tickets by ID, customer name, or transaction ID
/// - View ticket details
/// - Reprint individual tickets
/// - Reprint multiple tickets at once
class ReprintScreen extends StatefulWidget {
  const ReprintScreen({super.key});

  @override
  State<ReprintScreen> createState() => _ReprintScreenState();
}

class _ReprintScreenState extends State<ReprintScreen> {
  final DatabaseHelper _db = DatabaseHelper();
  final PrintService _printService = PrintService();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _tickets = [];
  List<Map<String, dynamic>> _filteredTickets = [];
  bool _isLoading = false;
  bool _isPrinting = false;
  int _printProgress = 0;
  int _printTotal = 0;
  Set<String> _selectedTickets = {};

  @override
  void initState() {
    super.initState();
    _loadTickets();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTickets() async {
    setState(() => _isLoading = true);

    try {
      final tickets = await _db.getAllLocalTickets();
      if (!mounted) return;

      setState(() {
        _tickets = tickets;
        _filteredTickets = tickets;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('Failed to load tickets: $e');
    }
  }

  void _filterTickets(String query) {
    if (query.isEmpty) {
      setState(() => _filteredTickets = _tickets);
      return;
    }

    final lowerQuery = query.toLowerCase();
    setState(() {
      _filteredTickets = _tickets.where((ticket) {
        final ticketId = ticket['ticket_id']?.toString().toLowerCase() ?? '';
        final customerName =
            ticket['customer_name']?.toString().toLowerCase() ?? '';
        final matchId = ticket['matche_id']?.toString().toLowerCase() ?? '';

        return ticketId.contains(lowerQuery) ||
            customerName.contains(lowerQuery) ||
            matchId.contains(lowerQuery);
      }).toList();
    });
  }

  Future<void> _reprintTicket(Map<String, dynamic> ticket) async {
    setState(() => _isPrinting = true);

    try {
      // Fetch ticket type name and event name from cache
      final ticketTypeName = await _getTicketTypeName(
        ticket['ticket_types_id'],
      );
      final eventName = await _getEventName(ticket['matche_id']);

      String? savedPdfPath;
      final success = await _printService.printTicket(
        eventName: eventName,
        ticketType: ticketTypeName,
        price: double.tryParse(ticket['amount']?.toString() ?? '0') ?? 0.0,
        ticketNumber: 1,
        totalTickets: 1,
        ticketCode: ticket['ticket_id'] ?? '',
        validationUrl: 'https://example.com/validate/${ticket['ticket_id']}',
        transactionId: ticket['ticket_id'] ?? '',
        customerName: ticket['customer_name'],
        ticketId: int.tryParse(ticket['ticket_id']?.toString() ?? '0'),
        matchId: ticket['matche_id'],
        ticketTypeId: ticket['ticket_types_id'],
        onSavedPdf: (path) {
          savedPdfPath = path;
        },
      );

      if (!mounted) return;

      setState(() => _isPrinting = false);

      if (success) {
        if (savedPdfPath != null) {
          _showSuccess('No printer found. Ticket saved to: $savedPdfPath');
        } else {
          _showSuccess('Ticket reprinted successfully');
        }
      } else {
        _showError('Failed to reprint ticket');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isPrinting = false);
      _showError('Error reprinting ticket: $e');
    }
  }

  Future<void> _reprintSelected() async {
    if (_selectedTickets.isEmpty) {
      _showError('No tickets selected');
      return;
    }

    final selectedTicketIds = _filteredTickets
        .map((ticket) => ticket['ticket_id']?.toString() ?? '')
        .where((ticketId) => _selectedTickets.contains(ticketId))
        .toList();
    final totalTickets = selectedTicketIds.length;
    setState(() {
      _isPrinting = true;
      _printProgress = 0;
      _printTotal = totalTickets;
    });

    int successCount = 0;
    int failCount = 0;

    int currentIndex = 0;
    for (final ticketId in selectedTicketIds) {
      currentIndex++;

      // Update progress
      if (mounted) {
        setState(() {
          _printProgress = currentIndex;
        });
      }

      final ticket = _tickets.firstWhere(
        (t) => t['ticket_id'] == ticketId,
        orElse: () => {},
      );

      if (ticket.isEmpty) continue;

      try {
        // Fetch ticket type name and event name from cache
        final ticketTypeName = await _getTicketTypeName(
          ticket['ticket_types_id'],
        );
        final eventName = await _getEventName(ticket['matche_id']);

        String? savedPdfPath;
        final success = await _printService.printTicket(
          eventName: eventName,
          ticketType: ticketTypeName,
          price: double.tryParse(ticket['amount']?.toString() ?? '0') ?? 0.0,
          ticketNumber: currentIndex,
          totalTickets: totalTickets,
          ticketCode: ticket['ticket_id'] ?? '',
          validationUrl: 'https://example.com/validate/${ticket['ticket_id']}',
          transactionId: ticket['ticket_id'] ?? '',
          customerName: ticket['customer_name'],
          ticketId: int.tryParse(ticket['ticket_id']?.toString() ?? '0'),
          matchId: ticket['matche_id'],
          ticketTypeId: ticket['ticket_types_id'],
          onSavedPdf: (path) {
            savedPdfPath = path;
          },
        );

        if (success) {
          successCount++;
          if (savedPdfPath != null && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Ticket saved to: $savedPdfPath'),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        } else {
          failCount++;
        }

        // Small delay between prints to prevent buffer overflow
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        failCount++;
        debugPrint('Error printing ticket $ticketId: $e');
      }
    }

    if (!mounted) return;

    setState(() {
      _isPrinting = false;
      _printProgress = 0;
      _printTotal = 0;
      _selectedTickets.clear();
    });

    _showSuccess('Reprinted $successCount ticket(s). Failed: $failCount');
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  /// Get ticket type name from cache
  Future<String> _getTicketTypeName(int? ticketTypeId) async {
    if (ticketTypeId == null) return 'Unknown Type';

    try {
      final db = await _db.database;
      final results = await db.query(
        'cached_ticket_types',
        where: 'id = ?',
        whereArgs: [ticketTypeId],
        limit: 1,
      );

      if (results.isNotEmpty) {
        return results.first['name']?.toString() ?? 'Type #$ticketTypeId';
      }
    } catch (e) {
      debugPrint('Error fetching ticket type name: $e');
    }

    return 'Type #$ticketTypeId';
  }

  /// Get event name from cache
  Future<String> _getEventName(int? matchId) async {
    if (matchId == null) return 'Unknown Event';

    try {
      final db = await _db.database;
      final results = await db.query(
        'cached_events',
        where: 'id = ?',
        whereArgs: [matchId],
        limit: 1,
      );

      if (results.isNotEmpty) {
        final homeTeam = results.first['home_team']?.toString() ?? '';
        final awayTeam = results.first['away_team']?.toString() ?? '';
        if (homeTeam.isNotEmpty && awayTeam.isNotEmpty) {
          return '$homeTeam vs $awayTeam';
        }
      }
    } catch (e) {
      debugPrint('Error fetching event name: $e');
    }

    return 'Event #$matchId';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isPrinting && _printTotal > 0
            ? Text('Printing $_printProgress/$_printTotal...')
            : const Text('Reprint Tickets'),
        actions: [
          if (_selectedTickets.isNotEmpty && !_isPrinting)
            TextButton.icon(
              onPressed: _reprintSelected,
              icon: const Icon(Icons.print, color: Colors.white),
              label: Text(
                'Print ${_selectedTickets.length}',
                style: const TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search tickets',
                hintText: 'Ticket ID, customer name, or match ID',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _filterTickets('');
                        },
                      )
                    : null,
              ),
              onChanged: _filterTickets,
            ),
          ),

          // Tickets List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredTickets.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.receipt_long,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchController.text.isEmpty
                              ? 'No tickets found'
                              : 'No matching tickets',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _filteredTickets.length,
                    itemBuilder: (context, index) {
                      final ticket = _filteredTickets[index];
                      final ticketId = ticket['ticket_id']?.toString() ?? '';
                      final isSelected = _selectedTickets.contains(ticketId);

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: ListTile(
                          leading: Checkbox(
                            value: isSelected,
                            onChanged: (value) {
                              setState(() {
                                if (value == true) {
                                  _selectedTickets.add(ticketId);
                                } else {
                                  _selectedTickets.remove(ticketId);
                                }
                              });
                            },
                          ),
                          title: Text(
                            ticket['customer_name'] ?? 'Guest',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text('Ticket ID: $ticketId'),
                              Text('Match ID: ${ticket['matche_id']}'),
                              Text(
                                'Amount: ₦${ticket['amount']}',
                                style: TextStyle(
                                  color: Colors.green.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'Status: ${ticket['status'] ?? 'sold'}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.print),
                            onPressed: _isPrinting
                                ? null
                                : () => _reprintTicket(ticket),
                            tooltip: 'Reprint',
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: _isPrinting
          ? const FloatingActionButton(
              onPressed: null,
              child: CircularProgressIndicator(color: Colors.white),
            )
          : null,
    );
  }
}
