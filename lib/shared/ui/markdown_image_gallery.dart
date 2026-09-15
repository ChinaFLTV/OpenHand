import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:markdown/markdown.dart' as md;

import '../../features/home/index.dart' show showOpenHandImageGallery;

const int kOpenHandImageGalleryLimit = 256;

class OpenHandGalleryImage {
  const OpenHandGalleryImage({required this.uri, required this.title});
  final Uri uri;
  final String title;
  bool get isSvg => uri.path.toLowerCase().endsWith('.svg');
  String? get filePath => uri.scheme == 'file' ? uri.toFilePath() : null;
}

/// 消息卡片提供定位回调；普通文档无需显示消息定位按钮。
class OpenHandImageMessageScope extends InheritedWidget {
  const OpenHandImageMessageScope({
    super.key,
    this.onLocate,
    this.onInteractiveTap,
    this.images = const [],
    required super.child,
  });
  final Future<void> Function()? onLocate;
  final VoidCallback? onInteractiveTap;
  final List<OpenHandGalleryImage> images;
  static OpenHandImageMessageScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OpenHandImageMessageScope>();
  @override
  bool updateShouldNotify(OpenHandImageMessageScope oldWidget) =>
      onLocate != oldWidget.onLocate ||
      onInteractiveTap != oldWidget.onInteractiveTap ||
      images != oldWidget.images;
}

Future<void> showOpenHandMessageImage(
  BuildContext context,
  OpenHandGalleryImage image,
) {
  final scope = OpenHandImageMessageScope.maybeOf(context);
  scope?.onInteractiveTap?.call();
  final index =
      scope?.images.indexWhere((entry) => entry.uri == image.uri) ?? -1;
  return showOpenHandImageGallery(
    context,
    images: index < 0 ? [image] : scope!.images,
    initialIndex: index < 0 ? 0 : index,
    onLocate: scope?.onLocate,
  );
}

List<OpenHandGalleryImage> collectOpenHandMarkdownImages(
  List<md.Node> nodes, {
  String? Function(Uri)? resolveFilePath,
}) {
  final images = <OpenHandGalleryImage>[];
  final seen = <String>{};
  void visit(List<md.Node> children) {
    for (final node in children) {
      if (images.length >= kOpenHandImageGalleryLimit) return;
      if (node is! md.Element) continue;
      if (node.tag == 'img') {
        final source = node.attributes['src'] ?? '';
        final parsed = Uri.tryParse(source);
        if (parsed == null) continue;
        final file = resolveFilePath?.call(parsed);
        final uri = file == null ? parsed : Uri.file(file);
        if (!['http', 'https', 'file'].contains(uri.scheme)) continue;
        if (!seen.add(source)) continue;
        images.add(
          OpenHandGalleryImage(
            uri: uri,
            title: node.attributes['alt']?.trim().isNotEmpty == true
                ? node.attributes['alt']!
                : node.attributes['title'] ?? '图片',
          ),
        );
      } else if (node.children != null) {
        visit(node.children!);
      }
    }
  }

  visit(nodes);
  return List.unmodifiable(images);
}

Widget buildOpenHandGalleryImage(
  BuildContext context, {
  required Uri uri,
  required String? title,
  required String? alt,
  required List<OpenHandGalleryImage> images,
  String? Function(Uri)? resolveFilePath,
  Widget? child,
}) {
  final file = resolveFilePath?.call(uri);
  final resolved = file == null ? uri : Uri.file(file);
  final index = images.indexWhere((image) => image.uri == resolved);
  if (!['http', 'https', 'file'].contains(resolved.scheme)) {
    return child ?? Text(alt ?? title ?? '图片无法预览');
  }
  final gallery = index < 0
      ? [OpenHandGalleryImage(uri: resolved, title: alt ?? title ?? '图片')]
      : images;
  final selectedIndex = index < 0 ? 0 : index;
  final image = gallery[selectedIndex];
  Widget failed(BuildContext _, Object error, StackTrace? stack) =>
      const Padding(
        padding: EdgeInsets.all(16),
        child: Icon(Icons.broken_image_outlined),
      );
  final content =
      (image.isSvg
          ? (image.filePath != null
                ? SvgPicture.file(File(image.filePath!), errorBuilder: failed)
                : SvgPicture.network(
                    image.uri.toString(),
                    errorBuilder: failed,
                  ))
          : child) ??
      (image.filePath != null
          ? Image.file(
              File(image.filePath!),
              fit: BoxFit.contain,
              cacheWidth: 1280,
              errorBuilder: failed,
            )
          : Image.network(
              image.uri.toString(),
              fit: BoxFit.contain,
              cacheWidth: 1280,
              errorBuilder: failed,
            ));
  return Builder(
    builder: (context) => Semantics(
      button: true,
      label: '预览图片：${image.title}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            final scope = OpenHandImageMessageScope.maybeOf(context);
            scope?.onInteractiveTap?.call();
            unawaited(
              showOpenHandImageGallery(
                context,
                images: gallery,
                initialIndex: selectedIndex,
                onLocate: scope?.onLocate,
              ),
            );
          },
          child: IgnorePointer(child: content),
        ),
      ),
    ),
  );
}
