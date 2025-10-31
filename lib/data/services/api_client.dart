import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myapp/core/constants/network_constants.dart';

class ApiClient {
  /// Optional global callback invoked when a 401 is encountered.
  /// Set this in app init to redirect to login.
  static void Function()? onUnauthorized;
  static bool _unauthorizedHandled = false;

  ApiClient._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: kBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
        headers: {
          'Accept': 'application/json',
        },
      ),
    );

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString(kAuthTokenKey);
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (e, handler) async {
        final status = e.response?.statusCode;
        if (status == 401) {
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove(kAuthTokenKey);
          } catch (_) {}

          if (!_unauthorizedHandled) {
            _unauthorizedHandled = true;
            // Schedule reset after short delay to allow subsequent logins
            Future.delayed(const Duration(seconds: 2), () => _unauthorizedHandled = false);
            // Trigger global redirect if provided
            onUnauthorized?.call();
          }
        }
        handler.next(e);
      },
    ));
  }

  static final ApiClient instance = ApiClient._internal();
  late final Dio _dio;

  Dio get dio => _dio;
}
