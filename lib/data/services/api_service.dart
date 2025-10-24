import 'dart:async';

import 'package:myapp/data/models/event_model.dart';
import 'package:myapp/data/models/ticket_model.dart';

class ApiService {
  Future<bool> login(String username, String password) async {
    // Simulate a network call
    await Future.delayed(const Duration(seconds: 2));

    // Dummy authentication logic
    if (username == 'admin' && password == 'password') {
      return true;
    } else {
      return false;
    }
  }

  Future<List<Event>> getEvents() async {
    // Simulate a network call
    await Future.delayed(const Duration(seconds: 2));

    return [
      Event(
        id: '1',
        title: 'Flutter Developer Conference',
        description: 'The biggest Flutter conference in the world.',
        date: '2024-12-15',
        category: 'Conference',
        location: 'San Francisco, CA',
        imageUrl: 'https://picsum.photos/seed/event1/300/200',
      ),
      Event(
        id: '2',
        title: 'Dart Programming Workshop',
        description: 'Learn Dart from the experts.',
        date: '2024-11-20',
        category: 'Workshop',
        location: 'New York, NY',
        imageUrl: 'https://picsum.photos/seed/event2/300/200',
      ),
      Event(
        id: '3',
        title: 'Firebase Summit 2024',
        description: 'The latest news and updates from Firebase.',
        date: '2024-10-25',
        category: 'Conference',
        location: 'Mountain View, CA',
        imageUrl: 'https://picsum.photos/seed/event3/300/200',
      ),
    ];
  }

  Future<List<Ticket>> getTickets(String eventId) async {
    // Simulate a network call
    await Future.delayed(const Duration(seconds: 1));

    // Dummy ticket data
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
