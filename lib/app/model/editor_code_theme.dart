import '../../shared/util/input_value_parsing.dart';

/// 编辑器可选的代码高亮主题。
enum EditorCodeTheme {
  /// 默认的 Material You 柔和配色。
  materialYou,

  /// Monokai 风格暖色配色。
  monokai,

  /// 以蓝绿色为主的 Solarized 配色。
  solarized,

  /// Atom 风格的 One Dark 主题。
  oneDark,

  /// GitHub 明暗主题风格。
  github,

  /// Dracula 主题。
  dracula;

  String get storageValue => name;

  String labelEn(bool darkSurface) {
    return switch (this) {
      EditorCodeTheme.materialYou => 'Material You (Default)',
      EditorCodeTheme.monokai => 'Monokai',
      EditorCodeTheme.solarized =>
        darkSurface ? 'Solarized Dark' : 'Solarized Light',
      EditorCodeTheme.oneDark => 'One Dark',
      EditorCodeTheme.github => darkSurface ? 'GitHub Dark' : 'GitHub Light',
      EditorCodeTheme.dracula => 'Dracula',
    };
  }

  static EditorCodeTheme fromStorage(String value) {
    return enumByStorageValueOr(
      values,
      value,
      (theme) => theme.storageValue,
      fallback: EditorCodeTheme.materialYou,
    );
  }
}
