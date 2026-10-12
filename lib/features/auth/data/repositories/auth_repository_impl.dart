import '../../../../core/error/api_exception.dart';
import '../../../../core/error/app_failure.dart';

// ignore_for_file: prefer_initializing_formals
// (Constructor takes public data-source parameters; fields are private.)

import '../../domain/entities/auth_tokens_entity.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_local_data_source.dart';
import '../datasources/auth_remote_data_source.dart';

/// [AuthRepository] implementation: coordinates the remote data source
/// (HTTP + DTOs) and the local data source (secure token persistence),
/// mapping DTOs to domain entities and [ApiException]s to typed
/// [AppFailure]s. The only failure type that escapes is [AppFailure].
class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource _remote;
  final AuthLocalDataSource _local;

  const AuthRepositoryImpl({
    required AuthRemoteDataSource remote,
    required AuthLocalDataSource local,
  }) : _remote = remote,
       _local = local;

  @override
  Future<UserEntity> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final dto = await _remote.signUp(
        name: name,
        email: email,
        password: password,
      );
      return dto.toEntity();
    } on ApiException catch (e) {
      throw AppFailure.fromApiException(e);
    }
  }

  @override
  Future<AuthTokensEntity> login({
    required String email,
    required String password,
  }) async {
    try {
      final dto = await _remote.login(email: email, password: password);
      return dto.toEntity();
    } on ApiException catch (e) {
      throw AppFailure.fromApiException(e);
    }
  }

  @override
  Future<UserEntity> getProfile(String accessToken) async {
    try {
      final dto = await _remote.getProfile(accessToken);
      return dto.toEntity();
    } on ApiException catch (e) {
      throw AppFailure.fromApiException(e);
    }
  }

  @override
  Future<AuthTokensEntity> refreshToken(String refreshToken) async {
    try {
      final dto = await _remote.refreshToken(refreshToken);
      return dto.toEntity();
    } on ApiException catch (e) {
      throw AppFailure.fromApiException(e);
    }
  }

  @override
  Future<bool> isEmailAvailable(String email) async {
    try {
      return await _remote.isEmailAvailable(email);
    } on ApiException catch (e) {
      throw AppFailure.fromApiException(e);
    }
  }

  @override
  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
  }) {
    // Local writes are not expected to throw typed API errors; any
    // platform failure propagates as-is (same as before the refactor).
    return _local.saveSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
  }

  @override
  Future<String?> readAccessToken() => _local.readAccessToken();

  @override
  Future<String?> readRefreshToken() => _local.readRefreshToken();

  @override
  Future<void> clearSession() => _local.clear();
}
