import 'package:flutter/foundation.dart';

// ignore_for_file: prefer_initializing_formals

import '../data/auth_exception.dart';
import '../data/models/auth_models.dart';
import '../data/models/user_model.dart';
import '../data/services/auth_service.dart';
import '../data/services/auth_storage.dart';

/// Lightweight session manager: owns tokens + current user, restores the
/// session on app start, refreshes expired access tokens once, and clears
/// everything on logout.
///
/// Screens call this (never Dio directly) so HTTP stays out of widgets.
class AuthSession extends ChangeNotifier {
  final AuthService _authService;
  final AuthStorage _storage;

  UserModel? _currentUser;
  String? _accessToken;
  String? _refreshToken;
  bool _isAuthenticating = false;

  AuthSession({required AuthService authService, required AuthStorage storage})
    : _authService = authService,
      _storage = storage;

  // Singleton used by the UI so navigation can stay unchanged
  // (screens use `pushReplacement` with const constructors).
  static AuthSession? _instance;

  /// The shared instance, initialised in `main()`.
  static AuthSession get instance {
    final current = _instance;
    if (current == null) {
      throw StateError(
        'AuthSession not initialised. Call AuthSession.init() in main().',
      );
    }
    return current;
  }

  /// Initialises (or replaces, e.g. in tests) the shared instance.
  static AuthSession init({
    required AuthService authService,
    required AuthStorage storage,
  }) {
    _instance = AuthSession(authService: authService, storage: storage);
    return _instance!;
  }

  /// Test-only override.
  @visibleForTesting
  static void debugSetInstance(AuthSession session) {
    _instance = session;
  }

  UserModel? get currentUser => _currentUser;
  String? get accessToken => _accessToken;
  // Exposed for session validity checks; never log this value.
  String? get refreshToken => _refreshToken;
  bool get isAuthenticated => _accessToken != null && _currentUser != null;
  bool get isAuthenticating => _isAuthenticating;

  /// Attempts a fresh registration. Does not log the user in; the caller
  /// navigates to Login on success.
  Future<UserModel> signUp({
    required String name,
    required String email,
    required String password,
  }) {
    return _authService.signUp(name: name, email: email, password: password);
  }

  /// Full login flow: `POST /auth/login` then `GET /auth/profile`, then
  /// persist tokens. Throws [AuthException] with a displayable message.
  /// Guards against concurrent calls.
  Future<UserModel> login({
    required String email,
    required String password,
  }) async {
    if (_isAuthenticating) {
      throw const AuthException('Please wait, authentication is in progress.');
    }
    _isAuthenticating = true;
    notifyListeners();
    try {
      final AuthTokens tokens = await _authService.login(
        email: email,
        password: password,
      );
      final UserModel user = await _authService.getProfile(tokens.accessToken);
      _accessToken = tokens.accessToken;
      _refreshToken = tokens.refreshToken;
      _currentUser = user;
      await _storage.saveSession(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
      return user;
    } finally {
      _isAuthenticating = false;
      notifyListeners();
    }
  }

  /// Restores a previous session: reads stored tokens, validates them with
  /// `GET /auth/profile`, and tries one refresh if the access token expired.
  /// Returns the user on success, `null` when no valid session exists.
  Future<UserModel?> restoreSession() async {
    final storedAccess = await _storage.readAccessToken();
    final storedRefresh = await _storage.readRefreshToken();
    if (storedAccess == null ||
        storedAccess.isEmpty ||
        storedRefresh == null ||
        storedRefresh.isEmpty) {
      return null;
    }
    try {
      final user = await _authService.getProfile(storedAccess);
      _accessToken = storedAccess;
      _refreshToken = storedRefresh;
      _currentUser = user;
      notifyListeners();
      return user;
    } on AuthException catch (e) {
      if (e.statusCode == 401) {
        // Access token expired/invalid — try the refresh token once.
        try {
          final AuthTokens fresh = await _authService.refreshToken(
            storedRefresh,
          );
          final user = await _authService.getProfile(fresh.accessToken);
          _accessToken = fresh.accessToken;
          _refreshToken = fresh.refreshToken;
          _currentUser = user;
          await _storage.saveSession(
            accessToken: fresh.accessToken,
            refreshToken: fresh.refreshToken,
          );
          notifyListeners();
          return user;
        } on AuthException {
          await _storage.clear();
          _accessToken = null;
          _refreshToken = null;
          _currentUser = null;
          notifyListeners();
          return null;
        }
      }
      // Non-auth failure (e.g. offline): keep stored tokens for next launch.
      return null;
    }
  }

  /// Clears tokens and user state.
  Future<void> logout() async {
    await _storage.clear();
    _accessToken = null;
    _refreshToken = null;
    _currentUser = null;
    notifyListeners();
  }
}
