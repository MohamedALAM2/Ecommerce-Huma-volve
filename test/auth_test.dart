import 'dart:io';

import 'package:dio/dio.dart';
import 'package:ecommerce_app_huma_volve/core/error/api_exception.dart';
import 'package:ecommerce_app_huma_volve/core/error/app_failure.dart';
import 'package:ecommerce_app_huma_volve/core/network/api_constants.dart';
import 'package:ecommerce_app_huma_volve/core/validators.dart';
import 'package:ecommerce_app_huma_volve/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:ecommerce_app_huma_volve/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:ecommerce_app_huma_volve/features/auth/data/models/auth_models.dart';
import 'package:ecommerce_app_huma_volve/features/auth/data/models/user_model.dart';
import 'package:ecommerce_app_huma_volve/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:ecommerce_app_huma_volve/features/auth/domain/entities/auth_tokens_entity.dart';
import 'package:ecommerce_app_huma_volve/features/auth/domain/entities/user_entity.dart';
import 'package:ecommerce_app_huma_volve/features/auth/domain/repositories/auth_repository.dart';
import 'package:ecommerce_app_huma_volve/features/auth/domain/usecases/login_usecase.dart';
import 'package:ecommerce_app_huma_volve/features/auth/domain/usecases/logout_usecase.dart';
import 'package:ecommerce_app_huma_volve/features/auth/domain/usecases/restore_session_usecase.dart';
import 'package:ecommerce_app_huma_volve/features/auth/domain/usecases/signup_usecase.dart';
import 'package:ecommerce_app_huma_volve/features/auth/login/screens/login_screen.dart';
import 'package:ecommerce_app_huma_volve/features/auth/session/auth_session.dart';
import 'package:ecommerce_app_huma_volve/features/auth/sign_up/screens/sign_up_screen.dart';
import 'package:ecommerce_app_huma_volve/features/splash/screens/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

const _testUserJson = {
  'id': 1,
  'email': 'john@mail.com',
  'name': 'Jhon',
  'role': 'customer',
  'avatar': 'https://i.imgur.com/LDOO4Qs.jpg',
};

const _testTokensJson = {
  'access_token': 'test-access-token',
  'refresh_token': 'test-refresh-token',
};

const _refreshedTokensJson = {
  'access_token': 'new-access-token',
  'refresh_token': 'new-refresh-token',
};

Dio _buildDio(void Function(Dio dio) configure) {
  final dio = Dio(BaseOptions(baseUrl: ApiConstants.baseApiUrl));
  configure(dio);
  return dio;
}

DioException _networkError(String path) {
  return DioException(
    requestOptions: RequestOptions(path: path),
    type: DioExceptionType.connectionError,
    error: const SocketException('No internet'),
  );
}

DioException _timeoutError(String path) {
  return DioException(
    requestOptions: RequestOptions(path: path),
    type: DioExceptionType.connectionTimeout,
  );
}

/// Fake implementing the Domain repository contract (no Dio/HTTP), with an
/// in-memory token store. Used for session-orchestration tests.
class FakeAuthRepository implements AuthRepository {
  static const testUser = UserEntity(
    id: 1,
    email: 'john@mail.com',
    name: 'Jhon',
    role: 'customer',
    avatar: 'https://i.imgur.com/LDOO4Qs.jpg',
  );
  static const testTokens = AuthTokensEntity(
    accessToken: 'test-access-token',
    refreshToken: 'test-refresh-token',
  );
  static const refreshedTokens = AuthTokensEntity(
    accessToken: 'new-access-token',
    refreshToken: 'new-refresh-token',
  );

  Future<UserEntity> Function({
    required String name,
    required String email,
    required String password,
  })?
  signUpHandler;
  Future<AuthTokensEntity> Function({
    required String email,
    required String password,
  })?
  loginHandler;
  Future<UserEntity> Function(String accessToken)? profileHandler;
  Future<AuthTokensEntity> Function(String refreshToken)? refreshHandler;

  final List<String> calls = [];
  String? storedAccessToken;
  String? storedRefreshToken;
  bool cleared = false;

  @override
  Future<UserEntity> signUp({
    required String name,
    required String email,
    required String password,
  }) {
    calls.add('signUp');
    final handler = signUpHandler;
    if (handler != null) {
      return handler(name: name, email: email, password: password);
    }
    return Future.value(testUser);
  }

  @override
  Future<AuthTokensEntity> login({
    required String email,
    required String password,
  }) {
    calls.add('login');
    final handler = loginHandler;
    if (handler != null) {
      return handler(email: email, password: password);
    }
    return Future.value(testTokens);
  }

  @override
  Future<UserEntity> getProfile(String accessToken) {
    calls.add('getProfile');
    final handler = profileHandler;
    if (handler != null) return handler(accessToken);
    return Future.value(testUser);
  }

  @override
  Future<AuthTokensEntity> refreshToken(String refreshToken) {
    calls.add('refreshToken');
    final handler = refreshHandler;
    if (handler != null) return handler(refreshToken);
    return Future.value(refreshedTokens);
  }

  @override
  Future<bool> isEmailAvailable(String email) => Future.value(true);

  @override
  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
  }) async {
    calls.add('saveSession');
    storedAccessToken = accessToken;
    storedRefreshToken = refreshToken;
  }

  @override
  Future<String?> readAccessToken() async => storedAccessToken;

  @override
  Future<String?> readRefreshToken() async => storedRefreshToken;

  @override
  Future<void> clearSession() async {
    calls.add('clearSession');
    cleared = true;
    storedAccessToken = null;
    storedRefreshToken = null;
  }
}

/// Builds an [AuthSession] exactly like the DI container does: use cases
/// over the given repository.
AuthSession _sessionWith(AuthRepository repo) {
  return AuthSession(
    signUp: SignUpUseCase(repo),
    login: LoginUseCase(repo),
    restoreSession: RestoreSessionUseCase(repo),
    logout: LogoutUseCase(repo),
  );
}

/// Builds a real repository implementation over a mocked Dio client plus an
/// in-memory local data source.
AuthRepository _repoWith(Dio dio, AuthLocalDataSource local) {
  return AuthRepositoryImpl(
    remote: AuthRemoteDataSource(dio: dio),
    local: local,
  );
}

void main() {
  group('AuthRemoteDataSource.signUp', () {
    test('successful registration returns the created user', () async {
      final dio = _buildDio(
        (d) => DioAdapter(dio: d, matcher: const UrlRequestMatcher()).onPost(
          ApiConstants.users,
          (server) => server.reply(201, _testUserJson),
        ),
      );
      final dataSource = AuthRemoteDataSource(dio: dio);

      final user = await dataSource.signUp(
        name: 'Jhon',
        email: 'john@mail.com',
        password: 'changeme',
      );

      expect(user.email, 'john@mail.com');
      expect(user.name, 'Jhon');
    });

    test('backend validation errors surface the backend message', () async {
      final dio = _buildDio(
        (d) => DioAdapter(dio: d, matcher: const UrlRequestMatcher()).onPost(
          ApiConstants.users,
          (server) => server.reply(400, {
            'message': [
              'email must be an email',
              'password must be longer than or equal to 4 characters',
            ],
            'error': 'Bad Request',
            'statusCode': 400,
          }),
        ),
      );
      final dataSource = AuthRemoteDataSource(dio: dio);

      expect(
        () => dataSource.signUp(name: 'x', email: 'bad', password: '123'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.kind, 'kind', ApiErrorKind.response)
              .having((e) => e.statusCode, 'status', 400)
              .having(
                (e) => e.message,
                'message',
                contains('email must be an email'),
              ),
        ),
      );
    });

    test('network failure maps to a friendly message', () async {
      final dio = _buildDio(
        (d) => DioAdapter(dio: d, matcher: const UrlRequestMatcher()).onPost(
          ApiConstants.users,
          (server) => server.throws(0, _networkError(ApiConstants.users)),
        ),
      );
      final dataSource = AuthRemoteDataSource(dio: dio);

      expect(
        () => dataSource.signUp(
          name: 'Jhon',
          email: 'john@mail.com',
          password: 'changeme',
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.kind, 'kind', ApiErrorKind.network)
              .having((e) => e.message, 'message', contains('No internet')),
        ),
      );
    });

    test('timeout maps to a friendly message', () async {
      final dio = _buildDio(
        (d) => DioAdapter(dio: d, matcher: const UrlRequestMatcher()).onPost(
          ApiConstants.users,
          (server) => server.throws(0, _timeoutError(ApiConstants.users)),
        ),
      );
      final dataSource = AuthRemoteDataSource(dio: dio);

      expect(
        () => dataSource.signUp(
          name: 'Jhon',
          email: 'john@mail.com',
          password: 'changeme',
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.kind, 'kind', ApiErrorKind.timeout)
              .having((e) => e.message, 'message', contains('timed out')),
        ),
      );
    });
  });

  group('AuthRemoteDataSource.login', () {
    test('successful login returns token pair', () async {
      final dio = _buildDio(
        (d) => DioAdapter(dio: d, matcher: const UrlRequestMatcher()).onPost(
          ApiConstants.login,
          (server) => server.reply(201, _testTokensJson),
        ),
      );
      final dataSource = AuthRemoteDataSource(dio: dio);

      final tokens = await dataSource.login(
        email: 'john@mail.com',
        password: 'changeme',
      );
      expect(tokens.accessToken, 'test-access-token');
      expect(tokens.refreshToken, 'test-refresh-token');
    });

    test('incorrect password (401) is rejected clearly', () async {
      final dio = _buildDio(
        (d) => DioAdapter(dio: d, matcher: const UrlRequestMatcher()).onPost(
          ApiConstants.login,
          (server) =>
              server.reply(401, {'message': 'Unauthorized', 'statusCode': 401}),
        ),
      );
      final dataSource = AuthRemoteDataSource(dio: dio);

      expect(
        () => dataSource.login(email: 'john@mail.com', password: 'wrong'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.kind, 'kind', ApiErrorKind.response)
              .having((e) => e.statusCode, 'status', 401)
              .having(
                (e) => e.message,
                'message',
                contains('Incorrect email or password'),
              ),
        ),
      );
    });

    test('nonexistent account (401) is rejected clearly', () async {
      final dio = _buildDio(
        (d) => DioAdapter(dio: d, matcher: const UrlRequestMatcher()).onPost(
          ApiConstants.login,
          (server) =>
              server.reply(401, {'message': 'Unauthorized', 'statusCode': 401}),
        ),
      );
      final dataSource = AuthRemoteDataSource(dio: dio);

      expect(
        () => dataSource.login(email: 'ghost_xyz@mail.com', password: '123456'),
        throwsA(isA<ApiException>()),
      );
    });

    test('network failure and timeout are handled', () async {
      final networkDio = _buildDio(
        (d) => DioAdapter(dio: d, matcher: const UrlRequestMatcher()).onPost(
          ApiConstants.login,
          (server) => server.throws(0, _networkError(ApiConstants.login)),
        ),
      );
      await expectLater(
        () =>
            AuthRemoteDataSource(dio: networkDio)
                .login(email: 'a@b.com', password: '123456'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.kind, 'kind', ApiErrorKind.network)
              .having((e) => e.message, 'message', contains('No internet')),
        ),
      );

      final timeoutDio = _buildDio(
        (d) => DioAdapter(dio: d, matcher: const UrlRequestMatcher()).onPost(
          ApiConstants.login,
          (server) => server.throws(0, _timeoutError(ApiConstants.login)),
        ),
      );
      await expectLater(
        () =>
            AuthRemoteDataSource(dio: timeoutDio)
                .login(email: 'a@b.com', password: '123456'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.kind, 'kind', ApiErrorKind.timeout)
              .having((e) => e.message, 'message', contains('timed out')),
        ),
      );
    });

    test('malformed token response is rejected', () async {
      final dio = _buildDio(
        (d) => DioAdapter(dio: d, matcher: const UrlRequestMatcher()).onPost(
          ApiConstants.login,
          (server) => server.reply(201, {'unexpected': true}),
        ),
      );
      expect(
        () =>
            AuthRemoteDataSource(dio: dio)
                .login(email: 'a@b.com', password: '123456'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.kind,
            'kind',
            ApiErrorKind.unknown,
          ),
        ),
      );
    });
  });

  group('AuthRemoteDataSource profile & refresh', () {
    test('getProfile returns the user', () async {
      final dio = _buildDio(
        (d) => DioAdapter(dio: d, matcher: const UrlRequestMatcher()).onGet(
          ApiConstants.profile,
          (server) => server.reply(200, _testUserJson),
        ),
      );
      final user = await AuthRemoteDataSource(dio: dio)
          .getProfile('test-access-token');
      expect(user.id, 1);
    });

    test('getProfile 401 maps to session-expired', () async {
      final dio = _buildDio(
        (d) => DioAdapter(dio: d, matcher: const UrlRequestMatcher()).onGet(
          ApiConstants.profile,
          (server) =>
              server.reply(401, {'message': 'Unauthorized', 'statusCode': 401}),
        ),
      );
      await expectLater(
        () => AuthRemoteDataSource(dio: dio).getProfile('expired'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.kind, 'kind', ApiErrorKind.response)
              .having((e) => e.statusCode, 'status', 401)
              .having((e) => e.message, 'message', contains('Session expired')),
        ),
      );
    });

    test('refreshToken returns a new token pair', () async {
      final dio = _buildDio(
        (d) => DioAdapter(dio: d, matcher: const UrlRequestMatcher()).onPost(
          ApiConstants.refreshToken,
          (server) => server.reply(201, _refreshedTokensJson),
        ),
      );
      final tokens = await AuthRemoteDataSource(dio: dio)
          .refreshToken('test-refresh-token');
      expect(tokens.accessToken, 'new-access-token');
    });

    test(
      'malformed successful refresh is unexpected, not unauthorized',
      () async {
        // A 200 response with an unusable body must NOT look like a 401:
        // callers clear stored credentials only on genuine rejection.
        final dio = _buildDio(
          (d) => DioAdapter(dio: d, matcher: const UrlRequestMatcher()).onPost(
            ApiConstants.refreshToken,
            (server) => server.reply(201, {'unexpected': true}),
          ),
        );
        await expectLater(
          () => AuthRemoteDataSource(dio: dio).refreshToken('r'),
          throwsA(
            isA<ApiException>()
                .having((e) => e.kind, 'kind', ApiErrorKind.unknown)
                .having((e) => e.statusCode, 'status', isNull),
          ),
        );
      },
    );
  });

  group('AuthSession', () {
    test('login persists tokens and sets the current user', () async {
      final dio = Dio(BaseOptions(baseUrl: ApiConstants.baseApiUrl));
      final adapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      adapter.onPost(
        ApiConstants.login,
        (server) => server.reply(201, _testTokensJson),
      );
      adapter.onGet(
        ApiConstants.profile,
        (server) => server.reply(200, _testUserJson),
      );
      final local = InMemoryAuthLocalDataSource();
      final session = _sessionWith(_repoWith(dio, local));

      final user = await session.login(
        email: 'john@mail.com',
        password: 'changeme',
      );
      expect(user.email, 'john@mail.com');
      expect(session.currentUser?.email, 'john@mail.com');
      expect(session.isAuthenticated, isTrue);
      expect(await local.readAccessToken(), 'test-access-token');
      expect(await local.readRefreshToken(), 'test-refresh-token');
    });

    test('concurrent login attempts are rejected', () async {
      final dio = Dio(BaseOptions(baseUrl: ApiConstants.baseApiUrl));
      final adapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      adapter.onPost(
        ApiConstants.login,
        (server) => server.reply(
          201,
          _testTokensJson,
          delay: const Duration(milliseconds: 200),
        ),
      );
      adapter.onGet(
        ApiConstants.profile,
        (server) => server.reply(200, _testUserJson),
      );
      final session = _sessionWith(
        _repoWith(dio, InMemoryAuthLocalDataSource()),
      );

      final first = session.login(email: 'john@mail.com', password: 'changeme');
      await expectLater(
        session.login(email: 'john@mail.com', password: 'changeme'),
        throwsA(isA<AppFailure>()),
      );
      await first;
    });

    test('restoreSession returns user when tokens are valid', () async {
      final local = InMemoryAuthLocalDataSource();
      await local.saveSession(
        accessToken: 'test-access-token',
        refreshToken: 'test-refresh-token',
      );
      final dio = Dio(BaseOptions(baseUrl: ApiConstants.baseApiUrl));
      DioAdapter(dio: dio, matcher: const UrlRequestMatcher()).onGet(
        ApiConstants.profile,
        (server) => server.reply(200, _testUserJson),
      );
      final session = _sessionWith(_repoWith(dio, local));

      final user = await session.restoreSession();
      expect(user?.email, 'john@mail.com');
      expect(session.isAuthenticated, isTrue);
    });

    test('restoreSession refreshes an expired access token', () async {
      final repo = FakeAuthRepository();
      var profileCalls = 0;
      repo.profileHandler = (accessToken) async {
        profileCalls++;
        if (profileCalls == 1) {
          throw const UnauthorizedFailure(
            'Session expired. Please log in again.',
            statusCode: 401,
          );
        }
        return FakeAuthRepository.testUser;
      };
      repo.refreshHandler = (_) async => FakeAuthRepository.refreshedTokens;
      await repo.saveSession(
        accessToken: 'expired',
        refreshToken: 'test-refresh-token',
      );
      final session = _sessionWith(repo);

      final user = await session.restoreSession();
      expect(user?.email, 'john@mail.com');
      expect(repo.storedAccessToken, 'new-access-token');
      expect(repo.calls.where((c) => c == 'refreshToken'), hasLength(1));
    });

    test('restoreSession clears storage when refresh fails', () async {
      final local = InMemoryAuthLocalDataSource();
      await local.saveSession(
        accessToken: 'expired',
        refreshToken: 'bad-refresh',
      );
      final dio = Dio(BaseOptions(baseUrl: ApiConstants.baseApiUrl));
      final adapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      adapter.onGet(
        ApiConstants.profile,
        (server) =>
            server.reply(401, {'message': 'Unauthorized', 'statusCode': 401}),
      );
      adapter.onPost(
        ApiConstants.refreshToken,
        (server) =>
            server.reply(401, {'message': 'Unauthorized', 'statusCode': 401}),
      );
      final session = _sessionWith(_repoWith(dio, local));

      expect(await session.restoreSession(), isNull);
      expect(await local.hasSession(), isFalse);
      expect(session.isAuthenticated, isFalse);
    });

    test(
      'restoreSession preserves stored credentials when offline (reliability)',
      () async {
        final repo = FakeAuthRepository();
        repo.profileHandler = (_) async {
          throw const NetworkFailure();
        };
        await repo.saveSession(
          accessToken: 'test-access-token',
          refreshToken: 'test-refresh-token',
        );
        final session = _sessionWith(repo);

        expect(await session.restoreSession(), isNull);
        // Valid credentials must NOT be deleted merely because the device
        // is offline.
        expect(repo.cleared, isFalse);
        expect(repo.storedAccessToken, 'test-access-token');
        expect(repo.storedRefreshToken, 'test-refresh-token');
        expect(session.isAuthenticated, isFalse);
      },
    );

    test(
      'restoreSession preserves stored credentials on refresh timeout',
      () async {
        final repo = FakeAuthRepository();
        var profileCalls = 0;
        repo.profileHandler = (_) async {
          profileCalls++;
          if (profileCalls == 1) {
            throw const UnauthorizedFailure(
              'Session expired. Please log in again.',
              statusCode: 401,
            );
          }
          return FakeAuthRepository.testUser;
        };
        repo.refreshHandler = (_) async {
          throw const TimeoutFailure();
        };
        await repo.saveSession(
          accessToken: 'expired',
          refreshToken: 'test-refresh-token',
        );
        final session = _sessionWith(repo);

        expect(await session.restoreSession(), isNull);
        expect(repo.cleared, isFalse);
        expect(repo.storedRefreshToken, 'test-refresh-token');
      },
    );

    test('restoreSession returns null with no stored session', () async {
      final session = _sessionWith(FakeAuthRepository());
      expect(await session.restoreSession(), isNull);
    });

    test('logout clears credentials', () async {
      final local = InMemoryAuthLocalDataSource();
      await local.saveSession(accessToken: 'a', refreshToken: 'r');
      // Simulate a logged-in user via a successful restore first.
      final dio = Dio(BaseOptions(baseUrl: ApiConstants.baseApiUrl));
      DioAdapter(dio: dio, matcher: const UrlRequestMatcher()).onGet(
        ApiConstants.profile,
        (server) => server.reply(200, _testUserJson),
      );
      final loggedIn = _sessionWith(_repoWith(dio, local));
      await loggedIn.restoreSession();
      expect(loggedIn.isAuthenticated, isTrue);

      await loggedIn.logout();
      expect(await local.hasSession(), isFalse);
      expect(loggedIn.isAuthenticated, isFalse);
    });
  });

  group('Validators', () {
    test('email validation', () {
      expect(Validators.email(null), isNotNull);
      expect(Validators.email(''), isNotNull);
      expect(Validators.email('not-an-email'), isNotNull);
      expect(Validators.email('user@domain'), isNotNull);
      expect(Validators.email('user@example.com'), isNull);
    });

    test('password validation', () {
      expect(Validators.password(null), isNotNull);
      expect(Validators.password(''), isNotNull);
      expect(Validators.password('12345'), isNotNull);
      expect(Validators.password('123456'), isNull);
    });

    test('password validation allows all character types', () {
      // Letters only, alphanumeric, and special characters must all pass
      // once the minimum length is met (backend requires >= 4 chars;
      // the app enforces >= 6).
      expect(Validators.password('abcdef'), isNull);
      expect(Validators.password('abc123'), isNull);
      expect(Validators.password('P@ssw0rd!'), isNull);
      expect(Validators.password('!@#\$%^&*()'), isNull);
      expect(Validators.password('pässwörd123!'), isNull);
      // Too short, even with special characters.
      expect(Validators.password('a!1'), isNotNull);
    });

    test('full name validation', () {
      expect(Validators.fullName(null), isNotNull);
      expect(Validators.fullName(''), isNotNull);
      expect(Validators.fullName('A'), isNotNull);
      expect(Validators.fullName('Jane Doe'), isNull);
    });
  });

  group('Models & storage', () {
    test('UserModel parses profile JSON', () {
      final user = UserModel.fromJson(Map<String, dynamic>.from(_testUserJson));
      expect(user.id, 1);
      expect(user.role, 'customer');
      expect(user.toJson()['email'], 'john@mail.com');
    });

    test('AuthTokens requires both tokens', () {
      expect(
        () => AuthTokens.fromJson({'access_token': 'a'}),
        throwsA(isA<FormatException>()),
      );
      final tokens = AuthTokens.fromJson(
        Map<String, dynamic>.from(_testTokensJson),
      );
      expect(tokens.accessToken, isNotEmpty);
    });

    test('SignUpRequest never includes unexpected fields', () {
      const request = SignUpRequest(
        name: 'Jane',
        email: 'jane@example.com',
        password: 'secret123',
        role: 'customer',
        avatar: 'https://i.imgur.com/LDOO4Qs.jpg',
      );
      final json = request.toJson();
      expect(json.keys.toSet(), {
        'name',
        'email',
        'password',
        'role',
        'avatar',
      });
    });

    test('InMemoryAuthLocalDataSource round-trip', () async {
      final storage = InMemoryAuthLocalDataSource();
      expect(await storage.hasSession(), isFalse);
      await storage.saveSession(accessToken: 'a', refreshToken: 'r');
      expect(await storage.hasSession(), isTrue);
      await storage.clear();
      expect(await storage.hasSession(), isFalse);
    });
  });

  group('LoginScreen', () {
    testWidgets('failed login shows an error and never navigates', (
      tester,
    ) async {
      final dio = Dio(BaseOptions(baseUrl: ApiConstants.baseApiUrl));
      DioAdapter(dio: dio, matcher: const UrlRequestMatcher()).onPost(
        ApiConstants.login,
        (server) =>
            server.reply(401, {'message': 'Unauthorized', 'statusCode': 401}),
      );
      AuthSession.debugSetInstance(
        _sessionWith(_repoWith(dio, InMemoryAuthLocalDataSource())),
      );

      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email Address'),
        'john@mail.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'wrongpass',
      );
      await tester.tap(find.text('Login'));
      await tester.pump();
      // Loading indicator appears while the request is in flight.
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Incorrect email or password'),
        findsOneWidget,
      );
      // Still on the login screen — no navigation occurred.
      expect(find.text('Welcome Back!'), findsOneWidget);
    });

    testWidgets('empty fields show validation errors without any request', (
      tester,
    ) async {
      final dio = Dio(BaseOptions(baseUrl: ApiConstants.baseApiUrl));
      // Any request would fail the test; no mock is registered on purpose.
      DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      AuthSession.debugSetInstance(
        _sessionWith(_repoWith(dio, InMemoryAuthLocalDataSource())),
      );

      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.tap(find.text('Login'));
      await tester.pump();

      expect(find.text('Please enter your email'), findsOneWidget);
      expect(find.text('Please enter your password'), findsOneWidget);
    });

    testWidgets('password fields use a full text keyboard and stay masked', (
      tester,
    ) async {
      final dio = Dio(BaseOptions(baseUrl: ApiConstants.baseApiUrl));
      DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
      AuthSession.debugSetInstance(
        _sessionWith(_repoWith(dio, InMemoryAuthLocalDataSource())),
      );

      for (final screen in [const LoginScreen(), const SignUpScreen()]) {
        await tester.pumpWidget(MaterialApp(home: screen));
        final passwordFormField = find.widgetWithText(
          TextFormField,
          'Password',
        );
        final field = tester.widget<TextField>(
          find.descendant(
            of: passwordFormField,
            matching: find.byType(TextField),
          ),
        );
        // Full text keyboard: letters, numbers, and special characters.
        expect(field.keyboardType, TextInputType.visiblePassword);
        // Masking preserved.
        expect(field.obscureText, isTrue);
        // No digits-only formatters or character restrictions.
        expect(field.inputFormatters, isNull);
      }
    });

    testWidgets('sign up accepts a special-character password', (tester) async {
      final dio = Dio(BaseOptions(baseUrl: ApiConstants.baseApiUrl));
      DioAdapter(dio: dio, matcher: const UrlRequestMatcher()).onPost(
        ApiConstants.users,
        (server) => server.reply(201, _testUserJson),
      );
      AuthSession.debugSetInstance(
        _sessionWith(_repoWith(dio, InMemoryAuthLocalDataSource())),
      );

      await tester.pumpWidget(const MaterialApp(home: SignUpScreen()));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Full Name'),
        'Jane Doe',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email Address'),
        'jane@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'P@ssw0rd!',
      );
      await tester.ensureVisible(find.text('Sign Up'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign Up'));
      await tester.pumpAndSettle();

      // Successful registration navigates to the Login screen.
      expect(find.text('Welcome Back!'), findsOneWidget);
    });
  });

  group('SplashScreen session routing', () {
    testWidgets('no stored session routes to Login', (tester) async {
      AuthSession.debugSetInstance(_sessionWith(FakeAuthRepository()));

      await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Welcome Back!'), findsOneWidget);
    });

    testWidgets('invalid session routes to Login', (tester) async {
      final repo = FakeAuthRepository();
      repo.profileHandler = (_) async {
        throw const UnauthorizedFailure(
          'Session expired. Please log in again.',
          statusCode: 401,
        );
      };
      repo.refreshHandler = (_) async {
        throw const UnauthorizedFailure(
          'Session expired. Please log in again.',
          statusCode: 401,
        );
      };
      await repo.saveSession(accessToken: 'expired', refreshToken: 'bad');
      AuthSession.debugSetInstance(_sessionWith(repo));

      await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Welcome Back!'), findsOneWidget);
      expect(repo.cleared, isTrue);
    });

    testWidgets('offline restore offers Retry and keeps credentials', (
      tester,
    ) async {
      final repo = FakeAuthRepository();
      repo.profileHandler = (_) async {
        throw const NetworkFailure();
      };
      await repo.saveSession(accessToken: 'a', refreshToken: 'r');
      AuthSession.debugSetInstance(_sessionWith(repo));

      await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
      await tester.pumpAndSettle();

      // Stayed on Splash with a Retry action instead of Login...
      expect(find.text('Huma-volve'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Welcome Back!'), findsNothing);
      // ...and nothing was deleted.
      expect(repo.cleared, isFalse);

      // Retrying while still offline stays put without granting access.
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Huma-volve'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Welcome Back!'), findsNothing);
      expect(repo.cleared, isFalse);
    });
  });
}
