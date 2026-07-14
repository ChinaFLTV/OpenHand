// 检查更新弹窗，带 Q 弹动画进度条和流畅的状态切换。
import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/model/app_info.dart';
import '../../app/support/app_update_checker.dart';
import '../../app/support/safe_subprocess.dart';
import '../../l10n/app_localizations.dart';
import '../util/byte_size_format.dart';
import '../util/date_time_format.dart';
import '../util/input_value_parsing.dart';
import '../util/localized_text.dart';
import 'animated_dialog.dart';
import 'motion_preference.dart';
import 'openhand_dialog_action_button.dart';

/// 检查更新弹窗入口。使用全局弹窗动画设置。
Future<void> showAppUpdateDialog({
  required BuildContext context,
  required AppInfo appInfo,
  AppUpdateDataSource? dataSource,
}) {
  return showAnimatedDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _AppUpdateDialogContent(
      appInfo: appInfo,
      dataSource: dataSource ?? GitHubReleaseDataSource(),
    ),
  );
}

enum _UpdatePhase { checking, available, notAvailable, downloading, error }

const Duration _kAppUpdatePhaseSwitchDuration = Duration(milliseconds: 320);
const Duration _kAppUpdateProgressAnimationDuration = Duration(
  milliseconds: 400,
);

class _AppUpdateDialogContent extends StatefulWidget {
  const _AppUpdateDialogContent({
    required this.appInfo,
    required this.dataSource,
  });

  final AppInfo appInfo;
  final AppUpdateDataSource dataSource;

  @override
  State<_AppUpdateDialogContent> createState() =>
      _AppUpdateDialogContentState();
}

class _AppUpdateDialogContentState extends State<_AppUpdateDialogContent>
    with SingleTickerProviderStateMixin {
  _UpdatePhase _phase = _UpdatePhase.checking;
  AppReleaseInfo? _release;
  String _errorMessage = '';
  String? _downloadedFilePath;
  Completer<void>? _downloadCancellation;

  late final AnimationController _progressAnimController;
  late Animation<double> _progressAnimation;
  double _targetProgress = 0;

  @override
  void initState() {
    super.initState();
    _progressAnimController = AnimationController(
      vsync: this,
      duration: _kAppUpdateProgressAnimationDuration,
    );
    _progressAnimation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(
        parent: _progressAnimController,
        curve: Curves.easeOutCubic,
      ),
    );
    _checkForUpdate();
  }

  @override
  void dispose() {
    final cancellation = _downloadCancellation;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
    _progressAnimController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!openHandTickerMotionEnabled(context) &&
        _progressAnimation.value != _targetProgress) {
      _settleProgressAnimation();
    }
  }

  Future<void> _checkForUpdate() async {
    final result = await widget.dataSource.checkForUpdate(
      widget.appInfo.version,
    );
    if (!mounted) return;
    setState(() {
      switch (result) {
        case AppUpdateAvailable(:final release):
          _phase = _UpdatePhase.available;
          _release = release;
        case AppUpdateNotAvailable():
          _phase = _UpdatePhase.notAvailable;
        case AppUpdateCheckError(:final message):
          _phase = _UpdatePhase.error;
          _errorMessage = message;
      }
    });
  }

  Future<void> _startDownload() async {
    final release = _release;
    if (release == null) return;
    setState(() {
      _phase = _UpdatePhase.downloading;
    });
    final cancellation = Completer<void>();
    _downloadCancellation = cancellation;
    try {
      await widget.dataSource.downloadUpdate(
        release,
        onProgress: (progress) {
          if (!mounted) return;
          _animateProgressTo(progress);
        },
        onFilePath: (path) {
          if (!mounted) return;
          setState(() => _downloadedFilePath = path);
        },
        cancelSignal: cancellation.future,
      );
      if (!mounted) return;
      _animateProgressTo(1.0);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _UpdatePhase.error;
        _errorMessage = '$error';
      });
    } finally {
      if (identical(_downloadCancellation, cancellation)) {
        _downloadCancellation = null;
      }
    }
  }

  void _cancelDownload() {
    final cancellation = _downloadCancellation;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
    Navigator.of(context).pop();
  }

  void _animateProgressTo(double target) {
    final safeTarget = finiteUnitInterval(target, fallback: _targetProgress);
    if (safeTarget <= _targetProgress) return;
    _targetProgress = safeTarget;
    if (!openHandTickerMotionEnabled(context)) {
      _settleProgressAnimation();
      setState(() {});
      return;
    }
    final oldValue = _progressAnimation.value;
    _progressAnimation = Tween<double>(begin: oldValue, end: safeTarget)
        .animate(
          CurvedAnimation(
            parent: _progressAnimController,
            curve: Curves.easeOutCubic,
          ),
        );
    _progressAnimController.forward(from: 0);
    setState(() {});
  }

  void _settleProgressAnimation() {
    _progressAnimController.stop();
    _progressAnimation = AlwaysStoppedAnimation<double>(_targetProgress);
  }

  Future<void> _revealDownloadedUpdate() async {
    final path = _downloadedFilePath;
    if (path == null) return;
    final revealed = await revealLocalPathInSystemFileManager(
      path,
      tag: 'app_update_dialog.reveal_download',
    );
    if (!mounted) return;
    if (revealed) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _phase = _UpdatePhase.error;
      _errorMessage = openHandLocalizedText(
        context,
        zh: '无法在文件管理器中显示更新文件。',
        en: 'Could not reveal the update file in the file manager.',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final motionEnabled = openHandTickerMotionEnabled(context);
    return buildOpenHandAlertDialog(
      title: Row(
        children: [
          Icon(Icons.system_update_outlined, color: colorScheme.primary),
          const SizedBox(width: 12),
          Text(l10n.appUpdateDialogTitle),
        ],
      ),
      content: AnimatedSwitcher(
        duration: motionEnabled
            ? _kAppUpdatePhaseSwitchDuration
            : Duration.zero,
        reverseDuration: motionEnabled
            ? _kAppUpdatePhaseSwitchDuration
            : Duration.zero,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.08),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        child: _buildPhaseContent(l10n, theme, colorScheme),
      ),
      actions: _buildActions(l10n),
    );
  }

  Widget _buildPhaseContent(
    AppLocalizations l10n,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return switch (_phase) {
      _UpdatePhase.checking => SizedBox(
        key: const ValueKey('checking'),
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(l10n.appUpdateChecking, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 8),
            Text(
              l10n.appUpdateCurrentVersion(widget.appInfo.displayVersion),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
      _UpdatePhase.available => SizedBox(
        key: const ValueKey('available'),
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.new_releases_outlined,
                    size: 20,
                    color: colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.appUpdateNewVersion(_release!.version),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _release!.releaseName,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (_release!.releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Text(
                    _release!.releaseNotes,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              l10n.appUpdatePublished(_formatDate(_release!.publishedAt)),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.outline,
              ),
            ),
            if (_release!.downloadSize > 0) ...[
              const SizedBox(height: 4),
              Text(
                l10n.appUpdateFileSize(formatByteSize(_release!.downloadSize)),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.outline,
                ),
              ),
            ],
          ],
        ),
      ),
      _UpdatePhase.notAvailable => SizedBox(
        key: const ValueKey('notAvailable'),
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Icon(
              Icons.check_circle_outline_rounded,
              size: 56,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 20),
            Text(
              l10n.appUpdateAlreadyLatestTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.appUpdateAlreadyLatestBody(widget.appInfo.displayVersion),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
      _UpdatePhase.downloading => SizedBox(
        key: const ValueKey('downloading'),
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Text(
              _downloadedFilePath != null
                  ? l10n.appUpdateDownloadComplete
                  : l10n.appUpdateDownloading,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            AnimatedBuilder(
              animation: _progressAnimController,
              builder: (context, _) {
                final value = _progressAnimation.value;
                return Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: value,
                        minHeight: 8,
                        backgroundColor: colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${(value * 100).toStringAsFixed(1)}%',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                );
              },
            ),
            if (_downloadedFilePath != null) ...[
              const SizedBox(height: 12),
              Icon(
                Icons.check_circle_rounded,
                color: colorScheme.primary,
                size: 32,
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
      _UpdatePhase.error => SizedBox(
        key: const ValueKey('error'),
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.appUpdateCheckFailed,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    };
  }

  List<Widget> _buildActions(AppLocalizations l10n) {
    return switch (_phase) {
      _UpdatePhase.checking => [
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(context).pop(),
          label: l10n.commonCancel,
        ),
      ],
      _UpdatePhase.available => [
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(context).pop(),
          label: l10n.appUpdateLater,
        ),
        if (_release!.downloadUrl.isNotEmpty)
          OpenHandDialogActionButton.primary(
            onPressed: _startDownload,
            icon: Icons.download_rounded,
            label: l10n.appUpdateDownload,
          ),
      ],
      _UpdatePhase.notAvailable => [
        OpenHandDialogActionButton.primary(
          onPressed: () => Navigator.of(context).pop(),
          label: l10n.commonOk,
        ),
      ],
      _UpdatePhase.downloading => [
        if (_downloadedFilePath != null)
          OpenHandDialogActionButton.primary(
            onPressed: _revealDownloadedUpdate,
            label: openHandLocalizedText(
              context,
              zh: '在文件夹中显示',
              en: 'Show in folder',
            ),
          ),
        if (_downloadedFilePath == null)
          OpenHandDialogActionButton.secondary(
            onPressed: _cancelDownload,
            label: l10n.commonCancel,
          ),
      ],
      _UpdatePhase.error => [
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(context).pop(),
          label: l10n.commonClose,
        ),
        OpenHandDialogActionButton.primary(
          onPressed: () {
            setState(() => _phase = _UpdatePhase.checking);
            _checkForUpdate();
          },
          label: l10n.commonRetry,
        ),
      ],
    };
  }

  String _formatDate(DateTime date) {
    return formatYearMonthDay(date);
  }
}
