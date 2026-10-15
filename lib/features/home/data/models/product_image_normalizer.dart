/// Normalizes raw `images` payloads from the Platzi Fake Store API.
///
/// The backend sometimes returns malformed image values, for example:
///   - `"https://example.com/product.jpg"`
///   - `'["https://example.com/product.jpg"]'` (JSON-encoded inside a string)
///   - `'["https://example.com/first.jpg","https://example.com/second.jpg"]'`
///   - `'[ "https://example.com/product.png" ]'`
///   - `"invalid-image-url"`, `""`, `[]`, `null`
///
/// Some list entries contain unwanted brackets, quotes, or whitespace wrapping
/// an otherwise valid URL. This utility extracts candidate HTTP/HTTPS URLs,
/// validates them with [Uri.tryParse], and drops anything unusable — without
/// throwing on unexpected shapes and without mutating valid URLs.
///
/// Lives in the Data layer so DTOs map clean values into Domain entities;
/// Domain stays free of JSON/network parsing.
abstract final class ProductImageNormalizer {
  /// Matches an HTTP/HTTPS URL up to (but not including) characters that
  /// are definitely delimiters: whitespace, quotes, angle brackets,
  /// square brackets, backslashes, and backticks.
  ///
  /// Deliberately permissive otherwise so legitimate query strings
  /// (`?text=Product&w=600`), fragments (`#a`), and percent-encoding
  /// (`%20`, `%2F`) survive untouched. Commas and parentheses are kept
  /// because they are legal inside URLs; wrapping quotes/brackets already
  /// terminate the match.
  static final RegExp _candidatePattern = RegExp(
    "https?://[^\\s\"'<>\\\\\\[\\]`]+",
    caseSensitive: false,
  );

  /// Returns true when [url] is a syntactically usable remote image URL:
  /// parseable, `http`/`https` scheme, and a non-empty host.
  ///
  /// This cannot verify the resource exists — [AppNetworkImage] still shows
  /// a placeholder for unreachable hosts.
  static bool isValidImageUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return false;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return false;
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    if (uri.host.isEmpty) return false;
    return true;
  }

  /// Normalizes the raw `images` JSON value into clean URLs.
  ///
  /// Accepts lists, single strings, `null`, and anything unexpected
  /// (never throws). Preserves order, preserves valid URLs verbatim
  /// (including query strings/encoding), and drops duplicates.
  static List<String> normalize(dynamic raw) {
    try {
      final found = <String>[];
      _collect(raw, found);
      // Deduplicate while preserving first-seen order.
      final seen = <String>{};
      final result = <String>[];
      for (final url in found) {
        if (seen.add(url)) result.add(url);
      }
      return result;
    } catch (_) {
      return const [];
    }
  }

  static void _collect(dynamic value, List<String> out) {
    if (value == null) return;
    if (value is List) {
      for (final item in value) {
        // Nested lists are flattened instead of crashing.
        if (item is List) {
          _collect(item, out);
        } else if (item is String) {
          out.addAll(_extractFromString(item));
        } else if (item != null) {
          out.addAll(_extractFromString(item.toString()));
        }
      }
      return;
    }
    if (value is String) {
      out.addAll(_extractFromString(value));
      return;
    }
    // Numbers, bools, maps, ... : only keep embedded URLs, if any.
    try {
      out.addAll(_extractFromString(value.toString()));
    } catch (_) {
      // Ignore unstringifiable values.
    }
  }

  static List<String> _extractFromString(String input) {
    final matches = _candidatePattern.allMatches(input);
    final urls = <String>[];
    for (final match in matches) {
      final cleaned = _cleanCandidate(match.group(0) ?? '');
      if (cleaned.isNotEmpty && isValidImageUrl(cleaned)) {
        urls.add(cleaned);
      }
    }
    return urls;
  }

  /// Trims whitespace and strips trailing sentence punctuation that is
  /// almost never part of an image URL. Leading wrapping is already
  /// excluded by the extractor pattern.
  static String _cleanCandidate(String candidate) {
    var url = candidate.trim();
    // Strip trailing delimiters one at a time: '.', ',', ';', '!', ')'.
    // Query strings and %-encoding never end with these in practice.
    while (url.isNotEmpty &&
        (url.endsWith('.') ||
            url.endsWith(',') ||
            url.endsWith(';') ||
            url.endsWith('!') ||
            url.endsWith(')'))) {
      url = url.substring(0, url.length - 1).trimRight();
    }
    return url;
  }
}
