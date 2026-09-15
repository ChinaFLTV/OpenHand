import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:markdown/markdown.dart' as md;

import '../../features/home/index.dart' show showOpenHandImageGallery;
import 'openhand_image_reveal.dart';

const int kOpenHandImageGalleryLimit = 256;

class OpenHandGalleryImage {
  const OpenHandGalleryImage({
    required this.uri,
    required this.title,
    this.messageId,
    this.onLocate,
  });
  final Uri uri;
  final String title;
  final String? messageId;
  final Future<void> Function()? onLocate;
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
    this.messageId,
    this.galleryImages,
    required super.child,
  });
  final Future<void> Function()? onLocate;
  final VoidCallback? onInteractiveTap;
  final List<OpenHandGalleryImage> images;
  final String? messageId;
  final Iterable<OpenHandGalleryImage> Function()? galleryImages;
  static OpenHandImageMessageScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OpenHandImageMessageScope>();
  @override
  bool updateShouldNotify(OpenHandImageMessageScope oldWidget) =>
      onLocate != oldWidget.onLocate ||
      onInteractiveTap != oldWidget.onInteractiveTap ||
      images != oldWidget.images ||
      messageId != oldWidget.messageId ||
      galleryImages != oldWidget.galleryImages;
}

/// 仅在打开预览时取有界快照，保留所点图片前后的消息顺序。
({List<OpenHandGalleryImage> images, int index, bool found})
resolveOpenHandImageGallery(
  Iterable<OpenHandGalleryImage> images,
  OpenHandGalleryImage selected, {
  String? messageId,
}) {
  final window = ListQueue<OpenHandGalleryImage>();
  var index = -1;
  for (final image in images) {
    if (index < 0 &&
        image.uri == selected.uri &&
        (messageId == null || image.messageId == messageId)) {
      index = window.length;
    }
    window.addLast(image);
    if (window.length > kOpenHandImageGalleryLimit) {
      window.removeFirst();
      if (index >= 0) index--;
    }
    if (index >= 0 &&
        index <= kOpenHandImageGalleryLimit ~/ 2 &&
        window.length == kOpenHandImageGalleryLimit) {
      break;
    }
  }
  return index < 0
      ? (images: [selected], index: 0, found: false)
      : (images: List.unmodifiable(window), index: index, found: true);
}

Future<void> showOpenHandMessageImage(
  BuildContext context,
  OpenHandGalleryImage image, {
  List<OpenHandGalleryImage> fallbackImages = const [],
}) {
  final scope = OpenHandImageMessageScope.maybeOf(context);
  scope?.onInteractiveTap?.call();
  final local = collectOpenHandMessageImages(
    content: '',
    attachments: [...?scope?.images, ...fallbackImages],
  );
  var gallery = resolveOpenHandImageGallery(
    scope?.galleryImages?.call() ?? local,
    image,
    messageId: scope?.galleryImages == null ? null : scope?.messageId,
  );
  if (!gallery.found) {
    gallery = resolveOpenHandImageGallery(local, image);
  }
  return showOpenHandImageGallery(
    context,
    images: gallery.images,
    initialIndex: gallery.index,
    onLocate: gallery.images[gallery.index].onLocate == null
        ? scope?.onLocate
        : null,
  );
}

/// 合并同一消息的附件和正文图片，跨消息保留各自的定位信息。
Iterable<OpenHandGalleryImage> collectOpenHandMessageImages({
  required String content,
  Iterable<OpenHandGalleryImage> attachments = const [],
  String? messageId,
  Future<void> Function()? onLocate,
  String? Function(Uri)? resolveFilePath,
}) sync* {
  final seen = <Uri>{};
  final markdownImages = content.contains('!')
      ? collectOpenHandMarkdownImages(
          md.Document(
            extensionSet: md.ExtensionSet.gitHubWeb,
          ).parseLines(content.split('\n')),
          resolveFilePath: resolveFilePath,
        )
      : const <OpenHandGalleryImage>[];
  for (final image in attachments.followedBy(markdownImages)) {
    if (!seen.add(image.uri)) continue;
    yield OpenHandGalleryImage(
      uri: image.uri,
      title: image.title,
      messageId: messageId,
      onLocate: onLocate,
    );
  }
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
                ? SvgPicture.file(
                    File(image.filePath!),
                    placeholderBuilder: (_) =>
                        const OpenHandImageShimmerPlaceholder(),
                    errorBuilder: failed,
                  )
                : SvgPicture.network(
                    image.uri.toString(),
                    placeholderBuilder: (_) =>
                        const OpenHandImageShimmerPlaceholder(),
                    errorBuilder: failed,
                  ))
          : child) ??
      (image.filePath != null
          ? Image.file(
              File(image.filePath!),
              fit: BoxFit.contain,
              cacheWidth: 1280,
              frameBuilder: openHandImageRevealFrameBuilder,
              errorBuilder: failed,
            )
          : Image.network(
              image.uri.toString(),
              fit: BoxFit.contain,
              cacheWidth: 1280,
              frameBuilder: openHandImageRevealFrameBuilder,
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
            unawaited(
              showOpenHandMessageImage(context, image, fallbackImages: gallery),
            );
          },
          child: IgnorePointer(child: content),
        ),
      ),
    ),
  );
}
