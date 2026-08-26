import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/openhand_status_colors.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/oh_pill.dart';
import '../../../shared/ui/openhand_reveal_switcher.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/util/localized_text.dart';
import '../ai_model_proxy_controller.dart';
import '../model/ai_exposure_models.dart';
import '../model/ai_model_proxy_models.dart';
import '../services_controller.dart';
import 'ai_exposure_proxy_dialog.dart';
import 'ai_model_proxy_dialogs.dart';
import 'ai_model_proxy_operations_dialog.dart';
import 'service_card_controls.dart';

class AiModelProxyServiceCard extends StatelessWidget {
  const AiModelProxyServiceCard({super.key});

  @override
  Widget build(BuildContext context) {
    final text = openHandTextResolver(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final controller = context.watch<AiModelProxyController>();
    final proxyState = context
        .select<
          ServicesController,
          ({bool enabled, AiExposureProxyMode mode, int activeCount})
        >((service) {
          final proxy = service.proxyConfiguration;
          return (
            enabled: proxy.enabled,
            mode: proxy.mode,
            activeCount: proxy.activeEndpoints.length,
          );
        });
    final settings = controller.settings;
    final running = controller.lifecycle == AiModelProxyLifecycle.running;
    final enabledRouteCount = settings.routes
        .where((route) => route.enabled)
        .length;
    final enabledProviderCount = settings.routes
        .where((route) => route.enabled)
        .expand((route) => route.backends)
        .map((backend) => backend.providerId)
        .toSet()
        .length;
    final statusColor = running ? OpenHandStatusColors.success : colors.outline;
    final subtitle = text(
      zh: '统一暴露模型接口，按所选策略调度多个云厂商后备模型。',
      en: 'Expose one model API and route requests by the selected backend strategy.',
    );
    return Card(
      key: const ValueKey<String>('ai-model-proxy-service-card'),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 820;
                final identity = ServiceCardIdentity(
                  icon: Icons.hub_rounded,
                  title: text(zh: 'AI 模型服务中转站', en: 'AI model service proxy'),
                  description: subtitle,
                  running: running,
                );
                final actions = _ProxyActions(
                  running: running,
                  busy: controller.busy,
                  onToggle: controller.toggle,
                  onProviders: () => showAiModelProxyProvidersDialog(context),
                  onNetworkProxy: () => showAiExposureProxyDialog(context),
                  onUsage: () => showAiModelProxyUsageDialog(context),
                  onOperations: () => showAiModelProxyOperationsDialog(context),
                  onSettings: () => showAiModelProxySettingsDialog(context),
                );
                return compact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          identity,
                          kOpenHandGap14,
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: actions,
                          ),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: identity),
                          kOpenHandHGap16,
                          actions,
                        ],
                      );
              },
            ),
            kOpenHandGap14,
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OpenHandStatusPill(
                  icon: running
                      ? Icons.check_circle_outline_rounded
                      : Icons.pause_circle_outline_rounded,
                  label: running
                      ? text(zh: '运行中', en: 'Running')
                      : text(zh: '已停止', en: 'Stopped'),
                  color: statusColor,
                ),
                OpenHandStatusPill(
                  icon: Icons.hub_outlined,
                  label: text(
                    zh: '提供商 $enabledProviderCount',
                    en: '$enabledProviderCount providers',
                  ),
                  color: colors.secondary,
                ),
                OpenHandStatusPill(
                  icon: Icons.api_rounded,
                  label: text(
                    zh: '已启用暴露模型 $enabledRouteCount',
                    en: '$enabledRouteCount enabled exposed models',
                  ),
                  color: colors.primary,
                ),
                OpenHandStatusPill(
                  icon: Icons.speed_rounded,
                  label:
                      '${aiModelProxyLimitScopeLabel(settings.limitScope, text)} · ${settings.limitMode.label} ${settings.limitThreshold}',
                  color: colors.tertiary,
                ),
                OpenHandStatusPill(
                  icon:
                      proxyState.enabled &&
                          proxyState.mode == AiExposureProxyMode.pool
                      ? Icons.lan_rounded
                      : proxyState.enabled
                      ? Icons.public_rounded
                      : Icons.link_rounded,
                  label: !proxyState.enabled
                      ? text(zh: '网络直连', en: 'Direct connection')
                      : proxyState.mode == AiExposureProxyMode.system
                      ? text(zh: '系统代理', en: 'System proxy')
                      : text(
                          zh: '代理节点 ${proxyState.activeCount}',
                          en: 'Proxies ${proxyState.activeCount}',
                        ),
                  color: !proxyState.enabled
                      ? colors.onSurfaceVariant
                      : proxyState.mode == AiExposureProxyMode.system
                      ? colors.secondary
                      : colors.tertiary,
                ),
              ],
            ),
            OpenHandVerticalRevealSwitcher(
              duration: kOpenHandMotion220,
              child: controller.errorMessage == null
                  ? null
                  : Padding(
                      key: const ValueKey<String>('ai-model-proxy-error'),
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        controller.errorMessage!,
                        style: TextStyle(color: colors.error),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProxyActions extends StatelessWidget {
  const _ProxyActions({
    required this.running,
    required this.busy,
    required this.onToggle,
    required this.onProviders,
    required this.onNetworkProxy,
    required this.onUsage,
    required this.onOperations,
    required this.onSettings,
  });
  final bool running;
  final bool busy;
  final Future<void> Function() onToggle;
  final VoidCallback onProviders;
  final VoidCallback onNetworkProxy;
  final VoidCallback onUsage;
  final VoidCallback onOperations;
  final VoidCallback onSettings;
  @override
  Widget build(BuildContext context) {
    final text = openHandTextResolver(context);
    return ServiceCardActions(
      running: running,
      busy: busy,
      onToggle: onToggle,
      actions: [
        ServiceCardIconAction(
          icon: Icons.monitor_heart_outlined,
          tooltip: text(zh: '服务运维', en: 'Service operations'),
          onPressed: onOperations,
        ),
        ServiceCardIconAction(
          icon: Icons.hub_outlined,
          tooltip: text(zh: 'AI 模型提供商', en: 'AI model providers'),
          onPressed: onProviders,
        ),
        ServiceCardIconAction(
          icon: Icons.lan_outlined,
          tooltip: text(zh: '网络代理', en: 'Network proxy'),
          onPressed: onNetworkProxy,
        ),
        ServiceCardIconAction(
          icon: Icons.query_stats_rounded,
          tooltip: text(zh: '使用统计', en: 'Usage analytics'),
          onPressed: onUsage,
        ),
        ServiceCardIconAction(
          icon: Icons.settings_outlined,
          tooltip: text(zh: '服务设置', en: 'Service settings'),
          onPressed: onSettings,
        ),
      ],
    );
  }
}
