import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// 消息网关 顶级面板（与 Crons / Hooks / Instructions / Settings 同级）。
///
/// 当前为占位实现：展示标题、描述和「即将推出」卡片，后续在该面板内
/// 接入第三方消息平台（Discord / Slack / 飞书 / 钉钉 / Telegram 等）的
/// 路由、转换与节流配置。
class MessageGatewayView extends StatelessWidget {
  const MessageGatewayView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.settingsMessageGatewayTitle,
          style: theme.textTheme.displaySmall,
        ),
        const SizedBox(height: 8),
        Text(
          l10n.settingsMessageGatewayDescription,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.hub_outlined,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            l10n.settingsMessageGatewayComingSoon,
                            style: theme.textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        l10n.settingsMessageGatewayComingSoonSubtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
