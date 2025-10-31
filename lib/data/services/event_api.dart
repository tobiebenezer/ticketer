import 'package:dio/dio.dart';
import 'package:myapp/data/services/api_client.dart';
import 'package:myapp/data/models/event_model.dart';

class EventApi {
  Dio get _dio => ApiClient.instance.dio;

  Future<List<Event>> getEvents({String? status}) async {
    try {
      final response = await _dio.get(
        '/matches',
        queryParameters: status != null ? {'status': status} : null,
      );
      
      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final events = (data['data'] as List)
            .map((json) => Event.fromJson(json))
            .toList();
        return events;
      }
      throw Exception('Failed to load events');
    } on DioException catch (e) {
      throw Exception('Failed to load events: ${e.message}');
    }
  }
}
