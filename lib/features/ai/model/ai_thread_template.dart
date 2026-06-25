import 'package:flutter/material.dart';

import 'ai_thread_template_icon_names.dart';

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

  static const String autoAwesomeRounded =
      AiThreadTemplateIconNames.autoAwesomeRounded;
  static const String buildCircleRounded =
      AiThreadTemplateIconNames.buildCircleRounded;
  static const String forumRounded = AiThreadTemplateIconNames.forumRounded;
  static const String hubRounded = AiThreadTemplateIconNames.hubRounded;
  static const String codeRounded = AiThreadTemplateIconNames.codeRounded;
  static const String travelExploreRounded =
      AiThreadTemplateIconNames.travelExploreRounded;
  static const String assistantRounded =
      AiThreadTemplateIconNames.assistantRounded;
  static const String androidRounded = AiThreadTemplateIconNames.androidRounded;

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
