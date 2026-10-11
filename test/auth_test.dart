import 'dart:io';

import 'package:dio/dio.dart';
import 'package:ecommerce_app_huma_volve/core/network/api_constants.dart';
import 'package:ecommerce_app_huma_volve/core/validators.dart';
import 'package:ecommerce_app_huma_volve/features/auth/data/auth_exception.dart';
import 'package:ecommerce_app_huma_volve/features/auth/data/models/auth_models.dart';
import 'package:ecommerce_app_huma_volve/features/auth/data/models/user_model.dart';
import 'package:ecommerce_app_huma_volve/features/auth/data/services/auth_service.dart';
import 'package:ecommerce_app_huma_volve/features/auth/data/services/auth_storage.dart';
import 'package:ecommerce_app_huma_volve/features/auth/login/screens/login_screen.dart';
import 'package:ecommerce_app_huma_volve/features/auth/session/auth_session.dart';
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

/// Fake service simulating: first profile call 401, then refresh succeeds
/// and the retry profile call returns the user. Used because a single
/// http_mock_adapter route cannot reply with two different status codes.
class _ExpiringThenValidAuthService extends AuthService {
  int _profileCalls = 0;

  _ExpiringThenValidAuthService() : super(dio: Dio());

  @override
  Future<UserModel> getProfile(String accessToken) async {
    _profileCalls++;
    if (_profileCalls == 1) {
      throw const AuthException(
        'Session expired. Please log in again.',
        statusCode: 401,
      );
    }
    return UserModel.fromJson(Map<String, dynamic>.from(_testUserJson));
  }

  @override
  Future<AuthTokens> refreshToken(String refreshTokenValue) async {
    return AuthTokens.fromJson(Map<String, dynamic>.from(_refreshedTokensJson));
  }
}

void main() {
  group('AuthService.signUp', () {
    test('successful registration returns the created user', () async {
      final dio = _buildDio(
        (d) => DioAdapter(dio: d, matcher: const UrlRequestMatcher()).onPost(
          ApiConstants.users,
          (server) => server.reply(201, _testUserJson),
        ),
      );
      final service = AuthService(dio: dio);

      final user = await service.signUp(
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
      final service = AuthService(dio: dio);

      expect(
        () => service.signUp(name: 'x', email: 'bad', password: '123'),
        throwsA(
          isA<AuthException>().having(
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
      final service = AuthService(dio: dio);

      expect(
        () => service.signUp(
          name: 'Jhon',
          email: 'john@mail.com',
          password: 'changeme',
        ),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            contains('No internet'),
          ),
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
      final service = AuthService(dio: dio);

      expect(
        () => service.signUp(
          name: 'Jhon',
          email: 'john@mail.com',
          password: 'changeme',
        ),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
    });
  });

  group('AuthService.login', () {
    test('successful login returns token pair', () async {
      final dio = _buildDio(
        (d) => DioAdapter(dio: d, matcher: const UrlRequestMatcher()).onPost(
          ApiConstants.login,
          (server) => server.reply(201, _testTokensJson),
        ),
      );
      final service = AuthService(dio: dio);

      final tokens = await service.login(
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
      final service = AuthService(dio: dio);

      expect(
        () => service.login(email: 'john@mail.com', password: 'wrong'),
        throwsA(
          isA<AuthException>()
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
      final service = AuthService(dio: dio);

      expect(
        () => service.login(email: 'ghost_xyz@mail.com', password: '123456'),
        throwsA(isA<AuthException>()),
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
            AuthService(dio: networkDio)
                .login(email: 'a@b.com', password: '123456'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            contains('No internet'),
          ),
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
            AuthService(dio: timeoutDio)
                .login(email: 'a@b.com', password: '123456'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            contains('timed out'),
          ),
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
        () => AuthService(dio: dio).login(email: 'a@b.com', password: '123456'),
        throwsA(isA<AuthException>()),
      );
    });
  });

  group('AuthService profile & refresh', () {
    test('getProfile returns the user', () async {
      final dio = _buildDio(
        (d) => DioAdapter(dio: d, matcher: const UrlRequestMatcher()).onGet(
          ApiConstants.profile,
          (server) => server.reply(200, _testUserJson),
        ),
      );
      final user = await AuthService(dio: dio).getProfile('test-access-token');
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
        () => AuthService(dio: dio).getProfile('expired'),
        throwsA(
          isA<AuthException>()
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
      final tokens = await AuthService(dio: dio)
          .refreshToken('test-refresh-token');
      expect(tokens.accessToken, 'new-access-token');
    });
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
      final storage = InMemoryAuthStorage();
      final session = AuthSession(
        authService: AuthService(dio: dio),
        storage: storage,
      );

      final user = await session.login(
        email: 'john@mail.com',
        password: 'changeme',
      );
      expect(user.email, 'john@mail.com');
      expect(session.currentUser?.email, 'john@mail.com');
      expect(session.isAuthenticated, isTrue);
      expect(await storage.readAccessToken(), 'test-access-token');
      expect(await storage.readRefreshToken(), 'test-refresh-token');
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
      final session = AuthSession(
        authService: AuthService(dio: dio),
        storage: InMemoryAuthStorage(),
      );

      final first = session.login(email: 'john@mail.com', password: 'changeme');
      await expectLater(
        session.login(email: 'john@mail.com', password: 'changeme'),
        throwsA(isA<AuthException>()),
      );
      await first;
    });

    test('restoreSession returns user when tokens are valid', () async {
      final storage = InMemoryAuthStorage();
      await storage.saveSession(
        accessToken: 'test-access-token',
        refreshToken: 'test-refresh-token',
      );
      final dio = Dio(BaseOptions(baseUrl: ApiConstants.baseApiUrl));
      DioAdapter(dio: dio, matcher: const UrlRequestMatcher()).onGet(
        ApiConstants.profile,
        (server) => server.reply(200, _testUserJson),
      );
      final session = AuthSession(
        authService: AuthService(dio: dio),
        storage: storage,
      );

      final user = await session.restoreSession();
      expect(user?.email, 'john@mail.com');
      expect(session.isAuthenticated, isTrue);
    });

    test('restoreSession refreshes an expired access token', () async {
      final storage = InMemoryAuthStorage();
      await storage.saveSession(
        accessToken: 'expired',
        refreshToken: 'test-refresh-token',
      );
      final session = AuthSession(
        authService: _ExpiringThenValidAuthService(),
        storage: storage,
      );

      final user = await session.restoreSession();
      expect(user?.email, 'john@mail.com');
      expect(await storage.readAccessToken(), 'new-access-token');
    });

    test('restoreSession clears storage when refresh fails', () async {
      final storage = InMemoryAuthStorage();
      await storage.saveSession(
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
      final session = AuthSession(
        authService: AuthService(dio: dio),
        storage: storage,
      );

      expect(await session.restoreSession(), isNull);
      expect(await storage.hasSession(), isFalse);
      expect(session.isAuthenticated, isFalse);
    });

    test('restoreSession returns null with no stored session', () async {
      final session = AuthSession(
        authService: AuthService(
          dio: Dio(BaseOptions(baseUrl: ApiConstants.baseApiUrl)),
        ),
        storage: InMemoryAuthStorage(),
      );
      expect(await session.restoreSession(), isNull);
    });

    test('logout clears credentials', () async {
      final storage = InMemoryAuthStorage();
      await storage.saveSession(accessToken: 'a', refreshToken: 'r');
      final session = AuthSession(
        authService: AuthService(
          dio: Dio(BaseOptions(baseUrl: ApiConstants.baseApiUrl)),
        ),
        storage: storage,
      );
      // Simulate a logged-in user via a successful restore first.
      final dio = Dio(BaseOptions(baseUrl: ApiConstants.baseApiUrl));
      DioAdapter(dio: dio, matcher: const UrlRequestMatcher()).onGet(
        ApiConstants.profile,
        (server) => server.reply(200, _testUserJson),
      );
      final loggedIn = AuthSession(
        authService: AuthService(dio: dio),
        storage: storage,
      );
      await loggedIn.restoreSession();
      expect(loggedIn.isAuthenticated, isTrue);

      await loggedIn.logout();
      expect(await storage.hasSession(), isFalse);
      expect(loggedIn.isAuthenticated, isFalse);
      expect(session.isAuthenticated, isFalse);
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

    test('InMemoryAuthStorage round-trip', () async {
      final storage = InMemoryAuthStorage();
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
        AuthSession(
          authService: AuthService(dio: dio),
          storage: InMemoryAuthStorage(),
        ),
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
        AuthSession(
          authService: AuthService(dio: dio),
          storage: InMemoryAuthStorage(),
        ),
      );

      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.tap(find.text('Login'));
      await tester.pump();

      expect(find.text('Please enter your email'), findsOneWidget);
      expect(find.text('Please enter your password'), findsOneWidget);
    });
  });
}
