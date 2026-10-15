import 'dart:async';

import 'package:ecommerce_app_huma_volve/core/error/app_failure.dart';
import 'package:ecommerce_app_huma_volve/core/network/api_constants.dart';
import 'package:ecommerce_app_huma_volve/core/widgets/app_network_image.dart';
import 'package:ecommerce_app_huma_volve/features/home/cubit/home_cubit.dart';
import 'package:ecommerce_app_huma_volve/features/home/data/models/product_image_normalizer.dart';
import 'package:ecommerce_app_huma_volve/features/home/data/models/product_model.dart';
import 'package:ecommerce_app_huma_volve/features/home/domain/entities/category_entity.dart';
import 'package:ecommerce_app_huma_volve/features/home/domain/entities/product_entity.dart';
import 'package:ecommerce_app_huma_volve/features/home/domain/repositories/home_repository.dart';
import 'package:ecommerce_app_huma_volve/features/home/domain/usecases/get_categories_usecase.dart';
import 'package:ecommerce_app_huma_volve/features/home/domain/usecases/get_products_usecase.dart';
import 'package:ecommerce_app_huma_volve/features/home/widgets/product_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fakes (mirror home_test.dart contracts, self-contained)
// ---------------------------------------------------------------------------

class FakeHomeRepository implements HomeRepository {
  Future<List<ProductEntity>> Function({
    int? limit,
    int? offset,
    int? categoryId,
    String? title,
  })?
  productsHandler;

  final List<Map<String, dynamic>> productCalls = [];

  @override
  Future<List<CategoryEntity>> getCategories() async => [];

  @override
  Future<List<ProductEntity>> getProducts({
    int? limit,
    int? offset,
    int? categoryId,
    String? title,
  }) {
    productCalls.add({
      'limit': limit,
      'offset': offset,
      'categoryId': categoryId,
      'title': title,
    });
    final handler = productsHandler;
    if (handler != null) {
      return handler(
        limit: limit,
        offset: offset,
        categoryId: categoryId,
        title: title,
      );
    }
    return Future.value([]);
  }

  @override
  Future<ProductEntity> getProductById(int id) => throw UnimplementedError();
}

HomeCubit makeCubit(FakeHomeRepository repo) => HomeCubit(
  getProducts: GetProductsUseCase(repo),
  getCategories: GetCategoriesUseCase(repo),
);

ProductEntity product(
  int id, {
  List<String> images = const [],
  String title = 'P',
}) => ProductEntity(
  id: id,
  title: '$title$id',
  price: 1,
  description: 'd',
  images: images,
);

List<ProductEntity> pageOf(int start, [int count = 10]) =>
    List.generate(count, (i) => product(start + i));

// ---------------------------------------------------------------------------
// Image URL normalization
// ---------------------------------------------------------------------------

void main() {
  group('ProductImageNormalizer', () {
    test('keeps normal valid URLs verbatim', () {
      expect(
        ProductImageNormalizer.normalize([
          'https://i.imgur.com/cleats.jpeg',
          'http://example.com/a.png',
        ]),
        ['https://i.imgur.com/cleats.jpeg', 'http://example.com/a.png'],
      );
    });

    test('strips quotes, brackets, and surrounding whitespace', () {
      expect(
        ProductImageNormalizer.normalize([
          '["https://example.com/product.jpg"]',
          '[ "https://example.com/product.png" ]',
          '  https://example.com/a.jpg  ',
          '"https://example.com/b.jpg"',
          "'https://example.com/c.jpg'",
        ]),
        [
          'https://example.com/product.jpg',
          'https://example.com/product.png',
          'https://example.com/a.jpg',
          'https://example.com/b.jpg',
          'https://example.com/c.jpg',
        ],
      );
    });

    test('extracts multiple URLs from a JSON-like string', () {
      expect(
        ProductImageNormalizer.normalize([
          '["https://example.com/first.jpg","https://example.com/second.jpg"]',
        ]),
        ['https://example.com/first.jpg', 'https://example.com/second.jpg'],
      );
    });

    test('handles a raw string payload (not a list)', () {
      expect(
        ProductImageNormalizer.normalize('["https://example.com/product.jpg"]'),
        ['https://example.com/product.jpg'],
      );
      expect(ProductImageNormalizer.normalize('https://example.com/a.jpg'), [
        'https://example.com/a.jpg',
      ]);
    });

    test('drops empty, missing, and malformed values without throwing', () {
      expect(ProductImageNormalizer.normalize([]), isEmpty);
      expect(ProductImageNormalizer.normalize(null), isEmpty);
      expect(ProductImageNormalizer.normalize(''), isEmpty);
      expect(ProductImageNormalizer.normalize('[]'), isEmpty);
      expect(ProductImageNormalizer.normalize('""'), isEmpty);
      expect(
        ProductImageNormalizer.normalize(['', '  ', 'invalid-image-url']),
        isEmpty,
      );
      expect(ProductImageNormalizer.normalize([null, 42, true, {}]), isEmpty);
      // Never throws on unexpected shapes.
      expect(ProductImageNormalizer.normalize({'a': 1}), isEmpty);
    });

    test('rejects unsupported schemes and host-less URLs', () {
      expect(
        ProductImageNormalizer.normalize([
          'ftp://example.com/a.jpg',
          'data:image/png;base64,abc',
          'example.com/a.jpg',
          '//example.com/a.jpg',
          'http://',
          'https://',
        ]),
        isEmpty,
      );
      expect(
        ProductImageNormalizer.isValidImageUrl('ftp://x.com/a.jpg'),
        isFalse,
      );
      expect(ProductImageNormalizer.isValidImageUrl('http://'), isFalse);
      expect(
        ProductImageNormalizer.isValidImageUrl('https://example.com/a.jpg'),
        isTrue,
      );
    });

    test('preserves query strings and percent-encoding', () {
      const withQuery = 'https://placehold.co/600x600/png?text=Product&w=600';
      const encoded = 'https://example.com/a%20b.jpg?x=a%2Fb&y=1#frag';
      expect(ProductImageNormalizer.normalize([withQuery]), [withQuery]);
      expect(ProductImageNormalizer.normalize([encoded]), [encoded]);
    });

    test('dedupes while keeping order; skips invalid before valid', () {
      expect(
        ProductImageNormalizer.normalize([
          'https://example.com/a.jpg',
          'invalid-image-url',
          'https://example.com/a.jpg',
          'https://example.com/b.jpg',
          '["https://example.com/b.jpg"]',
        ]),
        ['https://example.com/a.jpg', 'https://example.com/b.jpg'],
      );
    });
  });

  group('ProductModel images', () {
    ProductModel modelWith(dynamic images) => ProductModel.fromJson({
      'id': 1,
      'title': 't',
      'price': 10,
      'description': 'd',
      'images': images,
    });

    test('cleans wrapped single-entry payloads (known API bug)', () {
      final model = modelWith(['["https://example.com/real.jpg"]']);
      expect(model.images, ['https://example.com/real.jpg']);
      expect(model.primaryImage, 'https://example.com/real.jpg');
    });

    test('missing images default to safe placeholder behavior', () {
      final missing = ProductModel.fromJson({'id': 9});
      expect(missing.images, isEmpty);
      expect(missing.primaryImage, '');

      final empty = modelWith([]);
      expect(empty.images, isEmpty);
      expect(empty.primaryImage, '');
    });

    test('shares parsing across paginated, filtered, and searched pages', () {
      // Same factory backs initial pages, load-more pages, category pages,
      // search pages, and details — one malformed entry must never crash.
      final paged = modelWith([
        'invalid-image-url',
        '["https://example.com/keep.jpg"]',
      ]);
      expect(paged.images, ['https://example.com/keep.jpg']);
    });
  });

  group('Day-four pagination verification', () {
    test('requests offsets 0, 10, 20, 30 with limit 10', () async {
      final repo = FakeHomeRepository();
      repo.productsHandler =
          ({int? limit, int? offset, int? categoryId, String? title}) async {
            return pageOf(offset ?? 0);
          };
      final cubit = makeCubit(repo);
      await cubit.loadHome();
      await cubit.loadMore();
      await cubit.loadMore();
      await cubit.loadMore();

      expect(repo.productCalls.map((c) => c['offset']).toList(), [
        0,
        10,
        20,
        30,
      ]);
      expect(repo.productCalls.map((c) => c['limit']).toList(), [
        10,
        10,
        10,
        10,
      ]);
      expect(cubit.state.products, hasLength(40));
      await cubit.close();
    });

    test('preserves category/search filters across pages', () async {
      final repo = FakeHomeRepository();
      repo.productsHandler =
          ({int? limit, int? offset, int? categoryId, String? title}) async {
            return pageOf(offset ?? 0);
          };
      final cubit = makeCubit(repo);
      await cubit.loadHome();
      await cubit.selectCategory(2);
      // Debounced search: wait past the 400ms window.
      cubit.onSearchChanged('shirt');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await cubit.loadMore();

      final last = repo.productCalls.last;
      expect(last['categoryId'], 2);
      expect(last['title'], 'shirt');
      expect(last['offset'], 10);
      expect(last['limit'], ApiConstants.catalogPageSize);
      await cubit.close();
    });

    test('filters repeated product IDs without re-requesting pages', () async {
      final repo = FakeHomeRepository();
      repo.productsHandler =
          ({int? limit, int? offset, int? categoryId, String? title}) async {
            if ((offset ?? 0) == 0) return pageOf(0);
            // Second page repeats IDs 8 and 9 (mutable backend data).
            return [product(8), product(9), ...pageOf(10, 8)];
          };
      final cubit = makeCubit(repo);
      await cubit.loadHome();
      await cubit.loadMore();
      // 10 unique + 8 new (2 duplicates dropped).
      expect(cubit.state.products.map((p) => p.id).toSet(), hasLength(18));
      // Offset still advanced by the raw page length (10 + 10).
      await cubit.loadMore();
      expect(repo.productCalls.map((c) => c['offset']).toList(), [0, 10, 20]);
      await cubit.close();
    });

    test('stale loadMore response is dropped after a filter change', () async {
      final repo = FakeHomeRepository();
      final gate = Completer<List<ProductEntity>>();
      repo.productsHandler =
          ({int? limit, int? offset, int? categoryId, String? title}) {
            if ((offset ?? 0) > 0 && categoryId == null) return gate.future;
            if (categoryId == 4) return Future.value([product(100)]);
            return Future.value(pageOf(0));
          };
      final cubit = makeCubit(repo);
      await cubit.loadHome();
      final pending = cubit.loadMore();
      await cubit.selectCategory(4);
      gate.complete([product(999)]);
      await pending;
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.selectedCategoryId, 4);
      expect(cubit.state.products.map((p) => p.id), [100]);
      await cubit.close();
    });

    test(
      'loadMore failure preserves products; retry refetches same page',
      () async {
        final repo = FakeHomeRepository();
        var page2Calls = 0;
        repo.productsHandler =
            ({int? limit, int? offset, int? categoryId, String? title}) async {
              if ((offset ?? 0) == 0) return pageOf(0);
              page2Calls++;
              if (page2Calls == 1) {
                throw const NetworkFailure('Down.');
              }
              return [];
            };
        final cubit = makeCubit(repo);
        await cubit.loadHome();
        await cubit.loadMore();
        expect(cubit.state.products, hasLength(10));
        expect(cubit.state.loadMoreError, isTrue);
        await cubit.retryLoadMore();
        expect(page2Calls, 2);
        expect(cubit.state.loadMoreError, isFalse);
        await cubit.close();
      },
    );
  });

  group('AppNetworkImage fallback', () {
    testWidgets('empty and malformed URLs render a placeholder', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(height: 100, child: AppNetworkImage(imageUrl: '')),
                SizedBox(
                  height: 100,
                  child: AppNetworkImage(imageUrl: 'invalid-image-url'),
                ),
                SizedBox(
                  height: 100,
                  child: AppNetworkImage(imageUrl: 'ftp://example.com/a.jpg'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      // No crash; each shows the local placeholder icon.
      expect(find.byIcon(Icons.image_outlined), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('product cards with unusable images render without crash', (
      tester,
    ) async {
      const bad = ProductEntity(
        id: 1,
        title: 'Broken image product',
        price: 9.99,
        description: 'd',
        images: [],
      );
      await tester.pumpWidget(
        BlocProvider(
          create: (_) => makeCubit(FakeHomeRepository()),
          child: const MaterialApp(
            home: Scaffold(body: ProductCard(product: bad)),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Broken image product'), findsOneWidget);
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
