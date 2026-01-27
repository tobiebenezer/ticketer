import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:myapp/core/services/device_crypto_service.dart';
import 'package:myapp/core/utils/device_info_util.dart';
import 'package:myapp/data/services/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myapp/core/constants/network_constants.dart';


class AuthApi {
  final Dio _dio = ApiClient.instance.dio;
  final DeviceCryptoService _deviceCrypto = DeviceCryptoService();

  /// Login with device registration
  ///
  /// Sends device UID and type to server for device tracking
  Future<LoginResult> login(String username, String password) async {
    try {
      // Get device information (optional - login works without it)
      DeviceInfo? deviceInfo;
      try {
        deviceInfo = await DeviceInfoUtil.getDeviceInfo();
      } catch (e) {
        // Device info not critical for login
        print('Failed to get device info: $e');
      }

      final Map<String, dynamic> requestData = {
        'email': username,
        'password': password,
      };

      // Add device info if available
      if (deviceInfo != null) {
        final keys = await _deviceCrypto.ensureKeyPair();
        requestData['device_uid'] = deviceInfo.uid;
        requestData['device_type'] =
            'hybrid'; // Backend expects: sales, validator, or hybrid
        requestData['device_public_key'] = keys.publicKeyBase64;
        requestData['device_key_version'] = keys.keyVersion;
      }

      final response = await _dio.post('/login', data: requestData);

      print('Login response status: ${response}');
      print('Login response data: ${response.data}');

      if (response.statusCode == 200) {
        final data = response.data;
        final token = data is Map<String, dynamic>
            ? (data['token'] as String?)
            : (jsonDecode(jsonEncode(data)) as Map<String, dynamic>)['token']
                  as String?;

        if (token != null && token.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(kAuthTokenKey, token);

          try {
            // Persist user profile if available
            final map = data is Map<String, dynamic>
                ? data
                : (jsonDecode(jsonEncode(data)) as Map<String, dynamic>);
            final user = (map['user'] is Map<String, dynamic>)
                ? map['user']
                : map;
            await prefs.setString('kUserProfileJson', jsonEncode(user));

            // Store user capabilities
            await prefs.setBool(
              'can_sell_offline',
              user['can_sell_offline'] ?? false,
            );
            await prefs.setBool('can_validate', user['can_validate'] ?? false);
          } catch (_) {}

          return LoginResult.success(
            token: token,
            userData: data is Map<String, dynamic> ? data : {},
          );
        }
      }
      return LoginResult.error('Invalid credentials');
    } on DioException catch (e) {
      print('DioException: ${e.type}');
      print('DioException message: ${e.message}');
      print('DioException response: ${e.response?.data}');
      print('DioException status: ${e.response?.statusCode}');

      // Extract error message from response if available
      String errorMsg = 'Login failed';
      if (e.response?.data != null) {
        final data = e.response!.data;
        if (data is Map<String, dynamic>) {
          errorMsg = data['message'] ?? errorMsg;
        }
      }
      return LoginResult.error(errorMsg);
    } catch (e) {
      print('General exception: $e');
      return LoginResult.error('Login failed: $e');
    }
  }

  Future<Response> logout({String? overrideToken}) async {
    final headers = <String, dynamic>{};
    if (overrideToken != null) {
      headers['Authorization'] = 'Bearer $overrideToken';
    }
    final response = await _dio.post(
      '/logout',
      options: Options(headers: headers),
    );
    return response;
  }
}

/// Result of login attempt
class LoginResult {
  final bool isSuccess;
  final String? token;
  final Map<String, dynamic>? userData;
  final String? errorMessage;

  LoginResult._({
    required this.isSuccess,
    this.token,
    this.userData,
    this.errorMessage,
  });

  factory LoginResult.success({
    required String token,
    required Map<String, dynamic> userData,
  }) {
    return LoginResult._(isSuccess: true, token: token, userData: userData);
  }

  factory LoginResult.error(String message) {
    return LoginResult._(isSuccess: false, errorMessage: message);
  }
}
