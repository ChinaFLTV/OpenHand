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
    return switch (iconName) {
      'auto_awesome_rounded' => Icons.auto_awesome_rounded,
      'build_circle_rounded' => Icons.build_circle_rounded,
      'forum_rounded' => Icons.forum_rounded,
      'hub_rounded' => Icons.hub_rounded,
      'code_rounded' => Icons.code_rounded,
      'travel_explore_rounded' => Icons.travel_explore_rounded,
      'assistant_rounded' => Icons.assistant_rounded,
      'android_rounded' => Icons.android_rounded,
      _ => Icons.auto_awesome_rounded,
    };
  }
}
