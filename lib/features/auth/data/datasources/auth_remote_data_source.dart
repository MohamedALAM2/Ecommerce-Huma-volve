import 'package:dio/dio.dart';

import '../../../../core/error/api_exception.dart';
import '../../../../core/error/dio_error_parser.dart';
import '../../../../core/network/api_constants.dart';
import '../../../../core/network/dio_client.dart';
import '../models/auth_models.dart';
import '../models/user_model.dart';

/// Authentication HTTP calls. Returns DTOs, never domain entities, and
/// throws [ApiException] (never raw `DioException`) with endpoint-specific,
/// user-friendly messages. Repository implementations translate these into
/// typed domain failures.
class AuthRemoteDataSource {
  final Dio _dio;

  AuthRemoteDataSource({Dio? dio}) : _dio = dio ?? DioClient.create();

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
        throw const ApiException.unknown(
          'Registration failed. Please try again.',
        );
      }
      return UserModel.fromJson(Map<String, dynamic>.from(data));
    } on DioException catch (e) {
      throw _mapSignUpError(e);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException.unknown(
        'Registration failed. Please try again.',
      );
    }
  }

  /// `POST /auth/login` — authenticates and returns the token pair.
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
        throw const ApiException.unknown('Login failed. Please try again.');
      }
      try {
        return AuthTokens.fromJson(Map<String, dynamic>.from(data));
      } on FormatException {
        throw const ApiException.unknown(
          'Login failed. Unexpected server response.',
        );
      }
    } on DioException catch (e) {
      throw _mapLoginError(e);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException.unknown('Login failed. Please try again.');
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
        throw const ApiException.unknown(
          'Could not load your profile. Please try again.',
        );
      }
      return UserModel.fromJson(Map<String, dynamic>.from(data));
    } on DioException catch (e) {
      throw _mapProfileError(e);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException.unknown(
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
        throw const ApiException.response(
          401,
          'Session expired. Please log in again.',
        );
      }
      try {
        return AuthTokens.fromJson(Map<String, dynamic>.from(data));
      } on FormatException {
        throw const ApiException.response(
          401,
          'Session expired. Please log in again.',
        );
      }
    } on DioException catch (e) {
      throw _mapRefreshError(e);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException.unknown('Session expired. Please log in again.');
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

  // -- error mapping (messages preserved from the previous implementation) --

  ApiException _mapSignUpError(DioException e) {
    final status = dioStatusCode(e);
    if (isTimeoutError(e)) {
      return const ApiException.timeout(
        'Connection timed out. Please check your internet and try again.',
      );
    }
    if (isNetworkError(e)) {
      return const ApiException.network(
        'No internet connection. Please check your network and try again.',
      );
    }
    if (status == 400) {
      return ApiException.response(
        status,
        dioBackendMessage(e) ??
            'Registration failed. '
                'Please check your details and try again.',
      );
    }
    if (status == 409) {
      return const ApiException.response(
        409,
        'This email is already registered. Please log in instead.',
      );
    }
    if (status != null && status >= 500) {
      return ApiException.response(
        status,
        'Server error. Please try again later.',
      );
    }
    final backend = dioBackendMessage(e);
    if (backend != null) {
      // The API currently allows duplicate emails (returns 201), but if a
      // future version rejects them, surface it clearly.
      if (backend.toLowerCase().contains('already') ||
          backend.toLowerCase().contains('duplicate') ||
          backend.toLowerCase().contains('unique')) {
        return ApiException.response(
          status,
          'This email is already registered. Please log in instead.',
        );
      }
      return ApiException.response(status, backend);
    }
    return ApiException.response(
      status,
      'Registration failed. Please try again.',
    );
  }

  ApiException _mapLoginError(DioException e) {
    final status = dioStatusCode(e);
    if (isTimeoutError(e)) {
      return const ApiException.timeout(
        'Connection timed out. Please check your internet and try again.',
      );
    }
    if (isNetworkError(e)) {
      return const ApiException.network(
        'No internet connection. Please check your network and try again.',
      );
    }
    if (status == 400) {
      return ApiException.response(
        400,
        dioBackendMessage(e) ?? 'Invalid email or password. Please try again.',
      );
    }
    if (status == 401) {
      return const ApiException.response(
        401,
        'Incorrect email or password. Please try again.',
      );
    }
    if (status != null && status >= 500) {
      return ApiException.response(
        status,
        'Server error. Please try again later.',
      );
    }
    final backend = dioBackendMessage(e);
    if (backend != null) return ApiException.response(status, backend);
    return ApiException.response(status, 'Login failed. Please try again.');
  }

  ApiException _mapProfileError(DioException e) {
    final status = dioStatusCode(e);
    if (isTimeoutError(e)) {
      return const ApiException.timeout(
        'Connection timed out while loading your profile.',
      );
    }
    if (isNetworkError(e)) {
      return const ApiException.network(
        'No internet connection. Please check your network and try again.',
      );
    }
    if (status == 401) {
      return const ApiException.response(
        401,
        'Session expired. Please log in again.',
      );
    }
    final backend = dioBackendMessage(e);
    if (backend != null) return ApiException.response(status, backend);
    return ApiException.response(
      status,
      'Could not load your profile. Please try again.',
    );
  }

  ApiException _mapRefreshError(DioException e) {
    if (isTimeoutError(e) || isNetworkError(e)) {
      // Connectivity problems carry no status: stored credentials must be
      // preserved (see RestoreSessionUseCase), never treated as revoked.
      return const ApiException.network(
        'No internet connection. Please check your network and try again.',
      );
    }
    final status = dioStatusCode(e);
    return ApiException.response(
      status,
      dioBackendMessage(e) ?? 'Session expired. Please log in again.',
    );
  }

  ApiException _mapNetworkError(DioException e, {required String fallback}) {
    if (isTimeoutError(e)) {
      return const ApiException.timeout(
        'Connection timed out. Please check your internet and try again.',
      );
    }
    if (isNetworkError(e)) {
      return const ApiException.network(
        'No internet connection. Please check your network and try again.',
      );
    }
    return ApiException.response(
      dioStatusCode(e),
      dioBackendMessage(e) ?? fallback,
    );
  }
}
