/// Available code highlighting colour themes for the editor.
enum EditorCodeTheme {
  /// Default Material You pastel tones.
  materialYou,

  /// Monokai-inspired warm tones.
  monokai,

  /// Solarized palette with blue-green emphasis.
  solarized,

  /// One Dark (Atom-inspired) theme.
  oneDark,

  /// GitHub light / dark style.
  github,

  /// Dracula theme.
  dracula;

  String get storageValue => name;

  String labelZh(bool darkSurface) {
    return switch (this) {
      EditorCodeTheme.materialYou => 'Material You（默认）',
      EditorCodeTheme.monokai => 'Monokai',
      EditorCodeTheme.solarized =>
        darkSurface ? 'Solarized Dark' : 'Solarized Light',
      EditorCodeTheme.oneDark => 'One Dark',
      EditorCodeTheme.github =>
        darkSurface ? 'GitHub Dark' : 'GitHub Light',
      EditorCodeTheme.dracula => 'Dracula',
    };
  }

  String labelEn(bool darkSurface) {
    return switch (this) {
      EditorCodeTheme.materialYou => 'Material You (Default)',
      EditorCodeTheme.monokai => 'Monokai',
      EditorCodeTheme.solarized =>
        darkSurface ? 'Solarized Dark' : 'Solarized Light',
      EditorCodeTheme.oneDark => 'One Dark',
      EditorCodeTheme.github =>
        darkSurface ? 'GitHub Dark' : 'GitHub Light',
      EditorCodeTheme.dracula => 'Dracula',
    };
  }

  static EditorCodeTheme fromStorage(String value) {
    for (final theme in EditorCodeTheme.values) {
      if (theme.storageValue == value) return theme;
    }
    return EditorCodeTheme.materialYou;
  }
}
