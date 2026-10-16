/// Deep-link contract for the training assignment:
/// `humavolve://product/{productId}`.
///
/// - Scheme: `humavolve`
/// - Host: `product`
/// - Path: exactly one segment, a positive integer product ID.
///
/// Parsing uses structured [Uri] APIs (never fragile string splitting) and
/// is fully independent of UI rendering and backend requests, so it can be
/// unit-tested in isolation.
abstract final class ProductDeepLink {
  static const String scheme = 'humavolve';
  static const String host = 'product';

  /// Parses [raw] and returns the product ID, or `null` when the link is
  /// missing, malformed, or not a product link. Never throws.
  static int? parseProductId(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    Uri uri;
    try {
      uri = Uri.parse(raw.trim());
    } catch (_) {
      return null;
    }
    return parseProductIdFromUri(uri);
  }

  /// Structured-URI entry point. Returns the product ID or `null`.
  ///
  /// Rejects: wrong scheme/host, missing ID, non-numeric/negative/zero IDs,
  /// extra path segments, and unrelated routes.
  static int? parseProductIdFromUri(Uri? uri) {
    if (uri == null) return null;
    try {
      if (uri.scheme.toLowerCase() != scheme) return null;
      if (uri.host.toLowerCase() != host) return null;
      if (uri.pathSegments.length != 1) return null;
      final id = int.tryParse(uri.pathSegments.first);
      if (id == null || id <= 0) return null;
      return id;
    } catch (_) {
      return null;
    }
  }

  /// Builds a canonical product deep link for a valid [productId].
  static String build(int productId) {
    assert(productId > 0, 'productId must be positive');
    return '$scheme://$host/$productId';
  }
}
