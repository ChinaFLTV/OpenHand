import '../../../shared/ui/markdown_image_gallery.dart';
import '../../../shared/util/text_normalization.dart';
import '../model/dingtalk_message_gateway.dart';

/// 引用图片属于当前卡片的展示位置，不能按原消息 ID 匹配图库。
Iterable<OpenHandGalleryImage> collectDingTalkMessageImages(
  DingTalkGatewayMessage message, {
  Future<void> Function()? onLocate,
}) sync* {
  final quoted = message.quotedMessage;
  final seen = <Uri>{};
  for (final section in [
    if (quoted != null) (content: quoted.content, media: quoted.media),
    (content: message.content, media: message.media),
  ]) {
    for (final image in collectOpenHandMessageImages(
      content: stripImageSummaryMarkup(section.content),
      messageId: message.id,
      onLocate: onLocate,
      attachments: section.media
          .where(
            (item) =>
                item.kind == DingTalkMediaKind.image &&
                item.localPath.trim().isNotEmpty,
          )
          .map(
            (item) => OpenHandGalleryImage(
              uri: Uri.file(item.localPath.trim()),
              title: item.displayName,
            ),
          ),
    )) {
      if (seen.add(image.uri)) yield image;
    }
  }
}
