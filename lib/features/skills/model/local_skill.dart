import '../../../app/support/openhand_paths.dart';

enum LocalSkillIconKind { svg, raster }

class LocalSkill {
  const LocalSkill({
    required this.name,
    required this.description,
    required this.directoryPath,
    required this.manifestPath,
    required this.relativeDirectoryPath,
    this.defaultPrompt,
    this.emojiIcon,
    this.iconPath,
    this.iconKind,
  });

  final String name;
  final String description;
  final String directoryPath;
  final String manifestPath;
  final String relativeDirectoryPath;
  final String? defaultPrompt;
  final String? emojiIcon;
  final String? iconPath;
  final LocalSkillIconKind? iconKind;

  String get displayDirectoryPath =>
      OpenHandPaths.shortenHomePath(directoryPath);

  String get initials {
    final sanitized = name.trim();
    if (sanitized.isEmpty) {
      return 'S';
    }
    return sanitized.substring(0, 1).toUpperCase();
  }

  bool get hasIcon =>
      iconPath != null && iconPath!.trim().isNotEmpty && iconKind != null;

  bool get hasEmojiIcon => emojiIcon != null && emojiIcon!.trim().isNotEmpty;
}
