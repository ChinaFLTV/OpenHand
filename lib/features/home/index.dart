// Home feature barrel — exposes the page widget and shared cross-feature helpers.
// Home 自身是 widget-bundle 形态（带大量 part files 的 page）；P2 拆解前
// 此 barrel 仅暴露 sibling 实际需要的符号。
export 'message_path_linking.dart';
export 'openhand_home_page.dart' show OpenHandHomePage;
