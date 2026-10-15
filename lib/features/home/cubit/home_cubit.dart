import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

// ignore_for_file: prefer_initializing_formals
// (Constructor takes public use-case parameters; fields are private.)

import '../../../../core/error/app_failure.dart';
import '../../../../core/network/api_constants.dart';
import '../domain/entities/category_entity.dart';
import '../domain/entities/product_entity.dart' as domain;
import '../domain/usecases/get_categories_usecase.dart';
import '../domain/usecases/get_products_usecase.dart';
import 'home_state.dart';

/// Manages the Home catalog: initial load, category filtering, backend
/// search (debounced), pagination, and retry.
///
/// Depends only on Domain use cases — never on Dio, data sources, or
/// concrete repositories. All state-management behavior (request-id
/// stale-response protection, debounce, pagination guards) is preserved
/// from the previous implementation.
///
/// Stale-response protection: every logical fetch takes a request id. Only
/// the latest request may emit, so a slow Category A response can never
/// overwrite Category B's products.
class HomeCubit extends Cubit<HomeState> {
  final GetProductsUseCase _getProducts;
  final GetCategoriesUseCase _getCategories;
  Timer? _searchDebounce;

  int _requestId = 0;

  /// Raw number of products fetched from the backend for the current filter.
  ///
  /// Pagination offsets must count what the backend has already skipped —
  /// not the deduplicated UI list. When a page repeats IDs (mutable backend
  /// data), the UI filters duplicates but [_loadedCount] still advances by
  /// the raw page length, so the next offset never re-requests the same page.
  int _loadedCount = 0;

  static const searchDebounce = Duration(milliseconds: 400);

  HomeCubit({
    required GetProductsUseCase getProducts,
    required GetCategoriesUseCase getCategories,
  }) : _getProducts = getProducts,
       _getCategories = getCategories,
       super(const HomeState());

  /// Initial load: categories first, then the first product page.
  ///
  /// Categories are emitted as soon as they arrive (so the chips appear
  /// early) and are preserved if the products request fails, keeping the
  /// error/retry state contextual. A categories failure is recorded
  /// explicitly ([HomeState.categoriesErrorMessage]) instead of being
  /// silently ignored, and never blocks products.
  Future<void> loadHome() async {
    _searchDebounce?.cancel();
    final requestId = ++_requestId;
    _loadedCount = 0;
    emit(
      state.copyWith(
        status: HomeStatus.loading,
        products: const [],
        searchQuery: '',
        hasMore: true,
        isLoadingMore: false,
        loadMoreError: false,
        errorMessage: () => null,
      ),
    );
    List<CategoryEntity> categories = state.categories;
    String? categoriesError;
    try {
      categories = await _getCategories();
    } on AppFailure catch (e) {
      // Explicit failure: keep previously loaded categories (if any) so the
      // UI can offer a categories-only retry alongside product results.
      categoriesError = e.message;
    }
    if (requestId != _requestId || isClosed) return;
    // No-op emission when unchanged (Cubit skips equal states).
    emit(
      state.copyWith(
        categories: categories,
        categoriesErrorMessage: () => categoriesError,
      ),
    );
    try {
      final products = await _getProducts(
        limit: ApiConstants.catalogPageSize,
        offset: 0,
      );
      if (requestId != _requestId || isClosed) return;
      _loadedCount = products.length;
      final unique = _deduplicate(products);
      emit(
        state.copyWith(
          status: unique.isEmpty ? HomeStatus.empty : HomeStatus.success,
          categories: categories,
          selectedCategoryId: () => null,
          products: unique,
          hasMore: products.length == ApiConstants.catalogPageSize,
        ),
      );
    } on AppFailure catch (e) {
      if (requestId != _requestId || isClosed) return;
      emit(
        state.copyWith(
          status: HomeStatus.failure,
          errorMessage: () => e.message,
        ),
      );
    }
  }

  /// Re-fetches only the category list, e.g. after a categories failure.
  ///
  /// Products, selection, search, and pagination are left untouched, and the
  /// current selection is preserved even if the refreshed list differs.
  /// Safe to call repeatedly: a repeated failure simply keeps the error.
  Future<void> retryCategories() async {
    try {
      final categories = await _getCategories();
      if (isClosed) return;
      emit(
        state.copyWith(
          categories: categories,
          categoriesErrorMessage: () => null,
        ),
      );
    } on AppFailure catch (e) {
      if (isClosed) return;
      emit(state.copyWith(categoriesErrorMessage: () => e.message));
    }
  }

  /// Selects a category (`null` = the virtual "All" chip) and loads its
  /// first page. The selection is emitted immediately; duplicate taps on
  /// the already-active filter are ignored.
  Future<void> selectCategory(int? categoryId) async {
    if (categoryId == state.selectedCategoryId &&
        state.searchQuery.isEmpty &&
        (state.status == HomeStatus.success ||
            state.status == HomeStatus.empty)) {
      return;
    }
    _searchDebounce?.cancel();
    final requestId = ++_requestId;
    _loadedCount = 0;
    emit(
      state.copyWith(
        status: HomeStatus.loading,
        selectedCategoryId: () => categoryId,
        products: const [],
        searchQuery: '',
        hasMore: true,
        isLoadingMore: false,
        loadMoreError: false,
        errorMessage: () => null,
      ),
    );
    await _fetchFirstPage(requestId);
  }

  /// Debounced backend title search within the current category filter.
  void onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(searchDebounce, () => _search(query.trim()));
  }

  Future<void> _search(String query) async {
    final requestId = ++_requestId;
    _loadedCount = 0;
    emit(
      state.copyWith(
        status: HomeStatus.loading,
        products: const [],
        searchQuery: query,
        hasMore: true,
        isLoadingMore: false,
        loadMoreError: false,
        errorMessage: () => null,
      ),
    );
    await _fetchFirstPage(requestId);
  }

  /// Re-runs the current filter (category + search) from page one.
  Future<void> retry() async {
    // A keystroke timer firing mid-retry would hijack the filter, so a
    // manual retry always wins over pending input.
    _searchDebounce?.cancel();
    final requestId = ++_requestId;
    _loadedCount = 0;
    emit(
      state.copyWith(
        status: HomeStatus.loading,
        products: const [],
        hasMore: true,
        isLoadingMore: false,
        loadMoreError: false,
        errorMessage: () => null,
      ),
    );
    await _fetchFirstPage(requestId);
  }

  Future<void> _fetchFirstPage(int requestId) async {
    // Capture the filter at call time; the state may change while awaiting.
    final categoryId = state.selectedCategoryId;
    final query = state.searchQuery;
    try {
      final products = await _getProducts(
        limit: ApiConstants.catalogPageSize,
        offset: 0,
        categoryId: categoryId,
        title: query.isEmpty ? null : query,
      );
      if (requestId != _requestId || isClosed) return;
      _loadedCount = products.length;
      final unique = _deduplicate(products);
      emit(
        state.copyWith(
          status: unique.isEmpty ? HomeStatus.empty : HomeStatus.success,
          products: unique,
          hasMore: products.length == ApiConstants.catalogPageSize,
        ),
      );
    } on AppFailure catch (e) {
      if (requestId != _requestId || isClosed) return;
      emit(
        state.copyWith(
          status: HomeStatus.failure,
          errorMessage: () => e.message,
        ),
      );
    }
  }

  /// Appends the next page. Keeps existing products visible; a stale
  /// response (after a filter change) is dropped.
  ///
  /// After a failure ([HomeState.loadMoreError]) the scroll listener must
  /// NOT trigger another fetch: only an explicit [retryLoadMore] retries
  /// the failed page.
  Future<void> loadMore() async {
    if (state.isLoadingMore || state.loadMoreError || !state.hasMore) return;
    if (state.status != HomeStatus.success) return;
    await _fetchNextPage();
  }

  /// Manually retries the failed page after [HomeState.loadMoreError].
  /// Refetches the same offset with the current category/search filters.
  Future<void> retryLoadMore() async {
    if (state.isLoadingMore || !state.loadMoreError) return;
    if (state.status != HomeStatus.success) return;
    await _fetchNextPage();
  }

  Future<void> _fetchNextPage() async {
    final requestId = _requestId;
    final categoryId = state.selectedCategoryId;
    final query = state.searchQuery;
    // Offset counts raw backend items (see [_loadedCount]), never the
    // deduplicated UI list, so repeated IDs cannot cause repeated pages.
    final offset = _loadedCount;
    emit(state.copyWith(isLoadingMore: true, loadMoreError: false));
    try {
      final more = await _getProducts(
        limit: ApiConstants.catalogPageSize,
        offset: offset,
        categoryId: categoryId,
        title: query.isEmpty ? null : query,
      );
      if (isClosed || requestId != _requestId) return;
      if (categoryId != state.selectedCategoryId ||
          query != state.searchQuery) {
        return;
      }
      _loadedCount += more.length;
      emit(
        state.copyWith(
          products: _appendUnique(state.products, more),
          isLoadingMore: false,
          hasMore: more.length == ApiConstants.catalogPageSize,
        ),
      );
    } on AppFailure {
      if (isClosed || requestId != _requestId) return;
      emit(state.copyWith(isLoadingMore: false, loadMoreError: true));
    }
  }

  @override
  Future<void> close() {
    _searchDebounce?.cancel();
    return super.close();
  }

  /// Removes repeated product IDs while preserving order. Used for the
  /// first page, where the whole list comes from a single response.
  List<domain.ProductEntity> _deduplicate(List<domain.ProductEntity> items) {
    final seen = <int>{};
    final unique = <domain.ProductEntity>[];
    for (final item in items) {
      if (seen.add(item.id)) unique.add(item);
    }
    return unique;
  }

  /// Appends only products whose IDs are not already visible.
  List<domain.ProductEntity> _appendUnique(
    List<domain.ProductEntity> current,
    List<domain.ProductEntity> incoming,
  ) {
    if (incoming.isEmpty) return current;
    final seen = <int>{for (final item in current) item.id};
    final result = [...current];
    for (final item in incoming) {
      if (seen.add(item.id)) result.add(item);
    }
    return result;
  }
}
