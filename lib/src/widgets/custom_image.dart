import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class CustomImage extends StatelessWidget {
  final String uri;
  final double? height;
  final double? width;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final BorderRadius? borderRadius;

  const CustomImage({
    super.key,
    required this.uri,
    this.height,
    this.width,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.borderRadius,
  });

  bool get _isNetwork => uri.startsWith('http') || uri.startsWith('https');
  bool get _isFile => uri.startsWith('file://') || File(uri).existsSync();
  bool get _isAsset =>
      !uri.startsWith('http') &&
      !uri.startsWith('file://') &&
      !uri.startsWith('/');

  @override
  Widget build(BuildContext context) {
    Widget imageWidget;

    if (_isNetwork) {
      imageWidget = CachedNetworkImage(
        imageUrl: uri,
        height: height,
        width: width,
        fit: fit,
        placeholder: (context, url) => placeholder ?? _defaultPlaceholder(),
        errorWidget:
            (context, url, error) => errorWidget ?? _defaultPlaceholder(),
      );
    } else if (_isFile) {
      imageWidget = Image.file(
        File(uri.replaceAll('file://', '')),
        height: height,
        width: width,
        fit: fit,
        errorBuilder:
            (context, error, stackTrace) =>
                errorWidget ?? _defaultPlaceholder(),
      );
    } else if (_isAsset) {
      imageWidget = Image.asset(
        uri,
        height: height,
        width: width,
        fit: fit,
        errorBuilder:
            (context, error, stackTrace) =>
                errorWidget ?? _defaultPlaceholder(),
      );
    } else {
      imageWidget = errorWidget ?? _defaultPlaceholder();
    }

    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(8),
      child: imageWidget,
    );
  }

  Widget _defaultPlaceholder() => Container(
    height: height,
    width: width,
    alignment: Alignment.center,
    child: const Icon(Icons.music_note_rounded,),
  );
}
