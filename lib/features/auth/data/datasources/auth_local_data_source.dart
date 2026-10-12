import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Local persistence contract for authentication tokens.
///
/// Only tokens are stored — never raw passwords. Implemented with
/// `flutter_secure_storage` in production; the repository depends on this
/// abstraction, never on the plugin directly.
abstract class AuthLocalDataSource {
  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
  });

  Future<String?> readAccessToken();
  Future<String?> readRefreshToken();
  Future<bool> hasSession();
  Future<void> clear();
}

/// Production implementation backed by flutter_secure_storage.
class SecureAuthLocalDataSource implements AuthLocalDataSource {
  static const String _accessTokenKey = 'auth_access_token';
  static const String _refreshTokenKey = 'auth_refresh_token';

  final FlutterSecureStorage _storage;

  SecureAuthLocalDataSource({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
  }

  @override
  Future<String?> readAccessToken() => _storage.read(key: _accessTokenKey);

  @override
  Future<String?> readRefreshToken() => _storage.read(key: _refreshTokenKey);

  @override
  Future<bool> hasSession() async {
    final access = await readAccessToken();
    final refresh = await readRefreshToken();
    return access != null &&
        access.isNotEmpty &&
        refresh != null &&
        refresh.isNotEmpty;
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }
}

/// In-memory implementation for unit/widget tests (no platform channels).
class InMemoryAuthLocalDataSource implements AuthLocalDataSource {
  String? _accessToken;
  String? _refreshToken;

  @override
  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
  }

  @override
  Future<String?> readAccessToken() async => _accessToken;

  @override
  Future<String?> readRefreshToken() async => _refreshToken;

  @override
  Future<bool> hasSession() async =>
      _accessToken != null &&
      _accessToken!.isNotEmpty &&
      _refreshToken != null &&
      _refreshToken!.isNotEmpty;

  @override
  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
  }
}
