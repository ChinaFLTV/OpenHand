import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/util/input_value_parsing.dart';

enum OpenHandThemePreset {
  darkNightPurple('dark_night_purple', Color(0xFF6D4ACF)),
  deepSeaBlue('deep_sea_blue', Color(0xFF2D63B8)),
  mistGray('mist_gray', Color(0xFF8A8F99)),
  obsidianBlack('obsidian_black', Color(0xFF2F3138)),
  polarWhite('polar_white', Color(0xFFE7E3DA)),
  frostMorningBlue('frost_morning_blue', Color(0xFF7FAFD8)),
  duskMountainGreen('dusk_mountain_green', Color(0xFF4F7B6A)),
  nebulaPurple('nebula_purple', Color(0xFF8B63E6)),
  emberOrange('ember_orange', Color(0xFFD97A33)),
  tundraGreen('tundra_green', Color(0xFF5F7C53)),
  moonShadowSilver('moon_shadow_silver', Color(0xFFA7AFBC)),
  amberGold('amber_gold', Color(0xFFC99A27)),
  rainyCyan('rainy_cyan', Color(0xFF4E7C86)),
  graphiteGray('graphite_gray', Color(0xFF5A5E66)),
  glacierBlue('glacier_blue', Color(0xFF6FAFD9)),
  blazeRed('blaze_red', Color(0xFFC84B4B)),
  nightfallBlue('nightfall_blue', Color(0xFF284B8B)),
  coldMoonWhite('cold_moon_white', Color(0xFFDDE6F0)),
  pineInk('pine_ink', Color(0xFF38383F)),
  skyCyan('sky_cyan', Color(0xFF4E93C8));

  const OpenHandThemePreset(this.storageValue, this.seedColor);

  final String storageValue;
  final Color seedColor;


  static OpenHandThemePreset fromStorage(String? value) {
    return enumByStorageValueOr(
      values,
      value,
      (preset) => preset.storageValue,
      fallback: OpenHandThemePreset.deepSeaBlue,
    );
  }

  String label(AppLocalizations l10n) {
    return switch (this) {
      OpenHandThemePreset.darkNightPurple => l10n.themePresetDarkNightPurple,
      OpenHandThemePreset.deepSeaBlue => l10n.themePresetDeepSeaBlue,
      OpenHandThemePreset.mistGray => l10n.themePresetMistGray,
      OpenHandThemePreset.obsidianBlack => l10n.themePresetObsidianBlack,
      OpenHandThemePreset.polarWhite => l10n.themePresetPolarWhite,
      OpenHandThemePreset.frostMorningBlue => l10n.themePresetFrostMorningBlue,
      OpenHandThemePreset.duskMountainGreen =>
        l10n.themePresetDuskMountainGreen,
      OpenHandThemePreset.nebulaPurple => l10n.themePresetNebulaPurple,
      OpenHandThemePreset.emberOrange => l10n.themePresetEmberOrange,
      OpenHandThemePreset.tundraGreen => l10n.themePresetTundraGreen,
      OpenHandThemePreset.moonShadowSilver => l10n.themePresetMoonShadowSilver,
      OpenHandThemePreset.amberGold => l10n.themePresetAmberGold,
      OpenHandThemePreset.rainyCyan => l10n.themePresetRainyCyan,
      OpenHandThemePreset.graphiteGray => l10n.themePresetGraphiteGray,
      OpenHandThemePreset.glacierBlue => l10n.themePresetGlacierBlue,
      OpenHandThemePreset.blazeRed => l10n.themePresetBlazeRed,
      OpenHandThemePreset.nightfallBlue => l10n.themePresetNightfallBlue,
      OpenHandThemePreset.coldMoonWhite => l10n.themePresetColdMoonWhite,
      OpenHandThemePreset.pineInk => l10n.themePresetPineInk,
      OpenHandThemePreset.skyCyan => l10n.themePresetSkyCyan,
    };
  }
}
