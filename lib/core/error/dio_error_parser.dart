import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

/// Shared Dio introspection helpers, so every remote data source classifies
/// connectivity problems and extracts backend messages identically.
///
/// Pure functions over [DioException]: unit-testable, no Flutter/Dio leakage
/// beyond this module's signature.
bool isTimeoutError(DioException e) {
  return e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.sendTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e is TimeoutException;
}

bool isNetworkError(DioException e) {
  // A failed response cast (e.g. the server returned an object where a
  // list was expected) surfaces as DioExceptionType.unknown with a
  // TypeError: that is a shape problem, not a connectivity problem, and
  // must not be reported as "no internet".
  if (e.error is TypeError) return false;
  return e.type == DioExceptionType.connectionError ||
      e.type == DioExceptionType.unknown ||
      e.error is SocketException;
}

int? dioStatusCode(DioException e) => e.response?.statusCode;

/// Best-effort extraction of a server-provided message, supporting both
/// `{"message": "..."}` and `{"message": [...]}` shapes.
String? dioBackendMessage(DioException e) {
  final data = e.response?.data;
  if (data is Map) {
    final message = data['message'];
    if (message is String && message.trim().isNotEmpty) return message;
    if (message is List && message.isNotEmpty) {
      return message.map((m) => m.toString()).join('\n');
    }
  } else if (data is String && data.trim().isNotEmpty) {
    return data;
  }
  return null;
}
