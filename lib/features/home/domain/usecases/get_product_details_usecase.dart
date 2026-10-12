import '../entities/product_entity.dart';
import '../repositories/home_repository.dart';

/// Fetches a single product by id (used when the list item data is stale
/// or a deep link needs fresh details).
class GetProductDetailsUseCase {
  final HomeRepository _repository;

  const GetProductDetailsUseCase(this._repository);

  Future<ProductEntity> call(int id) => _repository.getProductById(id);
}
