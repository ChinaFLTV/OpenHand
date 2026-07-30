import 'package:characters/characters.dart';

import '../../../app/support/openhand_paths.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/xml_escape.dart';

const int skillManifestMaxBytes = 2 * kBytesPerMiB;

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
    return sanitized.characters.first.toUpperCase();
  }

  bool get hasIcon => nullIfBlank(iconPath) != null && iconKind != null;

  bool get hasEmojiIcon => nullIfBlank(emojiIcon) != null;
}

String buildLocalSkillSystemReminder(
  LocalSkill skill, {
  String? manifestContent,
}) {
  final manifest = manifestContent?.trim() ?? '';
  final description = skill.description.trim();
  final body = manifest.isNotEmpty
      ? manifest
      : (description.isNotEmpty
            ? description
            : 'SKILL.md is unavailable. Infer the intended workflow from the skill name.');
  final buffer = StringBuffer()
    ..writeln(
      'The user selected the local skill "${skill.name}" for this turn.',
    )
    ..writeln(
      'Apply its SKILL.md instructions to this request, even if the skill appears unrelated. They override conflicting default behavior.',
    )
    ..writeln()
    ..writeln(
      '<skill-manifest name="${escapeXmlAttribute(skill.name)}" path="${escapeXmlAttribute(skill.manifestPath)}">',
    )
    ..writeln(body)
    ..write('</skill-manifest>');
  return buffer.toString();
}
