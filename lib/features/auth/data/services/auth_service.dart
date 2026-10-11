import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../../../core/network/api_constants.dart';
import '../../../../core/network/dio_client.dart';
import '../auth_exception.dart';
import '../models/auth_models.dart';
import '../models/user_model.dart';

/// Thin HTTP layer for authentication. No UI logic here; errors are mapped
/// to [AuthException] with user-friendly messages.
class AuthService {
  final Dio _dio;

  AuthService({Dio? dio}) : _dio = dio ?? DioClient.create();

  /// `POST /users` — creates a new account.
  ///
  /// The API requires email, name, password, role and avatar. The UI only
  /// collects the first three; [role]/[avatar] default to valid values.
  Future<UserModel> signUp({
    required String name,
    required String email,
    required String password,
    String role = ApiConstants.defaultRole,
    String avatar = ApiConstants.defaultAvatar,
  }) async {
    final request = SignUpRequest(
      name: name.trim(),
      email: email.trim(),
      password: password,
      role: role,
      avatar: avatar,
    );
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        ApiConstants.users,
        data: request.toJson(),
      );
      final data = response.data;
      if (data == null) {
        throw const AuthException('Registration failed. Please try again.');
      }
      return UserModel.fromJson(Map<String, dynamic>.from(data));
    } on DioException catch (e) {
      throw _mapSignUpError(e);
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException('Registration failed. Please try again.');
    }
  }

  /// `POST /auth/login` — authenticates and returns token pair.
  Future<AuthTokens> login({
    required String email,
    required String password,
  }) async {
    final request = LoginRequest(email: email.trim(), password: password);
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        ApiConstants.login,
        data: request.toJson(),
      );
      final data = response.data;
      if (data == null) {
        throw const AuthException('Login failed. Please try again.');
      }
      try {
        return AuthTokens.fromJson(Map<String, dynamic>.from(data));
      } on FormatException {
        throw const AuthException('Login failed. Unexpected server response.');
      }
    } on DioException catch (e) {
      throw _mapLoginError(e);
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException('Login failed. Please try again.');
    }
  }

  /// `GET /auth/profile` — requires a valid Bearer access token.
  Future<UserModel> getProfile(String accessToken) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        ApiConstants.profile,
        options: DioClient.authOptions(accessToken),
      );
      final data = response.data;
      if (data == null) {
        throw const AuthException(
          'Could not load your profile. Please try again.',
          statusCode: 500,
        );
      }
      return UserModel.fromJson(Map<String, dynamic>.from(data));
    } on DioException catch (e) {
      throw _mapProfileError(e);
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException(
        'Could not load your profile. Please try again.',
      );
    }
  }

  /// `POST /auth/refresh-token` — exchanges a refresh token for a new pair.
  Future<AuthTokens> refreshToken(String refreshTokenValue) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        ApiConstants.refreshToken,
        data: {'refreshToken': refreshTokenValue},
      );
      final data = response.data;
      if (data == null) {
        throw const AuthException(
          'Session expired. Please log in again.',
          statusCode: 401,
        );
      }
      try {
        return AuthTokens.fromJson(Map<String, dynamic>.from(data));
      } on FormatException {
        throw const AuthException(
          'Session expired. Please log in again.',
          statusCode: 401,
        );
      }
    } on DioException catch (e) {
      throw _mapRefreshError(e);
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException('Session expired. Please log in again.');
    }
  }

  /// `POST /users/is-available` — checks email availability.
  ///
  /// Note: as of verification (Oct 2026) this endpoint always returns
  /// `{"isAvailable": false}`, even for unused emails, so callers must not
  /// block registration based on it. Kept for API completeness.
  Future<bool> isEmailAvailable(String email) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        ApiConstants.usersIsAvailable,
        data: {'email': email.trim()},
      );
      final data = response.data;
      if (data != null && data['isAvailable'] is bool) {
        return data['isAvailable'] as bool;
      }
      return true;
    } on DioException catch (e) {
      throw _mapNetworkError(
        e,
        fallback: 'Could not check email availability.',
      );
    }
  }

  // -- error mapping -------------------------------------------------------

  AuthException _mapSignUpError(DioException e) {
    final status = e.response?.statusCode;
    if (_isTimeout(e)) {
      return const AuthException(
        'Connection timed out. Please check your internet and try again.',
      );
    }
    if (_isNetworkError(e)) {
      return const AuthException(
        'No internet connection. Please check your network and try again.',
      );
    }
    if (status == 400) {
      return AuthException(
        _backendMessage(
          e,
          'Registration failed. '
          'Please check your details and try again.',
        ),
      );
    }
    if (status == 409) {
      return const AuthException(
        'This email is already registered. Please log in instead.',
        statusCode: 409,
      );
    }
    if (status != null && status >= 500) {
      return const AuthException('Server error. Please try again later.');
    }
    final backend = _backendMessageOrNull(e);
    if (backend != null) {
      // The API currently allows duplicate emails (returns 201), but if a
      // future version rejects them, surface it clearly.
      if (backend.toLowerCase().contains('already') ||
          backend.toLowerCase().contains('duplicate') ||
          backend.toLowerCase().contains('unique')) {
        return AuthException(
          'This email is already registered. Please log in instead.',
          statusCode: status,
        );
      }
      return AuthException(backend, statusCode: status);
    }
    return AuthException(
      'Registration failed. Please try again.',
      statusCode: status,
    );
  }

  AuthException _mapLoginError(DioException e) {
    final status = e.response?.statusCode;
    if (_isTimeout(e)) {
      return const AuthException(
        'Connection timed out. Please check your internet and try again.',
      );
    }
    if (_isNetworkError(e)) {
      return const AuthException(
        'No internet connection. Please check your network and try again.',
      );
    }
    if (status == 400) {
      return AuthException(
        _backendMessage(e, 'Invalid email or password. Please try again.'),
        statusCode: 400,
      );
    }
    if (status == 401) {
      return const AuthException(
        'Incorrect email or password. Please try again.',
        statusCode: 401,
      );
    }
    if (status != null && status >= 500) {
      return const AuthException('Server error. Please try again later.');
    }
    final backend = _backendMessageOrNull(e);
    if (backend != null) return AuthException(backend, statusCode: status);
    return AuthException('Login failed. Please try again.', statusCode: status);
  }

  AuthException _mapProfileError(DioException e) {
    final status = e.response?.statusCode;
    if (_isTimeout(e)) {
      return const AuthException(
        'Connection timed out while loading your profile.',
      );
    }
    if (_isNetworkError(e)) {
      return const AuthException(
        'No internet connection. Please check your network and try again.',
      );
    }
    if (status == 401) {
      return const AuthException(
        'Session expired. Please log in again.',
        statusCode: 401,
      );
    }
    final backend = _backendMessageOrNull(e);
    if (backend != null) return AuthException(backend, statusCode: status);
    return AuthException(
      'Could not load your profile. Please try again.',
      statusCode: status,
    );
  }

  AuthException _mapRefreshError(DioException e) {
    if (_isTimeout(e) || _isNetworkError(e)) {
      return const AuthException(
        'No internet connection. Please check your network and try again.',
      );
    }
    return AuthException(
      _backendMessageOrNull(e) ?? 'Session expired. Please log in again.',
      statusCode: e.response?.statusCode ?? 401,
    );
  }

  AuthException _mapNetworkError(DioException e, {required String fallback}) {
    if (_isTimeout(e)) {
      return const AuthException(
        'Connection timed out. Please check your internet and try again.',
      );
    }
    if (_isNetworkError(e)) {
      return const AuthException(
        'No internet connection. Please check your network and try again.',
      );
    }
    final backend = _backendMessageOrNull(e);
    return AuthException(
      backend ?? fallback,
      statusCode: e.response?.statusCode,
    );
  }

  bool _isTimeout(DioException e) {
    return e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e is TimeoutException;
  }

  bool _isNetworkError(DioException e) {
    return e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.unknown ||
        e.error is SocketException;
  }

  String? _backendMessageOrNull(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) return message;
      if (message is List && message.isNotEmpty) {
        return message.map((m) => m.toString()).join('\n');
      }
    } else if (data is String && data.trim().isNotEmpty) {
      return data;
    }
    return null;
  }

  String _backendMessage(DioException e, String fallback) {
    return _backendMessageOrNull(e) ?? fallback;
  }
}
