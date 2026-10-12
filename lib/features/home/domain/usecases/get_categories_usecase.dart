import '../entities/category_entity.dart';
import '../repositories/home_repository.dart';

/// Fetches all catalog categories.
class GetCategoriesUseCase {
  final HomeRepository _repository;

  const GetCategoriesUseCase(this._repository);

  Future<List<CategoryEntity>> call() => _repository.getCategories();
}
