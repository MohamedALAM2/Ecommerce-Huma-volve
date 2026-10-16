import 'package:dio/dio.dart';

import '../../features/auth/data/datasources/auth_local_data_source.dart';
import '../../features/auth/data/datasources/auth_remote_data_source.dart';
import '../../features/auth/data/repositories/auth_repository_impl.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/auth/domain/usecases/get_profile_usecase.dart';
import '../../features/auth/domain/usecases/login_usecase.dart';
import '../../features/auth/domain/usecases/logout_usecase.dart';
import '../../features/auth/domain/usecases/restore_session_usecase.dart';
import '../../features/auth/domain/usecases/signup_usecase.dart';
import '../../features/auth/session/auth_session.dart';
import '../../features/home/cubit/home_cubit.dart';
import '../../features/home/data/datasources/home_remote_data_source.dart';
import '../../features/home/data/repositories/home_repository_impl.dart';
import '../../features/home/domain/repositories/home_repository.dart';
import '../../features/home/domain/usecases/get_categories_usecase.dart';
import '../../features/home/domain/usecases/get_product_details_usecase.dart';
import '../../features/home/domain/usecases/get_products_usecase.dart';
import '../deep_links/deep_link_coordinator.dart';
import '../network/dio_client.dart';

/// Application composition root: builds the object graph once, in one
/// place, with constructor injection throughout.
///
/// A single shared [Dio] instance serves every remote data source (no
/// redundant clients). Repository implementations depend only on domain
/// contracts; use cases depend only on repositories; [AuthSession] and
/// [HomeCubit] depend only on use cases.
class AppDependencies {
  Dio? _dio;
  AuthLocalDataSource? _authLocal;
  AuthRepository? _authRepository;
  HomeRepository? _homeRepository;
  DeepLinkCoordinator? _deepLinks;

  /// Shared HTTP client for the whole app.
  Dio get dio => _dio ??= DioClient.create();

  AuthLocalDataSource get authLocalDataSource =>
      _authLocal ??= SecureAuthLocalDataSource();

  AuthRepository get authRepository => _authRepository ??= AuthRepositoryImpl(
    remote: AuthRemoteDataSource(dio: dio),
    local: authLocalDataSource,
  );

  HomeRepository get homeRepository =>
      _homeRepository ??= HomeRepositoryImpl(HomeRemoteDataSource(dio));

  // -- Auth use cases ------------------------------------------------------

  SignUpUseCase createSignUpUseCase() => SignUpUseCase(authRepository);
  LoginUseCase createLoginUseCase() => LoginUseCase(authRepository);
  GetProfileUseCase createGetProfileUseCase() =>
      GetProfileUseCase(authRepository);
  RestoreSessionUseCase createRestoreSessionUseCase() =>
      RestoreSessionUseCase(authRepository);
  LogoutUseCase createLogoutUseCase() => LogoutUseCase(authRepository);

  /// Initialises the shared [AuthSession] singleton on use-case
  /// abstractions (called once from `main()`).
  AuthSession initAuthSession() {
    return AuthSession.init(
      signUp: createSignUpUseCase(),
      login: createLoginUseCase(),
      restoreSession: createRestoreSessionUseCase(),
      logout: createLogoutUseCase(),
    );
  }

  // -- Home ----------------------------------------------------------------

  GetProductsUseCase createGetProductsUseCase() =>
      GetProductsUseCase(homeRepository);
  GetCategoriesUseCase createGetCategoriesUseCase() =>
      GetCategoriesUseCase(homeRepository);
  GetProductDetailsUseCase createGetProductDetailsUseCase() =>
      GetProductDetailsUseCase(homeRepository);

  /// Central deep-link coordinator (single instance per composition root).
  /// The navigator key is attached by `MyApp` once its [Navigator] exists;
  /// authentication is read live from the [AuthSession] singleton so
  /// logged-out links stay pending instead of navigating.
  DeepLinkCoordinator get deepLinkCoordinator =>
      _deepLinks ??= DeepLinkCoordinator(
        isAuthenticated: () => AuthSession.instance.isAuthenticated,
      );

  /// Fresh [HomeCubit] per owner (e.g. MainNavigationScreen), sharing the
  /// app-wide [Dio]. The owner must close it.
  HomeCubit createHomeCubit() {
    return HomeCubit(
      getProducts: createGetProductsUseCase(),
      getCategories: createGetCategoriesUseCase(),
    );
  }
}
