import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import 'api_constants.dart';

/// Shared Dio configuration.
///
/// Security note: authentication bodies/headers (passwords, tokens) are
/// never logged. [PrettyDioLogger] is kept for method/path/error debugging
/// with all header/body printing disabled.
class DioClient {
  DioClient._();

  static Dio create({Dio? dio, bool enableLogger = true}) {
    final client = dio ?? Dio();
    client.options = BaseOptions(
      baseUrl: ApiConstants.baseApiUrl,
      connectTimeout: ApiConstants.connectTimeout,
      receiveTimeout: ApiConstants.receiveTimeout,
      sendTimeout: ApiConstants.sendTimeout,
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
    );

    if (enableLogger) {
      final hasLogger = client.interceptors
          .whereType<PrettyDioLogger>()
          .isNotEmpty;
      if (!hasLogger) {
        client.interceptors.add(
          PrettyDioLogger(
            request: true,
            requestHeader: false,
            requestBody: false,
            responseHeader: false,
            // Never log response bodies: login/refresh responses contain
            // access & refresh tokens.
            responseBody: false,
            error: true,
            compact: true,
            // Route logs through debugPrint to avoid release-console noise.
            logPrint: (Object object) => debugPrint(object.toString()),
          ),
        );
      }
    }
    return client;
  }

  /// Authorization header for authenticated requests.
  static Options authOptions(String accessToken) {
    return Options(headers: {'Authorization': 'Bearer $accessToken'});
  }
}
