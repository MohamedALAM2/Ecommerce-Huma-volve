/// Category as returned by `GET /categories`.
class CategoryModel {
  final int id;
  final String name;
  final String image;

  const CategoryModel({
    required this.id,
    required this.name,
    required this.image,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: _asInt(json['id']),
      name: (json['name'] ?? '').toString(),
      image: (json['image'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'image': image};
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is CategoryModel &&
            other.id == id &&
            other.name == name &&
            other.image == image);
  }

  @override
  int get hashCode => Object.hash(id, name, image);

  static int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value.toString()) ?? 0;
  }
}
