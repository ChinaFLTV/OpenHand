import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/openhand_status_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/appear_once.dart';
import '../../../shared/ui/feature_page_shell.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/oh_pill.dart';
import '../../../shared/ui/openhand_reveal_switcher.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/util/localized_text.dart';
import '../model/ai_exposure_models.dart';
import '../services_controller.dart';
import 'ai_exposure_dialogs.dart';
import 'ai_exposure_monitoring_dialogs.dart';
import 'ai_exposure_proxy_dialog.dart';
import 'ai_model_proxy_service_card.dart';
import 'service_dialog_controls.dart';

const double _kServiceCardRadius = 22;
const double _kServiceIconExtent = 64;
const double _kServiceHeaderBreakpoint = 820;

enum _ServiceAction {
  operations,
  proxy,
  logs,
  newHunt,
  scanWorkspace,
  rules,
  settings,
}

class ServicesView extends StatelessWidget {
  const ServicesView({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return FeaturePageShell(
      title: l10n.servicesTitle,
      subtitle: l10n.servicesSubtitle,
      body: ListView(
        key: const ValueKey<String>('services-list'),
        padding: const EdgeInsets.fromLTRB(0, 2, 0, 16),
        children: const <Widget>[
          SettingsAwareAppearOnce(
            child: RepaintBoundary(child: _AiExposureServiceCard()),
          ),
          kOpenHandGap14,
          SettingsAwareAppearOnce(
            child: RepaintBoundary(child: AiModelProxyServiceCard()),
          ),
        ],
      ),
    );
  }
}

class _AiExposureServiceCard extends StatelessWidget {
  const _AiExposureServiceCard();

  @override
  Widget build(BuildContext context) {
    final snapshot = context
        .select<
          ServicesController,
          ({
            AiExposureServiceLifecycle lifecycle,
            AiExposureHealth? health,
            AiExposureProgress? progress,
            int historyCount,
            int resultCount,
            int enabledRuleCount,
            int configuredSourceCount,
            int sourceStatusCount,
            int enabledSourceCount,
            int defaultConcurrency,
            AiExposureValidationMode defaultValidationMode,
            AiExposureForumFetchMode forumFetchMode,
            bool defaultGptAssisted,
            AiExposureProxyRoute proxyRoute,
            int activeProxyCount,
            bool postgresqlEnabled,
            bool redisEnabled,
            String? error,
            bool busy,
          })
        >(
          (controller) => (
            lifecycle: controller.lifecycle,
            health: controller.health,
            progress: controller.progress,
            historyCount: controller.history.length,
            resultCount: controller.results.length,
            enabledRuleCount: controller.rules
                .where((rule) => rule.enabled)
                .length,
            configuredSourceCount: controller.sourceStatus.values
                .where((configured) => configured)
                .length,
            sourceStatusCount: controller.discoverySourceCount,
            enabledSourceCount: controller.enabledSources.length,
            defaultConcurrency: controller.defaultConcurrency,
            defaultValidationMode: controller.defaultValidationMode,
            forumFetchMode: controller.forumFetchMode,
            defaultGptAssisted: controller.defaultGptAssisted,
            proxyRoute: controller.proxyRoute,
            activeProxyCount: controller.proxyConfiguration.endpoints
                .where((endpoint) => endpoint.enabled)
                .length,
            postgresqlEnabled: controller.postgresqlEnabled,
            redisEnabled: controller.redisEnabled,
            error: controller.errorMessage,
            busy: controller.busy,
          ),
        );
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final text = openHandTextResolver(context);
    final controller = context.read<ServicesController>();
    final running = snapshot.lifecycle == AiExposureServiceLifecycle.running;
    final toneColor = running ? cs.primary : cs.outline;
    final activeValidation =
        snapshot.defaultValidationMode ==
        AiExposureValidationMode.authorizedActive;
    final capabilityFacts = <({IconData icon, String label, Color color})>[
      (
        icon: Icons.travel_explore_rounded,
        label: text(
          zh: '启用来源 ${snapshot.enabledSourceCount}',
          en: 'Sources ${snapshot.enabledSourceCount}',
        ),
        color: cs.primary,
      ),
      (
        icon: activeValidation
            ? Icons.verified_user_rounded
            : Icons.shield_outlined,
        label: activeValidation
            ? text(zh: '授权主动验证', en: 'Authorized active validation')
            : text(zh: '被动验证', en: 'Passive validation'),
        color: activeValidation ? OpenHandStatusColors.warning : cs.secondary,
      ),
      (
        icon: Icons.bolt_rounded,
        label: text(
          zh: '默认并发 ${snapshot.defaultConcurrency}',
          en: 'Concurrency ${snapshot.defaultConcurrency}',
        ),
        color: cs.tertiary,
      ),
      switch (snapshot.proxyRoute) {
        AiExposureProxyRoute.pool => (
          icon: Icons.lan_rounded,
          label: text(
            zh: '代理节点 ${snapshot.activeProxyCount}',
            en: 'Proxies ${snapshot.activeProxyCount}',
          ),
          color: cs.tertiary,
        ),
        AiExposureProxyRoute.system => (
          icon: Icons.public_rounded,
          label: text(zh: '系统代理', en: 'System proxy'),
          color: cs.secondary,
        ),
        AiExposureProxyRoute.direct => (
          icon: Icons.link_rounded,
          label: text(zh: '网络直连', en: 'Direct connection'),
          color: cs.onSurfaceVariant,
        ),
      },
      (
        icon: Icons.forum_rounded,
        label: switch (snapshot.forumFetchMode) {
          AiExposureForumFetchMode.jinaFallback => text(
            zh: '论坛智能降级',
            en: 'Forum fallback',
          ),
          AiExposureForumFetchMode.playwright => text(
            zh: '论坛浏览器直读',
            en: 'Forum browser',
          ),
          AiExposureForumFetchMode.cdp => 'Chrome CDP',
        },
        color: cs.primary,
      ),
      if (snapshot.defaultGptAssisted)
        (
          icon: Icons.auto_awesome_rounded,
          label: text(zh: 'GPT 辅助', en: 'GPT assisted'),
          color: OpenHandStatusColors.info,
        ),
      if (snapshot.postgresqlEnabled)
        (icon: Icons.storage_rounded, label: 'PostgreSQL', color: cs.tertiary),
      if (snapshot.redisEnabled)
        (icon: Icons.memory_rounded, label: 'Redis', color: cs.secondary),
    ];

    return Card(
      key: const ValueKey<String>('ai-infrastructure-exposure-service-card'),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_kServiceCardRadius),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < _kServiceHeaderBreakpoint;
            final identity = _ServiceIdentity(
              title: l10n.servicesAiInfrastructureExposureScanTitle,
              description: l10n.servicesAiInfrastructureExposureScanDescription,
              running: running,
            );
            final actions = _ServiceActions(
              lifecycle: snapshot.lifecycle,
              busy: snapshot.busy,
              onToggle: running
                  ? controller.stopService
                  : () =>
                        startOrConfigureAiExposureService(context, controller),
              onAction: (action) => _handleAction(context, action),
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (compact) ...[
                  identity,
                  kOpenHandGap16,
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: actions,
                  ),
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: identity),
                      kOpenHandHGap16,
                      Expanded(child: actions),
                    ],
                  ),
                kOpenHandGap16,
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OpenHandStatusPill(
                      icon: running
                          ? Icons.check_circle_outline_rounded
                          : Icons.pause_circle_outline_rounded,
                      label: _lifecycleLabel(context, snapshot.lifecycle),
                      color: toneColor,
                    ),
                    OpenHandStatusPill(
                      icon: Icons.workspace_premium_outlined,
                      label: l10n.servicesProprietaryBadge,
                      color: cs.secondary,
                    ),
                    if (snapshot.health != null)
                      OpenHandStatusPill(
                        icon: Icons.memory_rounded,
                        label: 'ai_jungler ${snapshot.health!.version}',
                        color: cs.tertiary,
                      ),
                    OpenHandStatusPill(
                      icon: Icons.travel_explore_rounded,
                      label: openHandLocalizedText(
                        context,
                        zh: '数据源 ${snapshot.configuredSourceCount}/${snapshot.sourceStatusCount}',
                        en: 'Sources ${snapshot.configuredSourceCount}/${snapshot.sourceStatusCount}',
                      ),
                      color: cs.primary,
                    ),
                    OpenHandStatusPill(
                      icon: Icons.rule_rounded,
                      label: openHandLocalizedText(
                        context,
                        zh: '规则 ${snapshot.enabledRuleCount}',
                        en: 'Rules ${snapshot.enabledRuleCount}',
                      ),
                      color: cs.secondary,
                    ),
                    OpenHandStatusPill(
                      icon: Icons.history_rounded,
                      label: openHandLocalizedText(
                        context,
                        zh: '历史 ${snapshot.historyCount}',
                        en: 'History ${snapshot.historyCount}',
                      ),
                      color: cs.primary,
                    ),
                    OpenHandStatusPill(
                      icon: Icons.fact_check_outlined,
                      label: openHandLocalizedText(
                        context,
                        zh: '结果 ${snapshot.resultCount}',
                        en: 'Results ${snapshot.resultCount}',
                      ),
                      color: cs.tertiary,
                    ),
                  ],
                ),
                if (snapshot.progress != null) ...[
                  kOpenHandGap14,
                  _CompactProgress(progress: snapshot.progress!),
                ],
                kOpenHandGap14,
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final fact in capabilityFacts)
                      _CapabilityChip(
                        icon: fact.icon,
                        label: fact.label,
                        color: fact.color,
                      ),
                  ],
                ),
                OpenHandVerticalRevealSwitcher(
                  duration: kOpenHandMotion220,
                  child: (snapshot.error?.trim().isNotEmpty ?? false)
                      ? Padding(
                          key: const ValueKey<String>('service-error'),
                          padding: const EdgeInsets.only(top: 12),
                          child: _ServiceError(
                            message: snapshot.error!,
                            onTap: () =>
                                showAiExposureScanWorkspaceDialog(context),
                          ),
                        )
                      : null,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ServiceIdentity extends StatelessWidget {
  const _ServiceIdentity({
    required this.title,
    required this.description,
    required this.running,
  });

  final String title;
  final String description;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: _kServiceIconExtent,
              height: _kServiceIconExtent,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(kOpenHandRadius18),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.radar_rounded,
                size: 31,
                color: cs.onPrimaryContainer,
              ),
            ),
            Positioned(
              right: -3,
              bottom: -3,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: cs.surface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.circle,
                  color: running ? OpenHandStatusColors.success : cs.outline,
                  size: 18,
                ),
              ),
            ),
          ],
        ),
        kOpenHandHGap16,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.headlineSmall),
              kOpenHandGap8,
              Text(
                description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ServiceActions extends StatelessWidget {
  const _ServiceActions({
    required this.lifecycle,
    required this.busy,
    required this.onToggle,
    required this.onAction,
  });

  final AiExposureServiceLifecycle lifecycle;
  final bool busy;
  final Future<void> Function() onToggle;
  final ValueChanged<_ServiceAction> onAction;

  @override
  Widget build(BuildContext context) {
    final running = lifecycle == AiExposureServiceLifecycle.running;
    final text = openHandTextResolver(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        Tooltip(
          message: running
              ? text(zh: '停止服务', en: 'Stop service')
              : text(zh: '启动服务', en: 'Start service'),
          child: IconButton.filledTonal(
            onPressed: busy ? null : onToggle,
            style: running
                ? OpenHandStatusColors.runningStopButtonStyle()
                : null,
            icon: busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(running ? Icons.stop_rounded : Icons.play_arrow_rounded),
          ),
        ),
        _ServiceIconAction(
          icon: Icons.dashboard_customize_outlined,
          tooltip: text(zh: '服务状态与运维', en: 'Service status and operations'),
          action: _ServiceAction.operations,
          onAction: onAction,
        ),
        _ServiceIconAction(
          icon: Icons.lan_outlined,
          tooltip: text(zh: '网络代理', en: 'Network proxy'),
          action: _ServiceAction.proxy,
          onAction: onAction,
        ),
        _ServiceIconAction(
          icon: Icons.manage_search_rounded,
          tooltip: text(zh: '日志监控', en: 'Log monitor'),
          action: _ServiceAction.logs,
          onAction: onAction,
        ),
        _ServiceIconAction(
          icon: Icons.add_rounded,
          tooltip: text(zh: '新建狩猎', en: 'New hunt'),
          action: _ServiceAction.newHunt,
          onAction: onAction,
        ),
        _ServiceIconAction(
          icon: Icons.track_changes_rounded,
          tooltip: text(zh: '扫描工作台', en: 'Scan workspace'),
          action: _ServiceAction.scanWorkspace,
          onAction: onAction,
        ),
        _ServiceIconAction(
          icon: Icons.rule_rounded,
          tooltip: text(zh: '扫描规则管理', en: 'Scan rules'),
          action: _ServiceAction.rules,
          onAction: onAction,
        ),
        _ServiceIconAction(
          icon: Icons.settings_outlined,
          tooltip: text(zh: '服务设置', en: 'Service settings'),
          action: _ServiceAction.settings,
          onAction: onAction,
        ),
      ],
    );
  }
}

class _ServiceIconAction extends StatelessWidget {
  const _ServiceIconAction({
    required this.icon,
    required this.tooltip,
    required this.action,
    required this.onAction,
  });

  final IconData icon;
  final String tooltip;
  final _ServiceAction action;
  final ValueChanged<_ServiceAction> onAction;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: IconButton.filledTonal(
      onPressed: () => onAction(action),
      icon: Icon(icon),
    ),
  );
}

class _CompactProgress extends StatelessWidget {
  const _CompactProgress({required this.progress});
  final AiExposureProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: kOpenHandPillBorderRadius,
            child: ServiceAnimatedProgressBar(
              value: progress.displayFraction,
              minHeight: 7,
              backgroundColor: cs.surfaceContainerHighest,
            ),
          ),
        ),
        kOpenHandHGap12,
        Text(
          '${progress.processed}/${progress.total}',
          style: theme.textTheme.labelMedium?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// 服务卡片的配置事实芯片：以图标 + 主题微色调呈现次级配置信息，
/// 与上方状态度量胶囊形成清晰的层次，避免把配置折叠进省略号文本。
class _CapabilityChip extends StatelessWidget {
  const _CapabilityChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(kOpenHandRadius10),
        border: Border.all(color: color.withValues(alpha: 0.26)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          kOpenHandHGap6,
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceError extends StatelessWidget {
  const _ServiceError({required this.message, required this.onTap});
  final String message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Tooltip(
      message: openHandLocalizedText(
        context,
        zh: '打开扫描工作台查看完整日志',
        en: 'Open the scan workspace for complete logs',
      ),
      child: Material(
        color: cs.errorContainer.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(kOpenHandRadius10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(kOpenHandRadius10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline_rounded, size: 19, color: cs.error),
                kOpenHandHGap8,
                Expanded(
                  child: Text(
                    message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onErrorContainer,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                kOpenHandHGap6,
                Icon(Icons.chevron_right_rounded, size: 20, color: cs.error),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _lifecycleLabel(
  BuildContext context,
  AiExposureServiceLifecycle lifecycle,
) => switch (lifecycle) {
  AiExposureServiceLifecycle.stopped => openHandLocalizedText(
    context,
    zh: '已停止',
    en: 'Stopped',
  ),
  AiExposureServiceLifecycle.starting => openHandLocalizedText(
    context,
    zh: '启动中',
    en: 'Starting',
  ),
  AiExposureServiceLifecycle.running => openHandLocalizedText(
    context,
    zh: '运行中',
    en: 'Running',
  ),
  AiExposureServiceLifecycle.stopping => openHandLocalizedText(
    context,
    zh: '停止中',
    en: 'Stopping',
  ),
  AiExposureServiceLifecycle.error => openHandLocalizedText(
    context,
    zh: '异常',
    en: 'Error',
  ),
};

Future<void> _handleAction(BuildContext context, _ServiceAction action) async {
  switch (action) {
    case _ServiceAction.operations:
      await showAiExposureOperationsDialog(context);
    case _ServiceAction.proxy:
      await showAiExposureProxyDialog(context);
    case _ServiceAction.logs:
      await showAiExposureLogMonitorDialog(context);
    case _ServiceAction.newHunt:
      await showAiExposureNewHuntDialog(context);
    case _ServiceAction.scanWorkspace:
      await showAiExposureScanWorkspaceDialog(context);
    case _ServiceAction.rules:
      await showAiExposureRulesDialog(context);
    case _ServiceAction.settings:
      await showAiExposureSettingsDialog(context);
  }
}
