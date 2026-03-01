/// DesignMirror AI — Auth Repository
///
/// PATTERN: Repository Pattern
/// ───────────────────────────
/// The Repository sits between the BLoC (state management) and the
/// API service. It translates raw HTTP responses into typed Dart models.
///
/// Why not call ApiService directly from BLoC?
///   • The BLoC shouldn't know about HTTP status codes or Dio exceptions.
///   • If we switch from REST to GraphQL, only the repository changes.
///   • We can easily mock this class for unit testing.

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';

import '../models/token_model.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';

class AuthRepository {
  final ApiService _api;
  final Logger _logger = Logger();

  AuthRepository({required ApiService apiService}) : _api = apiService;

  /// Register a new user account.
  ///
  /// Returns the created [UserModel] on success.
  /// Throws a descriptive error string on failure.
  Future<UserModel> signup({
    required String email,
    required String fullName,
    required String password,
  }) async {
    try {
      final response = await _api.post(
        '/auth/signup',
        data: {
          'email': email,
          'full_name': fullName,
          'password': password,
        },
      );
      return UserModel.fromJson(response.data);
    } on DioException catch (e) {
      throw _extractError(e);
    }
  }

  /// Log in with email and password.
  ///
  /// On success, stores JWT tokens and returns the token pair.
  Future<TokenModel> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _api.postForm(
        '/auth/login',
        data: {
          'username': email, // OAuth2 form expects 'username'
          'password': password,
        },
      );
      final tokens = TokenModel.fromJson(response.data);
      await _api.saveTokens(tokens);
      _logger.i('Login successful for $email');
      return tokens;
    } on DioException catch (e) {
      throw _extractError(e);
    }
  }

  /// Get the currently authenticated user's profile.
  Future<UserModel> getCurrentUser() async {
    try {
      final response = await _api.get('/auth/me');
      return UserModel.fromJson(response.data);
    } on DioException catch (e) {
      throw _extractError(e);
    }
  }

  /// Log out — clear stored tokens.
  Future<void> logout() async {
    await _api.clearTokens();
    _logger.i('User logged out');
  }

  /// Update the current user's profile (e.g. full_name).
  Future<UserModel> updateProfile({String? fullName}) async {
    try {
      final data = <String, dynamic>{};
      if (fullName != null) data['full_name'] = fullName;
      final response = await _api.patch('/auth/me', data: data);
      return UserModel.fromJson(response.data);
    } on DioException catch (e) {
      throw _extractError(e);
    }
  }

  /// Change the user's password.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      await _api.post('/auth/change-password', data: {
        'current_password': currentPassword,
        'new_password': newPassword,
      });
    } on DioException catch (e) {
      throw _extractError(e);
    }
  }

  /// Check if the user has stored tokens (may still be expired).
  Future<bool> isLoggedIn() async {
    return await _api.hasTokens();
  }

  /// Extract a human-readable error message from a Dio exception.
  String _extractError(DioException e) {
    if (e.response?.data != null && e.response!.data is Map) {
      final detail = e.response!.data['detail'];
      if (detail != null) return detail.toString();
    }
    if (e.type == DioExceptionType.connectionTimeout) {
      return 'Connection timed out. Please check your internet.';
    }
    if (e.type == DioExceptionType.connectionError) {
      return 'Cannot reach the server. Is the backend running?';
    }
    return 'Something went wrong. Please try again.';
  }
}

