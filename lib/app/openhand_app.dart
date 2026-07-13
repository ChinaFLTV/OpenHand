import 'dart:async';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/home/openhand_home_page.dart';
import '../features/mcp/mcp_controller.dart';
import '../features/mcp/model/mcp_server_ops.dart';
import '../features/mcp/widgets/mcp_ops_approval_dialog.dart';
import '../features/message_gateway/index.dart';
import '../l10n/app_localizations.dart';
import '../shared/ui/animated_dialog.dart';
import '../shared/ui/openhand_safe_scrollbar.dart';
import '../shared/ui/openhand_snack_bar.dart';
import '../shared/ui/openhand_tooltip_dismissal.dart';
import '../shared/util/timer_safety.dart';
import 'model/app_language.dart';
import 'state/settings_controller.dart';
import 'support/input_repair_service.dart';
import 'support/safe_subprocess.dart';
import 'support/silent_log.dart';
import 'theme/openhand_theme.dart';
import 'theme/openhand_theme_preset.dart';

class OpenHandApp extends StatefulWidget {
  const OpenHandApp({
    super.key,
    this.home = const OpenHandHomePage(),
    this.onShutdown,
  });

  final Widget home;
  final Future<void> Function()? onShutdown;

  @override
  State<OpenHandApp> createState() => _OpenHandAppState();
}

class _OpenHandAppState extends State<OpenHandApp> {
  late final AppLifecycleListener _lifecycleListener;
  Future<void>? _shutdownFuture;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final FocusNode _inputRepairSentinelFocusNode = FocusNode(
    debugLabel: 'input-repair-sentinel',
  );

  @override
  void initState() {
    super.initState();
    // IMK 输入死锁防御网（与 main.dart 的 SIGTERM/SIGINT
    // 互补）：在 Cmd+Q / 窗口关闭等"正常"退出路径上同步清掉所有登记
    // 在册的子进程，避免 osascript / mitmdump / npm 等遗孤继续向系统
    // 投递事件污染 IMK 上下文。`onExitRequested` 在 Dart 同步部分返回
    // 前会被 await，所以我们等 `killAllTrackedChildren` 完成再放行。
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: () async {
        await _shutdownRuntime();
        try {
          await killAllTrackedChildren();
        } catch (error, stack) {
          silentLog(
            'openhand_app',
            'kill tracked children on exit',
            error,
            stack,
          );
        }
        return AppExitResponse.exit;
      },
    );
  }

  @override
  void dispose() {
    unawaited(_shutdownRuntime());
    _lifecycleListener.dispose();
    _inputRepairSentinelFocusNode.dispose();
    super.dispose();
  }

  Future<void> _shutdownRuntime() {
    return _shutdownFuture ??= _performShutdown();
  }

  Future<void> _performShutdown() async {
    try {
      await widget.onShutdown?.call();
    } catch (error, stack) {
      silentLog('openhand_app', 'shutdown runtime', error, stack);
    }
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
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: OpenHandSnackBar.rootMessengerKey,
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
      // 用户层 reduceMotion 通过 MediaQuery.disableAnimations 向会读取该
      // 信号的框架能力和自研动画组件统一传播；系统级偏好仍由 Flutter
      // 的 PlatformDispatcher 合并进 MediaQuery。
      builder: (context, child) {
        Provider.of<MessageGatewayController?>(
          context,
          listen: false,
        )?.updateTheme(Theme.of(context));
        final media = MediaQuery.of(context);
        final disable = reduceMotion || media.disableAnimations;
        final builtChild = _OverlayPortalStabilityBoundary(
          child: child ?? const SizedBox.shrink(),
        );
        final appStack = Stack(
          fit: StackFit.expand,
          children: [
            _McpOpsApprovalHost(navigatorKey: _navigatorKey, child: builtChild),
            Offstage(
              child: Focus(
                focusNode: _inputRepairSentinelFocusNode,
                child: const SizedBox.shrink(),
              ),
            ),
            const OpenHandGlobalSnackBarHost(),
          ],
        );
        return disable == media.disableAnimations
            ? appStack
            : MediaQuery(
                data: media.copyWith(disableAnimations: disable),
                child: appStack,
              );
      },
      home: InputRepairSentinelScope(
        focusNode: _inputRepairSentinelFocusNode,
        child: widget.home,
      ),
    );
  }
}

class _McpOpsApprovalHost extends StatefulWidget {
  const _McpOpsApprovalHost({required this.navigatorKey, required this.child});

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<_McpOpsApprovalHost> createState() => _McpOpsApprovalHostState();
}

class _McpOpsApprovalHostState extends State<_McpOpsApprovalHost> {
  static const Duration _navigatorRetryDelay = Duration(milliseconds: 120);

  final Set<String> _handledDialogIds = <String>{};
  McpController? _controller;
  Timer? _dialogRetryTimer;
  String? _scheduledDialogId;
  String? _presentingDialogId;
  OpenHandDialogSession<bool>? _activeDialogSession;
  VoidCallback? _detachActiveDialogListener;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    McpController? controller;
    try {
      controller = context.read<McpController>();
    } catch (_) {
      controller = null;
    }
    if (identical(_controller, controller)) {
      return;
    }
    _dismissActiveApprovalDialog('controller changed');
    _controller?.removeListener(_handleApprovalsChanged);
    _controller = controller;
    _controller?.addListener(_handleApprovalsChanged);
    _handleApprovalsChanged();
  }

  @override
  void dispose() {
    _dialogRetryTimer?.cancel();
    _dismissActiveApprovalDialog('host disposed');
    _controller?.removeListener(_handleApprovalsChanged);
    _controller = null;
    super.dispose();
  }

  void _dismissActiveApprovalDialog(String reason) {
    _detachActiveDialogListener?.call();
    _detachActiveDialogListener = null;
    final session = _activeDialogSession;
    _activeDialogSession = null;
    if (session == null) return;
    unawaited(
      session.dismiss(
        logTag: 'openhand_app',
        logAction: 'dismiss MCP ops approval: $reason',
      ),
    );
  }

  void _handleApprovalsChanged() {
    final controller = _controller;
    if (!mounted || controller == null) {
      return;
    }
    final approvals = controller.opsApprovalRequests;
    final pendingIds = approvals.map((item) => item.id).toSet();
    final scheduledId = _scheduledDialogId;
    if (scheduledId != null && !pendingIds.contains(scheduledId)) {
      _dialogRetryTimer?.cancel();
      _dialogRetryTimer = null;
      _scheduledDialogId = null;
    }
    _handledDialogIds.removeWhere(
      (id) =>
          !pendingIds.contains(id) &&
          id != _presentingDialogId &&
          id != _scheduledDialogId,
    );
    if (_presentingDialogId != null || _scheduledDialogId != null) {
      return;
    }
    for (final approval in approvals) {
      if (_handledDialogIds.contains(approval.id)) {
        continue;
      }
      _scheduledDialogId = approval.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scheduledDialogId == approval.id) {
          _scheduledDialogId = null;
        }
        if (!mounted) {
          return;
        }
        unawaited(_presentApprovalDialog(approval));
      });
      return;
    }
  }

  Future<void> _presentApprovalDialog(McpOpsApprovalRequest approval) async {
    final controller = _controller;
    if (controller == null || !mounted) {
      return;
    }
    if (_presentingDialogId != null ||
        _handledDialogIds.contains(approval.id)) {
      return;
    }
    if (!controller.opsApprovalRequests.any((item) => item.id == approval.id)) {
      return;
    }

    _presentingDialogId = approval.id;
    _handledDialogIds.add(approval.id);
    final navigator = _dialogNavigator;
    if (navigator == null) {
      _rescheduleApprovalDialog(controller, approval);
      return;
    }
    var rescheduled = false;
    var resolvedElsewhere = false;
    var listenerAttached = false;
    OpenHandDialogSession<bool>? dialogSession;
    late final VoidCallback listener;
    void detachListener() {
      if (!listenerAttached) {
        return;
      }
      controller.removeListener(listener);
      listenerAttached = false;
    }

    try {
      final session = showMcpOpsWriteApprovalDialogOnNavigator(
        navigator,
        context: context,
        request: approval,
      );
      dialogSession = session;
      _activeDialogSession = session;
      listener = () {
        final stillPending = controller.opsApprovalRequests.any(
          (item) => item.id == approval.id,
        );
        if (stillPending) return;
        resolvedElsewhere = true;
        detachListener();
        unawaited(
          session.dismiss(
            logTag: 'openhand_app',
            logAction: 'dismiss externally resolved MCP ops approval',
          ),
        );
      };
      controller.addListener(listener);
      listenerAttached = true;
      _detachActiveDialogListener = detachListener;
      // Recheck after listener registration so an approval resolved between
      // the initial pending check and route presentation cannot get stranded.
      listener();

      final approved = await session.result;
      if (!mounted ||
          resolvedElsewhere ||
          !identical(_controller, controller)) {
        return;
      }
      detachListener();
      controller.resolveOpsApproval(approval.id, approved: approved == true);
    } catch (error, stack) {
      silentLog('openhand_app', 'present MCP ops approval', error, stack);
      if (!mounted || !identical(_controller, controller)) {
        return;
      }
      if (!resolvedElsewhere && _approvalStillPending(controller, approval)) {
        rescheduled = true;
        _rescheduleApprovalDialog(controller, approval);
        return;
      }
      if (!resolvedElsewhere && mounted) {
        controller.resolveOpsApproval(approval.id, approved: false);
      }
    } finally {
      detachListener();
      if (_presentingDialogId == approval.id) {
        _presentingDialogId = null;
      }
      if (identical(_activeDialogSession, dialogSession)) {
        _activeDialogSession = null;
        _detachActiveDialogListener = null;
      }
      if (mounted && !rescheduled) {
        _handleApprovalsChanged();
      }
    }
  }

  NavigatorState? get _dialogNavigator {
    final navigator = widget.navigatorKey.currentState;
    if (navigator == null || !navigator.mounted) {
      return null;
    }
    return navigator.overlay == null ? null : navigator;
  }

  bool _approvalStillPending(
    McpController controller,
    McpOpsApprovalRequest approval,
  ) {
    return mounted &&
        DateTime.now().toUtc().isBefore(approval.expiresAt) &&
        controller.opsApprovalRequests.any((item) => item.id == approval.id);
  }

  void _rescheduleApprovalDialog(
    McpController controller,
    McpOpsApprovalRequest approval,
  ) {
    _handledDialogIds.remove(approval.id);
    if (_presentingDialogId == approval.id) {
      _presentingDialogId = null;
    }
    if (!_approvalStillPending(controller, approval)) {
      return;
    }
    _dialogRetryTimer?.cancel();
    _scheduledDialogId = approval.id;
    _dialogRetryTimer = startSafeTimer(
      _navigatorRetryDelay,
      () {
        _dialogRetryTimer = null;
        if (_scheduledDialogId == approval.id) {
          _scheduledDialogId = null;
        }
        if (mounted) {
          _handleApprovalsChanged();
        }
      },
      onError: (error, stack) {
        silentLog('openhand_app', 'retry approval dialog', error, stack);
      },
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _OverlayPortalStabilityBoundary extends StatelessWidget {
  const _OverlayPortalStabilityBoundary({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollStartNotification>(
      onNotification: (_) {
        dismissOpenHandTooltipsSafely(
          debugLabel: 'OpenHandApp.scrollStart.dismissTooltips',
        );
        return false;
      },
      child: child,
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
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return buildOpenHandImplicitScrollbar(
      platform: getPlatform(context),
      child: child,
      details: details,
    );
  }

  @override
  GestureVelocityTrackerBuilder velocityTrackerBuilder(BuildContext context) {
    return (PointerEvent event) => VelocityTracker.withKind(event.kind);
  }
}
