import 'package:dio/dio.dart';
import 'package:myapp/data/services/api_client.dart';
import 'package:myapp/data/models/ticket_model.dart';

class TicketApi {
  Dio get _dio => ApiClient.instance.dio;

  Future<List<Ticket>> getTickets(String eventId) async {
    // TODO: Replace with real endpoint call
    // final res = await _dio.get('/events/$eventId/tickets');
    await Future.delayed(const Duration(milliseconds: 200));
    return [
      Ticket(
        id: '1',
        eventId: eventId,
        type: 'General Admission',
        price: 50.00,
        quantity: 100,
      ),
      Ticket(
        id: '2',
        eventId: eventId,
        type: 'VIP',
        price: 150.00,
        quantity: 25,
      ),
      Ticket(
        id: '3',
        eventId: eventId,
        type: 'Student',
        price: 25.00,
        quantity: 50,
      ),
    ];
  }
}
