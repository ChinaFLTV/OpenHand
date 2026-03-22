import '../features/home/openhand_home_page.dart';
import '../l10n/app_localizations.dart';
import 'model/app_language.dart';
import 'state/settings_controller.dart';
import 'theme/openhand_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class OpenHandApp extends StatelessWidget {
  const OpenHandApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsController = context.watch<SettingsController>();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      themeMode: settingsController.themeMode,
      theme: OpenHandTheme.light(settingsController.themePreset),
      darkTheme: OpenHandTheme.dark(settingsController.themePreset),
      locale: settingsController.locale,
      supportedLocales: supportedAppLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      themeAnimationCurve: Curves.easeOutCubic,
      themeAnimationDuration: const Duration(milliseconds: 220),
      home: const OpenHandHomePage(),
    );
  }
}
