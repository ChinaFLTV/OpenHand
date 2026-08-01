import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/appear_once.dart';
import '../../../shared/ui/feature_page_shell.dart';
import '../../../shared/ui/oh_pill.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/util/localized_text.dart';
import '../model/ai_exposure_models.dart';
import '../services_controller.dart';
import 'ai_exposure_dialogs.dart';
import 'ai_exposure_monitoring_dialogs.dart';
import 'ai_exposure_proxy_dialog.dart';

const double _kServiceCardRadius = 22;
const double _kServiceIconExtent = 64;
const double _kServiceHeaderBreakpoint = 820;

enum _ServiceAction {
  status,
  operations,
  proxy,
  logs,
  newHunt,
  progress,
  results,
  history,
  tools,
  rules,
  customHunt,
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
            error: controller.errorMessage,
            busy: controller.busy,
          ),
        );
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final controller = context.read<ServicesController>();
    final running = snapshot.lifecycle == AiExposureServiceLifecycle.running;
    final toneColor = running ? cs.primary : cs.outline;

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
                  : () async {
                      if (controller.useBundledEngine) {
                        await controller.startService();
                      } else {
                        await showAiExposureSettingsDialog(context);
                      }
                    },
              onAction: (action) => _handleAction(context, action),
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (compact) ...[
                  identity,
                  const SizedBox(height: 16),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: actions,
                  ),
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: identity),
                      const SizedBox(width: 16),
                      Expanded(child: actions),
                    ],
                  ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _ServicePill(
                      icon: running
                          ? Icons.check_circle_outline_rounded
                          : Icons.pause_circle_outline_rounded,
                      label: _lifecycleLabel(context, snapshot.lifecycle),
                      color: toneColor,
                    ),
                    _ServicePill(
                      icon: Icons.workspace_premium_outlined,
                      label: l10n.servicesProprietaryBadge,
                      color: cs.secondary,
                    ),
                    if (snapshot.health != null)
                      _ServicePill(
                        icon: Icons.memory_rounded,
                        label: 'ai_jungler ${snapshot.health!.version}',
                        color: cs.tertiary,
                      ),
                    _ServicePill(
                      icon: Icons.travel_explore_rounded,
                      label: openHandLocalizedText(
                        context,
                        zh: '数据源 ${snapshot.configuredSourceCount}/5',
                        en: 'Sources ${snapshot.configuredSourceCount}/5',
                      ),
                      color: cs.primary,
                    ),
                    _ServicePill(
                      icon: Icons.rule_rounded,
                      label: openHandLocalizedText(
                        context,
                        zh: '规则 ${snapshot.enabledRuleCount}',
                        en: 'Rules ${snapshot.enabledRuleCount}',
                      ),
                      color: cs.secondary,
                    ),
                    _ServicePill(
                      icon: Icons.history_rounded,
                      label: openHandLocalizedText(
                        context,
                        zh: '历史 ${snapshot.historyCount}',
                        en: 'History ${snapshot.historyCount}',
                      ),
                      color: cs.primary,
                    ),
                    _ServicePill(
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
                  const SizedBox(height: 14),
                  _CompactProgress(progress: snapshot.progress!),
                ],
                const SizedBox(height: 14),
                Text(
                  openHandLocalizedText(
                    context,
                    zh: '暴露面发现 · 凭证风险识别 · 产品指纹 · 并发验证 · 加密归档',
                    en: 'Exposure discovery · credential risk detection · fingerprinting · concurrent validation · encrypted archive',
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                if (snapshot.error?.trim().isNotEmpty ?? false) ...[
                  const SizedBox(height: 12),
                  _ServiceError(message: snapshot.error!),
                ],
                const SizedBox(height: 12),
                _AuthorizationNotice(label: l10n.servicesAuthorizationHint),
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
                borderRadius: BorderRadius.circular(18),
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
                  color: running ? Colors.green : cs.outline,
                  size: 18,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
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
            icon: busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(running ? Icons.stop_rounded : Icons.play_arrow_rounded),
          ),
        ),
        _ServiceIconAction(
          icon: Icons.monitor_heart_outlined,
          tooltip: text(zh: '服务状态', en: 'Service status'),
          action: _ServiceAction.status,
          onAction: onAction,
        ),
        _ServiceIconAction(
          icon: Icons.dashboard_customize_outlined,
          tooltip: text(zh: '服务运维', en: 'Service operations'),
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
          tooltip: text(zh: '实时扫描', en: 'Live scan'),
          action: _ServiceAction.progress,
          onAction: onAction,
        ),
        _ServiceIconAction(
          icon: Icons.fact_check_outlined,
          tooltip: text(zh: '结果中心', en: 'Results'),
          action: _ServiceAction.results,
          onAction: onAction,
        ),
        _ServiceIconAction(
          icon: Icons.history_rounded,
          tooltip: text(zh: '扫描历史', en: 'Scan history'),
          action: _ServiceAction.history,
          onAction: onAction,
        ),
        _ServiceIconAction(
          icon: Icons.construction_rounded,
          tooltip: text(zh: '扫描工具管理', en: 'Scanner tools'),
          action: _ServiceAction.tools,
          onAction: onAction,
        ),
        _ServiceIconAction(
          icon: Icons.rule_rounded,
          tooltip: text(zh: '扫描规则管理', en: 'Scan rules'),
          action: _ServiceAction.rules,
          onAction: onAction,
        ),
        _ServiceIconAction(
          icon: Icons.tune_rounded,
          tooltip: text(zh: '自定义狩猎', en: 'Custom hunt'),
          action: _ServiceAction.customHunt,
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

class _ServicePill extends StatelessWidget {
  const _ServicePill({
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: kOpenHandPillBorderRadius,
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 7),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
            child: LinearProgressIndicator(
              value: progress.total <= 0 ? null : progress.fraction,
              minHeight: 7,
              backgroundColor: cs.surfaceContainerHighest,
            ),
          ),
        ),
        const SizedBox(width: 12),
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

class _ServiceError extends StatelessWidget {
  const _ServiceError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline_rounded, size: 18, color: cs.error),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: cs.error),
          ),
        ),
      ],
    );
  }
}

class _AuthorizationNotice extends StatelessWidget {
  const _AuthorizationNotice({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.shield_outlined, size: 17, color: cs.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ),
      ],
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
    case _ServiceAction.status:
      await showAiExposureStatusDialog(context);
    case _ServiceAction.operations:
      await showAiExposureOperationsDialog(context);
    case _ServiceAction.proxy:
      await showAiExposureProxyDialog(context);
    case _ServiceAction.logs:
      await showAiExposureLogMonitorDialog(context);
    case _ServiceAction.newHunt:
      await showAiExposureNewHuntDialog(context);
    case _ServiceAction.progress:
      await showAiExposureProgressDialog(context);
    case _ServiceAction.results:
      await showAiExposureResultsDialog(context);
    case _ServiceAction.history:
      await showAiExposureHistoryDialog(context);
    case _ServiceAction.tools:
      await showAiExposureToolsDialog(context);
    case _ServiceAction.rules:
      await showAiExposureRulesDialog(context);
    case _ServiceAction.customHunt:
      await showAiExposureNewHuntDialog(context, custom: true);
    case _ServiceAction.settings:
      await showAiExposureSettingsDialog(context);
  }
  if (!context.mounted) return;
  final error = context.read<ServicesController>().errorMessage;
  if (error != null && error.trim().isNotEmpty) {
    showOpenHandErrorSnack(context, error, maxLines: 4);
  }
}
