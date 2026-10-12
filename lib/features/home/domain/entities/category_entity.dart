/// Catalog category as the application understands it.
///
/// Pure Dart: no JSON, no Dio, no Flutter. Data models map to this type at
/// the Data/Domain boundary.
class CategoryEntity {
  final int id;
  final String name;
  final String image;

  const CategoryEntity({
    required this.id,
    required this.name,
    required this.image,
  });

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is CategoryEntity &&
            other.id == id &&
            other.name == name &&
            other.image == image);
  }

  @override
  int get hashCode => Object.hash(id, name, image);
}
