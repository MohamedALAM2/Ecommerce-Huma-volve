import 'package:flutter/foundation.dart';

import '../../../core/error/app_failure.dart';
import '../domain/entities/user_entity.dart';
import '../domain/usecases/login_usecase.dart';
import '../domain/usecases/logout_usecase.dart';
import '../domain/usecases/restore_session_usecase.dart';
import '../domain/usecases/signup_usecase.dart';

// ignore_for_file: prefer_initializing_formals

/// Application/session orchestration for authentication.
///
/// Depends ONLY on domain use cases — never on Dio, data sources, concrete
/// repositories, or storage plugins. Screens call this (never infrastructure
/// directly) so layer boundaries stay intact.
///
/// Retained as a ChangeNotifier singleton (rather than migrating Auth to
/// Cubit) because its observable behavior, navigation integration, and tests
/// already work; the refactor only swapped its dependencies to abstractions.
class AuthSession extends ChangeNotifier {
  final SignUpUseCase _signUp;
  final LoginUseCase _login;
  final RestoreSessionUseCase _restoreSession;
  final LogoutUseCase _logout;

  UserEntity? _currentUser;
  String? _accessToken;
  String? _refreshToken;
  bool _isAuthenticating = false;

  AuthSession({
    required SignUpUseCase signUp,
    required LoginUseCase login,
    required RestoreSessionUseCase restoreSession,
    required LogoutUseCase logout,
  }) : _signUp = signUp,
       _login = login,
       _restoreSession = restoreSession,
       _logout = logout;

  // Singleton used by the UI so navigation can stay unchanged
  // (screens use `pushReplacement` with const constructors).
  static AuthSession? _instance;

  /// The shared instance, initialised in `main()` via the DI container.
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
    required SignUpUseCase signUp,
    required LoginUseCase login,
    required RestoreSessionUseCase restoreSession,
    required LogoutUseCase logout,
  }) {
    _instance = AuthSession(
      signUp: signUp,
      login: login,
      restoreSession: restoreSession,
      logout: logout,
    );
    return _instance!;
  }

  /// Test-only override.
  @visibleForTesting
  static void debugSetInstance(AuthSession session) {
    _instance = session;
  }

  UserEntity? get currentUser => _currentUser;
  String? get accessToken => _accessToken;
  // Exposed for session validity checks; never log this value.
  String? get refreshToken => _refreshToken;
  bool get isAuthenticated => _accessToken != null && _currentUser != null;
  bool get isAuthenticating => _isAuthenticating;

  /// Attempts a fresh registration. Does not log the user in; the caller
  /// navigates to Login on success.
  Future<UserEntity> signUp({
    required String name,
    required String email,
    required String password,
  }) {
    return _signUp(name: name, email: email, password: password);
  }

  /// Full login flow (delegated to [LoginUseCase], which authenticates,
  /// fetches the profile, and persists tokens). Throws [AppFailure] with a
  /// displayable message. Guards against concurrent calls.
  Future<UserEntity> login({
    required String email,
    required String password,
  }) async {
    if (_isAuthenticating) {
      throw const UnexpectedFailure(
        'Please wait, authentication is in progress.',
      );
    }
    _isAuthenticating = true;
    notifyListeners();
    try {
      final result = await _login(email: email, password: password);
      _accessToken = result.tokens.accessToken;
      _refreshToken = result.tokens.refreshToken;
      _currentUser = result.user;
      return result.user;
    } finally {
      _isAuthenticating = false;
      notifyListeners();
    }
  }

  /// Restores a previous session via [RestoreSessionUseCase]. Returns the
  /// user on success, `null` when no valid session exists.
  Future<UserEntity?> restoreSession() async {
    final session = await _restoreSession();
    if (session != null) {
      _accessToken = session.tokens.accessToken;
      _refreshToken = session.tokens.refreshToken;
      _currentUser = session.user;
      notifyListeners();
    } else if (_currentUser != null ||
        _accessToken != null ||
        _refreshToken != null) {
      _currentUser = null;
      _accessToken = null;
      _refreshToken = null;
      notifyListeners();
    }
    return session?.user;
  }

  /// Clears tokens and user state.
  Future<void> logout() async {
    await _logout();
    _accessToken = null;
    _refreshToken = null;
    _currentUser = null;
    notifyListeners();
  }
}
