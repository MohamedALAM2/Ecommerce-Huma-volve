/// User-facing catalog error with a displayable message.
class CatalogException implements Exception {
  final String message;
  final int? statusCode;

  const CatalogException(this.message, {this.statusCode});

  @override
  String toString() => 'CatalogException($statusCode): $message';
}
