import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:dio/dio.dart';
import 'package:ecommerce_app_huma_volve/core/network/api_constants.dart';
import 'package:ecommerce_app_huma_volve/features/home/cubit/home_cubit.dart';
import 'package:ecommerce_app_huma_volve/features/home/cubit/home_state.dart';
import 'package:ecommerce_app_huma_volve/features/home/data/catalog_exception.dart';
import 'package:ecommerce_app_huma_volve/features/home/data/models/category_model.dart';
import 'package:ecommerce_app_huma_volve/features/home/data/models/product_model.dart';
import 'package:ecommerce_app_huma_volve/features/home/data/repositories/home_repository.dart';
import 'package:ecommerce_app_huma_volve/features/home/screens/home_screen.dart';
import 'package:ecommerce_app_huma_volve/features/home/widgets/category_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const tCatShoes = CategoryModel(id: 4, name: 'Shoes', image: 'shoes.jpg');
const tCatElectronics = CategoryModel(
  id: 2,
  name: 'Electronics',
  image: 'electronics.jpg',
);

const tShoe = ProductModel(
  id: 35,
  title: 'Futuristic Holographic Soccer Cleats',
  price: 39,
  description: 'Shiny cleats.',
  images: ['https://i.imgur.com/cleats.jpeg'],
  category: tCatShoes,
);

const tHoodie = ProductModel(
  id: 2,
  title: 'Classic Red Pullover Hoodie',
  price: 10,
  description: 'Cozy hoodie.',
  images: ['https://i.imgur.com/hoodie.jpeg'],
  category: null,
);

const tPhone = ProductModel(
  id: 20,
  title: 'Sleek Smartphone',
  price: 299.99,
  description: 'Fast phone.',
  images: ['https://i.imgur.com/phone.jpeg'],
  category: tCatElectronics,
);

Map<String, dynamic> shoeJson() => {
  'id': 35,
  'title': 'Futuristic Holographic Soccer Cleats',
  'price': 39,
  'description': 'Shiny cleats.',
  'category': {'id': 4, 'name': 'Shoes', 'image': 'shoes.jpg'},
  'images': ['https://i.imgur.com/cleats.jpeg', '', 'not-a-url', '  '],
};

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class FakeHomeRepository extends HomeRepository {
  FakeHomeRepository() : super(Dio());

  Future<List<CategoryModel>> Function()? categoriesHandler;
  Future<List<ProductModel>> Function({
    int limit,
    int offset,
    int? categoryId,
    String? title,
  })?
  productsHandler;

  final List<Map<String, dynamic>> productCalls = [];

  @override
  Future<List<CategoryModel>> getCategories() {
    final handler = categoriesHandler;
    if (handler != null) return handler();
    return Future.value([]);
  }

  @override
  Future<List<ProductModel>> getProducts({
    int limit = ApiConstants.catalogPageSize,
    int offset = 0,
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
}

Dio _mockedDio(void Function(DioAdapter adapter) configure) {
  final dio = Dio(BaseOptions(baseUrl: ApiConstants.baseApiUrl));
  configure(DioAdapter(dio: dio, matcher: const UrlRequestMatcher()));
  return dio;
}

DioException _networkError(String path) {
  return DioException(
    requestOptions: RequestOptions(path: path),
    type: DioExceptionType.connectionError,
    error: const SocketException('No internet'),
  );
}

// ---------------------------------------------------------------------------
// Fake image transport for widget tests.
//
// Widget tests must not hit the real network for NetworkImage (header
// avatar, product images). This serves a 1x1 PNG for every request.
// ---------------------------------------------------------------------------

final _kTransparentPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

class _FakeHttpHeaders implements HttpHeaders {
  final Map<String, List<String>> _values = {};

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    _values.putIfAbsent(name, () => []).add(value.toString());
  }

  @override
  List<String>? operator [](String name) => _values[name];

  @override
  String? value(String name) => _values[name]?.join(',');

  @override
  void forEach(void Function(String name, List<String> values) action) {
    _values.forEach(action);
  }

  @override
  void removeAll(String name) => _values.remove(name);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpResponse extends Stream<List<int>>
    implements HttpClientResponse {
  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => _kTransparentPng.length;

  @override
  HttpHeaders get headers => _FakeHttpHeaders();

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(_kTransparentPng).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpRequest implements HttpClientRequest {
  @override
  HttpHeaders get headers => _FakeHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => _FakeHttpResponse();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClient implements HttpClient {
  @override
  bool autoUncompress = false;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _FakeHttpRequest();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Runs [body] with mocked network images.
///
/// NetworkImage uses its own HTTP client; this debug hook swaps it for the
/// fake. The hook MUST be cleared before the test body returns — the
/// framework asserts painting debug vars are unset after each test, and
/// that check runs before package:test tearDown callbacks.
Future<void> _withMockImages(Future<void> Function() body) async {
  debugNetworkImageHttpClientProvider = () => _FakeHttpClient();
  try {
    await body();
  } finally {
    debugNetworkImageHttpClientProvider = null;
  }
}

/// Widget-test variant that serves mocked network images for the whole
/// body and clears the debug hook before returning (required by the
/// framework's post-test invariant check).
void _testHomeWidgets(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (tester) => _withMockImages(() => body(tester)));
}

/// Advances a fixed number of frames instead of [WidgetTester.pumpAndSettle].
///
/// Product images decode slowly (or not at all) in this headless test
/// environment, so their loading spinners never stop and pumpAndSettle
/// would time out. These tests assert on text and state — which render
/// deterministically — rather than on decoded pixels.
Future<void> _pumpFrames(WidgetTester tester, [int frames = 20]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  // -------------------------------------------------------------------------
  // Repository
  // -------------------------------------------------------------------------
  group('HomeRepository', () {
    test('getProducts parses products with nested category', () async {
      final dio = _mockedDio(
        (a) => a.onGet(
          ApiConstants.products,
          (server) => server.reply(200, [shoeJson()]),
        ),
      );
      final products = await HomeRepository(dio).getProducts();

      expect(products, hasLength(1));
      expect(products.first, tShoe);
      // Junk image entries are dropped.
      expect(products.first.images, ['https://i.imgur.com/cleats.jpeg']);
    });

    test('getProducts sends pagination and category params', () async {
      final dio = Dio(BaseOptions(baseUrl: ApiConstants.baseApiUrl));
      // Default (exact) matcher verifies the query parameters precisely.
      DioAdapter(dio: dio).onGet(
        ApiConstants.products,
        (server) => server.reply(200, []),
        queryParameters: {'limit': 10, 'offset': 0, 'categoryId': 4},
      );
      final products = await HomeRepository(dio)
          .getProducts(limit: 10, offset: 0, categoryId: 4);
      expect(products, isEmpty);
    });

    test('getProducts sends the title search param', () async {
      final dio = Dio(BaseOptions(baseUrl: ApiConstants.baseApiUrl));
      DioAdapter(dio: dio).onGet(
        ApiConstants.products,
        (server) => server.reply(200, []),
        queryParameters: {'limit': 10, 'offset': 0, 'title': 'hoodie'},
      );
      final products = await HomeRepository(dio).getProducts(title: 'hoodie');
      expect(products, isEmpty);
    });

    test('getCategories parses categories', () async {
      final dio = _mockedDio(
        (a) => a.onGet(
          ApiConstants.categories,
          (server) => server.reply(200, [
            {'id': 4, 'name': 'Shoes', 'image': 'shoes.jpg'},
            {'id': 2, 'name': 'Electronics'},
          ]),
        ),
      );
      final categories = await HomeRepository(dio).getCategories();

      expect(categories, hasLength(2));
      expect(categories.first, tCatShoes);
      // Missing optional image defaults to ''.
      expect(categories[1].image, '');
    });

    test('empty API responses map to empty lists', () async {
      final dio = _mockedDio((a) {
        a.onGet(ApiConstants.products, (server) => server.reply(200, []));
        a.onGet(ApiConstants.categories, (server) => server.reply(200, []));
      });
      final repo = HomeRepository(dio);
      expect(await repo.getProducts(), isEmpty);
      expect(await repo.getCategories(), isEmpty);
    });

    test('network failure and timeout map to friendly errors', () async {
      final networkDio = _mockedDio(
        (a) => a.onGet(
          ApiConstants.products,
          (server) => server.throws(0, _networkError(ApiConstants.products)),
        ),
      );
      await expectLater(
        () => HomeRepository(networkDio).getProducts(),
        throwsA(
          isA<CatalogException>().having(
            (e) => e.message,
            'message',
            contains('No internet'),
          ),
        ),
      );

      final timeoutDio = _mockedDio(
        (a) => a.onGet(
          ApiConstants.categories,
          (server) => server.throws(
            0,
            DioException(
              requestOptions: RequestOptions(path: ApiConstants.categories),
              type: DioExceptionType.connectionTimeout,
            ),
          ),
        ),
      );
      await expectLater(
        () => HomeRepository(timeoutDio).getCategories(),
        throwsA(
          isA<CatalogException>().having(
            (e) => e.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
    });

    test('server errors map to a generic message', () async {
      final dio = _mockedDio(
        (a) => a.onGet(
          ApiConstants.products,
          (server) => server.reply(500, {'message': 'Boom'}),
        ),
      );
      await expectLater(
        () => HomeRepository(dio).getProducts(),
        throwsA(
          isA<CatalogException>().having(
            (e) => e.message,
            'message',
            contains('Server error'),
          ),
        ),
      );
    });

    test('getProductById returns a single product', () async {
      final dio = _mockedDio(
        (a) => a.onGet(
          '${ApiConstants.products}/35',
          (server) => server.reply(200, shoeJson()),
        ),
      );
      expect(await HomeRepository(dio).getProductById(35), tShoe);
    });
  });

  // -------------------------------------------------------------------------
  // Models
  // -------------------------------------------------------------------------
  group('Catalog models', () {
    test('price parses int, double and string safely', () {
      ProductModel withPrice(dynamic price) => ProductModel.fromJson({
        'id': 1,
        'title': 't',
        'price': price,
        'description': 'd',
        'images': [],
      });
      expect(withPrice(44).price, 44.0);
      expect(withPrice(29.99).price, 29.99);
      expect(withPrice('15.5').price, 15.5);
      expect(withPrice(null).price, 0.0);
    });

    test('missing optionals default gracefully', () {
      final product = ProductModel.fromJson({'id': 9});
      expect(product.title, '');
      expect(product.images, isEmpty);
      expect(product.primaryImage, '');
      expect(product.category, isNull);
    });

    test('toProduct maps title->name and keeps string ids', () {
      final product = tShoe.toProduct();
      expect(product.id, '35');
      expect(product.name, tShoe.title);
      expect(product.price, 39.0);
      expect(product.colors, isEmpty);
      expect(product.sizes, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // Cubit
  // -------------------------------------------------------------------------
  group('HomeCubit', () {
    late FakeHomeRepository repo;

    setUp(() {
      repo = FakeHomeRepository();
      repo.categoriesHandler = () async => [tCatShoes, tCatElectronics];
      repo.productsHandler =
          ({
            int limit = 10,
            int offset = 0,
            int? categoryId,
            String? title,
          }) async {
            if (categoryId == 4) return [tShoe];
            if (categoryId == 2) return [tPhone];
            if (title == 'hoodie') return [tHoodie];
            if (title != null) return [];
            return [tShoe, tHoodie];
          };
    });

    blocTest<HomeCubit, HomeState>(
      'loadHome emits loading then success with categories and products',
      build: () => HomeCubit(repo),
      act: (cubit) => cubit.loadHome(),
      expect: () => [
        const HomeState(status: HomeStatus.loading),
        const HomeState(
          status: HomeStatus.loading,
          categories: [tCatShoes, tCatElectronics],
        ),
        const HomeState(
          status: HomeStatus.success,
          categories: [tCatShoes, tCatElectronics],
          products: [tShoe, tHoodie],
          hasMore: false,
        ),
      ],
    );

    blocTest<HomeCubit, HomeState>(
      'loadHome emits failure when products fail',
      setUp: () {
        repo.productsHandler =
            ({
              int limit = 10,
              int offset = 0,
              int? categoryId,
              String? title,
            }) async {
              throw const CatalogException('No internet connection.');
            };
      },
      build: () => HomeCubit(repo),
      act: (cubit) => cubit.loadHome(),
      expect: () => [
        const HomeState(status: HomeStatus.loading),
        const HomeState(
          status: HomeStatus.loading,
          categories: [tCatShoes, tCatElectronics],
        ),
        const HomeState(
          status: HomeStatus.failure,
          categories: [tCatShoes, tCatElectronics],
          errorMessage: 'No internet connection.',
        ),
      ],
    );

    blocTest<HomeCubit, HomeState>(
      'retry after failure reloads the current filter',
      setUp: () {
        var calls = 0;
        repo.productsHandler =
            ({
              int limit = 10,
              int offset = 0,
              int? categoryId,
              String? title,
            }) async {
              calls++;
              if (calls == 1) throw const CatalogException('Down.');
              return [tShoe];
            };
      },
      build: () => HomeCubit(repo),
      act: (cubit) async {
        await cubit.loadHome();
        await cubit.retry();
      },
      expect: () => [
        const HomeState(status: HomeStatus.loading),
        const HomeState(
          status: HomeStatus.loading,
          categories: [tCatShoes, tCatElectronics],
        ),
        const HomeState(
          status: HomeStatus.failure,
          categories: [tCatShoes, tCatElectronics],
          errorMessage: 'Down.',
        ),
        const HomeState(
          status: HomeStatus.loading,
          categories: [tCatShoes, tCatElectronics],
        ),
        const HomeState(
          status: HomeStatus.success,
          categories: [tCatShoes, tCatElectronics],
          products: [tShoe],
          hasMore: false,
        ),
      ],
    );

    blocTest<HomeCubit, HomeState>(
      'selectCategory filters by real category id and back to All',
      build: () => HomeCubit(repo),
      act: (cubit) async {
        await cubit.loadHome();
        await cubit.selectCategory(4);
        await cubit.selectCategory(null);
      },
      expect: () => [
        const HomeState(status: HomeStatus.loading),
        const HomeState(
          status: HomeStatus.loading,
          categories: [tCatShoes, tCatElectronics],
        ),
        const HomeState(
          status: HomeStatus.success,
          categories: [tCatShoes, tCatElectronics],
          products: [tShoe, tHoodie],
          hasMore: false,
        ),
        const HomeState(
          status: HomeStatus.loading,
          categories: [tCatShoes, tCatElectronics],
          selectedCategoryId: 4,
        ),
        const HomeState(
          status: HomeStatus.success,
          categories: [tCatShoes, tCatElectronics],
          selectedCategoryId: 4,
          products: [tShoe],
          hasMore: false,
        ),
        // Selection updates immediately to All while reloading.
        const HomeState(
          status: HomeStatus.loading,
          categories: [tCatShoes, tCatElectronics],
        ),
        const HomeState(
          status: HomeStatus.success,
          categories: [tCatShoes, tCatElectronics],
          products: [tShoe, tHoodie],
          hasMore: false,
        ),
      ],
      verify: (cubit) {
        final ids = repo.productCalls.map((c) => c['categoryId']).toList();
        expect(ids, [null, 4, null]);
      },
    );

    blocTest<HomeCubit, HomeState>(
      'duplicate taps on the active category do not refetch',
      build: () => HomeCubit(repo),
      act: (cubit) async {
        await cubit.loadHome();
        final before = repo.productCalls.length;
        await cubit.selectCategory(null);
        expect(repo.productCalls.length, before);
      },
      expect: () => [
        const HomeState(status: HomeStatus.loading),
        const HomeState(
          status: HomeStatus.loading,
          categories: [tCatShoes, tCatElectronics],
        ),
        const HomeState(
          status: HomeStatus.success,
          categories: [tCatShoes, tCatElectronics],
          products: [tShoe, tHoodie],
          hasMore: false,
        ),
      ],
    );

    blocTest<HomeCubit, HomeState>(
      'empty category emits the empty state',
      build: () => HomeCubit(repo),
      setUp: () {
        repo.productsHandler =
            ({
              int limit = 10,
              int offset = 0,
              int? categoryId,
              String? title,
            }) async {
              if (categoryId == null) return [tShoe];
              return [];
            };
      },
      act: (cubit) async {
        await cubit.loadHome();
        await cubit.selectCategory(2);
      },
      expect: () => [
        const HomeState(status: HomeStatus.loading),
        const HomeState(
          status: HomeStatus.loading,
          categories: [tCatShoes, tCatElectronics],
        ),
        const HomeState(
          status: HomeStatus.success,
          categories: [tCatShoes, tCatElectronics],
          products: [tShoe],
          hasMore: false,
        ),
        const HomeState(
          status: HomeStatus.loading,
          categories: [tCatShoes, tCatElectronics],
          selectedCategoryId: 2,
        ),
        const HomeState(
          status: HomeStatus.empty,
          categories: [tCatShoes, tCatElectronics],
          selectedCategoryId: 2,
          hasMore: false,
        ),
      ],
    );

    test('rapid category switching drops the stale response', () async {
      final slow = Completer<List<ProductModel>>();
      repo.productsHandler =
          ({int limit = 10, int offset = 0, int? categoryId, String? title}) {
            if (categoryId == 4) return slow.future;
            return Future.value([tPhone]);
          };
      final cubit = HomeCubit(repo);
      await cubit.loadHome();

      final pending = cubit.selectCategory(4);
      await cubit.selectCategory(2);
      // The slow Category A response arrives late.
      slow.complete([tShoe]);
      await pending;
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.selectedCategoryId, 2);
      expect(cubit.state.products, [tPhone]);
      expect(cubit.state.status, HomeStatus.success);
      await cubit.close();
    });

    blocTest<HomeCubit, HomeState>(
      'search is debounced and queries the backend',
      build: () => HomeCubit(repo),
      act: (cubit) async {
        await cubit.loadHome();
        cubit.onSearchChanged('h');
        cubit.onSearchChanged('hoodie');
      },
      wait: const Duration(milliseconds: 600),
      expect: () => [
        const HomeState(status: HomeStatus.loading),
        const HomeState(
          status: HomeStatus.loading,
          categories: [tCatShoes, tCatElectronics],
        ),
        const HomeState(
          status: HomeStatus.success,
          categories: [tCatShoes, tCatElectronics],
          products: [tShoe, tHoodie],
          hasMore: false,
        ),
        const HomeState(
          status: HomeStatus.loading,
          categories: [tCatShoes, tCatElectronics],
          searchQuery: 'hoodie',
        ),
        const HomeState(
          status: HomeStatus.success,
          categories: [tCatShoes, tCatElectronics],
          products: [tHoodie],
          searchQuery: 'hoodie',
          hasMore: false,
        ),
      ],
      verify: (cubit) {
        final titles = repo.productCalls.map((c) => c['title']).toList();
        // Initial load (null) + a single debounced search.
        expect(titles, [null, 'hoodie']);
      },
    );

    blocTest<HomeCubit, HomeState>(
      'category switch with pending search cancels the debounced query',
      build: () => HomeCubit(repo),
      act: (cubit) async {
        await cubit.loadHome();
        cubit.onSearchChanged('hoodie');
        await cubit.selectCategory(4);
      },
      wait: const Duration(milliseconds: 600),
      expect: () => [
        const HomeState(status: HomeStatus.loading),
        const HomeState(
          status: HomeStatus.loading,
          categories: [tCatShoes, tCatElectronics],
        ),
        const HomeState(
          status: HomeStatus.success,
          categories: [tCatShoes, tCatElectronics],
          products: [tShoe, tHoodie],
          hasMore: false,
        ),
        const HomeState(
          status: HomeStatus.loading,
          categories: [tCatShoes, tCatElectronics],
          selectedCategoryId: 4,
        ),
        const HomeState(
          status: HomeStatus.success,
          categories: [tCatShoes, tCatElectronics],
          selectedCategoryId: 4,
          products: [tShoe],
          hasMore: false,
        ),
      ],
      verify: (cubit) {
        // Query cleared and the cancelled debounce never fetched.
        expect(cubit.state.searchQuery, isEmpty);
        final titles = repo.productCalls.map((c) => c['title']).toList();
        expect(titles, [null, null]);
      },
    );

    blocTest<HomeCubit, HomeState>(
      'categories failure keeps products visible with an explicit error',
      setUp: () {
        repo.categoriesHandler = () async {
          throw const CatalogException('No cats.');
        };
      },
      build: () => HomeCubit(repo),
      act: (cubit) => cubit.loadHome(),
      expect: () => [
        const HomeState(status: HomeStatus.loading),
        const HomeState(
          status: HomeStatus.loading,
          categoriesErrorMessage: 'No cats.',
        ),
        const HomeState(
          status: HomeStatus.success,
          products: [tShoe, tHoodie],
          hasMore: false,
          categoriesErrorMessage: 'No cats.',
        ),
      ],
    );

    blocTest<HomeCubit, HomeState>(
      'retryCategories reloads only the categories',
      setUp: () {
        repo.categoriesHandler = () async {
          throw const CatalogException('No cats.');
        };
      },
      build: () => HomeCubit(repo),
      act: (cubit) async {
        await cubit.loadHome();
        repo.categoriesHandler = () async => [tCatShoes];
        await cubit.retryCategories();
      },
      expect: () => [
        const HomeState(status: HomeStatus.loading),
        const HomeState(
          status: HomeStatus.loading,
          categoriesErrorMessage: 'No cats.',
        ),
        const HomeState(
          status: HomeStatus.success,
          products: [tShoe, tHoodie],
          hasMore: false,
          categoriesErrorMessage: 'No cats.',
        ),
        const HomeState(
          status: HomeStatus.success,
          categories: [tCatShoes],
          products: [tShoe, tHoodie],
          hasMore: false,
        ),
      ],
      verify: (cubit) {
        // Products fetched exactly once (initial load); the retry touched
        // categories only and preserved the selection.
        expect(repo.productCalls, hasLength(1));
        expect(cubit.state.selectedCategoryId, isNull);
        expect(cubit.state.hasCategoriesError, isFalse);
      },
    );

    test('repeated categories retry keeps the error gracefully', () async {
      repo.categoriesHandler = () async {
        throw const CatalogException('No cats.');
      };
      final cubit = HomeCubit(repo);
      await cubit.loadHome();
      expect(cubit.state.categoriesErrorMessage, 'No cats.');
      expect(cubit.state.products, [tShoe, tHoodie]);

      await cubit.retryCategories();
      await cubit.retryCategories();
      expect(cubit.state.categoriesErrorMessage, 'No cats.');
      expect(cubit.state.products, [tShoe, tHoodie]);
      await cubit.close();
    });

    blocTest<HomeCubit, HomeState>(
      'pagination appends pages and stops at a short page',
      setUp: () {
        final page1 = List.generate(
          10,
          (i) => ProductModel(
            id: i,
            title: 'Product $i',
            price: 10 + i.toDouble(),
            description: 'd',
            images: const [],
          ),
        );
        const last = ProductModel(
          id: 99,
          title: 'Last one',
          price: 1,
          description: 'd',
          images: [],
        );
        repo.categoriesHandler = () async => [];
        repo.productsHandler =
            ({
              int limit = 10,
              int offset = 0,
              int? categoryId,
              String? title,
            }) async {
              if (offset == 0) return page1;
              return [last];
            };
      },
      build: () => HomeCubit(repo),
      act: (cubit) async {
        await cubit.loadHome();
        await cubit.loadMore();
        // No more pages: ignored.
        await cubit.loadMore();
      },
      expect: () => [
        const HomeState(status: HomeStatus.loading),
        HomeState(
          status: HomeStatus.success,
          products: List.generate(
            10,
            (i) => ProductModel(
              id: i,
              title: 'Product $i',
              price: 10 + i.toDouble(),
              description: 'd',
              images: const [],
            ),
          ),
          hasMore: true,
        ),
        HomeState(
          status: HomeStatus.success,
          products: List.generate(
            10,
            (i) => ProductModel(
              id: i,
              title: 'Product $i',
              price: 10 + i.toDouble(),
              description: 'd',
              images: const [],
            ),
          ),
          isLoadingMore: true,
          hasMore: true,
        ),
        HomeState(
          status: HomeStatus.success,
          products: [
            ...List.generate(
              10,
              (i) => ProductModel(
                id: i,
                title: 'Product $i',
                price: 10 + i.toDouble(),
                description: 'd',
                images: const [],
              ),
            ),
            const ProductModel(
              id: 99,
              title: 'Last one',
              price: 1,
              description: 'd',
              images: [],
            ),
          ],
          hasMore: false,
        ),
      ],
      verify: (cubit) {
        expect(repo.productCalls.map((c) => c['offset']).toList(), [0, 10]);
      },
    );

    test('simultaneous loadMore calls fetch only once', () async {
      final gate = Completer<List<ProductModel>>();
      var calls = 0;
      repo.productsHandler =
          ({int limit = 10, int offset = 0, int? categoryId, String? title}) {
            calls++;
            if (offset == 0) {
              return Future.value(
                List.generate(
                  10,
                  (i) => ProductModel(
                    id: i,
                    title: 'P$i',
                    price: 1,
                    description: 'd',
                    images: const [],
                  ),
                ),
              );
            }
            return gate.future;
          };
      final cubit = HomeCubit(repo);
      await cubit.loadHome();
      calls = 0;

      final first = cubit.loadMore();
      final second = cubit.loadMore();
      gate.complete([]);
      await Future.wait([first, second]);

      expect(calls, 1);
      await cubit.close();
    });

    test('failed loadMore keeps products and allows explicit retry', () async {
      var page2Calls = 0;
      repo.productsHandler =
          ({
            int limit = 10,
            int offset = 0,
            int? categoryId,
            String? title,
          }) async {
            if (offset == 0) {
              return List.generate(
                10,
                (i) => ProductModel(
                  id: i,
                  title: 'P$i',
                  price: 1,
                  description: 'd',
                  images: const [],
                ),
              );
            }
            page2Calls++;
            if (page2Calls == 1) throw const CatalogException('Down.');
            return [];
          };
      final cubit = HomeCubit(repo);
      await cubit.loadHome();
      await cubit.loadMore();

      expect(cubit.state.products, hasLength(10));
      expect(cubit.state.loadMoreError, isTrue);
      expect(cubit.state.isLoadingMore, isFalse);

      // Scroll-driven loadMore must NOT auto-retry the failed page.
      await cubit.loadMore();
      expect(page2Calls, 1);
      expect(cubit.state.loadMoreError, isTrue);
      expect(cubit.state.products, hasLength(10));

      // Only the explicit retry refetches the same page.
      await cubit.retryLoadMore();
      expect(page2Calls, 2);
      expect(cubit.state.loadMoreError, isFalse);
      expect(cubit.state.hasMore, isFalse);
      await cubit.close();
    });

    test('retryLoadMore is a no-op without a prior failure', () async {
      final cubit = HomeCubit(repo);
      await cubit.loadHome();
      final calls = repo.productCalls.length;
      await cubit.retryLoadMore();
      expect(repo.productCalls.length, calls);
      await cubit.close();
    });

    test('retryLoadMore preserves offset and filters', () async {
      List<ProductModel> pageOf(int start) => List.generate(
        10,
        (i) => ProductModel(
          id: start + i,
          title: 'P${start + i}',
          price: 1,
          description: 'd',
          images: const [],
        ),
      );
      repo.productsHandler =
          ({
            int limit = 10,
            int offset = 0,
            int? categoryId,
            String? title,
          }) async {
            if (categoryId == 4) {
              if (offset == 0) return pageOf(100);
              throw const CatalogException('Down.');
            }
            return pageOf(0);
          };
      final cubit = HomeCubit(repo);
      await cubit.loadHome();
      await cubit.selectCategory(4);
      expect(cubit.state.hasMore, isTrue);
      await cubit.loadMore();
      expect(cubit.state.loadMoreError, isTrue);
      expect(cubit.state.products, hasLength(10));

      await cubit.retryLoadMore();
      final last = repo.productCalls.last;
      // Same failed page: offset 10 within category 4.
      expect(last['offset'], 10);
      expect(last['categoryId'], 4);
      await cubit.close();
    });
  });

  // -------------------------------------------------------------------------
  // Widgets
  // -------------------------------------------------------------------------
  group('HomeScreen widgets', () {
    late FakeHomeRepository repo;

    setUp(() {
      repo = FakeHomeRepository();
      repo.categoriesHandler = () async => [tCatShoes, tCatElectronics];
      repo.productsHandler =
          ({
            int limit = 10,
            int offset = 0,
            int? categoryId,
            String? title,
          }) async {
            if (categoryId == 4) return [tShoe];
            if (categoryId == 2) return [tPhone];
            if (title == 'hoodie') return [tHoodie];
            if (title != null) return [];
            return [tShoe, tHoodie];
          };
    });

    Widget buildHome(HomeCubit cubit) {
      return MaterialApp(
        home: BlocProvider.value(value: cubit, child: const HomeScreen()),
      );
    }

    _testHomeWidgets('shows loading then real products and categories', (
      tester,
    ) async {
      final gate = Completer<List<ProductModel>>();
      repo.productsHandler = ({
        int limit = 10,
        int offset = 0,
        int? categoryId,
        String? title,
      }) => gate.future;
      final cubit = HomeCubit(repo);
      await tester.pumpWidget(buildHome(cubit));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsWidgets);

      gate.complete([tShoe, tHoodie]);
      await _pumpFrames(tester);

      expect(find.text('Futuristic Holographic Soccer Cleats'), findsOneWidget);
      expect(find.text('\$39.00'), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Shoes'), findsOneWidget);
      expect(find.text('Electronics'), findsOneWidget);
      await cubit.close();
    });

    _testHomeWidgets('tapping a category filters the grid', (tester) async {
      final cubit = HomeCubit(repo);
      await tester.pumpWidget(buildHome(cubit));
      await _pumpFrames(tester);

      expect(find.text('Classic Red Pullover Hoodie'), findsOneWidget);

      await tester.tap(find.text('Shoes'));
      await _pumpFrames(tester);

      expect(find.text('Futuristic Holographic Soccer Cleats'), findsOneWidget);
      expect(find.text('Classic Red Pullover Hoodie'), findsNothing);
      // Selection highlight moved to Shoes.
      final chip = tester.widget<CategoryChip>(
        find.ancestor(
          of: find.text('Shoes'),
          matching: find.byType(CategoryChip),
        ),
      );
      expect(chip.isSelected, isTrue);
      await cubit.close();
    });

    _testHomeWidgets('error state with retry recovers', (tester) async {
      var calls = 0;
      repo.productsHandler =
          ({
            int limit = 10,
            int offset = 0,
            int? categoryId,
            String? title,
          }) async {
            calls++;
            if (calls == 1) throw const CatalogException('No internet.');
            return [tShoe];
          };
      final cubit = HomeCubit(repo);
      await tester.pumpWidget(buildHome(cubit));
      await _pumpFrames(tester);

      expect(find.text('No internet.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await _pumpFrames(tester);

      expect(find.text('Futuristic Holographic Soccer Cleats'), findsOneWidget);
      await cubit.close();
    });

    _testHomeWidgets('empty category shows a friendly empty state', (
      tester,
    ) async {
      repo.productsHandler =
          ({
            int limit = 10,
            int offset = 0,
            int? categoryId,
            String? title,
          }) async {
            if (categoryId == null) return [tShoe];
            return [];
          };
      final cubit = HomeCubit(repo);
      await tester.pumpWidget(buildHome(cubit));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Electronics'));
      await tester.pumpAndSettle();

      expect(find.text('No products in Electronics yet.'), findsOneWidget);
      await cubit.close();
    });

    _testHomeWidgets('search filters and clearing restores the category', (
      tester,
    ) async {
      final cubit = HomeCubit(repo);
      await tester.pumpWidget(buildHome(cubit));
      await _pumpFrames(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Search clothes...'),
        'hoodie',
      );
      await tester.pump(const Duration(milliseconds: 500));
      await _pumpFrames(tester);

      expect(find.text('Classic Red Pullover Hoodie'), findsOneWidget);
      expect(find.text('Futuristic Holographic Soccer Cleats'), findsNothing);

      await tester.enterText(
        find.widgetWithText(TextField, 'Search clothes...'),
        '',
      );
      await tester.pump(const Duration(milliseconds: 500));
      await _pumpFrames(tester);

      expect(find.text('Futuristic Holographic Soccer Cleats'), findsOneWidget);
      await cubit.close();
    });

    _testHomeWidgets('switching category clears the visible search text', (
      tester,
    ) async {
      final cubit = HomeCubit(repo);
      await tester.pumpWidget(buildHome(cubit));
      await _pumpFrames(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Search clothes...'),
        'hoodie',
      );
      // Switch before the 400ms debounce fires.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Shoes'));
      await _pumpFrames(tester);

      // Field cleared, results match the selected category (not the query).
      final field = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Search clothes...'),
      );
      expect(field.controller!.text, isEmpty);
      expect(find.text('Futuristic Holographic Soccer Cleats'), findsOneWidget);

      // Past the original debounce window: the cancelled query must never
      // have fetched.
      await _pumpFrames(tester);
      expect(repo.productCalls.where((c) => c['title'] == 'hoodie'), isEmpty);
      await cubit.close();
    });

    _testHomeWidgets(
      'categories failure shows a retry banner without losing products',
      (tester) async {
        repo.categoriesHandler = () async {
          throw const CatalogException('No cats.');
        };
        final cubit = HomeCubit(repo);
        await tester.pumpWidget(buildHome(cubit));
        await _pumpFrames(tester);

        // Products visible, categories-only retry offered.
        expect(
          find.text('Futuristic Holographic Soccer Cleats'),
          findsOneWidget,
        );
        expect(find.text('All'), findsOneWidget);
        expect(find.text('Shoes'), findsNothing);
        expect(find.text('Retry'), findsOneWidget);

        repo.categoriesHandler = () async => [tCatShoes];
        await tester.tap(find.text('Retry'));
        await _pumpFrames(tester);

        // Categories appear; existing products untouched.
        expect(find.text('Shoes'), findsOneWidget);
        expect(
          find.text('Futuristic Holographic Soccer Cleats'),
          findsOneWidget,
        );
        expect(find.text('Retry'), findsNothing);
        await cubit.close();
      },
    );

    _testHomeWidgets('failed pagination does not auto-retry on scroll', (
      tester,
    ) async {
      var page2Calls = 0;
      ProductModel pageItem(int id) => ProductModel(
        id: id,
        title: 'P$id',
        price: 1,
        description: 'd',
        images: const [],
      );
      repo.productsHandler =
          ({
            int limit = 10,
            int offset = 0,
            int? categoryId,
            String? title,
          }) async {
            if (offset == 0) return List.generate(10, (i) => pageItem(i));
            page2Calls++;
            if (page2Calls == 1) throw const CatalogException('Down.');
            return [pageItem(99)];
          };
      final cubit = HomeCubit(repo);
      await tester.pumpWidget(buildHome(cubit));
      await _pumpFrames(tester);

      // Scroll to the bottom: first page-2 attempt fails.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -3000));
      await _pumpFrames(tester);
      expect(find.text('Couldn\'t load more. Tap to retry.'), findsOneWidget);
      expect(page2Calls, 1);

      // Scrolling again must NOT refetch the failed page automatically.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
      await _pumpFrames(tester);
      expect(page2Calls, 1);

      // Only the explicit retry refetches and appends.
      await tester.tap(find.text('Couldn\'t load more. Tap to retry.'));
      await _pumpFrames(tester);
      expect(page2Calls, 2);
      expect(find.text('P99'), findsOneWidget);
      expect(find.text('Couldn\'t load more. Tap to retry.'), findsNothing);
      await cubit.close();
    });

    _testHomeWidgets('tapping a product opens its details', (tester) async {
      final cubit = HomeCubit(repo);
      await tester.pumpWidget(buildHome(cubit));
      await _pumpFrames(tester);

      await tester.ensureVisible(
        find.text('Futuristic Holographic Soccer Cleats'),
      );
      await tester.pump();
      await tester.tap(find.text('Futuristic Holographic Soccer Cleats'));
      await _pumpFrames(tester);

      expect(find.text('Shiny cleats.'), findsOneWidget);
      expect(find.text('\$39.00'), findsWidgets);
      // API products carry no variants: selectors are hidden, no crash.
      expect(find.text('Select Color'), findsNothing);
      expect(find.text('Select Size'), findsNothing);

      await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
      await _pumpFrames(tester);
      expect(find.text('Explore'), findsOneWidget);
      await cubit.close();
    });

    _testHomeWidgets('long titles do not overflow small screens', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const longTitle =
          'An extremely long product title that spans multiple lines on '
          'narrow phone screens and must be ellipsized gracefully';
      repo.productsHandler =
          ({
            int limit = 10,
            int offset = 0,
            int? categoryId,
            String? title,
          }) async {
            return List.generate(
              6,
              (i) => ProductModel(
                id: i,
                title: '$longTitle $i',
                price: 1234567.89,
                description: 'd',
                images: const [],
              ),
            );
          };
      final cubit = HomeCubit(repo);
      await tester.pumpWidget(buildHome(cubit));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await cubit.close();
    });

    _testHomeWidgets('rebuild keeps selection without refetching', (
      tester,
    ) async {
      final cubit = HomeCubit(repo);
      await tester.pumpWidget(buildHome(cubit));
      await _pumpFrames(tester);
      await tester.tap(find.text('Shoes'));
      await _pumpFrames(tester);
      final calls = repo.productCalls.length;

      // Simulates a bottom-navigation tab switch.
      await tester.pumpWidget(buildHome(cubit));
      await _pumpFrames(tester);

      expect(repo.productCalls.length, calls);
      expect(find.text('Futuristic Holographic Soccer Cleats'), findsOneWidget);
      final chip = tester.widget<CategoryChip>(
        find.ancestor(
          of: find.text('Shoes'),
          matching: find.byType(CategoryChip),
        ),
      );
      expect(chip.isSelected, isTrue);
      await cubit.close();
    });
  });
}
