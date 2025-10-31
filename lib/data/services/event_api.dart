import 'package:dio/dio.dart';
import 'package:myapp/data/services/api_client.dart';
import 'package:myapp/data/models/event_model.dart';

class EventApi {
  Dio get _dio => ApiClient.instance.dio;

  Future<List<Event>> getEvents() async {
    // TODO: Replace with real endpoint call, e.g.:
    // final res = await _dio.get('/events');
    // return (res.data as List).map((e) => Event.fromJson(e)).toList();
    await Future.delayed(const Duration(milliseconds: 300));
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
}
