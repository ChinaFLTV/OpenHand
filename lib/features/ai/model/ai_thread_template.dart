import 'package:flutter/material.dart';

enum AiThreadTemplateAvailability {
  all,
  appleOnly;

  bool supportsPlatform(TargetPlatform platform) {
    return switch (this) {
      AiThreadTemplateAvailability.all => true,
      AiThreadTemplateAvailability.appleOnly =>
        platform == TargetPlatform.macOS || platform == TargetPlatform.iOS,
    };
  }
}

class AiThreadTemplateIcons {
  const AiThreadTemplateIcons._();

  static const String autoAwesomeRounded = 'auto_awesome_rounded';
  static const String buildCircleRounded = 'build_circle_rounded';
  static const String forumRounded = 'forum_rounded';
  static const String hubRounded = 'hub_rounded';
  static const String codeRounded = 'code_rounded';
  static const String travelExploreRounded = 'travel_explore_rounded';
  static const String assistantRounded = 'assistant_rounded';
  static const String androidRounded = 'android_rounded';

  static const IconData fallback = Icons.auto_awesome_rounded;

  static const Map<String, IconData> _byName = <String, IconData>{
    autoAwesomeRounded: Icons.auto_awesome_rounded,
    buildCircleRounded: Icons.build_circle_rounded,
    forumRounded: Icons.forum_rounded,
    hubRounded: Icons.hub_rounded,
    codeRounded: Icons.code_rounded,
    travelExploreRounded: Icons.travel_explore_rounded,
    assistantRounded: Icons.assistant_rounded,
    androidRounded: Icons.android_rounded,
  };

  static IconData resolve(String iconName) {
    return _byName[iconName.trim()] ?? fallback;
  }
}

class AiThreadTemplate {
  const AiThreadTemplate({
    required this.id,
    required this.name,
    required this.iconName,
    required this.description,
    required this.internalVersion,
    required this.promptAssetDirectory,
    this.availability = AiThreadTemplateAvailability.all,
  });

  final String id;
  final String name;
  final String iconName;
  final String description;
  final String internalVersion;
  final String promptAssetDirectory;
  final AiThreadTemplateAvailability availability;

  bool isSupportedOnPlatform(TargetPlatform platform) {
    return availability.supportsPlatform(platform);
  }

  IconData get iconData {
    return AiThreadTemplateIcons.resolve(iconName);
  }
}
