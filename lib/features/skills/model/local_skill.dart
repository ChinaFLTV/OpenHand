import '../../../app/support/openhand_paths.dart';
import '../../../shared/util/input_value_parsing.dart';

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
    final sanitized = nullIfBlank(name);
    if (sanitized == null) {
      return 'S';
    }
    return sanitized.substring(0, 1).toUpperCase();
  }

  bool get hasIcon => nullIfBlank(iconPath) != null && iconKind != null;

  bool get hasEmojiIcon => nullIfBlank(emojiIcon) != null;
}
