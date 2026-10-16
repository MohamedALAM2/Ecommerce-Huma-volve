import 'dart:async';

import 'package:flutter/material.dart';

// ignore_for_file: prefer_initializing_formals
// (Constructor takes a public predicate parameter; the field is private.)

import '../../features/details/screens/product_details_loader_screen.dart';
import 'product_deep_link.dart';

/// Single central receiver for external product deep links.
///
/// Owns exactly one platform-link subscription (created in `MyApp`), so
/// listeners are never scattered across screens. Responsibilities:
/// - parse incoming URIs with [ProductDeepLink] (structured `Uri` APIs);
/// - ignore invalid/malformed links without crashing;
/// - deduplicate overlapping deliveries of the same event;
/// - hold a validated pending product ID across Splash/auth;
/// - navigate only when the app is past Splash, authenticated, and the
///   [Navigator] is ready.
///
/// Flow: link → parser → pending ID → [openPendingIfAny] (from warm-start
/// events or `MainNavigationScreen`'s post-frame check) → loader screen →
/// [GetProductDetailsUseCase] → repository → remote → Dio. No Dio here.
class DeepLinkCoordinator {
  /// How long a consecutive identical URI is treated as the same platform
  /// event (cold-start initial-link/stream overlap). A deliberate later
  /// user action for the same product falls outside this window and is
  /// handled normally.
  static const duplicateWindow = Duration(seconds: 3);

  final bool Function() _isAuthenticated;

  GlobalKey<NavigatorState>? _navigatorKey;
  StreamSubscription<Uri>? _subscription;

  int? _pendingProductId;
  String? _lastRawEvent;
  DateTime? _lastEventTime;
  bool _splashResolved = false;

  DeepLinkCoordinator({required bool Function() isAuthenticated})
    : _isAuthenticated = isAuthenticated;

  bool get _authenticated {
    try {
      return _isAuthenticated();
    } catch (_) {
      return false;
    }
  }

  int? get pendingProductId => _pendingProductId;
  bool get hasPending => _pendingProductId != null;

  void attachNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  /// Subscribes to the platform link stream (single source: `uriLinkStream`
  /// already includes the cold-start initial link, so `getInitialLink` is
  /// intentionally NOT consulted — no overlap, no double handling).
  void listenTo(Stream<Uri> linkStream) {
    _subscription?.cancel();
    _subscription = linkStream.listen(_onUri, onError: (_) {});
  }

  /// Structured-URI entry point shared by the stream listener and tests.
  /// Returns the accepted product ID, or `null` when ignored.
  int? handleUri(Uri? uri) {
    if (uri == null) return null;
    final raw = uri.toString();
    final now = DateTime.now();
    final lastRaw = _lastRawEvent;
    final lastTime = _lastEventTime;
    if (lastRaw != null &&
        lastRaw == raw &&
        lastTime != null &&
        now.difference(lastTime) < duplicateWindow) {
      return null;
    }
    _lastRawEvent = raw;
    _lastEventTime = now;
    final id = ProductDeepLink.parseProductIdFromUri(uri);
    if (id == null) return null;
    _pendingProductId = id;
    _tryOpenNow();
    return id;
  }

  /// Raw-string entry point (convenience for callers holding strings).
  int? handleRawLink(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    Uri uri;
    try {
      uri = Uri.parse(raw.trim());
    } catch (_) {
      return null;
    }
    return handleUri(uri);
  }

  void _onUri(Uri uri) => handleUri(uri);

  /// Called by Splash after it has navigated to Main/Login. Only records
  /// readiness — navigation itself happens via [openPendingIfAny] (warm
  /// events) or `MainNavigationScreen`'s post-frame check (cold start), so
  /// a pending details route can never be replaced by Splash's own
  /// `pushReplacement`.
  void markSplashResolved() {
    _splashResolved = true;
  }

  /// Navigates to the pending product when the app is ready: past Splash,
  /// authenticated, and with a mounted [Navigator]. Otherwise the pending
  /// ID is kept for later (post-login / post-retry consumption).
  /// Returns the opened product ID, or `null` when nothing was opened.
  int? openPendingIfAny() {
    if (!_splashResolved) return null;
    if (!_authenticated) return null;
    final nav = _navigatorKey?.currentState;
    if (nav == null) return null;
    final id = _pendingProductId;
    if (id == null) return null;
    _pendingProductId = null;
    _pushDetails(nav, id);
    return id;
  }

  void _tryOpenNow() => openPendingIfAny();

  void _pushDetails(NavigatorState nav, int productId) {
    nav.push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (context, animation, secondaryAnimation) =>
            ProductDetailsLoaderScreen(productId: productId),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  /// Removes the stored request without navigating.
  int? consumePending() {
    final id = _pendingProductId;
    _pendingProductId = null;
    return id;
  }

  /// Clears pending state on logout so no callback can reopen
  /// authenticated screens. Splash readiness is kept (the app stays warm).
  void clearForLogout() {
    _pendingProductId = null;
    _lastRawEvent = null;
    _lastEventTime = null;
  }

  /// Test seam: resets everything, including Splash readiness.
  @visibleForTesting
  void debugReset() {
    _pendingProductId = null;
    _lastRawEvent = null;
    _lastEventTime = null;
    _splashResolved = false;
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _navigatorKey = null;
  }
}
