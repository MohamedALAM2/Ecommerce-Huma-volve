import 'package:flutter/material.dart';

import '../../../core/di/app_scope.dart';
import '../../../core/error/app_failure.dart';
import '../../../core/theme.dart';
import '../../home/domain/entities/product_entity.dart';
import '../../home/widgets/product_card.dart' show ProductEntityCompat;
import 'product_details_screen.dart';

/// ID-based entry to Product Details, used by external deep links.
///
/// Receives only a validated product ID, fetches the real product through
/// the existing `GetProductDetailsUseCase` (Presentation → Domain ← Data),
/// and on success reuses the existing [ProductDetailsScreen] UI — no
/// duplicated page implementation, no catalog re-fetch, no dummy products.
///
/// Each instance is pinned to its own [productId], so rapid consecutive
/// links (10 then 20) render in separate routes: the top route always shows
/// the latest request and a slow first response can never overwrite it.
class ProductDetailsLoaderScreen extends StatefulWidget {
  final int productId;

  const ProductDetailsLoaderScreen({super.key, required this.productId});

  @override
  State<ProductDetailsLoaderScreen> createState() =>
      _ProductDetailsLoaderScreenState();
}

class _ProductDetailsLoaderScreenState
    extends State<ProductDetailsLoaderScreen> {
  bool _isLoading = true;
  ProductEntity? _product;
  String? _errorMessage;

  /// Guards against stale completions within this route (retry supersedes
  /// the in-flight request).
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final attempt = ++_attempt;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final useCase = AppScope.read(context).createGetProductDetailsUseCase();
      final product = await useCase(widget.productId);
      if (!mounted || attempt != _attempt) return;
      setState(() {
        _isLoading = false;
        _product = product;
      });
    } on AppFailure catch (e) {
      if (!mounted || attempt != _attempt) return;
      setState(() {
        _isLoading = false;
        _errorMessage = _displayMessage(e);
      });
    } catch (_) {
      if (!mounted || attempt != _attempt) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not load product details.';
      });
    }
  }

  /// The public API may answer unknown IDs with HTTP 400 (mapped to
  /// [ValidationFailure]) instead of 404 — both mean "not found" here.
  String _displayMessage(AppFailure failure) {
    if (failure is NotFoundFailure || failure is ValidationFailure) {
      return 'Product not found or no longer available.';
    }
    return failure.message;
  }

  @override
  Widget build(BuildContext context) {
    final product = _product;
    // Success reuses the existing details UI verbatim (same styling, Hero,
    // back/favorite/cart behavior, placeholder images).
    if (!_isLoading && product != null) {
      return ProductDetailsScreen(product: product.toProduct());
    }
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back_ios_new, size: 16),
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: _isLoading
              ? const CircularProgressIndicator(color: AppTheme.primary)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 64,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage ?? 'Could not load product details.',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _load,
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
      ),
    );
  }
}
