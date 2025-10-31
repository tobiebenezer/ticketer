import 'package:dio/dio.dart';
import 'package:myapp/data/services/api_client.dart';
import 'package:myapp/data/models/ticket_model.dart';
import 'package:myapp/data/models/ticket_type.dart';
import 'package:myapp/data/models/ticket_validation_result.dart';

class TicketApi {
  Dio get _dio => ApiClient.instance.dio;

  Future<List<Ticket>> getTickets(int matchId) async {
    try {
      final response = await _dio.get(
        '/tickets',
        queryParameters: {'match_id': matchId},
      );
      
      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        return (data['tickets'] as List)
            .map((json) => Ticket.fromJson(json))
            .toList();
      }
      throw Exception('Failed to load tickets');
    } on DioException catch (e) {
      throw Exception('Failed to load tickets: ${e.message}');
    }
  }

  Future<List<Ticket>> bookTicket({
    required int matchId,
    required int ticketTypeId,
    required int quantity,
    required double amount,
    String? customerName,
  }) async {
    try {
      final response = await _dio.post(
        '/tickets',
        data: {
          'match_id': matchId,
          'ticket_type_id': ticketTypeId,
          'quantity': quantity,
          'amount': amount,
          'customer_name': customerName,
        },
      );
      
      if (response.statusCode == 201) {
        final data = response.data as Map<String, dynamic>;
        return (data['tickets'] as List)
            .map((json) => Ticket.fromJson(json))
            .toList();
      }
      throw Exception('Failed to book tickets');
    } on DioException catch (e) {
      throw Exception('Failed to book tickets: ${e.message}');
    }
  }

  Future<List<TicketType>> getTicketTypes() async {
    print("getTicketTypes");
    // try {
      final response = await _dio.get('/ticket-types');
      if (response.statusCode == 200) {
        final data = response.data;
        final List<dynamic> list;
        if (data is List) {
          list = data;
        } else if (data is Map<String, dynamic> && data['data'] is List) {
          list = data['data'] as List;
        } else {
          list = const [];
        }
        return list.map((e) => TicketType.fromJson(e as Map<String, dynamic>)).toList();
      }

      return [];
    //   throw Exception('Failed to load ticket types');
    // } on DioException catch (e) {
    //   throw Exception('Failed to load ticket types: ${e.message}');
    // }
  }

  Future<TicketValidationResult> validateTicket(String reference) async {
    try {
      final response = await _dio.get('/validate-ticket/$reference');
      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        return TicketValidationResult.fromJson(data);
      }
      throw Exception('Failed to validate ticket');
    } on DioException catch (e) {
      throw Exception('Failed to validate ticket: ${e.message}');
    }
  }

  Future<TicketValidationResult> markTicket(String reference) async {
    try {
      final response = await _dio.get('/mark-ticket/$reference');
      if (response.data is Map<String, dynamic>) {
        return TicketValidationResult.fromJson(response.data as Map<String, dynamic>);
      }
      return TicketValidationResult(
        message: 'Ticket marked successfully',
        type: 'success',
        status: '',
        id: reference,
      );
    } on DioException catch (e) {
      throw Exception('Failed to update ticket status: ${e.message}');
    }
  }
}