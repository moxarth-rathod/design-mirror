/// DesignMirror AI — API Service
///
/// Centralized HTTP client built on Dio.
///
/// MENTOR MOMENT: Why Dio instead of http?
/// ───────────────────────────────────────
/// Dart's built-in `http` package is fine for simple requests, but Dio gives us:
///   • Interceptors — automatically attach JWT to every request
///   • Token refresh — if a 401 comes back, automatically refresh and retry
///   • Request/response logging — see exactly what's being sent/received
///   • Timeout handling — don't hang forever on bad connections
///
/// PATTERN: Interceptor Chain
/// ─────────────────────────
/// Every HTTP request passes through a chain of interceptors:
///   Request → [Auth Interceptor] → [Logging Interceptor] → Server
///   Response ← [Error Interceptor] ← [Logging Interceptor] ← Server
///
/// This is the same pattern used by OkHttp (Android) and Axios (JavaScript).

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';

import '../config/app_config.dart';
import '../models/token_model.dart';

class ApiService {
  late final Dio _dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final Logger _logger = Logger();

  ApiService() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.apiUrl,
        connectTimeout: AppConfig.connectTimeout,
        receiveTimeout: AppConfig.receiveTimeout,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    // Add interceptors
    _dio.interceptors.add(_authInterceptor());
    _dio.interceptors.add(_loggingInterceptor());
  }

  // ── Auth Interceptor ──────────────────────────

  /// Automatically attaches the JWT access token to every request.
  /// If a 401 response comes back, attempts to refresh the token and retry.
  Interceptor _authInterceptor() {
    return InterceptorsWrapper(
      onRequest: (options, handler) async {
        // Skip auth header for public endpoints
        final publicPaths = ['/auth/login', '/auth/signup', '/health'];
        final isPublic = publicPaths.any((p) => options.path.contains(p));

        if (!isPublic) {
          final token = await _storage.read(key: AppConfig.accessTokenKey);
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        // If we get a 401, try refreshing the token
        if (error.response?.statusCode == 401) {
          final refreshed = await _tryRefreshToken();
          if (refreshed) {
            // Retry the original request with the new token
            final token = await _storage.read(key: AppConfig.accessTokenKey);
            error.requestOptions.headers['Authorization'] = 'Bearer $token';

            try {
              final response = await _dio.fetch(error.requestOptions);
              return handler.resolve(response);
            } catch (e) {
              return handler.next(error);
            }
          }
        }
        handler.next(error);
      },
    );
  }

  /// Attempt to refresh the access token using the stored refresh token.
  Future<bool> _tryRefreshToken() async {
    try {
      final refreshToken =
          await _storage.read(key: AppConfig.refreshTokenKey);
      if (refreshToken == null) return false;

      // Use a separate Dio instance to avoid interceptor loops
      final refreshDio = Dio(BaseOptions(baseUrl: AppConfig.apiUrl));
      final response = await refreshDio.post(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );

      if (response.statusCode == 200) {
        final tokens = TokenModel.fromJson(response.data);
        await saveTokens(tokens);
        _logger.i('Token refreshed successfully');
        return true;
      }
    } catch (e) {
      _logger.e('Token refresh failed: $e');
    }
    return false;
  }

  // ── Logging Interceptor ───────────────────────

  Interceptor _loggingInterceptor() {
    return InterceptorsWrapper(
      onRequest: (options, handler) {
        _logger.d('→ ${options.method} ${options.path}');
        handler.next(options);
      },
      onResponse: (response, handler) {
        _logger.d('← ${response.statusCode} ${response.requestOptions.path}');
        handler.next(response);
      },
      onError: (error, handler) {
        _logger.e(
          '✕ ${error.response?.statusCode} ${error.requestOptions.path}: '
          '${error.message}',
        );
        handler.next(error);
      },
    );
  }

  // ── Token Management ──────────────────────────

  Future<void> saveTokens(TokenModel tokens) async {
    await _storage.write(
        key: AppConfig.accessTokenKey, value: tokens.accessToken);
    await _storage.write(
        key: AppConfig.refreshTokenKey, value: tokens.refreshToken);
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: AppConfig.accessTokenKey);
    await _storage.delete(key: AppConfig.refreshTokenKey);
  }

  Future<bool> hasTokens() async {
    final token = await _storage.read(key: AppConfig.accessTokenKey);
    return token != null;
  }

  // ── HTTP Methods ──────────────────────────────

  /// GET request with optional query parameters.
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParams,
  }) async {
    return _dio.get(path, queryParameters: queryParams);
  }

  /// POST request with JSON body.
  Future<Response> post(
    String path, {
    dynamic data,
  }) async {
    return _dio.post(path, data: data);
  }

  /// POST with form data (used for OAuth2 login).
  Future<Response> postForm(
    String path, {
    required Map<String, dynamic> data,
  }) async {
    return _dio.post(
      path,
      data: FormData.fromMap(data),
      options: Options(contentType: 'application/x-www-form-urlencoded'),
    );
  }

  /// PUT request with JSON body.
  Future<Response> put(
    String path, {
    dynamic data,
  }) async {
    return _dio.put(path, data: data);
  }

  /// PATCH request with JSON body.
  Future<Response> patch(
    String path, {
    dynamic data,
  }) async {
    return _dio.patch(path, data: data);
  }

  /// DELETE request.
  Future<Response> delete(String path) async {
    return _dio.delete(path);
  }
}

