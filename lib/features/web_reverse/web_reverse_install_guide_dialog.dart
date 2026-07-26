import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/support/safe_subprocess.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/util/localized_text.dart';
import 'web_reverse_dialog_utils.dart';

/// 用户没有安装 Chrome 同核浏览器时弹出的引导对话框。
///
/// 文案随系统语言切换：中文（zh*）走 google.cn 镜像，其他走 google.com。
/// 用户也可以直接复制下载链接到自己的浏览器。点"我已安装"会让上层重新探测。
Future<WebReverseInstallGuideDecision?> showWebReverseInstallGuideDialog(
  BuildContext context,
) async {
  return webReverseToolDialogs.show<WebReverseInstallGuideDecision>(
    context: context,
    builder: (ctx) => const _WebReverseInstallGuideDialog(),
  );
}

enum WebReverseInstallGuideDecision { rechecked, cancelled, openedDownloadPage }

class _WebReverseInstallGuideDialog extends StatelessWidget {
  const _WebReverseInstallGuideDialog();

  bool _isZh(BuildContext context) => openHandIsChineseLocale(context);

  String _downloadUrl(BuildContext context) {
    return _isZh(context)
        ? 'https://www.google.cn/chrome/'
        : 'https://www.google.com/chrome/';
  }

  Future<void> _openDownloadUrl(BuildContext context) async {
    final url = _downloadUrl(context);
    if (Platform.isMacOS) {
      // open URL via system 'open'，避免引入额外依赖。
      await runTrackedProcessOrFailed(
        '/usr/bin/open',
        [url],
        timeout: const Duration(seconds: 5),
        tag: 'web_reverse.install_guide_open',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final url = _downloadUrl(context);

    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: 520,
      maxHeight: 640,
      insetPadding: const EdgeInsets.all(36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.travel_explore_rounded,
            title: loc?.webReverseInstallTitle ?? 'Google Chrome required',
            closeTooltip: loc?.webReverseInstallClose ?? 'Close',
            onClose: () => Navigator.of(
              context,
            ).pop(WebReverseInstallGuideDecision.cancelled),
          ),
          Divider(height: 1, color: colorScheme.outlineVariant),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    loc?.webReverseInstallBody ??
                        'The Web Reverse Expert relies on an external Chromium-based browser (Chrome / Edge / Brave / Chromium) driven via CDP. None was detected.',
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.link_rounded,
                          size: 18,
                          color: colorScheme.primary,
                        ),
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
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: () => _openDownloadUrl(context),
                          icon: const Icon(Icons.open_in_new_rounded, size: 16),
                          label: Text(loc?.webReverseInstallOpen ?? 'Open'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    loc?.webReverseInstallHint ??
                        'Install Chrome and retry. If Edge / Brave / Chromium is already installed, click "I have installed, recheck".',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: colorScheme.outlineVariant),
          buildOpenHandDialogActionsBar(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
            actions: [
              OpenHandDialogActionButton.secondary(
                onPressed: () => Navigator.of(
                  context,
                ).pop(WebReverseInstallGuideDecision.cancelled),
                label: loc?.commonCancel ?? 'Cancel',
              ),
              OpenHandDialogActionButton.primary(
                onPressed: () => Navigator.of(
                  context,
                ).pop(WebReverseInstallGuideDecision.rechecked),
                label: loc?.webReverseInstallInstalled ?? 'I Have Installed',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
