import 'dart:async';

import 'package:ecommerce_app_huma_volve/core/deep_links/deep_link_coordinator.dart';
import 'package:ecommerce_app_huma_volve/core/deep_links/product_deep_link.dart';
import 'package:ecommerce_app_huma_volve/core/di/app_dependencies.dart';
import 'package:ecommerce_app_huma_volve/core/di/app_scope.dart';
import 'package:ecommerce_app_huma_volve/core/error/app_failure.dart';
import 'package:ecommerce_app_huma_volve/features/details/screens/product_details_loader_screen.dart';
import 'package:ecommerce_app_huma_volve/features/home/domain/entities/category_entity.dart';
import 'package:ecommerce_app_huma_volve/features/home/domain/entities/product_entity.dart';
import 'package:ecommerce_app_huma_volve/features/home/domain/repositories/home_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

const _category = CategoryEntity(id: 2, name: 'Electronics', image: 'e.jpg');

ProductEntity product(int id) => ProductEntity(
  id: id,
  title: 'Product $id',
  price: id.toDouble(),
  description: 'Description $id.',
  images: const [],
  category: _category,
);

class FakeHomeRepository implements HomeRepository {
  Future<ProductEntity> Function(int id)? detailsHandler;
  final List<int> requestedIds = [];

  @override
  Future<List<CategoryEntity>> getCategories() async => [];

  @override
  Future<List<ProductEntity>> getProducts({
    int? limit,
    int? offset,
    int? categoryId,
    String? title,
  }) async => [];

  @override
  Future<ProductEntity> getProductById(int id) {
    requestedIds.add(id);
    final handler = detailsHandler;
    if (handler != null) return handler(id);
    return Future.value(product(id));
  }
}

class FakeDeps extends AppDependencies {
  FakeDeps(this.fakeHome);
  final FakeHomeRepository fakeHome;

  @override
  HomeRepository get homeRepository => fakeHome;
}

/// Pumps a loader for [id] inside the DI scope used in production.
Future<void> pumpLoader(
  WidgetTester tester,
  FakeHomeRepository repo,
  int id,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: AppScope(
        dependencies: FakeDeps(repo),
        child: ProductDetailsLoaderScreen(productId: id),
      ),
    ),
  );
}

/// Push counting observer for navigation assertions.
class CountingObserver extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route route, Route? previousRoute) {
    pushes++;
    super.didPush(route, previousRoute);
  }
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

void main() {
  group('ProductDeepLink parser', () {
    test('accepts valid product links', () {
      expect(ProductDeepLink.parseProductId('humavolve://product/1'), 1);
      expect(ProductDeepLink.parseProductId('humavolve://product/25'), 25);
      expect(ProductDeepLink.parseProductId('humavolve://product/100'), 100);
    });

    test('rejects missing, invalid, negative, and zero IDs', () {
      expect(ProductDeepLink.parseProductId('humavolve://product/'), isNull);
      expect(ProductDeepLink.parseProductId('humavolve://product'), isNull);
      expect(ProductDeepLink.parseProductId('humavolve://product/abc'), isNull);
      expect(ProductDeepLink.parseProductId('humavolve://product/-5'), isNull);
      expect(ProductDeepLink.parseProductId('humavolve://product/0'), isNull);
      expect(ProductDeepLink.parseProductId('humavolve://product/'), isNull);
    });

    test('rejects wrong scheme and host', () {
      expect(ProductDeepLink.parseProductId('https://product/25'), isNull);
      expect(ProductDeepLink.parseProductId('other://product/25'), isNull);
      expect(ProductDeepLink.parseProductId('humavolve://unknown/25'), isNull);
      expect(ProductDeepLink.parseProductId('humavolve://products/25'), isNull);
    });

    test('rejects extra path segments', () {
      expect(
        ProductDeepLink.parseProductId('humavolve://product/25/extra'),
        isNull,
      );
      expect(ProductDeepLink.parseProductId('humavolve://product/25?x=1'), 25);
    });

    test('handles malformed and unsupported links without throwing', () {
      expect(ProductDeepLink.parseProductId(null), isNull);
      expect(ProductDeepLink.parseProductId(''), isNull);
      expect(ProductDeepLink.parseProductId('   '), isNull);
      expect(ProductDeepLink.parseProductId('not a uri at all'), isNull);
      expect(ProductDeepLink.parseProductId('humavolve://'), isNull);
      expect(ProductDeepLink.parseProductId('tel:+123456'), isNull);
    });

    test('builds canonical links that re-parse', () {
      final raw = ProductDeepLink.build(25);
      expect(raw, 'humavolve://product/25');
      expect(ProductDeepLink.parseProductId(raw), 25);
    });
  });

  // -------------------------------------------------------------------------
  // Loader
  // -------------------------------------------------------------------------
  group('ProductDetailsLoaderScreen', () {
    testWidgets('shows loading then the real product', (tester) async {
      final repo = FakeHomeRepository();
      await pumpLoader(tester, repo, 25);
      // Loading indicator first (no blank screen).
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();

      expect(repo.requestedIds, [25]);
      expect(find.text('Product 25'), findsOneWidget);
      expect(find.text('Description 25.'), findsOneWidget);
      expect(find.text('\$25.00'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('product-not-found maps 400/404 to a friendly message', (
      tester,
    ) async {
      final repo = FakeHomeRepository()
        ..detailsHandler = (_) async {
          throw const NotFoundFailure('Product not found.', statusCode: 404);
        };
      await pumpLoader(tester, repo, 9999);
      await tester.pumpAndSettle();

      expect(
        find.text('Product not found or no longer available.'),
        findsOneWidget,
      );

      // The public API may answer unknown IDs with HTTP 400 instead of 404.
      repo.detailsHandler = (_) async {
        throw const ValidationFailure('Bad.', statusCode: 400);
      };
      await pumpLoader(tester, repo, 9999);
      await tester.pumpAndSettle();
      expect(
        find.text('Product not found or no longer available.'),
        findsOneWidget,
      );
    });

    testWidgets('network failure shows message with working retry', (
      tester,
    ) async {
      var calls = 0;
      final repo = FakeHomeRepository()
        ..detailsHandler = (_) async {
          calls++;
          if (calls == 1) throw const NetworkFailure('No internet.');
          return product(25);
        };
      await pumpLoader(tester, repo, 25);
      await tester.pumpAndSettle();

      expect(find.text('No internet.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(calls, 2);
      expect(find.text('Product 25'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('malformed product response is handled without crashing', (
      tester,
    ) async {
      final repo = FakeHomeRepository()
        ..detailsHandler = (_) async {
          throw const UnexpectedFailure('Could not load product details.');
        };
      await pumpLoader(tester, repo, 7);
      await tester.pumpAndSettle();

      expect(find.text('Could not load product details.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('broken image falls back to a placeholder', (tester) async {
      final repo = FakeHomeRepository();
      await pumpLoader(tester, repo, 3);
      await tester.pumpAndSettle();

      expect(find.text('Product 3'), findsOneWidget);
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // Coordinator / navigation
  // -------------------------------------------------------------------------
  group('DeepLinkCoordinator navigation', () {
    late GlobalKey<NavigatorState> navKey;
    late CountingObserver observer;
    late bool authenticated;
    late DeepLinkCoordinator coordinator;

    setUp(() {
      navKey = GlobalKey<NavigatorState>();
      observer = CountingObserver();
      authenticated = true;
      coordinator = DeepLinkCoordinator(isAuthenticated: () => authenticated);
      coordinator.attachNavigatorKey(navKey);
    });

    tearDown(() async {
      await coordinator.dispose();
    });

    Future<void> pumpApp(WidgetTester tester) async {
      // AppScope sits above MaterialApp (as in production main.dart) so
      // pushed deep-link routes resolve dependencies too.
      await tester.pumpWidget(
        AppScope(
          dependencies: FakeDeps(FakeHomeRepository()),
          child: MaterialApp(
            navigatorKey: navKey,
            navigatorObservers: [observer],
            home: const Scaffold(body: Text('Home')),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('warm start opens the linked product', (tester) async {
      await pumpApp(tester);
      coordinator.markSplashResolved();

      coordinator.handleRawLink('humavolve://product/25');
      await tester.pumpAndSettle();

      expect(coordinator.pendingProductId, isNull);
      expect(find.text('Product 25'), findsOneWidget);
    });

    testWidgets('cold start defers until Splash resolves', (tester) async {
      await pumpApp(tester);
      // Link arrives before Splash is done: stored, not navigated.
      coordinator.handleRawLink('humavolve://product/25');
      await tester.pump();
      expect(coordinator.pendingProductId, 25);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Product 25'), findsNothing);

      // Splash finishes → pending opens on top of Main.
      coordinator.markSplashResolved();
      coordinator.openPendingIfAny();
      await tester.pumpAndSettle();
      expect(find.text('Product 25'), findsOneWidget);
    });

    testWidgets('logged-out link waits for post-login consumption', (
      tester,
    ) async {
      await pumpApp(tester);
      coordinator.markSplashResolved();
      authenticated = false;

      coordinator.handleRawLink('humavolve://product/25');
      await tester.pump();
      // No protected screen opens while logged out.
      expect(find.text('Product 25'), findsNothing);
      expect(coordinator.pendingProductId, 25);

      // After a successful login the pending link is honored and cleared.
      authenticated = true;
      coordinator.openPendingIfAny();
      await tester.pumpAndSettle();
      expect(find.text('Product 25'), findsOneWidget);
      expect(coordinator.pendingProductId, isNull);
    });

    testWidgets('pending survives failed open attempts (retry after offline)', (
      tester,
    ) async {
      await pumpApp(tester);
      coordinator.markSplashResolved();
      authenticated = false;

      coordinator.handleRawLink('humavolve://product/10');
      await tester.pump();
      // Failed attempt (logged out) keeps the request, like Splash Retry.
      expect(coordinator.openPendingIfAny(), isNull);
      expect(coordinator.pendingProductId, 10);

      authenticated = true;
      expect(coordinator.openPendingIfAny(), 10);
      await tester.pumpAndSettle();
      expect(find.text('Product 10'), findsOneWidget);
    });

    testWidgets('duplicate delivery of the same event opens once', (
      tester,
    ) async {
      await pumpApp(tester);
      coordinator.markSplashResolved();
      final pushesBefore = observer.pushes;

      coordinator.handleRawLink('humavolve://product/25');
      coordinator.handleRawLink('humavolve://product/25');
      await tester.pumpAndSettle();

      expect(observer.pushes - pushesBefore, 1);
      expect(find.text('Product 25'), findsOneWidget);
    });

    testWidgets('rapid consecutive links show the latest on top', (
      tester,
    ) async {
      await pumpApp(tester);
      coordinator.markSplashResolved();
      final pushesBefore = observer.pushes;

      coordinator.handleRawLink('humavolve://product/10');
      await tester.pump(); // Route pushed, fetch in flight.
      coordinator.handleRawLink('humavolve://product/20');
      await tester.pumpAndSettle();

      // Two detail routes; the latest request is displayed on top.
      expect(observer.pushes - pushesBefore, 2);
      expect(find.text('Product 20'), findsOneWidget);

      // Back navigation returns to the previous product, then Home.
      navKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('Product 10'), findsOneWidget);
      navKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('invalid links never navigate', (tester) async {
      await pumpApp(tester);
      coordinator.markSplashResolved();
      final pushesBefore = observer.pushes;

      for (final raw in [
        'humavolve://product/',
        'humavolve://product/abc',
        'humavolve://product/-5',
        'humavolve://product/0',
        'humavolve://unknown/25',
        'https://example.com/product/25',
        'garbage',
      ]) {
        coordinator.handleRawLink(raw);
      }
      await tester.pump();

      expect(observer.pushes, pushesBefore);
      expect(coordinator.hasPending, isFalse);
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('stream source delivers links while running', (tester) async {
      await pumpApp(tester);
      coordinator.markSplashResolved();
      final links = StreamController<Uri>();
      addTearDown(links.close);
      coordinator.listenTo(links.stream);

      links.add(Uri.parse('humavolve://product/42'));
      await tester.pumpAndSettle();

      expect(find.text('Product 42'), findsOneWidget);
    });

    test('logout clears pending so no protected screen can reopen', () {
      coordinator.handleRawLink('humavolve://product/25');
      expect(coordinator.hasPending, isTrue);
      coordinator.clearForLogout();
      expect(coordinator.hasPending, isFalse);
    });
  });
}
