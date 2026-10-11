import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../../../core/network/api_constants.dart';
import '../catalog_exception.dart';
import '../models/category_model.dart';
import '../models/product_model.dart';

/// Read-only catalog access. All HTTP lives here — widgets and the Cubit
/// never touch Dio directly.
class HomeRepository {
  final Dio _dio;

  HomeRepository(this._dio);

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
        throw const CatalogException('Product not found.', statusCode: 404);
      }
      return ProductModel.fromJson(Map<String, dynamic>.from(data));
    } on DioException catch (e) {
      throw _mapError(e, fallback: 'Could not load product details.');
    } on CatalogException {
      rethrow;
    }
  }

  CatalogException _mapError(DioException e, {required String fallback}) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e is TimeoutException) {
      return const CatalogException(
        'Connection timed out. Please check your internet and try again.',
      );
    }
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.unknown ||
        e.error is SocketException) {
      return const CatalogException(
        'No internet connection. Please check your network and try again.',
      );
    }
    final status = e.response?.statusCode;
    if (status != null && status >= 500) {
      return const CatalogException('Server error. Please try again later.');
    }
    final data = e.response?.data;
    String? backend;
    if (data is Map && data['message'] is String) {
      backend = data['message'] as String;
    } else if (data is Map && data['message'] is List) {
      backend = (data['message'] as List).join('\n');
    }
    return CatalogException(backend ?? fallback, statusCode: status);
  }
}
