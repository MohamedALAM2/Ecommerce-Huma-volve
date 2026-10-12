import 'dart:io';

import 'package:dio/dio.dart';
import 'package:ecommerce_app_huma_volve/core/di/app_dependencies.dart';
import 'package:ecommerce_app_huma_volve/core/error/api_exception.dart';
import 'package:ecommerce_app_huma_volve/core/error/app_failure.dart';
import 'package:ecommerce_app_huma_volve/core/error/dio_error_parser.dart';
import 'package:ecommerce_app_huma_volve/core/network/api_constants.dart';
import 'package:ecommerce_app_huma_volve/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:ecommerce_app_huma_volve/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:ecommerce_app_huma_volve/features/auth/data/models/auth_models.dart';
import 'package:ecommerce_app_huma_volve/features/auth/data/models/user_model.dart';
import 'package:ecommerce_app_huma_volve/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:ecommerce_app_huma_volve/features/auth/domain/entities/auth_tokens_entity.dart';
import 'package:ecommerce_app_huma_volve/features/auth/domain/entities/user_entity.dart';
import 'package:ecommerce_app_huma_volve/features/auth/domain/repositories/auth_repository.dart';
import 'package:ecommerce_app_huma_volve/features/auth/domain/usecases/get_profile_usecase.dart';
import 'package:ecommerce_app_huma_volve/features/auth/domain/usecases/login_usecase.dart';
import 'package:ecommerce_app_huma_volve/features/auth/domain/usecases/logout_usecase.dart';
import 'package:ecommerce_app_huma_volve/features/auth/domain/usecases/restore_session_usecase.dart';
import 'package:ecommerce_app_huma_volve/features/auth/domain/usecases/signup_usecase.dart';
import 'package:ecommerce_app_huma_volve/features/auth/session/auth_session.dart';
import 'package:ecommerce_app_huma_volve/features/home/cubit/home_cubit.dart';
import 'package:ecommerce_app_huma_volve/features/home/data/datasources/home_remote_data_source.dart';
import 'package:ecommerce_app_huma_volve/features/home/data/models/category_model.dart';
import 'package:ecommerce_app_huma_volve/features/home/data/models/product_model.dart';
import 'package:ecommerce_app_huma_volve/features/home/data/repositories/home_repository_impl.dart';
import 'package:ecommerce_app_huma_volve/features/home/domain/entities/category_entity.dart';
import 'package:ecommerce_app_huma_volve/features/home/domain/entities/product_entity.dart';
import 'package:ecommerce_app_huma_volve/features/home/domain/repositories/home_repository.dart';
import 'package:ecommerce_app_huma_volve/features/home/domain/usecases/get_categories_usecase.dart';
import 'package:ecommerce_app_huma_volve/features/home/domain/usecases/get_product_details_usecase.dart';
import 'package:ecommerce_app_huma_volve/features/home/domain/usecases/get_products_usecase.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fixtures & fakes (self-contained; mirrors the feature suites)
// ---------------------------------------------------------------------------

const _user = UserEntity(
  id: 1,
  email: 'john@mail.com',
  name: 'Jhon',
  role: 'customer',
  avatar: 'https://i.imgur.com/LDOO4Qs.jpg',
);

DioException _dioError({
  required String path,
  DioExceptionType type = DioExceptionType.unknown,
  Object? error,
  int? status,
  dynamic data,
}) {
  return DioException(
    requestOptions: RequestOptions(path: path),
    type: type,
    error: error,
    response: status == null && data == null
        ? null
        : Response(
            requestOptions: RequestOptions(path: path),
            statusCode: status,
            data: data,
          ),
  );
}

/// Fake AuthRepository with call logging and an in-memory token store.
class FakeAuthRepository implements AuthRepository {
  static const testTokens = AuthTokensEntity(
    accessToken: 'test-access-token',
    refreshToken: 'test-refresh-token',
  );
  static const refreshedTokens = AuthTokensEntity(
    accessToken: 'new-access-token',
    refreshToken: 'new-refresh-token',
  );

  Future<UserEntity> Function()? userHandler;
  Future<AuthTokensEntity> Function({
    required String email,
    required String password,
  })?
  loginHandler;
  Future<UserEntity> Function(String accessToken)? profileHandler;
  Future<AuthTokensEntity> Function(String refreshToken)? tokensHandler;

  final List<String> calls = [];
  String? storedAccessToken;
  String? storedRefreshToken;
  bool cleared = false;

  @override
  Future<UserEntity> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    calls.add('signUp');
    final handler = userHandler;
    if (handler != null) return handler();
    return _user;
  }

  @override
  Future<AuthTokensEntity> login({
    required String email,
    required String password,
  }) async {
    calls.add('login');
    final handler = loginHandler;
    if (handler != null) {
      return handler(email: email, password: password);
    }
    return testTokens;
  }

  @override
  Future<UserEntity> getProfile(String accessToken) async {
    calls.add('getProfile');
    final handler = profileHandler;
    if (handler != null) return handler(accessToken);
    final fallback = userHandler;
    if (fallback != null) return fallback();
    return _user;
  }

  @override
  Future<AuthTokensEntity> refreshToken(String refreshToken) async {
    calls.add('refreshToken');
    final handler = tokensHandler;
    if (handler != null) return handler(refreshToken);
    return refreshedTokens;
  }

  @override
  Future<bool> isEmailAvailable(String email) async => true;

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

/// Fake HomeRepository with call logging.
class FakeHomeRepository implements HomeRepository {
  final List<Map<String, dynamic>> productCalls = [];
  List<CategoryEntity> categoriesResult = const [];
  Future<List<ProductEntity>> Function({
    int? limit,
    int? offset,
    int? categoryId,
    String? title,
  })?
  productsHandler;
  Future<ProductEntity> Function(int id)? detailsHandler;

  @override
  Future<List<CategoryEntity>> getCategories() async => categoriesResult;

  @override
  Future<List<ProductEntity>> getProducts({
    int? limit,
    int? offset,
    int? categoryId,
    String? title,
  }) {
    productCalls.add({
      'limit': limit,
      'offset': offset,
      'categoryId': categoryId,
      'title': title,
    });
    final handler = productsHandler;
    if (handler != null) {
      return handler(
        limit: limit,
        offset: offset,
        categoryId: categoryId,
        title: title,
      );
    }
    return Future.value([]);
  }

  @override
  Future<ProductEntity> getProductById(int id) {
    final handler = detailsHandler;
    if (handler != null) return handler(id);
    throw UnimplementedError();
  }
}

/// Fake remote data source for repository-implementation tests.
class FakeAuthRemote extends AuthRemoteDataSource {
  FakeAuthRemote() : super(dio: Dio());

  UserModel? userToReturn;
  AuthTokens? tokensToReturn;
  bool? availabilityToReturn;
  ApiException? errorToThrow;

  @override
  Future<UserModel> signUp({
    required String name,
    required String email,
    required String password,
    String role = ApiConstants.defaultRole,
    String avatar = ApiConstants.defaultAvatar,
  }) async {
    final error = errorToThrow;
    if (error != null) throw error;
    return userToReturn!;
  }

  @override
  Future<AuthTokens> login({
    required String email,
    required String password,
  }) async {
    final error = errorToThrow;
    if (error != null) throw error;
    return tokensToReturn!;
  }

  @override
  Future<UserModel> getProfile(String accessToken) async {
    final error = errorToThrow;
    if (error != null) throw error;
    return userToReturn!;
  }

  @override
  Future<AuthTokens> refreshToken(String refreshTokenValue) async {
    final error = errorToThrow;
    if (error != null) throw error;
    return tokensToReturn!;
  }

  @override
  Future<bool> isEmailAvailable(String email) async {
    final error = errorToThrow;
    if (error != null) throw error;
    return availabilityToReturn ?? true;
  }
}

class FakeHomeRemote extends HomeRemoteDataSource {
  FakeHomeRemote() : super(Dio());

  List<CategoryModel> categoriesToReturn = const [];
  List<ProductModel> productsToReturn = const [];
  ProductModel? detailsToReturn;
  ApiException? errorToThrow;
  Map<String, dynamic>? lastProductsArgs;

  @override
  Future<List<CategoryModel>> getCategories() async {
    final error = errorToThrow;
    if (error != null) throw error;
    return categoriesToReturn;
  }

  @override
  Future<List<ProductModel>> getProducts({
    int limit = ApiConstants.catalogPageSize,
    int offset = 0,
    int? categoryId,
    String? title,
  }) async {
    lastProductsArgs = {
      'limit': limit,
      'offset': offset,
      'categoryId': categoryId,
      'title': title,
    };
    final error = errorToThrow;
    if (error != null) throw error;
    return productsToReturn;
  }

  @override
  Future<ProductModel> getProductById(int id) async {
    final error = errorToThrow;
    if (error != null) throw error;
    return detailsToReturn!;
  }
}

void main() {
  // -------------------------------------------------------------------------
  // Core error handling
  // -------------------------------------------------------------------------
  group('Core error mapping', () {
    test('dio parser classifies timeouts', () {
      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        final e = _dioError(path: '/x', type: type);
        expect(isTimeoutError(e), isTrue);
        expect(isNetworkError(e), isFalse);
      }
    });

    test('dio parser classifies network failures', () {
      final e = _dioError(
        path: '/x',
        type: DioExceptionType.connectionError,
        error: const SocketException('down'),
      );
      expect(isNetworkError(e), isTrue);
      expect(isTimeoutError(e), isFalse);
      expect(
        _dioError(path: '/x', type: DioExceptionType.unknown),
        predicate<DioException>(isNetworkError),
      );
    });

    test('dio parser extracts backend messages', () {
      expect(
        dioBackendMessage(_dioError(path: '/x', data: {'message': 'Bad!'})),
        'Bad!',
      );
      expect(
        dioBackendMessage(
          _dioError(
            path: '/x',
            data: {
              'message': ['a', 'b'],
            },
          ),
        ),
        'a\nb',
      );
      expect(dioBackendMessage(_dioError(path: '/x')), isNull);
      expect(dioStatusCode(_dioError(path: '/x', status: 404)), 404);
    });

    test('fromApiException maps every kind and status', () {
      AppFailure map(ApiException e) => AppFailure.fromApiException(e);
      expect(map(const ApiException.network('m')), isA<NetworkFailure>());
      expect(map(const ApiException.timeout('m')), isA<TimeoutFailure>());
      expect(
        map(const ApiException.response(400, 'm')),
        isA<ValidationFailure>(),
      );
      expect(
        map(const ApiException.response(422, 'm')),
        isA<ValidationFailure>(),
      );
      expect(
        map(const ApiException.response(401, 'm')),
        isA<UnauthorizedFailure>().having((f) => f.statusCode, 's', 401),
      );
      expect(
        map(const ApiException.response(403, 'm')),
        isA<ForbiddenFailure>(),
      );
      expect(
        map(const ApiException.response(404, 'm')),
        isA<NotFoundFailure>().having((f) => f.statusCode, 's', 404),
      );
      expect(
        map(const ApiException.response(429, 'm')),
        isA<RateLimitFailure>(),
      );
      expect(
        map(const ApiException.response(500, 'm')),
        isA<ServerFailure>().having((f) => f.statusCode, 's', 500),
      );
      expect(
        map(const ApiException.response(null, 'm')),
        isA<UnexpectedFailure>(),
      );
      expect(map(const ApiException.unknown('m')), isA<UnexpectedFailure>());
      // Messages are preserved verbatim.
      expect(
        map(const ApiException.response(401, 'Custom!')).message,
        'Custom!',
      );
    });
  });

  // -------------------------------------------------------------------------
  // Auth: repository implementation
  // -------------------------------------------------------------------------
  group('AuthRepositoryImpl', () {
    test('maps DTOs to entities', () async {
      final remote = FakeAuthRemote()
        ..userToReturn = UserModel.fromJson({
          'id': 1,
          'email': 'john@mail.com',
          'name': 'Jhon',
          'role': 'customer',
          'avatar': 'https://i.imgur.com/LDOO4Qs.jpg',
        })
        ..tokensToReturn = AuthTokens.fromJson({
          'access_token': 'a',
          'refresh_token': 'r',
        });
      final repo = AuthRepositoryImpl(
        remote: remote,
        local: InMemoryAuthLocalDataSource(),
      );

      expect(await repo.getProfile('x'), _user);
      expect(
        await repo.login(email: 'e', password: 'p'),
        const AuthTokensEntity(accessToken: 'a', refreshToken: 'r'),
      );
    });

    test('translates ApiException into typed failures', () async {
      final remote = FakeAuthRemote()
        ..errorToThrow = const ApiException.response(401, 'Nope.');
      final repo = AuthRepositoryImpl(
        remote: remote,
        local: InMemoryAuthLocalDataSource(),
      );

      await expectLater(
        () => repo.login(email: 'e', password: 'p'),
        throwsA(isA<UnauthorizedFailure>()),
      );

      remote.errorToThrow = const ApiException.network('Down.');
      await expectLater(
        () => repo.getProfile('x'),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('delegates session persistence to the local data source', () async {
      final local = InMemoryAuthLocalDataSource();
      final repo = AuthRepositoryImpl(remote: FakeAuthRemote(), local: local);

      await repo.saveSession(accessToken: 'a', refreshToken: 'r');
      expect(await repo.readAccessToken(), 'a');
      expect(await repo.readRefreshToken(), 'r');
      await repo.clearSession();
      expect(await local.hasSession(), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // Auth: use cases
  // -------------------------------------------------------------------------
  group('Auth use cases', () {
    test('SignUpUseCase delegates and returns the user', () async {
      final repo = FakeAuthRepository();
      final user = await SignUpUseCase(repo)(
        name: 'Jhon',
        email: 'john@mail.com',
        password: 'changeme',
      );
      expect(user, _user);
      expect(repo.calls, ['signUp']);
    });

    test('LoginUseCase orchestrates login, profile, and persistence', () async {
      final repo = FakeAuthRepository();
      final result = await LoginUseCase(repo)(
        email: 'john@mail.com',
        password: 'changeme',
      );
      expect(result.user, _user);
      expect(result.tokens, FakeAuthRepository.testTokens);
      expect(repo.calls, ['login', 'getProfile', 'saveSession']);
      expect(repo.storedAccessToken, 'test-access-token');
    });

    test('LoginUseCase never persists on login failure', () async {
      final repo = FakeAuthRepository()
        ..loginHandler = ({required email, required password}) async {
          throw const UnauthorizedFailure('Bad.', statusCode: 401);
        };
      await expectLater(
        () => LoginUseCase(repo)(email: 'e', password: 'p'),
        throwsA(isA<UnauthorizedFailure>()),
      );
      expect(repo.calls, ['login']);
      expect(repo.storedAccessToken, isNull);
    });

    test('GetProfileUseCase delegates', () async {
      final repo = FakeAuthRepository();
      expect(await GetProfileUseCase(repo)('token'), _user);
    });

    test('GetProfileUseCase delegates', () async {
      final repo = FakeAuthRepository();
      expect(await GetProfileUseCase(repo)('token'), _user);
      expect(repo.calls, ['getProfile']);
    });

    test('RestoreSessionUseCase returns the user for valid tokens', () async {
      final repo = FakeAuthRepository()
        ..storedAccessToken = 'a'
        ..storedRefreshToken = 'r';
      final result = await RestoreSessionUseCase(repo)();
      expect(result?.user, _user);
      expect(result?.tokens.accessToken, 'a');
      expect(repo.calls, ['getProfile']);
    });

    test('RestoreSessionUseCase refreshes once on 401', () async {
      final repo = FakeAuthRepository()
        ..storedAccessToken = 'expired'
        ..storedRefreshToken = 'r';
      var profileCalls = 0;
      repo.profileHandler = (_) async {
        profileCalls++;
        if (profileCalls == 1) {
          throw const UnauthorizedFailure('Expired.', statusCode: 401);
        }
        return _user;
      };
      final result = await RestoreSessionUseCase(repo)();
      expect(result?.user, _user);
      expect(result?.tokens.accessToken, 'new-access-token');
      expect(repo.storedAccessToken, 'new-access-token');
      expect(repo.cleared, isFalse);
    });

    test(
      'RestoreSessionUseCase clears on genuinely rejected refresh',
      () async {
        final repo = FakeAuthRepository()
          ..storedAccessToken = 'expired'
          ..storedRefreshToken = 'bad';
        repo.profileHandler = (_) async {
          throw const UnauthorizedFailure('Expired.', statusCode: 401);
        };
        repo.tokensHandler = (_) async {
          throw const UnauthorizedFailure('Revoked.', statusCode: 401);
        };
        expect(await RestoreSessionUseCase(repo)(), isNull);
        expect(repo.cleared, isTrue);
        expect(repo.storedAccessToken, isNull);
      },
    );

    test('RestoreSessionUseCase preserves tokens when offline', () async {
      final repo = FakeAuthRepository()
        ..storedAccessToken = 'a'
        ..storedRefreshToken = 'r';
      repo.profileHandler = (_) async {
        throw const NetworkFailure();
      };
      expect(await RestoreSessionUseCase(repo)(), isNull);
      expect(repo.cleared, isFalse);
      expect(repo.storedAccessToken, 'a');
      expect(repo.storedRefreshToken, 'r');
    });

    test('RestoreSessionUseCase preserves tokens on refresh timeout', () async {
      final repo = FakeAuthRepository()
        ..storedAccessToken = 'expired'
        ..storedRefreshToken = 'r';
      var profileCalls = 0;
      repo.profileHandler = (_) async {
        profileCalls++;
        if (profileCalls == 1) {
          throw const UnauthorizedFailure('Expired.', statusCode: 401);
        }
        return _user;
      };
      repo.tokensHandler = (_) async {
        throw const TimeoutFailure();
      };
      expect(await RestoreSessionUseCase(repo)(), isNull);
      expect(repo.cleared, isFalse);
      expect(repo.storedRefreshToken, 'r');
    });

    test('RestoreSessionUseCase returns null with no stored session', () async {
      expect(await RestoreSessionUseCase(FakeAuthRepository())(), isNull);
    });

    test('LogoutUseCase clears the session', () async {
      final repo = FakeAuthRepository()
        ..storedAccessToken = 'a'
        ..storedRefreshToken = 'r';
      await LogoutUseCase(repo)();
      expect(repo.cleared, isTrue);
      expect(repo.storedAccessToken, isNull);
    });

    test('entities compare by value', () {
      expect(
        const UserEntity(id: 1, email: 'e', name: 'n', role: 'r', avatar: 'a'),
        const UserEntity(id: 1, email: 'e', name: 'n', role: 'r', avatar: 'a'),
      );
      expect(
        const AuthTokensEntity(accessToken: 'a', refreshToken: 'r'),
        const AuthTokensEntity(accessToken: 'a', refreshToken: 'r'),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Home: repository implementation + use cases
  // -------------------------------------------------------------------------
  group('HomeRepositoryImpl', () {
    const dtoCategory = CategoryModel(id: 4, name: 'Shoes', image: 's.jpg');
    const dtoProduct = ProductModel(
      id: 35,
      title: 'Cleats',
      price: 39,
      description: 'd',
      images: ['https://i.imgur.com/x.jpeg'],
    );

    test('maps DTOs to entities', () async {
      final remote = FakeHomeRemote()
        ..categoriesToReturn = [dtoCategory]
        ..productsToReturn = [dtoProduct]
        ..detailsToReturn = dtoProduct;
      final repo = HomeRepositoryImpl(remote);

      expect(await repo.getCategories(), [
        const CategoryEntity(id: 4, name: 'Shoes', image: 's.jpg'),
      ]);
      expect((await repo.getProducts()).first.title, 'Cleats');
      expect((await repo.getProductById(35)).id, 35);
    });

    test('translates ApiException into typed failures', () async {
      final remote = FakeHomeRemote()
        ..errorToThrow = const ApiException.response(500, 'Boom.');
      final repo = HomeRepositoryImpl(remote);

      await expectLater(
        () => repo.getProducts(),
        throwsA(isA<ServerFailure>()),
      );

      remote.errorToThrow = const ApiException.network('Down.');
      await expectLater(
        () => repo.getCategories(),
        throwsA(isA<NetworkFailure>()),
      );
    });

    test('applies data-layer page defaults for null params', () async {
      final remote = FakeHomeRemote();
      final repo = HomeRepositoryImpl(remote);

      await repo.getProducts();
      expect(remote.lastProductsArgs, {
        'limit': ApiConstants.catalogPageSize,
        'offset': 0,
        'categoryId': null,
        'title': null,
      });
    });
  });

  group('Home use cases', () {
    test('use cases forward parameters to the repository', () async {
      final repo = FakeHomeRepository();
      const products = [
        ProductEntity(
          id: 1,
          title: 't',
          price: 1,
          description: 'd',
          images: [],
        ),
      ];
      repo.productsHandler = ({
        int? limit,
        int? offset,
        int? categoryId,
        String? title,
      }) async => products;

      expect(
        await GetProductsUseCase(repo)(
          limit: 10,
          offset: 5,
          categoryId: 4,
          title: 'shoe',
        ),
        products,
      );
      expect(repo.productCalls.single, {
        'limit': 10,
        'offset': 5,
        'categoryId': 4,
        'title': 'shoe',
      });

      // Nulls (no filter / data defaults) forward untouched.
      await GetProductsUseCase(repo)();
      expect(repo.productCalls.last, {
        'limit': null,
        'offset': null,
        'categoryId': null,
        'title': null,
      });
    });

    test('GetCategoriesUseCase delegates', () async {
      final repo = FakeHomeRepository()
        ..categoriesResult = const [
          CategoryEntity(id: 4, name: 'Shoes', image: 's.jpg'),
        ];
      expect(await GetCategoriesUseCase(repo)(), hasLength(1));
    });

    test('GetProductDetailsUseCase delegates by id', () async {
      const product = ProductEntity(
        id: 7,
        title: 't',
        price: 1,
        description: 'd',
        images: [],
      );
      final repo = FakeHomeRepository()
        ..detailsHandler = (id) async {
          expect(id, 7);
          return product;
        };
      expect(await GetProductDetailsUseCase(repo)(7), product);
    });
  });

  // -------------------------------------------------------------------------
  // Dependency injection
  // -------------------------------------------------------------------------
  group('AppDependencies', () {
    test('shares one Dio and wires working auth + home graphs', () async {
      final dependencies = AppDependencies();
      expect(identical(dependencies.dio, dependencies.dio), isTrue);

      // Auth graph: session built purely from abstractions.
      final session = dependencies.initAuthSession();
      expect(session, isA<AuthSession>());
      expect(AuthSession.instance, same(session));

      // Home graph: cubit over use cases (closed after the check).
      final cubit = dependencies.createHomeCubit();
      expect(cubit, isA<HomeCubit>());
      await cubit.close();
    });
  });
}
