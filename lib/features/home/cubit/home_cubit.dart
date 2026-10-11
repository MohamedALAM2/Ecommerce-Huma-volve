import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/network/api_constants.dart';
import '../data/catalog_exception.dart';
import '../data/models/category_model.dart';
import '../data/repositories/home_repository.dart';
import 'home_state.dart';

/// Manages the Home catalog: initial load, category filtering, backend
/// search (debounced), pagination, and retry.
///
/// Stale-response protection: every logical fetch takes a request id. Only
/// the latest request may emit, so a slow Category A response can never
/// overwrite Category B's products.
class HomeCubit extends Cubit<HomeState> {
  final HomeRepository _repository;
  Timer? _searchDebounce;

  int _requestId = 0;

  static const searchDebounce = Duration(milliseconds: 400);

  HomeCubit(this._repository) : super(const HomeState());

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
    List<CategoryModel> categories = state.categories;
    String? categoriesError;
    try {
      categories = await _repository.getCategories();
    } on CatalogException catch (e) {
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
      final products = await _repository.getProducts(
        limit: ApiConstants.catalogPageSize,
      );
      if (requestId != _requestId || isClosed) return;
      emit(
        state.copyWith(
          status: products.isEmpty ? HomeStatus.empty : HomeStatus.success,
          categories: categories,
          selectedCategoryId: () => null,
          products: products,
          hasMore: products.length == ApiConstants.catalogPageSize,
        ),
      );
    } on CatalogException catch (e) {
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
      final categories = await _repository.getCategories();
      if (isClosed) return;
      emit(
        state.copyWith(
          categories: categories,
          categoriesErrorMessage: () => null,
        ),
      );
    } on CatalogException catch (e) {
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
      final products = await _repository.getProducts(
        limit: ApiConstants.catalogPageSize,
        categoryId: categoryId,
        title: query.isEmpty ? null : query,
      );
      if (requestId != _requestId || isClosed) return;
      emit(
        state.copyWith(
          status: products.isEmpty ? HomeStatus.empty : HomeStatus.success,
          products: products,
          hasMore: products.length == ApiConstants.catalogPageSize,
        ),
      );
    } on CatalogException catch (e) {
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
    final offset = state.products.length;
    emit(state.copyWith(isLoadingMore: true, loadMoreError: false));
    try {
      final more = await _repository.getProducts(
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
      emit(
        state.copyWith(
          products: [...state.products, ...more],
          isLoadingMore: false,
          hasMore: more.length == ApiConstants.catalogPageSize,
        ),
      );
    } on CatalogException {
      if (isClosed || requestId != _requestId) return;
      emit(state.copyWith(isLoadingMore: false, loadMoreError: true));
    }
  }

  @override
  Future<void> close() {
    _searchDebounce?.cancel();
    return super.close();
  }
}
