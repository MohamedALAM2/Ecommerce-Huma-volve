import 'package:flutter/material.dart';

import '../theme.dart';

/// Network image with loading and error states.
///
/// The public catalog contains invalid, missing, or inaccessible image URLs,
/// so this widget never leaves a blank/error box: it shows a neutral
/// placeholder instead, without changing the surrounding layout.
class AppNetworkImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  const AppNetworkImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.borderRadius,
  });

  bool get _hasUrl {
    final trimmed = imageUrl.trim();
    if (trimmed.isEmpty) return false;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return false;
    // Match ProductImageNormalizer: only http(s) with a host is attempted.
    // Anything else (empty, ftp/data, host-less) shows the local placeholder.
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    if (uri.host.isEmpty) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final Widget image = _hasUrl
        ? Image.network(
            imageUrl,
            fit: fit,
            width: width,
            height: height,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return _Placeholder(width: width, height: height, loading: true);
            },
            errorBuilder: (context, error, stackTrace) {
              return _Placeholder(width: width, height: height);
            },
          )
        : _Placeholder(width: width, height: height);

    final radius = borderRadius;
    if (radius == null) return image;
    return ClipRRect(borderRadius: radius, child: image);
  }
}

class _Placeholder extends StatelessWidget {
  final double? width;
  final double? height;
  final bool loading;

  const _Placeholder({this.width, this.height, this.loading = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width ?? double.infinity,
      height: height ?? double.infinity,
      color: Colors.grey.shade200,
      child: Center(
        child: loading
            ? SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppTheme.primary.withValues(alpha: 0.6),
                ),
              )
            : Icon(Icons.image_outlined, size: 40, color: Colors.grey.shade400),
      ),
    );
  }
}
