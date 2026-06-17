// 2026-05-13 — 检查更新弹窗，带 Q 弹动画进度条和流畅的状态切换。
import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/model/app_info.dart';
import '../../app/support/app_update_checker.dart';
import '../util/byte_size_format.dart';
import '../util/localized_text.dart';
import 'animated_dialog.dart';
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

  late final AnimationController _progressAnimController;
  late Animation<double> _progressAnimation;
  double _targetProgress = 0;

  @override
  void initState() {
    super.initState();
    _progressAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
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
    _progressAnimController.dispose();
    super.dispose();
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
      );
      if (!mounted) return;
      _animateProgressTo(1.0);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _UpdatePhase.error;
        _errorMessage = '$error';
      });
    }
  }

  void _animateProgressTo(double target) {
    if (target <= _targetProgress) return;
    final oldValue = _progressAnimation.value;
    _targetProgress = target;
    _progressAnimation = Tween<double>(begin: oldValue, end: target).animate(
      CurvedAnimation(
        parent: _progressAnimController,
        curve: Curves.easeOutCubic,
      ),
    );
    _progressAnimController.forward(from: 0);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isZh = openHandIsChineseLocale(context);
    return buildOpenHandAlertDialog(
      title: Row(
        children: [
          Icon(Icons.system_update_outlined, color: colorScheme.primary),
          const SizedBox(width: 12),
          Text(isZh ? '检查更新' : 'Check for Updates'),
        ],
      ),
      content: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
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
        child: _buildPhaseContent(isZh, theme, colorScheme),
      ),
      actions: _buildActions(isZh),
    );
  }

  Widget _buildPhaseContent(
    bool isZh,
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
            Text(
              isZh ? '正在检查更新...' : 'Checking for updates...',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              isZh
                  ? '当前版本: ${widget.appInfo.displayVersion}'
                  : 'Current: ${widget.appInfo.displayVersion}',
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
                      isZh
                          ? '发现新版本: v${_release!.version}'
                          : 'New version: v${_release!.version}',
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
              isZh
                  ? '发布时间: ${_formatDate(_release!.publishedAt)}'
                  : 'Published: ${_formatDate(_release!.publishedAt)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.outline,
              ),
            ),
            if (_release!.downloadSize > 0) ...[
              const SizedBox(height: 4),
              Text(
                isZh
                    ? '文件大小: ${formatByteSize(_release!.downloadSize)}'
                    : 'Size: ${formatByteSize(_release!.downloadSize)}',
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
              isZh ? '已是最新版本' : 'You\'re up to date',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isZh
                  ? 'OpenHand ${widget.appInfo.displayVersion} 已是最新版本。'
                  : 'OpenHand ${widget.appInfo.displayVersion} is the latest version.',
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
                  ? (isZh ? '下载完成' : 'Download Complete')
                  : (isZh ? '正在下载...' : 'Downloading...'),
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
              isZh ? '检查更新失败' : 'Update Check Failed',
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

  List<Widget> _buildActions(bool isZh) {
    return switch (_phase) {
      _UpdatePhase.checking => [
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(context).pop(),
          label: isZh ? '取消' : 'Cancel',
        ),
      ],
      _UpdatePhase.available => [
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(context).pop(),
          label: isZh ? '稍后' : 'Later',
        ),
        if (_release!.downloadUrl.isNotEmpty)
          OpenHandDialogActionButton.primary(
            onPressed: _startDownload,
            icon: Icons.download_rounded,
            label: isZh ? '下载更新' : 'Download',
          ),
      ],
      _UpdatePhase.notAvailable => [
        OpenHandDialogActionButton.primary(
          onPressed: () => Navigator.of(context).pop(),
          label: isZh ? '好的' : 'OK',
        ),
      ],
      _UpdatePhase.downloading => [
        if (_downloadedFilePath != null)
          OpenHandDialogActionButton.primary(
            onPressed: () => Navigator.of(context).pop(),
            label: isZh ? '完成' : 'Done',
          )
        else
          OpenHandDialogActionButton.secondary(
            onPressed: () => Navigator.of(context).pop(),
            label: isZh ? '后台下载' : 'Background',
          ),
      ],
      _UpdatePhase.error => [
        OpenHandDialogActionButton.secondary(
          onPressed: () => Navigator.of(context).pop(),
          label: isZh ? '关闭' : 'Close',
        ),
        OpenHandDialogActionButton.primary(
          onPressed: () {
            setState(() => _phase = _UpdatePhase.checking);
            _checkForUpdate();
          },
          label: isZh ? '重试' : 'Retry',
        ),
      ],
    };
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
