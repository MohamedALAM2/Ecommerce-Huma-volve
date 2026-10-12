import 'category_entity.dart';

/// Catalog product as the application understands it.
///
/// Pure Dart: no JSON, no Dio, no Flutter, no UI models. The backend
/// provides no colors/sizes/stock, so none are invented here either.
class ProductEntity {
  final int id;
  final String title;
  final double price;
  final String description;
  final List<String> images;
  final CategoryEntity? category;

  const ProductEntity({
    required this.id,
    required this.title,
    required this.price,
    required this.description,
    required this.images,
    this.category,
  });

  /// First usable image, or an empty string when none is available.
  String get primaryImage => images.isEmpty ? '' : images.first;

  static bool _imagesEqual(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ProductEntity &&
            other.id == id &&
            other.title == title &&
            other.price == price &&
            other.description == description &&
            _imagesEqual(other.images, images) &&
            other.category == category);
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    price,
    description,
    Object.hashAll(images),
    category,
  );
}
