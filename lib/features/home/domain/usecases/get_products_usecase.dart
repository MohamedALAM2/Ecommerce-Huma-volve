import '../entities/product_entity.dart';
import '../repositories/home_repository.dart';

/// Fetches a product page with the current filters. `null` parameters mean
/// "no filter / Data defaults" and are forwarded as-is.
class GetProductsUseCase {
  final HomeRepository _repository;

  const GetProductsUseCase(this._repository);

  Future<List<ProductEntity>> call({
    int? limit,
    int? offset,
    int? categoryId,
    String? title,
  }) {
    return _repository.getProducts(
      limit: limit,
      offset: offset,
      categoryId: categoryId,
      title: title,
    );
  }
}
