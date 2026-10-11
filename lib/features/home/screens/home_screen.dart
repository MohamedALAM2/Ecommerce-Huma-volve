import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/dummy_data.dart';
import '../../../core/theme.dart';
import '../cubit/home_cubit.dart';
import '../cubit/home_state.dart';
import '../widgets/category_chip.dart';
import '../widgets/product_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final TextEditingController _searchController;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    final cubit = context.read<HomeCubit>();
    // Restore the search text if the screen rebuilds (e.g. tab switch)
    // while a query is active.
    _searchController = TextEditingController(text: cubit.state.searchQuery);
    _scrollController = ScrollController()..addListener(_onScroll);
    if (cubit.state.status == HomeStatus.initial) {
      cubit.loadHome();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    // Load more as the user approaches the bottom.
    if (position.pixels >= position.maxScrollExtent - 300) {
      context.read<HomeCubit>().loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withValues(alpha: 0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.menu,
                            color: AppTheme.primary,
                          ),
                        ),
                        CircleAvatar(
                          radius: 24,
                          backgroundImage: NetworkImage(
                            dummyUser.profilePictureUrl,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'Explore',
                      style: Theme.of(context).textTheme.displayLarge
                          ?.copyWith(fontSize: 36),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Best trendy collection!',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(fontSize: 18),
                    ),
                    const SizedBox(height: 32),
                    BlocListener<HomeCubit, HomeState>(
                      // The Cubit owns the query: category switches clear it
                      // (even while a keystroke debounce is still pending, in
                      // which case the query never reached the state) and
                      // retries re-assert it. Mirror it into the field so the
                      // visible text always matches the applied filter.
                      listenWhen: (previous, current) =>
                          previous.searchQuery != current.searchQuery ||
                          previous.selectedCategoryId !=
                              current.selectedCategoryId,
                      listener: (context, state) {
                        final controller = _searchController;
                        if (controller.text == state.searchQuery) return;
                        // Don't fight mid-typing whitespace: results already
                        // match the trimmed query.
                        if (controller.text.trim() == state.searchQuery) {
                          return;
                        }
                        controller.text = state.searchQuery;
                        controller.selection = TextSelection.collapsed(
                          offset: controller.text.length,
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withValues(alpha: 0.05),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: _searchController,
                          onChanged: (value) =>
                              context.read<HomeCubit>().onSearchChanged(value),
                          decoration: InputDecoration(
                            hintText: 'Search clothes...',
                            hintStyle: TextStyle(color: Colors.grey.shade400),
                            prefixIcon: const Icon(
                              Icons.search,
                              color: Colors.grey,
                            ),
                            suffixIcon: Container(
                              margin: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.tune,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    BlocBuilder<HomeCubit, HomeState>(
                      buildWhen: (previous, current) =>
                          previous.categories != current.categories ||
                          previous.selectedCategoryId !=
                              current.selectedCategoryId ||
                          previous.status != current.status,
                      builder: (context, state) {
                        final chips = <Widget>[
                          CategoryChip(
                            label: 'All',
                            isSelected: state.isAllSelected,
                            onTap: () =>
                                context.read<HomeCubit>().selectCategory(null),
                          ),
                        ];
                        for (final category in state.categories) {
                          chips.add(
                            CategoryChip(
                              label: category.name,
                              isSelected:
                                  state.selectedCategoryId == category.id,
                              onTap: () => context
                                  .read<HomeCubit>()
                                  .selectCategory(category.id),
                            ),
                          );
                        }
                        return SizedBox(
                          height: 44,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: chips.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(width: 12),
                            itemBuilder: (context, index) => chips[index],
                          ),
                        );
                      },
                    ),
                    BlocBuilder<HomeCubit, HomeState>(
                      // Categories-only failure banner. Products are
                      // independent and stay visible; this retries just the
                      // category list without touching them.
                      buildWhen: (previous, current) =>
                          previous.categoriesErrorMessage !=
                          current.categoriesErrorMessage,
                      builder: (context, state) {
                        final message = state.categoriesErrorMessage;
                        if (message == null) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.error.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  size: 18,
                                  color: AppTheme.error,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Categories unavailable. $message',
                                    style: const TextStyle(
                                      color: AppTheme.error,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => context
                                      .read<HomeCubit>()
                                      .retryCategories(),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppTheme.error,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                  ),
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            BlocBuilder<HomeCubit, HomeState>(
              builder: (context, state) {
                switch (state.status) {
                  case HomeStatus.initial:
                  case HomeStatus.loading:
                    // First load or filter change: keep the header/chips
                    // visible and show content-area loading.
                    return const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppTheme.primary,
                        ),
                      ),
                    );
                  case HomeStatus.failure:
                    return SliverFillRemaining(
                      hasScrollBody: false,
                      child: _ErrorView(
                        message: state.errorMessage ?? 'Something went wrong.',
                        onRetry: () => context.read<HomeCubit>().retry(),
                      ),
                    );
                  case HomeStatus.empty:
                    return SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyView(
                        searchQuery: state.searchQuery,
                        categoryName: state.selectedCategoryName(),
                      ),
                    );
                  case HomeStatus.success:
                    return _ProductGrid(state: state);
                }
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

class _ProductGrid extends StatelessWidget {
  final HomeState state;

  const _ProductGrid({required this.state});

  @override
  Widget build(BuildContext context) {
    return SliverMainAxisGroup(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.7,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              return ProductCard(product: state.products[index]);
            }, childCount: state.products.length),
          ),
        ),
        if (state.isLoadingMore)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: CircularProgressIndicator(color: AppTheme.primary),
              ),
            ),
          ),
        if (state.loadMoreError)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: TextButton(
                  // Explicit retry only: the scroll listener deliberately
                  // ignores failed pages (see HomeCubit.loadMore).
                  onPressed: () => context.read<HomeCubit>().retryLoadMore(),
                  child: const Text('Couldn\'t load more. Tap to retry.'),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final String searchQuery;
  final String categoryName;

  const _EmptyView({required this.searchQuery, required this.categoryName});

  @override
  Widget build(BuildContext context) {
    final message = searchQuery.isNotEmpty
        ? 'No matches for "$searchQuery".'
        : 'No products in $categoryName yet.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
