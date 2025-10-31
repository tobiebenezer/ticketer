import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:myapp/data/services/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myapp/core/constants/network_constants.dart';

class AuthApi {
  final Dio _dio = ApiClient.instance.dio;

  Future<bool> login(String username, String password) async {
    try {
      final response = await _dio.post(
        '/login',
        data: {
          'username': username,
          'password': password,
        },
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final token = data is Map<String, dynamic>
            ? (data['token'] as String?)
            : (jsonDecode(jsonEncode(data)) as Map<String, dynamic>)['token'] as String?;
        if (token != null && token.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(kAuthTokenKey, token);
          return true;
        }
      }
      return false;
    } on DioException {
      return false;
    }
  }

  Future<Response> logout({String? overrideToken}) async {
    final headers = <String, dynamic>{};
    if (overrideToken != null) {
      headers['Authorization'] = 'Bearer $overrideToken';
    }
    final response = await _dio.post('/logout', options: Options(headers: headers));
    return response;
  }
}
