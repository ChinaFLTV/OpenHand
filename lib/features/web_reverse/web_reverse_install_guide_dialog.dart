import 'dart:io';

import 'package:flutter/material.dart';

import '../../shared/ui/animated_dialog.dart';

/// 用户没有安装 Chrome 同核浏览器时弹出的引导对话框。
///
/// 文案随系统语言切换：中文（zh*）走 google.cn 镜像，其他走 google.com。
/// 用户也可以直接复制下载链接到自己的浏览器。点"我已安装"会让上层重新探测。
Future<WebReverseInstallGuideDecision?> showWebReverseInstallGuideDialog(
  BuildContext context,
) async {
  return showAnimatedDialog<WebReverseInstallGuideDecision>(
    context: context,
    builder: (ctx) => const _WebReverseInstallGuideDialog(),
  );
}

enum WebReverseInstallGuideDecision {
  rechecked,
  cancelled,
  openedDownloadPage,
}

class _WebReverseInstallGuideDialog extends StatelessWidget {
  const _WebReverseInstallGuideDialog();

  bool _isZh(BuildContext context) =>
      Localizations.localeOf(context).languageCode.startsWith('zh');

  String _downloadUrl(BuildContext context) {
    return _isZh(context)
        ? 'https://www.google.cn/chrome/'
        : 'https://www.google.com/chrome/';
  }

  Future<void> _openDownloadUrl(BuildContext context) async {
    final url = _downloadUrl(context);
    if (Platform.isMacOS) {
      // open URL via system 'open'，避免引入额外依赖。
      await Process.run('/usr/bin/open', [url]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isZh = _isZh(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final url = _downloadUrl(context);

    return Dialog(
      backgroundColor: colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(36),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.travel_explore_rounded,
                      color: colorScheme.onPrimaryContainer,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isZh ? '需要 Google Chrome（或同核浏览器）' : 'Google Chrome required',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                isZh
                    ? 'Web 逆向专家依赖外部 Chrome / Edge / Brave / Chromium 等同核浏览器，'
                          '通过 CDP（Chrome DevTools Protocol）通道驱动调试。'
                          '检测到当前系统没有可用的同核浏览器。'
                    : 'The Web Reverse Expert relies on an external Chromium-based browser '
                          '(Chrome / Edge / Brave / Chromium) driven via CDP. None was detected.',
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Row(
                  children: [
                    Icon(Icons.link_rounded, size: 18, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SelectableText(
                        url,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isZh
                    ? '建议安装 Chrome 正式版后重试。如已安装 Edge / Brave / Chromium，'
                          '点击"我已安装，重新检测"。'
                    : 'Install Chrome and retry. If Edge / Brave / Chromium is already installed, '
                          'click "I have installed, recheck".',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(
                      WebReverseInstallGuideDecision.cancelled,
                    ),
                    child: Text(isZh ? '取消' : 'Cancel'),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await _openDownloadUrl(context);
                      if (context.mounted) {
                        Navigator.of(context).pop(
                          WebReverseInstallGuideDecision.openedDownloadPage,
                        );
                      }
                    },
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(isZh ? '打开下载页' : 'Open download'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(
                      WebReverseInstallGuideDecision.rechecked,
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(isZh ? '我已安装，重新检测' : 'I have installed, recheck'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
