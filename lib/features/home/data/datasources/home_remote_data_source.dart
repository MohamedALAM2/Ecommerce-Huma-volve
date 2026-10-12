import 'package:dio/dio.dart';

import '../../../../core/error/api_exception.dart';
import '../../../../core/error/dio_error_parser.dart';
import '../../../../core/network/api_constants.dart';
import '../models/category_model.dart';
import '../models/product_model.dart';

/// Catalog HTTP calls. Returns DTOs, never domain entities, and throws
/// [ApiException] (never raw `DioException`). Repository implementations
/// translate these into typed domain failures.
class HomeRemoteDataSource {
  final Dio _dio;

  HomeRemoteDataSource(this._dio);

  /// `GET /categories`.
  Future<List<CategoryModel>> getCategories() async {
    try {
      final response = await _dio.get<List<dynamic>>(ApiConstants.categories);
      final data = response.data ?? [];
      return data
          .whereType<Map<String, dynamic>>()
          .map(CategoryModel.fromJson)
          .toList();
    } on DioException catch (e) {
      throw _mapError(e, fallback: 'Could not load categories.');
    } catch (_) {
      // Non-Dio mapping failures (unexpected shapes): still an
      // application-level failure so the Cubit can show error + Retry.
      throw const ApiException.unknown('Could not load categories.');
    }
  }

  /// `GET /products` with pagination and optional filters.
  ///
  /// [categoryId] filters server-side; [title] performs a backend title
  /// search. Both may be combined.
  Future<List<ProductModel>> getProducts({
    int limit = ApiConstants.catalogPageSize,
    int offset = 0,
    int? categoryId,
    String? title,
  }) async {
    final query = <String, dynamic>{'limit': limit, 'offset': offset};
    if (categoryId != null) query['categoryId'] = categoryId;
    final trimmedTitle = title?.trim();
    if (trimmedTitle != null && trimmedTitle.isNotEmpty) {
      query['title'] = trimmedTitle;
    }
    try {
      final response = await _dio.get<List<dynamic>>(
        ApiConstants.products,
        queryParameters: query,
      );
      final data = response.data ?? [];
      return data
          .whereType<Map<String, dynamic>>()
          .map(ProductModel.fromJson)
          .toList();
    } on DioException catch (e) {
      throw _mapError(e, fallback: 'Could not load products.');
    } catch (_) {
      throw const ApiException.unknown('Could not load products.');
    }
  }

  /// `GET /products/{id}`.
  Future<ProductModel> getProductById(int id) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        ApiConstants.productById(id),
      );
      final data = response.data;
      if (data == null) {
        throw const ApiException.response(404, 'Product not found.');
      }
      return ProductModel.fromJson(Map<String, dynamic>.from(data));
    } on DioException catch (e) {
      throw _mapError(e, fallback: 'Could not load product details.');
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException.unknown('Could not load product details.');
    }
  }

  ApiException _mapError(DioException e, {required String fallback}) {
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
    final status = dioStatusCode(e);
    if (status != null && status >= 500) {
      return ApiException.response(
        status,
        'Server error. Please try again later.',
      );
    }
    final backend = dioBackendMessage(e);
    return ApiException.response(status, backend ?? fallback);
  }
}
