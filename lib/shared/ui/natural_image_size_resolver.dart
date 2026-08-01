import 'package:flutter/widgets.dart';

/// 订阅 [ImageProvider] 流，取得图片自身宽高，供弹窗按原始宽高比排版。
///
/// 只借用 Flutter 的 ImageCache（同一张图二次解析不会重复下载或解码）。
/// 解码失败时 [size] 保持为 null，调用方走占位尺寸分支即可。
class NaturalImageSizeResolver {
  NaturalImageSizeResolver({required this.onResolved});

  /// 尺寸在首帧之后才到达时回调，用于触发重建。
  ///
  /// 命中缓存的同步回调发生在首次 build 之前，此时只写字段、不触发回调，
  /// 避免在 `initState` 中调用 `setState`。
  final VoidCallback onResolved;

  ImageStream? _stream;
  ImageStreamListener? _listener;
  Size? _size;

  /// 已解析出的原始尺寸；尚未解析或解析失败时为 null。
  Size? get size => _size;

  /// 订阅 [provider]。[provider] 为 null 时不做任何事；重复调用会先解绑旧流，
  /// 因此可安全用于 provider 变化后的重新解析。
  void resolve(ImageProvider? provider) {
    _detach();
    _size = null;
    if (provider == null) return;
    final stream = provider.resolve(const ImageConfiguration());
    final listener = ImageStreamListener(
      (ImageInfo info, bool synchronousCall) {
        final width = info.image.width.toDouble();
        final height = info.image.height.toDouble();
        if (width <= 0 || height <= 0) return;
        final resolved = Size(width, height);
        if (_size == resolved) return;
        _size = resolved;
        if (!synchronousCall) onResolved();
      },
      onError: (Object _, StackTrace? _) {
        // 保持 size 为 null：调用方的 Image 控件自身会渲染 errorBuilder。
      },
    );
    stream.addListener(listener);
    _stream = stream;
    _listener = listener;
  }

  void dispose() => _detach();

  void _detach() {
    final stream = _stream;
    final listener = _listener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _stream = null;
    _listener = null;
  }
}
