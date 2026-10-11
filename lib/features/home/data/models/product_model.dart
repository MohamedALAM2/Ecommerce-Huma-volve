import 'package:ecommerce_app_huma_volve/core/dummy_data.dart' show Product;
import 'package:flutter/foundation.dart' show listEquals;

import 'category_model.dart';

/// Product as returned by `GET /products` (and `GET /products/{id}`).
///
/// The API uses `title` while the legacy UI model uses `name`; the mapping
/// happens in [toProduct]. The backend provides no colors/sizes/stock, so
/// those are intentionally left empty instead of inventing data.
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
    final rawImages = json['images'];
    final images = <String>[];
    if (rawImages is List) {
      for (final item in rawImages) {
        final url = item.toString().trim();
        // Drop empty entries and non-URL junk like "[\"...\"]" leftovers.
        if (url.isNotEmpty && url.startsWith('http')) {
          images.add(url);
        }
      }
    }

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

  /// Compatibility adapter for [ProductDetailsScreen] and the Cart, which
  /// still operate on the legacy [Product] type. Variants are empty because
  /// the backend does not provide them; the details screen hides the
  /// color/size selectors when they are empty.
  Product toProduct() {
    return Product(
      id: '$id',
      name: title,
      description: description,
      price: price,
      imageUrl: primaryImage,
      colors: const [],
      sizes: const [],
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
