/// Centralised API endpoint definitions for the Platzi Fake Store API.
///
/// Base URL: https://api.escuelajs.co/api/v1
/// Docs: https://api.escuelajs.co/docs
abstract final class ApiConstants {
  static const String baseUrl = 'https://api.escuelajs.co';
  static const String apiVersion = '/api/v1';
  static const String baseApiUrl = '$baseUrl$apiVersion';

  static const String users = '/users';
  static const String usersIsAvailable = '/users/is-available';
  static const String login = '/auth/login';
  static const String profile = '/auth/profile';
  static const String refreshToken = '/auth/refresh-token';

  static const String products = '/products';
  static const String categories = '/categories';

  static String categoryProducts(int categoryId) =>
      '$categories/$categoryId/products';
  static String productById(int productId) => '$products/$productId';

  /// Defaults required by `POST /users` (all fields are required by the API:
  /// email, name, password, role, avatar). The UI only collects name/email/
  /// password, so these valid values are supplied without extra UI.
  static const String defaultRole = 'customer';
  static const String defaultAvatar = 'https://i.imgur.com/LDOO4Qs.jpg';

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 15);
  static const Duration sendTimeout = Duration(seconds: 15);

  /// Default page size for catalog pagination.
  static const int catalogPageSize = 10;
}
