import '../entities/category_entity.dart';
import '../entities/product_entity.dart';

/// What the application needs from the catalog, expressed without any HTTP,
/// DTO, or pagination-implementation details.
///
/// Implemented in Data; consumed by use cases (and therefore, indirectly, by
/// the Cubit). All methods throw an [AppFailure] (see `core/error`) on
/// failure instead of returning error codes.
abstract class HomeRepository {
  /// All categories (`GET /categories`).
  Future<List<CategoryEntity>> getCategories();

  /// Product page (`GET /products`) with optional server-side filters.
  /// `null` limit/offset fall back to the Data layer's page defaults.
  Future<List<ProductEntity>> getProducts({
    int? limit,
    int? offset,
    int? categoryId,
    String? title,
  });

  /// Single product (`GET /products/{id}`).
  Future<ProductEntity> getProductById(int id);
}
