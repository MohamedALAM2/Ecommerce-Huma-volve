import 'package:flutter/foundation.dart';

import '../data/models/category_model.dart';
import '../data/models/product_model.dart';

/// Products-section status. Category selection and the category list are
/// separate fields so the selection stays visible while products load.
enum HomeStatus { initial, loading, success, empty, failure }

@immutable
class HomeState {
  final HomeStatus status;
  final List<CategoryModel> categories;

  /// `null` means the virtual "All" category is selected.
  final int? selectedCategoryId;
  final List<ProductModel> products;
  final String searchQuery;
  final bool isLoadingMore;
  final bool hasMore;
  final bool loadMoreError;
  final String? errorMessage;

  const HomeState({
    this.status = HomeStatus.initial,
    this.categories = const [],
    this.selectedCategoryId,
    this.products = const [],
    this.searchQuery = '',
    this.isLoadingMore = false,
    this.hasMore = true,
    this.loadMoreError = false,
    this.errorMessage,
  });

  bool get isAllSelected => selectedCategoryId == null;

  String selectedCategoryName() {
    final id = selectedCategoryId;
    if (id == null) return 'All';
    for (final category in categories) {
      if (category.id == id) return category.name;
    }
    return 'All';
  }

  HomeState copyWith({
    HomeStatus? status,
    List<CategoryModel>? categories,
    int? Function()? selectedCategoryId,
    List<ProductModel>? products,
    String? searchQuery,
    bool? isLoadingMore,
    bool? hasMore,
    bool? loadMoreError,
    String? Function()? errorMessage,
  }) {
    return HomeState(
      status: status ?? this.status,
      categories: categories ?? this.categories,
      selectedCategoryId: selectedCategoryId != null
          ? selectedCategoryId()
          : this.selectedCategoryId,
      products: products ?? this.products,
      searchQuery: searchQuery ?? this.searchQuery,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      loadMoreError: loadMoreError ?? this.loadMoreError,
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is HomeState &&
            other.status == status &&
            listEquals(other.categories, categories) &&
            other.selectedCategoryId == selectedCategoryId &&
            listEquals(other.products, products) &&
            other.searchQuery == searchQuery &&
            other.isLoadingMore == isLoadingMore &&
            other.hasMore == hasMore &&
            other.loadMoreError == loadMoreError &&
            other.errorMessage == errorMessage);
  }

  @override
  int get hashCode => Object.hash(
    status,
    Object.hashAll(categories),
    selectedCategoryId,
    Object.hashAll(products),
    searchQuery,
    isLoadingMore,
    hasMore,
    loadMoreError,
    errorMessage,
  );
}
