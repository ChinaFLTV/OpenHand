import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/model/dialog_animation_settings.dart';
import '../../../app/support/openhand_scroll_physics.dart';
import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../../../app/theme/openhand_status_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/animated_menu.dart';
import '../../../shared/ui/auto_follow_scroll_guard.dart';
import '../../../shared/ui/feature_page_shell.dart';
import '../../../shared/ui/feature_state_card.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_safe_scrollbar.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/localized_text.dart';
import '../../../shared/util/rolling_hash.dart';
import '../../../shared/util/text_fingerprint.dart';
import '../../../shared/util/timer_safety.dart';
import '../message_gateway_controller.dart';
import '../model/web_message_platform_config.dart';
import '../service/web_message_platform_service.dart';
import 'message_gateway_dialog_utils.dart';

String _gatewayEmptyMeansAllLabel(BuildContext context, String label) {
  final suffix = openHandLocalizedText(
    context,
    zh: '空=全部',
    zhHant: '空=全部',
    en: 'empty = all',
    fr: 'vide = tout',
    de: 'leer = alle',
    ja: '空欄 = すべて',
  );
  return '$label（$suffix）';
}

String _gatewayListSeparator(BuildContext context) {
  final languageCode = Localizations.localeOf(
    context,
  ).languageCode.toLowerCase();
  return languageCode == 'zh' || languageCode == 'ja' ? '、' : ', ';
}

String _gatewayUnavailable(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '不可用',
    zhHant: '不可用',
    en: 'Unavailable',
    fr: 'Indisponible',
    de: 'Nicht verfügbar',
    ja: '利用不可',
  );
}

String _gatewayScopeAll(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '全部条目',
    zhHant: '全部項目',
    en: 'All items',
    fr: 'Tous les éléments',
    de: 'Alle Einträge',
    ja: 'すべての項目',
  );
}

String _gatewaySelectedCount(BuildContext context, int selected, int total) {
  return openHandLocalizedText(
    context,
    zh: '已选 $selected/$total',
    zhHant: '已選 $selected/$total',
    en: 'Selected $selected/$total',
    fr: '$selected/$total sélectionnés',
    de: '$selected/$total ausgewählt',
    ja: '$selected/$total 選択済み',
  );
}

class MessageGatewayView extends StatefulWidget {
  const MessageGatewayView({super.key});

  @override
  State<MessageGatewayView> createState() => _MessageGatewayViewState();
}

class _MessageGatewayViewState extends State<MessageGatewayView> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    context.read<MessageGatewayController>().updateTheme(Theme.of(context));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controller = context.watch<MessageGatewayController>();

    return FeaturePageShell(
      title: l10n.settingsMessageGatewayTitle,
      subtitle: l10n.settingsMessageGatewayDescription,
      actions: const SizedBox.shrink(),
      successSignal: controller.saveSuccessSignal,
      body: _buildBody(context, controller),
      headerSpacing: 16,
    );
  }

  Widget _buildBody(BuildContext context, MessageGatewayController controller) {
    if (controller.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.errorMessage != null) {
      return FeatureStateCard.centered(
        icon: Icons.error_outline_rounded,
        tone: FeatureStateTone.error,
        title: openHandLocalizedText(
          context,
          zh: '消息网关加载失败',
          zhHant: '訊息閘道載入失敗',
          en: 'Message gateway failed to load',
          fr: 'Échec du chargement de la passerelle de messages',
          de: 'Nachrichten-Gateway konnte nicht geladen werden',
          ja: 'メッセージゲートウェイの読み込みに失敗しました',
        ),
        body: controller.errorMessage!,
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 16),
      children: [_WebPlatformServiceCard(controller: controller)],
    );
  }
}

class _WebPlatformServiceCard extends StatelessWidget {
  const _WebPlatformServiceCard({required this.controller});

  final MessageGatewayController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = controller.config;
    final runtime = controller.runtimeSnapshot();
    final isRunning = controller.isRunning;
    final boundPort = Uri.tryParse(runtime.boundUrl)?.port;
    final usingFallbackPort =
        isRunning && boundPort != null && boundPort != config.listenPort;
    final stateColor = switch (controller.runtimeState) {
      WebGatewayRuntimeState.running => const Color(0xFF16A34A),
      WebGatewayRuntimeState.crashed => theme.colorScheme.error,
      WebGatewayRuntimeState.starting ||
      WebGatewayRuntimeState.stopping => OpenHandStatusColors.warning,
      WebGatewayRuntimeState.stopped => theme.colorScheme.onSurfaceVariant,
    };

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 760;
                final title = Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 状态点采用与 MCP 服务同款布局：
                    // 套在图标 Stack 里，用 Positioned(right:-2,bottom:-2) 顶出于右下角，
                    // 带与 surface 同色的 3px 描边 + 软阴影，提供一致的“状态徽标”观感。
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Icon(
                            Icons.language_rounded,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: _StatusDot(color: stateColor),
                        ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 状态点已上移到图标右下角，标题行只留应用名。
                          Text(
                            webMessagePlatformBuiltinName,
                            style: theme.textTheme.titleLarge,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            config.description,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
                final actions = Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    _FeatureIconButton(
                      tooltip: config.loggingEnabled
                          ? openHandLocalizedText(
                              context,
                              zh: '查看 Web 服务日志',
                              zhHant: '查看 Web 服務日誌',
                              en: 'View web service logs',
                              fr: 'Voir les journaux du service web',
                              de: 'Webdienste-Protokolle anzeigen',
                              ja: 'Webサービスログを表示',
                            )
                          : openHandLocalizedText(
                              context,
                              zh: '开启日志后可查看日志',
                              zhHant: '開啟日誌後可查看日誌',
                              en: 'Enable logging to view logs',
                              fr: 'Activez les journaux pour les consulter',
                              de: 'Aktivieren Sie Protokolle zum Anzeigen',
                              ja: 'ログを有効にすると表示できます',
                            ),
                      enabled: config.loggingEnabled,
                      icon: Icons.terminal_rounded,
                      onPressed: () => _showLogs(context, controller),
                    ),
                    _FeatureIconButton(
                      tooltip: isRunning
                          ? openHandLocalizedText(
                              context,
                              zh: '端口连通性测试',
                              zhHant: '連接埠連通性測試',
                              en: 'Port connectivity test',
                              fr: 'Test de connectivité du port',
                              de: 'Port-Konnektivitätstest',
                              ja: 'ポート接続テスト',
                            )
                          : openHandLocalizedText(
                              context,
                              zh: '服务运行后可测试端口',
                              zhHant: '服務執行後可測試連接埠',
                              en: 'Start the service to test ports',
                              fr: 'Démarrez le service pour tester les ports',
                              de: 'Starten Sie den Dienst, um Ports zu testen',
                              ja: 'サービス起動後にポートをテストできます',
                            ),
                      enabled: isRunning,
                      icon: Icons.network_check_rounded,
                      onPressed: () =>
                          _showConnectivityTest(context, controller),
                    ),
                    _FeatureIconButton(
                      tooltip: config.healthCheck.enabled
                          ? openHandLocalizedText(
                              context,
                              zh: '健康检测',
                              zhHant: '健康檢測',
                              en: 'Health check',
                              fr: 'Contrôle de santé',
                              de: 'Integritätsprüfung',
                              ja: 'ヘルスチェック',
                            )
                          : openHandLocalizedText(
                              context,
                              zh: '开启健康检查后可使用',
                              zhHant: '開啟健康檢查後可使用',
                              en: 'Enable health checks to use this',
                              fr: 'Activez les contrôles de santé pour utiliser ceci',
                              de: 'Aktivieren Sie Integritätsprüfungen zur Nutzung',
                              ja: 'ヘルスチェックを有効にすると使用できます',
                            ),
                      enabled: config.healthCheck.enabled,
                      icon: Icons.monitor_heart_outlined,
                      onPressed: () => _runHealth(context, controller),
                    ),
                    _FeatureIconButton(
                      tooltip: config.opsEnabled
                          ? openHandLocalizedText(
                              context,
                              zh: '运维面板',
                              zhHant: '維運面板',
                              en: 'Operations panel',
                              fr: 'Panneau opérations',
                              de: 'Betriebsbereich',
                              ja: '運用パネル',
                            )
                          : openHandLocalizedText(
                              context,
                              zh: '开启运维后可查看',
                              zhHant: '開啟維運後可查看',
                              en: 'Enable operations to view this',
                              fr: 'Activez les opérations pour voir ceci',
                              de: 'Aktivieren Sie Betrieb zur Anzeige',
                              ja: '運用機能を有効にすると表示できます',
                            ),
                      enabled: config.opsEnabled,
                      icon: Icons.speed_rounded,
                      onPressed: () => _showOps(context, controller),
                    ),
                    IconButton.filledTonal(
                      tooltip: openHandLocalizedText(
                        context,
                        zh: '编辑配置',
                        zhHant: '編輯設定',
                        en: 'Edit configuration',
                        fr: 'Modifier la configuration',
                        de: 'Konfiguration bearbeiten',
                        ja: '設定を編集',
                      ),
                      onPressed: () => _showEditor(context, controller),
                      icon: const Icon(Icons.edit_rounded),
                    ),
                    IconButton.filled(
                      tooltip: isRunning
                          ? openHandLocalizedText(
                              context,
                              zh: '停止',
                              zhHant: '停止',
                              en: 'Stop',
                              fr: 'Arrêter',
                              de: 'Stoppen',
                              ja: '停止',
                            )
                          : openHandLocalizedText(
                              context,
                              zh: '启动',
                              zhHant: '啟動',
                              en: 'Start',
                              fr: 'Démarrer',
                              de: 'Starten',
                              ja: '起動',
                            ),
                      onPressed: controller.isOperating
                          ? null
                          : () => isRunning
                                ? controller.stopService()
                                : controller.startService(),
                      icon: Icon(
                        isRunning
                            ? Icons.stop_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    ),
                  ],
                );
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [title, const SizedBox(height: 14), actions],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 18),
                    Flexible(
                      child: Align(
                        alignment: Alignment.topRight,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 620),
                          child: actions,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(
                  icon: Icons.power_settings_new_rounded,
                  label: config.enabled
                      ? openHandLocalizedText(
                          context,
                          zh: '已启用',
                          zhHant: '已啟用',
                          en: 'Enabled',
                          fr: 'Activé',
                          de: 'Aktiviert',
                          ja: '有効',
                        )
                      : openHandLocalizedText(
                          context,
                          zh: '未启用',
                          zhHant: '未啟用',
                          en: 'Disabled',
                          fr: 'Désactivé',
                          de: 'Deaktiviert',
                          ja: '無効',
                        ),
                ),
                _InfoChip(
                  icon: Icons.rocket_launch_outlined,
                  label: config.autoStartOnLaunch
                      ? openHandLocalizedText(
                          context,
                          zh: '冷启动自启',
                          zhHant: '冷啟動自啟',
                          en: 'Auto-start on launch',
                          fr: 'Démarrage auto au lancement',
                          de: 'Autostart beim Start',
                          ja: '起動時に自動開始',
                        )
                      : openHandLocalizedText(
                          context,
                          zh: '冷启动不干预',
                          zhHant: '冷啟動不干預',
                          en: 'No launch auto-start',
                          fr: 'Pas de démarrage auto',
                          de: 'Kein Autostart',
                          ja: '起動時は自動開始しない',
                        ),
                ),
                _InfoChip(
                  icon: Icons.sync_rounded,
                  label: config.autoReloadOnChange
                      ? openHandLocalizedText(
                          context,
                          zh: '配置自动重载',
                          zhHant: '設定自動重載',
                          en: 'Auto-reload config',
                          fr: 'Rechargement auto',
                          de: 'Konfiguration automatisch neu laden',
                          ja: '設定を自動再読み込み',
                        )
                      : openHandLocalizedText(
                          context,
                          zh: '配置重启生效',
                          zhHant: '設定重啟生效',
                          en: 'Restart required for config',
                          fr: 'Redémarrage requis',
                          de: 'Neustart für Konfiguration nötig',
                          ja: '設定反映には再起動が必要',
                        ),
                ),
                if (controller.hasPendingRuntimeConfig)
                  _InfoChip(
                    icon: Icons.pending_actions_rounded,
                    label: openHandLocalizedText(
                      context,
                      zh: '待重启生效',
                      zhHant: '待重啟生效',
                      en: 'Pending restart',
                      fr: 'Redémarrage en attente',
                      de: 'Neustart ausstehend',
                      ja: '再起動待ち',
                    ),
                  ),
                _InfoChip(
                  icon: Icons.link_rounded,
                  label: isRunning
                      ? controller.webUrl
                      : '${config.listenHost}:${config.listenPort}',
                ),
                if (usingFallbackPort)
                  _InfoChip(
                    icon: Icons.warning_amber_rounded,
                    label: openHandLocalizedText(
                      context,
                      zh: '${config.listenPort} 被占用，临时端口 $boundPort',
                      zhHant: '${config.listenPort} 已被占用，臨時連接埠 $boundPort',
                      en: '${config.listenPort} is in use, temporary port $boundPort',
                      fr: '${config.listenPort} est occupé, port temporaire $boundPort',
                      de: '${config.listenPort} ist belegt, temporärer Port $boundPort',
                      ja: '${config.listenPort} は使用中、一時ポート $boundPort',
                    ),
                  ),
                _InfoChip(
                  icon: Icons.lock_outline_rounded,
                  label: config.authEnabled
                      ? openHandLocalizedText(
                          context,
                          zh: '鉴权开启',
                          zhHant: '鑑權開啟',
                          en: 'Auth enabled',
                          fr: 'Auth activée',
                          de: 'Auth aktiviert',
                          ja: '認証有効',
                        )
                      : openHandLocalizedText(
                          context,
                          zh: '免鉴权',
                          zhHant: '免鑑權',
                          en: 'Auth disabled',
                          fr: 'Auth désactivée',
                          de: 'Auth deaktiviert',
                          ja: '認証なし',
                        ),
                ),
                _InfoChip(
                  icon: Icons.analytics_outlined,
                  label: config.telemetryEnabled
                      ? openHandLocalizedText(
                          context,
                          zh: '遥测开启',
                          zhHant: '遙測開啟',
                          en: 'Telemetry enabled',
                          fr: 'Télémétrie activée',
                          de: 'Telemetrie aktiviert',
                          ja: 'テレメトリ有効',
                        )
                      : openHandLocalizedText(
                          context,
                          zh: '遥测关闭',
                          zhHant: '遙測關閉',
                          en: 'Telemetry disabled',
                          fr: 'Télémétrie désactivée',
                          de: 'Telemetrie deaktiviert',
                          ja: 'テレメトリ無効',
                        ),
                ),
                _InfoChip(
                  icon: Icons.article_outlined,
                  label: config.loggingEnabled
                      ? openHandLocalizedText(
                          context,
                          zh: '日志开启',
                          zhHant: '日誌開啟',
                          en: 'Logging enabled',
                          fr: 'Journaux activés',
                          de: 'Protokolle aktiviert',
                          ja: 'ログ有効',
                        )
                      : openHandLocalizedText(
                          context,
                          zh: '日志关闭',
                          zhHant: '日誌關閉',
                          en: 'Logging disabled',
                          fr: 'Journaux désactivés',
                          de: 'Protokolle deaktiviert',
                          ja: 'ログ無効',
                        ),
                ),
                _InfoChip(
                  icon: Icons.security_rounded,
                  label: openHandLocalizedText(
                    context,
                    zh: '并发 ${config.maxConcurrentRequests}',
                    zhHant: '並發 ${config.maxConcurrentRequests}',
                    en: 'Concurrency ${config.maxConcurrentRequests}',
                    fr: 'Concurrence ${config.maxConcurrentRequests}',
                    de: 'Parallelität ${config.maxConcurrentRequests}',
                    ja: '同時実行 ${config.maxConcurrentRequests}',
                  ),
                ),
                _InfoChip(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: openHandLocalizedText(
                    context,
                    zh: '单消息 ${config.singleMessageTokenLimit} tokens',
                    zhHant: '單訊息 ${config.singleMessageTokenLimit} tokens',
                    en: '${config.singleMessageTokenLimit} tokens/message',
                    fr: '${config.singleMessageTokenLimit} tokens/message',
                    de: '${config.singleMessageTokenLimit} Tokens/Nachricht',
                    ja: '1メッセージ ${config.singleMessageTokenLimit} tokens',
                  ),
                ),
                _InfoChip(
                  icon: Icons.forum_outlined,
                  label: openHandLocalizedText(
                    context,
                    zh: '单会话 ${config.maxMessagesPerSession} 条',
                    zhHant: '單會話 ${config.maxMessagesPerSession} 則',
                    en: '${config.maxMessagesPerSession} messages/session',
                    fr: '${config.maxMessagesPerSession} messages/session',
                    de: '${config.maxMessagesPerSession} Nachrichten/Sitzung',
                    ja: '1セッション ${config.maxMessagesPerSession} 件',
                  ),
                ),
                _InfoChip(
                  icon: Icons.manage_accounts_outlined,
                  label: config.sessionManagementEnabled
                      ? openHandLocalizedText(
                          context,
                          zh: '会话可管理',
                          zhHant: '會話可管理',
                          en: 'Sessions manageable',
                          fr: 'Sessions gérables',
                          de: 'Sitzungen verwaltbar',
                          ja: 'セッション管理可',
                        )
                      : openHandLocalizedText(
                          context,
                          zh: '会话只读',
                          zhHant: '會話唯讀',
                          en: 'Sessions read-only',
                          fr: 'Sessions en lecture seule',
                          de: 'Sitzungen schreibgeschützt',
                          ja: 'セッション読み取り専用',
                        ),
                ),
                _InfoChip(
                  icon: Icons.library_books_outlined,
                  label: config.knowledgeBaseEnabled
                      ? openHandLocalizedText(
                          context,
                          zh: '知识库开启',
                          zhHant: '知識庫開啟',
                          en: 'Knowledge base enabled',
                          fr: 'Base de connaissances activée',
                          de: 'Wissensdatenbank aktiviert',
                          ja: 'ナレッジベース有効',
                        )
                      : openHandLocalizedText(
                          context,
                          zh: '知识库关闭',
                          zhHant: '知識庫關閉',
                          en: 'Knowledge base disabled',
                          fr: 'Base de connaissances désactivée',
                          de: 'Wissensdatenbank deaktiviert',
                          ja: 'ナレッジベース無効',
                        ),
                ),
                _InfoChip(
                  icon: Icons.folder_open_rounded,
                  label: config.workspaceFileWriteEnabled
                      ? openHandLocalizedText(
                          context,
                          zh: '文件浏览 / 可操作',
                          zhHant: '檔案瀏覽 / 可操作',
                          en: 'Files browsable / writable',
                          fr: 'Fichiers consultables / modifiables',
                          de: 'Dateien durchsuchbar / schreibbar',
                          ja: 'ファイル閲覧 / 操作可',
                        )
                      : openHandLocalizedText(
                          context,
                          zh: '文件浏览 / 只读',
                          zhHant: '檔案瀏覽 / 唯讀',
                          en: 'Files browsable / read-only',
                          fr: 'Fichiers consultables / lecture seule',
                          de: 'Dateien durchsuchbar / schreibgeschützt',
                          ja: 'ファイル閲覧 / 読み取り専用',
                        ),
                ),
              ],
            ),
            // 监听通配符地址（0.0.0.0 / ::）时由 service.accessibleUrls 列出
            // 全部可访问 URL（含 LAN IP），点 chip 即拷贝。仅当 URL 数量 >1
            // 时渲染，避免与上方"已运行单 URL"的 InfoChip 重复。
            if (isRunning && controller.webUrls.length > 1) ...[
              const SizedBox(height: 12),
              _AccessibleUrlsBar(urls: controller.webUrls),
            ],
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth < 820 ? 1 : 4;
                return GridView.count(
                  crossAxisCount: columns,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: columns == 1 ? 5.8 : 2.9,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _MetricTile(
                      label: openHandLocalizedText(
                        context,
                        zh: '状态',
                        zhHant: '狀態',
                        en: 'Status',
                        fr: 'État',
                        de: 'Status',
                        ja: '状態',
                      ),
                      value: _runtimeStateLabel(context, runtime.state),
                    ),
                    _MetricTile(
                      label: openHandLocalizedText(
                        context,
                        zh: '请求数',
                        zhHant: '請求數',
                        en: 'Requests',
                        fr: 'Requêtes',
                        de: 'Anfragen',
                        ja: 'リクエスト数',
                      ),
                      value: '${runtime.totalRequests}',
                    ),
                    _MetricTile(
                      label: openHandLocalizedText(
                        context,
                        zh: '错误数',
                        zhHant: '錯誤數',
                        en: 'Errors',
                        fr: 'Erreurs',
                        de: 'Fehler',
                        ja: 'エラー数',
                      ),
                      value: '${runtime.totalErrors}',
                    ),
                    _MetricTile(
                      label: openHandLocalizedText(
                        context,
                        zh: '运行时长',
                        zhHant: '執行時間',
                        en: 'Uptime',
                        fr: 'Temps actif',
                        de: 'Laufzeit',
                        ja: '稼働時間',
                      ),
                      value: formatCompactDurationMs(runtime.uptimeMs),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditor(
    BuildContext context,
    MessageGatewayController controller,
  ) async {
    await showAnimatedDialog<void>(
      context: context,
      builder: (_) => _WebPlatformEditorDialog(
        controller: controller,
        initialConfig: controller.config,
      ),
    );
  }

  Future<void> _runHealth(
    BuildContext context,
    MessageGatewayController controller,
  ) async {
    final result = await controller.runHealthCheck();
    if (!context.mounted) return;
    showOpenHandSnackBar(
      context,
      result.ok
          ? OpenHandSnackBar.success(
              context,
              '${result.summary} (${result.durationMs}ms)',
            )
          : OpenHandSnackBar.error(
              context,
              '${result.summary} (${result.durationMs}ms)',
            ),
    );
  }

  Future<void> _showLogs(
    BuildContext context,
    MessageGatewayController controller,
  ) async {
    await showAnimatedDialog<void>(
      context: context,
      builder: (_) => _WebGatewayLogDialog(controller: controller),
    );
  }

  Future<void> _showConnectivityTest(
    BuildContext context,
    MessageGatewayController controller,
  ) async {
    await showAnimatedDialog<void>(
      context: context,
      builder: (_) => _WebGatewayConnectivityDialog(controller: controller),
    );
  }

  Future<void> _showOps(
    BuildContext context,
    MessageGatewayController controller,
  ) async {
    await showAnimatedDialog<void>(
      context: context,
      builder: (_) => _WebGatewayOpsDialog(controller: controller),
    );
  }
}

class _WebPlatformEditorDialog extends StatefulWidget {
  const _WebPlatformEditorDialog({
    required this.controller,
    required this.initialConfig,
  });

  final MessageGatewayController controller;
  final WebMessagePlatformConfig initialConfig;

  @override
  State<_WebPlatformEditorDialog> createState() =>
      _WebPlatformEditorDialogState();
}

class _WebPlatformEditorDialogState extends State<_WebPlatformEditorDialog> {
  late bool _enabled;
  late bool _autoStartOnLaunch;
  late bool _autoReloadOnChange;
  late bool _authEnabled;
  late bool _telemetryEnabled;
  late bool _loggingEnabled;
  late bool _opsEnabled;
  late bool _healthEnabled;
  late bool _planModeEnabled;
  late bool _agentsEnabled;
  late bool _knowledgeBaseEnabled;
  late bool _readAloudEnabled;
  late bool _translationEnabled;
  late bool _feedbackEnabled;
  late bool _regenerationEnabled;
  late bool _sessionManagementEnabled;
  late bool _workspaceFileWriteEnabled;
  late final TextEditingController _descriptionController;
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _maxConcurrentController;
  late final TextEditingController _singleMessageController;
  late final TextEditingController _maxMessagesController;
  late final TextEditingController _logMaxMbController;
  late final TextEditingController _logRotationDaysController;
  late final TextEditingController _logMaxFilesController;
  late final TextEditingController _workspaceFileMaxMbController;
  late final TextEditingController _workspaceFileExtensionsController;
  late final TextEditingController _uploadCacheRetentionDaysController;
  late final TextEditingController _uploadCacheMaxMbController;
  late final TextEditingController _healthPathController;
  late final TextEditingController _healthMethodController;
  late final TextEditingController _healthTimeoutController;
  late final TextEditingController _healthStatusController;
  late final TextEditingController _healthContainsController;
  late final TextEditingController _healthQueryController;
  late bool _healthFollowRedirects;
  late Set<String> _templates;
  late Set<String> _skills;
  late Set<String> _mcpServers;
  late Set<String> _memories;
  late Set<String> _tools;
  late Set<String> _instructions;
  late Set<String> _agents;
  late Set<String> _models;
  late Set<WebGatewayMessageType> _messageTypes;
  late Set<WebGatewayConversationMode> _modes;
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    final config = widget.initialConfig;
    _enabled = config.enabled;
    _autoStartOnLaunch = config.autoStartOnLaunch;
    _autoReloadOnChange = config.autoReloadOnChange;
    _authEnabled = config.authEnabled;
    _telemetryEnabled = config.telemetryEnabled;
    _loggingEnabled = config.loggingEnabled;
    _opsEnabled = config.opsEnabled;
    _healthEnabled = config.healthCheck.enabled;
    _planModeEnabled = config.planModeEnabled;
    _agentsEnabled = config.agentsEnabled;
    _knowledgeBaseEnabled = config.knowledgeBaseEnabled;
    _readAloudEnabled = config.readAloudEnabled;
    _translationEnabled = config.translationEnabled;
    _feedbackEnabled = config.feedbackEnabled;
    _regenerationEnabled = config.regenerationEnabled;
    _sessionManagementEnabled = config.sessionManagementEnabled;
    _workspaceFileWriteEnabled = config.workspaceFileWriteEnabled;
    _descriptionController = TextEditingController(text: config.description);
    _hostController = TextEditingController(text: config.listenHost);
    _portController = TextEditingController(text: '${config.listenPort}');
    _usernameController = TextEditingController(text: config.username);
    _passwordController = TextEditingController(text: config.password);
    _maxConcurrentController = TextEditingController(
      text: '${config.maxConcurrentRequests}',
    );
    _singleMessageController = TextEditingController(
      text: '${config.singleMessageTokenLimit}',
    );
    _maxMessagesController = TextEditingController(
      text: '${config.maxMessagesPerSession}',
    );
    _logMaxMbController = TextEditingController(
      text: '${(config.logConfig.fileMaxBytes / (1024 * 1024)).round()}',
    );
    _logRotationDaysController = TextEditingController(
      text: '${config.logConfig.rotationDays}',
    );
    _logMaxFilesController = TextEditingController(
      text: '${config.logConfig.maxFiles}',
    );
    _workspaceFileMaxMbController = TextEditingController(
      text:
          '${math.max(1, (config.workspaceFileMaxBytes / (1024 * 1024)).ceil())}',
    );
    _workspaceFileExtensionsController = TextEditingController(
      text: config.workspaceFileAllowedExtensions.join(', '),
    );
    _uploadCacheRetentionDaysController = TextEditingController(
      text: '${config.uploadCacheRetentionDays}',
    );
    _uploadCacheMaxMbController = TextEditingController(
      text: '${(config.uploadCacheMaxBytes / (1024 * 1024)).round()}',
    );
    _healthPathController = TextEditingController(
      text: config.healthCheck.path,
    );
    _healthMethodController = TextEditingController(
      text: config.healthCheck.method,
    );
    _healthTimeoutController = TextEditingController(
      text: '${config.healthCheck.timeoutMs}',
    );
    _healthStatusController = TextEditingController(
      text: '${config.healthCheck.expectedStatusCode}',
    );
    _healthContainsController = TextEditingController(
      text: config.healthCheck.responseContains,
    );
    _healthQueryController = TextEditingController(
      text: _formatQueryParameters(config.healthCheck.queryParameters),
    );
    _healthFollowRedirects = config.healthCheck.followRedirects;
    _templates = config.allowedTemplateIds.toSet();
    _skills = config.allowedSkillNames.toSet();
    _mcpServers = config.allowedMcpServerNames.toSet();
    _memories = config.allowedMemoryIds.toSet();
    final configuredTools = config.allowedBuiltinToolNames.toSet();
    _tools = _knowledgeBaseEnabled
        ? configuredTools
        : _toolsWithoutKnowledgeBase(configuredTools);
    _instructions = config.allowedInstructionIds.toSet();
    _agents = config.allowedAgentIds.toSet();
    _models = config.allowedModelKeys.toSet();
    _messageTypes = config.allowedMessageTypes.toSet();
    _modes = config.allowedConversationModes.toSet();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _maxConcurrentController.dispose();
    _singleMessageController.dispose();
    _maxMessagesController.dispose();
    _logMaxMbController.dispose();
    _logRotationDaysController.dispose();
    _logMaxFilesController.dispose();
    _workspaceFileMaxMbController.dispose();
    _workspaceFileExtensionsController.dispose();
    _uploadCacheRetentionDaysController.dispose();
    _uploadCacheMaxMbController.dispose();
    _healthPathController.dispose();
    _healthMethodController.dispose();
    _healthTimeoutController.dispose();
    _healthStatusController.dispose();
    _healthContainsController.dispose();
    _healthQueryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return buildOpenHandResponsiveDialogShell(
      context: context,
      maxWidth: 920,
      minAvailableHeight: 420,
      backgroundColor: colorScheme.surfaceContainerHigh,
      surfaceTintColor: colorScheme.surfaceTint,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kOpenHandDialogDefaultRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(22, 18, 14, 16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              border: Border(
                bottom: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(19),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.primary.withValues(alpha: .14),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.language_rounded,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        webMessagePlatformBuiltinName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        openHandLocalizedText(
                          context,
                          zh: '配置 Web 端可见能力、访问边界与运行保护策略',
                          zhHant: '設定 Web 端可見能力、存取邊界與執行保護策略',
                          en: 'Configure web-visible capabilities, access boundaries, and runtime safeguards',
                          fr: 'Configurez les capacités web visibles, les limites d’accès et les protections',
                          de: 'Websichtbare Funktionen, Zugriffsgrenzen und Schutzregeln konfigurieren',
                          ja: 'Web側の表示機能、アクセス境界、実行保護を設定',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  tooltip: openHandLocalizedText(
                    context,
                    zh: '关闭',
                    zhHant: '關閉',
                    en: 'Close',
                    fr: 'Fermer',
                    de: 'Schließen',
                    ja: '閉じる',
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              primary: false,
              physics: kOpenHandClampingPhysics,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final twoColumns = constraints.maxWidth >= 760;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SwitchGrid(
                        twoColumns: twoColumns,
                        children: [
                          _SwitchTile(
                            label: openHandLocalizedText(
                              context,
                              zh: '是否启用',
                              zhHant: '是否啟用',
                              en: 'Enabled',
                              fr: 'Activé',
                              de: 'Aktiviert',
                              ja: '有効',
                            ),
                            value: _enabled,
                            onChanged: (v) => setState(() => _enabled = v),
                          ),
                          _SwitchTile(
                            label: openHandLocalizedText(
                              context,
                              zh: '冷启动自动启动',
                              zhHant: '冷啟動自動啟動',
                              en: 'Auto-start on launch',
                              fr: 'Démarrage auto au lancement',
                              de: 'Autostart beim Start',
                              ja: '起動時に自動開始',
                            ),
                            value: _autoStartOnLaunch,
                            onChanged: (value) =>
                                setState(() => _autoStartOnLaunch = value),
                          ),
                          _SwitchTile(
                            label: openHandLocalizedText(
                              context,
                              zh: '配置变更自动重载',
                              zhHant: '設定變更自動重載',
                              en: 'Auto-reload config changes',
                              fr: 'Recharger automatiquement les changements',
                              de: 'Konfigurationsänderungen automatisch laden',
                              ja: '設定変更を自動再読み込み',
                            ),
                            value: _autoReloadOnChange,
                            onChanged: (value) =>
                                setState(() => _autoReloadOnChange = value),
                          ),
                          _SwitchTile(
                            label: openHandLocalizedText(
                              context,
                              zh: '是否开启鉴权',
                              zhHant: '是否開啟鑑權',
                              en: 'Authentication',
                              fr: 'Authentification',
                              de: 'Authentifizierung',
                              ja: '認証',
                            ),
                            value: _authEnabled,
                            onChanged: (v) => setState(() => _authEnabled = v),
                          ),
                          _SwitchTile(
                            label: openHandLocalizedText(
                              context,
                              zh: '是否启用遥测',
                              zhHant: '是否啟用遙測',
                              en: 'Telemetry',
                              fr: 'Télémétrie',
                              de: 'Telemetrie',
                              ja: 'テレメトリ',
                            ),
                            value: _telemetryEnabled,
                            onChanged: (v) =>
                                setState(() => _telemetryEnabled = v),
                          ),
                          _SwitchTile(
                            label: openHandLocalizedText(
                              context,
                              zh: '是否记录日志',
                              zhHant: '是否記錄日誌',
                              en: 'Logging',
                              fr: 'Journaux',
                              de: 'Protokollierung',
                              ja: 'ログ記録',
                            ),
                            value: _loggingEnabled,
                            onChanged: (v) =>
                                setState(() => _loggingEnabled = v),
                          ),
                          _SwitchTile(
                            label: openHandLocalizedText(
                              context,
                              zh: '是否支持运维',
                              zhHant: '是否支援維運',
                              en: 'Operations panel',
                              fr: 'Panneau opérations',
                              de: 'Betriebsbereich',
                              ja: '運用パネル',
                            ),
                            value: _opsEnabled,
                            onChanged: (v) => setState(() => _opsEnabled = v),
                          ),
                          _SwitchTile(
                            label: openHandLocalizedText(
                              context,
                              zh: '是否开启健康检查',
                              zhHant: '是否開啟健康檢查',
                              en: 'Health checks',
                              fr: 'Contrôles de santé',
                              de: 'Integritätsprüfungen',
                              ja: 'ヘルスチェック',
                            ),
                            value: _healthEnabled,
                            onChanged: (v) =>
                                setState(() => _healthEnabled = v),
                          ),
                          _SwitchTile(
                            label: openHandLocalizedText(
                              context,
                              zh: '是否支持计划模式',
                              zhHant: '是否支援計劃模式',
                              en: 'Plan mode',
                              fr: 'Mode plan',
                              de: 'Planmodus',
                              ja: 'プランモード',
                            ),
                            value: _planModeEnabled,
                            onChanged: (v) =>
                                setState(() => _planModeEnabled = v),
                          ),
                          _SwitchTile(
                            label: openHandLocalizedText(
                              context,
                              zh: '是否开启智能体',
                              zhHant: '是否開啟智能體',
                              en: 'Agent access',
                              fr: 'Accès aux agents',
                              de: 'Agent-Zugriff',
                              ja: 'エージェントアクセス',
                            ),
                            value: _agentsEnabled,
                            onChanged: (v) =>
                                setState(() => _agentsEnabled = v),
                          ),
                          _SwitchTile(
                            label: openHandLocalizedText(
                              context,
                              zh: '是否开启知识库',
                              zhHant: '是否開啟知識庫',
                              en: 'Knowledge base',
                              fr: 'Base de connaissances',
                              de: 'Wissensdatenbank',
                              ja: 'ナレッジベース',
                            ),
                            value: _knowledgeBaseEnabled,
                            onChanged: _setKnowledgeBaseEnabled,
                          ),
                          _SwitchTile(
                            label: openHandLocalizedText(
                              context,
                              zh: '是否启用朗读功能',
                              zhHant: '是否啟用朗讀功能',
                              en: 'Read aloud',
                              fr: 'Lecture vocale',
                              de: 'Vorlesen',
                              ja: '読み上げ',
                            ),
                            value: _readAloudEnabled,
                            onChanged: (v) =>
                                setState(() => _readAloudEnabled = v),
                          ),
                          _SwitchTile(
                            label: openHandLocalizedText(
                              context,
                              zh: '是否启用翻译功能',
                              zhHant: '是否啟用翻譯功能',
                              en: 'Translation',
                              fr: 'Traduction',
                              de: 'Übersetzung',
                              ja: '翻訳',
                            ),
                            value: _translationEnabled,
                            onChanged: (v) =>
                                setState(() => _translationEnabled = v),
                          ),
                          _SwitchTile(
                            label: openHandLocalizedText(
                              context,
                              zh: '是否启用点赞功能',
                              zhHant: '是否啟用按讚功能',
                              en: 'Feedback buttons',
                              fr: 'Boutons de retour',
                              de: 'Feedback-Schaltflächen',
                              ja: 'フィードバックボタン',
                            ),
                            value: _feedbackEnabled,
                            onChanged: (v) =>
                                setState(() => _feedbackEnabled = v),
                          ),
                          _SwitchTile(
                            label: openHandLocalizedText(
                              context,
                              zh: '是否启用重新生成功能',
                              zhHant: '是否啟用重新生成功能',
                              en: 'Regenerate',
                              fr: 'Régénération',
                              de: 'Neu generieren',
                              ja: '再生成',
                            ),
                            value: _regenerationEnabled,
                            onChanged: (v) =>
                                setState(() => _regenerationEnabled = v),
                          ),
                          _SwitchTile(
                            label: openHandLocalizedText(
                              context,
                              zh: '是否允许 Web 会话管理',
                              zhHant: '是否允許 Web 會話管理',
                              en: 'Web session management',
                              fr: 'Gestion des sessions web',
                              de: 'Web-Sitzungsverwaltung',
                              ja: 'Webセッション管理',
                            ),
                            value: _sessionManagementEnabled,
                            onChanged: (v) =>
                                setState(() => _sessionManagementEnabled = v),
                          ),
                          _SwitchTile(
                            label: openHandLocalizedText(
                              context,
                              zh: '是否支持操作文件',
                              zhHant: '是否支援操作檔案',
                              en: 'File write access',
                              fr: 'Accès en écriture aux fichiers',
                              de: 'Dateischreibzugriff',
                              ja: 'ファイル書き込み',
                            ),
                            value: _workspaceFileWriteEnabled,
                            onChanged: (v) =>
                                setState(() => _workspaceFileWriteEnabled = v),
                          ),
                        ],
                      ),
                      AnimatedSwitcher(
                        duration: openHandMotionDurationMs(context, 220),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: _switcherSizeFadeTransition,
                        child: _autoReloadOnChange
                            ? const SizedBox.shrink(
                                key: ValueKey('auto-reload-on'),
                              )
                            : Padding(
                                key: const ValueKey('auto-reload-off'),
                                padding: const EdgeInsets.only(top: 10),
                                child: _EditorNotice(
                                  icon: Icons.restart_alt_rounded,
                                  title: openHandLocalizedText(
                                    context,
                                    zh: '配置将等待重启生效',
                                    zhHant: '設定將等待重啟生效',
                                    en: 'Configuration will apply after restart',
                                    fr: 'La configuration s’appliquera après redémarrage',
                                    de: 'Konfiguration wird nach Neustart wirksam',
                                    ja: '設定は再起動後に反映されます',
                                  ),
                                  body: openHandLocalizedText(
                                    context,
                                    zh: '自动重载关闭后，本次保存只写入配置文件；运行中的 Web 服务会继续使用旧配置，直到手动重启服务或应用冷启动。',
                                    zhHant:
                                        '自動重載關閉後，本次儲存只會寫入設定檔；執行中的 Web 服務會繼續使用舊設定，直到手動重啟服務或應用冷啟動。',
                                    en: 'With auto-reload off, saving only writes the config file. The running web service keeps the old config until you restart the service or relaunch the app.',
                                    fr: 'Quand le rechargement auto est désactivé, l’enregistrement écrit seulement le fichier. Le service web garde l’ancienne configuration jusqu’au redémarrage.',
                                    de: 'Bei deaktiviertem Auto-Reload wird nur die Datei gespeichert. Der laufende Webdienst nutzt die alte Konfiguration bis zum Neustart.',
                                    ja: '自動再読み込みがオフの場合、保存は設定ファイルだけを書き込みます。実行中のWebサービスは再起動まで旧設定を使います。',
                                  ),
                                ),
                              ),
                      ),
                      AnimatedSwitcher(
                        duration: openHandMotionDurationMs(context, 240),
                        switchInCurve: Curves.easeOutBack,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: _switcherSizeFadeTransition,
                        child: _agentsEnabled
                            ? Padding(
                                key: const ValueKey('agents-enabled'),
                                padding: const EdgeInsets.only(top: 12),
                                child: _AgentExposurePanel(
                                  options: widget.controller.agentOptions,
                                  selected: _effectiveAgentIdsForDisplay(),
                                  onChanged: _setEffectiveAgentIds,
                                ),
                              )
                            : const SizedBox.shrink(
                                key: ValueKey('agents-disabled'),
                              ),
                      ),
                      const SizedBox(height: 18),
                      _SectionTitle(
                        openHandLocalizedText(
                          context,
                          zh: '基础信息',
                          zhHant: '基礎資訊',
                          en: 'Basic Info',
                          fr: 'Informations de base',
                          de: 'Basisinformationen',
                          ja: '基本情報',
                        ),
                        icon: Icons.info_outline_rounded,
                      ),
                      _TextArea(
                        label: openHandLocalizedText(
                          context,
                          zh: '介绍',
                          zhHant: '介紹',
                          en: 'Description',
                          fr: 'Description',
                          de: 'Beschreibung',
                          ja: '説明',
                        ),
                        controller: _descriptionController,
                      ),
                      _ResponsiveFields(
                        twoColumns: twoColumns,
                        children: [
                          _TextFieldSpec(
                            label: openHandLocalizedText(
                              context,
                              zh: '监听 IP 地址',
                              zhHant: '監聽 IP 位址',
                              en: 'Listen IP address',
                              fr: 'Adresse IP d’écoute',
                              de: 'Lausch-IP-Adresse',
                              ja: 'リッスンIPアドレス',
                            ),
                            controller: _hostController,
                          ),
                          _TextFieldSpec(
                            label: openHandLocalizedText(
                              context,
                              zh: '监听端口',
                              zhHant: '監聽連接埠',
                              en: 'Listen port',
                              fr: 'Port d’écoute',
                              de: 'Lausch-Port',
                              ja: 'リッスンポート',
                            ),
                            controller: _portController,
                            keyboardType: TextInputType.number,
                          ),
                          _TextFieldSpec(
                            label: openHandLocalizedText(
                              context,
                              zh: '可接受并发数',
                              zhHant: '可接受並發數',
                              en: 'Max concurrency',
                              fr: 'Concurrence maximale',
                              de: 'Maximale Parallelität',
                              ja: '最大同時実行数',
                            ),
                            controller: _maxConcurrentController,
                            keyboardType: TextInputType.number,
                          ),
                          _TextFieldSpec(
                            label: openHandLocalizedText(
                              context,
                              zh: '单消息大小(tokens)',
                              zhHant: '單訊息大小(tokens)',
                              en: 'Single message size (tokens)',
                              fr: 'Taille d’un message (tokens)',
                              de: 'Nachrichtengröße (Tokens)',
                              ja: '1メッセージサイズ(tokens)',
                            ),
                            controller: _singleMessageController,
                            keyboardType: TextInputType.number,
                          ),
                          _TextFieldSpec(
                            label: openHandLocalizedText(
                              context,
                              zh: '单会话最大消息数',
                              zhHant: '單會話最大訊息數',
                              en: 'Max messages per session',
                              fr: 'Messages max par session',
                              de: 'Max. Nachrichten pro Sitzung',
                              ja: 'セッション最大メッセージ数',
                            ),
                            controller: _maxMessagesController,
                            keyboardType: TextInputType.number,
                          ),
                        ],
                      ),
                      if (_authEnabled) ...[
                        const SizedBox(height: 18),
                        _SectionTitle(
                          openHandLocalizedText(
                            context,
                            zh: '鉴权',
                            zhHant: '鑑權',
                            en: 'Authentication',
                            fr: 'Authentification',
                            de: 'Authentifizierung',
                            ja: '認証',
                          ),
                          icon: Icons.lock_outline_rounded,
                        ),
                        _ResponsiveFields(
                          twoColumns: twoColumns,
                          children: [
                            _TextFieldSpec(
                              label: openHandLocalizedText(
                                context,
                                zh: '用户名',
                                zhHant: '使用者名稱',
                                en: 'Username',
                                fr: 'Nom d’utilisateur',
                                de: 'Benutzername',
                                ja: 'ユーザー名',
                              ),
                              controller: _usernameController,
                            ),
                            _TextFieldSpec(
                              label: openHandLocalizedText(
                                context,
                                zh: '密码',
                                zhHant: '密碼',
                                en: 'Password',
                                fr: 'Mot de passe',
                                de: 'Passwort',
                                ja: 'パスワード',
                              ),
                              controller: _passwordController,
                              obscureText: true,
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 18),
                      _SectionTitle(
                        openHandLocalizedText(
                          context,
                          zh: '安全控制',
                          zhHant: '安全控制',
                          en: 'Security Controls',
                          fr: 'Contrôles de sécurité',
                          de: 'Sicherheitssteuerung',
                          ja: 'セキュリティ制御',
                        ),
                        icon: Icons.shield_outlined,
                      ),
                      _MultiSelectDropdown<String>(
                        label: openHandLocalizedText(
                          context,
                          zh: '可新建的线程模板类型',
                          zhHant: '可新建的執行緒模板類型',
                          en: 'Allowed thread templates',
                          fr: 'Modèles de fil autorisés',
                          de: 'Erlaubte Thread-Vorlagen',
                          ja: '作成可能なスレッドテンプレート',
                        ),
                        emptyMeansAll: true,
                        noneValue: webGatewayDenyAllSelectionMarker,
                        options: [
                          for (final t in widget.controller.templates)
                            _SelectOption(value: t.id, label: t.name),
                        ],
                        selected: _templates,
                        onChanged: (next) => setState(() => _templates = next),
                      ),
                      _MultiSelectDropdown<String>(
                        label: openHandLocalizedText(
                          context,
                          zh: '可用的技能',
                          zhHant: '可用的技能',
                          en: 'Allowed skills',
                          fr: 'Compétences autorisées',
                          de: 'Erlaubte Skills',
                          ja: '利用可能なスキル',
                        ),
                        emptyMeansAll: true,
                        noneValue: webGatewayDenyAllSelectionMarker,
                        options: [
                          for (final name in widget.controller.skillNames)
                            _SelectOption(value: name, label: name),
                        ],
                        selected: _skills,
                        onChanged: (next) => setState(() => _skills = next),
                      ),
                      _MultiSelectDropdown<String>(
                        label: openHandLocalizedText(
                          context,
                          zh: '可用的 MCP',
                          zhHant: '可用的 MCP',
                          en: 'Allowed MCP servers',
                          fr: 'Serveurs MCP autorisés',
                          de: 'Erlaubte MCP-Server',
                          ja: '利用可能なMCP',
                        ),
                        emptyMeansAll: true,
                        noneValue: webGatewayDenyAllSelectionMarker,
                        options: [
                          for (final name in widget.controller.mcpServerNames)
                            _SelectOption(value: name, label: name),
                        ],
                        selected: _mcpServers,
                        onChanged: (next) => setState(() => _mcpServers = next),
                      ),
                      _MultiSelectDropdown<String>(
                        label: openHandLocalizedText(
                          context,
                          zh: '可用的记忆',
                          zhHant: '可用的記憶',
                          en: 'Allowed memories',
                          fr: 'Mémoires autorisées',
                          de: 'Erlaubte Erinnerungen',
                          ja: '利用可能なメモリ',
                        ),
                        emptyMeansAll: true,
                        noneValue: webGatewayDenyAllSelectionMarker,
                        options: [
                          for (final id in widget.controller.memoryIds)
                            _SelectOption(value: id, label: id),
                        ],
                        selected: _memories,
                        onChanged: (next) => setState(() => _memories = next),
                      ),
                      _MultiSelectDropdown<String>(
                        label: openHandLocalizedText(
                          context,
                          zh: '可用的内建工具',
                          zhHant: '可用的內建工具',
                          en: 'Allowed built-in tools',
                          fr: 'Outils intégrés autorisés',
                          de: 'Erlaubte integrierte Tools',
                          ja: '利用可能な内蔵ツール',
                        ),
                        emptyMeansAll: true,
                        noneValue: webGatewayDenyAllSelectionMarker,
                        options: [
                          for (final name in _visibleBuiltinToolNames)
                            _SelectOption(value: name, label: name),
                        ],
                        selected: _tools,
                        onChanged: (next) => setState(() => _tools = next),
                      ),
                      _MultiSelectDropdown<String>(
                        label: openHandLocalizedText(
                          context,
                          zh: '可用的用户指令',
                          zhHant: '可用的使用者指令',
                          en: 'Allowed user instructions',
                          fr: 'Instructions utilisateur autorisées',
                          de: 'Erlaubte Benutzeranweisungen',
                          ja: '利用可能なユーザー指示',
                        ),
                        emptyMeansAll: true,
                        noneValue: webGatewayDenyAllSelectionMarker,
                        options: [
                          for (final option
                              in widget.controller.instructionOptions)
                            _SelectOption(
                              value: option.id,
                              label: option.enabled
                                  ? option.label
                                  : '${option.label}（${openHandLocalizedText(context, zh: '已禁用', zhHant: '已停用', en: 'disabled', fr: 'désactivé', de: 'deaktiviert', ja: '無効')}）',
                            ),
                        ],
                        selected: _instructions,
                        onChanged: (next) =>
                            setState(() => _instructions = next),
                      ),
                      _EnumMultiSelectDropdown<WebGatewayMessageType>(
                        label: openHandLocalizedText(
                          context,
                          zh: '可发送的消息类型',
                          zhHant: '可傳送的訊息類型',
                          en: 'Allowed message types',
                          fr: 'Types de message autorisés',
                          de: 'Erlaubte Nachrichtentypen',
                          ja: '送信可能なメッセージタイプ',
                        ),
                        values: WebGatewayMessageType.values,
                        selected: _messageTypes,
                        labelFor: (value) => _messageTypeLabel(context, value),
                        onChanged: (next) =>
                            setState(() => _messageTypes = next),
                      ),
                      _EnumMultiSelectDropdown<WebGatewayConversationMode>(
                        label: openHandLocalizedText(
                          context,
                          zh: '可使用的对话模式',
                          zhHant: '可使用的對話模式',
                          en: 'Allowed conversation modes',
                          fr: 'Modes de conversation autorisés',
                          de: 'Erlaubte Gesprächsmodi',
                          ja: '利用可能な会話モード',
                        ),
                        values: WebGatewayConversationMode.values,
                        selected: _modes,
                        labelFor: (mode) => _modeLabel(context, mode),
                        onChanged: (next) => setState(() => _modes = next),
                      ),
                      _ModelMultiSelectField(
                        label: openHandLocalizedText(
                          context,
                          zh: '可使用的模型',
                          zhHant: '可使用的模型',
                          en: 'Allowed models',
                          fr: 'Modèles autorisés',
                          de: 'Erlaubte Modelle',
                          ja: '利用可能なモデル',
                        ),
                        emptyMeansAll: true,
                        options: widget.controller.modelOptions,
                        selected: _models,
                        onChanged: (next) => setState(() => _models = next),
                      ),
                      const SizedBox(height: 18),
                      _SectionTitle(
                        openHandLocalizedText(
                          context,
                          zh: '项目文件',
                          zhHant: '專案檔案',
                          en: 'Project Files',
                          fr: 'Fichiers du projet',
                          de: 'Projektdateien',
                          ja: 'プロジェクトファイル',
                        ),
                        icon: Icons.folder_open_rounded,
                      ),
                      _ResponsiveFields(
                        twoColumns: twoColumns,
                        children: [
                          _TextFieldSpec(
                            label: openHandLocalizedText(
                              context,
                              zh: '单文件最大(MB)',
                              zhHant: '單檔最大(MB)',
                              en: 'Max file size (MB)',
                              fr: 'Taille max du fichier (Mo)',
                              de: 'Max. Dateigröße (MB)',
                              ja: '最大ファイルサイズ(MB)',
                            ),
                            controller: _workspaceFileMaxMbController,
                            keyboardType: TextInputType.number,
                          ),
                          _TextFieldSpec(
                            label: openHandLocalizedText(
                              context,
                              zh: '允许扩展名(空=全部文本)',
                              zhHant: '允許副檔名(空=全部文字)',
                              en: 'Allowed extensions (empty = all text)',
                              fr: 'Extensions autorisées (vide = tout texte)',
                              de: 'Erlaubte Endungen (leer = alle Texte)',
                              ja: '許可拡張子(空欄=すべてのテキスト)',
                            ),
                            controller: _workspaceFileExtensionsController,
                          ),
                          _TextFieldSpec(
                            label: openHandLocalizedText(
                              context,
                              zh: '上传缓存保留天数',
                              zhHant: '上傳快取保留天數',
                              en: 'Upload cache retention days',
                              fr: 'Jours de rétention du cache',
                              de: 'Aufbewahrungstage für Upload-Cache',
                              ja: 'アップロードキャッシュ保持日数',
                            ),
                            controller: _uploadCacheRetentionDaysController,
                            keyboardType: TextInputType.number,
                          ),
                          _TextFieldSpec(
                            label: openHandLocalizedText(
                              context,
                              zh: '上传缓存上限(MB)',
                              zhHant: '上傳快取上限(MB)',
                              en: 'Upload cache limit (MB)',
                              fr: 'Limite du cache d’envoi (Mo)',
                              de: 'Limit für Upload-Cache (MB)',
                              ja: 'アップロードキャッシュ上限(MB)',
                            ),
                            controller: _uploadCacheMaxMbController,
                            keyboardType: TextInputType.number,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _SectionTitle(
                        openHandLocalizedText(
                          context,
                          zh: '健康检查',
                          zhHant: '健康檢查',
                          en: 'Health Check',
                          fr: 'Contrôle de santé',
                          de: 'Integritätsprüfung',
                          ja: 'ヘルスチェック',
                        ),
                        icon: Icons.monitor_heart_outlined,
                      ),
                      _SwitchTile(
                        label: openHandLocalizedText(
                          context,
                          zh: '是否跟随重定向',
                          zhHant: '是否跟隨重新導向',
                          en: 'Follow redirects',
                          fr: 'Suivre les redirections',
                          de: 'Weiterleitungen folgen',
                          ja: 'リダイレクトを追跡',
                        ),
                        value: _healthFollowRedirects,
                        onChanged: (v) =>
                            setState(() => _healthFollowRedirects = v),
                      ),
                      const SizedBox(height: 12),
                      _ResponsiveFields(
                        twoColumns: twoColumns,
                        children: [
                          _TextFieldSpec(
                            label: openHandLocalizedText(
                              context,
                              zh: '请求 URL',
                              zhHant: '請求 URL',
                              en: 'Request URL',
                              fr: 'URL de requête',
                              de: 'Anfrage-URL',
                              ja: 'リクエストURL',
                            ),
                            controller: _healthPathController,
                          ),
                          _TextFieldSpec(
                            label: openHandLocalizedText(
                              context,
                              zh: '请求方式',
                              zhHant: '請求方式',
                              en: 'Request method',
                              fr: 'Méthode de requête',
                              de: 'Anfragemethode',
                              ja: 'リクエスト方式',
                            ),
                            controller: _healthMethodController,
                          ),
                          _TextFieldSpec(
                            label: openHandLocalizedText(
                              context,
                              zh: '超时时间(ms)',
                              zhHant: '逾時時間(ms)',
                              en: 'Timeout (ms)',
                              fr: 'Délai d’attente (ms)',
                              de: 'Timeout (ms)',
                              ja: 'タイムアウト(ms)',
                            ),
                            controller: _healthTimeoutController,
                            keyboardType: TextInputType.number,
                          ),
                          _TextFieldSpec(
                            label: openHandLocalizedText(
                              context,
                              zh: '期望状态码',
                              zhHant: '期望狀態碼',
                              en: 'Expected status code',
                              fr: 'Code d’état attendu',
                              de: 'Erwarteter Statuscode',
                              ja: '期待ステータスコード',
                            ),
                            controller: _healthStatusController,
                            keyboardType: TextInputType.number,
                          ),
                          _TextFieldSpec(
                            label: openHandLocalizedText(
                              context,
                              zh: '响应断言包含',
                              zhHant: '回應斷言包含',
                              en: 'Response must contain',
                              fr: 'La réponse doit contenir',
                              de: 'Antwort muss enthalten',
                              ja: 'レスポンスに含む文字列',
                            ),
                            controller: _healthContainsController,
                          ),
                          _TextFieldSpec(
                            label: openHandLocalizedText(
                              context,
                              zh: '查询参数(k=v&k2=v2)',
                              zhHant: '查詢參數(k=v&k2=v2)',
                              en: 'Query parameters (k=v&k2=v2)',
                              fr: 'Paramètres de requête (k=v&k2=v2)',
                              de: 'Abfrageparameter (k=v&k2=v2)',
                              ja: 'クエリパラメータ(k=v&k2=v2)',
                            ),
                            controller: _healthQueryController,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _SectionTitle(
                        openHandLocalizedText(
                          context,
                          zh: '日志轮转',
                          zhHant: '日誌輪轉',
                          en: 'Log Rotation',
                          fr: 'Rotation des journaux',
                          de: 'Protokollrotation',
                          ja: 'ログローテーション',
                        ),
                        icon: Icons.article_outlined,
                      ),
                      _ResponsiveFields(
                        twoColumns: twoColumns,
                        children: [
                          _TextFieldSpec(
                            label: openHandLocalizedText(
                              context,
                              zh: '单日志最大(MB)',
                              zhHant: '單日誌最大(MB)',
                              en: 'Max log size (MB)',
                              fr: 'Taille max d’un journal (Mo)',
                              de: 'Max. Protokollgröße (MB)',
                              ja: '最大ログサイズ(MB)',
                            ),
                            controller: _logMaxMbController,
                            keyboardType: TextInputType.number,
                          ),
                          _TextFieldSpec(
                            label: openHandLocalizedText(
                              context,
                              zh: '轮转天数',
                              zhHant: '輪轉天數',
                              en: 'Rotation days',
                              fr: 'Jours de rotation',
                              de: 'Rotationstage',
                              ja: 'ローテーション日数',
                            ),
                            controller: _logRotationDaysController,
                            keyboardType: TextInputType.number,
                          ),
                          _TextFieldSpec(
                            label: openHandLocalizedText(
                              context,
                              zh: '最多日志文件数',
                              zhHant: '最多日誌檔案數',
                              en: 'Max log files',
                              fr: 'Nombre max de fichiers journaux',
                              de: 'Max. Protokolldateien',
                              ja: '最大ログファイル数',
                            ),
                            controller: _logMaxFilesController,
                            keyboardType: TextInputType.number,
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              border: Border(
                top: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnimatedSwitcher(
                  duration: openHandMotionDurationMs(context, 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: _saveError == null
                      ? const SizedBox.shrink(key: ValueKey('save-ok'))
                      : Padding(
                          key: const ValueKey('save-error'),
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _EditorNotice(
                            icon: Icons.error_outline_rounded,
                            title: openHandLocalizedText(
                              context,
                              zh: '保存失败',
                              zhHant: '儲存失敗',
                              en: 'Save failed',
                              fr: 'Échec de l’enregistrement',
                              de: 'Speichern fehlgeschlagen',
                              ja: '保存に失敗しました',
                            ),
                            body: _saveError!,
                            error: true,
                          ),
                        ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OpenHandDialogActionButton.secondary(
                      label: openHandLocalizedText(
                        context,
                        zh: '取消',
                        zhHant: '取消',
                        en: 'Cancel',
                        fr: 'Annuler',
                        de: 'Abbrechen',
                        ja: 'キャンセル',
                      ),
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 12),
                    OpenHandDialogActionButton.primary(
                      label: _saving
                          ? openHandLocalizedText(
                              context,
                              zh: '保存中',
                              zhHant: '儲存中',
                              en: 'Saving',
                              fr: 'Enregistrement',
                              de: 'Speichern',
                              ja: '保存中',
                            )
                          : openHandLocalizedText(
                              context,
                              zh: '保存配置',
                              zhHant: '儲存設定',
                              en: 'Save configuration',
                              fr: 'Enregistrer la configuration',
                              de: 'Konfiguration speichern',
                              ja: '設定を保存',
                            ),
                      onPressed: _saving ? null : _save,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _switcherSizeFadeTransition(
    Widget child,
    Animation<double> animation,
  ) {
    if (!openHandTickerMotionEnabled(context)) return child;
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );
    return SizeTransition(
      sizeFactor: animation,
      axisAlignment: -1,
      child: FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, .04),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final config = WebMessagePlatformConfig(
      enabled: _enabled,
      autoStartOnLaunch: _autoStartOnLaunch,
      autoReloadOnChange: _autoReloadOnChange,
      description: _descriptionController.text.trim().isEmpty
          ? WebMessagePlatformConfig.defaultDescription
          : _descriptionController.text.trim(),
      listenHost: _hostController.text.trim().isEmpty
          ? '0.0.0.0'
          : _hostController.text.trim(),
      listenPort: _boundedInt(
        _portController.text,
        fallback: kWebGatewayDefaultListenPort,
        min: kWebGatewayMinListenPort,
        max: kWebGatewayMaxListenPort,
      ),
      authEnabled: _authEnabled,
      username: _usernameController.text.trim().isEmpty
          ? 'openhand'
          : _usernameController.text.trim(),
      password: _passwordController.text,
      telemetryEnabled: _telemetryEnabled,
      loggingEnabled: _loggingEnabled,
      opsEnabled: _opsEnabled,
      maxConcurrentRequests: _boundedInt(
        _maxConcurrentController.text,
        fallback: kWebGatewayDefaultMaxConcurrentRequests,
        min: kWebGatewayMinConcurrentRequests,
        max: kWebGatewayMaxConcurrentRequests,
      ),
      allowedTemplateIds: _templates.toList(growable: false),
      allowedSkillNames: _skills.toList(growable: false),
      allowedMcpServerNames: _mcpServers.toList(growable: false),
      allowedMemoryIds: _memories.toList(growable: false),
      allowedBuiltinToolNames: _normalizedBuiltinToolsForSave().toList(
        growable: false,
      ),
      allowedInstructionIds: _instructions.toList(growable: false),
      allowedAgentIds: _normalizedAgentIdsForSave(),
      allowedMessageTypes: _messageTypes,
      allowedConversationModes: _modes,
      allowedModelKeys: _models.toList(growable: false),
      planModeEnabled: _planModeEnabled,
      agentsEnabled: _agentsEnabled,
      knowledgeBaseEnabled: _knowledgeBaseEnabled,
      readAloudEnabled: _readAloudEnabled,
      translationEnabled: _translationEnabled,
      feedbackEnabled: _feedbackEnabled,
      regenerationEnabled: _regenerationEnabled,
      singleMessageTokenLimit: _boundedInt(
        _singleMessageController.text,
        fallback: kWebGatewayDefaultSingleMessageTokenLimit,
        min: kWebGatewayMinSingleMessageTokenLimit,
        max: kWebGatewayMaxSingleMessageTokenLimit,
      ),
      maxMessagesPerSession: _boundedInt(
        _maxMessagesController.text,
        fallback: kWebGatewayDefaultMaxMessagesPerSession,
        min: kWebGatewayMinMessagesPerSession,
        max: kWebGatewayMaxMessagesPerSession,
      ),
      sessionManagementEnabled: _sessionManagementEnabled,
      workspaceFileWriteEnabled: _workspaceFileWriteEnabled,
      workspaceFileMaxBytes: _boundedMegabytesAsBytes(
        _workspaceFileMaxMbController.text,
        fallbackBytes: kWebGatewayDefaultWorkspaceFileMaxBytes,
        minBytes: kWebGatewayMinWorkspaceFileMaxBytes,
        maxBytes: kWebGatewayMaxWorkspaceFileMaxBytes,
      ),
      workspaceFileAllowedExtensions:
          webGatewayNormalizeWorkspaceFileExtensions(
            _workspaceFileExtensionsController.text,
          ),
      uploadCacheRetentionDays: _boundedInt(
        _uploadCacheRetentionDaysController.text,
        fallback: kWebGatewayDefaultUploadCacheRetentionDays,
        min: kWebGatewayMinUploadCacheRetentionDays,
        max: kWebGatewayMaxUploadCacheRetentionDays,
      ),
      uploadCacheMaxBytes: _boundedMegabytesAsBytes(
        _uploadCacheMaxMbController.text,
        fallbackBytes: kWebGatewayDefaultUploadCacheMaxBytes,
        minBytes: kWebGatewayMinUploadCacheMaxBytes,
        maxBytes: kWebGatewayMaxUploadCacheMaxBytes,
      ),
      healthCheck: WebGatewayHealthCheckConfig(
        enabled: _healthEnabled,
        path: _healthPathController.text.trim().isEmpty
            ? '/api/health'
            : _healthPathController.text.trim(),
        method: _healthMethodController.text.trim().isEmpty
            ? 'GET'
            : _healthMethodController.text.trim().toUpperCase(),
        timeoutMs: _boundedInt(
          _healthTimeoutController.text,
          fallback: kWebGatewayDefaultHealthTimeoutMs,
          min: kWebGatewayMinHealthTimeoutMs,
          max: kWebGatewayMaxHealthTimeoutMs,
        ),
        expectedStatusCode: _boundedInt(
          _healthStatusController.text,
          fallback: kWebGatewayDefaultHealthStatusCode,
          min: kWebGatewayMinHealthStatusCode,
          max: kWebGatewayMaxHealthStatusCode,
        ),
        responseContains: _healthContainsController.text.trim(),
        queryParameters: _parseQueryParameters(_healthQueryController.text),
        followRedirects: _healthFollowRedirects,
      ),
      logConfig: WebGatewayLogConfig(
        fileMaxBytes: _boundedMegabytesAsBytes(
          _logMaxMbController.text,
          fallbackBytes: kWebGatewayDefaultLogFileMaxBytes,
          minBytes: kWebGatewayMinLogFileMaxBytes,
          maxBytes: kWebGatewayMaxLogFileMaxBytes,
        ),
        rotationDays: _boundedInt(
          _logRotationDaysController.text,
          fallback: kWebGatewayDefaultLogRotationDays,
          min: kWebGatewayMinLogRotationDays,
          max: kWebGatewayMaxLogRotationDays,
        ),
        maxFiles: _boundedInt(
          _logMaxFilesController.text,
          fallback: kWebGatewayDefaultLogMaxFiles,
          min: kWebGatewayMinLogMaxFiles,
          max: kWebGatewayMaxLogMaxFiles,
        ),
      ),
    );
    try {
      await widget.controller.saveConfig(config);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      showOpenHandSnackBar(
        context,
        OpenHandSnackBar.error(
          context,
          openHandLocalizedText(
            context,
            zh: '保存失败: $error',
            zhHant: '儲存失敗: $error',
            en: 'Save failed: $error',
            fr: 'Échec de l’enregistrement : $error',
            de: 'Speichern fehlgeschlagen: $error',
            ja: '保存に失敗しました: $error',
          ),
        ),
      );
      setState(() {
        _saveError = '$error';
        _saving = false;
      });
    }
  }

  List<String> get _visibleBuiltinToolNames {
    final names = widget.controller.builtinToolNames;
    if (_knowledgeBaseEnabled) return names;
    return names
        .where((name) => !_isKnowledgeBaseBuiltinToolName(name))
        .toList(growable: false);
  }

  Set<String> get _knowledgeBaseBuiltinToolNameSet => <String>{
    ...webGatewayKnowledgeBaseBuiltinToolNames,
    ...widget.controller.knowledgeBaseBuiltinToolNames,
  };

  bool _isKnowledgeBaseBuiltinToolName(String name) {
    if (webGatewayIsKnowledgeBaseBuiltinToolName(name)) return true;
    return _knowledgeBaseBuiltinToolNameSet.contains(name);
  }

  void _setKnowledgeBaseEnabled(bool value) {
    setState(() {
      _knowledgeBaseEnabled = value;
      if (!value) {
        _tools = _toolsWithoutKnowledgeBase(_tools);
      }
    });
  }

  Set<String> _normalizedBuiltinToolsForSave() {
    if (_knowledgeBaseEnabled) return _tools;
    return _toolsWithoutKnowledgeBase(_tools);
  }

  Set<String> _effectiveAgentIdsForDisplay() {
    final optionIds = widget.controller.agentOptions
        .map((option) => option.id)
        .toSet();
    if (optionIds.isEmpty ||
        _isExplicitNone(_agents, webGatewayDenyAllSelectionMarker)) {
      return <String>{};
    }
    if (_agents.isEmpty) return optionIds;
    return _agents.intersection(optionIds);
  }

  void _setEffectiveAgentIds(Set<String> values) {
    final optionIds = widget.controller.agentOptions
        .map((option) => option.id)
        .toSet();
    setState(() {
      if (values.isEmpty) {
        _agents = <String>{webGatewayDenyAllSelectionMarker};
      } else if (optionIds.isNotEmpty && values.length == optionIds.length) {
        _agents = <String>{};
      } else {
        _agents = values.intersection(optionIds);
      }
    });
  }

  List<String> _normalizedAgentIdsForSave() {
    final optionIds = widget.controller.agentOptions
        .map((option) => option.id)
        .toSet();
    if (optionIds.isEmpty) return _agents.toList(growable: false);
    if (_isExplicitNone(_agents, webGatewayDenyAllSelectionMarker)) {
      return const <String>[webGatewayDenyAllSelectionMarker];
    }
    final selected = _effectiveAgentIdsForDisplay();
    if (selected.isEmpty) {
      return const <String>[webGatewayDenyAllSelectionMarker];
    }
    if (selected.length == optionIds.length) return const <String>[];
    return selected.toList(growable: false);
  }

  Set<String> _toolsWithoutKnowledgeBase(Set<String> source) {
    if (source.isEmpty ||
        _isExplicitNone(source, webGatewayDenyAllSelectionMarker)) {
      return Set<String>.from(source);
    }
    final next = source
        .where((name) => !_isKnowledgeBaseBuiltinToolName(name))
        .toSet();
    return next.isEmpty ? <String>{webGatewayDenyAllSelectionMarker} : next;
  }
}

class _EditorNotice extends StatelessWidget {
  const _EditorNotice({
    required this.icon,
    required this.title,
    required this.body,
    this.error = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = error ? colorScheme.error : colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.labelLarge),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentExposurePanel extends StatelessWidget {
  const _AgentExposurePanel({
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<WebGatewayAgentOption> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final optionIds = options.map((option) => option.id).toSet();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: .46),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.primary.withValues(alpha: .24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: .74),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  Icons.smart_toy_outlined,
                  size: 18,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      openHandLocalizedText(
                        context,
                        zh: '可暴露给 Web 的智能体',
                        zhHant: '可暴露給 Web 的智能體',
                        en: 'Agents exposed to Web',
                        fr: 'Agents exposés au Web',
                        de: 'Für Web freigegebene Agenten',
                        ja: 'Webに公開するエージェント',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      options.isEmpty
                          ? openHandLocalizedText(
                              context,
                              zh: '暂无可用智能体',
                              zhHant: '暫無可用智能體',
                              en: 'No available agents',
                              fr: 'Aucun agent disponible',
                              de: 'Keine Agenten verfügbar',
                              ja: '利用可能なエージェントなし',
                            )
                          : _gatewaySelectedCount(
                              context,
                              selected.length,
                              options.length,
                            ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _GatewayRoundIconActionButton(
                tooltip: openHandLocalizedText(
                  context,
                  zh: '全选',
                  zhHant: '全選',
                  en: 'Select all',
                  fr: 'Tout sélectionner',
                  de: 'Alle auswählen',
                  ja: 'すべて選択',
                ),
                icon: Icons.done_all_rounded,
                onPressed: options.isEmpty ? null : () => onChanged(optionIds),
              ),
              const SizedBox(width: 8),
              _GatewayRoundIconActionButton(
                tooltip: openHandLocalizedText(
                  context,
                  zh: '全不选',
                  zhHant: '全不選',
                  en: 'Deselect all',
                  fr: 'Tout désélectionner',
                  de: 'Alle abwählen',
                  ja: 'すべて解除',
                ),
                icon: Icons.remove_done_rounded,
                onPressed: options.isEmpty
                    ? null
                    : () => onChanged(const <String>{}),
              ),
            ],
          ),
          if (options.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in options)
                  _AgentExposureChip(
                    option: option,
                    selected: selected.contains(option.id),
                    onTap: () {
                      final next = Set<String>.from(selected);
                      if (!next.add(option.id)) next.remove(option.id);
                      onChanged(next);
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AgentExposureChip extends StatelessWidget {
  const _AgentExposureChip({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final WebGatewayAgentOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tooltip = option.subtitle.isEmpty
        ? option.label
        : '${option.label} · ${option.subtitle}';
    return Tooltip(
      message: tooltip,
      child: AnimatedContainer(
        duration: openHandMotionDurationMs(context, 160),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primaryContainer.withValues(alpha: .82)
              : colorScheme.surfaceContainerHighest.withValues(alpha: .72),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? colorScheme.primary.withValues(alpha: .42)
                : colorScheme.outlineVariant,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(10, 7, 12, 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSwitcher(
                    duration: openHandMotionDurationMs(context, 140),
                    child: Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      key: ValueKey<bool>(selected),
                      size: 16,
                      color: selected
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 7),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(
                      option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: selected
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WebGatewayConnectivityDialog extends StatefulWidget {
  const _WebGatewayConnectivityDialog({required this.controller});

  final MessageGatewayController controller;

  @override
  State<_WebGatewayConnectivityDialog> createState() =>
      _WebGatewayConnectivityDialogState();
}

class _WebGatewayConnectivityDialogState
    extends State<_WebGatewayConnectivityDialog> {
  WebGatewayConnectivityTestResult? _result;
  Object? _error;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await widget.controller.runConnectivityTest();
      if (!mounted) return;
      setState(() => _result = result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final result = _result;
    final error = _error;

    return buildOpenHandResponsiveDialogShell(
      context: context,
      maxWidth: 920,
      maxHeight: 700,
      minAvailableHeight: 420,
      minHeight: 480,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 8, 12),
            child: Row(
              children: [
                Icon(
                  Icons.network_check_rounded,
                  color: result == null
                      ? colorScheme.primary
                      : result.ok
                      ? const Color(0xFF16A34A)
                      : colorScheme.error,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        openHandLocalizedText(
                          context,
                          zh: '端口连通性测试',
                          zhHant: '連接埠連通性測試',
                          en: 'Port connectivity test',
                          fr: 'Test de connectivité du port',
                          de: 'Port-Konnektivitätstest',
                          ja: 'ポート接続テスト',
                        ),
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        openHandLocalizedText(
                          context,
                          zh: '逐一探测当前可用 IP + 端口入口的 /api/health',
                          zhHant: '逐一探測目前可用 IP + 連接埠入口的 /api/health',
                          en: 'Probe /api/health for each available IP + port entry',
                          fr: 'Sonde /api/health pour chaque entrée IP + port disponible',
                          de: '/api/health für jeden verfügbaren IP- und Port-Eintrag prüfen',
                          ja: '利用可能なIP + ポート入口ごとに /api/health を検査',
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    IconButton.filledTonal(
                      tooltip: openHandLocalizedText(
                        context,
                        zh: '复制结果 JSON',
                        zhHant: '複製結果 JSON',
                        en: 'Copy result JSON',
                        fr: 'Copier le JSON du résultat',
                        de: 'Ergebnis-JSON kopieren',
                        ja: '結果JSONをコピー',
                      ),
                      onPressed: result == null
                          ? null
                          : () => _copyResult(result),
                      icon: const Icon(Icons.content_copy_rounded),
                    ),
                    IconButton.filledTonal(
                      tooltip: openHandLocalizedText(
                        context,
                        zh: '重新测试',
                        zhHant: '重新測試',
                        en: 'Test again',
                        fr: 'Relancer le test',
                        de: 'Erneut testen',
                        ja: '再テスト',
                      ),
                      onPressed: _running ? null : _run,
                      icon: _running
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                    ),
                    IconButton.filledTonal(
                      tooltip: openHandLocalizedText(
                        context,
                        zh: '关闭',
                        zhHant: '關閉',
                        en: 'Close',
                        fr: 'Fermer',
                        de: 'Schließen',
                        ja: '閉じる',
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: AnimatedSwitcher(
              duration: openHandMotionDurationMs(context, 260),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeInCubic,
              child: error != null
                  ? _ConnectivityErrorView(error: error)
                  : result == null
                  ? const _ConnectivityLoadingView()
                  : _ConnectivityResultView(result: result),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copyResult(WebGatewayConnectivityTestResult result) async {
    await copyMessageGatewayTextToClipboard(
      context: context,
      text: prettyPrintJson(result.toJson()),
      successMessage: openHandLocalizedText(
        context,
        zh: '连通性测试结果已复制',
        zhHant: '連通性測試結果已複製',
        en: 'Connectivity test result copied',
        fr: 'Résultat du test de connectivité copié',
        de: 'Konnektivitätstestergebnis kopiert',
        ja: '接続テスト結果をコピーしました',
      ),
      logAction: 'copy connectivity test result',
      successDuration: const Duration(milliseconds: 1600),
    );
  }
}

class _ConnectivityLoadingView extends StatelessWidget {
  const _ConnectivityLoadingView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            openHandLocalizedText(
              context,
              zh: '正在检测全部可访问入口',
              zhHant: '正在檢測全部可存取入口',
              en: 'Checking all accessible entries',
              fr: 'Vérification de toutes les entrées accessibles',
              de: 'Alle erreichbaren Einträge werden geprüft',
              ja: 'すべてのアクセス可能な入口を確認中',
            ),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          Text(
            openHandLocalizedText(
              context,
              zh: '会按当前运行时 URL 顺序逐个探测并汇总结果',
              zhHant: '會依目前執行時 URL 順序逐個探測並彙總結果',
              en: 'Entries are probed in runtime URL order and summarized',
              fr: 'Les entrées sont sondées dans l’ordre des URL d’exécution puis résumées',
              de: 'Einträge werden in Laufzeit-URL-Reihenfolge geprüft und zusammengefasst',
              ja: '実行時URLの順序で順番に検査して結果を集計します',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectivityErrorView extends StatelessWidget {
  const _ConnectivityErrorView({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          openHandLocalizedText(
            context,
            zh: '测试启动失败: $error',
            zhHant: '測試啟動失敗: $error',
            en: 'Test failed to start: $error',
            fr: 'Échec du démarrage du test : $error',
            de: 'Test konnte nicht gestartet werden: $error',
            ja: 'テストを開始できませんでした: $error',
          ),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ),
    );
  }
}

class _ConnectivityResultView extends StatelessWidget {
  const _ConnectivityResultView({required this.result});

  final WebGatewayConnectivityTestResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return SingleChildScrollView(
      primary: false,
      physics: kOpenHandClampingPhysics,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: (result.ok ? const Color(0xFF16A34A) : colorScheme.error)
                  .withValues(alpha: .10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: (result.ok ? const Color(0xFF16A34A) : colorScheme.error)
                    .withValues(alpha: .35),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  result.ok
                      ? Icons.check_circle_outline_rounded
                      : Icons.error_outline_rounded,
                  color: result.ok
                      ? const Color(0xFF16A34A)
                      : colorScheme.error,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(result.summary, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        openHandLocalizedText(
                          context,
                          zh: '${formatYearMonthDayHms(result.startedAt.toLocal())} · 总耗时 ${result.durationMs}ms',
                          zhHant:
                              '${formatYearMonthDayHms(result.startedAt.toLocal())} · 總耗時 ${result.durationMs}ms',
                          en: '${formatYearMonthDayHms(result.startedAt.toLocal())} · Total ${result.durationMs}ms',
                          fr: '${formatYearMonthDayHms(result.startedAt.toLocal())} · Total ${result.durationMs}ms',
                          de: '${formatYearMonthDayHms(result.startedAt.toLocal())} · Gesamt ${result.durationMs}ms',
                          ja: '${formatYearMonthDayHms(result.startedAt.toLocal())} · 合計 ${result.durationMs}ms',
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 720 ? 2 : 4;
              return GridView.count(
                crossAxisCount: columns,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: columns == 2 ? 2.6 : 2.8,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _MetricTile(
                    label: openHandLocalizedText(
                      context,
                      zh: '入口总数',
                      zhHant: '入口總數',
                      en: 'Entries',
                      fr: 'Entrées',
                      de: 'Einträge',
                      ja: '入口数',
                    ),
                    value: '${result.targets.length}',
                  ),
                  _MetricTile(
                    label: openHandLocalizedText(
                      context,
                      zh: '连通',
                      zhHant: '連通',
                      en: 'Reachable',
                      fr: 'Joignables',
                      de: 'Erreichbar',
                      ja: '接続可',
                    ),
                    value: '${result.successCount}',
                  ),
                  _MetricTile(
                    label: openHandLocalizedText(
                      context,
                      zh: '失败',
                      zhHant: '失敗',
                      en: 'Failed',
                      fr: 'Échecs',
                      de: 'Fehlgeschlagen',
                      ja: '失敗',
                    ),
                    value: '${result.failureCount}',
                  ),
                  _MetricTile(
                    label: openHandLocalizedText(
                      context,
                      zh: '总耗时',
                      zhHant: '總耗時',
                      en: 'Total time',
                      fr: 'Temps total',
                      de: 'Gesamtzeit',
                      ja: '合計時間',
                    ),
                    value: '${result.durationMs}ms',
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          _SectionTitle(
            openHandLocalizedText(
              context,
              zh: '入口探测结果',
              zhHant: '入口探測結果',
              en: 'Entry Probe Results',
              fr: 'Résultats des sondes',
              de: 'Ergebnisse der Eintragsprüfung',
              ja: '入口検査結果',
            ),
            icon: Icons.monitor_heart_outlined,
          ),
          if (result.targets.isEmpty)
            Text(
              openHandLocalizedText(
                context,
                zh: '当前服务没有可测试入口。请先启动 Web 通用消息平台服务。',
                zhHant: '目前服務沒有可測試入口。請先啟動 Web 通用訊息平台服務。',
                en: 'The current service has no testable entries. Start the web message platform service first.',
                fr: 'Le service actuel n’a aucune entrée testable. Démarrez d’abord la passerelle web.',
                de: 'Der aktuelle Dienst hat keine testbaren Einträge. Starten Sie zuerst den Webnachrichtendienst.',
                ja: '現在のサービスにはテスト可能な入口がありません。先にWebメッセージプラットフォームサービスを起動してください。',
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            )
          else
            for (var index = 0; index < result.targets.length; index++)
              _ConnectivityTargetCard(
                target: result.targets[index],
                index: index,
              ),
          const SizedBox(height: 18),
          _SectionTitle(
            openHandLocalizedText(
              context,
              zh: '测试流程日志',
              zhHant: '測試流程日誌',
              en: 'Test Flow Logs',
              fr: 'Journaux du test',
              de: 'Testablauf-Protokolle',
              ja: 'テストフローログ',
            ),
            icon: Icons.article_outlined,
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF101218),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: SelectableText(
              result.logs.isEmpty
                  ? openHandLocalizedText(
                      context,
                      zh: '暂无流程日志',
                      zhHant: '暫無流程日誌',
                      en: 'No flow logs yet',
                      fr: 'Aucun journal de test',
                      de: 'Noch keine Ablaufprotokolle',
                      ja: 'フローログはまだありません',
                    )
                  : result.logs.join('\n'),
              style: const TextStyle(
                fontFamily: 'Menlo',
                fontSize: 12,
                height: 1.45,
                color: Color(0xFFE5E7EB),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectivityTargetCard extends StatelessWidget {
  const _ConnectivityTargetCard({required this.target, required this.index});

  final WebGatewayConnectivityProbeResult target;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final stateColor = target.ok ? const Color(0xFF16A34A) : colorScheme.error;
    final content = Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: .42),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: stateColor.withValues(alpha: .32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                target.ok
                    ? Icons.check_circle_outline_rounded
                    : Icons.error_outline_rounded,
                size: 20,
                color: stateColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  target.hostPort,
                  style: theme.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${target.durationMs}ms',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            target.endpointUrl,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(
                icon: Icons.http_rounded,
                label: 'HTTP ${target.statusCode}',
              ),
              _InfoChip(
                icon: Icons.timer_outlined,
                label: '${target.durationMs}ms',
              ),
              _InfoChip(icon: Icons.dns_outlined, label: target.baseUrl),
            ],
          ),
          if (target.errorMessage.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              target.errorMessage,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.error,
              ),
            ),
          ],
          if (target.bodyPreview.isNotEmpty) ...[
            const SizedBox(height: 8),
            _StructuredResponsePreview(raw: target.bodyPreview),
          ],
        ],
      ),
    );
    if (!openHandTickerMotionEnabled(context)) return content;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 220 + math.min(index, 6) * 30),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Opacity(
          opacity: clampUnitInterval(value),
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 10),
            child: child,
          ),
        );
      },
      child: content,
    );
  }
}

class _StructuredResponsePreview extends StatelessWidget {
  const _StructuredResponsePreview({required this.raw});

  final String raw;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final decoded = _tryDecodeJson(raw);
    final entries = decoded is Map
        ? decoded.entries.toList(growable: false)
        : const <MapEntry<Object?, Object?>>[];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.data_object_rounded,
                size: 16,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                openHandLocalizedText(
                  context,
                  zh: '响应数据',
                  zhHant: '回應資料',
                  en: 'Response data',
                  fr: 'Données de réponse',
                  de: 'Antwortdaten',
                  ja: 'レスポンスデータ',
                ),
                style: theme.textTheme.labelLarge,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (entries.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in entries)
                  _ResponseFieldChip(
                    label: '${entry.key}',
                    value: _formatStructuredValue(entry.value),
                  ),
              ],
            )
          else
            SelectableText(
              raw,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontFamily: 'Menlo',
              ),
            ),
        ],
      ),
    );
  }
}

class _ResponseFieldChip extends StatelessWidget {
  const _ResponseFieldChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 132, maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: .50),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            maxLines: 4,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface,
              fontFamily: 'Menlo',
            ),
          ),
        ],
      ),
    );
  }
}

class _WebGatewayLogDialog extends StatefulWidget {
  const _WebGatewayLogDialog({required this.controller});

  final MessageGatewayController controller;

  @override
  State<_WebGatewayLogDialog> createState() => _WebGatewayLogDialogState();
}

class _WebGatewayLogDialogState extends State<_WebGatewayLogDialog> {
  final ScrollController _scrollController = ScrollController();
  final AutoFollowScrollGuard _scrollGuard = AutoFollowScrollGuard();
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  final Set<WebGatewayLogLevel> _hidden = <WebGatewayLogLevel>{};
  final List<WebGatewayLogEntry> _rendered = <WebGatewayLogEntry>[];
  final Set<int> _renderedIds = <int>{};
  bool _follow = true;
  int _anchorLogId = 0;
  int _historyLimit = 0;
  int _lastPageSize = 60;
  int _renderedFingerprint = 0;
  int _pendingRenderedFingerprint = 0;
  List<WebGatewayLogEntry> _pendingRenderedTarget =
      const <WebGatewayLogEntry>[];
  bool _syncScheduled = false;
  bool _isExportingLog = false;

  @override
  void initState() {
    super.initState();
    final logs = widget.controller.logs;
    _anchorLogId = logs.isEmpty ? 0 : logs.last.id;
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    if (_follow) _scrollToBottomSoon();
  }

  @override
  Widget build(BuildContext context) {
    final logs = widget.controller.logs;
    final mediaSize = MediaQuery.sizeOf(context);
    final dialogMaxHeight = resolveOpenHandResponsiveDialogExtent(
      viewportExtent: mediaSize.height,
      maxExtent: 680,
      viewportMargin: 120,
    );
    _lastPageSize = _logPageSize(dialogMaxHeight);
    final visible = _visibleLogs(logs);
    final historicalCount = logs
        .where(
          (entry) => entry.id <= _anchorLogId && !_hidden.contains(entry.level),
        )
        .length;
    _scheduleRenderedSync(visible);
    return buildOpenHandResponsiveDialogShell(
      context: context,
      maxWidth: 960,
      maxHeight: 680,
      minHeight: 480,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 8, 10),
            child: Row(
              children: [
                const Icon(Icons.terminal_rounded),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    openHandLocalizedText(
                      context,
                      zh: 'Web 服务日志',
                      zhHant: 'Web 服務日誌',
                      en: 'Web service logs',
                      fr: 'Journaux du service web',
                      de: 'Webdienste-Protokolle',
                      ja: 'Webサービスログ',
                    ),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    IconButton(
                      tooltip: openHandLocalizedText(
                        context,
                        zh: '加载历史更多',
                        zhHant: '載入更多歷史',
                        en: 'Load more history',
                        fr: 'Charger plus d’historique',
                        de: 'Mehr Verlauf laden',
                        ja: '履歴をさらに読み込む',
                      ),
                      onPressed: historicalCount > _historyLimit
                          ? () => setState(() => _historyLimit += _lastPageSize)
                          : null,
                      icon: const Icon(Icons.history_rounded),
                    ),
                    IconButton(
                      tooltip: openHandLocalizedText(
                        context,
                        zh: '加载最新日志',
                        zhHant: '載入最新日誌',
                        en: 'Load latest logs',
                        fr: 'Charger les derniers journaux',
                        de: 'Neueste Protokolle laden',
                        ja: '最新ログを読み込む',
                      ),
                      onPressed: _loadLatestLogs,
                      icon: const Icon(Icons.new_releases_outlined),
                    ),
                    IconButton(
                      tooltip: _follow
                          ? openHandLocalizedText(
                              context,
                              zh: '取消跟随',
                              zhHant: '取消跟隨',
                              en: 'Stop following',
                              fr: 'Arrêter le suivi',
                              de: 'Folgen beenden',
                              ja: '追従を停止',
                            )
                          : openHandLocalizedText(
                              context,
                              zh: '跟随日志',
                              zhHant: '跟隨日誌',
                              en: 'Follow logs',
                              fr: 'Suivre les journaux',
                              de: 'Protokollen folgen',
                              ja: 'ログに追従',
                            ),
                      onPressed: () => setState(() => _follow = !_follow),
                      icon: Icon(
                        _follow
                            ? Icons.vertical_align_bottom_rounded
                            : Icons.vertical_align_center_rounded,
                      ),
                    ),
                    IconButton(
                      tooltip: openHandLocalizedText(
                        context,
                        zh: '保存日志到剪贴板',
                        zhHant: '儲存日誌到剪貼簿',
                        en: 'Copy logs to clipboard',
                        fr: 'Copier les journaux',
                        de: 'Protokolle in Zwischenablage kopieren',
                        ja: 'ログをクリップボードへコピー',
                      ),
                      onPressed: () => _copyLogs(visible),
                      icon: const Icon(Icons.content_copy_rounded),
                    ),
                    IconButton(
                      tooltip: openHandLocalizedText(
                        context,
                        zh: '导出当前日志',
                        zhHant: '匯出目前日誌',
                        en: 'Export current logs',
                        fr: 'Exporter les journaux actuels',
                        de: 'Aktuelle Protokolle exportieren',
                        ja: '現在のログをエクスポート',
                      ),
                      onPressed: _isExportingLog ? null : _exportCurrentLog,
                      icon: _isExportingLog
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_alt_rounded),
                    ),
                    // 清空终端：仅清除当前弹窗内的渲染项，
                    // 底层服务的日志环形缓冲与磁盘文件保持不变（类似 shell `clear`）。
                    IconButton(
                      tooltip: openHandLocalizedText(
                        context,
                        zh: '清空终端（仅清除显示，不删除日志文件）',
                        zhHant: '清空終端（僅清除顯示，不刪除日誌檔案）',
                        en: 'Clear terminal display only',
                        fr: 'Effacer seulement l’affichage du terminal',
                        de: 'Nur Terminalanzeige leeren',
                        ja: '端末表示のみクリア',
                      ),
                      onPressed: _clearTerminal,
                      icon: const Icon(Icons.cleaning_services_outlined),
                    ),
                    // 日志级别多选菜单：取代原来顶部的 FilterChip 条，并走
                    // OpenHand 共用菜单转场，让 App / Web 服务面板的进退场手感一致。
                    AnimatedPopupMenuButton<WebGatewayLogLevel>(
                      tooltip: openHandLocalizedText(
                        context,
                        zh: '日志级别筛选',
                        zhHant: '日誌級別篩選',
                        en: 'Filter log levels',
                        fr: 'Filtrer les niveaux de journal',
                        de: 'Protokollstufen filtern',
                        ja: 'ログレベルを絞り込む',
                      ),
                      icon: const Icon(Icons.filter_list_rounded),
                      // 返回 null 代表点击了外部区域 / Esc，不需要响应。
                      onSelected: (level) =>
                          setState(() => _toggleLogLevel(level)),
                      // 多选能力：在 itemBuilder 里手搽复选框，
                      // 点击任一项都在 onSelected 里进行反选。
                      itemBuilder: (menuContext) => WebGatewayLogLevel.values
                          .map(
                            (level) => CheckedPopupMenuItem<WebGatewayLogLevel>(
                              value: level,
                              checked: !_hidden.contains(level),
                              child: Text(level.name),
                            ),
                          )
                          .toList(growable: false),
                    ),
                    IconButton(
                      tooltip: openHandLocalizedText(
                        context,
                        zh: '关闭',
                        zhHant: '關閉',
                        en: 'Close',
                        fr: 'Fermer',
                        de: 'Schließen',
                        ja: '閉じる',
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Container(
              color: const Color(0xFF101218),
              child: NotificationListener<ScrollNotification>(
                onNotification: _scrollGuard.handleNotification,
                child: OpenHandSafeScrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: AnimatedList(
                    key: _listKey,
                    initialItemCount: _rendered.length,
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                    itemBuilder: (context, index, animation) =>
                        _AnimatedLogLine(
                          entry: _rendered[index],
                          animation: animation,
                        ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 在 _hidden 集合中切换一个级别的可见性。
  // 保证至少保留一个级别可见，避免用户误操作后看到空列表。
  void _toggleLogLevel(WebGatewayLogLevel level) {
    if (_hidden.contains(level)) {
      _hidden.remove(level);
      return;
    }
    final wouldHideAll = _hidden.length + 1 >= WebGatewayLogLevel.values.length;
    if (wouldHideAll) return;
    _hidden.add(level);
  }

  // 清空终端：仅清零当前弹窗内的渲染项。
  // 使用 _anchorLogId = 当前最后一条日志的 id，以后只追加新增日志；
  // _historyLimit 归 0，避免下一次渲染又把历史记录拉回来。
  // 底层 service.logs 与磁盘日志文件都不动，效果类似 shell `clear`。
  void _clearTerminal() {
    final logs = widget.controller.logs;
    setState(() {
      _anchorLogId = logs.isEmpty ? 0 : logs.last.id;
      _historyLimit = 0;
    });
    showOpenHandSnackBar(
      context,
      OpenHandSnackBar.success(
        context,
        openHandLocalizedText(
          context,
          zh: '终端显示已清空，底层日志文件保持不变',
          zhHant: '終端顯示已清空，底層日誌檔案保持不變',
          en: 'Terminal display cleared; log files are unchanged',
          fr: 'Affichage effacé ; les fichiers journaux sont inchangés',
          de: 'Terminalanzeige geleert; Protokolldateien bleiben unverändert',
          ja: '端末表示をクリアしました。ログファイルは変更されません',
        ),
        duration: const Duration(milliseconds: 1600),
      ),
    );
  }

  List<WebGatewayLogEntry> _visibleLogs(List<WebGatewayLogEntry> logs) {
    final historical = logs
        .where(
          (entry) => entry.id <= _anchorLogId && !_hidden.contains(entry.level),
        )
        .toList(growable: false);
    final live = logs
        .where(
          (entry) => entry.id > _anchorLogId && !_hidden.contains(entry.level),
        )
        .toList(growable: false);
    final start = math.max(0, historical.length - _historyLimit);
    return <WebGatewayLogEntry>[
      if (_historyLimit > 0) ...historical.skip(start),
      ...live,
    ];
  }

  int _logFingerprint(List<WebGatewayLogEntry> logs) {
    return rollingHash30(logs, (entry) => entry.id, seed: logs.length);
  }

  void _scheduleRenderedSync(List<WebGatewayLogEntry> target) {
    final fingerprint = _logFingerprint(target);
    if (fingerprint == _renderedFingerprint && !_syncScheduled) return;
    _pendingRenderedTarget = List<WebGatewayLogEntry>.from(target);
    _pendingRenderedFingerprint = fingerprint;
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncScheduled = false;
      _renderedFingerprint = _pendingRenderedFingerprint;
      _syncRendered(_pendingRenderedTarget);
      if (_follow) _scrollToBottomSoon();
    });
  }

  void _syncRendered(List<WebGatewayLogEntry> target) {
    final listState = _listKey.currentState;
    if (listState == null) {
      setState(() {
        _rendered
          ..clear()
          ..addAll(target);
        _renderedIds
          ..clear()
          ..addAll(target.map((entry) => entry.id));
      });
      return;
    }
    final targetIds = target.map((entry) => entry.id).toSet();
    for (var index = _rendered.length - 1; index >= 0; index--) {
      final entry = _rendered[index];
      if (!targetIds.contains(entry.id)) {
        _rendered.removeAt(index);
        _renderedIds.remove(entry.id);
        listState.removeItem(
          index,
          (context, animation) => _AnimatedLogLine(
            entry: entry,
            animation: animation,
            removing: true,
          ),
          duration: openHandMotionDurationMs(context, 220),
        );
      }
    }
    for (var targetIndex = 0; targetIndex < target.length; targetIndex++) {
      final entry = target[targetIndex];
      if (_renderedIds.contains(entry.id)) continue;
      final insertIndex = math.min(targetIndex, _rendered.length);
      _rendered.insert(insertIndex, entry);
      _renderedIds.add(entry.id);
      listState.insertItem(
        insertIndex,
        duration: openHandMotionDurationMs(context, 280),
      );
    }
  }

  void _loadLatestLogs() {
    final logs = widget.controller.logs;
    setState(() {
      _anchorLogId = logs.isEmpty ? 0 : logs.last.id;
      _historyLimit = _lastPageSize;
    });
    _scrollToBottomSoon();
  }

  void _scrollToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollGuard.followToBottom(
        _scrollController,
        animated: true,
        animationDuration: openHandMotionDurationMs(context, 220),
      );
    });
  }

  Future<void> _copyLogs(List<WebGatewayLogEntry> logs) async {
    await copyMessageGatewayTextToClipboard(
      context: context,
      text: logs.map((entry) => entry.toLogLine()).join('\n'),
      successMessage: openHandLocalizedText(
        context,
        zh: '日志已保存到剪贴板',
        zhHant: '日誌已儲存到剪貼簿',
        en: 'Logs copied to clipboard',
        fr: 'Journaux copiés',
        de: 'Protokolle kopiert',
        ja: 'ログをクリップボードにコピーしました',
      ),
      logAction: 'copy gateway logs',
    );
  }

  Future<void> _exportCurrentLog() async {
    if (_isExportingLog) return;
    setState(() => _isExportingLog = true);
    final stamp = DateTime.now()
        .toLocal()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    try {
      final location = await getSaveLocation(
        suggestedName: 'openhand-web-gateway-current-$stamp.log',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Log', extensions: ['log', 'txt', 'jsonl']),
        ],
      );
      if (location == null) return;
      final text = await widget.controller.exportCurrentLogText();
      await File(location.path).writeAsString(text);
      if (!mounted) return;
      showOpenHandSnackBar(
        context,
        OpenHandSnackBar.success(
          context,
          openHandLocalizedText(
            context,
            zh: '当前日志已导出到 ${location.path}',
            zhHant: '目前日誌已匯出到 ${location.path}',
            en: 'Current logs exported to ${location.path}',
            fr: 'Journaux actuels exportés vers ${location.path}',
            de: 'Aktuelle Protokolle exportiert nach ${location.path}',
            ja: '現在のログを ${location.path} にエクスポートしました',
          ),
          maxLines: 2,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      showOpenHandSnackBar(
        context,
        OpenHandSnackBar.error(
          context,
          openHandLocalizedText(
            context,
            zh: '当前日志导出失败: $error',
            zhHant: '目前日誌匯出失敗: $error',
            en: 'Current log export failed: $error',
            fr: 'Échec de l’export des journaux : $error',
            de: 'Export der aktuellen Protokolle fehlgeschlagen: $error',
            ja: '現在のログのエクスポートに失敗しました: $error',
          ),
          maxLines: 2,
        ),
      );
    } finally {
      if (mounted) setState(() => _isExportingLog = false);
    }
  }
}

class _WebGatewayOpsDialog extends StatefulWidget {
  const _WebGatewayOpsDialog({required this.controller});

  final MessageGatewayController controller;

  @override
  State<_WebGatewayOpsDialog> createState() => _WebGatewayOpsDialogState();
}

class _WebGatewayOpsDialogState extends State<_WebGatewayOpsDialog>
    with WidgetsBindingObserver {
  static const Duration _refreshInterval = Duration(seconds: 2);
  static const Duration _refreshCallbackTimeout = Duration(seconds: 8);
  static const int _trendLimit = 40;

  final ScrollController _scrollController = ScrollController();
  Timer? _timer;
  final List<WebGatewayRuntimeSnapshot> _trend = <WebGatewayRuntimeSnapshot>[];
  bool _isCleaning = false;
  bool _isRefreshingSnapshot = false;
  bool _isServiceActing = false;
  bool _isHealthChecking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tick();
    _startTimerIfForeground();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 应用切到后台时暂停 2s 一次的 runtime snapshot 轮询；回到前台再恢复。
    // 避免后台持续走网络/IPC 拉 snapshot 浪费资源。
    if (state == AppLifecycleState.resumed) {
      _startTimerIfForeground();
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _startTimerIfForeground() {
    _timer?.cancel();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      return;
    }
    _timer = startNonOverlappingPeriodicTimer(
      _refreshInterval,
      (_) => _tick(),
      callbackTimeout: _refreshCallbackTimeout,
      onError: (error, stack) =>
          silentLog('message_gateway', 'runtime snapshot tick', error, stack),
    );
  }

  Future<void> _tick() async {
    if (!mounted || _isRefreshingSnapshot) return;
    _isRefreshingSnapshot = true;
    try {
      final snapshot = await widget.controller.refreshRuntimeSnapshot();
      if (!mounted) return;
      setState(() {
        _trend.add(snapshot);
        if (_trend.length > _trendLimit) _trend.removeAt(0);
      });
    } finally {
      _isRefreshingSnapshot = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _trend.isEmpty
        ? widget.controller.runtimeSnapshot()
        : _trend.last;
    final cleanupHistory = widget.controller.cleanupHistory.reversed
        .take(6)
        .toList(growable: false);
    final isRunning = widget.controller.isRunning;
    final isTransitioning =
        snapshot.state == WebGatewayRuntimeState.starting ||
        snapshot.state == WebGatewayRuntimeState.stopping;
    final serviceControlsDisabled = _isServiceActing || isTransitioning;
    final startLabel = openHandLocalizedText(
      context,
      zh: '开启',
      zhHant: '開啟',
      en: 'Start',
      fr: 'Démarrer',
      de: 'Starten',
      ja: '起動',
    );
    final stopLabel = openHandLocalizedText(
      context,
      zh: '关机',
      zhHant: '關機',
      en: 'Stop',
      fr: 'Arrêter',
      de: 'Stoppen',
      ja: '停止',
    );
    final restartLabel = openHandLocalizedText(
      context,
      zh: '重启',
      zhHant: '重啟',
      en: 'Restart',
      fr: 'Redémarrer',
      de: 'Neustarten',
      ja: '再起動',
    );
    final reloadLabel = openHandLocalizedText(
      context,
      zh: '配置重载',
      zhHant: '設定重載',
      en: 'Reload config',
      fr: 'Recharger la configuration',
      de: 'Konfiguration neu laden',
      ja: '設定を再読み込み',
    );
    final hotFixLabel = openHandLocalizedText(
      context,
      zh: '热修复',
      zhHant: '熱修復',
      en: 'Hotfix',
      fr: 'Correctif à chaud',
      de: 'Hotfix',
      ja: 'ホットフィックス',
    );
    final healthLabel = openHandLocalizedText(
      context,
      zh: '健康诊断',
      zhHant: '健康診斷',
      en: 'Health diagnosis',
      fr: 'Diagnostic de santé',
      de: 'Integritätsdiagnose',
      ja: 'ヘルス診断',
    );
    final expiredResourcesLabel = openHandLocalizedText(
      context,
      zh: '过期资源',
      zhHant: '過期資源',
      en: 'Expired resources',
      fr: 'Ressources expirées',
      de: 'Abgelaufene Ressourcen',
      ja: '期限切れリソース',
    );
    final logsLabel = openHandLocalizedText(
      context,
      zh: '日志',
      zhHant: '日誌',
      en: 'Logs',
      fr: 'Journaux',
      de: 'Protokolle',
      ja: 'ログ',
    );
    final uploadCacheLabel = openHandLocalizedText(
      context,
      zh: '上传缓存',
      zhHant: '上傳快取',
      en: 'Upload cache',
      fr: 'Cache d’envoi',
      de: 'Upload-Cache',
      ja: 'アップロードキャッシュ',
    );
    return buildOpenHandResponsiveDialogShell(
      context: context,
      maxWidth: 1100,
      minAvailableHeight: 420,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 8, 12),
            child: Row(
              children: [
                const Icon(Icons.speed_rounded),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    openHandLocalizedText(
                      context,
                      zh: 'Web 服务运维',
                      zhHant: 'Web 服務維運',
                      en: 'Web service operations',
                      fr: 'Opérations du service web',
                      de: 'Webdienstbetrieb',
                      ja: 'Webサービス運用',
                    ),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: openHandLocalizedText(
                    context,
                    zh: '关闭',
                    zhHant: '關閉',
                    en: 'Close',
                    fr: 'Fermer',
                    de: 'Schließen',
                    ja: '閉じる',
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: OpenHandSafeScrollbar(
              controller: _scrollController,
              child: SingleChildScrollView(
                controller: _scrollController,
                primary: false,
                physics: kOpenHandClampingPhysics,
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedOpacity(
                      duration: openHandMotionDurationMs(context, 220),
                      curve: Curves.easeOutCubic,
                      opacity: serviceControlsDisabled ? .62 : 1,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: isRunning || serviceControlsDisabled
                                ? null
                                : () => _runServiceAction(
                                    label: startLabel,
                                    action: widget.controller.startService,
                                  ),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: Text(startLabel),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: !isRunning || serviceControlsDisabled
                                ? null
                                : () => _runServiceAction(
                                    label: stopLabel,
                                    action: widget.controller.stopService,
                                  ),
                            icon: const Icon(Icons.stop_rounded),
                            label: Text(stopLabel),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: serviceControlsDisabled
                                ? null
                                : () => _runServiceAction(
                                    label: restartLabel,
                                    action: widget.controller.restartService,
                                  ),
                            icon: const Icon(Icons.restart_alt_rounded),
                            label: Text(restartLabel),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: serviceControlsDisabled
                                ? null
                                : () => _runServiceAction(
                                    label: reloadLabel,
                                    action: widget.controller.reloadConfig,
                                  ),
                            icon: const Icon(Icons.sync_rounded),
                            label: Text(reloadLabel),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: serviceControlsDisabled
                                ? null
                                : () => _runServiceAction(
                                    label: hotFixLabel,
                                    action: widget.controller.hotFix,
                                  ),
                            icon: const Icon(Icons.healing_rounded),
                            label: Text(hotFixLabel),
                          ),
                          FilledButton.icon(
                            onPressed: _isHealthChecking
                                ? null
                                : _runOpsHealthCheck,
                            icon: _isHealthChecking
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.monitor_heart_outlined),
                            label: Text(healthLabel),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: _isCleaning
                                ? null
                                : () => _runCleanup(
                                    label: expiredResourcesLabel,
                                    action: widget
                                        .controller
                                        .cleanupExpiredArtifacts,
                                  ),
                            icon: const Icon(Icons.cleaning_services_outlined),
                            label: Text(
                              openHandLocalizedText(
                                context,
                                zh: '清理过期',
                                zhHant: '清理過期',
                                en: 'Clean expired',
                                fr: 'Nettoyer les expirés',
                                de: 'Abgelaufene bereinigen',
                                ja: '期限切れを清理',
                              ),
                            ),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: _isCleaning
                                ? null
                                : () => _confirmAndCleanup(
                                    title: openHandLocalizedText(
                                      context,
                                      zh: '清空日志',
                                      zhHant: '清空日誌',
                                      en: 'Clear logs',
                                      fr: 'Effacer les journaux',
                                      de: 'Protokolle leeren',
                                      ja: 'ログをクリア',
                                    ),
                                    message: openHandLocalizedText(
                                      context,
                                      zh: '会清空内存日志和 Web 服务磁盘日志，保留策略不会保留当前内容。',
                                      zhHant:
                                          '會清空記憶體日誌和 Web 服務磁碟日誌，保留策略不會保留目前內容。',
                                      en: 'This clears in-memory logs and web service log files. Retention policy will not keep the current content.',
                                      fr: 'Cela efface les journaux en mémoire et sur disque. La rétention ne conservera pas le contenu actuel.',
                                      de: 'Dies leert Speicher- und Dateiprotokolle. Die Aufbewahrungsregel behält den aktuellen Inhalt nicht.',
                                      ja: 'メモリ内ログとWebサービスのディスクログをクリアします。保持ポリシーは現在の内容を保持しません。',
                                    ),
                                    label: logsLabel,
                                    action: widget.controller.cleanupLogs,
                                  ),
                            icon: const Icon(Icons.delete_sweep_outlined),
                            label: Text(
                              openHandLocalizedText(
                                context,
                                zh: '清空日志',
                                zhHant: '清空日誌',
                                en: 'Clear logs',
                                fr: 'Effacer les journaux',
                                de: 'Protokolle leeren',
                                ja: 'ログをクリア',
                              ),
                            ),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: _isCleaning
                                ? null
                                : () => _confirmAndCleanup(
                                    title: openHandLocalizedText(
                                      context,
                                      zh: '清空上传缓存',
                                      zhHant: '清空上傳快取',
                                      en: 'Clear upload cache',
                                      fr: 'Effacer le cache d’envoi',
                                      de: 'Upload-Cache leeren',
                                      ja: 'アップロードキャッシュをクリア',
                                    ),
                                    message: openHandLocalizedText(
                                      context,
                                      zh: '会删除 Web 消息附件落盘缓存，不影响已经写入会话的消息记录。',
                                      zhHant: '會刪除 Web 訊息附件落盤快取，不影響已寫入會話的訊息記錄。',
                                      en: 'This deletes cached web message attachments. Messages already written to sessions are unaffected.',
                                      fr: 'Cela supprime le cache des pièces jointes web. Les messages déjà écrits ne sont pas affectés.',
                                      de: 'Dies löscht zwischengespeicherte Webnachrichten-Anhänge. Bereits gespeicherte Sitzungsnachrichten bleiben erhalten.',
                                      ja: 'Webメッセージ添付のディスクキャッシュを削除します。セッションに保存済みのメッセージには影響しません。',
                                    ),
                                    label: uploadCacheLabel,
                                    action:
                                        widget.controller.cleanupUploadCache,
                                  ),
                            icon: const Icon(Icons.folder_delete_outlined),
                            label: Text(
                              openHandLocalizedText(
                                context,
                                zh: '清空缓存',
                                zhHant: '清空快取',
                                en: 'Clear cache',
                                fr: 'Effacer le cache',
                                de: 'Cache leeren',
                                ja: 'キャッシュをクリア',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth < 760 ? 2 : 4;
                        return GridView.count(
                          crossAxisCount: columns,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: columns == 2 ? 2.1 : 2.4,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            _MetricTile(
                              label: openHandLocalizedText(
                                context,
                                zh: '运行状态',
                                zhHant: '執行狀態',
                                en: 'Runtime state',
                                fr: 'État d’exécution',
                                de: 'Laufzeitstatus',
                                ja: '実行状態',
                              ),
                              value: _runtimeStateLabel(
                                context,
                                snapshot.state,
                              ),
                            ),
                            _MetricTile(
                              label: openHandLocalizedText(
                                context,
                                zh: '运行时间',
                                zhHant: '執行時間',
                                en: 'Uptime',
                                fr: 'Temps actif',
                                de: 'Laufzeit',
                                ja: '稼働時間',
                              ),
                              value: formatCompactDurationMs(snapshot.uptimeMs),
                            ),
                            _MetricTile(
                              label: 'CPU',
                              value: snapshot.cpuPercent == null
                                  ? _gatewayUnavailable(context)
                                  : '${snapshot.cpuPercent!.toStringAsFixed(1)}%',
                            ),
                            _MetricTile(
                              label: openHandLocalizedText(
                                context,
                                zh: '线程数',
                                zhHant: '執行緒數',
                                en: 'Threads',
                                fr: 'Threads',
                                de: 'Threads',
                                ja: 'スレッド数',
                              ),
                              value:
                                  snapshot.threadCount?.toString() ??
                                  _gatewayUnavailable(context),
                            ),
                            _MetricTile(
                              label: openHandLocalizedText(
                                context,
                                zh: '文件句柄',
                                zhHant: '檔案句柄',
                                en: 'File handles',
                                fr: 'Descripteurs de fichier',
                                de: 'Dateihandles',
                                ja: 'ファイルハンドル',
                              ),
                              value:
                                  snapshot.fileHandleCount?.toString() ??
                                  _gatewayUnavailable(context),
                            ),
                            _MetricTile(
                              label: 'Swap',
                              value: snapshot.swapBytes == null
                                  ? _gatewayUnavailable(context)
                                  : _bytes(snapshot.swapBytes!),
                            ),
                            _MetricTile(
                              label: openHandLocalizedText(
                                context,
                                zh: '内存',
                                zhHant: '記憶體',
                                en: 'Memory',
                                fr: 'Mémoire',
                                de: 'Speicher',
                                ja: 'メモリ',
                              ),
                              value: _bytes(snapshot.currentRssBytes),
                            ),
                            _MetricTile(
                              label: openHandLocalizedText(
                                context,
                                zh: '最大内存',
                                zhHant: '最大記憶體',
                                en: 'Peak memory',
                                fr: 'Mémoire max',
                                de: 'Max. Speicher',
                                ja: '最大メモリ',
                              ),
                              value: _bytes(snapshot.maxRssBytes),
                            ),
                            _MetricTile(
                              label: openHandLocalizedText(
                                context,
                                zh: '日志磁盘',
                                zhHant: '日誌磁碟',
                                en: 'Log disk',
                                fr: 'Disque des journaux',
                                de: 'Protokollspeicher',
                                ja: 'ログディスク',
                              ),
                              value: _bytes(snapshot.logBytes),
                            ),
                            _MetricTile(
                              label: openHandLocalizedText(
                                context,
                                zh: '活动请求',
                                zhHant: '活動請求',
                                en: 'Active requests',
                                fr: 'Requêtes actives',
                                de: 'Aktive Anfragen',
                                ja: 'アクティブリクエスト',
                              ),
                              value: '${snapshot.activeRequests}',
                            ),
                            _MetricTile(
                              label: openHandLocalizedText(
                                context,
                                zh: 'SSE 长连接',
                                zhHant: 'SSE 長連線',
                                en: 'SSE connections',
                                fr: 'Connexions SSE',
                                de: 'SSE-Verbindungen',
                                ja: 'SSE接続',
                              ),
                              value: '${snapshot.activeSseSubscriptions}',
                            ),
                            _MetricTile(
                              label: openHandLocalizedText(
                                context,
                                zh: '总请求',
                                zhHant: '總請求',
                                en: 'Total requests',
                                fr: 'Requêtes totales',
                                de: 'Anfragen gesamt',
                                ja: '総リクエスト',
                              ),
                              value: '${snapshot.totalRequests}',
                            ),
                            _MetricTile(
                              label: openHandLocalizedText(
                                context,
                                zh: '请求/min',
                                zhHant: '請求/min',
                                en: 'Requests/min',
                                fr: 'Requêtes/min',
                                de: 'Anfragen/min',
                                ja: 'リクエスト/min',
                              ),
                              value: _rate(snapshot.requestsPerMinute),
                            ),
                            _MetricTile(
                              label: openHandLocalizedText(
                                context,
                                zh: '错误数',
                                zhHant: '錯誤數',
                                en: 'Errors',
                                fr: 'Erreurs',
                                de: 'Fehler',
                                ja: 'エラー数',
                              ),
                              value: '${snapshot.totalErrors}',
                            ),
                            _MetricTile(
                              label: openHandLocalizedText(
                                context,
                                zh: '错误/min',
                                zhHant: '錯誤/min',
                                en: 'Errors/min',
                                fr: 'Erreurs/min',
                                de: 'Fehler/min',
                                ja: 'エラー/min',
                              ),
                              value: _rate(snapshot.errorsPerMinute),
                            ),
                            _MetricTile(
                              label: openHandLocalizedText(
                                context,
                                zh: '入流量/min',
                                zhHant: '入流量/min',
                                en: 'Inbound/min',
                                fr: 'Entrant/min',
                                de: 'Eingehend/min',
                                ja: '受信/min',
                              ),
                              value: _bytes(snapshot.bytesInPerMinute.round()),
                            ),
                            _MetricTile(
                              label: openHandLocalizedText(
                                context,
                                zh: '出流量/min',
                                zhHant: '出流量/min',
                                en: 'Outbound/min',
                                fr: 'Sortant/min',
                                de: 'Ausgehend/min',
                                ja: '送信/min',
                              ),
                              value: _bytes(snapshot.bytesOutPerMinute.round()),
                            ),
                            _MetricTile(
                              label: openHandLocalizedText(
                                context,
                                zh: '延迟 P95',
                                zhHant: '延遲 P95',
                                en: 'Latency P95',
                                fr: 'Latence P95',
                                de: 'Latenz P95',
                                ja: 'レイテンシ P95',
                              ),
                              value: '${snapshot.latencyStats.p95Ms}ms',
                            ),
                            _MetricTile(
                              label: openHandLocalizedText(
                                context,
                                zh: '延迟 P50',
                                zhHant: '延遲 P50',
                                en: 'Latency P50',
                                fr: 'Latence P50',
                                de: 'Latenz P50',
                                ja: 'レイテンシ P50',
                              ),
                              value: '${snapshot.latencyStats.p50Ms}ms',
                            ),
                            _MetricTile(
                              label: openHandLocalizedText(
                                context,
                                zh: '延迟 P99',
                                zhHant: '延遲 P99',
                                en: 'Latency P99',
                                fr: 'Latence P99',
                                de: 'Latenz P99',
                                ja: 'レイテンシ P99',
                              ),
                              value: '${snapshot.latencyStats.p99Ms}ms',
                            ),
                            _MetricTile(
                              label: openHandLocalizedText(
                                context,
                                zh: '延迟 MAX',
                                zhHant: '延遲 MAX',
                                en: 'Latency MAX',
                                fr: 'Latence MAX',
                                de: 'Latenz MAX',
                                ja: 'レイテンシ MAX',
                              ),
                              value: '${snapshot.latencyStats.maxMs}ms',
                            ),
                            _MetricTile(
                              label: openHandLocalizedText(
                                context,
                                zh: '延迟样本',
                                zhHant: '延遲樣本',
                                en: 'Latency samples',
                                fr: 'Échantillons latence',
                                de: 'Latenzstichproben',
                                ja: 'レイテンシサンプル',
                              ),
                              value: '${snapshot.latencyStats.sampleCount}',
                            ),
                            _MetricTile(
                              label: openHandLocalizedText(
                                context,
                                zh: '累计入流量',
                                zhHant: '累計入流量',
                                en: 'Total inbound',
                                fr: 'Entrant total',
                                de: 'Eingehend gesamt',
                                ja: '総受信量',
                              ),
                              value: _bytes(snapshot.totalBytesIn),
                            ),
                            _MetricTile(
                              label: openHandLocalizedText(
                                context,
                                zh: '累计出流量',
                                zhHant: '累計出流量',
                                en: 'Total outbound',
                                fr: 'Sortant total',
                                de: 'Ausgehend gesamt',
                                ja: '総送信量',
                              ),
                              value: _bytes(snapshot.totalBytesOut),
                            ),
                            _MetricTile(
                              label: openHandLocalizedText(
                                context,
                                zh: '崩溃数',
                                zhHant: '崩潰數',
                                en: 'Crashes',
                                fr: 'Plantages',
                                de: 'Abstürze',
                                ja: 'クラッシュ数',
                              ),
                              value: '${snapshot.crashCount}',
                            ),
                            _MetricTile(
                              label: openHandLocalizedText(
                                context,
                                zh: '重启数',
                                zhHant: '重啟數',
                                en: 'Restarts',
                                fr: 'Redémarrages',
                                de: 'Neustarts',
                                ja: '再起動数',
                              ),
                              value: '${snapshot.restartCount}',
                            ),
                            _MetricTile(
                              label: openHandLocalizedText(
                                context,
                                zh: '线程会话',
                                zhHant: '執行緒會話',
                                en: 'Thread sessions',
                                fr: 'Sessions de fil',
                                de: 'Thread-Sitzungen',
                                ja: 'スレッドセッション',
                              ),
                              value: '${snapshot.openSessionCount}',
                            ),
                            _MetricTile(
                              label: openHandLocalizedText(
                                context,
                                zh: '并发水位',
                                zhHant: '並發水位',
                                en: 'Concurrency level',
                                fr: 'Niveau de concurrence',
                                de: 'Parallelitätsniveau',
                                ja: '同時実行水位',
                              ),
                              value: _percent(snapshot.activeRequestRatio),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    _OpsHealthCard(snapshot: snapshot),
                    const SizedBox(height: 18),
                    _OpsSummaryCard(snapshot: snapshot),
                    const SizedBox(height: 18),
                    _NaturalCardGrid(
                      minTileWidth: 360,
                      spacing: 12,
                      maxColumns: 2,
                      children: [
                        _OpsBreakdownCard(
                          title: openHandLocalizedText(
                            context,
                            zh: 'HTTP 状态码分布',
                            zhHant: 'HTTP 狀態碼分布',
                            en: 'HTTP status distribution',
                            fr: 'Répartition des statuts HTTP',
                            de: 'HTTP-Statusverteilung',
                            ja: 'HTTPステータス分布',
                          ),
                          values: snapshot.statusCodeBreakdown,
                        ),
                        _OpsBreakdownCard(
                          title: openHandLocalizedText(
                            context,
                            zh: 'HTTP Method 分布',
                            zhHant: 'HTTP Method 分布',
                            en: 'HTTP method distribution',
                            fr: 'Répartition des méthodes HTTP',
                            de: 'HTTP-Methodenverteilung',
                            ja: 'HTTPメソッド分布',
                          ),
                          values: snapshot.methodBreakdown,
                        ),
                        _OpsBreakdownCard(
                          title: openHandLocalizedText(
                            context,
                            zh: '延迟桶',
                            zhHant: '延遲桶',
                            en: 'Latency buckets',
                            fr: 'Buckets de latence',
                            de: 'Latenz-Buckets',
                            ja: 'レイテンシバケット',
                          ),
                          values: snapshot.latencyBuckets,
                        ),
                        _OpsBreakdownCard(
                          title: openHandLocalizedText(
                            context,
                            zh: '发送阶段分布',
                            zhHant: '傳送階段分布',
                            en: 'Send phase distribution',
                            fr: 'Répartition des phases d’envoi',
                            de: 'Sendephasenverteilung',
                            ja: '送信フェーズ分布',
                          ),
                          values: snapshot.sendPhaseBreakdown,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _NaturalCardGrid(
                      minTileWidth: 360,
                      spacing: 12,
                      maxColumns: 2,
                      children: [
                        _TopRoutesCard(routes: snapshot.topRoutes),
                        _RecentErrorsCard(errors: snapshot.recentErrors),
                        _OpsBreakdownCard(
                          title: openHandLocalizedText(
                            context,
                            zh: '日志级别分布',
                            zhHant: '日誌級別分布',
                            en: 'Log level distribution',
                            fr: 'Répartition des niveaux de journal',
                            de: 'Protokollstufenverteilung',
                            ja: 'ログレベル分布',
                          ),
                          values: snapshot.logLevelBreakdown,
                          footer: openHandLocalizedText(
                            context,
                            zh: '${snapshot.memoryLogCount} 条内存日志',
                            zhHant: '${snapshot.memoryLogCount} 則記憶體日誌',
                            en: '${snapshot.memoryLogCount} in-memory logs',
                            fr: '${snapshot.memoryLogCount} journaux en mémoire',
                            de: '${snapshot.memoryLogCount} Speicherprotokolle',
                            ja: '${snapshot.memoryLogCount} 件のメモリ内ログ',
                          ),
                        ),
                        _ResourceInventoryCard(snapshot: snapshot),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _SectionTitle(
                      openHandLocalizedText(
                        context,
                        zh: '吞吐趋势',
                        zhHant: '吞吐趨勢',
                        en: 'Throughput Trends',
                        fr: 'Tendances du débit',
                        de: 'Durchsatztrends',
                        ja: 'スループット傾向',
                      ),
                      icon: Icons.show_chart,
                    ),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth < 720 ? 1 : 2;
                        return GridView.count(
                          crossAxisCount: columns,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: columns == 1 ? 2.35 : 1.85,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            _TrendLineChart(
                              title: openHandLocalizedText(
                                context,
                                zh: '请求/秒',
                                zhHant: '請求/秒',
                                en: 'Requests/sec',
                                fr: 'Requêtes/s',
                                de: 'Anfragen/s',
                                ja: 'リクエスト/秒',
                              ),
                              values: _deltaSeries(
                                _trend,
                                (snapshot) => snapshot.totalRequests.toDouble(),
                              ),
                              valueFormatter: (value) =>
                                  value.toStringAsFixed(0),
                            ),
                            _TrendLineChart(
                              title: openHandLocalizedText(
                                context,
                                zh: '错误/秒',
                                zhHant: '錯誤/秒',
                                en: 'Errors/sec',
                                fr: 'Erreurs/s',
                                de: 'Fehler/s',
                                ja: 'エラー/秒',
                              ),
                              values: _deltaSeries(
                                _trend,
                                (snapshot) => snapshot.totalErrors.toDouble(),
                              ),
                              valueFormatter: (value) =>
                                  value.toStringAsFixed(0),
                            ),
                            _TrendLineChart(
                              title: openHandLocalizedText(
                                context,
                                zh: '活动请求',
                                zhHant: '活動請求',
                                en: 'Active requests',
                                fr: 'Requêtes actives',
                                de: 'Aktive Anfragen',
                                ja: 'アクティブリクエスト',
                              ),
                              values: _series(
                                _trend,
                                (snapshot) =>
                                    snapshot.activeRequests.toDouble(),
                              ),
                              valueFormatter: (value) =>
                                  value.toStringAsFixed(0),
                            ),
                            _TrendLineChart(
                              title: openHandLocalizedText(
                                context,
                                zh: 'P95 延迟',
                                zhHant: 'P95 延遲',
                                en: 'P95 latency',
                                fr: 'Latence P95',
                                de: 'P95-Latenz',
                                ja: 'P95レイテンシ',
                              ),
                              values: _series(
                                _trend,
                                (snapshot) =>
                                    snapshot.latencyStats.p95Ms.toDouble(),
                              ),
                              valueFormatter: (value) =>
                                  '${value.toStringAsFixed(0)}ms',
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    _SectionTitle(
                      openHandLocalizedText(
                        context,
                        zh: '资源趋势',
                        zhHant: '資源趨勢',
                        en: 'Resource Trends',
                        fr: 'Tendances des ressources',
                        de: 'Ressourcentrends',
                        ja: 'リソース傾向',
                      ),
                      icon: Icons.show_chart,
                    ),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth < 720 ? 1 : 2;
                        return GridView.count(
                          crossAxisCount: columns,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: columns == 1 ? 2.35 : 1.85,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            _TrendLineChart(
                              title: 'CPU %',
                              values: _series(
                                _trend,
                                (snapshot) => snapshot.cpuPercent,
                              ),
                              valueFormatter: (value) =>
                                  '${value.toStringAsFixed(1)}%',
                            ),
                            _TrendLineChart(
                              title: openHandLocalizedText(
                                context,
                                zh: '内存 RSS',
                                zhHant: '記憶體 RSS',
                                en: 'Memory RSS',
                                fr: 'Mémoire RSS',
                                de: 'Speicher RSS',
                                ja: 'メモリ RSS',
                              ),
                              values: _series(
                                _trend,
                                (snapshot) =>
                                    snapshot.currentRssBytes.toDouble(),
                              ),
                              valueFormatter: (value) => _bytes(value.round()),
                            ),
                            _TrendLineChart(
                              title: openHandLocalizedText(
                                context,
                                zh: '日志磁盘',
                                zhHant: '日誌磁碟',
                                en: 'Log disk',
                                fr: 'Disque des journaux',
                                de: 'Protokollspeicher',
                                ja: 'ログディスク',
                              ),
                              values: _series(
                                _trend,
                                (snapshot) => snapshot.logBytes.toDouble(),
                              ),
                              valueFormatter: (value) => _bytes(value.round()),
                            ),
                            _TrendLineChart(
                              title: openHandLocalizedText(
                                context,
                                zh: '线程数',
                                zhHant: '執行緒數',
                                en: 'Threads',
                                fr: 'Threads',
                                de: 'Threads',
                                ja: 'スレッド数',
                              ),
                              values: _series(
                                _trend,
                                (snapshot) => snapshot.threadCount?.toDouble(),
                              ),
                              valueFormatter: (value) =>
                                  value.toStringAsFixed(0),
                            ),
                            _TrendLineChart(
                              title: openHandLocalizedText(
                                context,
                                zh: '会话数',
                                zhHant: '會話數',
                                en: 'Sessions',
                                fr: 'Sessions',
                                de: 'Sitzungen',
                                ja: 'セッション数',
                              ),
                              values: _series(
                                _trend,
                                (snapshot) =>
                                    snapshot.openSessionCount.toDouble(),
                              ),
                              valueFormatter: (value) =>
                                  value.toStringAsFixed(0),
                            ),
                            _TrendLineChart(
                              title: openHandLocalizedText(
                                context,
                                zh: '入流量/min',
                                zhHant: '入流量/min',
                                en: 'Inbound/min',
                                fr: 'Entrant/min',
                                de: 'Eingehend/min',
                                ja: '受信/min',
                              ),
                              values: _series(
                                _trend,
                                (snapshot) => snapshot.bytesInPerMinute,
                              ),
                              valueFormatter: (value) => _bytes(value.round()),
                            ),
                          ],
                        );
                      },
                    ),
                    if (cleanupHistory.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      _SectionTitle(
                        openHandLocalizedText(
                          context,
                          zh: '清理历史',
                          zhHant: '清理歷史',
                          en: 'Cleanup History',
                          fr: 'Historique de nettoyage',
                          de: 'Bereinigungsverlauf',
                          ja: 'クリーンアップ履歴',
                        ),
                        icon: Icons.cleaning_services_outlined,
                      ),
                      ...cleanupHistory.map(
                        (entry) => _CleanupHistoryLine(entry: entry),
                      ),
                    ],
                    if (snapshot.lastError.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      _SectionTitle(
                        openHandLocalizedText(
                          context,
                          zh: '最近错误',
                          zhHant: '最近錯誤',
                          en: 'Latest Error',
                          fr: 'Dernière erreur',
                          de: 'Letzter Fehler',
                          ja: '最新エラー',
                        ),
                        icon: Icons.article_outlined,
                      ),
                      SelectableText(snapshot.lastError),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndCleanup({
    required String title,
    required String message,
    required String label,
    required Future<WebGatewayCleanupResult> Function() action,
  }) async {
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: title,
      message: message,
      cancelLabel: openHandLocalizedText(
        context,
        zh: '取消',
        zhHant: '取消',
        en: 'Cancel',
        fr: 'Annuler',
        de: 'Abbrechen',
        ja: 'キャンセル',
      ),
      confirmLabel: openHandLocalizedText(
        context,
        zh: '确认清理',
        zhHant: '確認清理',
        en: 'Confirm cleanup',
        fr: 'Confirmer le nettoyage',
        de: 'Bereinigung bestätigen',
        ja: 'クリーンアップを確認',
      ),
    );
    if (confirmed) {
      await _runCleanup(label: label, action: action);
    }
  }

  Future<void> _runServiceAction({
    required String label,
    required Future<void> Function() action,
  }) async {
    if (_isServiceActing) return;
    setState(() => _isServiceActing = true);
    try {
      await action();
      await _tick();
      if (!mounted) return;
      showOpenHandSnackBar(
        context,
        OpenHandSnackBar.success(
          context,
          openHandLocalizedText(
            context,
            zh: '$label 已完成',
            zhHant: '$label 已完成',
            en: '$label completed',
            fr: '$label terminé',
            de: '$label abgeschlossen',
            ja: '$label が完了しました',
          ),
          duration: const Duration(milliseconds: 1600),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      showOpenHandSnackBar(
        context,
        OpenHandSnackBar.error(
          context,
          openHandLocalizedText(
            context,
            zh: '$label 失败: $error',
            zhHant: '$label 失敗: $error',
            en: '$label failed: $error',
            fr: 'Échec de $label : $error',
            de: '$label fehlgeschlagen: $error',
            ja: '$label に失敗しました: $error',
          ),
          maxLines: 2,
        ),
      );
    } finally {
      if (mounted) setState(() => _isServiceActing = false);
    }
  }

  Future<void> _runOpsHealthCheck() async {
    if (_isHealthChecking) return;
    setState(() => _isHealthChecking = true);
    try {
      final result = await widget.controller.runHealthCheck();
      await _tick();
      if (!mounted) return;
      showOpenHandSnackBar(
        context,
        result.ok
            ? OpenHandSnackBar.success(
                context,
                '${result.summary} (${result.durationMs}ms)',
                duration: const Duration(milliseconds: 1800),
              )
            : OpenHandSnackBar.error(
                context,
                '${result.summary} (${result.durationMs}ms)',
                duration: const Duration(milliseconds: 1800),
              ),
      );
    } catch (error) {
      if (!mounted) return;
      showOpenHandSnackBar(
        context,
        OpenHandSnackBar.error(
          context,
          openHandLocalizedText(
            context,
            zh: '健康诊断失败: $error',
            zhHant: '健康診斷失敗: $error',
            en: 'Health diagnosis failed: $error',
            fr: 'Échec du diagnostic de santé : $error',
            de: 'Integritätsdiagnose fehlgeschlagen: $error',
            ja: 'ヘルス診断に失敗しました: $error',
          ),
          maxLines: 2,
        ),
      );
    } finally {
      if (mounted) setState(() => _isHealthChecking = false);
    }
  }

  Future<void> _runCleanup({
    required String label,
    required Future<WebGatewayCleanupResult> Function() action,
  }) async {
    if (_isCleaning) return;
    setState(() => _isCleaning = true);
    try {
      final result = await action();
      if (!mounted) return;
      showOpenHandSnackBar(
        context,
        OpenHandSnackBar.success(
          context,
          openHandLocalizedText(
            context,
            zh: '$label清理完成，释放 ${_bytes(result.bytesFreed)}，删除 ${result.deletedFiles} 个文件',
            zhHant:
                '$label 清理完成，釋放 ${_bytes(result.bytesFreed)}，刪除 ${result.deletedFiles} 個檔案',
            en: '$label cleanup completed, freed ${_bytes(result.bytesFreed)}, deleted ${result.deletedFiles} files',
            fr: 'Nettoyage $label terminé, ${_bytes(result.bytesFreed)} libérés, ${result.deletedFiles} fichiers supprimés',
            de: '$label-Bereinigung abgeschlossen, ${_bytes(result.bytesFreed)} freigegeben, ${result.deletedFiles} Dateien gelöscht',
            ja: '$label のクリーンアップが完了しました。${_bytes(result.bytesFreed)} 解放、${result.deletedFiles} ファイル削除',
          ),
        ),
      );
      await _tick();
    } catch (error) {
      if (!mounted) return;
      showOpenHandSnackBar(
        context,
        OpenHandSnackBar.error(
          context,
          openHandLocalizedText(
            context,
            zh: '$label清理失败: $error',
            zhHant: '$label 清理失敗: $error',
            en: '$label cleanup failed: $error',
            fr: 'Échec du nettoyage $label : $error',
            de: '$label-Bereinigung fehlgeschlagen: $error',
            ja: '$label のクリーンアップに失敗しました: $error',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isCleaning = false);
    }
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 与 MCP `_McpHealthStatusDot` 对齐：16×16 + 3px surface 同色描边 + 32% 透明软阴影；
    // 颜色变化走 AnimatedContainer，但若全局动画被禁用则 duration 归零，避免不必要重绘。
    return AnimatedContainer(
      duration: openHandMotionDurationMs(context, 180),
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: colorScheme.surface, width: 3),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.32),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

class _FeatureIconButton extends StatelessWidget {
  const _FeatureIconButton({
    required this.tooltip,
    required this.enabled,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final bool enabled;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: IconButton.filledTonal(
        style: IconButton.styleFrom(
          disabledBackgroundColor: theme.colorScheme.surfaceContainerHighest
              .withValues(alpha: .42),
          disabledForegroundColor: theme.colorScheme.onSurfaceVariant
              .withValues(alpha: .45),
        ),
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label, overflow: TextOverflow.ellipsis),
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      side: BorderSide(color: theme.colorScheme.outlineVariant),
    );
  }
}

/// 监听通配符地址（0.0.0.0 / ::）时展示全部可访问 URL 的横向胶囊条。
/// 每个 URL 胶囊同时提供复制与浏览器访问动作。
class _AccessibleUrlsBar extends StatelessWidget {
  const _AccessibleUrlsBar({required this.urls});

  final List<String> urls;

  Future<void> _copy(BuildContext context, String url) async {
    await copyMessageGatewayTextToClipboard(
      context: context,
      text: url,
      successMessage: openHandLocalizedText(
        context,
        zh: '已复制 $url',
        zhHant: '已複製 $url',
        en: 'Copied $url',
        fr: '$url copié',
        de: '$url kopiert',
        ja: '$url をコピーしました',
      ),
      logAction: 'copy accessible url',
    );
  }

  Future<void> _open(BuildContext context, String url) async {
    try {
      final opened = await openHttpUrlWithSystemBrowser(
        url,
        tag: 'message_gateway.open_url',
      );
      if (!context.mounted) return;
      if (!opened) {
        showOpenHandSnackBar(
          context,
          OpenHandSnackBar.error(
            context,
            openHandLocalizedText(
              context,
              zh: '打开失败: $url',
              zhHant: '開啟失敗: $url',
              en: 'Failed to open: $url',
              fr: 'Échec de l’ouverture : $url',
              de: 'Öffnen fehlgeschlagen: $url',
              ja: '開けませんでした: $url',
            ),
          ),
        );
        return;
      }
      showOpenHandSnackBar(
        context,
        OpenHandSnackBar.info(
          context,
          openHandLocalizedText(
            context,
            zh: '正在打开 $url',
            zhHant: '正在開啟 $url',
            en: 'Opening $url',
            fr: 'Ouverture de $url',
            de: '$url wird geöffnet',
            ja: '$url を開いています',
          ),
        ),
      );
    } catch (error, stack) {
      silentLog('message_gateway_view', 'open url', error, stack);
      if (!context.mounted) return;
      showOpenHandSnackBar(
        context,
        OpenHandSnackBar.error(
          context,
          openHandLocalizedText(
            context,
            zh: '打开失败: $error',
            zhHant: '開啟失敗: $error',
            en: 'Failed to open: $error',
            fr: 'Échec de l’ouverture : $error',
            de: 'Öffnen fehlgeschlagen: $error',
            ja: '開けませんでした: $error',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.lan_outlined, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              openHandLocalizedText(
                context,
                zh: '可访问 URL（复制 / 访问）',
                zhHant: '可存取 URL（複製 / 存取）',
                en: 'Accessible URLs (copy / open)',
                fr: 'URL accessibles (copier / ouvrir)',
                de: 'Erreichbare URLs (kopieren / öffnen)',
                ja: 'アクセス可能なURL（コピー / 開く）',
              ),
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final url in urls)
              _AccessibleUrlPill(
                url: url,
                onCopy: () => _copy(context, url),
                onOpen: () => _open(context, url),
              ),
          ],
        ),
      ],
    );
  }
}

class _AccessibleUrlPill extends StatelessWidget {
  const _AccessibleUrlPill({
    required this.url,
    required this.onCopy,
    required this.onOpen,
  });

  final String url;
  final VoidCallback onCopy;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: cs.primary.withValues(alpha: 0.32),
          width: 0.6,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: openHandLocalizedText(
              context,
              zh: '复制地址',
              zhHant: '複製位址',
              en: 'Copy address',
              fr: 'Copier l’adresse',
              de: 'Adresse kopieren',
              ja: 'アドレスをコピー',
            ),
            child: IconButton(
              onPressed: onCopy,
              style: IconButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: cs.onPrimaryContainer,
                hoverColor: cs.primary.withValues(alpha: 0.08),
                highlightColor: cs.primary.withValues(alpha: 0.12),
                focusColor: cs.primary.withValues(alpha: 0.10),
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.content_copy_rounded),
              iconSize: 16,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 34, height: 34),
            ),
          ),
          Flexible(
            child: Text(
              url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                color: cs.onPrimaryContainer,
              ),
            ),
          ),
          Tooltip(
            message: openHandLocalizedText(
              context,
              zh: '浏览器访问',
              zhHant: '瀏覽器存取',
              en: 'Open in browser',
              fr: 'Ouvrir dans le navigateur',
              de: 'Im Browser öffnen',
              ja: 'ブラウザで開く',
            ),
            child: IconButton(
              onPressed: onOpen,
              style: IconButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: cs.onPrimaryContainer,
                hoverColor: cs.primary.withValues(alpha: 0.08),
                highlightColor: cs.primary.withValues(alpha: 0.12),
                focusColor: cs.primary.withValues(alpha: 0.10),
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.open_in_browser_rounded),
              iconSize: 17,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 36, height: 34),
            ),
          ),
        ],
      ),
    );
  }
}

Object? _tryDecodeJson(String value) {
  try {
    return jsonDecode(value);
  } catch (_) {
    return null;
  }
}

String _formatStructuredValue(Object? value) {
  if (value == null) return 'null';
  if (value is String || value is num || value is bool) return '$value';
  try {
    return prettyPrintJson(value);
  } catch (_) {
    return '$value';
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.56,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {required this.icon});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: .74),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 15, color: colorScheme.onPrimaryContainer),
          ),
          const SizedBox(width: 9),
          Text(
            text,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Divider(
              height: 1,
              color: colorScheme.outlineVariant.withValues(alpha: .72),
            ),
          ),
        ],
      ),
    );
  }
}

class _NaturalCardGrid extends StatelessWidget {
  const _NaturalCardGrid({
    required this.children,
    this.minTileWidth = 320,
    required this.spacing,
    required this.maxColumns,
  });

  final List<Widget> children;
  final double minTileWidth;
  final double spacing;
  final int maxColumns;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final possibleColumns =
          ((constraints.maxWidth + spacing) / (minTileWidth + spacing)).floor();
      final columns = possibleColumns.clamp(1, maxColumns).toInt();
      final tileWidth =
          (constraints.maxWidth - spacing * (columns - 1)) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final child in children)
            SizedBox(width: tileWidth, child: child),
        ],
      );
    },
  );
}

class _OpsHealthCard extends StatelessWidget {
  const _OpsHealthCard({required this.snapshot});

  final WebGatewayRuntimeSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final diagnosis = _OpsDiagnosis.from(context, snapshot);
    final color = switch (diagnosis.tone) {
      _OpsDiagnosisTone.ok => Colors.green.shade700,
      _OpsDiagnosisTone.warn => Colors.orange.shade800,
      _OpsDiagnosisTone.error => theme.colorScheme.error,
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _opsCardDecoration(
        theme,
      ).copyWith(border: Border.all(color: color.withValues(alpha: 0.42))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      openHandLocalizedText(
                        context,
                        zh: '运行健康度',
                        zhHant: '執行健康度',
                        en: 'Runtime health',
                        fr: 'Santé d’exécution',
                        de: 'Laufzeitintegrität',
                        ja: '実行ヘルス',
                      ),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${diagnosis.score}',
                          style: theme.textTheme.displaySmall?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 7),
                          child: Text(
                            diagnosis.label,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.health_and_safety_outlined, size: 24),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: diagnosis.signals
                .map((signal) => _OpsPill(signal.label, signal.value))
                .toList(growable: false),
          ),
          const SizedBox(height: 12),
          ...diagnosis.recommendations.map(
            (item) => _OpsKeyValue(
              openHandLocalizedText(
                context,
                zh: '建议',
                zhHant: '建議',
                en: 'Advice',
                fr: 'Conseil',
                de: 'Empfehlung',
                ja: '推奨',
              ),
              item,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            openHandLocalizedText(
              context,
              zh: '阈值告警',
              zhHant: '閾值告警',
              en: 'Threshold alerts',
              fr: 'Alertes de seuil',
              de: 'Schwellwertwarnungen',
              ja: 'しきい値アラート',
            ),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          if (diagnosis.alerts.isEmpty)
            Text(
              openHandLocalizedText(
                context,
                zh: '暂无触发阈值',
                zhHant: '暫無觸發閾值',
                en: 'No thresholds triggered',
                fr: 'Aucun seuil déclenché',
                de: 'Keine Schwellenwerte ausgelöst',
                ja: 'しきい値超過はありません',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: diagnosis.alerts
                  .map(
                    (alert) => _OpsPill(
                      alert.label,
                      '${alert.threshold} · ${alert.actual}',
                    ),
                  )
                  .toList(growable: false),
            ),
        ],
      ),
    );
  }
}

enum _OpsDiagnosisTone { ok, warn, error }

class _OpsDiagnosisSignal {
  const _OpsDiagnosisSignal(this.label, this.value);
  final String label;
  final String value;
}

class _OpsDiagnosisAlert {
  const _OpsDiagnosisAlert(this.label, this.threshold, this.actual);
  final String label;
  final String threshold;
  final String actual;
}

class _OpsDiagnosis {
  const _OpsDiagnosis({
    required this.score,
    required this.label,
    required this.tone,
    required this.signals,
    required this.alerts,
    required this.recommendations,
  });

  factory _OpsDiagnosis.from(
    BuildContext context,
    WebGatewayRuntimeSnapshot snapshot,
  ) {
    var score = 100;
    final recommendations = <String>[];
    final alerts = <_OpsDiagnosisAlert>[];
    final errorRate = snapshot.totalRequests <= 0
        ? 0.0
        : snapshot.totalErrors / snapshot.totalRequests;
    final p95 = snapshot.latencyStats.p95Ms;
    final p99 = snapshot.latencyStats.p99Ms;
    final saturation = snapshot.activeRequestRatio;
    final logErrors = snapshot.logLevelBreakdown['error'] ?? 0;
    final serviceStateLabel = openHandLocalizedText(
      context,
      zh: '服务状态',
      zhHant: '服務狀態',
      en: 'Service state',
      fr: 'État du service',
      de: 'Dienststatus',
      ja: 'サービス状態',
    );
    final errorRateLabel = openHandLocalizedText(
      context,
      zh: '错误率',
      zhHant: '錯誤率',
      en: 'Error rate',
      fr: 'Taux d’erreur',
      de: 'Fehlerrate',
      ja: 'エラー率',
    );
    final errorsPerMinuteLabel = openHandLocalizedText(
      context,
      zh: '错误/min',
      zhHant: '錯誤/min',
      en: 'Errors/min',
      fr: 'Erreurs/min',
      de: 'Fehler/min',
      ja: 'エラー/min',
    );
    final concurrencyLabel = openHandLocalizedText(
      context,
      zh: '并发水位',
      zhHant: '並發水位',
      en: 'Concurrency level',
      fr: 'Niveau de concurrence',
      de: 'Parallelitätsniveau',
      ja: '同時実行水位',
    );
    final p95LatencyLabel = openHandLocalizedText(
      context,
      zh: 'P95 延迟',
      zhHant: 'P95 延遲',
      en: 'P95 latency',
      fr: 'Latence P95',
      de: 'P95-Latenz',
      ja: 'P95レイテンシ',
    );

    if (snapshot.state == WebGatewayRuntimeState.crashed) {
      score -= 45;
      alerts.add(
        _OpsDiagnosisAlert(serviceStateLabel, 'running', snapshot.state.name),
      );
      recommendations.add(
        openHandLocalizedText(
          context,
          zh: '服务处于 crashed，优先查看最近错误和内存日志并重启服务。',
          zhHant: '服務處於 crashed，優先查看最近錯誤和記憶體日誌並重啟服務。',
          en: 'Service is crashed. Check latest errors and in-memory logs, then restart it.',
          fr: 'Le service est crashed. Consultez les erreurs récentes et les journaux mémoire, puis redémarrez.',
          de: 'Der Dienst ist abgestürzt. Prüfen Sie letzte Fehler und Speicherprotokolle und starten Sie neu.',
          ja: 'サービスは crashed 状態です。最新エラーとメモリ内ログを確認して再起動してください。',
        ),
      );
    } else if (snapshot.state != WebGatewayRuntimeState.running) {
      score -= 20;
      alerts.add(
        _OpsDiagnosisAlert(serviceStateLabel, 'running', snapshot.state.name),
      );
      recommendations.add(
        openHandLocalizedText(
          context,
          zh: '服务未处于 running，确认监听端口、鉴权配置和启动日志。',
          zhHant: '服務未處於 running，請確認監聽連接埠、鑑權設定和啟動日誌。',
          en: 'Service is not running. Check listen port, auth configuration, and startup logs.',
          fr: 'Le service n’est pas running. Vérifiez le port, l’authentification et les journaux de démarrage.',
          de: 'Der Dienst läuft nicht. Prüfen Sie Port, Auth-Konfiguration und Startprotokolle.',
          ja: 'サービスは running ではありません。リッスンポート、認証設定、起動ログを確認してください。',
        ),
      );
    }
    if (errorRate >= 0.05) {
      score -= 25;
      alerts.add(
        _OpsDiagnosisAlert(errorRateLabel, '>= 5%', _percent(errorRate)),
      );
      recommendations.add(
        openHandLocalizedText(
          context,
          zh: '错误率超过 5%，优先按最近错误路径定位 4xx/5xx 来源。',
          zhHant: '錯誤率超過 5%，優先按最近錯誤路徑定位 4xx/5xx 來源。',
          en: 'Error rate is above 5%. Use recent error paths to locate 4xx/5xx sources first.',
          fr: 'Le taux d’erreur dépasse 5 %. Utilisez les chemins récents pour trouver les sources 4xx/5xx.',
          de: 'Fehlerrate über 5 %. Nutzen Sie aktuelle Fehlerpfade zur 4xx/5xx-Analyse.',
          ja: 'エラー率が5%を超えています。最近のエラーパスから4xx/5xxの原因を優先確認してください。',
        ),
      );
    } else if (errorRate >= 0.01) {
      score -= 12;
      alerts.add(
        _OpsDiagnosisAlert(errorRateLabel, '>= 1%', _percent(errorRate)),
      );
      recommendations.add(
        openHandLocalizedText(
          context,
          zh: '错误率超过 1%，建议核对请求来源、模型服务和文件权限。',
          zhHant: '錯誤率超過 1%，建議核對請求來源、模型服務和檔案權限。',
          en: 'Error rate is above 1%. Check request sources, model service, and file permissions.',
          fr: 'Le taux d’erreur dépasse 1 %. Vérifiez les sources, le service modèle et les droits fichier.',
          de: 'Fehlerrate über 1 %. Prüfen Sie Anfragequellen, Modelldienst und Dateirechte.',
          ja: 'エラー率が1%を超えています。リクエスト元、モデルサービス、ファイル権限を確認してください。',
        ),
      );
    }
    if (snapshot.errorsPerMinute > 0) {
      score -= math.min(15, 5 + (snapshot.errorsPerMinute * 2).round());
      alerts.add(
        _OpsDiagnosisAlert(
          errorsPerMinuteLabel,
          '> 0',
          _rate(snapshot.errorsPerMinute),
        ),
      );
      recommendations.add(
        openHandLocalizedText(
          context,
          zh: '最近 1 分钟仍有错误增长，观察错误是否持续并检查对应路由。',
          zhHant: '最近 1 分鐘仍有錯誤增長，觀察錯誤是否持續並檢查對應路由。',
          en: 'Errors are still increasing in the last minute. Watch for persistence and inspect related routes.',
          fr: 'Les erreurs augmentent encore sur la dernière minute. Surveillez la tendance et vérifiez les routes concernées.',
          de: 'Fehler steigen in der letzten Minute weiter. Beobachten Sie die Entwicklung und prüfen Sie betroffene Routen.',
          ja: '直近1分でエラーが増えています。継続するか確認し、該当ルートを調べてください。',
        ),
      );
    }
    if (saturation >= 0.85) {
      score -= 20;
      alerts.add(
        _OpsDiagnosisAlert(concurrencyLabel, '>= 85%', _percent(saturation)),
      );
      recommendations.add(
        openHandLocalizedText(
          context,
          zh: '并发水位接近上限，建议降低长连接/轮询压力或提高并发限制。',
          zhHant: '並發水位接近上限，建議降低長連線/輪詢壓力或提高並發限制。',
          en: 'Concurrency is near the limit. Reduce long-connection or polling pressure, or raise the concurrency limit.',
          fr: 'La concurrence approche la limite. Réduisez les connexions longues/le polling ou augmentez la limite.',
          de: 'Parallelität nahe am Limit. Reduzieren Sie Langverbindungen/Polling oder erhöhen Sie das Limit.',
          ja: '同時実行が上限に近づいています。長時間接続やポーリング負荷を下げるか上限を上げてください。',
        ),
      );
    } else if (saturation >= 0.6) {
      score -= 10;
      alerts.add(
        _OpsDiagnosisAlert(concurrencyLabel, '>= 60%', _percent(saturation)),
      );
      recommendations.add(
        openHandLocalizedText(
          context,
          zh: '并发水位偏高，继续观察请求排队和 SSE 连接数。',
          zhHant: '並發水位偏高，繼續觀察請求排隊和 SSE 連線數。',
          en: 'Concurrency is elevated. Keep watching request queueing and SSE connections.',
          fr: 'La concurrence est élevée. Surveillez la file de requêtes et les connexions SSE.',
          de: 'Parallelität ist erhöht. Beobachten Sie Anfragewarteschlangen und SSE-Verbindungen.',
          ja: '同時実行水位が高めです。リクエスト待ちとSSE接続数を引き続き確認してください。',
        ),
      );
    }
    if (p95 >= 3000) {
      score -= 15;
      alerts.add(_OpsDiagnosisAlert(p95LatencyLabel, '>= 3000ms', '${p95}ms'));
      recommendations.add(
        openHandLocalizedText(
          context,
          zh: 'P95 延迟超过 3s，建议检查慢路由、上游模型和文件 IO。',
          zhHant: 'P95 延遲超過 3s，建議檢查慢路由、上游模型和檔案 IO。',
          en: 'P95 latency is above 3s. Check slow routes, upstream models, and file I/O.',
          fr: 'La latence P95 dépasse 3 s. Vérifiez les routes lentes, les modèles amont et les E/S fichier.',
          de: 'P95-Latenz über 3 s. Prüfen Sie langsame Routen, Upstream-Modelle und Datei-I/O.',
          ja: 'P95レイテンシが3秒を超えています。低速ルート、上流モデル、ファイルI/Oを確認してください。',
        ),
      );
    } else if (p95 >= 1000) {
      score -= 8;
      alerts.add(_OpsDiagnosisAlert(p95LatencyLabel, '>= 1000ms', '${p95}ms'));
      recommendations.add(
        openHandLocalizedText(
          context,
          zh: 'P95 延迟超过 1s，可结合 Top Routes 排查热点路径。',
          zhHant: 'P95 延遲超過 1s，可結合 Top Routes 排查熱點路徑。',
          en: 'P95 latency is above 1s. Use top routes to inspect hot paths.',
          fr: 'La latence P95 dépasse 1 s. Utilisez les routes principales pour trouver les chemins chauds.',
          de: 'P95-Latenz über 1 s. Nutzen Sie Top-Routen zur Hotpath-Analyse.',
          ja: 'P95レイテンシが1秒を超えています。トップルートと合わせてホットパスを確認してください。',
        ),
      );
    }
    if (snapshot.crashCount > 0 || snapshot.restartCount > 0) {
      score -= math.min(
        12,
        snapshot.crashCount * 6 + snapshot.restartCount * 2,
      );
      alerts.add(
        _OpsDiagnosisAlert(
          openHandLocalizedText(
            context,
            zh: '崩溃/重启',
            zhHant: '崩潰/重啟',
            en: 'Crashes/restarts',
            fr: 'Plantages/redémarrages',
            de: 'Abstürze/Neustarts',
            ja: 'クラッシュ/再起動',
          ),
          '= 0',
          '${snapshot.crashCount}/${snapshot.restartCount}',
        ),
      );
    }
    if (logErrors > 0) {
      score -= math.min(10, logErrors);
      alerts.add(
        _OpsDiagnosisAlert(
          openHandLocalizedText(
            context,
            zh: '错误日志',
            zhHant: '錯誤日誌',
            en: 'Error logs',
            fr: 'Journaux d’erreur',
            de: 'Fehlerprotokolle',
            ja: 'エラーログ',
          ),
          '= 0',
          '$logErrors',
        ),
      );
    }
    if (recommendations.isEmpty) {
      recommendations.add(
        openHandLocalizedText(
          context,
          zh: '当前核心信号平稳，保持自动刷新并关注错误率、P95 延迟和并发水位。',
          zhHant: '目前核心信號平穩，保持自動刷新並關注錯誤率、P95 延遲和並發水位。',
          en: 'Core signals are stable. Keep auto-refresh on and watch error rate, P95 latency, and concurrency.',
          fr: 'Les signaux clés sont stables. Gardez l’actualisation et surveillez le taux d’erreur, la latence P95 et la concurrence.',
          de: 'Kernsignale sind stabil. Lassen Sie Auto-Refresh aktiv und beobachten Sie Fehlerrate, P95-Latenz und Parallelität.',
          ja: '主要シグナルは安定しています。自動更新を維持し、エラー率、P95レイテンシ、同時実行水位を確認してください。',
        ),
      );
    }
    score = score.clamp(0, 100).toInt();
    final tone = score >= 85
        ? _OpsDiagnosisTone.ok
        : score >= 65
        ? _OpsDiagnosisTone.warn
        : _OpsDiagnosisTone.error;
    final label = switch (tone) {
      _OpsDiagnosisTone.ok => openHandLocalizedText(
        context,
        zh: '健康',
        zhHant: '健康',
        en: 'Healthy',
        fr: 'Sain',
        de: 'Gesund',
        ja: '正常',
      ),
      _OpsDiagnosisTone.warn => openHandLocalizedText(
        context,
        zh: '需关注',
        zhHant: '需關注',
        en: 'Needs attention',
        fr: 'À surveiller',
        de: 'Beobachten',
        ja: '要注意',
      ),
      _OpsDiagnosisTone.error => openHandLocalizedText(
        context,
        zh: '异常',
        zhHant: '異常',
        en: 'Unhealthy',
        fr: 'Anormal',
        de: 'Fehlerhaft',
        ja: '異常',
      ),
    };
    return _OpsDiagnosis(
      score: score,
      label: label,
      tone: tone,
      recommendations: recommendations.take(4).toList(growable: false),
      alerts: alerts,
      signals: [
        _OpsDiagnosisSignal(errorRateLabel, _percent(errorRate)),
        _OpsDiagnosisSignal('P95', p95 > 0 ? '${p95}ms' : '—'),
        _OpsDiagnosisSignal('P99', p99 > 0 ? '${p99}ms' : '—'),
        _OpsDiagnosisSignal(concurrencyLabel, _percent(saturation)),
        _OpsDiagnosisSignal(
          errorsPerMinuteLabel,
          _rate(snapshot.errorsPerMinute),
        ),
        _OpsDiagnosisSignal('SSE', '${snapshot.activeSseSubscriptions}'),
      ],
    );
  }

  final int score;
  final String label;
  final _OpsDiagnosisTone tone;
  final List<_OpsDiagnosisSignal> signals;
  final List<_OpsDiagnosisAlert> alerts;
  final List<String> recommendations;
}

class _OpsSummaryCard extends StatelessWidget {
  const _OpsSummaryCard({required this.snapshot});

  final WebGatewayRuntimeSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slow = snapshot.slowestRecent;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _opsCardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.monitor_heart_outlined, size: 18),
              const SizedBox(width: 8),
              Text(
                openHandLocalizedText(
                  context,
                  zh: '核心信号',
                  zhHant: '核心信號',
                  en: 'Golden Signals',
                  fr: 'Signaux clés',
                  de: 'Golden Signals',
                  ja: '主要シグナル',
                ),
                style: theme.textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _OpsPill(
                openHandLocalizedText(
                  context,
                  zh: '流量',
                  zhHant: '流量',
                  en: 'Traffic',
                  fr: 'Trafic',
                  de: 'Traffic',
                  ja: 'トラフィック',
                ),
                openHandLocalizedText(
                  context,
                  zh: '${_rate(snapshot.requestsPerMinute)} 请求/min',
                  zhHant: '${_rate(snapshot.requestsPerMinute)} 請求/min',
                  en: '${_rate(snapshot.requestsPerMinute)} req/min',
                  fr: '${_rate(snapshot.requestsPerMinute)} req/min',
                  de: '${_rate(snapshot.requestsPerMinute)} Anfragen/min',
                  ja: '${_rate(snapshot.requestsPerMinute)} リクエスト/min',
                ),
              ),
              _OpsPill(
                openHandLocalizedText(
                  context,
                  zh: '错误',
                  zhHant: '錯誤',
                  en: 'Errors',
                  fr: 'Erreurs',
                  de: 'Fehler',
                  ja: 'エラー',
                ),
                openHandLocalizedText(
                  context,
                  zh: '${_rate(snapshot.errorsPerMinute)} 错误/min',
                  zhHant: '${_rate(snapshot.errorsPerMinute)} 錯誤/min',
                  en: '${_rate(snapshot.errorsPerMinute)} err/min',
                  fr: '${_rate(snapshot.errorsPerMinute)} err/min',
                  de: '${_rate(snapshot.errorsPerMinute)} Fehler/min',
                  ja: '${_rate(snapshot.errorsPerMinute)} エラー/min',
                ),
              ),
              _OpsPill(
                openHandLocalizedText(
                  context,
                  zh: '延迟',
                  zhHant: '延遲',
                  en: 'Latency',
                  fr: 'Latence',
                  de: 'Latenz',
                  ja: 'レイテンシ',
                ),
                openHandLocalizedText(
                  context,
                  zh: '平均 ${snapshot.latencyStats.avgMs}ms / p95 ${snapshot.latencyStats.p95Ms}ms / p99 ${snapshot.latencyStats.p99Ms}ms',
                  zhHant:
                      '平均 ${snapshot.latencyStats.avgMs}ms / p95 ${snapshot.latencyStats.p95Ms}ms / p99 ${snapshot.latencyStats.p99Ms}ms',
                  en: 'avg ${snapshot.latencyStats.avgMs}ms / p95 ${snapshot.latencyStats.p95Ms}ms / p99 ${snapshot.latencyStats.p99Ms}ms',
                  fr: 'moy ${snapshot.latencyStats.avgMs}ms / p95 ${snapshot.latencyStats.p95Ms}ms / p99 ${snapshot.latencyStats.p99Ms}ms',
                  de: 'Ø ${snapshot.latencyStats.avgMs}ms / p95 ${snapshot.latencyStats.p95Ms}ms / p99 ${snapshot.latencyStats.p99Ms}ms',
                  ja: '平均 ${snapshot.latencyStats.avgMs}ms / p95 ${snapshot.latencyStats.p95Ms}ms / p99 ${snapshot.latencyStats.p99Ms}ms',
                ),
              ),
              _OpsPill(
                openHandLocalizedText(
                  context,
                  zh: '饱和度',
                  zhHant: '飽和度',
                  en: 'Saturation',
                  fr: 'Saturation',
                  de: 'Sättigung',
                  ja: '飽和度',
                ),
                openHandLocalizedText(
                  context,
                  zh: '${snapshot.activeRequests}/${snapshot.maxConcurrentRequests} 活动 · ${_percent(snapshot.activeRequestRatio)}',
                  zhHant:
                      '${snapshot.activeRequests}/${snapshot.maxConcurrentRequests} 活動 · ${_percent(snapshot.activeRequestRatio)}',
                  en: '${snapshot.activeRequests}/${snapshot.maxConcurrentRequests} active · ${_percent(snapshot.activeRequestRatio)}',
                  fr: '${snapshot.activeRequests}/${snapshot.maxConcurrentRequests} actives · ${_percent(snapshot.activeRequestRatio)}',
                  de: '${snapshot.activeRequests}/${snapshot.maxConcurrentRequests} aktiv · ${_percent(snapshot.activeRequestRatio)}',
                  ja: '${snapshot.activeRequests}/${snapshot.maxConcurrentRequests} アクティブ · ${_percent(snapshot.activeRequestRatio)}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _OpsKeyValue(
            openHandLocalizedText(
              context,
              zh: '绑定地址',
              zhHant: '綁定位址',
              en: 'Bound address',
              fr: 'Adresse liée',
              de: 'Gebundene Adresse',
              ja: 'バインドアドレス',
            ),
            snapshot.boundUrl.isEmpty
                ? openHandLocalizedText(
                    context,
                    zh: '未监听',
                    zhHant: '未監聽',
                    en: 'Not listening',
                    fr: 'Pas à l’écoute',
                    de: 'Nicht lauschend',
                    ja: 'リッスンなし',
                  )
                : snapshot.boundUrl,
          ),
          _OpsKeyValue(
            openHandLocalizedText(
              context,
              zh: '可访问 URL',
              zhHant: '可存取 URL',
              en: 'Accessible URLs',
              fr: 'URL accessibles',
              de: 'Erreichbare URLs',
              ja: 'アクセス可能なURL',
            ),
            snapshot.accessibleUrls.isEmpty
                ? openHandLocalizedText(
                    context,
                    zh: '暂无',
                    zhHant: '暫無',
                    en: 'None',
                    fr: 'Aucune',
                    de: 'Keine',
                    ja: 'なし',
                  )
                : snapshot.accessibleUrls.join(' / '),
          ),
          _OpsKeyValue(
            openHandLocalizedText(
              context,
              zh: '主机 / Dart',
              zhHant: '主機 / Dart',
              en: 'Host / Dart',
              fr: 'Hôte / Dart',
              de: 'Host / Dart',
              ja: 'ホスト / Dart',
            ),
            '${snapshot.hostName.isEmpty ? 'unknown' : snapshot.hostName} · ${snapshot.dartVersion.isEmpty ? 'unknown' : snapshot.dartVersion}',
          ),
          if (slow != null)
            _OpsKeyValue(
              openHandLocalizedText(
                context,
                zh: '近期最慢请求',
                zhHant: '近期最慢請求',
                en: 'Slowest recent request',
                fr: 'Requête récente la plus lente',
                de: 'Langsamste aktuelle Anfrage',
                ja: '最近最も遅いリクエスト',
              ),
              '${slow.method} ${slow.path} -> ${slow.statusCode} · ${slow.durationMs}ms${slow.at == null ? '' : ' · ${formatYearMonthDayHms(slow.at!.toLocal())}'}',
            ),
        ],
      ),
    );
  }
}

class _OpsBreakdownCard extends StatelessWidget {
  const _OpsBreakdownCard({
    required this.title,
    required this.values,
    this.footer,
  });

  final String title;
  final Map<String, int> values;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = values.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<int>(0, (sum, entry) => sum + entry.value);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _opsCardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 10),
          if (entries.isEmpty)
            Text(
              openHandLocalizedText(
                context,
                zh: '暂无样本',
                zhHant: '暫無樣本',
                en: 'No samples yet',
                fr: 'Aucun échantillon',
                de: 'Noch keine Stichproben',
                ja: 'サンプルはまだありません',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            ...entries
                .take(8)
                .map(
                  (entry) => _OpsDistributionRow(
                    label: entry.key,
                    value: entry.value,
                    total: total,
                  ),
                ),
          if (footer != null) ...[
            const SizedBox(height: 12),
            Text(
              footer!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OpsDistributionRow extends StatelessWidget {
  const _OpsDistributionRow({
    required this.label,
    required this.value,
    required this.total,
  });

  final String label;
  final int value;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = unitRatio(value, total);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium,
                ),
              ),
              const SizedBox(width: 8),
              Text('$value', style: theme.textTheme.labelMedium),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(value: ratio, minHeight: 5),
          ),
        ],
      ),
    );
  }
}

class _TopRoutesCard extends StatelessWidget {
  const _TopRoutesCard({required this.routes});

  final List<MapEntry<String, int>> routes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _opsCardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            openHandLocalizedText(
              context,
              zh: '高频路由',
              zhHant: '高頻路由',
              en: 'Top Routes',
              fr: 'Routes principales',
              de: 'Top-Routen',
              ja: '上位ルート',
            ),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 10),
          if (routes.isEmpty)
            Text(
              openHandLocalizedText(
                context,
                zh: '暂无路由样本',
                zhHant: '暫無路由樣本',
                en: 'No route samples yet',
                fr: 'Aucun échantillon de route',
                de: 'Noch keine Routenstichproben',
                ja: 'ルートサンプルはまだありません',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            ...routes
                .take(8)
                .map(
                  (entry) => _OpsKeyValue(
                    entry.key,
                    openHandLocalizedText(
                      context,
                      zh: '${entry.value} 次',
                      zhHant: '${entry.value} 次',
                      en: '${entry.value} times',
                      fr: '${entry.value} fois',
                      de: '${entry.value} Mal',
                      ja: '${entry.value} 回',
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

class _RecentErrorsCard extends StatelessWidget {
  const _RecentErrorsCard({required this.errors});

  final List<Map<String, Object?>> errors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _opsCardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            openHandLocalizedText(
              context,
              zh: '近期错误请求',
              zhHant: '近期錯誤請求',
              en: 'Recent error requests',
              fr: 'Requêtes récentes en erreur',
              de: 'Aktuelle Fehleranfragen',
              ja: '最近のエラーリクエスト',
            ),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 10),
          if (errors.isEmpty)
            Text(
              openHandLocalizedText(
                context,
                zh: '暂无 4xx/5xx 请求',
                zhHant: '暫無 4xx/5xx 請求',
                en: 'No 4xx/5xx requests yet',
                fr: 'Aucune requête 4xx/5xx',
                de: 'Noch keine 4xx/5xx-Anfragen',
                ja: '4xx/5xx リクエストはまだありません',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            ...errors.reversed.take(6).map((entry) {
              final method = entry['method']?.toString() ?? '';
              final path = entry['path']?.toString() ?? '';
              final status = entry['status']?.toString() ?? '';
              final duration = entry['duration_ms']?.toString() ?? '';
              return _OpsKeyValue('$method $path', '$status · ${duration}ms');
            }),
        ],
      ),
    );
  }
}

class _ResourceInventoryCard extends StatelessWidget {
  const _ResourceInventoryCard({required this.snapshot});

  final WebGatewayRuntimeSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _opsCardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            openHandLocalizedText(
              context,
              zh: 'Web 可见资源',
              zhHant: 'Web 可見資源',
              en: 'Web-visible resources',
              fr: 'Ressources visibles par le web',
              de: 'Websichtbare Ressourcen',
              ja: 'Web表示リソース',
            ),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _OpsPill(
                openHandLocalizedText(
                  context,
                  zh: '模型',
                  zhHant: '模型',
                  en: 'Models',
                  fr: 'Modèles',
                  de: 'Modelle',
                  ja: 'モデル',
                ),
                '${snapshot.allowedModelCount}',
              ),
              _OpsPill(
                openHandLocalizedText(
                  context,
                  zh: '供应商',
                  zhHant: '供應商',
                  en: 'Providers',
                  fr: 'Fournisseurs',
                  de: 'Anbieter',
                  ja: 'プロバイダー',
                ),
                '${snapshot.modelProviderCount}',
              ),
              _OpsPill(
                openHandLocalizedText(
                  context,
                  zh: '模板',
                  zhHant: '模板',
                  en: 'Templates',
                  fr: 'Modèles',
                  de: 'Vorlagen',
                  ja: 'テンプレート',
                ),
                '${snapshot.templateCount}',
              ),
              _OpsPill(
                openHandLocalizedText(
                  context,
                  zh: '定时任务',
                  zhHant: '定時任務',
                  en: 'Crons',
                  fr: 'Tâches cron',
                  de: 'Cronjobs',
                  ja: 'Cron',
                ),
                '${snapshot.cronEnabledCount}/${snapshot.cronTotalCount}',
              ),
              _OpsPill(
                openHandLocalizedText(
                  context,
                  zh: '记忆',
                  zhHant: '記憶',
                  en: 'Memory',
                  fr: 'Mémoire',
                  de: 'Speicher',
                  ja: 'メモリ',
                ),
                '${snapshot.memoryEntryCount}',
              ),
              _OpsPill(
                'MCP',
                '${snapshot.mcpServerEnabledCount}/${snapshot.mcpServerTotalCount}',
              ),
              _OpsPill('SSE', '${snapshot.activeSseSubscriptions}'),
              _OpsPill(
                openHandLocalizedText(
                  context,
                  zh: '会话',
                  zhHant: '會話',
                  en: 'Sessions',
                  fr: 'Sessions',
                  de: 'Sitzungen',
                  ja: 'セッション',
                ),
                '${snapshot.openSessionCount}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OpsPill extends StatelessWidget {
  const _OpsPill(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.48,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: RichText(
        text: TextSpan(
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
          children: [
            TextSpan(
              text: '$label ',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpsKeyValue extends StatelessWidget {
  const _OpsKeyValue(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              value,
              maxLines: 2,
              style: theme.textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );
  }
}

BoxDecoration _opsCardDecoration(ThemeData theme) => BoxDecoration(
  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.36),
  borderRadius: BorderRadius.circular(8),
  border: Border.all(color: theme.colorScheme.outlineVariant),
);

class _SwitchGrid extends StatelessWidget {
  const _SwitchGrid({required this.twoColumns, required this.children});
  final bool twoColumns;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => GridView.count(
    crossAxisCount: twoColumns ? 2 : 1,
    childAspectRatio: twoColumns ? 5.0 : 5.8,
    crossAxisSpacing: 12,
    mainAxisSpacing: 12,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    children: children,
  );
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return AnimatedContainer(
      duration: openHandMotionDurationMs(context, 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: value
            ? colorScheme.primaryContainer.withValues(alpha: .34)
            : colorScheme.surfaceContainerHighest.withValues(alpha: .42),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: value
              ? colorScheme.primary.withValues(alpha: .32)
              : colorScheme.outlineVariant.withValues(alpha: .78),
        ),
      ),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        title: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: value ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        contentPadding: const EdgeInsetsDirectional.fromSTEB(14, 0, 10, 0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

class _TextArea extends StatelessWidget {
  const _TextArea({required this.label, required this.controller});
  final String label;
  final TextEditingController controller;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      minLines: 3,
      maxLines: 5,
      decoration: _gatewayInputDecoration(context, label),
    ),
  );
}

class _TextFieldSpec {
  const _TextFieldSpec({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.obscureText = false,
  });
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final bool obscureText;
}

class _ResponsiveFields extends StatelessWidget {
  const _ResponsiveFields({required this.twoColumns, required this.children});
  final bool twoColumns;
  final List<_TextFieldSpec> children;
  @override
  Widget build(BuildContext context) => GridView.count(
    crossAxisCount: twoColumns ? 2 : 1,
    childAspectRatio: twoColumns ? 5.0 : 6.0,
    crossAxisSpacing: 12,
    mainAxisSpacing: 12,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    children: children
        .map(
          (spec) => TextField(
            controller: spec.controller,
            keyboardType: spec.keyboardType,
            obscureText: spec.obscureText,
            decoration: _gatewayInputDecoration(context, spec.label),
          ),
        )
        .toList(growable: false),
  );
}

InputDecoration _gatewayInputDecoration(BuildContext context, String label) {
  final colorScheme = Theme.of(context).colorScheme;
  final radius = BorderRadius.circular(16);
  final border = OutlineInputBorder(
    borderRadius: radius,
    borderSide: BorderSide(
      color: colorScheme.outlineVariant.withValues(alpha: .78),
    ),
  );
  return InputDecoration(
    labelText: label,
    filled: true,
    fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: .44),
    border: border,
    enabledBorder: border,
    focusedBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
    ),
  );
}

class _SelectOption<T> {
  const _SelectOption({required this.value, required this.label});
  final T value;
  final String label;
}

class _MultiSelectDropdown<T> extends StatefulWidget {
  const _MultiSelectDropdown({
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.emptyMeansAll = false,
    this.noneValue,
  });

  final String label;
  final List<_SelectOption<T>> options;
  final Set<T> selected;
  final ValueChanged<Set<T>> onChanged;
  final bool emptyMeansAll;
  final T? noneValue;

  @override
  State<_MultiSelectDropdown<T>> createState() =>
      _MultiSelectDropdownState<T>();
}

class _MultiSelectDropdownState<T> extends State<_MultiSelectDropdown<T>> {
  final MenuController _menuController = MenuController();

  @override
  Widget build(BuildContext context) {
    if (widget.options.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: MenuAnchor(
        controller: _menuController,
        alignmentOffset: const Offset(0, 8),
        menuChildren: [
          _MultiSelectDropdownMenu<T>(
            label: widget.label,
            options: widget.options,
            selected: widget.selected,
            emptyMeansAll: widget.emptyMeansAll,
            noneValue: widget.noneValue,
            onApply: widget.onChanged,
            onClose: _menuController.close,
          ),
        ],
        builder: (context, controller, child) {
          final open = controller.isOpen;
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => open ? controller.close() : controller.open(),
            child: InputDecorator(
              decoration:
                  _gatewayInputDecoration(
                    context,
                    widget.emptyMeansAll
                        ? _gatewayEmptyMeansAllLabel(context, widget.label)
                        : widget.label,
                  ).copyWith(
                    suffixIcon: Icon(
                      open
                          ? Icons.arrow_drop_up_rounded
                          : Icons.arrow_drop_down_rounded,
                    ),
                  ),
              child: Text(
                _summary(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          );
        },
      ),
    );
  }

  String _summary(BuildContext context) {
    if (_isExplicitNone(widget.selected, widget.noneValue)) {
      return openHandLocalizedText(
        context,
        zh: '全部不可用',
        zhHant: '全部不可用',
        en: 'All unavailable',
        fr: 'Tout indisponible',
        de: 'Alle nicht verfügbar',
        ja: 'すべて利用不可',
      );
    }
    if (widget.emptyMeansAll && widget.selected.isEmpty) {
      return openHandLocalizedText(
        context,
        zh: '全部可用',
        zhHant: '全部可用',
        en: 'All available',
        fr: 'Tout disponible',
        de: 'Alle verfügbar',
        ja: 'すべて利用可能',
      );
    }
    if (widget.selected.isEmpty) {
      return openHandLocalizedText(
        context,
        zh: '未选择',
        zhHant: '未選擇',
        en: 'None selected',
        fr: 'Aucune sélection',
        de: 'Nichts ausgewählt',
        ja: '未選択',
      );
    }
    final labels = widget.options
        .where((option) => widget.selected.contains(option.value))
        .map((option) => option.label)
        .toList(growable: false);
    final separator = _gatewayListSeparator(context);
    if (labels.length <= 2) return labels.join(separator);
    return openHandLocalizedText(
      context,
      zh: '${labels.take(2).join(separator)} 等 ${labels.length} 项',
      zhHant: '${labels.take(2).join(separator)} 等 ${labels.length} 項',
      en: '${labels.take(2).join(separator)} and ${labels.length} items',
      fr: '${labels.take(2).join(separator)} et ${labels.length} éléments',
      de: '${labels.take(2).join(separator)} und ${labels.length} Einträge',
      ja: '${labels.take(2).join(separator)} ほか ${labels.length} 項目',
    );
  }
}

class _MultiSelectDropdownMenu<T> extends StatefulWidget {
  const _MultiSelectDropdownMenu({
    required this.label,
    required this.options,
    required this.selected,
    required this.emptyMeansAll,
    required this.noneValue,
    required this.onApply,
    required this.onClose,
  });

  final String label;
  final List<_SelectOption<T>> options;
  final Set<T> selected;
  final bool emptyMeansAll;
  final T? noneValue;
  final ValueChanged<Set<T>> onApply;
  final VoidCallback onClose;

  @override
  State<_MultiSelectDropdownMenu<T>> createState() =>
      _MultiSelectDropdownMenuState<T>();
}

class _MultiSelectDropdownMenuState<T>
    extends State<_MultiSelectDropdownMenu<T>>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  late final AnimationController _transitionController;
  late Set<T> _selected;
  bool _closing = false;
  DialogAnimationSettings? _lastMotionSettings;

  @override
  void initState() {
    super.initState();
    _transitionController = AnimationController(vsync: this);
    _selected = Set<T>.from(widget.selected);
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = _menuMotionSettingsOf(context);
    _lastMotionSettings = settings;
    _transitionController
      ..duration = settings.duration
      ..reverseDuration = settings.duration;
    if (_transitionController.value == 0 && !_closing) {
      if (!openHandTickerMotionEnabled(context) ||
          settings.duration == Duration.zero) {
        _transitionController.value = 1;
      } else {
        unawaited(_transitionController.forward());
      }
    }
  }

  @override
  void didUpdateWidget(covariant _MultiSelectDropdownMenu<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      _selected = Set<T>.from(widget.selected);
    }
  }

  @override
  void dispose() {
    _transitionController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final settings = _lastMotionSettings ?? _menuMotionSettingsOf(context);
    final query = _searchController.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? widget.options
        : widget.options
              .where((option) => option.label.toLowerCase().contains(query))
              .toList(growable: false);
    final filteredValues = filtered.map((option) => option.value).toSet();
    final totalValues = widget.options.map((option) => option.value).toSet();
    final effectiveSelected = _effectiveSelectedValues();
    final selectedCount = effectiveSelected.length;
    final scopeText = query.isEmpty
        ? _gatewayScopeAll(context)
        : openHandLocalizedText(
            context,
            zh: '当前筛选 ${filtered.length} 项',
            zhHant: '目前篩選 ${filtered.length} 項',
            en: 'Current filter: ${filtered.length} items',
            fr: 'Filtre actuel : ${filtered.length} éléments',
            de: 'Aktueller Filter: ${filtered.length} Einträge',
            ja: '現在の絞り込み: ${filtered.length} 項目',
          );
    return Align(
      alignment: Alignment.topLeft,
      child: buildAnimationStyleTransition(
        animation: _transitionController,
        settings: settings,
        child: Material(
          type: MaterialType.card,
          clipBehavior: Clip.antiAlias,
          elevation: 14,
          shadowColor: colorScheme.shadow.withValues(alpha: 0.18),
          surfaceTintColor: colorScheme.surfaceTint,
          color: colorScheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.72),
            ),
          ),
          child: SizedBox(
            width: 460,
            height: 410,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 14, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Icon(
                          Icons.tune_rounded,
                          size: 18,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.label,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _selectionSummaryText(
                                context,
                                selectedCount,
                                totalValues.length,
                                scopeText,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _GatewayRoundIconActionButton(
                        tooltip: query.isEmpty
                            ? openHandLocalizedText(
                                context,
                                zh: '全选',
                                zhHant: '全選',
                                en: 'Select all',
                                fr: 'Tout sélectionner',
                                de: 'Alle auswählen',
                                ja: 'すべて選択',
                              )
                            : openHandLocalizedText(
                                context,
                                zh: '当前筛选全选',
                                zhHant: '目前篩選全選',
                                en: 'Select filtered',
                                fr: 'Sélectionner le filtre',
                                de: 'Gefilterte auswählen',
                                ja: '絞り込み結果を全選択',
                              ),
                        icon: Icons.done_all_rounded,
                        onPressed: filteredValues.isEmpty
                            ? null
                            : () => _selectValues(filteredValues),
                      ),
                      const SizedBox(width: 8),
                      _GatewayRoundIconActionButton(
                        tooltip: query.isEmpty
                            ? openHandLocalizedText(
                                context,
                                zh: '全不选',
                                zhHant: '全不選',
                                en: 'Deselect all',
                                fr: 'Tout désélectionner',
                                de: 'Alle abwählen',
                                ja: 'すべて解除',
                              )
                            : openHandLocalizedText(
                                context,
                                zh: '当前筛选全不选',
                                zhHant: '目前篩選全不選',
                                en: 'Deselect filtered',
                                fr: 'Désélectionner le filtre',
                                de: 'Gefilterte abwählen',
                                ja: '絞り込み結果を全解除',
                              ),
                        icon: Icons.remove_done_rounded,
                        onPressed: filteredValues.isEmpty
                            ? null
                            : () => _deselectValues(filteredValues),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.58,
                      ),
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      hintText: openHandLocalizedText(
                        context,
                        zh: '搜索',
                        zhHant: '搜尋',
                        en: 'Search',
                        fr: 'Rechercher',
                        de: 'Suchen',
                        ja: '検索',
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: colorScheme.outlineVariant,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.72,
                          ),
                        ),
                      ),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: openHandLocalizedText(
                                context,
                                zh: '清空搜索',
                                zhHant: '清空搜尋',
                                en: 'Clear search',
                                fr: 'Effacer la recherche',
                                de: 'Suche leeren',
                                ja: '検索をクリア',
                              ),
                              onPressed: _searchController.clear,
                              icon: const Icon(Icons.clear_rounded, size: 18),
                            ),
                    ),
                  ),
                ),
                Divider(height: 1, color: colorScheme.outlineVariant),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            openHandLocalizedText(
                              context,
                              zh: '没有匹配项',
                              zhHant: '沒有符合項目',
                              en: 'No matches',
                              fr: 'Aucune correspondance',
                              de: 'Keine Treffer',
                              ja: '一致する項目はありません',
                            ),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                          itemCount: filtered.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 4),
                          itemBuilder: (context, index) {
                            final option = filtered[index];
                            final selected = effectiveSelected.contains(
                              option.value,
                            );
                            return Material(
                              color: selected
                                  ? colorScheme.primaryContainer.withValues(
                                      alpha: 0.36,
                                    )
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(14),
                              child: CheckboxListTile(
                                dense: true,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                value: selected,
                                onChanged: (_) => _toggle(option.value),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                title: Text(
                                  option.label,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                Divider(height: 1, color: colorScheme.outlineVariant),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          query.isEmpty
                              ? openHandLocalizedText(
                                  context,
                                  zh: '对全部条目生效',
                                  zhHant: '對全部項目生效',
                                  en: 'Applies to all items',
                                  fr: 'S’applique à tous les éléments',
                                  de: 'Gilt für alle Einträge',
                                  ja: 'すべての項目に適用',
                                )
                              : openHandLocalizedText(
                                  context,
                                  zh: '仅对当前筛选结果生效',
                                  zhHant: '僅對目前篩選結果生效',
                                  en: 'Applies only to filtered results',
                                  fr: 'S’applique seulement aux résultats filtrés',
                                  de: 'Gilt nur für gefilterte Ergebnisse',
                                  ja: '現在の絞り込み結果だけに適用',
                                ),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      _MenuActionButton(
                        onPressed: _applyAndClose,
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: Text(
                          openHandLocalizedText(
                            context,
                            zh: '完成',
                            zhHant: '完成',
                            en: 'Done',
                            fr: 'Terminé',
                            de: 'Fertig',
                            ja: '完了',
                          ),
                        ),
                        filled: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _toggle(T value) {
    final next = _effectiveSelectedValues();
    if (next.contains(value)) {
      next.remove(value);
    } else {
      next.add(value);
    }
    _setEffectiveSelected(next);
  }

  Set<T> _effectiveSelectedValues() {
    if (_isExplicitNone(_selected, widget.noneValue)) return <T>{};
    if (widget.emptyMeansAll && _selected.isEmpty) {
      return widget.options.map((option) => option.value).toSet();
    }
    final values = widget.options.map((option) => option.value).toSet();
    return _selected.where(values.contains).toSet();
  }

  void _selectValues(Set<T> values) {
    final next = _effectiveSelectedValues()..addAll(values);
    _setEffectiveSelected(next);
  }

  void _deselectValues(Set<T> values) {
    final next = _effectiveSelectedValues()..removeAll(values);
    _setEffectiveSelected(next);
  }

  void _setEffectiveSelected(Set<T> values) {
    final allValues = widget.options.map((option) => option.value).toSet();
    if (values.isEmpty) {
      final noneValue = widget.noneValue;
      _setSelected(noneValue == null ? <T>{} : <T>{noneValue});
      return;
    }
    if (widget.emptyMeansAll && values.length == allValues.length) {
      _setSelected(<T>{});
      return;
    }
    _setSelected(values.intersection(allValues));
  }

  void _setSelected(Set<T> next) {
    setState(() => _selected = next);
  }

  void _applyAndClose() {
    if (_closing) return;
    widget.onApply(Set<T>.from(_selected));
    if (!openHandTickerMotionEnabled(context) ||
        _transitionController.duration == Duration.zero) {
      widget.onClose();
      return;
    }
    _closing = true;
    unawaited(
      _transitionController.reverse().whenComplete(() {
        if (mounted) widget.onClose();
      }),
    );
  }

  String _selectionSummaryText(
    BuildContext context,
    int selectedCount,
    int totalCount,
    String scope,
  ) {
    if (_isExplicitNone(_selected, widget.noneValue)) {
      return '$scope · ${openHandLocalizedText(context, zh: '全部不可用', zhHant: '全部不可用', en: 'All unavailable', fr: 'Tout indisponible', de: 'Alle nicht verfügbar', ja: 'すべて利用不可')}';
    }
    if (widget.emptyMeansAll && _selected.isEmpty) {
      return '$scope · ${openHandLocalizedText(context, zh: '全部可用', zhHant: '全部可用', en: 'All available', fr: 'Tout disponible', de: 'Alle verfügbar', ja: 'すべて利用可能')}';
    }
    return '$scope · ${_gatewaySelectedCount(context, selectedCount, totalCount)}';
  }
}

bool _isExplicitNone<T>(Set<T> selected, T? noneValue) {
  return noneValue != null && selected.contains(noneValue);
}

DialogAnimationSettings _menuMotionSettingsOf(BuildContext context) {
  return openHandMotionSettingsFallbackOf(
    context,
    OpenHandMotionSettingsScope.menu,
  );
}

class _GatewayRoundIconActionButton extends StatelessWidget {
  const _GatewayRoundIconActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton.filledTonal(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        style: IconButton.styleFrom(
          fixedSize: const Size(38, 38),
          minimumSize: const Size(38, 38),
          padding: EdgeInsets.zero,
          shape: const CircleBorder(),
        ),
      ),
    );
  }
}

class _MenuActionButton extends StatelessWidget {
  const _MenuActionButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    this.filled = false,
  });

  final VoidCallback onPressed;
  final Widget icon;
  final Widget label;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final style = filled
        ? FilledButton.styleFrom(
            minimumSize: const Size(104, 44),
            padding: const EdgeInsets.symmetric(horizontal: 14),
          )
        : TextButton.styleFrom(
            minimumSize: const Size(104, 44),
            padding: const EdgeInsets.symmetric(horizontal: 14),
          );
    if (filled) {
      return FilledButton.tonalIcon(
        onPressed: onPressed,
        icon: icon,
        label: label,
        style: style,
      );
    }
    return TextButton.icon(
      onPressed: onPressed,
      icon: icon,
      label: label,
      style: style,
    );
  }
}

class _EnumMultiSelectDropdown<T> extends StatelessWidget {
  const _EnumMultiSelectDropdown({
    required this.label,
    required this.values,
    required this.selected,
    required this.labelFor,
    required this.onChanged,
  });

  final String label;
  final List<T> values;
  final Set<T> selected;
  final String Function(T value) labelFor;
  final ValueChanged<Set<T>> onChanged;

  @override
  Widget build(BuildContext context) => _MultiSelectDropdown<T>(
    label: label,
    options: values
        .map((value) => _SelectOption<T>(value: value, label: labelFor(value)))
        .toList(growable: false),
    selected: selected,
    onChanged: onChanged,
  );
}

class _ModelMultiSelectField extends StatelessWidget {
  const _ModelMultiSelectField({
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.emptyMeansAll = false,
  });

  final String label;
  final List<WebGatewayModelOption> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final bool emptyMeansAll;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final result = await showAnimatedDialog<Set<String>>(
            context: context,
            builder: (_) => _ModelMultiSelectDialog(
              options: options,
              selected: selected,
              emptyMeansAll: emptyMeansAll,
            ),
          );
          if (result != null) onChanged(result);
        },
        child: InputDecorator(
          decoration: _gatewayInputDecoration(
            context,
            emptyMeansAll ? _gatewayEmptyMeansAllLabel(context, label) : label,
          ).copyWith(suffixIcon: const Icon(Icons.manage_search_rounded)),
          child: Text(
            _modelSummary(context, options, selected, emptyMeansAll),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ),
    );
  }
}

class _ModelMultiSelectDialog extends StatefulWidget {
  const _ModelMultiSelectDialog({
    required this.options,
    required this.selected,
    required this.emptyMeansAll,
  });

  final List<WebGatewayModelOption> options;
  final Set<String> selected;
  final bool emptyMeansAll;

  @override
  State<_ModelMultiSelectDialog> createState() =>
      _ModelMultiSelectDialogState();
}

class _ModelMultiSelectDialogState extends State<_ModelMultiSelectDialog> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.selected);
    _searchController.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final query = _searchController.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? widget.options
        : widget.options
              .where((option) => option.label.toLowerCase().contains(query))
              .toList(growable: false);
    // 按 providerId 顺序保留首次出现的 providerLabel，避免标签碰撞造成串组。
    final providerOrder = <String>[];
    final providerLabels = <String, String>{};
    final grouped = <String, List<WebGatewayModelOption>>{};
    for (final option in filtered) {
      final pid = option.providerId;
      if (!grouped.containsKey(pid)) {
        providerOrder.add(pid);
        providerLabels[pid] = option.providerLabel;
      }
      (grouped[pid] ??= <WebGatewayModelOption>[]).add(option);
    }
    final rows = <Object>[];
    for (final pid in providerOrder) {
      rows
        ..add(
          _ProviderGroupHeader(
            providerId: pid,
            providerLabel: providerLabels[pid] ?? pid,
            options: grouped[pid]!,
          ),
        )
        ..addAll(grouped[pid]!);
    }
    final visibleKeys = filtered.map((option) => option.key).toSet();
    final totalKeys = _allModelKeys();
    final effectiveSelected = _effectiveSelectedModelKeys();
    final scopeText = query.isEmpty
        ? openHandLocalizedText(
            context,
            zh: '全部模型',
            zhHant: '全部模型',
            en: 'All models',
            fr: 'Tous les modèles',
            de: 'Alle Modelle',
            ja: 'すべてのモデル',
          )
        : openHandLocalizedText(
            context,
            zh: '当前筛选 ${filtered.length} 个模型',
            zhHant: '目前篩選 ${filtered.length} 個模型',
            en: 'Current filter: ${filtered.length} models',
            fr: 'Filtre actuel : ${filtered.length} modèles',
            de: 'Aktueller Filter: ${filtered.length} Modelle',
            ja: '現在の絞り込み: ${filtered.length} モデル',
          );
    return buildOpenHandDialog(
      backgroundColor: colorScheme.surfaceContainerHigh,
      surfaceTintColor: colorScheme.surfaceTint,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kOpenHandDialogDefaultRadius),
      ),
      maxWidth: 640,
      maxHeight: 680,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 14, 12),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Icon(
                    Icons.hub_outlined,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        openHandLocalizedText(
                          context,
                          zh: '选择可用模型',
                          zhHant: '選擇可用模型',
                          en: 'Choose available models',
                          fr: 'Choisir les modèles disponibles',
                          de: 'Verfügbare Modelle auswählen',
                          ja: '利用可能なモデルを選択',
                        ),
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$scopeText · ${_modelSelectionCountText(context, effectiveSelected.length, totalKeys.length)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _GatewayRoundIconActionButton(
                  tooltip: query.isEmpty
                      ? openHandLocalizedText(
                          context,
                          zh: '全选',
                          zhHant: '全選',
                          en: 'Select all',
                          fr: 'Tout sélectionner',
                          de: 'Alle auswählen',
                          ja: 'すべて選択',
                        )
                      : openHandLocalizedText(
                          context,
                          zh: '当前筛选全选',
                          zhHant: '目前篩選全選',
                          en: 'Select filtered',
                          fr: 'Sélectionner le filtre',
                          de: 'Gefilterte auswählen',
                          ja: '絞り込み結果を全選択',
                        ),
                  icon: Icons.done_all_rounded,
                  onPressed: visibleKeys.isEmpty
                      ? null
                      : () => _selectModelKeys(visibleKeys),
                ),
                const SizedBox(width: 8),
                _GatewayRoundIconActionButton(
                  tooltip: query.isEmpty
                      ? openHandLocalizedText(
                          context,
                          zh: '全不选',
                          zhHant: '全不選',
                          en: 'Deselect all',
                          fr: 'Tout désélectionner',
                          de: 'Alle abwählen',
                          ja: 'すべて解除',
                        )
                      : openHandLocalizedText(
                          context,
                          zh: '当前筛选全不选',
                          zhHant: '目前篩選全不選',
                          en: 'Deselect filtered',
                          fr: 'Désélectionner le filtre',
                          de: 'Gefilterte abwählen',
                          ja: '絞り込み結果を全解除',
                        ),
                  icon: Icons.remove_done_rounded,
                  onPressed: visibleKeys.isEmpty
                      ? null
                      : () => _deselectModelKeys(visibleKeys),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: openHandLocalizedText(
                    context,
                    zh: '关闭',
                    zhHant: '關閉',
                    en: 'Close',
                    fr: 'Fermer',
                    de: 'Schließen',
                    ja: '閉じる',
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              decoration: InputDecoration(
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.58,
                ),
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: openHandLocalizedText(
                  context,
                  zh: '搜索模型',
                  zhHant: '搜尋模型',
                  en: 'Search models',
                  fr: 'Rechercher des modèles',
                  de: 'Modelle suchen',
                  ja: 'モデルを検索',
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.72),
                  ),
                ),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: openHandLocalizedText(
                          context,
                          zh: '清空搜索',
                          zhHant: '清空搜尋',
                          en: 'Clear search',
                          fr: 'Effacer la recherche',
                          de: 'Suche leeren',
                          ja: '検索をクリア',
                        ),
                        onPressed: _searchController.clear,
                        icon: const Icon(Icons.clear_rounded),
                      ),
              ),
            ),
          ),
          Divider(height: 1, color: colorScheme.outlineVariant),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      openHandLocalizedText(
                        context,
                        zh: '没有匹配的模型',
                        zhHant: '沒有符合的模型',
                        en: 'No matching models',
                        fr: 'Aucun modèle correspondant',
                        de: 'Keine passenden Modelle',
                        ja: '一致するモデルはありません',
                      ),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      if (row is _ProviderGroupHeader) {
                        final groupKeys = row.options
                            .map((option) => option.key)
                            .toSet();
                        final selectedInGroup = groupKeys
                            .where(effectiveSelected.contains)
                            .length;
                        final allSelected = selectedInGroup == groupKeys.length;
                        final noneSelected = selectedInGroup == 0;
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(4, 12, 0, 5),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  row.providerLabel,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Text(
                                '$selectedInGroup/${groupKeys.length}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 10),
                              _GatewayRoundIconActionButton(
                                tooltip: openHandLocalizedText(
                                  context,
                                  zh: '本服务商全选',
                                  zhHant: '本供應商全選',
                                  en: 'Select this provider',
                                  fr: 'Sélectionner ce fournisseur',
                                  de: 'Diesen Anbieter auswählen',
                                  ja: 'このプロバイダーを全選択',
                                ),
                                icon: Icons.done_all_rounded,
                                onPressed: allSelected
                                    ? null
                                    : () => _selectGroup(groupKeys),
                              ),
                              const SizedBox(width: 8),
                              _GatewayRoundIconActionButton(
                                tooltip: openHandLocalizedText(
                                  context,
                                  zh: '本服务商全不选',
                                  zhHant: '本供應商全不選',
                                  en: 'Deselect this provider',
                                  fr: 'Désélectionner ce fournisseur',
                                  de: 'Diesen Anbieter abwählen',
                                  ja: 'このプロバイダーを全解除',
                                ),
                                icon: Icons.remove_done_rounded,
                                onPressed: noneSelected
                                    ? null
                                    : () => _deselectGroup(groupKeys),
                              ),
                            ],
                          ),
                        );
                      }
                      final option = row as WebGatewayModelOption;
                      final selected = effectiveSelected.contains(option.key);
                      return CheckboxListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        tileColor: selected
                            ? colorScheme.primaryContainer.withValues(
                                alpha: 0.30,
                              )
                            : null,
                        value: selected,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(
                          option.modelId,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        onChanged: (_) => _toggle(option.key),
                      );
                    },
                  ),
          ),
          Divider(height: 1, color: colorScheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _modelSummary(
                      context,
                      widget.options,
                      _selected,
                      widget.emptyMeansAll,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                OpenHandDialogActionButton.primary(
                  label: openHandLocalizedText(
                    context,
                    zh: '完成',
                    zhHant: '完成',
                    en: 'Done',
                    fr: 'Terminé',
                    de: 'Fertig',
                    ja: '完了',
                  ),
                  onPressed: () => Navigator.of(context).pop(_selected),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _toggle(String key) {
    final next = _effectiveSelectedModelKeys();
    if (next.contains(key)) {
      next.remove(key);
    } else {
      next.add(key);
    }
    _setEffectiveSelectedModels(next);
  }

  void _selectGroup(Set<String> keys) {
    _selectModelKeys(keys);
  }

  void _deselectGroup(Set<String> keys) {
    _deselectModelKeys(keys);
  }

  Set<String> _allModelKeys() =>
      widget.options.map((option) => option.key).toSet();

  Set<String> _effectiveSelectedModelKeys() {
    if (_selected.contains(webGatewayDenyAllSelectionMarker)) {
      return <String>{};
    }
    final allKeys = _allModelKeys();
    if (widget.emptyMeansAll && _selected.isEmpty) return allKeys;
    return _selected.intersection(allKeys);
  }

  void _selectModelKeys(Set<String> keys) {
    final next = _effectiveSelectedModelKeys()..addAll(keys);
    _setEffectiveSelectedModels(next);
  }

  void _deselectModelKeys(Set<String> keys) {
    final next = _effectiveSelectedModelKeys()..removeAll(keys);
    _setEffectiveSelectedModels(next);
  }

  void _setEffectiveSelectedModels(Set<String> keys) {
    final allKeys = _allModelKeys();
    if (keys.isEmpty) {
      setState(() {
        _selected = const <String>{webGatewayDenyAllSelectionMarker};
      });
      return;
    }
    if (widget.emptyMeansAll && keys.length == allKeys.length) {
      setState(() => _selected = <String>{});
      return;
    }
    setState(() => _selected = keys.intersection(allKeys));
  }

  String _modelSelectionCountText(
    BuildContext context,
    int selectedCount,
    int totalCount,
  ) {
    if (_selected.contains(webGatewayDenyAllSelectionMarker)) {
      return openHandLocalizedText(
        context,
        zh: '全部不可用',
        zhHant: '全部不可用',
        en: 'All unavailable',
        fr: 'Tout indisponible',
        de: 'Alle nicht verfügbar',
        ja: 'すべて利用不可',
      );
    }
    if (widget.emptyMeansAll && _selected.isEmpty) {
      return openHandLocalizedText(
        context,
        zh: '全部可用',
        zhHant: '全部可用',
        en: 'All available',
        fr: 'Tout disponible',
        de: 'Alle verfügbar',
        ja: 'すべて利用可能',
      );
    }
    return _gatewaySelectedCount(context, selectedCount, totalCount);
  }
}

class _ProviderGroupHeader {
  const _ProviderGroupHeader({
    required this.providerId,
    required this.providerLabel,
    required this.options,
  });

  final String providerId;
  final String providerLabel;
  final List<WebGatewayModelOption> options;
}

class _AnimatedLogLine extends StatelessWidget {
  const _AnimatedLogLine({
    required this.entry,
    required this.animation,
    this.removing = false,
  });

  final WebGatewayLogEntry entry;
  final Animation<double> animation;
  final bool removing;

  @override
  Widget build(BuildContext context) {
    if (!openHandTickerMotionEnabled(context)) {
      return _LogLine(entry: entry);
    }
    final curved = CurvedAnimation(
      parent: animation,
      curve: removing ? Curves.easeInCubic : Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );
    return SizeTransition(
      sizeFactor: animation,
      axisAlignment: -1,
      child: FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, .18),
            end: Offset.zero,
          ).animate(curved),
          child: _LogLine(entry: entry),
        ),
      ),
    );
  }
}

class _LogLine extends StatelessWidget {
  const _LogLine({required this.entry});
  final WebGatewayLogEntry entry;
  @override
  Widget build(BuildContext context) {
    final color = switch (entry.level) {
      WebGatewayLogLevel.success => const Color(0xFF86EFAC),
      WebGatewayLogLevel.warn => const Color(0xFFFCD34D),
      WebGatewayLogLevel.error => const Color(0xFFFCA5A5),
      WebGatewayLogLevel.debug => const Color(0xFF9CA3AF),
      WebGatewayLogLevel.telemetry => const Color(0xFF7DD3FC),
      WebGatewayLogLevel.info => const Color(0xFFE5E7EB),
    };
    final ts = formatHourMinuteSecondMillis(entry.timestamp.toLocal());
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: SelectableText.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$ts ',
              style: const TextStyle(color: Color(0xFF6B7280)),
            ),
            TextSpan(
              text: entry.tag.padRight(9),
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
            TextSpan(
              text: ' ${entry.message}',
              style: TextStyle(color: color),
            ),
          ],
        ),
        style: const TextStyle(fontFamily: 'Menlo', fontSize: 12, height: 1.45),
      ),
    );
  }
}

class _CleanupHistoryLine extends StatelessWidget {
  const _CleanupHistoryLine({required this.entry});

  final WebGatewayCleanupResult entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .52),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          const Icon(Icons.cleaning_services_outlined, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${_cleanupTargetLabel(context, entry.target)} · ${entry.expiredOnly ? openHandLocalizedText(context, zh: '保留策略', zhHant: '保留策略', en: 'Retention policy', fr: 'Politique de rétention', de: 'Aufbewahrungsregel', ja: '保持ポリシー') : openHandLocalizedText(context, zh: '手动清理', zhHant: '手動清理', en: 'Manual cleanup', fr: 'Nettoyage manuel', de: 'Manuelle Bereinigung', ja: '手動クリーンアップ')} · ${formatYearMonthDayHms(entry.timestamp.toLocal())}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            openHandLocalizedText(
              context,
              zh: '${entry.deletedFiles} 文件 / ${_bytes(entry.bytesFreed)}',
              zhHant: '${entry.deletedFiles} 個檔案 / ${_bytes(entry.bytesFreed)}',
              en: '${entry.deletedFiles} files / ${_bytes(entry.bytesFreed)}',
              fr: '${entry.deletedFiles} fichiers / ${_bytes(entry.bytesFreed)}',
              de: '${entry.deletedFiles} Dateien / ${_bytes(entry.bytesFreed)}',
              ja: '${entry.deletedFiles} ファイル / ${_bytes(entry.bytesFreed)}',
            ),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendLineChart extends StatefulWidget {
  const _TrendLineChart({
    required this.title,
    required this.values,
    required this.valueFormatter,
  });

  final String title;
  final List<double> values;
  final String Function(double value) valueFormatter;

  @override
  State<_TrendLineChart> createState() => _TrendLineChartState();
}

class _TrendLineChartState extends State<_TrendLineChart> {
  List<double> _fromValues = const <double>[];
  List<double> _toValues = const <double>[];
  List<double> _lastPaintValues = const <double>[];
  int _animationVersion = 0;

  @override
  void initState() {
    super.initState();
    _toValues = List<double>.from(widget.values);
    _lastPaintValues = _toValues;
  }

  @override
  void didUpdateWidget(covariant _TrendLineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (scaledNumberSeriesFingerprint(oldWidget.values) ==
        scaledNumberSeriesFingerprint(widget.values)) {
      return;
    }
    _fromValues = _lastPaintValues;
    _toValues = List<double>.from(widget.values);
    _animationVersion++;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final headerValues = _toValues;
    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: .42),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                Text(
                  headerValues.isEmpty
                      ? openHandLocalizedText(
                          context,
                          zh: '暂无数据',
                          zhHant: '暫無資料',
                          en: 'No data',
                          fr: 'Aucune donnée',
                          de: 'Keine Daten',
                          ja: 'データなし',
                        )
                      : widget.valueFormatter(headerValues.last),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 112,
              child: TweenAnimationBuilder<double>(
                key: ValueKey<int>(_animationVersion),
                tween: Tween<double>(begin: 0, end: 1),
                duration: openHandMotionDurationMs(context, 420),
                curve: Curves.easeOutBack,
                builder: (context, progress, child) {
                  final values = _lerpSeries(_fromValues, _toValues, progress);
                  _lastPaintValues = values;
                  final minValue = values.isEmpty
                      ? 0.0
                      : values.reduce(math.min);
                  final maxValue = values.isEmpty
                      ? 1.0
                      : math.max(minValue + 1, values.reduce(math.max));
                  return CustomPaint(
                    painter: _TrendLinePainter(
                      values: values,
                      minValue: minValue,
                      maxValue: maxValue,
                      progress: 1,
                      lineColor: colorScheme.primary,
                      gridColor: colorScheme.outlineVariant.withValues(
                        alpha: .72,
                      ),
                      labelColor: colorScheme.onSurfaceVariant,
                      valueFormatter: widget.valueFormatter,
                    ),
                    child: const SizedBox.expand(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

List<double> _lerpSeries(List<double> from, List<double> to, double progress) {
  if (to.isEmpty) return const <double>[];
  final t = clampUnitInterval(progress);
  final fallback = from.isEmpty ? to.first : from.last;
  return List<double>.generate(to.length, (index) {
    final start = index < from.length ? from[index] : fallback;
    return start + (to[index] - start) * t;
  }, growable: false);
}

class _TrendLinePainter extends CustomPainter {
  const _TrendLinePainter({
    required this.values,
    required this.minValue,
    required this.maxValue,
    required this.progress,
    required this.lineColor,
    required this.gridColor,
    required this.labelColor,
    required this.valueFormatter,
  });

  final List<double> values;
  final double minValue;
  final double maxValue;
  final double progress;
  final Color lineColor;
  final Color gridColor;
  final Color labelColor;
  final String Function(double value) valueFormatter;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 50.0;
    const right = 8.0;
    const top = 8.0;
    const bottom = 24.0;
    final chart = Rect.fromLTWH(
      left,
      top,
      math.max(1, size.width - left - right),
      math.max(1, size.height - top - bottom),
    );
    final axisPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = chart.top + chart.height * i / 3;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), axisPaint);
    }
    canvas.drawLine(
      Offset(chart.left, chart.top),
      Offset(chart.left, chart.bottom),
      axisPaint,
    );
    canvas.drawLine(
      Offset(chart.left, chart.bottom),
      Offset(chart.right, chart.bottom),
      axisPaint,
    );
    _paintLabel(canvas, valueFormatter(maxValue), Offset(0, chart.top - 2));
    _paintLabel(canvas, valueFormatter(minValue), Offset(0, chart.bottom - 14));
    _paintLabel(
      canvas,
      '0',
      Offset(chart.left - 3, chart.bottom + 5),
      alignRight: false,
    );
    _paintLabel(
      canvas,
      '${math.max(0, values.length - 1)}',
      Offset(chart.right - 16, chart.bottom + 5),
      alignRight: false,
    );
    if (values.length < 2) return;
    final span = math.max(1.0, maxValue - minValue);
    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x = chart.left + chart.width * i / (values.length - 1);
      final normalized = finiteUnitInterval((values[i] - minValue) / span);
      final y = chart.bottom - chart.height * normalized;
      points.add(Offset(x, y));
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final point = points[i];
      final mid = Offset(
        (previous.dx + point.dx) / 2,
        (previous.dy + point.dy) / 2,
      );
      path.quadraticBezierTo(previous.dx, previous.dy, mid.dx, mid.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);
    final fillPath = Path.from(path)
      ..lineTo(points.last.dx, chart.bottom)
      ..lineTo(points.first.dx, chart.bottom)
      ..close();
    final visibleRight = chart.left + chart.width * clampUnitInterval(progress);
    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(chart.left, chart.top, visibleRight, chart.bottom),
    );
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            lineColor.withValues(alpha: .20),
            lineColor.withValues(alpha: .02),
          ],
        ).createShader(chart),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  void _paintLabel(
    Canvas canvas,
    String text,
    Offset offset, {
    bool alignRight = true,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: labelColor, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: 48);
    final dx = alignRight ? 46 - painter.width : offset.dx;
    painter.paint(canvas, Offset(dx, offset.dy));
  }

  @override
  bool shouldRepaint(covariant _TrendLinePainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.progress != progress ||
        oldDelegate.minValue != minValue ||
        oldDelegate.maxValue != maxValue ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.labelColor != labelColor;
  }
}

String _messageTypeLabel(BuildContext context, WebGatewayMessageType type) {
  return switch (type) {
    WebGatewayMessageType.text => openHandLocalizedText(
      context,
      zh: '纯文本',
      zhHant: '純文字',
      en: 'Plain text',
      fr: 'Texte brut',
      de: 'Nur Text',
      ja: 'プレーンテキスト',
    ),
    WebGatewayMessageType.attachment => openHandLocalizedText(
      context,
      zh: '带附件',
      zhHant: '含附件',
      en: 'With attachments',
      fr: 'Avec pièces jointes',
      de: 'Mit Anhängen',
      ja: '添付あり',
    ),
  };
}

String _modeLabel(BuildContext context, WebGatewayConversationMode mode) {
  return switch (mode) {
    WebGatewayConversationMode.normal => openHandLocalizedText(
      context,
      zh: '普通',
      zhHant: '普通',
      en: 'Normal',
      fr: 'Normal',
      de: 'Normal',
      ja: '通常',
    ),
    WebGatewayConversationMode.image => openHandLocalizedText(
      context,
      zh: '生成图片',
      zhHant: '生成圖片',
      en: 'Generate image',
      fr: 'Générer une image',
      de: 'Bild erzeugen',
      ja: '画像生成',
    ),
    WebGatewayConversationMode.video => openHandLocalizedText(
      context,
      zh: '生成视频',
      zhHant: '生成影片',
      en: 'Generate video',
      fr: 'Générer une vidéo',
      de: 'Video erzeugen',
      ja: '動画生成',
    ),
    WebGatewayConversationMode.audio => openHandLocalizedText(
      context,
      zh: '生成音频',
      zhHant: '生成音訊',
      en: 'Generate audio',
      fr: 'Générer un audio',
      de: 'Audio erzeugen',
      ja: '音声生成',
    ),
    WebGatewayConversationMode.deepResearch => openHandLocalizedText(
      context,
      zh: '深度研究',
      zhHant: '深度研究',
      en: 'Deep research',
      fr: 'Recherche approfondie',
      de: 'Tiefe Recherche',
      ja: 'ディープリサーチ',
    ),
  };
}

String _modelSummary(
  BuildContext context,
  List<WebGatewayModelOption> options,
  Set<String> selected,
  bool emptyMeansAll,
) {
  if (selected.contains(webGatewayDenyAllSelectionMarker)) {
    return openHandLocalizedText(
      context,
      zh: '全部模型不可用',
      zhHant: '全部模型不可用',
      en: 'All models unavailable',
      fr: 'Tous les modèles indisponibles',
      de: 'Alle Modelle nicht verfügbar',
      ja: 'すべてのモデルが利用不可',
    );
  }
  if (emptyMeansAll && selected.isEmpty) {
    return openHandLocalizedText(
      context,
      zh: '全部模型可用',
      zhHant: '全部模型可用',
      en: 'All models available',
      fr: 'Tous les modèles disponibles',
      de: 'Alle Modelle verfügbar',
      ja: 'すべてのモデルが利用可能',
    );
  }
  if (selected.isEmpty) {
    return openHandLocalizedText(
      context,
      zh: '未选择模型',
      zhHant: '未選擇模型',
      en: 'No models selected',
      fr: 'Aucun modèle sélectionné',
      de: 'Keine Modelle ausgewählt',
      ja: 'モデル未選択',
    );
  }
  final labels = options
      .where((option) => selected.contains(option.key))
      .map((option) => option.label)
      .toList(growable: false);
  final separator = _gatewayListSeparator(context);
  if (labels.length <= 2) return labels.join(separator);
  return openHandLocalizedText(
    context,
    zh: '${labels.take(2).join(separator)} 等 ${labels.length} 个模型',
    zhHant: '${labels.take(2).join(separator)} 等 ${labels.length} 個模型',
    en: '${labels.take(2).join(separator)} and ${labels.length} models',
    fr: '${labels.take(2).join(separator)} et ${labels.length} modèles',
    de: '${labels.take(2).join(separator)} und ${labels.length} Modelle',
    ja: '${labels.take(2).join(separator)} ほか ${labels.length} モデル',
  );
}

String _runtimeStateLabel(BuildContext context, WebGatewayRuntimeState state) {
  return switch (state) {
    WebGatewayRuntimeState.stopped => openHandLocalizedText(
      context,
      zh: '已停止',
      zhHant: '已停止',
      en: 'Stopped',
      fr: 'Arrêté',
      de: 'Gestoppt',
      ja: '停止済み',
    ),
    WebGatewayRuntimeState.starting => openHandLocalizedText(
      context,
      zh: '启动中',
      zhHant: '啟動中',
      en: 'Starting',
      fr: 'Démarrage',
      de: 'Startet',
      ja: '起動中',
    ),
    WebGatewayRuntimeState.running => openHandLocalizedText(
      context,
      zh: '运行中',
      zhHant: '執行中',
      en: 'Running',
      fr: 'En cours',
      de: 'Läuft',
      ja: '実行中',
    ),
    WebGatewayRuntimeState.stopping => openHandLocalizedText(
      context,
      zh: '停止中',
      zhHant: '停止中',
      en: 'Stopping',
      fr: 'Arrêt en cours',
      de: 'Stoppt',
      ja: '停止中',
    ),
    WebGatewayRuntimeState.crashed => openHandLocalizedText(
      context,
      zh: '已崩溃',
      zhHant: '已崩潰',
      en: 'Crashed',
      fr: 'Planté',
      de: 'Abgestürzt',
      ja: 'クラッシュ',
    ),
  };
}

List<double> _series(
  List<WebGatewayRuntimeSnapshot> snapshots,
  double? Function(WebGatewayRuntimeSnapshot snapshot) pick,
) {
  return snapshots
      .map(pick)
      .whereType<double>()
      .map((value) => value.isFinite ? value : 0.0)
      .toList(growable: false);
}

List<double> _deltaSeries(
  List<WebGatewayRuntimeSnapshot> snapshots,
  double Function(WebGatewayRuntimeSnapshot snapshot) pick,
) {
  if (snapshots.length < 2) return const <double>[];
  final values = <double>[];
  for (var index = 1; index < snapshots.length; index++) {
    values.add(
      math.max(0, pick(snapshots[index]) - pick(snapshots[index - 1])),
    );
  }
  return values;
}

int _logPageSize(double dialogHeight) {
  final available = math.max(160.0, dialogHeight - 190);
  return math.max(24, (available / 22).floor());
}

String _formatQueryParameters(Map<String, String> value) {
  return value.entries.map((entry) => '${entry.key}=${entry.value}').join('&');
}

Map<String, String> _parseQueryParameters(String raw) {
  final result = <String, String>{};
  final normalized = raw.replaceAll('\n', '&');
  for (final part in normalized.split('&')) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    final index = trimmed.indexOf('=');
    if (index <= 0) {
      result[trimmed] = '';
      continue;
    }
    final key = trimmed.substring(0, index).trim();
    final value = trimmed.substring(index + 1).trim();
    if (key.isNotEmpty) result[key] = value;
  }
  return result;
}

int _boundedInt(
  String value, {
  required int fallback,
  required int min,
  required int max,
}) {
  return clampedIntFromText(value, fallback: fallback, min: min, max: max);
}

int _boundedMegabytesAsBytes(
  String value, {
  required int fallbackBytes,
  required int minBytes,
  required int maxBytes,
}) {
  const bytesPerMegabyte = 1024 * 1024;
  final minMegabytes = math.max(1, (minBytes / bytesPerMegabyte).ceil());
  final maxMegabytes = math.max(
    minMegabytes,
    (maxBytes / bytesPerMegabyte).floor(),
  );
  final fallbackMegabytes = (fallbackBytes / bytesPerMegabyte)
      .round()
      .clamp(minMegabytes, maxMegabytes)
      .toInt();
  return _boundedInt(
        value,
        fallback: fallbackMegabytes,
        min: minMegabytes,
        max: maxMegabytes,
      ) *
      bytesPerMegabyte;
}

String _rate(double value) {
  if (value >= 100) return value.toStringAsFixed(0);
  if (value >= 10) return value.toStringAsFixed(1);
  return value.toStringAsFixed(2);
}

String _percent(double value) =>
    '${(value * 100).clamp(0, 999).toStringAsFixed(0)}%';

String _cleanupTargetLabel(BuildContext context, String target) {
  return switch (target) {
    'logs' => openHandLocalizedText(
      context,
      zh: '日志',
      zhHant: '日誌',
      en: 'Logs',
      fr: 'Journaux',
      de: 'Protokolle',
      ja: 'ログ',
    ),
    'uploads' => openHandLocalizedText(
      context,
      zh: '上传缓存',
      zhHant: '上傳快取',
      en: 'Upload cache',
      fr: 'Cache d’envoi',
      de: 'Upload-Cache',
      ja: 'アップロードキャッシュ',
    ),
    'all' => openHandLocalizedText(
      context,
      zh: '全部资源',
      zhHant: '全部資源',
      en: 'All resources',
      fr: 'Toutes les ressources',
      de: 'Alle Ressourcen',
      ja: 'すべてのリソース',
    ),
    _ => target,
  };
}

String _bytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  return '${(mb / 1024).toStringAsFixed(1)} GB';
}
