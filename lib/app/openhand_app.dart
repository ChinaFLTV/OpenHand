import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../features/home/openhand_home_page.dart';
import '../features/message_gateway/index.dart';
import '../l10n/app_localizations.dart';
import 'model/app_language.dart';
import 'state/settings_controller.dart';
import 'support/openhand_notification_service.dart';
import 'support/safe_subprocess.dart';
import 'theme/openhand_theme.dart';
import 'theme/openhand_theme_preset.dart';

class OpenHandApp extends StatefulWidget {
  const OpenHandApp({super.key, this.home = const OpenHandHomePage()});

  final Widget home;

  @override
  State<OpenHandApp> createState() => _OpenHandAppState();
}

class _OpenHandAppState extends State<OpenHandApp> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    // 2026-05-19 — IMK 输入死锁防御网（与 main.dart 的 SIGTERM/SIGINT
    // 互补）：在 Cmd+Q / 窗口关闭等"正常"退出路径上同步清掉所有登记
    // 在册的子进程，避免 osascript / mitmdump / npm 等遗孤继续向系统
    // 投递事件污染 IMK 上下文。`onExitRequested` 在 Dart 同步部分返回
    // 前会被 await，所以我们等 `killAllTrackedChildren` 完成再放行。
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: () async {
        try {
          await killAllTrackedChildren();
        } catch (_) {}
        return AppExitResponse.exit;
      },
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = context.select<SettingsController, ThemeMode>(
      (controller) => controller.themeMode,
    );
    final themePreset = context.select<SettingsController, OpenHandThemePreset>(
      (controller) => controller.themePreset,
    );
    final locale = context.select<SettingsController, Locale?>(
      (controller) => controller.locale,
    );
    final reduceMotion = context.select<SettingsController, bool>(
      (controller) => controller.reduceMotion,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: OpenHandNotificationService.scaffoldMessengerKey,
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      themeMode: themeMode,
      theme: OpenHandTheme.light(themePreset),
      darkTheme: OpenHandTheme.dark(themePreset),
      locale: locale,
      supportedLocales: supportedAppLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      themeAnimationCurve: Curves.easeOutCubic,
      themeAnimationDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 220),
      scrollBehavior: const _SafeScrollBehavior(),
      // 2026-05 — 用户层 reduceMotion 通过 MediaQuery.disableAnimations 同步
      // 给框架（Hero/PageRoute/Theme 等内置动画自动归零），同时也是自研
      // 动画组件（AnimatedExpandable / AppearOnce 等）的统一信号源。OS-level
      // reduceMotion 仍然由 Flutter 的 PlatformDispatcher 自动并入。
      builder: (context, child) {
        Provider.of<MessageGatewayController?>(
          context,
          listen: false,
        )?.updateTheme(Theme.of(context));
        final media = MediaQuery.of(context);
        final disable = reduceMotion || media.disableAnimations;
        if (disable == media.disableAnimations) {
          return child ?? const SizedBox.shrink();
        }
        return MediaQuery(
          data: media.copyWith(disableAnimations: disable),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: widget.home,
    );
  }
}

/// Work around a Flutter framework bug on macOS where trackpad pointer events
/// can arrive with non‑monotonic timestamps, causing an assertion failure in
/// [IOSScrollViewFlingVelocityTracker].  Using the basic [VelocityTracker]
/// avoids that assertion while keeping fling/scroll behaviour functional.
class _SafeScrollBehavior extends MaterialScrollBehavior {
  const _SafeScrollBehavior();

  @override
  GestureVelocityTrackerBuilder velocityTrackerBuilder(BuildContext context) {
    return (PointerEvent event) => VelocityTracker.withKind(event.kind);
  }
}
