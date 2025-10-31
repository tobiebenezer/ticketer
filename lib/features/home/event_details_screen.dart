import 'package:flutter/material.dart';
import 'package:myapp/data/models/event_model.dart';
import 'package:myapp/data/models/ticket_type.dart';
import 'package:myapp/data/services/ticket_api.dart';
import 'package:myapp/features/checkout/sell_ticket_screen.dart';

class EventDetailsScreen extends StatefulWidget {
  final Event event;

  const EventDetailsScreen({super.key, required this.event});

  @override
  State<EventDetailsScreen> createState() => _EventDetailsScreenState();
}

class _EventDetailsScreenState extends State<EventDetailsScreen> {
  final TicketApi _ticketApi = TicketApi();
  List<TicketType> _ticketTypes = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchTicketTypes();
  }

  Future<void> _fetchTicketTypes() async {
    // try {
      final ticketTypes = await _ticketApi.getTicketTypes();
      setState(() {
        _ticketTypes = ticketTypes;
        _isLoading = false;
      });
    // } catch (e) {
    //   setState(() {
    //     _error = 'Failed to load tickets. Please try again later.';
    //     _isLoading = false;
    //   });
    // }
  }

  void _navigateToSellTicket(TicketType ticketType) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SellTicketScreen(event: widget.event, ticketType: ticketType),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.event.homeTeam} vs ${widget.event.awayTeam}')),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Image.asset(
              'assets/images/event_art.jpg',
              height: 250,
              fit: BoxFit.cover,
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${widget.event.homeTeam} vs ${widget.event.awayTeam}',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 16.0),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 20.0),
                      const SizedBox(width: 8.0),
                      Text(
                        widget.event.matchDate,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8.0),
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 20.0),
                      const SizedBox(width: 8.0),
                      Text(
                        widget.event.venue,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24.0),
                  Text(
                    'About this event',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8.0),
                  Text(
                    widget.event.competition,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24.0),
                  Text(
                    'Available Tickets',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8.0),
                  _buildTicketList(),
                  // const SizedBox(height: 32.0),
                  // ElevatedButton(
                  //   onPressed: _navigateToSellTicket,
                  //   style: ElevatedButton.styleFrom(
                  //     minimumSize: const Size(double.infinity, 50),
                  //   ),
                  //   child: const Text('Sell Ticket'),
                  // ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTicketList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Text(_error!, style: const TextStyle(color: Colors.red));
    }

    if (_ticketTypes.isEmpty) {
      return const Text('No ticket types available.');
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _ticketTypes.length,
      itemBuilder: (context, index) {
        final ticketType = _ticketTypes[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4.0),
          child: ListTile(
            onTap: () => _navigateToSellTicket(ticketType),
            title: Text(ticketType.name,
                style: Theme.of(context).textTheme.titleMedium),
            subtitle: Text('₦${ticketType.price.toStringAsFixed(2)}'),
            trailing: const Icon(Icons.chevron_right),
          ),
        );
      },
    );
  }
}
