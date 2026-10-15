import 'package:flutter/foundation.dart' show listEquals;

import '../../domain/entities/product_entity.dart' as domain;
import 'category_model.dart';
import 'product_image_normalizer.dart';

/// Product DTO as returned by `GET /products` (and `GET /products/{id}`).
///
/// JSON decoding lives here; the Domain layer works with
/// [domain.ProductEntity]. The API uses `title` while the legacy UI model
/// uses `name`; that mapping happens in Presentation (see `ProductCard`).
/// The backend provides no colors/sizes/stock, so those are intentionally
/// left empty instead of inventing data.
class ProductModel {
  final int id;
  final String title;
  final double price;
  final String description;
  final List<String> images;
  final CategoryModel? category;

  const ProductModel({
    required this.id,
    required this.title,
    required this.price,
    required this.description,
    required this.images,
    this.category,
  });

  /// First usable image, or an empty string when the API provides none.
  String get primaryImage => images.isEmpty ? '' : images.first;

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    // Raw `images` may be a list, a single JSON-encoded string, or garbage.
    // Normalization extracts usable http(s) URLs and drops the rest without
    // throwing, so every product page (initial, paginated, filtered,
    // searched, details) shares the same safe parsing.
    final images = ProductImageNormalizer.normalize(json['images']);

    CategoryModel? category;
    if (json['category'] is Map) {
      category = CategoryModel.fromJson(
        Map<String, dynamic>.from(json['category'] as Map),
      );
    }

    return ProductModel(
      id: _asInt(json['id']),
      title: (json['title'] ?? '').toString(),
      price: _asDouble(json['price']),
      description: (json['description'] ?? '').toString(),
      images: images,
      category: category,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'price': price,
      'description': description,
      'images': images,
      'category': category?.toJson(),
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ProductModel &&
            other.id == id &&
            other.title == title &&
            other.price == price &&
            other.description == description &&
            listEquals(other.images, images) &&
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

  /// Maps this DTO to the domain entity at the Data/Domain boundary.
  domain.ProductEntity toEntity() {
    return domain.ProductEntity(
      id: id,
      title: title,
      price: price,
      description: description,
      images: List<String>.unmodifiable(images),
      category: category?.toEntity(),
    );
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value.toString()) ?? 0;
  }

  static double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }
}
