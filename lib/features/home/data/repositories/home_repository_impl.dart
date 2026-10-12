import '../../../../core/error/api_exception.dart';
import '../../../../core/error/app_failure.dart';
import '../../../../core/network/api_constants.dart';
import '../../domain/entities/category_entity.dart';
import '../../domain/entities/product_entity.dart';
import '../../domain/repositories/home_repository.dart';
import '../datasources/home_remote_data_source.dart';

/// [HomeRepository] implementation: delegates to the remote data source,
/// maps DTOs to domain entities, and translates [ApiException]s into typed
/// [AppFailure]s. The only failure type that escapes is [AppFailure].
class HomeRepositoryImpl implements HomeRepository {
  final HomeRemoteDataSource _remote;

  const HomeRepositoryImpl(this._remote);

  @override
  Future<List<CategoryEntity>> getCategories() async {
    try {
      final dtos = await _remote.getCategories();
      return dtos.map((dto) => dto.toEntity()).toList();
    } on ApiException catch (e) {
      throw AppFailure.fromApiException(e);
    }
  }

  @override
  Future<List<ProductEntity>> getProducts({
    int? limit,
    int? offset,
    int? categoryId,
    String? title,
  }) async {
    try {
      final dtos = await _remote.getProducts(
        limit: limit ?? ApiConstants.catalogPageSize,
        offset: offset ?? 0,
        categoryId: categoryId,
        title: title,
      );
      return dtos.map((dto) => dto.toEntity()).toList();
    } on ApiException catch (e) {
      throw AppFailure.fromApiException(e);
    }
  }

  @override
  Future<ProductEntity> getProductById(int id) async {
    try {
      final dto = await _remote.getProductById(id);
      return dto.toEntity();
    } on ApiException catch (e) {
      throw AppFailure.fromApiException(e);
    }
  }
}
