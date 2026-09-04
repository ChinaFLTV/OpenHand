import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart'
    show PointerScrollEvent, PointerSignalEvent, TapGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:openhand/shared/util/text_normalization.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../../app/model/dialog_animation_settings.dart';
import '../../../app/state/settings_controller.dart';
import '../../../app/support/openhand_paths.dart';
import '../../../app/support/openhand_scroll_physics.dart';
import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../../../app/theme/openhand_status_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/model/dingtalk_multimodal_capability.dart';
import '../../../shared/ui/animated_appearance.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/animated_menu.dart';
import '../../../shared/ui/appear_once.dart';
import '../../../shared/ui/auto_follow_scroll_guard.dart';
import '../../../shared/ui/data_cleanup_range_dialog.dart';
import '../../../shared/ui/feature_page_shell.dart';
import '../../../shared/ui/feature_state_card.dart';
import '../../../shared/ui/frame_coalesced_rebuild.dart';
import '../../../shared/ui/generated_media_result_card.dart';
import '../../../shared/ui/image_editor_dialog.dart';
import '../../../shared/ui/markdown_inline_code.dart';
import '../../../shared/ui/media_preview_dialog.dart';
import '../../../shared/ui/micro_press_feedback.dart';
import '../../../shared/ui/model_search_selector.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/oh_pill.dart';
import '../../../shared/ui/openhand_busy_indicators.dart';
import '../../../shared/ui/openhand_clipboard.dart';
import '../../../shared/ui/openhand_console_log_panel.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_inline_empty_state.dart';
import '../../../shared/ui/openhand_inline_notice.dart';
import '../../../shared/ui/openhand_live_value.dart';
import '../../../shared/ui/openhand_ops_charts.dart';
import '../../../shared/ui/openhand_ops_press_scale.dart';
import '../../../shared/ui/openhand_safe_markdown_body.dart';
import '../../../shared/ui/openhand_safe_scrollbar.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/openhand_sweep_shimmer.dart';
import '../../../shared/ui/openhand_tap_region.dart';
import '../../../shared/ui/openhand_trailing_toolbar.dart';
import '../../../shared/ui/openhand_typography.dart';
import '../../../shared/ui/reasoning_effort_selector.dart';
import '../../../shared/ui/runtime_log_dialog.dart';
import '../../../shared/ui/streaming_text_reveal.dart';
import '../../../shared/util/async_concurrency.dart';
import '../../../shared/util/bounded_directory_io.dart';
import '../../../shared/util/bounded_file_io.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/localized_text.dart';
import '../../../shared/util/rolling_hash.dart';
import '../../../shared/util/serial_task_queue.dart';
import '../../../shared/util/stable_hash.dart';
import '../../../shared/util/text_clip.dart';
import '../../../shared/util/text_fingerprint.dart';
import '../../../shared/util/timer_safety.dart';
import '../../ai/index.dart';
import '../../knowledge_base/index.dart';
import '../../mcp/index.dart';
import '../../workflows/index.dart';
import '../dingtalk_markdown_compat.dart';
import '../dingtalk_message_gateway_controller.dart';
import '../message_gateway_controller.dart';
import '../message_gateway_errors.dart';
import '../model/dingtalk_message_gateway.dart';
import '../model/web_message_platform_config.dart';
import '../service/web_message_platform_service.dart';

const int _dingtalkTranslationCacheMaxEntries = 64;
const int _dingtalkClipboardImageMaxBytes = 64 * kBytesPerMiB;
const Duration _dingtalkMediaClipboardTimeout = Duration(seconds: 15);
const double _dingtalkResourceIntroMaxHeight = 180;
int _dingtalkTemporaryFileSerial = 0;

enum _DingTalkMediaClipboardContent { image, files }

String _dingtalkTextContent(String content) =>
    stripImageSummaryMarkup(content).trim();

bool _hasDingTalkTextContent(String content, List<DingTalkGatewayMedia> media) {
  return normalizeDingTalkMediaText(content, media).isNotEmpty;
}

String _nextDingTalkTemporaryFileName(String prefix, String extension) {
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final serial = _dingtalkTemporaryFileSerial++;
  return '$prefix-$stamp-$pid-$serial.$extension';
}

Future<bool> _pathExistsBounded(FileSystemEntity entity) async {
  try {
    return await entity.exists().timeout(defaultBoundedFileReadIdleTimeout);
  } on FileSystemException {
    return false;
  } on TimeoutException {
    return false;
  }
}

Future<_DingTalkMediaClipboardContent> _copyDingTalkMediaToClipboard(
  List<DingTalkGatewayMedia> media, {
  VoidCallback? onUnavailable,
}) async {
  final paths = <String>[];
  int? singleFileSize;
  for (final item in media) {
    final path = item.localPath.trim();
    if (path.isEmpty) continue;
    final size = await probeFileSizeBounded(File(path));
    if (size == null || size <= 0) continue;
    paths.add(path);
    if (media.length == 1) singleFileSize = size;
  }
  if (paths.isEmpty) {
    onUnavailable?.call();
    throw const FileSystemException('媒体文件尚未准备完成。');
  }
  if (paths.length == 1 &&
      media.length == 1 &&
      media.single.kind == DingTalkMediaKind.image &&
      singleFileSize != null &&
      singleFileSize <= _dingtalkClipboardImageMaxBytes) {
    await writeOpenHandClipboardImage(
      await readBoundedFileBytes(
        File(paths.single),
        maxBytes: _dingtalkClipboardImageMaxBytes,
        idleTimeout: _dingtalkMediaClipboardTimeout,
        totalTimeout: _dingtalkMediaClipboardTimeout,
      ),
    );
    return _DingTalkMediaClipboardContent.image;
  }
  if (!await writeOpenHandClipboardFiles(paths)) {
    throw const FileSystemException('系统不支持复制媒体文件。');
  }
  return _DingTalkMediaClipboardContent.files;
}

String _reportMessageGatewayUiFailure(
  String action,
  Object error,
  StackTrace stack, {
  required String fallback,
}) {
  silentLog('message_gateway', action, error, stack);
  return messageGatewayFailureMessage(error, fallback: fallback);
}

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

int _webGatewayOpsFineMetricColumnCount(double maxWidth) => maxWidth < 440
    ? 1
    : maxWidth < 760
    ? 2
    : 4;

bool _webGatewayOpsShouldStackDistribution(double maxWidth) => maxWidth < 300;

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

String _dingtalkAllowlistText(
  BuildContext context,
  String key, {
  DingTalkConversationType? type,
  int? count,
}) {
  final isGroup = type == DingTalkConversationType.group;
  switch (key) {
    case 'group_title':
      return openHandLocalizedText(
        context,
        zh: '允许响应的群聊',
        zhHant: '允許回應的群聊',
        en: 'Allowed groups',
        fr: 'Groupes autorisés',
        de: 'Zulässige Gruppen',
        ja: '応答を許可するグループ',
      );
    case 'contact_title':
      return openHandLocalizedText(
        context,
        zh: '允许响应的联系人',
        zhHant: '允許回應的聯絡人',
        en: 'Allowed contacts',
        fr: 'Contacts autorisés',
        de: 'Zulässige Kontakte',
        ja: '応答を許可する連絡先',
      );
    case 'group_subtitle':
      return openHandLocalizedText(
        context,
        zh: '仅名单内群聊且消息 @ 当前钉钉账号时才会触发 AI 响应。',
        zhHant: '僅名單內群聊且訊息 @ 目前釘釘帳號時才會觸發 AI 回應。',
        en: 'Respond only to @ mentions from groups on this list.',
        fr: 'Répondre uniquement aux mentions @ des groupes autorisés.',
        de: 'Nur auf @-Erwähnungen aus diesen Gruppen antworten.',
        ja: 'このリストのグループからの @ メンションだけに応答します。',
      );
    case 'contact_subtitle':
      return openHandLocalizedText(
        context,
        zh: '仅名单内联系人的单聊消息会触发 AI 响应。',
        zhHant: '僅名單內聯絡人的單聊訊息會觸發 AI 回應。',
        en: 'Respond only to direct messages from contacts on this list.',
        fr: 'Répondre uniquement aux messages directs des contacts autorisés.',
        de: 'Nur auf Direktnachrichten dieser Kontakte antworten.',
        ja: 'このリストの連絡先からのダイレクトメッセージだけに応答します。',
      );
    case 'group_empty':
      return openHandLocalizedText(
        context,
        zh: '尚未配置自动响应群聊；已打开会话仍会实时同步。',
        zhHant: '尚未設定自動回應群聊；已開啟會話仍會即時同步。',
        en: 'No auto-response groups; open conversations still sync live.',
        fr: 'Aucun groupe avec réponse automatique ; les conversations ouvertes restent synchronisées.',
        de: 'Keine Gruppen mit automatischer Antwort; geöffnete Chats werden weiter live synchronisiert.',
        ja: '自動応答グループは未設定ですが、開いた会話はリアルタイム同期されます。',
      );
    case 'contact_empty':
      return openHandLocalizedText(
        context,
        zh: '尚未配置自动响应联系人；已打开会话仍会实时同步。',
        zhHant: '尚未設定自動回應聯絡人；已開啟會話仍會即時同步。',
        en: 'No auto-response contacts; open conversations still sync live.',
        fr: 'Aucun contact avec réponse automatique ; les conversations ouvertes restent synchronisées.',
        de: 'Keine Kontakte mit automatischer Antwort; geöffnete Chats werden weiter live synchronisiert.',
        ja: '自動応答の連絡先は未設定ですが、開いた会話はリアルタイム同期されます。',
      );
    case 'add':
      return openHandLocalizedText(
        context,
        zh: isGroup ? '添加群聊' : '添加联系人',
        zhHant: isGroup ? '新增群聊' : '新增聯絡人',
        en: isGroup ? 'Add group' : 'Add contact',
        fr: isGroup ? 'Ajouter un groupe' : 'Ajouter un contact',
        de: isGroup ? 'Gruppe hinzufügen' : 'Kontakt hinzufügen',
        ja: isGroup ? 'グループを追加' : '連絡先を追加',
      );
    case 'picker_title':
      return openHandLocalizedText(
        context,
        zh: isGroup ? '选择允许响应的群聊' : '选择允许响应的联系人',
        zhHant: isGroup ? '選擇允許回應的群聊' : '選擇允許回應的聯絡人',
        en: isGroup ? 'Choose allowed groups' : 'Choose allowed contacts',
        fr: isGroup
            ? 'Choisir les groupes autorisés'
            : 'Choisir les contacts autorisés',
        de: isGroup
            ? 'Zulässige Gruppen auswählen'
            : 'Zulässige Kontakte auswählen',
        ja: isGroup ? '許可するグループを選択' : '許可する連絡先を選択',
      );
    case 'selected':
      return openHandLocalizedText(
        context,
        zh: '已选 ${count ?? 0}',
        zhHant: '已選 ${count ?? 0}',
        en: 'Selected ${count ?? 0}',
        fr: 'Sélectionnés : ${count ?? 0}',
        de: 'Ausgewählt: ${count ?? 0}',
        ja: '選択済み ${count ?? 0}',
      );
    case 'search_label':
      return openHandLocalizedText(
        context,
        zh: isGroup ? '搜索群聊名称' : '搜索联系人姓名',
        zhHant: isGroup ? '搜尋群聊名稱' : '搜尋聯絡人姓名',
        en: isGroup ? 'Search group name' : 'Search contact name',
        fr: isGroup ? 'Rechercher un groupe' : 'Rechercher un contact',
        de: isGroup ? 'Gruppennamen suchen' : 'Kontaktnamen suchen',
        ja: isGroup ? 'グループ名を検索' : '連絡先名を検索',
      );
    case 'search_hint':
      return openHandLocalizedText(
        context,
        zh: '输入关键词快速匹配',
        zhHant: '輸入關鍵詞快速匹配',
        en: 'Type a keyword to search',
        fr: 'Saisissez un mot-clé',
        de: 'Suchbegriff eingeben',
        ja: 'キーワードを入力して検索',
      );
    case 'search_start':
      return openHandLocalizedText(
        context,
        zh: '输入关键词开始搜索',
        zhHant: '輸入關鍵詞開始搜尋',
        en: 'Type a keyword to search',
        fr: 'Saisissez un mot-clé pour rechercher',
        de: 'Suchbegriff eingeben',
        ja: 'キーワードを入力して検索',
      );
    case 'no_results':
      return openHandLocalizedText(
        context,
        zh: '暂无匹配结果',
        zhHant: '暫無匹配結果',
        en: 'No matches',
        fr: 'Aucun résultat',
        de: 'Keine Treffer',
        ja: '一致する結果はありません',
      );
    case 'apply':
      return openHandLocalizedText(
        context,
        zh: '应用选择',
        zhHant: '套用選擇',
        en: 'Apply selection',
        fr: 'Appliquer',
        de: 'Auswahl anwenden',
        ja: '選択を適用',
      );
    case 'cancel':
      return openHandLocalizedText(
        context,
        zh: '取消',
        zhHant: '取消',
        en: 'Cancel',
        fr: 'Annuler',
        de: 'Abbrechen',
        ja: 'キャンセル',
      );
  }
  return key;
}

/// 网关详情弹窗走 expandToMax（固定尺寸），不套用统一档位——档位是上限语义。
const double _kGatewayDetailDialogWidth = 860;
const double _kGatewayDetailDialogHeight = 760;
const double _kMetricTileSpacing = 10;

/// 消息网关平台卡片：与服务板块同族，但保留网关专属层次与仪表盘质感。
const double _kGatewayCardRadius = 22;
const double _kGatewayIdentityExtent = 64;
const double _kGatewayIdentityIconSize = 31;
const double _kGatewayHeaderBreakpoint = 820;
const double _kGatewayFactIconSize = 14;
const double _kGatewayFactRadius = 10;
const EdgeInsets _kGatewayFactPadding = EdgeInsets.symmetric(
  horizontal: 10,
  vertical: 6,
);
const EdgeInsets _kGatewayCardPadding = EdgeInsets.all(18);
const EdgeInsets _kGatewayMetricsPadding = EdgeInsets.symmetric(
  horizontal: 14,
  vertical: 14,
);

Widget _buildMetricTileGrid({
  required double width,
  required int columns,
  required List<Widget> children,
}) {
  final tileWidth = (width - _kMetricTileSpacing * (columns - 1)) / columns;
  return Wrap(
    spacing: _kMetricTileSpacing,
    runSpacing: _kMetricTileSpacing,
    children: [
      for (final child in children) SizedBox(width: tileWidth, child: child),
    ],
  );
}

class MessageGatewayView extends StatefulWidget {
  const MessageGatewayView({super.key});

  @override
  State<MessageGatewayView> createState() => _MessageGatewayViewState();
}

class _MessageGatewayViewState extends State<MessageGatewayView>
    with WidgetsBindingObserver {
  static const Duration _addressRefreshInterval = Duration(seconds: 30);
  static const Duration _addressRefreshTimeout = Duration(seconds: 5);

  MessageGatewayController? _controller;
  Timer? _addressRefreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<MessageGatewayController>();
    controller.updateTheme(Theme.of(context));
    if (!identical(_controller, controller)) {
      _controller = controller;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_refreshAccessibleUrls(force: true));
      });
      _startAddressRefreshTimer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshAccessibleUrls(force: true));
      _startAddressRefreshTimer();
      return;
    }
    _addressRefreshTimer?.cancel();
    _addressRefreshTimer = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _addressRefreshTimer?.cancel();
    super.dispose();
  }

  void _startAddressRefreshTimer() {
    _addressRefreshTimer?.cancel();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    _addressRefreshTimer = startNonOverlappingPeriodicTimer(
      _addressRefreshInterval,
      (_) => _refreshAccessibleUrls(),
      callbackTimeout: _addressRefreshTimeout,
      onError: (error, stack) =>
          silentLog('message_gateway', '刷新可访问地址', error, stack),
    );
  }

  Future<void> _refreshAccessibleUrls({bool force = false}) async {
    final controller = _controller;
    if (!mounted || controller == null || !controller.isRunning) return;
    await controller.refreshAccessibleUrls(force: force);
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
      notices: [
        if (controller.errorMessage != null && controller.hasTrustedSnapshot)
          OpenHandInlineNoticeFactory.error(
            context,
            controller.errorMessage!,
            copyText: controller.errorMessage,
            onDismiss: controller.clearError,
          ),
      ],
      headerSpacing: 16,
    );
  }

  Widget _buildBody(BuildContext context, MessageGatewayController controller) {
    if (controller.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.errorMessage != null && !controller.hasTrustedSnapshot) {
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
      key: const ValueKey<String>('message-gateway-list'),
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 16),
      children: [
        SettingsAwareAppearOnce(
          child: RepaintBoundary(
            child: _WebPlatformServiceCard(controller: controller),
          ),
        ),
        kOpenHandGap14,
        SettingsAwareAppearOnce(
          child: RepaintBoundary(
            child: _DingTalkGatewayCard(controller: controller),
          ),
        ),
      ],
    );
  }
}

class _WebPlatformServiceCard extends StatelessWidget {
  const _WebPlatformServiceCard({required this.controller});

  final MessageGatewayController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final config = controller.config;
    final runtime = controller.runtimeSnapshot();
    final isRunning = controller.isRunning;
    final boundPort = Uri.tryParse(runtime.boundUrl)?.port;
    final usingFallbackPort =
        isRunning && boundPort != null && boundPort != config.listenPort;
    final stateColor = switch (controller.runtimeState) {
      WebGatewayRuntimeState.running => OpenHandStatusColors.success,
      WebGatewayRuntimeState.crashed => cs.error,
      WebGatewayRuntimeState.starting ||
      WebGatewayRuntimeState.stopping => OpenHandStatusColors.warning,
      WebGatewayRuntimeState.stopped => cs.outline,
    };
    final statusPills = <Widget>[
      OpenHandStatusPill(
        icon: config.enabled
            ? Icons.check_circle_outline_rounded
            : Icons.pause_circle_outline_rounded,
        label: config.enabled
            ? openHandEnabledLabel(context)
            : openHandDisabledLabel(context),
        color: config.enabled ? OpenHandStatusColors.success : cs.outline,
      ),
      OpenHandStatusPill(
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
        color: config.authEnabled ? cs.primary : cs.outline,
      ),
      OpenHandStatusPill(
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
        color: config.telemetryEnabled ? cs.secondary : cs.outline,
      ),
      OpenHandStatusPill(
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
        color: config.loggingEnabled ? cs.tertiary : cs.outline,
      ),
      OpenHandStatusPill(
        icon: Icons.link_rounded,
        label: isRunning
            ? controller.webUrl
            : '${config.listenHost}:${config.listenPort}',
        color: isRunning ? cs.primary : cs.outline,
      ),
      if (controller.hasPendingRuntimeConfig)
        OpenHandStatusPill(
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
          color: OpenHandStatusColors.warning,
        ),
      if (usingFallbackPort)
        OpenHandStatusPill(
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
          color: OpenHandStatusColors.warning,
        ),
    ];
    final factChips = <Widget>[
      _GatewayFactChip(
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
        color: config.autoStartOnLaunch ? cs.secondary : cs.onSurfaceVariant,
      ),
      _GatewayFactChip(
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
        color: config.autoReloadOnChange ? cs.tertiary : cs.onSurfaceVariant,
      ),
      _GatewayFactChip(
        icon: Icons.bolt_rounded,
        label: openHandLocalizedText(
          context,
          zh: '并发 ${config.maxConcurrentRequests}',
          zhHant: '並發 ${config.maxConcurrentRequests}',
          en: 'Concurrency ${config.maxConcurrentRequests}',
          fr: 'Concurrence ${config.maxConcurrentRequests}',
          de: 'Parallelität ${config.maxConcurrentRequests}',
          ja: '同時実行 ${config.maxConcurrentRequests}',
        ),
        color: cs.primary,
      ),
      _GatewayFactChip(
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
        color: cs.tertiary,
      ),
      _GatewayFactChip(
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
        color: cs.secondary,
      ),
      _GatewayFactChip(
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
        color: config.sessionManagementEnabled
            ? cs.secondary
            : cs.onSurfaceVariant,
      ),
      _GatewayFactChip(
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
        color: config.knowledgeBaseEnabled ? cs.primary : cs.onSurfaceVariant,
      ),
      _GatewayFactChip(
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
        color: config.workspaceFileWriteEnabled
            ? cs.tertiary
            : cs.onSurfaceVariant,
      ),
    ];
    return Card(
      key: const ValueKey<String>('web-message-platform-card'),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_kGatewayCardRadius),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: _kGatewayCardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final compact =
                    constraints.maxWidth < _kGatewayHeaderBreakpoint;
                final actions = Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    IconButton.filled(
                      tooltip: isRunning
                          ? openHandStopLabel(context)
                          : openHandStartLabel(context),
                      onPressed: controller.isOperating
                          ? null
                          : () => _runServiceAction(
                              context,
                              controller,
                              stop: isRunning,
                            ),
                      style:
                          (isRunning
                                  ? OpenHandStatusColors.runningStopButtonStyle()
                                  : IconButton.styleFrom())
                              .copyWith(
                                shape:
                                    const WidgetStatePropertyAll<
                                      OutlinedBorder
                                    >(CircleBorder()),
                              ),
                      icon: controller.isOperating
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              isRunning
                                  ? Icons.stop_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                    ),
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
                          ? _messageGatewayPortConnectivityTestLabel(context)
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
                    _FeatureIconButton(
                      tooltip: openHandLocalizedText(
                        context,
                        zh: '编辑配置',
                        zhHant: '編輯設定',
                        en: 'Edit configuration',
                        fr: 'Modifier la configuration',
                        de: 'Konfiguration bearbeiten',
                        ja: '設定を編集',
                      ),
                      enabled: true,
                      icon: Icons.edit_rounded,
                      onPressed: () => _showEditor(context, controller),
                    ),
                  ],
                );
                final identity = _GatewayPlatformIdentity(
                  icon: Icons.language_rounded,
                  title: webMessagePlatformBuiltinName,
                  description: config.description,
                  statusColor: stateColor,
                );
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      identity,
                      kOpenHandGap16,
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: actions,
                      ),
                    ],
                  );
                }
                // 操作区固有宽度贴右；介绍 Expanded 扩展到首个按钮左侧，中间留 16 空隙。
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: identity),
                    kOpenHandHGap16,
                    actions,
                  ],
                );
              },
            ),
            kOpenHandGap16,
            Wrap(spacing: 10, runSpacing: 10, children: statusPills),
            kOpenHandGap12,
            Wrap(spacing: 8, runSpacing: 8, children: factChips),
            // 监听通配符地址时列出全部可访问 URL；仅多地址时展示，避免与状态层重复。
            if (isRunning && controller.webUrls.length > 1) ...[
              kOpenHandGap14,
              _AccessibleUrlsBar(urls: controller.webUrls),
            ],
            kOpenHandGap16,
            _GatewayRuntimeMetricsStrip(
              items: [
                (
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
                  accent: stateColor,
                ),
                (
                  label: openHandRequestsLabel(context),
                  value: '${runtime.totalRequests}',
                  accent: cs.primary,
                ),
                (
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
                  accent: runtime.totalErrors > 0
                      ? cs.error
                      : cs.onSurfaceVariant,
                ),
                (
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
                  accent: cs.tertiary,
                ),
              ],
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
    final failureFallback = openHandLocalizedText(
      context,
      zh: '健康检查失败，请稍后重试。',
      zhHant: '健康檢查失敗，請稍後再試。',
      en: 'Health check failed. Try again later.',
      fr: 'Le contrôle de santé a échoué. Réessayez plus tard.',
      de: 'Integritätsprüfung fehlgeschlagen. Versuchen Sie es später erneut.',
      ja: 'ヘルスチェックに失敗しました。後でもう一度お試しください。',
    );
    try {
      final result = await controller.runHealthCheck();
      if (!context.mounted) return;
      OpenHandSnackBar.flash(
        context,
        '${result.summary} (${result.durationMs}ms)',
        kind: result.ok ? OpenHandSnackKind.success : OpenHandSnackKind.error,
      );
    } catch (error, stack) {
      final message = _reportMessageGatewayUiFailure(
        '执行消息网关健康检查',
        error,
        stack,
        fallback: failureFallback,
      );
      if (context.mounted) showOpenHandErrorSnack(context, message);
    }
  }

  Future<void> _runServiceAction(
    BuildContext context,
    MessageGatewayController controller, {
    required bool stop,
  }) async {
    final failureFallback = openHandLocalizedText(
      context,
      zh: stop ? '消息网关停止失败，请稍后重试。' : '消息网关启动失败，请检查监听地址与端口。',
      zhHant: stop ? '訊息閘道停止失敗，請稍後再試。' : '訊息閘道啟動失敗，請檢查監聽位址與連接埠。',
      en: stop
          ? 'Message gateway failed to stop. Try again later.'
          : 'Message gateway failed to start. Check the listen address and port.',
      fr: stop
          ? 'L’arrêt de la passerelle a échoué. Réessayez plus tard.'
          : 'Le démarrage de la passerelle a échoué. Vérifiez l’adresse et le port d’écoute.',
      de: stop
          ? 'Das Gateway konnte nicht gestoppt werden. Versuchen Sie es später erneut.'
          : 'Das Gateway konnte nicht gestartet werden. Prüfen Sie Adresse und Port.',
      ja: stop
          ? 'メッセージゲートウェイを停止できませんでした。後でもう一度お試しください。'
          : 'メッセージゲートウェイを起動できませんでした。待受アドレスとポートを確認してください。',
    );
    try {
      if (stop) {
        await controller.stopService();
      } else {
        await controller.startService();
      }
    } catch (error, stack) {
      final message = _reportMessageGatewayUiFailure(
        stop ? '停止消息网关' : '启动消息网关',
        error,
        stack,
        fallback: failureFallback,
      );
      if (context.mounted) {
        showOpenHandErrorSnack(context, message, maxLines: 2);
      }
    }
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
      text: '${(config.logConfig.fileMaxBytes / kBytesPerMiB).round()}',
    );
    _logRotationDaysController = TextEditingController(
      text: '${config.logConfig.rotationDays}',
    );
    _logMaxFilesController = TextEditingController(
      text: '${config.logConfig.maxFiles}',
    );
    _workspaceFileMaxMbController = TextEditingController(
      text:
          '${math.max(1, (config.workspaceFileMaxBytes / kBytesPerMiB).ceil())}',
    );
    _workspaceFileExtensionsController = TextEditingController(
      text: config.workspaceFileAllowedExtensions.join(', '),
    );
    _uploadCacheRetentionDaysController = TextEditingController(
      text: '${config.uploadCacheRetentionDays}',
    );
    _uploadCacheMaxMbController = TextEditingController(
      text: '${(config.uploadCacheMaxBytes / kBytesPerMiB).round()}',
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
      maxWidth: kOpenHandDialogWidthExtraWide,
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
                    borderRadius: kOpenHandBorderRadius18,
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
                kOpenHandHGap14,
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
                      kOpenHandGap4,
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
                kOpenHandHGap10,
                IconButton.filledTonal(
                  tooltip: openHandCloseLabel(context),
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
                        switchInCurve: kOpenHandSwitchInCurve,
                        switchOutCurve: kOpenHandSwitchOutCurve,
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
                        kOpenHandGap18,
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
                      kOpenHandGap18,
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
                      kOpenHandGap18,
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
                      kOpenHandGap18,
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
                      kOpenHandGap12,
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
                      kOpenHandGap18,
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
                  switchInCurve: kOpenHandSwitchInCurve,
                  switchOutCurve: kOpenHandSwitchOutCurve,
                  child: _saveError == null
                      ? const SizedBox.shrink(key: ValueKey('save-ok'))
                      : Padding(
                          key: const ValueKey('save-error'),
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _EditorNotice(
                            icon: Icons.error_outline_rounded,
                            title: openHandSaveFailedLabel(context),
                            body: _saveError!,
                            error: true,
                          ),
                        ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OpenHandDialogActionButton.secondary(
                      label: openHandCancelLabel(context),
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                    ),
                    kOpenHandHGap12,
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
      curve: kOpenHandEntranceCurve,
      reverseCurve: kOpenHandSwitchOutCurve,
    );
    return SizeTransition(
      sizeFactor: animation,
      alignment: AlignmentDirectional.topStart,
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
    // 开鉴权必须有密码：空口令会让登录的相等比较对任何空密码请求成立，
    // 而网关默认监听 0.0.0.0。服务端也会拒绝这种配置，这里先行拦下并说明原因。
    if (_authEnabled && _passwordController.text.isEmpty) {
      setState(() {
        _saving = false;
        _saveError = openHandLocalizedText(
          context,
          zh: '已开启访问鉴权，必须设置登录密码。',
          zhHant: '已開啟存取驗證，必須設定登入密碼。',
          en: 'Access authentication is on; a login password is required.',
          fr: "L'authentification est activée ; un mot de passe est requis.",
          de: 'Authentifizierung ist aktiv; ein Passwort ist erforderlich.',
          ja: '認証が有効です。ログインパスワードを設定してください。',
        );
      });
      return;
    }
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
      allowedMessageTypes: _messageTypes,
      allowedConversationModes: _modes,
      allowedModelKeys: _models.toList(growable: false),
      planModeEnabled: _planModeEnabled,
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
    } catch (error, stack) {
      silentLog('message_gateway', '保存消息网关配置', error, stack);
      if (!mounted) return;
      final message = messageGatewayFailureMessage(
        error,
        fallback: openHandLocalizedText(
          context,
          zh: '消息网关配置保存失败，请稍后重试。',
          zhHant: '訊息閘道設定儲存失敗，請稍後再試。',
          en: 'Failed to save the message gateway configuration. Try again later.',
          fr: 'Échec de l’enregistrement de la configuration. Réessayez plus tard.',
          de: 'Gateway-Konfiguration konnte nicht gespeichert werden. Versuchen Sie es später erneut.',
          ja: 'メッセージゲートウェイ設定を保存できませんでした。後でもう一度お試しください。',
        ),
      );
      showOpenHandErrorSnack(context, message);
      setState(() {
        _saveError = message;
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
        borderRadius: kOpenHandBorderRadius12,
        border: Border.all(color: color.withValues(alpha: .28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          kOpenHandHGap10,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.labelLarge),
                kOpenHandGap3,
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
  String? _error;
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
    } catch (error, stack) {
      silentLog('message_gateway', '执行端口连通性测试', error, stack);
      if (!mounted) return;
      setState(
        () => _error = messageGatewayFailureMessage(
          error,
          fallback: openHandLocalizedText(
            context,
            zh: '端口连通性测试失败，请稍后重试。',
            zhHant: '連接埠連通性測試失敗，請稍後再試。',
            en: 'Port connectivity test failed. Try again later.',
            fr: 'Le test de connectivité des ports a échoué. Réessayez plus tard.',
            de: 'Portverbindungstest fehlgeschlagen. Versuchen Sie es später erneut.',
            ja: 'ポート接続テストに失敗しました。後でもう一度お試しください。',
          ),
        ),
      );
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
      maxWidth: kOpenHandDialogWidthExtraWide,
      maxHeight: kOpenHandDialogHeightTall,
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
                      ? OpenHandStatusColors.success
                      : colorScheme.error,
                ),
                kOpenHandHGap10,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _messageGatewayPortConnectivityTestLabel(context),
                        style: theme.textTheme.titleMedium,
                      ),
                      kOpenHandGap2,
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
                      tooltip: openHandCloseLabel(context),
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
              switchInCurve: kOpenHandEntranceCurve,
              switchOutCurve: kOpenHandSwitchOutCurve,
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
    await copyOpenHandTextToClipboard(
      logTag: 'message_gateway',
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
      logAction: '复制连通性测试结果',
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
          kOpenHandGap16,
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
          kOpenHandGap6,
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

  final String error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          error,
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
              color:
                  (result.ok ? OpenHandStatusColors.success : colorScheme.error)
                      .withValues(alpha: .10),
              borderRadius: kOpenHandBorderRadius14,
              border: Border.all(
                color:
                    (result.ok
                            ? OpenHandStatusColors.success
                            : colorScheme.error)
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
                      ? OpenHandStatusColors.success
                      : colorScheme.error,
                ),
                kOpenHandHGap12,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(result.summary, style: theme.textTheme.titleMedium),
                      kOpenHandGap4,
                      Text(
                        openHandLocalizedText(
                          context,
                          zh: '${formatYearMonthDayHmsLocal(result.startedAt)} · 总耗时 ${result.durationMs}ms',
                          zhHant:
                              '${formatYearMonthDayHmsLocal(result.startedAt)} · 總耗時 ${result.durationMs}ms',
                          en: '${formatYearMonthDayHmsLocal(result.startedAt)} · Total ${result.durationMs}ms',
                          fr: '${formatYearMonthDayHmsLocal(result.startedAt)} · Total ${result.durationMs}ms',
                          de: '${formatYearMonthDayHmsLocal(result.startedAt)} · Gesamt ${result.durationMs}ms',
                          ja: '${formatYearMonthDayHmsLocal(result.startedAt)} · 合計 ${result.durationMs}ms',
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
          kOpenHandGap14,
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 720 ? 2 : 4;
              return _buildMetricTileGrid(
                width: constraints.maxWidth,
                columns: columns,
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
                    label: openHandTotalTimeLabel(context),
                    value: '${result.durationMs}ms',
                  ),
                ],
              );
            },
          ),
          kOpenHandGap18,
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
          kOpenHandGap18,
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
              color: _webGatewayDarkSurface,
              borderRadius: kOpenHandBorderRadius12,
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
                fontFamily: kOpenHandMonospaceFontFamily,
                fontSize: 12,
                height: 1.45,
                color: _webGatewayLightGray,
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
    final stateColor = target.ok
        ? OpenHandStatusColors.success
        : colorScheme.error;
    final content = Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: .42),
        borderRadius: kOpenHandBorderRadius12,
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
              kOpenHandHGap8,
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
          kOpenHandGap8,
          SelectableText(
            target.endpointUrl,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          kOpenHandGap8,
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
            kOpenHandGap8,
            Text(
              target.errorMessage,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.error,
              ),
            ),
          ],
          if (target.bodyPreview.isNotEmpty) ...[
            kOpenHandGap8,
            _StructuredResponsePreview(raw: target.bodyPreview),
          ],
        ],
      ),
    );
    if (!openHandTickerMotionEnabled(context)) return content;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 220 + math.min(index, 6) * 30),
      curve: kOpenHandEntranceCurve,
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
    final decoded = tryDecodeJson(raw);
    final entries = decoded is Map
        ? decoded.entries.toList(growable: false)
        : const <MapEntry<Object?, Object?>>[];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(kOpenHandRadius10),
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
              kOpenHandHGap6,
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
          kOpenHandGap10,
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
                fontFamily: kOpenHandMonospaceFontFamily,
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
        borderRadius: BorderRadius.circular(kOpenHandRadius10),
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
          kOpenHandGap4,
          SelectableText(
            value,
            maxLines: 4,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface,
              fontFamily: kOpenHandMonospaceFontFamily,
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

class _WebGatewayLogDialogState extends State<_WebGatewayLogDialog>
    with FrameCoalescedRebuild<_WebGatewayLogDialog> {
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

  void _onControllerChanged() => scheduleCoalescedRebuild();

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
      maxWidth: kOpenHandDialogWidthExtraWide,
      maxHeight: kOpenHandDialogHeightStandard,
      minHeight: 480,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 8, 10),
            child: Row(
              children: [
                const Icon(Icons.terminal_rounded),
                kOpenHandHGap10,
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
                    // 日志级别多选菜单复用全局弹出动效。
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
                      tooltip: openHandCloseLabel(context),
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
              color: _webGatewayDarkSurface,
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
    showOpenHandSuccessSnack(
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
      duration: kOpenHandMotion1600,
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
    _scrollGuard.scheduleFollowToBottom(
      _scrollController,
      animated: true,
      animationDuration: openHandMotionDurationMs(context, 220),
    );
  }

  Future<void> _copyLogs(List<WebGatewayLogEntry> logs) async {
    await copyOpenHandTextToClipboard(
      logTag: 'message_gateway',
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
      logAction: '复制网关日志',
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
      await writeFileAtomically(File(location.path), text);
      if (!mounted) return;
      showOpenHandSuccessSnack(
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
      );
    } catch (error, stack) {
      silentLog('message_gateway', '导出当前消息网关日志', error, stack);
      if (!mounted) return;
      showOpenHandErrorSnack(
        context,
        messageGatewayFailureMessage(
          error,
          fallback: openHandLocalizedText(
            context,
            zh: '当前日志导出失败，请稍后重试。',
            zhHant: '目前日誌匯出失敗，請稍後再試。',
            en: 'Current log export failed. Try again later.',
            fr: 'L’export des journaux a échoué. Réessayez plus tard.',
            de: 'Protokollexport fehlgeschlagen. Versuchen Sie es später erneut.',
            ja: '現在のログをエクスポートできませんでした。後でもう一度お試しください。',
          ),
        ),
        maxLines: 2,
      );
    } finally {
      if (mounted) setState(() => _isExportingLog = false);
    }
  }
}

enum _WebOpsInsightKind {
  overview,
  connections,
  requests,
  outcomes,
  traffic,
  latency,
  mutations,
  requestTrend,
  latencyTrend,
  statusMix,
  peerMix,
  clientMix,
  requestMix,
  protocolMix,
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
    final persisted = widget.controller.persistedRuntimeSnapshots;
    _trend.addAll(persisted.skip(math.max(0, persisted.length - _trendLimit)));
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
          silentLog('message_gateway', '刷新运行时快照', error, stack),
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

  Future<void> _showOpsInsight(_WebOpsInsightKind kind) async {
    if (!mounted) return;
    final snapshot = _trend.isEmpty
        ? widget.controller.runtimeSnapshot()
        : _trend.last;
    await showAnimatedDialog<void>(
      context: context,
      builder: (_) => _WebOpsInsightDialog(kind: kind, snapshot: snapshot),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _trend.isEmpty
        ? widget.controller.runtimeSnapshot()
        : _trend.last;
    final config = widget.controller.config;
    final stats = _WebOpsDashboardStats.from(snapshot);
    final failuresPerMinute = snapshot.trafficSeries.isEmpty
        ? 0.0
        : snapshot.trafficSeries.last.failed.toDouble();
    final persistedSnapshotCount =
        widget.controller.persistedRuntimeSnapshots.length;
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
    final restartLabel = openHandRestartLabel(context);
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
    final logsLabel = _messageGatewayLogsLabel(context);
    final uploadCacheLabel = _messageGatewayUploadCacheLabel(context);
    final opsCacheLabel = openHandLocalizedText(
      context,
      zh: '运维缓存',
      zhHant: '維運快取',
      en: 'Ops cache',
      fr: 'Cache opérations',
      de: 'Ops-Cache',
      ja: '運用キャッシュ',
    );
    return buildOpenHandResponsiveDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthFull,
      minAvailableHeight: 520,
      child: _WebOpsDialogSurface(
        child: _WebOpsConsoleShell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _WebOpsConsoleHeader(
                snapshot: snapshot,
                config: config,
                persistedSnapshotCount: persistedSnapshotCount,
                isRunning: isRunning,
                serviceControlsDisabled: serviceControlsDisabled,
                cleaning: _isCleaning,
                healthChecking: _isHealthChecking,
                startLabel: startLabel,
                stopLabel: stopLabel,
                restartLabel: restartLabel,
                reloadLabel: reloadLabel,
                hotFixLabel: hotFixLabel,
                healthLabel: healthLabel,
                onStart: () => _runServiceAction(
                  label: startLabel,
                  action: widget.controller.startService,
                ),
                onStop: () => _runServiceAction(
                  label: stopLabel,
                  action: widget.controller.stopService,
                ),
                onRestart: () => _runServiceAction(
                  label: restartLabel,
                  action: widget.controller.restartService,
                ),
                onReload: () => _runServiceAction(
                  label: reloadLabel,
                  action: widget.controller.reloadConfig,
                ),
                onHotFix: () => _runServiceAction(
                  label: hotFixLabel,
                  action: widget.controller.hotFix,
                ),
                onHealthCheck: _runOpsHealthCheck,
                onCleanExpired: () => _confirmAndCleanupExpiredResources(
                  expiredResourcesLabel: expiredResourcesLabel,
                  opsCacheLabel: opsCacheLabel,
                ),
                onClearLogs: () => _confirmAndCleanup(
                  title: _messageGatewayClearLogsLabel(context),
                  message: openHandLocalizedText(
                    context,
                    zh: '会清空内存日志和 Web 服务磁盘日志，保留策略不会保留当前内容。',
                    zhHant: '會清空記憶體日誌和 Web 服務磁碟日誌，保留策略不會保留目前內容。',
                    en: 'This clears in-memory logs and web service log files. Retention policy will not keep the current content.',
                    fr: 'Cela efface les journaux en mémoire et sur disque. La rétention ne conservera pas le contenu actuel.',
                    de: 'Dies leert Speicher- und Dateiprotokolle. Die Aufbewahrungsregel behält den aktuellen Inhalt nicht.',
                    ja: 'メモリ内ログとWebサービスのディスクログをクリアします。保持ポリシーは現在の内容を保持しません。',
                  ),
                  label: logsLabel,
                  action: widget.controller.cleanupLogs,
                ),
                onClearCache: () => _confirmAndCleanupGatewayCache(
                  uploadCacheLabel: uploadCacheLabel,
                  opsCacheLabel: opsCacheLabel,
                ),
                onClose: () => Navigator.of(context).pop(),
              ),
              kOpenHandGap14,
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
                        _WebOpsHeroPanel(snapshot: snapshot, config: config),
                        kOpenHandGap16,
                        _WebOpsMetricGrid(
                          children: [
                            _WebOpsMetricTile(
                              icon: Icons.link_rounded,
                              label: openHandLocalizedText(
                                context,
                                zh: '当前连接数',
                                zhHant: '目前連線數',
                                en: 'Connections',
                                fr: 'Connexions',
                                de: 'Verbindungen',
                                ja: '現在の接続数',
                              ),
                              value: '${snapshot.currentConnections}',
                              detail: openHandLocalizedText(
                                context,
                                zh: '活动请求 + SSE 长连接',
                                zhHant: '活動請求 + SSE 長連線',
                                en: 'Active requests + SSE streams',
                                fr: 'Requêtes actives + flux SSE',
                                de: 'Aktive Anfragen + SSE-Streams',
                                ja: 'アクティブ要求 + SSE 接続',
                              ),
                              tone: Theme.of(context).colorScheme.primary,
                              onTap: () => _showOpsInsight(
                                _WebOpsInsightKind.connections,
                              ),
                            ),
                            _WebOpsMetricTile(
                              icon: Icons.bolt_rounded,
                              label: openHandLocalizedText(
                                context,
                                zh: '活跃请求',
                                zhHant: '活動請求',
                                en: 'Active requests',
                                fr: 'Requêtes actives',
                                de: 'Aktive Anfragen',
                                ja: 'アクティブ要求',
                              ),
                              value: '${snapshot.activeRequests}',
                              detail:
                                  '${snapshot.activeRequests}/${snapshot.maxConcurrentRequests}',
                              progress: snapshot.activeRequestRatio,
                              tone: snapshot.activeRequestRatio >= .75
                                  ? OpenHandStatusColors.warning
                                  : Theme.of(context).colorScheme.secondary,
                              onTap: () => _showOpsInsight(
                                _WebOpsInsightKind.connections,
                              ),
                            ),
                            _WebOpsMetricTile(
                              icon: Icons.call_made_rounded,
                              label: openHandLocalizedText(
                                context,
                                zh: '请求总数',
                                zhHant: '請求總數',
                                en: 'Requests',
                                fr: 'Requêtes',
                                de: 'Anfragen',
                                ja: 'リクエスト',
                              ),
                              value: '${snapshot.totalRequests}',
                              detail: openHandLocalizedText(
                                context,
                                zh: '近 12 分钟 ${stats.windowRequestCount}',
                                zhHant: '近 12 分鐘 ${stats.windowRequestCount}',
                                en: 'Last 12 min ${stats.windowRequestCount}',
                                fr: '12 dernières min ${stats.windowRequestCount}',
                                de: 'Letzte 12 Min. ${stats.windowRequestCount}',
                                ja: '直近12分 ${stats.windowRequestCount}',
                              ),
                              tone: Theme.of(context).colorScheme.primary,
                              onTap: () =>
                                  _showOpsInsight(_WebOpsInsightKind.requests),
                            ),
                            _WebOpsMetricTile(
                              icon: Icons.task_alt_rounded,
                              label: openHandLocalizedText(
                                context,
                                zh: '成功数量',
                                zhHant: '成功數量',
                                en: 'Succeeded',
                                fr: 'Réussies',
                                de: 'Erfolgreich',
                                ja: '成功数',
                              ),
                              value: '${snapshot.successTotal}',
                              detail: stats.rateLabel(
                                snapshot.successTotal,
                                snapshot.totalRequests,
                              ),
                              tone: OpenHandStatusColors.success,
                              onTap: () =>
                                  _showOpsInsight(_WebOpsInsightKind.outcomes),
                            ),
                            _WebOpsMetricTile(
                              icon: Icons.shield_rounded,
                              label: openHandLocalizedText(
                                context,
                                zh: '拦截数量',
                                zhHant: '攔截數量',
                                en: 'Blocked',
                                fr: 'Bloquées',
                                de: 'Blockiert',
                                ja: 'ブロック数',
                              ),
                              value: '${snapshot.effectiveBlockedTotal}',
                              detail: stats.rateLabel(
                                snapshot.effectiveBlockedTotal,
                                snapshot.totalRequests,
                              ),
                              tone: OpenHandStatusColors.warning,
                              onTap: () =>
                                  _showOpsInsight(_WebOpsInsightKind.outcomes),
                            ),
                            _WebOpsMetricTile(
                              icon: Icons.error_outline_rounded,
                              label: openHandLocalizedText(
                                context,
                                zh: '失败数量',
                                zhHant: '失敗數量',
                                en: 'Failures',
                                fr: 'Échecs',
                                de: 'Fehler',
                                ja: '失敗数',
                              ),
                              value: '${snapshot.failedRequests}',
                              detail: stats.rateLabel(
                                snapshot.failedRequests,
                                snapshot.totalRequests,
                              ),
                              tone: Theme.of(context).colorScheme.error,
                              onTap: () =>
                                  _showOpsInsight(_WebOpsInsightKind.outcomes),
                            ),
                            _WebOpsMetricTile(
                              icon: Icons.south_west_rounded,
                              label: openHandLocalizedText(
                                context,
                                zh: '入口流量',
                                zhHant: '入口流量',
                                en: 'Inbound',
                                fr: 'Entrant',
                                de: 'Eingehend',
                                ja: '受信量',
                              ),
                              value: formatByteSize(snapshot.totalBytesIn),
                              detail: openHandLocalizedText(
                                context,
                                zh: '累计请求体',
                                zhHant: '累計請求本文',
                                en: 'Cumulative request bytes',
                                fr: 'Octets de requête cumulés',
                                de: 'Kumulierte Anfragebytes',
                                ja: '累積リクエスト量',
                              ),
                              tone: Theme.of(context).colorScheme.primary,
                              onTap: () =>
                                  _showOpsInsight(_WebOpsInsightKind.traffic),
                            ),
                            _WebOpsMetricTile(
                              icon: Icons.north_east_rounded,
                              label: openHandLocalizedText(
                                context,
                                zh: '出口流量',
                                zhHant: '出口流量',
                                en: 'Outbound',
                                fr: 'Sortant',
                                de: 'Ausgehend',
                                ja: '送信量',
                              ),
                              value: formatByteSize(snapshot.totalBytesOut),
                              detail: openHandLocalizedText(
                                context,
                                zh: '累计响应体',
                                zhHant: '累計回應本文',
                                en: 'Cumulative response bytes',
                                fr: 'Octets de réponse cumulés',
                                de: 'Kumulierte Antwortbytes',
                                ja: '累積レスポンス量',
                              ),
                              tone: Theme.of(context).colorScheme.tertiary,
                              onTap: () =>
                                  _showOpsInsight(_WebOpsInsightKind.traffic),
                            ),
                            _WebOpsMetricTile(
                              icon: Icons.change_circle_rounded,
                              label: openHandLocalizedText(
                                context,
                                zh: '文件变动',
                                zhHant: '檔案變動',
                                en: 'Mutations',
                                fr: 'Mutations',
                                de: 'Dateiänderungen',
                                ja: 'ファイル変更',
                              ),
                              value: '${snapshot.fileMutationCount}',
                              detail: openHandLocalizedText(
                                context,
                                zh: '写入 / 建目录 / 删除',
                                zhHant: '寫入 / 建目錄 / 刪除',
                                en: 'Write / mkdir / delete',
                                fr: 'Écriture / dossier / suppression',
                                de: 'Schreiben / Ordner / Löschen',
                                ja: '書込 / 作成 / 削除',
                              ),
                              tone: Theme.of(context).colorScheme.secondary,
                              onTap: () =>
                                  _showOpsInsight(_WebOpsInsightKind.mutations),
                            ),
                            _WebOpsMetricTile(
                              icon: Icons.route_rounded,
                              label: openHandLocalizedText(
                                context,
                                zh: '请求速率',
                                zhHant: '請求速率',
                                en: 'Request rate',
                                fr: 'Débit requêtes',
                                de: 'Anfragerate',
                                ja: 'リクエスト率',
                              ),
                              value: _rate(snapshot.requestsPerMinute),
                              detail: openHandLocalizedText(
                                context,
                                zh: '每分钟请求',
                                zhHant: '每分鐘請求',
                                en: 'requests/min',
                                fr: 'requêtes/min',
                                de: 'Anfragen/min',
                                ja: 'リクエスト/min',
                              ),
                              tone: Theme.of(context).colorScheme.primary,
                              onTap: () =>
                                  _showOpsInsight(_WebOpsInsightKind.requests),
                            ),
                            _WebOpsMetricTile(
                              icon: Icons.report_gmailerrorred_rounded,
                              label: openHandLocalizedText(
                                context,
                                zh: '失败速率',
                                zhHant: '失敗速率',
                                en: 'Failure rate',
                                fr: 'Débit d’échecs',
                                de: 'Ausfallrate',
                                ja: '失敗率',
                              ),
                              value: _rate(failuresPerMinute),
                              detail: openHandLocalizedText(
                                context,
                                zh: '每分钟失败',
                                zhHant: '每分鐘失敗',
                                en: 'failures/min',
                                fr: 'échecs/min',
                                de: 'Ausfälle/min',
                                ja: '失敗/min',
                              ),
                              tone: failuresPerMinute > 0
                                  ? Theme.of(context).colorScheme.error
                                  : OpenHandStatusColors.success,
                              onTap: () =>
                                  _showOpsInsight(_WebOpsInsightKind.outcomes),
                            ),
                            _WebOpsMetricTile(
                              icon: Icons.timer_rounded,
                              label: _messageGatewayP95LatencyLabel(context),
                              value: '${snapshot.latencyStats.p95Ms}ms',
                              detail: openHandLocalizedText(
                                context,
                                zh: 'P50 ${snapshot.latencyStats.p50Ms}ms · P99 ${snapshot.latencyStats.p99Ms}ms',
                                zhHant:
                                    'P50 ${snapshot.latencyStats.p50Ms}ms · P99 ${snapshot.latencyStats.p99Ms}ms',
                                en: 'P50 ${snapshot.latencyStats.p50Ms}ms · P99 ${snapshot.latencyStats.p99Ms}ms',
                                fr: 'P50 ${snapshot.latencyStats.p50Ms}ms · P99 ${snapshot.latencyStats.p99Ms}ms',
                                de: 'P50 ${snapshot.latencyStats.p50Ms}ms · P99 ${snapshot.latencyStats.p99Ms}ms',
                                ja: 'P50 ${snapshot.latencyStats.p50Ms}ms · P99 ${snapshot.latencyStats.p99Ms}ms',
                              ),
                              tone: Theme.of(context).colorScheme.tertiary,
                              onTap: () =>
                                  _showOpsInsight(_WebOpsInsightKind.latency),
                            ),
                            _WebOpsMetricTile(
                              icon: Icons.hub_rounded,
                              label: openHandLocalizedText(
                                context,
                                zh: '并发水位',
                                zhHant: '並發水位',
                                en: 'Concurrency',
                                fr: 'Concurrence',
                                de: 'Parallelität',
                                ja: '同時実行',
                              ),
                              value: _percent(snapshot.activeRequestRatio),
                              detail:
                                  '${snapshot.activeRequests}/${snapshot.maxConcurrentRequests} · SSE ${snapshot.activeSseSubscriptions}',
                              progress: snapshot.activeRequestRatio,
                              tone: snapshot.activeRequestRatio >= .75
                                  ? OpenHandStatusColors.warning
                                  : Theme.of(context).colorScheme.secondary,
                              onTap: () => _showOpsInsight(
                                _WebOpsInsightKind.connections,
                              ),
                            ),
                            _WebOpsMetricTile(
                              icon: Icons.memory_rounded,
                              label: openHandLocalizedText(
                                context,
                                zh: '进程内存',
                                zhHant: '程序記憶體',
                                en: 'Process memory',
                                fr: 'Mémoire processus',
                                de: 'Prozessspeicher',
                                ja: 'プロセスメモリ',
                              ),
                              value: formatByteSize(snapshot.currentRssBytes),
                              detail: openHandLocalizedText(
                                context,
                                zh: '峰值 ${formatByteSize(snapshot.maxRssBytes)}',
                                zhHant:
                                    '峰值 ${formatByteSize(snapshot.maxRssBytes)}',
                                en: 'peak ${formatByteSize(snapshot.maxRssBytes)}',
                                fr: 'pic ${formatByteSize(snapshot.maxRssBytes)}',
                                de: 'Peak ${formatByteSize(snapshot.maxRssBytes)}',
                                ja: 'ピーク ${formatByteSize(snapshot.maxRssBytes)}',
                              ),
                              tone: Theme.of(context).colorScheme.primary,
                              onTap: () =>
                                  _showOpsInsight(_WebOpsInsightKind.overview),
                            ),
                            _WebOpsMetricTile(
                              icon: Icons.speed_rounded,
                              label: 'CPU',
                              value: snapshot.cpuPercent == null
                                  ? _gatewayUnavailable(context)
                                  : '${snapshot.cpuPercent!.toStringAsFixed(1)}%',
                              detail: openHandLocalizedText(
                                context,
                                zh: '线程 ${snapshot.threadCount?.toString() ?? _gatewayUnavailable(context)} · 句柄 ${snapshot.fileHandleCount?.toString() ?? _gatewayUnavailable(context)}',
                                zhHant:
                                    '執行緒 ${snapshot.threadCount?.toString() ?? _gatewayUnavailable(context)} · 句柄 ${snapshot.fileHandleCount?.toString() ?? _gatewayUnavailable(context)}',
                                en: 'threads ${snapshot.threadCount?.toString() ?? _gatewayUnavailable(context)} · handles ${snapshot.fileHandleCount?.toString() ?? _gatewayUnavailable(context)}',
                                fr: 'threads ${snapshot.threadCount?.toString() ?? _gatewayUnavailable(context)} · handles ${snapshot.fileHandleCount?.toString() ?? _gatewayUnavailable(context)}',
                                de: 'Threads ${snapshot.threadCount?.toString() ?? _gatewayUnavailable(context)} · Handles ${snapshot.fileHandleCount?.toString() ?? _gatewayUnavailable(context)}',
                                ja: 'スレッド ${snapshot.threadCount?.toString() ?? _gatewayUnavailable(context)} · ハンドル ${snapshot.fileHandleCount?.toString() ?? _gatewayUnavailable(context)}',
                              ),
                              tone: Theme.of(context).colorScheme.secondary,
                              onTap: () =>
                                  _showOpsInsight(_WebOpsInsightKind.overview),
                            ),
                            _WebOpsMetricTile(
                              icon: Icons.swap_vert_rounded,
                              label: openHandLocalizedText(
                                context,
                                zh: '数据流量',
                                zhHant: '資料流量',
                                en: 'Data flow',
                                fr: 'Flux de données',
                                de: 'Datenfluss',
                                ja: 'データフロー',
                              ),
                              value: formatByteSize(
                                (snapshot.bytesInPerMinute +
                                        snapshot.bytesOutPerMinute)
                                    .round(),
                              ),
                              detail: openHandLocalizedText(
                                context,
                                zh: '入 ${formatByteSize(snapshot.bytesInPerMinute.round())} / 出 ${formatByteSize(snapshot.bytesOutPerMinute.round())}',
                                zhHant:
                                    '入 ${formatByteSize(snapshot.bytesInPerMinute.round())} / 出 ${formatByteSize(snapshot.bytesOutPerMinute.round())}',
                                en: 'in ${formatByteSize(snapshot.bytesInPerMinute.round())} / out ${formatByteSize(snapshot.bytesOutPerMinute.round())}',
                                fr: 'in ${formatByteSize(snapshot.bytesInPerMinute.round())} / out ${formatByteSize(snapshot.bytesOutPerMinute.round())}',
                                de: 'in ${formatByteSize(snapshot.bytesInPerMinute.round())} / out ${formatByteSize(snapshot.bytesOutPerMinute.round())}',
                                ja: '受信 ${formatByteSize(snapshot.bytesInPerMinute.round())} / 送信 ${formatByteSize(snapshot.bytesOutPerMinute.round())}',
                              ),
                              tone: Theme.of(context).colorScheme.tertiary,
                              onTap: () =>
                                  _showOpsInsight(_WebOpsInsightKind.traffic),
                            ),
                            _WebOpsMetricTile(
                              icon: Icons.history_rounded,
                              label: openHandLocalizedText(
                                context,
                                zh: '本地回溯',
                                zhHant: '本地回溯',
                                en: 'Local history',
                                fr: 'Historique local',
                                de: 'Lokale Historie',
                                ja: 'ローカル履歴',
                              ),
                              value: '$persistedSnapshotCount',
                              detail: openHandLocalizedText(
                                context,
                                zh: '${snapshot.memoryLogCount} 条内存日志 · ${cleanupHistory.length} 条清理记录',
                                zhHant:
                                    '${snapshot.memoryLogCount} 則記憶體日誌 · ${cleanupHistory.length} 則清理記錄',
                                en: '${snapshot.memoryLogCount} memory logs · ${cleanupHistory.length} cleanup records',
                                fr: '${snapshot.memoryLogCount} journaux mémoire · ${cleanupHistory.length} nettoyages',
                                de: '${snapshot.memoryLogCount} Speicherlogs · ${cleanupHistory.length} Bereinigungen',
                                ja: '${snapshot.memoryLogCount} 件メモリログ · ${cleanupHistory.length} 件クリーンアップ',
                              ),
                              tone: Theme.of(context).colorScheme.primary,
                              onTap: () =>
                                  _showOpsInsight(_WebOpsInsightKind.overview),
                            ),
                          ],
                        ),
                        kOpenHandGap16,
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final panels = <Widget>[
                              _WebOpsTrendPanel(
                                title: _messageGatewayRequestTrendLabel(
                                  context,
                                ),
                                icon: Icons.show_chart_rounded,
                                subtitle: openHandLocalizedText(
                                  context,
                                  zh: '最近 12 分钟 · 成功 / 拦截 / 失败',
                                  zhHant: '最近 12 分鐘 · 成功 / 攔截 / 失敗',
                                  en: 'Last 12 minutes · success / blocked / failed',
                                  fr: '12 dernières minutes · succès / bloqué / échec',
                                  de: 'Letzte 12 Minuten · Erfolg / blockiert / Fehler',
                                  ja: '直近12分 · 成功 / ブロック / 失敗',
                                ),
                                series: stats.requestTrendSeries(context),
                                emptyLabel:
                                    _messageGatewayWaitingForTrafficLabel(
                                      context,
                                    ),
                                onTap: () => _showOpsInsight(
                                  _WebOpsInsightKind.requestTrend,
                                ),
                              ),
                              _WebOpsTrendPanel(
                                title: _messageGatewayLatencyCurveLabel(
                                  context,
                                ),
                                icon: Icons.timeline_rounded,
                                subtitle: openHandLocalizedText(
                                  context,
                                  zh: '平均耗时与 P95 尾延迟',
                                  zhHant: '平均耗時與 P95 尾延遲',
                                  en: 'Average and P95 tail latency',
                                  fr: 'Latence moyenne et de queue P95',
                                  de: 'Mittelwert und P95-Tail-Latenz',
                                  ja: '平均および P95 テールレイテンシ',
                                ),
                                series: stats.latencyTrendSeries(context),
                                emptyLabel:
                                    _messageGatewayNoLatencySamplesLabel(
                                      context,
                                    ),
                                valueSuffix: 'ms',
                                onTap: () => _showOpsInsight(
                                  _WebOpsInsightKind.latencyTrend,
                                ),
                              ),
                            ];
                            if (constraints.maxWidth < 780) {
                              return Column(
                                children: [
                                  panels.first,
                                  const SizedBox(height: _webOpsGridGap),
                                  panels.last,
                                ],
                              );
                            }
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: panels.first),
                                const SizedBox(width: _webOpsGridGap),
                                Expanded(child: panels.last),
                              ],
                            );
                          },
                        ),
                        kOpenHandGap16,
                        _NaturalCardGrid(
                          minTileWidth: 300,
                          spacing: _webOpsGridGap,
                          maxColumns: 3,
                          children: [
                            _WebOpsDistributionPanel(
                              title: _messageGatewayStatusMixLabel(context),
                              icon: Icons.donut_small_rounded,
                              values: stats.statusDistribution(
                                context,
                                snapshot,
                              ),
                              onTap: () =>
                                  _showOpsInsight(_WebOpsInsightKind.statusMix),
                            ),
                            _WebOpsDistributionPanel(
                              title: openHandLocalizedText(
                                context,
                                zh: '来源端点（IP:端口）',
                                zhHant: '來源端點（IP:連接埠）',
                                en: 'Source endpoints',
                                fr: 'Points de terminaison source',
                                de: 'Quellendpunkte',
                                ja: '送信元エンドポイント',
                              ),
                              icon: Icons.public_rounded,
                              values: snapshot.effectivePeerDistribution,
                              onTap: () =>
                                  _showOpsInsight(_WebOpsInsightKind.peerMix),
                            ),
                            _WebOpsDistributionPanel(
                              title: _messageGatewayClientUaMixLabel(context),
                              icon: Icons.devices_other_rounded,
                              values: snapshot.clientDistribution,
                              onTap: () =>
                                  _showOpsInsight(_WebOpsInsightKind.clientMix),
                            ),
                            _WebOpsDistributionPanel(
                              title: _messageGatewayRequestMixLabel(context),
                              icon: Icons.account_tree_rounded,
                              values: snapshot.requestDistribution,
                              onTap: () => _showOpsInsight(
                                _WebOpsInsightKind.requestMix,
                              ),
                            ),
                            _WebOpsDistributionPanel(
                              title: _messageGatewayProtocolMixLabel(context),
                              icon: Icons.api_rounded,
                              values: snapshot.protocolDistribution,
                              onTap: () => _showOpsInsight(
                                _WebOpsInsightKind.protocolMix,
                              ),
                            ),
                          ],
                        ),
                        kOpenHandGap16,
                        _WebOpsPanelGrid(
                          children: [
                            _WebOpsEnvironmentPanel(
                              snapshot: snapshot,
                              config: config,
                            ),
                            _WebOpsFeatureMatrixPanel(
                              snapshot: snapshot,
                              config: config,
                            ),
                          ],
                        ),
                        kOpenHandGap16,
                        _SectionTitle(
                          openHandLocalizedText(
                            context,
                            zh: '细粒度指标快照',
                            zhHant: '細粒度指標快照',
                            en: 'Fine-grained metric snapshot',
                            fr: 'Instantané détaillé des métriques',
                            de: 'Feingranularer Metrik-Snapshot',
                            ja: '詳細メトリクススナップショット',
                          ),
                          icon: Icons.dashboard_customize_rounded,
                        ),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final columns = _webGatewayOpsFineMetricColumnCount(
                              constraints.maxWidth,
                            );
                            const spacing = 10.0;
                            final tileWidth =
                                (constraints.maxWidth -
                                    spacing * (columns - 1)) /
                                columns;
                            return Wrap(
                              spacing: spacing,
                              runSpacing: spacing,
                              children: [
                                SizedBox(
                                  width: tileWidth,
                                  child: _MetricTile(
                                    label: _messageGatewayThreadsLabel(context),
                                    value:
                                        snapshot.threadCount?.toString() ??
                                        _gatewayUnavailable(context),
                                  ),
                                ),
                                SizedBox(
                                  width: tileWidth,
                                  child: _MetricTile(
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
                                ),
                                SizedBox(
                                  width: tileWidth,
                                  child: _MetricTile(
                                    label: 'Swap',
                                    value: snapshot.swapBytes == null
                                        ? _gatewayUnavailable(context)
                                        : formatByteSize(snapshot.swapBytes!),
                                  ),
                                ),
                                SizedBox(
                                  width: tileWidth,
                                  child: _MetricTile(
                                    label: openHandLocalizedText(
                                      context,
                                      zh: '最大内存',
                                      zhHant: '最大記憶體',
                                      en: 'Peak memory',
                                      fr: 'Mémoire max',
                                      de: 'Max. Speicher',
                                      ja: '最大メモリ',
                                    ),
                                    value: formatByteSize(snapshot.maxRssBytes),
                                  ),
                                ),
                                SizedBox(
                                  width: tileWidth,
                                  child: _MetricTile(
                                    label: _messageGatewayLogDiskLabel(context),
                                    value: formatByteSize(snapshot.logBytes),
                                  ),
                                ),
                                SizedBox(
                                  width: tileWidth,
                                  child: _MetricTile(
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
                                ),
                                SizedBox(
                                  width: tileWidth,
                                  child: _MetricTile(
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
                                ),
                                SizedBox(
                                  width: tileWidth,
                                  child: _MetricTile(
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
                                ),
                                SizedBox(
                                  width: tileWidth,
                                  child: _MetricTile(
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
                                ),
                                SizedBox(
                                  width: tileWidth,
                                  child: _MetricTile(
                                    label: openHandLocalizedText(
                                      context,
                                      zh: '延迟样本',
                                      zhHant: '延遲樣本',
                                      en: 'Latency samples',
                                      fr: 'Échantillons latence',
                                      de: 'Latenzstichproben',
                                      ja: 'レイテンシサンプル',
                                    ),
                                    value:
                                        '${snapshot.latencyStats.sampleCount}',
                                  ),
                                ),
                                SizedBox(
                                  width: tileWidth,
                                  child: _MetricTile(
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
                                ),
                                SizedBox(
                                  width: tileWidth,
                                  child: _MetricTile(
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
                                ),
                                SizedBox(
                                  width: tileWidth,
                                  child: _MetricTile(
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
                                ),
                              ],
                            );
                          },
                        ),
                        kOpenHandGap18,
                        _OpsHealthCard(snapshot: snapshot),
                        kOpenHandGap18,
                        _OpsSummaryCard(snapshot: snapshot),
                        kOpenHandGap18,
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
                        kOpenHandGap18,
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
                                zh: '${snapshot.memoryLogCount} 条内存 · 待写 ${snapshot.fileLogPendingWrites} · 丢弃 ${snapshot.fileLogDroppedWrites}',
                                zhHant:
                                    '${snapshot.memoryLogCount} 則記憶體 · 待寫 ${snapshot.fileLogPendingWrites} · 丟棄 ${snapshot.fileLogDroppedWrites}',
                                en: '${snapshot.memoryLogCount} memory · ${snapshot.fileLogPendingWrites} pending · ${snapshot.fileLogDroppedWrites} dropped',
                                fr: '${snapshot.memoryLogCount} en mémoire · ${snapshot.fileLogPendingWrites} en attente · ${snapshot.fileLogDroppedWrites} ignorés',
                                de: '${snapshot.memoryLogCount} im Speicher · ${snapshot.fileLogPendingWrites} ausstehend · ${snapshot.fileLogDroppedWrites} verworfen',
                                ja: '${snapshot.memoryLogCount} 件メモリ · 待機 ${snapshot.fileLogPendingWrites} · 破棄 ${snapshot.fileLogDroppedWrites}',
                              ),
                            ),
                            _ResourceInventoryCard(snapshot: snapshot),
                          ],
                        ),
                        kOpenHandGap18,
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
                                  valueFormatter: (value) =>
                                      formatByteSize(value.round()),
                                ),
                                _TrendLineChart(
                                  title: _messageGatewayLogDiskLabel(context),
                                  values: _series(
                                    _trend,
                                    (snapshot) => snapshot.logBytes.toDouble(),
                                  ),
                                  valueFormatter: (value) =>
                                      formatByteSize(value.round()),
                                ),
                                _TrendLineChart(
                                  title: _messageGatewayThreadsLabel(context),
                                  values: _series(
                                    _trend,
                                    (snapshot) =>
                                        snapshot.threadCount?.toDouble(),
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
                                  valueFormatter: (value) =>
                                      formatByteSize(value.round()),
                                ),
                              ],
                            );
                          },
                        ),
                        if (cleanupHistory.isNotEmpty) ...[
                          kOpenHandGap18,
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
                          kOpenHandGap18,
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
        ),
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
      cancelLabel: openHandCancelLabel(context),
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
    if (confirmed && mounted) {
      await _runCleanup(label: label, action: action);
    }
  }

  Future<void> _confirmAndCleanupGatewayCache({
    required String uploadCacheLabel,
    required String opsCacheLabel,
  }) async {
    final range = await showOpenHandDataCleanupRangeDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '清空 Web 服务缓存',
        zhHant: '清空 Web 服務快取',
        en: 'Clear web service cache',
        fr: 'Effacer le cache du service web',
        de: 'Webdienst-Cache leeren',
        ja: 'Webサービスキャッシュをクリア',
      ),
      description: openHandLocalizedText(
        context,
        zh: '会清空 Web 消息附件上传缓存，并按所选时间范围清理本地持久化的 Web 运维、监控与日志回溯数据。',
        zhHant: '會清空 Web 訊息附件上傳快取，並依所選時間範圍清理本地持久化的 Web 維運、監控與日誌回溯資料。',
        en: 'Clears cached web message uploads and removes locally persisted web operations metrics, monitoring snapshots and log history in the selected range.',
        fr: 'Efface le cache des envois web et les métriques, instantanés et journaux persistés dans la période choisie.',
        de: 'Leert den Upload-Cache und entfernt lokal gespeicherte Betriebsmetriken, Monitoring-Snapshots und Protokolle im gewählten Zeitraum.',
        ja: 'Webメッセージのアップロードキャッシュを消去し、選択範囲の運用メトリクス、監視スナップショット、ログ履歴を削除します。',
      ),
    );
    if (range == null || !mounted || _isCleaning) return;
    setState(() => _isCleaning = true);
    try {
      final uploadResult = await widget.controller.cleanupUploadCache();
      final opsResult = await widget.controller.cleanupOpsCache(
        startUtc: range.startUtc,
        endUtc: range.endUtc,
      );
      if (!mounted) return;
      final freedBytes = uploadResult.bytesFreed + opsResult.bytes;
      showOpenHandSuccessSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '$uploadCacheLabel / $opsCacheLabel 清理完成，释放 ${formatByteSize(freedBytes)}，清理 ${opsResult.itemCount} 条运维记录',
          zhHant:
              '$uploadCacheLabel / $opsCacheLabel 清理完成，釋放 ${formatByteSize(freedBytes)}，清理 ${opsResult.itemCount} 則維運記錄',
          en: '$uploadCacheLabel / $opsCacheLabel cleanup completed, freed ${formatByteSize(freedBytes)}, removed ${opsResult.itemCount} ops records',
          fr: 'Nettoyage $uploadCacheLabel / $opsCacheLabel terminé, ${formatByteSize(freedBytes)} libérés, ${opsResult.itemCount} enregistrements supprimés',
          de: '$uploadCacheLabel / $opsCacheLabel bereinigt, ${formatByteSize(freedBytes)} freigegeben, ${opsResult.itemCount} Ops-Einträge entfernt',
          ja: '$uploadCacheLabel / $opsCacheLabel のクリーンアップが完了しました。${formatByteSize(freedBytes)} 解放、${opsResult.itemCount} 件削除',
        ),
      );
      final persisted = widget.controller.persistedRuntimeSnapshots;
      setState(() {
        _trend
          ..clear()
          ..addAll(persisted.skip(math.max(0, persisted.length - _trendLimit)));
      });
      await _tick();
    } catch (error, stack) {
      silentLog('message_gateway', '清理消息网关缓存', error, stack);
      if (!mounted) return;
      showOpenHandErrorSnack(
        context,
        messageGatewayFailureMessage(
          error,
          fallback: openHandLocalizedText(
            context,
            zh: '消息网关缓存清理失败，请稍后重试。',
            zhHant: '訊息閘道快取清理失敗，請稍後再試。',
            en: 'Message gateway cache cleanup failed. Try again later.',
            fr: 'Le nettoyage du cache a échoué. Réessayez plus tard.',
            de: 'Gateway-Cache konnte nicht bereinigt werden. Versuchen Sie es später erneut.',
            ja: 'メッセージゲートウェイのキャッシュを消去できませんでした。後でもう一度お試しください。',
          ),
        ),
        maxLines: 2,
      );
    } finally {
      if (mounted) setState(() => _isCleaning = false);
    }
  }

  Future<void> _confirmAndCleanupExpiredResources({
    required String expiredResourcesLabel,
    required String opsCacheLabel,
  }) async {
    final range = await showOpenHandDataCleanupRangeDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '清理 Web 过期资源',
        zhHant: '清理 Web 過期資源',
        en: 'Clean expired web resources',
        fr: 'Nettoyer les ressources web expirées',
        de: 'Abgelaufene Webressourcen bereinigen',
        ja: '期限切れWebリソースを清理',
      ),
      description: openHandLocalizedText(
        context,
        zh: '会按保留策略清理 Web 服务过期日志与上传资源，并按所选时间范围清理本地持久化的 Web 运维、监控与日志回溯数据。',
        zhHant: '會依保留策略清理 Web 服務過期日誌與上傳資源，並依所選時間範圍清理本地持久化的 Web 維運、監控與日誌回溯資料。',
        en: 'Applies the retention policy to expired web logs and uploads, and removes locally persisted web operations metrics, monitoring snapshots and log history in the selected range.',
        fr: 'Applique la rétention aux journaux et envois expirés, puis supprime les métriques, instantanés et journaux persistés dans la période choisie.',
        de: 'Wendet die Aufbewahrungsregel auf abgelaufene Webprotokolle und Uploads an und entfernt lokal gespeicherte Betriebsmetriken, Monitoring-Snapshots und Protokolle im gewählten Zeitraum.',
        ja: '保持ポリシーに従って期限切れのWebログとアップロードを削除し、選択範囲の運用メトリクス、監視スナップショット、ログ履歴を削除します。',
      ),
    );
    if (range == null || !mounted || _isCleaning) return;
    setState(() => _isCleaning = true);
    try {
      final expiredResult = await widget.controller.cleanupExpiredArtifacts();
      final opsResult = await widget.controller.cleanupOpsCache(
        startUtc: range.startUtc,
        endUtc: range.endUtc,
      );
      if (!mounted) return;
      final freedBytes = expiredResult.bytesFreed + opsResult.bytes;
      showOpenHandSuccessSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '$expiredResourcesLabel / $opsCacheLabel 清理完成，释放 ${formatByteSize(freedBytes)}，删除 ${expiredResult.deletedFiles} 个文件，清理 ${opsResult.itemCount} 条运维记录',
          zhHant:
              '$expiredResourcesLabel / $opsCacheLabel 清理完成，釋放 ${formatByteSize(freedBytes)}，刪除 ${expiredResult.deletedFiles} 個檔案，清理 ${opsResult.itemCount} 則維運記錄',
          en: '$expiredResourcesLabel / $opsCacheLabel cleanup completed, freed ${formatByteSize(freedBytes)}, deleted ${expiredResult.deletedFiles} files, removed ${opsResult.itemCount} ops records',
          fr: 'Nettoyage $expiredResourcesLabel / $opsCacheLabel terminé, ${formatByteSize(freedBytes)} libérés, ${expiredResult.deletedFiles} fichiers supprimés, ${opsResult.itemCount} enregistrements supprimés',
          de: '$expiredResourcesLabel / $opsCacheLabel bereinigt, ${formatByteSize(freedBytes)} freigegeben, ${expiredResult.deletedFiles} Dateien gelöscht, ${opsResult.itemCount} Ops-Einträge entfernt',
          ja: '$expiredResourcesLabel / $opsCacheLabel のクリーンアップが完了しました。${formatByteSize(freedBytes)} 解放、${expiredResult.deletedFiles} ファイル削除、${opsResult.itemCount} 件削除',
        ),
        maxLines: 2,
      );
      final persisted = widget.controller.persistedRuntimeSnapshots;
      setState(() {
        _trend
          ..clear()
          ..addAll(persisted.skip(math.max(0, persisted.length - _trendLimit)));
      });
      await _tick();
    } catch (error, stack) {
      silentLog('message_gateway', '清理消息网关过期资源', error, stack);
      if (!mounted) return;
      showOpenHandErrorSnack(
        context,
        messageGatewayFailureMessage(
          error,
          fallback: openHandLocalizedText(
            context,
            zh: '消息网关过期资源清理失败，请稍后重试。',
            zhHant: '訊息閘道過期資源清理失敗，請稍後再試。',
            en: 'Expired message gateway resource cleanup failed. Try again later.',
            fr: 'Le nettoyage des ressources expirées a échoué. Réessayez plus tard.',
            de: 'Abgelaufene Gateway-Ressourcen konnten nicht bereinigt werden. Versuchen Sie es später erneut.',
            ja: '期限切れのメッセージゲートウェイリソースを消去できませんでした。後でもう一度お試しください。',
          ),
        ),
        maxLines: 2,
      );
    } finally {
      if (mounted) setState(() => _isCleaning = false);
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
      showOpenHandSuccessSnack(
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
        duration: kOpenHandMotion1600,
      );
    } catch (error, stack) {
      silentLog('message_gateway', '执行消息网关运维服务操作', error, stack);
      if (!mounted) return;
      showOpenHandErrorSnack(
        context,
        messageGatewayFailureMessage(
          error,
          fallback: openHandLocalizedText(
            context,
            zh: '$label 失败，请稍后重试。',
            zhHant: '$label 失敗，請稍後再試。',
            en: '$label failed. Try again later.',
            fr: 'Échec de $label. Réessayez plus tard.',
            de: '$label fehlgeschlagen. Versuchen Sie es später erneut.',
            ja: '$label に失敗しました。後でもう一度お試しください。',
          ),
        ),
        maxLines: 2,
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
      OpenHandSnackBar.flash(
        context,
        '${result.summary} (${result.durationMs}ms)',
        kind: result.ok ? OpenHandSnackKind.success : OpenHandSnackKind.error,
        duration: kOpenHandMotion1800,
      );
    } catch (error, stack) {
      silentLog('message_gateway', '执行消息网关健康诊断', error, stack);
      if (!mounted) return;
      showOpenHandErrorSnack(
        context,
        messageGatewayFailureMessage(
          error,
          fallback: openHandLocalizedText(
            context,
            zh: '消息网关健康诊断失败，请稍后重试。',
            zhHant: '訊息閘道健康診斷失敗，請稍後再試。',
            en: 'Message gateway health diagnosis failed. Try again later.',
            fr: 'Le diagnostic de santé a échoué. Réessayez plus tard.',
            de: 'Gateway-Integritätsdiagnose fehlgeschlagen. Versuchen Sie es später erneut.',
            ja: 'メッセージゲートウェイのヘルス診断に失敗しました。後でもう一度お試しください。',
          ),
        ),
        maxLines: 2,
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
      showOpenHandSuccessSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '$label清理完成，释放 ${formatByteSize(result.bytesFreed)}，删除 ${result.deletedFiles} 个文件',
          zhHant:
              '$label 清理完成，釋放 ${formatByteSize(result.bytesFreed)}，刪除 ${result.deletedFiles} 個檔案',
          en: '$label cleanup completed, freed ${formatByteSize(result.bytesFreed)}, deleted ${result.deletedFiles} files',
          fr: 'Nettoyage $label terminé, ${formatByteSize(result.bytesFreed)} libérés, ${result.deletedFiles} fichiers supprimés',
          de: '$label-Bereinigung abgeschlossen, ${formatByteSize(result.bytesFreed)} freigegeben, ${result.deletedFiles} Dateien gelöscht',
          ja: '$label のクリーンアップが完了しました。${formatByteSize(result.bytesFreed)} 解放、${result.deletedFiles} ファイル削除',
        ),
      );
      await _tick();
    } catch (error, stack) {
      silentLog('message_gateway', '清理消息网关运维资源', error, stack);
      if (!mounted) return;
      showOpenHandErrorSnack(
        context,
        messageGatewayFailureMessage(
          error,
          fallback: openHandLocalizedText(
            context,
            zh: '$label 清理失败，请稍后重试。',
            zhHant: '$label 清理失敗，請稍後再試。',
            en: '$label cleanup failed. Try again later.',
            fr: 'Échec du nettoyage $label. Réessayez plus tard.',
            de: '$label-Bereinigung fehlgeschlagen. Versuchen Sie es später erneut.',
            ja: '$label のクリーンアップに失敗しました。後でもう一度お試しください。',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isCleaning = false);
    }
  }
}

class _WebOpsInsightDialog extends StatelessWidget {
  const _WebOpsInsightDialog({required this.kind, required this.snapshot});

  final _WebOpsInsightKind kind;
  final WebGatewayRuntimeSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final spec = _spec(context);
    return buildOpenHandResponsiveDialogShell(
      context: context,
      maxWidth: _kGatewayDetailDialogWidth,
      maxHeight: _kGatewayDetailDialogHeight,
      maxWidthFraction: .94,
      maxHeightFraction: .90,
      minAvailableWidth: 300,
      expandToMax: true,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      child: _WebOpsDialogSurface(
        child: _WebOpsConsoleShell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withValues(alpha: .72),
                      borderRadius: BorderRadius.circular(kOpenHandRadius13),
                    ),
                    child: Icon(
                      spec.icon,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  kOpenHandHGap12,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          spec.title,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          openHandLocalizedText(
                            context,
                            zh: '实时指标下钻 · 最近 12 分钟',
                            en: 'Live metric drill-down · last 12 minutes',
                          ),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  OpenHandToolbarIconButton(
                    icon: Icons.close_rounded,
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
              kOpenHandGap14,
              Expanded(
                child: SingleChildScrollView(
                  physics: openHandDialogAwareScrollPhysics(context),
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _NaturalCardGrid(
                        minTileWidth: 150,
                        spacing: 10,
                        maxColumns: 4,
                        children: _metricTiles(context),
                      ),
                      kOpenHandGap14,
                      _detailPanel(context),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  ({String title, IconData icon}) _spec(BuildContext context) {
    String text(String zh, String en) =>
        openHandLocalizedText(context, zh: zh, en: en);
    return switch (kind) {
      _WebOpsInsightKind.overview => (
        title: text('运行总览', 'Runtime overview'),
        icon: Icons.dashboard_rounded,
      ),
      _WebOpsInsightKind.connections => (
        title: text('连接与并发', 'Connections and concurrency'),
        icon: Icons.link_rounded,
      ),
      _WebOpsInsightKind.requests => (
        title: text('请求明细', 'Request details'),
        icon: Icons.call_made_rounded,
      ),
      _WebOpsInsightKind.outcomes => (
        title: text('请求结果', 'Request outcomes'),
        icon: Icons.task_alt_rounded,
      ),
      _WebOpsInsightKind.traffic => (
        title: text('流量明细', 'Traffic details'),
        icon: Icons.swap_vert_rounded,
      ),
      _WebOpsInsightKind.latency => (
        title: text('延迟明细', 'Latency details'),
        icon: Icons.timer_rounded,
      ),
      _WebOpsInsightKind.mutations => (
        title: text('文件变动', 'File mutations'),
        icon: Icons.change_circle_rounded,
      ),
      _WebOpsInsightKind.requestTrend => (
        title: text('请求趋势', 'Request trend'),
        icon: Icons.show_chart_rounded,
      ),
      _WebOpsInsightKind.latencyTrend => (
        title: text('耗时曲线', 'Latency curve'),
        icon: Icons.timeline_rounded,
      ),
      _WebOpsInsightKind.statusMix => (
        title: text('状态分布', 'Status mix'),
        icon: Icons.donut_small_rounded,
      ),
      _WebOpsInsightKind.peerMix => (
        title: text('来源端点（IP:端口）', 'Source endpoints'),
        icon: Icons.public_rounded,
      ),
      _WebOpsInsightKind.clientMix => (
        title: text('客户端 UA 分布', 'Client UA mix'),
        icon: Icons.devices_other_rounded,
      ),
      _WebOpsInsightKind.requestMix => (
        title: text('请求分布', 'Request mix'),
        icon: Icons.account_tree_rounded,
      ),
      _WebOpsInsightKind.protocolMix => (
        title: text('协议分布', 'Protocol mix'),
        icon: Icons.api_rounded,
      ),
    };
  }

  List<Widget> _metricTiles(BuildContext context) {
    String text(String zh, String en) =>
        openHandLocalizedText(context, zh: zh, en: en);
    final items = <(String, String)>[
      (text('当前连接', 'Connections'), '${snapshot.currentConnections}'),
      (text('活跃请求', 'Active requests'), '${snapshot.activeRequests}'),
      (text('SSE 长连接', 'SSE streams'), '${snapshot.activeSseSubscriptions}'),
      (text('会话', 'Sessions'), '${snapshot.openSessionCount}'),
      (text('请求总数', 'Requests'), '${snapshot.totalRequests}'),
      (text('成功', 'Succeeded'), '${snapshot.successTotal}'),
      (text('拦截', 'Blocked'), '${snapshot.effectiveBlockedTotal}'),
      (text('失败', 'Failed'), '${snapshot.failedRequests}'),
      (text('入口流量', 'Inbound'), formatByteSize(snapshot.totalBytesIn)),
      (text('出口流量', 'Outbound'), formatByteSize(snapshot.totalBytesOut)),
      (text('当前 RPM', 'Current RPM'), _rate(snapshot.requestsPerMinute)),
      (text('平均延迟', 'Average latency'), '${snapshot.latencyStats.avgMs}ms'),
      ('P95', '${snapshot.latencyStats.p95Ms}ms'),
      (text('文件变动', 'Mutations'), '${snapshot.fileMutationCount}'),
      (text('内存 RSS', 'Memory RSS'), formatByteSize(snapshot.currentRssBytes)),
    ];
    return items
        .map((item) => _MetricTile(label: item.$1, value: item.$2))
        .toList(growable: false);
  }

  Widget _detailPanel(BuildContext context) {
    final stats = _WebOpsDashboardStats.from(snapshot);
    return switch (kind) {
      _WebOpsInsightKind.requestTrend => _WebOpsTrendPanel(
        title: _messageGatewayRequestTrendLabel(context),
        icon: Icons.show_chart_rounded,
        subtitle: openHandLocalizedText(
          context,
          zh: '成功 / 拦截 / 失败',
          en: 'Success / blocked / failed',
        ),
        series: stats.requestTrendSeries(context),
        emptyLabel: _messageGatewayWaitingForTrafficLabel(context),
      ),
      _WebOpsInsightKind.latency ||
      _WebOpsInsightKind.latencyTrend => _WebOpsTrendPanel(
        title: _messageGatewayLatencyCurveLabel(context),
        icon: Icons.timeline_rounded,
        subtitle: openHandLocalizedText(
          context,
          zh: '平均耗时与 P95 尾延迟',
          zhHant: '平均耗時與 P95 尾延遲',
          en: 'Average and P95 tail latency',
          fr: 'Latence moyenne et de queue P95',
          de: 'Mittelwert und P95-Tail-Latenz',
          ja: '平均および P95 テールレイテンシ',
        ),
        series: stats.latencyTrendSeries(context),
        emptyLabel: _messageGatewayNoLatencySamplesLabel(context),
        valueSuffix: 'ms',
      ),
      _WebOpsInsightKind.statusMix ||
      _WebOpsInsightKind.outcomes => _WebOpsDistributionPanel(
        title: _messageGatewayStatusMixLabel(context),
        icon: Icons.donut_small_rounded,
        values: stats.statusDistribution(context, snapshot),
      ),
      _WebOpsInsightKind.peerMix => _WebOpsDistributionPanel(
        title: _messageGatewaySourceEndpointsLabel(context),
        icon: Icons.public_rounded,
        values: snapshot.effectivePeerDistribution,
      ),
      _WebOpsInsightKind.clientMix ||
      _WebOpsInsightKind.connections => _WebOpsDistributionPanel(
        title: _messageGatewayClientUaMixLabel(context),
        icon: Icons.devices_other_rounded,
        values: snapshot.clientDistribution,
      ),
      _WebOpsInsightKind.requestMix ||
      _WebOpsInsightKind.requests ||
      _WebOpsInsightKind.mutations => _WebOpsDistributionPanel(
        title: _messageGatewayRequestMixLabel(context),
        icon: Icons.account_tree_rounded,
        values: snapshot.requestDistribution,
      ),
      _WebOpsInsightKind.protocolMix ||
      _WebOpsInsightKind.traffic => _WebOpsDistributionPanel(
        title: _messageGatewayProtocolMixLabel(context),
        icon: Icons.api_rounded,
        values: snapshot.protocolDistribution,
      ),
      _WebOpsInsightKind.overview => _WebOpsPanelGrid(
        children: [
          _WebOpsDistributionPanel(
            title: _messageGatewaySourceEndpointsLabel(context),
            icon: Icons.public_rounded,
            values: snapshot.effectivePeerDistribution,
          ),
          _WebOpsDistributionPanel(
            title: _messageGatewayProtocolMixLabel(context),
            icon: Icons.api_rounded,
            values: snapshot.protocolDistribution,
          ),
        ],
      ),
    };
  }
}

const double _webOpsOuterRadius = 24;
const double _webOpsShellRadius = 18;
const double _webOpsGridGap = 14;
const double _webOpsHoverScale = 1.012;

/// 运维头部由并排切换为上下两行的宽度阈值。
const double _webOpsHeaderCompactBreakpoint = 980;
const double _webOpsMetricWideBreakpoint = 860;
const double _webOpsMetricMediumBreakpoint = 560;
const Color _webOpsTerminalBackground = Color(0xFF10131A);
const Color _webGatewayDarkSurface = OpenHandConsolePalette.gatewayDarkSurface;
const Color _webGatewayLightGray = Color(0xFFE5E7EB);
const double _kWebOpsTerminalRadius = 8;

class _WebOpsDashboardStats {
  const _WebOpsDashboardStats({
    required this.windowRequestCount,
    required this.successBuckets,
    required this.blockedBuckets,
    required this.failedBuckets,
    required this.avgLatencyBuckets,
    required this.p95LatencyBuckets,
  });

  factory _WebOpsDashboardStats.from(WebGatewayRuntimeSnapshot snapshot) {
    final successBuckets = <double>[];
    final blockedBuckets = <double>[];
    final failedBuckets = <double>[];
    final avgLatencyBuckets = <double>[];
    final p95LatencyBuckets = <double>[];
    var windowRequestCount = 0;
    for (final sample in snapshot.trafficSeries) {
      successBuckets.add(sample.success.toDouble());
      blockedBuckets.add(sample.blocked.toDouble());
      failedBuckets.add(sample.failed.toDouble());
      avgLatencyBuckets.add(sample.avgLatencyMs.toDouble());
      p95LatencyBuckets.add(sample.p95LatencyMs.toDouble());
      windowRequestCount += sample.total;
    }
    return _WebOpsDashboardStats(
      windowRequestCount: windowRequestCount,
      successBuckets: List<double>.unmodifiable(successBuckets),
      blockedBuckets: List<double>.unmodifiable(blockedBuckets),
      failedBuckets: List<double>.unmodifiable(failedBuckets),
      avgLatencyBuckets: List<double>.unmodifiable(avgLatencyBuckets),
      p95LatencyBuckets: List<double>.unmodifiable(p95LatencyBuckets),
    );
  }

  final int windowRequestCount;
  final List<double> successBuckets;
  final List<double> blockedBuckets;
  final List<double> failedBuckets;
  final List<double> avgLatencyBuckets;
  final List<double> p95LatencyBuckets;

  String rateLabel(int value, int total) =>
      '${(unitRatio(value, total) * 100).toStringAsFixed(1)}%';

  List<OpenHandChartSeries> requestTrendSeries(BuildContext context) {
    return <OpenHandChartSeries>[
      OpenHandChartSeries(
        label: _messageGatewaySuccessLabel(context),
        values: successBuckets,
        color: OpenHandStatusColors.success,
      ),
      OpenHandChartSeries(
        label: _messageGatewayBlockedLabel(context),
        values: blockedBuckets,
        color: OpenHandStatusColors.warning,
      ),
      OpenHandChartSeries(
        label: _messageGatewayFailedLabel(context),
        values: failedBuckets,
        color: Theme.of(context).colorScheme.error,
      ),
    ];
  }

  List<OpenHandChartSeries> latencyTrendSeries(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return <OpenHandChartSeries>[
      OpenHandChartSeries(
        label: openHandLocalizedText(
          context,
          zh: '平均',
          zhHant: '平均',
          en: 'Average',
          fr: 'Moyenne',
          de: 'Mittelwert',
          ja: '平均',
        ),
        values: avgLatencyBuckets,
        color: cs.primary,
      ),
      OpenHandChartSeries(
        label: 'P95',
        values: p95LatencyBuckets,
        color: cs.tertiary,
      ),
    ];
  }

  Map<String, int> statusDistribution(
    BuildContext context,
    WebGatewayRuntimeSnapshot snapshot,
  ) {
    return <String, int>{
      _messageGatewaySuccessLabel(context): snapshot.successTotal,
      _messageGatewayBlockedLabel(context): snapshot.effectiveBlockedTotal,
      _messageGatewayFailedLabel(context): snapshot.failedRequests,
    }..removeWhere((_, value) => value <= 0);
  }
}

class _WebOpsDialogSurface extends StatelessWidget {
  const _WebOpsDialogSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(_webOpsOuterRadius),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .72)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: .18),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

class _WebOpsConsoleShell extends StatelessWidget {
  const _WebOpsConsoleShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: openHandMotionDurationMs(context, 180),
      curve: kOpenHandSwitchInCurve,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: .42),
        borderRadius: BorderRadius.circular(_webOpsShellRadius),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .72)),
      ),
      child: child,
    );
  }
}

class _WebOpsConsoleHeader extends StatelessWidget {
  const _WebOpsConsoleHeader({
    required this.snapshot,
    required this.config,
    required this.persistedSnapshotCount,
    required this.isRunning,
    required this.serviceControlsDisabled,
    required this.cleaning,
    required this.healthChecking,
    required this.startLabel,
    required this.stopLabel,
    required this.restartLabel,
    required this.reloadLabel,
    required this.hotFixLabel,
    required this.healthLabel,
    required this.onStart,
    required this.onStop,
    required this.onRestart,
    required this.onReload,
    required this.onHotFix,
    required this.onHealthCheck,
    required this.onCleanExpired,
    required this.onClearLogs,
    required this.onClearCache,
    required this.onClose,
  });

  final WebGatewayRuntimeSnapshot snapshot;
  final WebMessagePlatformConfig config;
  final int persistedSnapshotCount;
  final bool isRunning;
  final bool serviceControlsDisabled;
  final bool cleaning;
  final bool healthChecking;
  final String startLabel;
  final String stopLabel;
  final String restartLabel;
  final String reloadLabel;
  final String hotFixLabel;
  final String healthLabel;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onRestart;
  final VoidCallback onReload;
  final VoidCallback onHotFix;
  final VoidCallback onHealthCheck;
  final VoidCallback onCleanExpired;
  final VoidCallback onClearLogs;
  final VoidCallback onClearCache;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final statusColor = _webOpsStateColor(cs, snapshot.state);
    final endpoint = snapshot.boundUrl.isEmpty
        ? config.endpointUrl
        : snapshot.boundUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OpenHandResponsiveHeaderLayout(
          compactBreakpoint: _webOpsHeaderCompactBreakpoint,
          identity: _WebOpsHeaderIdentity(
            statusColor: statusColor,
            endpoint: endpoint,
          ),
          actions: _WebOpsHeaderActions(
            cleaning: cleaning,
            onClearLogs: onClearLogs,
            onClearCache: onClearCache,
            onClose: onClose,
          ),
        ),
        kOpenHandGap12,
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _WebOpsStatusChip(
              icon: Icons.circle_rounded,
              label: _runtimeStateLabel(context, snapshot.state),
              color: statusColor,
            ),
            _WebOpsStatusChip(
              icon: Icons.link_rounded,
              label: endpoint,
              color: cs.primary,
              monospace: true,
            ),
            _WebOpsStatusChip(
              icon: Icons.schedule_rounded,
              color: cs.tertiary,
              labelChild: OpenHandCompactDurationLabel(
                elapsed: Duration(milliseconds: math.max(0, snapshot.uptimeMs)),
                prefix: openHandLocalizedText(
                  context,
                  zh: '运行',
                  zhHant: '運行',
                  en: 'Uptime',
                  fr: 'Disponibilité',
                  de: 'Laufzeit',
                  ja: '稼働',
                ),
              ),
            ),
            _WebOpsStatusChip(
              icon: config.authEnabled
                  ? Icons.verified_user_rounded
                  : Icons.no_encryption_gmailerrorred_rounded,
              label: config.authEnabled
                  ? openHandLocalizedText(
                      context,
                      zh: '鉴权开启',
                      zhHant: '鑑權開啟',
                      en: 'Auth enabled',
                      fr: 'Auth activée',
                      de: 'Auth aktiv',
                      ja: '認証有効',
                    )
                  : openHandLocalizedText(
                      context,
                      zh: '鉴权关闭',
                      zhHant: '鑑權關閉',
                      en: 'Auth off',
                      fr: 'Auth désactivée',
                      de: 'Auth aus',
                      ja: '認証オフ',
                    ),
              color: config.authEnabled
                  ? cs.secondary
                  : OpenHandStatusColors.warning,
            ),
            _WebOpsStatusChip(
              icon: Icons.history_rounded,
              label: openHandLocalizedText(
                context,
                zh: '本地回溯 $persistedSnapshotCount',
                zhHant: '本地回溯 $persistedSnapshotCount',
                en: 'Local history $persistedSnapshotCount',
                fr: 'Historique local $persistedSnapshotCount',
                de: 'Lokale Historie $persistedSnapshotCount',
                ja: 'ローカル履歴 $persistedSnapshotCount',
              ),
              color: cs.primary,
            ),
          ],
        ),
        kOpenHandGap12,
        AnimatedOpacity(
          duration: openHandMotionDurationMs(context, 180),
          curve: kOpenHandSwitchInCurve,
          opacity: serviceControlsDisabled ? .64 : 1,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OpenHandToolbarIconButton(
                icon: Icons.play_arrow_rounded,
                tooltip: startLabel,
                onPressed: !isRunning && !serviceControlsDisabled
                    ? onStart
                    : null,
              ),
              OpenHandToolbarIconButton(
                icon: Icons.stop_rounded,
                tooltip: stopLabel,
                onPressed: isRunning && !serviceControlsDisabled
                    ? onStop
                    : null,
              ),
              OpenHandToolbarIconButton(
                icon: Icons.restart_alt_rounded,
                tooltip: restartLabel,
                onPressed: serviceControlsDisabled ? null : onRestart,
              ),
              OpenHandToolbarIconButton(
                icon: Icons.sync_rounded,
                tooltip: reloadLabel,
                onPressed: serviceControlsDisabled ? null : onReload,
              ),
              OpenHandToolbarIconButton(
                icon: Icons.healing_rounded,
                tooltip: hotFixLabel,
                onPressed: serviceControlsDisabled ? null : onHotFix,
              ),
              OpenHandToolbarIconButton(
                icon: healthChecking
                    ? Icons.hourglass_top_rounded
                    : Icons.monitor_heart_outlined,
                tooltip: healthLabel,
                onPressed: healthChecking ? null : onHealthCheck,
              ),
              OpenHandToolbarIconButton(
                icon: cleaning
                    ? Icons.hourglass_bottom_rounded
                    : Icons.cleaning_services_outlined,
                tooltip: openHandLocalizedText(
                  context,
                  zh: '清理过期资源',
                  zhHant: '清理過期資源',
                  en: 'Clean expired resources',
                  fr: 'Nettoyer les ressources expirées',
                  de: 'Abgelaufene Ressourcen bereinigen',
                  ja: '期限切れリソースを清理',
                ),
                onPressed: cleaning ? null : onCleanExpired,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WebOpsHeaderIdentity extends StatelessWidget {
  const _WebOpsHeaderIdentity({
    required this.statusColor,
    required this.endpoint,
  });

  final Color statusColor;
  final String endpoint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: openHandMotionDurationMs(context, 180),
              curve: kOpenHandSwitchInCurve,
              width: 50,
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: .13),
                borderRadius: kOpenHandBorderRadius16,
                border: Border.all(color: statusColor.withValues(alpha: .34)),
              ),
              child: Icon(Icons.language_rounded, color: statusColor, size: 28),
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: _StatusDot(color: statusColor),
            ),
          ],
        ),
        kOpenHandWidth13,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                openHandLocalizedText(
                  context,
                  zh: 'Web 服务运维',
                  zhHant: 'Web 服務維運',
                  en: 'Web service operations',
                  fr: 'Opérations du service web',
                  de: 'Webdienstbetrieb',
                  ja: 'Webサービス運用',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              kOpenHandGap3,
              Text(
                openHandLocalizedText(
                  context,
                  zh: '$webMessagePlatformBuiltinName · $endpoint',
                  zhHant: '$webMessagePlatformBuiltinName · $endpoint',
                  en: '$webMessagePlatformBuiltinName · $endpoint',
                  fr: '$webMessagePlatformBuiltinName · $endpoint',
                  de: '$webMessagePlatformBuiltinName · $endpoint',
                  ja: '$webMessagePlatformBuiltinName · $endpoint',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WebOpsHeaderActions extends StatelessWidget {
  const _WebOpsHeaderActions({
    required this.cleaning,
    required this.onClearLogs,
    required this.onClearCache,
    required this.onClose,
  });

  final bool cleaning;
  final VoidCallback onClearLogs;
  final VoidCallback onClearCache;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OpenHandToolbarIconButton(
          icon: Icons.delete_sweep_outlined,
          tooltip: _messageGatewayClearLogsLabel(context),
          onPressed: cleaning ? null : onClearLogs,
        ),
        OpenHandToolbarIconButton(
          icon: Icons.folder_delete_outlined,
          tooltip: openHandLocalizedText(
            context,
            zh: '清空缓存',
            zhHant: '清空快取',
            en: 'Clear cache',
            fr: 'Effacer le cache',
            de: 'Cache leeren',
            ja: 'キャッシュをクリア',
          ),
          onPressed: cleaning ? null : onClearCache,
        ),
        OpenHandToolbarIconButton(
          icon: Icons.close_rounded,
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: onClose,
        ),
      ],
    );
  }
}

class _WebOpsStatusChip extends StatelessWidget {
  const _WebOpsStatusChip({
    required this.icon,
    required this.color,
    this.label = '',
    this.labelChild,
    this.monospace = false,
  });

  final IconData icon;
  final String label;
  final Widget? labelChild;
  final Color color;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final labelStyle = openHandOpsChipLabelStyle(
      context,
      color: Theme.of(context).colorScheme.onSurface,
      monospace: monospace,
    );
    return AnimatedContainer(
      duration: openHandMotionDurationMs(context, 180),
      curve: kOpenHandSwitchInCurve,
      constraints: kOpenHandContentMaxWidth360,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: kOpenHandPillBorderRadius,
        border: Border.all(color: color.withValues(alpha: .24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          kOpenHandHGap7,
          Flexible(
            child: DefaultTextStyle(
              style: labelStyle,
              child:
                  labelChild ??
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: labelStyle,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WebOpsHeroPanel extends StatelessWidget {
  const _WebOpsHeroPanel({required this.snapshot, required this.config});

  final WebGatewayRuntimeSnapshot snapshot;
  final WebMessagePlatformConfig config;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final running = snapshot.state == WebGatewayRuntimeState.running;
    return _WebOpsPanel(
      icon: running ? Icons.cloud_done_rounded : Icons.cloud_queue_rounded,
      title: openHandLocalizedText(
        context,
        zh: '服务控制台',
        zhHant: '服務控制台',
        en: 'Service console',
        fr: 'Console du service',
        de: 'Dienstkonsole',
        ja: 'サービスコンソール',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WebOpsRuntimeTerminal(snapshot: snapshot, config: config),
          if (snapshot.accessibleUrls.isNotEmpty) ...[
            kOpenHandGap12,
            _AccessibleUrlsBar(urls: snapshot.accessibleUrls),
          ],
          if (snapshot.lastError.isNotEmpty) ...[
            kOpenHandGap12,
            Text(
              snapshot.lastError,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WebOpsRuntimeTerminal extends StatelessWidget {
  const _WebOpsRuntimeTerminal({required this.snapshot, required this.config});

  final WebGatewayRuntimeSnapshot snapshot;
  final WebMessagePlatformConfig config;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final endpoint = snapshot.boundUrl.isEmpty
        ? config.endpointUrl
        : snapshot.boundUrl;
    const promptColor = OpenHandStatusColors.success;
    final commandColor = cs.tertiary;
    return OpenHandTerminalHintCard(
      backgroundColor: _webOpsTerminalBackground,
      borderRadius: _kWebOpsTerminalRadius,
      children: [
        _WebOpsConsoleLine(
          prompt: 'OpenHand',
          command: 'web-gateway',
          detail: endpoint,
          promptColor: promptColor,
          commandColor: commandColor,
        ),
        _WebOpsConsoleLine(
          prompt: 'state',
          command: _runtimeStateLabel(context, snapshot.state),
          detail:
              'uptime=${formatCompactDurationMs(snapshot.uptimeMs)} active=${snapshot.activeRequests} sse=${snapshot.activeSseSubscriptions}',
          promptColor: promptColor,
          commandColor: commandColor,
        ),
        _WebOpsConsoleLine(
          prompt: 'traffic',
          command:
              'in=${formatByteSize(snapshot.totalBytesIn)} out=${formatByteSize(snapshot.totalBytesOut)}',
          detail:
              'rpm=${_rate(snapshot.requestsPerMinute)} err=${_rate(snapshot.errorsPerMinute)} p95=${snapshot.latencyStats.p95Ms}ms',
          promptColor: promptColor,
          commandColor: commandColor,
        ),
        _WebOpsConsoleLine(
          prompt: 'policy',
          command: config.authEnabled ? 'auth=on' : 'auth=off',
          detail:
              'telemetry=${_webOpsOnOff(config.telemetryEnabled)} logs=${_webOpsOnOff(config.loggingEnabled)} ops=${_webOpsOnOff(config.opsEnabled)}',
          promptColor: promptColor,
          commandColor: commandColor,
        ),
        _WebOpsConsoleLine(
          prompt: 'limits',
          command: 'concurrency=${config.maxConcurrentRequests}',
          detail:
              'message_tokens=${config.singleMessageTokenLimit} upload_cache=${formatByteSize(config.uploadCacheMaxBytes)}',
          promptColor: promptColor,
          commandColor: commandColor,
        ),
      ],
    );
  }
}

class _WebOpsConsoleLine extends StatelessWidget {
  const _WebOpsConsoleLine({
    required this.prompt,
    required this.command,
    required this.detail,
    required this.promptColor,
    required this.commandColor,
  });

  final String prompt;
  final String command;
  final String detail;
  final Color promptColor;
  final Color commandColor;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '> $prompt ',
            style: TextStyle(color: promptColor),
          ),
          TextSpan(
            text: command,
            style: TextStyle(color: commandColor, fontWeight: FontWeight.w900),
          ),
          TextSpan(
            text: detail.trim().isEmpty ? '' : '  $detail',
            style: TextStyle(color: Colors.white.withValues(alpha: .72)),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _WebOpsMetricGrid extends StatelessWidget {
  const _WebOpsMetricGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final columns = !maxWidth.isFinite
            ? 4
            : maxWidth >= _webOpsMetricWideBreakpoint
            ? 4
            : maxWidth >= _webOpsMetricMediumBreakpoint
            ? 2
            : 1;
        final width = maxWidth.isFinite
            ? (maxWidth - _webOpsGridGap * (columns - 1)) / columns
            : 240.0;
        return Wrap(
          spacing: _webOpsGridGap,
          runSpacing: _webOpsGridGap,
          children: [
            for (final child in children)
              SizedBox(width: math.max(0, width), child: child),
          ],
        );
      },
    );
  }
}

class _WebOpsMetricTile extends StatelessWidget {
  const _WebOpsMetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    required this.tone,
    this.progress,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final Color tone;
  final double? progress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final card = AnimatedContainer(
      duration: openHandMotionDurationMs(context, 180),
      curve: kOpenHandSwitchInCurve,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withValues(alpha: .68),
        borderRadius: kOpenHandBorderRadius8,
        border: Border.all(color: tone.withValues(alpha: .22)),
        boxShadow: [
          BoxShadow(
            color: tone.withValues(alpha: .08),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: .12),
                  borderRadius: kOpenHandBorderRadius8,
                ),
                child: Icon(icon, color: tone, size: 18),
              ),
              kOpenHandHGap10,
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          kOpenHandGap12,
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          kOpenHandGap4,
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (progress != null) ...[
            kOpenHandGap10,
            ClipRRect(
              borderRadius: kOpenHandPillBorderRadius,
              child: LinearProgressIndicator(
                value: clampUnitInterval(progress!),
                minHeight: 5,
                color: tone,
                backgroundColor: tone.withValues(alpha: .14),
              ),
            ),
          ],
        ],
      ),
    );
    return onTap == null
        ? card
        : _WebOpsTappableCard(onTap: onTap!, tone: tone, child: card);
  }
}

class _WebOpsTappableCard extends StatelessWidget {
  const _WebOpsTappableCard({
    required this.onTap,
    required this.tone,
    required this.child,
  });

  final VoidCallback onTap;
  final Color tone;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return OpenHandOpsPressScale(
      onTap: onTap,
      tone: tone,
      borderRadius: kOpenHandBorderRadius8,
      hoverScale: _webOpsHoverScale,
      showFocusRing: true,
      child: child,
    );
  }
}

class _WebOpsTrendPanel extends StatefulWidget {
  const _WebOpsTrendPanel({
    required this.title,
    required this.icon,
    required this.subtitle,
    required this.series,
    required this.emptyLabel,
    this.valueSuffix = '',
    this.onTap,
  });

  final String title;
  final IconData icon;
  final String subtitle;
  final List<OpenHandChartSeries> series;
  final String emptyLabel;
  final String valueSuffix;
  final VoidCallback? onTap;

  @override
  State<_WebOpsTrendPanel> createState() => _WebOpsTrendPanelState();
}

class _WebOpsTrendPanelState extends State<_WebOpsTrendPanel> {
  List<List<double>> _fromValues = const <List<double>>[];
  List<List<double>> _toValues = const <List<double>>[];
  List<List<double>> _lastPaintValues = const <List<double>>[];
  int _animationVersion = 0;

  @override
  void initState() {
    super.initState();
    _toValues = _snapshotValues();
    _fromValues = _toValues;
    _lastPaintValues = _toValues;
  }

  @override
  void didUpdateWidget(covariant _WebOpsTrendPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = oldWidget.series.expand((item) => item.values);
    final next = widget.series.expand((item) => item.values);
    if (scaledNumberSeriesFingerprint(previous) ==
        scaledNumberSeriesFingerprint(next)) {
      return;
    }
    _fromValues = _lastPaintValues;
    _toValues = _snapshotValues();
    _animationVersion++;
  }

  List<List<double>> _snapshotValues() => widget.series
      .map((item) => List<double>.from(item.values))
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasSamples = widget.series.any(
      (item) => item.values.any((value) => value > 0),
    );
    return _WebOpsPanel(
      icon: widget.icon,
      title: widget.title,
      onTap: widget.onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          kOpenHandGap10,
          SizedBox(
            height: 156,
            child: RepaintBoundary(
              child: TweenAnimationBuilder<double>(
                key: ValueKey<int>(_animationVersion),
                tween: Tween<double>(begin: 0, end: 1),
                duration: openHandMotionDurationMs(context, 420),
                curve: kOpenHandSwitchInCurve,
                builder: (context, progress, _) {
                  final paintedValues = List<List<double>>.generate(
                    widget.series.length,
                    (index) => _lerpSeries(
                      index < _fromValues.length
                          ? _fromValues[index]
                          : const <double>[],
                      index < _toValues.length
                          ? _toValues[index]
                          : const <double>[],
                      progress,
                    ),
                    growable: false,
                  );
                  _lastPaintValues = paintedValues;
                  final animatedSeries = List<OpenHandChartSeries>.generate(
                    widget.series.length,
                    (index) => OpenHandChartSeries(
                      label: widget.series[index].label,
                      color: widget.series[index].color,
                      values: paintedValues[index],
                    ),
                    growable: false,
                  );
                  return CustomPaint(
                    painter: OpenHandSmoothLineChartPainter(
                      series: animatedSeries,
                      gridColor: cs.outlineVariant.withValues(alpha: .46),
                      labelColor: cs.onSurfaceVariant,
                      emptyLabel: hasSamples ? '' : widget.emptyLabel,
                      valueSuffix: widget.valueSuffix,
                      textDirection: Directionality.of(context),
                    ),
                    child: const SizedBox.expand(),
                  );
                },
              ),
            ),
          ),
          kOpenHandGap12,
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (final item in widget.series)
                _WebOpsLegendPill(label: item.label, color: item.color),
            ],
          ),
        ],
      ),
    );
  }
}

class _WebOpsLegendPill extends StatelessWidget {
  const _WebOpsLegendPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        kOpenHandHGap6,
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _WebOpsDistributionPanel extends StatelessWidget {
  const _WebOpsDistributionPanel({
    required this.title,
    required this.icon,
    required this.values,
    this.onTap,
  });

  final String title;
  final IconData icon;
  final Map<String, int> values;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final otherLabel = openHandOtherLabel(context);
    final top = webGatewayCompactDistribution(values, otherLabel: otherLabel);
    final total = values.values.fold<int>(0, (sum, value) => sum + value);
    final palette = <Color>[
      cs.primary,
      cs.tertiary,
      OpenHandStatusColors.success,
      OpenHandStatusColors.warning,
      cs.error,
    ];
    return _WebOpsPanel(
      icon: icon,
      title: title,
      onTap: onTap,
      child: top.isEmpty
          ? Text(
              _messageGatewayWaitingForTrafficLabel(context),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final chart = SizedBox(
                  width: 104,
                  height: 104,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: OpenHandDonutChartPainter(
                        values: top
                            .map((entry) => entry.value)
                            .toList(growable: false),
                        colors: palette,
                        trackColor: cs.surfaceContainerHighest,
                      ),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(25),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '$total',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
                final legend = Column(
                  children: [
                    for (var index = 0; index < top.length; index++)
                      _WebOpsDistributionRow(
                        label: top[index].key,
                        value: top[index].value,
                        total: total,
                        color: palette[index % palette.length],
                      ),
                  ],
                );
                if (_webGatewayOpsShouldStackDistribution(
                  constraints.maxWidth,
                )) {
                  return Column(children: [chart, kOpenHandGap12, legend]);
                }
                return Row(
                  children: [
                    chart,
                    kOpenHandHGap14,
                    Expanded(child: legend),
                  ],
                );
              },
            ),
    );
  }
}

class _WebOpsDistributionRow extends StatelessWidget {
  const _WebOpsDistributionRow({
    required this.label,
    required this.value,
    required this.total,
    required this.color,
  });

  final String label;
  final int value;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = unitRatio(value, total);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: label,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium,
                  ),
                ),
              ),
              kOpenHandHGap8,
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 64),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    '$value',
                    maxLines: 1,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
          kOpenHandGap5,
          ClipRRect(
            borderRadius: kOpenHandPillBorderRadius,
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 7,
              color: color,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

class _WebOpsPanelGrid extends StatelessWidget {
  const _WebOpsPanelGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final columns = !maxWidth.isFinite || maxWidth >= 900 ? 2 : 1;
        final width = maxWidth.isFinite
            ? (maxWidth - _webOpsGridGap * (columns - 1)) / columns
            : 420.0;
        return Wrap(
          spacing: _webOpsGridGap,
          runSpacing: _webOpsGridGap,
          children: [
            for (final child in children)
              SizedBox(width: math.max(0, width), child: child),
          ],
        );
      },
    );
  }
}

class _WebOpsPanel extends StatelessWidget {
  const _WebOpsPanel({
    required this.icon,
    required this.title,
    required this.child,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final panel = Container(
      padding: _kOpsCardPadding,
      decoration: _opsCardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: .58),
                  borderRadius: kOpenHandBorderRadius8,
                ),
                child: Icon(icon, size: 17, color: cs.onPrimaryContainer),
              ),
              kOpenHandHGap10,
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          kOpenHandGap12,
          child,
        ],
      ),
    );
    return onTap == null
        ? panel
        : _WebOpsTappableCard(onTap: onTap!, tone: cs.primary, child: panel);
  }
}

class _WebOpsEnvironmentPanel extends StatelessWidget {
  const _WebOpsEnvironmentPanel({required this.snapshot, required this.config});

  final WebGatewayRuntimeSnapshot snapshot;
  final WebMessagePlatformConfig config;

  @override
  Widget build(BuildContext context) {
    final startedAt = snapshot.startedAt?.toLocal();
    final platform = snapshot.platform.isEmpty
        ? Platform.operatingSystem
        : snapshot.platform;
    final platformVersion = snapshot.platformVersion.isEmpty
        ? Platform.operatingSystemVersion
        : snapshot.platformVersion;
    return _WebOpsPanel(
      icon: Icons.dns_rounded,
      title: openHandLocalizedText(
        context,
        zh: '环境与进程画像',
        zhHant: '環境與程序畫像',
        en: 'Environment and process profile',
        fr: 'Profil environnement et processus',
        de: 'Umgebungs- und Prozessprofil',
        ja: '環境とプロセスプロファイル',
      ),
      child: Column(
        children: [
          _WebOpsInfoRow(
            openHandLocalizedText(
              context,
              zh: '主机',
              zhHant: '主機',
              en: 'Host',
              fr: 'Hôte',
              de: 'Host',
              ja: 'ホスト',
            ),
            snapshot.hostName.isEmpty
                ? _gatewayUnavailable(context)
                : snapshot.hostName,
          ),
          _WebOpsInfoRow(
            openHandLocalizedText(
              context,
              zh: '系统',
              zhHant: '系統',
              en: 'System',
              fr: 'Système',
              de: 'System',
              ja: 'システム',
            ),
            '$platform · $platformVersion',
          ),
          _WebOpsInfoRow(
            'PID / Dart',
            '${snapshot.processId <= 0 ? pid : snapshot.processId} · ${snapshot.dartVersion.isEmpty ? Platform.version : snapshot.dartVersion}',
          ),
          _WebOpsInfoRow(
            openHandLocalizedText(
              context,
              zh: '启动时间',
              zhHant: '啟動時間',
              en: 'Started at',
              fr: 'Démarré à',
              de: 'Gestartet um',
              ja: '起動時刻',
            ),
            startedAt == null
                ? _gatewayUnavailable(context)
                : formatYearMonthDayHms(startedAt),
          ),
          _WebOpsInfoRow(
            openHandLocalizedText(
              context,
              zh: '监听策略',
              zhHant: '監聽策略',
              en: 'Listen policy',
              fr: 'Politique écoute',
              de: 'Lauschrichtlinie',
              ja: 'リッスンポリシー',
            ),
            '${config.listenHost}:${config.listenPort} · ${snapshot.accessibleUrls.length} URL',
          ),
          _WebOpsInfoRow(
            openHandLocalizedText(
              context,
              zh: '资源占用',
              zhHant: '資源佔用',
              en: 'Resource usage',
              fr: 'Utilisation ressources',
              de: 'Ressourcennutzung',
              ja: 'リソース使用量',
            ),
            'RSS ${formatByteSize(snapshot.currentRssBytes)} · CPU ${snapshot.cpuPercent == null ? _gatewayUnavailable(context) : '${snapshot.cpuPercent!.toStringAsFixed(1)}%'}',
          ),
          _WebOpsInfoRow(
            openHandLocalizedText(
              context,
              zh: '句柄 / Swap',
              zhHant: '句柄 / Swap',
              en: 'Handles / Swap',
              fr: 'Handles / Swap',
              de: 'Handles / Swap',
              ja: 'ハンドル / Swap',
            ),
            '${snapshot.fileHandleCount?.toString() ?? _gatewayUnavailable(context)} · ${snapshot.swapBytes == null ? _gatewayUnavailable(context) : formatByteSize(snapshot.swapBytes!)}',
          ),
        ],
      ),
    );
  }
}

class _WebOpsFeatureMatrixPanel extends StatelessWidget {
  const _WebOpsFeatureMatrixPanel({
    required this.snapshot,
    required this.config,
  });

  final WebGatewayRuntimeSnapshot snapshot;
  final WebMessagePlatformConfig config;

  @override
  Widget build(BuildContext context) {
    return _WebOpsPanel(
      icon: Icons.tune_rounded,
      title: openHandLocalizedText(
        context,
        zh: '能力、策略与数据面',
        zhHant: '能力、策略與資料面',
        en: 'Capabilities, policy and data plane',
        fr: 'Capacités, politiques et plan de données',
        de: 'Fähigkeiten, Richtlinien und Datenebene',
        ja: '機能、ポリシー、データプレーン',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _webOpsFlagChip(
                context,
                label: openHandLocalizedText(
                  context,
                  zh: '鉴权',
                  zhHant: '鑑權',
                  en: 'Auth',
                  fr: 'Auth',
                  de: 'Auth',
                  ja: '認証',
                ),
                enabled: config.authEnabled,
              ),
              _webOpsFlagChip(
                context,
                label: openHandLocalizedText(
                  context,
                  zh: '遥测',
                  zhHant: '遙測',
                  en: 'Telemetry',
                  fr: 'Télémétrie',
                  de: 'Telemetrie',
                  ja: 'テレメトリ',
                ),
                enabled: config.telemetryEnabled,
              ),
              _webOpsFlagChip(
                context,
                label: openHandLocalizedText(
                  context,
                  zh: '日志',
                  zhHant: '日誌',
                  en: 'Logging',
                  fr: 'Journalisation',
                  de: 'Protokolle',
                  ja: 'ログ',
                ),
                enabled: config.loggingEnabled,
              ),
              _webOpsFlagChip(
                context,
                label: openHandLocalizedText(
                  context,
                  zh: '运维 API',
                  zhHant: '維運 API',
                  en: 'Ops API',
                  fr: 'API Ops',
                  de: 'Ops-API',
                  ja: 'Ops API',
                ),
                enabled: config.opsEnabled,
              ),
              _webOpsFlagChip(
                context,
                label: openHandLocalizedText(
                  context,
                  zh: '自动启动',
                  zhHant: '自動啟動',
                  en: 'Auto start',
                  fr: 'Démarrage auto',
                  de: 'Autostart',
                  ja: '自動起動',
                ),
                enabled: config.autoStartOnLaunch,
              ),
              _webOpsFlagChip(
                context,
                label: openHandLocalizedText(
                  context,
                  zh: '热重载',
                  zhHant: '熱重載',
                  en: 'Hot reload',
                  fr: 'Rechargement à chaud',
                  de: 'Hot Reload',
                  ja: 'ホットリロード',
                ),
                enabled: config.autoReloadOnChange,
              ),
              _webOpsFlagChip(
                context,
                label: openHandLocalizedText(
                  context,
                  zh: '工作区写入',
                  zhHant: '工作區寫入',
                  en: 'Workspace write',
                  fr: 'Écriture workspace',
                  de: 'Workspace-Schreiben',
                  ja: 'ワークスペース書込',
                ),
                enabled: config.workspaceFileWriteEnabled,
              ),
              _webOpsFlagChip(
                context,
                label: openHandLocalizedText(
                  context,
                  zh: '会话管理',
                  zhHant: '會話管理',
                  en: 'Sessions',
                  fr: 'Sessions',
                  de: 'Sitzungen',
                  ja: 'セッション',
                ),
                enabled: config.sessionManagementEnabled,
              ),
              _webOpsFlagChip(
                context,
                label: openHandLocalizedText(
                  context,
                  zh: '工作区文件',
                  zhHant: '工作區檔案',
                  en: 'Workspace files',
                  fr: 'Fichiers workspace',
                  de: 'Workspace-Dateien',
                  ja: 'ワークスペースファイル',
                ),
                enabled: config.workspaceFilesEnabled,
              ),
              _webOpsFlagChip(
                context,
                label: openHandLocalizedText(
                  context,
                  zh: '计划模式',
                  zhHant: '計劃模式',
                  en: 'Plan mode',
                  fr: 'Mode plan',
                  de: 'Planmodus',
                  ja: '計画モード',
                ),
                enabled: config.planModeEnabled,
              ),
              _webOpsFlagChip(
                context,
                label: openHandKnowledgeLabel(context),
                enabled: config.knowledgeBaseEnabled,
              ),
              _webOpsFlagChip(
                context,
                label: openHandLocalizedText(
                  context,
                  zh: '朗读',
                  zhHant: '朗讀',
                  en: 'Read aloud',
                  fr: 'Lecture vocale',
                  de: 'Vorlesen',
                  ja: '読み上げ',
                ),
                enabled: config.readAloudEnabled,
              ),
              _webOpsFlagChip(
                context,
                label: openHandTranslateLabel(context),
                enabled: config.translationEnabled,
              ),
              _webOpsFlagChip(
                context,
                label: openHandLocalizedText(
                  context,
                  zh: '反馈',
                  zhHant: '回饋',
                  en: 'Feedback',
                  fr: 'Retour',
                  de: 'Feedback',
                  ja: 'フィードバック',
                ),
                enabled: config.feedbackEnabled,
              ),
              _webOpsFlagChip(
                context,
                label: openHandRegenerateLabel(context),
                enabled: config.regenerationEnabled,
              ),
              _webOpsFlagChip(
                context,
                label: openHandLocalizedText(
                  context,
                  zh: '健康检查',
                  zhHant: '健康檢查',
                  en: 'Health check',
                  fr: 'Santé',
                  de: 'Healthcheck',
                  ja: 'ヘルスチェック',
                ),
                enabled: config.healthCheck.enabled,
              ),
            ],
          ),
          kOpenHandGap12,
          _WebOpsInfoRow(
            openHandLocalizedText(
              context,
              zh: '入口限制',
              zhHant: '入口限制',
              en: 'Ingress limits',
              fr: 'Limites entrée',
              de: 'Ingress-Limits',
              ja: '入口制限',
            ),
            openHandLocalizedText(
              context,
              zh: '${config.maxConcurrentRequests} 并发 · ${config.singleMessageTokenLimit} token/消息 · ${config.maxMessagesPerSession} 消息/会话',
              zhHant:
                  '${config.maxConcurrentRequests} 並發 · ${config.singleMessageTokenLimit} token/訊息 · ${config.maxMessagesPerSession} 訊息/會話',
              en: '${config.maxConcurrentRequests} concurrent · ${config.singleMessageTokenLimit} tokens/message · ${config.maxMessagesPerSession} messages/session',
              fr: '${config.maxConcurrentRequests} concurrents · ${config.singleMessageTokenLimit} tokens/message · ${config.maxMessagesPerSession} messages/session',
              de: '${config.maxConcurrentRequests} parallel · ${config.singleMessageTokenLimit} Tokens/Nachricht · ${config.maxMessagesPerSession} Nachrichten/Sitzung',
              ja: '${config.maxConcurrentRequests} 同時実行 · ${config.singleMessageTokenLimit} token/メッセージ · ${config.maxMessagesPerSession} メッセージ/セッション',
            ),
          ),
          _WebOpsInfoRow(
            openHandLocalizedText(
              context,
              zh: '缓存与文件',
              zhHant: '快取與檔案',
              en: 'Cache and files',
              fr: 'Cache et fichiers',
              de: 'Cache und Dateien',
              ja: 'キャッシュとファイル',
            ),
            openHandLocalizedText(
              context,
              zh: '上传缓存 ${formatByteSize(config.uploadCacheMaxBytes)} / ${config.uploadCacheRetentionDays} 天 · 工作区 ${formatByteSize(config.workspaceFileMaxBytes)}',
              zhHant:
                  '上傳快取 ${formatByteSize(config.uploadCacheMaxBytes)} / ${config.uploadCacheRetentionDays} 天 · 工作區 ${formatByteSize(config.workspaceFileMaxBytes)}',
              en: 'upload cache ${formatByteSize(config.uploadCacheMaxBytes)} / ${config.uploadCacheRetentionDays} days · workspace ${formatByteSize(config.workspaceFileMaxBytes)}',
              fr: 'cache upload ${formatByteSize(config.uploadCacheMaxBytes)} / ${config.uploadCacheRetentionDays} jours · workspace ${formatByteSize(config.workspaceFileMaxBytes)}',
              de: 'Upload-Cache ${formatByteSize(config.uploadCacheMaxBytes)} / ${config.uploadCacheRetentionDays} Tage · Workspace ${formatByteSize(config.workspaceFileMaxBytes)}',
              ja: 'アップロードキャッシュ ${formatByteSize(config.uploadCacheMaxBytes)} / ${config.uploadCacheRetentionDays} 日 · ワークスペース ${formatByteSize(config.workspaceFileMaxBytes)}',
            ),
          ),
          _WebOpsInfoRow(
            openHandLocalizedText(
              context,
              zh: '资源可见性',
              zhHant: '資源可見性',
              en: 'Resource visibility',
              fr: 'Visibilité ressources',
              de: 'Ressourcensichtbarkeit',
              ja: 'リソース可視性',
            ),
            openHandLocalizedText(
              context,
              zh: '模型 ${snapshot.allowedModelCount} · 模板 ${snapshot.templateCount} · MCP ${snapshot.mcpServerEnabledCount}/${snapshot.mcpServerTotalCount} · 记忆 ${snapshot.memoryEntryCount}',
              zhHant:
                  '模型 ${snapshot.allowedModelCount} · 模板 ${snapshot.templateCount} · MCP ${snapshot.mcpServerEnabledCount}/${snapshot.mcpServerTotalCount} · 記憶 ${snapshot.memoryEntryCount}',
              en: 'models ${snapshot.allowedModelCount} · templates ${snapshot.templateCount} · MCP ${snapshot.mcpServerEnabledCount}/${snapshot.mcpServerTotalCount} · memory ${snapshot.memoryEntryCount}',
              fr: 'modèles ${snapshot.allowedModelCount} · templates ${snapshot.templateCount} · MCP ${snapshot.mcpServerEnabledCount}/${snapshot.mcpServerTotalCount} · mémoire ${snapshot.memoryEntryCount}',
              de: 'Modelle ${snapshot.allowedModelCount} · Vorlagen ${snapshot.templateCount} · MCP ${snapshot.mcpServerEnabledCount}/${snapshot.mcpServerTotalCount} · Speicher ${snapshot.memoryEntryCount}',
              ja: 'モデル ${snapshot.allowedModelCount} · テンプレート ${snapshot.templateCount} · MCP ${snapshot.mcpServerEnabledCount}/${snapshot.mcpServerTotalCount} · メモリ ${snapshot.memoryEntryCount}',
            ),
          ),
          _WebOpsInfoRow(
            openHandLocalizedText(
              context,
              zh: '授权清单',
              zhHant: '授權清單',
              en: 'Allow lists',
              fr: 'Listes autorisées',
              de: 'Allow-Listen',
              ja: '許可リスト',
            ),
            openHandLocalizedText(
              context,
              zh: '技能 ${_webOpsScopeCount(context, config.allowedSkillNames)} · 工具 ${_webOpsScopeCount(context, config.allowedBuiltinToolNames)} · 指令 ${_webOpsScopeCount(context, config.allowedInstructionIds)}',
              zhHant:
                  '技能 ${_webOpsScopeCount(context, config.allowedSkillNames)} · 工具 ${_webOpsScopeCount(context, config.allowedBuiltinToolNames)} · 指令 ${_webOpsScopeCount(context, config.allowedInstructionIds)}',
              en: 'skills ${_webOpsScopeCount(context, config.allowedSkillNames)} · tools ${_webOpsScopeCount(context, config.allowedBuiltinToolNames)} · instructions ${_webOpsScopeCount(context, config.allowedInstructionIds)}',
              fr: 'skills ${_webOpsScopeCount(context, config.allowedSkillNames)} · outils ${_webOpsScopeCount(context, config.allowedBuiltinToolNames)} · instructions ${_webOpsScopeCount(context, config.allowedInstructionIds)}',
              de: 'Skills ${_webOpsScopeCount(context, config.allowedSkillNames)} · Tools ${_webOpsScopeCount(context, config.allowedBuiltinToolNames)} · Anweisungen ${_webOpsScopeCount(context, config.allowedInstructionIds)}',
              ja: 'スキル ${_webOpsScopeCount(context, config.allowedSkillNames)} · ツール ${_webOpsScopeCount(context, config.allowedBuiltinToolNames)} · 指示 ${_webOpsScopeCount(context, config.allowedInstructionIds)}',
            ),
          ),
          _WebOpsInfoRow(
            openHandLocalizedText(
              context,
              zh: '日志策略',
              zhHant: '日誌策略',
              en: 'Log policy',
              fr: 'Politique journaux',
              de: 'Protokollrichtlinie',
              ja: 'ログポリシー',
            ),
            openHandLocalizedText(
              context,
              zh: '${formatByteSize(config.logConfig.fileMaxBytes)} / 文件 · ${config.logConfig.maxFiles} 文件 · ${config.logConfig.rotationDays} 天轮转 · ${config.logConfig.lazyReadPageSize} 条/页',
              zhHant:
                  '${formatByteSize(config.logConfig.fileMaxBytes)} / 檔案 · ${config.logConfig.maxFiles} 檔案 · ${config.logConfig.rotationDays} 天輪轉 · ${config.logConfig.lazyReadPageSize} 則/頁',
              en: '${formatByteSize(config.logConfig.fileMaxBytes)} per file · ${config.logConfig.maxFiles} files · ${config.logConfig.rotationDays}d rotation · ${config.logConfig.lazyReadPageSize}/page',
              fr: '${formatByteSize(config.logConfig.fileMaxBytes)} par fichier · ${config.logConfig.maxFiles} fichiers · rotation ${config.logConfig.rotationDays}j · ${config.logConfig.lazyReadPageSize}/page',
              de: '${formatByteSize(config.logConfig.fileMaxBytes)} pro Datei · ${config.logConfig.maxFiles} Dateien · Rotation ${config.logConfig.rotationDays}T · ${config.logConfig.lazyReadPageSize}/Seite',
              ja: 'ファイルごと ${formatByteSize(config.logConfig.fileMaxBytes)} · ${config.logConfig.maxFiles} ファイル · ${config.logConfig.rotationDays}日ローテーション · ${config.logConfig.lazyReadPageSize}/ページ',
            ),
          ),
          _WebOpsInfoRow(
            openHandLocalizedText(
              context,
              zh: '消息面',
              zhHant: '訊息面',
              en: 'Message plane',
              fr: 'Plan messages',
              de: 'Nachrichtenebene',
              ja: 'メッセージ面',
            ),
            '${config.allowedMessageTypes.map((item) => _messageTypeLabel(context, item)).join(_gatewayListSeparator(context))} · ${config.allowedConversationModes.map((item) => _modeLabel(context, item)).join(_gatewayListSeparator(context))}',
          ),
          _WebOpsInfoRow(
            openHandLocalizedText(
              context,
              zh: '健康检查',
              zhHant: '健康檢查',
              en: 'Health check',
              fr: 'Contrôle santé',
              de: 'Integritätsprüfung',
              ja: 'ヘルスチェック',
            ),
            _webOpsHealthEndpoint(context, config),
          ),
        ],
      ),
    );
  }
}

class _WebOpsInfoRow extends StatelessWidget {
  const _WebOpsInfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          kOpenHandHGap10,
          Expanded(
            child: SelectableText(
              value,
              maxLines: 2,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Color _webOpsStateColor(ColorScheme colorScheme, WebGatewayRuntimeState state) {
  return switch (state) {
    WebGatewayRuntimeState.running => OpenHandStatusColors.success,
    WebGatewayRuntimeState.crashed => colorScheme.error,
    WebGatewayRuntimeState.starting ||
    WebGatewayRuntimeState.stopping => OpenHandStatusColors.warning,
    WebGatewayRuntimeState.stopped => colorScheme.onSurfaceVariant,
  };
}

String _webOpsOnOff(bool value) => value ? 'on' : 'off';

Widget _webOpsFlagChip(
  BuildContext context, {
  required String label,
  required bool enabled,
}) {
  final cs = Theme.of(context).colorScheme;
  final color = enabled ? OpenHandStatusColors.success : cs.onSurfaceVariant;
  return _OpsPill(
    label,
    enabled
        ? _messageGatewayOnLabel(context)
        : _messageGatewayOffLabel(context),
    color: color,
  );
}

String _webOpsScopeCount(BuildContext context, List<String> values) {
  if (webGatewayIsDenyAllSelection(values)) {
    return openHandLocalizedText(
      context,
      zh: '全部不可用',
      zhHant: '全部不可用',
      en: 'all unavailable',
      fr: 'tout indisponible',
      de: 'alle nicht verfügbar',
      ja: 'すべて利用不可',
    );
  }
  if (values.isEmpty) {
    return openHandLocalizedText(
      context,
      zh: '全部可用',
      zhHant: '全部可用',
      en: 'all available',
      fr: 'tout disponible',
      de: 'alle verfügbar',
      ja: 'すべて利用可能',
    );
  }
  return openHandLocalizedText(
    context,
    zh: '${values.length} 项',
    zhHant: '${values.length} 項',
    en: '${values.length} items',
    fr: '${values.length} éléments',
    de: '${values.length} Einträge',
    ja: '${values.length} 項目',
  );
}

String _webOpsHealthEndpoint(
  BuildContext context,
  WebMessagePlatformConfig config,
) {
  final query = config.healthCheck.queryParameters.isEmpty
      ? ''
      : '?${_formatQueryParameters(config.healthCheck.queryParameters)}';
  final enabled = config.healthCheck.enabled
      ? _messageGatewayOnLabel(context)
      : _messageGatewayOffLabel(context);
  return '$enabled · ${config.healthCheck.method} ${config.healthCheck.path}$query · ${config.healthCheck.timeoutMs}ms · ${config.healthCheck.expectedStatusCode}';
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
          shape: const CircleBorder(),
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

/// 消息网关平台身份区：大图标 + 状态点 + 标题描述。
/// 宽屏由外层 Row 把操作按钮放在右侧固有宽度区，介绍可扩展到按钮左侧空隙。
class _GatewayPlatformIdentity extends StatelessWidget {
  const _GatewayPlatformIdentity({
    required this.title,
    required this.description,
    required this.statusColor,
    this.icon,
    this.iconChild,
  }) : assert(icon != null || iconChild != null);

  final IconData? icon;
  final Widget? iconChild;
  final String title;
  final String description;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: _kGatewayIdentityExtent,
              height: _kGatewayIdentityExtent,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: kOpenHandBorderRadius18,
              ),
              alignment: Alignment.center,
              child:
                  iconChild ??
                  Icon(
                    icon,
                    size: _kGatewayIdentityIconSize,
                    color: colors.onPrimaryContainer,
                  ),
            ),
            Positioned(
              right: -3,
              bottom: -3,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surface,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.circle, color: statusColor, size: 18),
              ),
            ),
          ],
        ),
        kOpenHandHGap16,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.headlineSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              kOpenHandGap8,
              Text(
                description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
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

/// 配置事实芯片：次级信息，视觉权重低于状态胶囊。
class _GatewayFactChip extends StatelessWidget {
  const _GatewayFactChip({
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
      padding: _kGatewayFactPadding,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(_kGatewayFactRadius),
        border: Border.all(color: color.withValues(alpha: 0.26)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: _kGatewayFactIconSize, color: color),
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

/// 卡片底部运行指标条：一体式仪表盘分区，替代零散灰块。
class _GatewayRuntimeMetricsStrip extends StatelessWidget {
  const _GatewayRuntimeMetricsStrip({required this.items});

  final List<({String label, String value, Color accent})> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720 || items.length <= 1;
        if (compact) {
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final item in items)
                SizedBox(
                  width: constraints.maxWidth < 420
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 10) / 2,
                  child: _GatewayMetricCell(item: item),
                ),
            ],
          );
        }
        return DecoratedBox(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(kOpenHandRadius16),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Padding(
            padding: _kGatewayMetricsPadding,
            child: IntrinsicHeight(
              child: Row(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: cs.outlineVariant,
                        ),
                      ),
                    Expanded(child: _GatewayMetricCell(item: items[i])),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GatewayMetricCell extends StatelessWidget {
  const _GatewayMetricCell({required this.item});

  final ({String label, String value, Color accent}) item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AnimatedContainer(
      duration: openHandMotionDurationMs(context, 180),
      curve: kOpenHandSwitchInCurve,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: item.accent,
                  shape: BoxShape.circle,
                ),
              ),
              kOpenHandHGap8,
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          kOpenHandGap8,
          Text(
            item.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              color: item.accent,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// 弹窗内轻量信息芯片：复用状态胶囊，保持与卡片状态层一致的语义色。
const double _kGatewayUrlPillIconSize = 15;
const double _kGatewayUrlPillActionSize = 30;
const EdgeInsets _kGatewayUrlPillPadding = EdgeInsets.symmetric(
  horizontal: 10,
  vertical: 5,
);

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return OpenHandStatusPill(
      icon: icon,
      label: label,
      color: cs.onSurfaceVariant,
    );
  }
}

/// 监听通配符地址（0.0.0.0 / ::）时展示全部可访问 URL 的横向胶囊条。
/// 每个 URL 胶囊同时提供复制与浏览器访问动作。
class _AccessibleUrlsBar extends StatelessWidget {
  const _AccessibleUrlsBar({required this.urls});

  final List<String> urls;

  Future<void> _copy(BuildContext context, String url) async {
    await copyOpenHandTextToClipboard(
      logTag: 'message_gateway',
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
      logAction: '复制可访问地址',
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
        showOpenHandErrorSnack(
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
        );
        return;
      }
      showOpenHandInfoSnack(
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
      );
    } catch (error, stack) {
      silentLog('message_gateway', '打开地址', error, stack);
      if (!context.mounted) return;
      showOpenHandErrorSnack(
        context,
        messageGatewayFailureMessage(
          error,
          fallback: openHandLocalizedText(
            context,
            zh: '打开地址失败，请稍后重试。',
            zhHant: '開啟位址失敗，請稍後再試。',
            en: 'Failed to open the address. Try again later.',
            fr: 'Impossible d’ouvrir l’adresse. Réessayez plus tard.',
            de: 'Adresse konnte nicht geöffnet werden. Versuchen Sie es später erneut.',
            ja: 'アドレスを開けませんでした。後でもう一度お試しください。',
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
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(kOpenHandRadius8),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.lan_outlined, size: 14, color: cs.primary),
            ),
            kOpenHandHGap8,
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
              style: theme.textTheme.labelLarge?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        kOpenHandGap10,
        Wrap(
          spacing: 10,
          runSpacing: 10,
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
    final accent = cs.primary;
    return Container(
      constraints: kOpenHandContentMaxWidth360,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: kOpenHandPillBorderRadius,
        border: Border.all(color: accent.withValues(alpha: 0.26)),
      ),
      padding: _kGatewayUrlPillPadding,
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
                foregroundColor: accent,
                hoverColor: accent.withValues(alpha: 0.10),
                highlightColor: accent.withValues(alpha: 0.14),
                focusColor: accent.withValues(alpha: 0.12),
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.content_copy_rounded),
              iconSize: _kGatewayUrlPillIconSize,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(
                width: _kGatewayUrlPillActionSize,
                height: _kGatewayUrlPillActionSize,
              ),
            ),
          ),
          Flexible(
            child: Text(
              url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                color: accent,
                fontWeight: FontWeight.w600,
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
                foregroundColor: accent,
                hoverColor: accent.withValues(alpha: 0.10),
                highlightColor: accent.withValues(alpha: 0.14),
                focusColor: accent.withValues(alpha: 0.12),
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.open_in_browser_rounded),
              iconSize: _kGatewayUrlPillIconSize,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(
                width: _kGatewayUrlPillActionSize,
                height: _kGatewayUrlPillActionSize,
              ),
            ),
          ),
        ],
      ),
    );
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
    final colorScheme = theme.colorScheme;
    return AnimatedContainer(
      duration: openHandMotionDurationMs(context, 180),
      curve: kOpenHandSwitchInCurve,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.62),
        borderRadius: kOpenHandBorderRadius8,
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.72),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          kOpenHandGap8,
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
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
              borderRadius: BorderRadius.circular(kOpenHandRadius10),
            ),
            child: Icon(icon, size: 15, color: colorScheme.onPrimaryContainer),
          ),
          kOpenHandHGap9,
          Text(
            text,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: colorScheme.onSurface,
            ),
          ),
          kOpenHandHGap10,
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
      padding: _kOpsCardPadding,
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
                    kOpenHandGap4,
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
                        kOpenHandHGap8,
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
          kOpenHandGap12,
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: diagnosis.signals
                .map((signal) => _OpsPill(signal.label, signal.value))
                .toList(growable: false),
          ),
          kOpenHandGap12,
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
          kOpenHandGap4,
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
          kOpenHandGap8,
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
        : snapshot.failedRequests / snapshot.totalRequests;
    final failuresPerMinute = snapshot.trafficSeries.isEmpty
        ? 0.0
        : snapshot.trafficSeries.last.failed.toDouble();
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
      zh: '失败率',
      zhHant: '失敗率',
      en: 'Failure rate',
      fr: 'Taux d’échec',
      de: 'Ausfallrate',
      ja: '失敗率',
    );
    final errorsPerMinuteLabel = openHandLocalizedText(
      context,
      zh: '失败/min',
      zhHant: '失敗/min',
      en: 'Failures/min',
      fr: 'Échecs/min',
      de: 'Ausfälle/min',
      ja: '失敗/min',
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
    final p95LatencyLabel = _messageGatewayP95LatencyLabel(context);

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
    if (failuresPerMinute > 0) {
      score -= math.min(15, 5 + (failuresPerMinute * 2).round());
      alerts.add(
        _OpsDiagnosisAlert(
          errorsPerMinuteLabel,
          '> 0',
          _rate(failuresPerMinute),
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
        _OpsDiagnosisSignal(errorsPerMinuteLabel, _rate(failuresPerMinute)),
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
      padding: _kOpsCardPadding,
      decoration: _opsCardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.monitor_heart_outlined, size: 18),
              kOpenHandHGap8,
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
          kOpenHandGap12,
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
                openHandErrorsLabel(context),
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
          kOpenHandGap12,
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
              '${slow.method} ${slow.path} -> ${slow.statusCode} · ${slow.durationMs}ms${slow.at == null ? '' : ' · ${formatYearMonthDayHmsLocal(slow.at!)}'}',
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
      padding: _kOpsCardPadding,
      decoration: _opsCardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          kOpenHandGap10,
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
            kOpenHandGap12,
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
              kOpenHandHGap8,
              Text('$value', style: theme.textTheme.labelMedium),
            ],
          ),
          kOpenHandGap4,
          ClipRRect(
            borderRadius: kOpenHandPillBorderRadius,
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
      padding: _kOpsCardPadding,
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
          kOpenHandGap10,
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
      padding: _kOpsCardPadding,
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
          kOpenHandGap10,
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
      padding: _kOpsCardPadding,
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
          kOpenHandGap10,
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
                openHandMemoryLabel(context),
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
  const _OpsPill(this.label, this.value, {this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = color ?? theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: kOpenHandBorderRadius8,
        border: Border.all(color: tone.withValues(alpha: 0.20)),
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
              style: TextStyle(fontWeight: FontWeight.w800, color: tone),
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
          kOpenHandHGap8,
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

/// 运维面板卡片的统一内边距，与 [_opsCardDecoration] 配套使用。
const EdgeInsets _kOpsCardPadding = EdgeInsets.all(14);

BoxDecoration _opsCardDecoration(ThemeData theme) => BoxDecoration(
  color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.58),
  borderRadius: kOpenHandBorderRadius8,
  border: Border.all(
    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.72),
  ),
  boxShadow: [
    BoxShadow(
      color: theme.colorScheme.shadow.withValues(alpha: 0.06),
      blurRadius: 18,
      offset: const Offset(0, 9),
    ),
  ],
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
      curve: kOpenHandSwitchInCurve,
      decoration: BoxDecoration(
        color: value
            ? colorScheme.primaryContainer.withValues(alpha: .34)
            : colorScheme.surfaceContainerHighest.withValues(alpha: .42),
        borderRadius: kOpenHandBorderRadius16,
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
        shape: const RoundedRectangleBorder(
          borderRadius: kOpenHandBorderRadius16,
        ),
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
  const radius = kOpenHandBorderRadius16;
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
  bool _menuOpen = false;

  Future<void> _showMenu() async {
    if (_menuOpen || widget.options.isEmpty) return;
    setState(() => _menuOpen = true);
    final selected = await showAnimatedAnchoredMenu<Set<T>>(
      context: context,
      offset: const Offset(0, 8),
      builder: (_) => _MultiSelectDropdownMenu<T>(
        label: widget.label,
        options: widget.options,
        selected: widget.selected,
        emptyMeansAll: widget.emptyMeansAll,
        noneValue: widget.noneValue,
      ),
    );
    if (!mounted) return;
    setState(() => _menuOpen = false);
    if (selected != null) {
      widget.onChanged(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.options.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: kOpenHandBorderRadius12,
        onTap: _showMenu,
        child: InputDecorator(
          decoration:
              _gatewayInputDecoration(
                context,
                widget.emptyMeansAll
                    ? _gatewayEmptyMeansAllLabel(context, widget.label)
                    : widget.label,
              ).copyWith(
                suffixIcon: Icon(
                  _menuOpen
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
      ),
    );
  }

  String _summary(BuildContext context) {
    if (_isExplicitNone(widget.selected, widget.noneValue)) {
      return _messageGatewayAllUnavailableLabel(context);
    }
    if (widget.emptyMeansAll && widget.selected.isEmpty) {
      return _messageGatewayAllAvailableLabel(context);
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
  });

  final String label;
  final List<_SelectOption<T>> options;
  final Set<T> selected;
  final bool emptyMeansAll;
  final T? noneValue;

  @override
  State<_MultiSelectDropdownMenu<T>> createState() =>
      _MultiSelectDropdownMenuState<T>();
}

class _MultiSelectDropdownMenuState<T>
    extends State<_MultiSelectDropdownMenu<T>> {
  final TextEditingController _searchController = TextEditingController();
  late Set<T> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set<T>.from(widget.selected);
    _searchController.addListener(() => setState(() {}));
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
    _searchController.dispose();
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
    return Material(
      type: MaterialType.card,
      clipBehavior: Clip.antiAlias,
      elevation: 14,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.18),
      surfaceTintColor: colorScheme.surfaceTint,
      color: colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kOpenHandRadius24),
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
                      borderRadius: BorderRadius.circular(kOpenHandRadius13),
                    ),
                    child: Icon(
                      Icons.tune_rounded,
                      size: 18,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  kOpenHandHGap10,
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
                        kOpenHandGap2,
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
                  kOpenHandHGap8,
                  _GatewayRoundIconActionButton(
                    tooltip: _gatewaySelectAllTooltip(
                      context,
                      filtered: query.isNotEmpty,
                    ),
                    icon: Icons.done_all_rounded,
                    onPressed: filteredValues.isEmpty
                        ? null
                        : () => _selectValues(filteredValues),
                  ),
                  kOpenHandHGap8,
                  _GatewayRoundIconActionButton(
                    tooltip: _gatewayDeselectAllTooltip(
                      context,
                      filtered: query.isNotEmpty,
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
                decoration: _gatewaySelectionSearchDecoration(
                  context,
                  dense: true,
                  hintText: openHandSearchLabel(context),
                  showClear: _searchController.text.isNotEmpty,
                  onClear: _searchController.clear,
                ),
              ),
            ),
            Divider(height: 1, color: colorScheme.outlineVariant),
            Expanded(
              child: filtered.isEmpty
                  ? OpenHandInlineEmptyState(
                      message: openHandLocalizedText(
                        context,
                        zh: '没有匹配项',
                        zhHant: '沒有符合項目',
                        en: 'No matches',
                        fr: 'Aucune correspondance',
                        de: 'Keine Treffer',
                        ja: '一致する項目はありません',
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      itemCount: filtered.length,
                      separatorBuilder: (context, index) => kOpenHandGap4,
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
                          borderRadius: kOpenHandBorderRadius14,
                          child: CheckboxListTile(
                            dense: true,
                            shape: const RoundedRectangleBorder(
                              borderRadius: kOpenHandBorderRadius14,
                            ),
                            value: selected,
                            onChanged: (_) => _toggle(option.value),
                            controlAffinity: ListTileControlAffinity.leading,
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
                    label: Text(_messageGatewayDoneLabel(context)),
                    filled: true,
                  ),
                ],
              ),
            ),
          ],
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
    Navigator.of(context).pop(Set<T>.from(_selected));
  }

  String _selectionSummaryText(
    BuildContext context,
    int selectedCount,
    int totalCount,
    String scope,
  ) {
    if (_isExplicitNone(_selected, widget.noneValue)) {
      return '$scope · ${_messageGatewayAllUnavailableLabel(context)}';
    }
    if (widget.emptyMeansAll && _selected.isEmpty) {
      return '$scope · ${_messageGatewayAllAvailableLabel(context)}';
    }
    return '$scope · ${_gatewaySelectedCount(context, selectedCount, totalCount)}';
  }
}

bool _isExplicitNone<T>(Set<T> selected, T? noneValue) {
  return noneValue != null && selected.contains(noneValue);
}

/// 「全选 / 全不选」按钮的提示文案。[filtered] 为真时说明当前有搜索筛选，
/// 操作只作用于筛选结果，文案需要点明范围。
String _gatewaySelectAllTooltip(
  BuildContext context, {
  required bool filtered,
}) {
  return filtered
      ? openHandLocalizedText(
          context,
          zh: '当前筛选全选',
          zhHant: '目前篩選全選',
          en: 'Select filtered',
          fr: 'Sélectionner le filtre',
          de: 'Gefilterte auswählen',
          ja: '絞り込み結果を全選択',
        )
      : _messageGatewaySelectAllLabel(context);
}

String _gatewayDeselectAllTooltip(
  BuildContext context, {
  required bool filtered,
}) {
  return filtered
      ? openHandLocalizedText(
          context,
          zh: '当前筛选全不选',
          zhHant: '目前篩選全不選',
          en: 'Deselect filtered',
          fr: 'Désélectionner le filtre',
          de: 'Gefilterte abwählen',
          ja: '絞り込み結果を全解除',
        )
      : _messageGatewayDeselectAllLabel(context);
}

/// 选择弹窗搜索框的统一装饰。[hintText] 由调用方给出（「搜索」/「搜索模型」）。
InputDecoration _gatewaySelectionSearchDecoration(
  BuildContext context, {
  required String hintText,
  required bool showClear,
  required VoidCallback onClear,
  bool dense = false,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  final iconSize = dense ? 18.0 : null;
  return InputDecoration(
    isDense: dense,
    filled: true,
    fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.58),
    prefixIcon: Icon(Icons.search_rounded, size: iconSize),
    hintText: hintText,
    border: OutlineInputBorder(
      borderRadius: kOpenHandBorderRadius16,
      borderSide: dense
          ? BorderSide(color: colorScheme.outlineVariant)
          : const BorderSide(),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: kOpenHandBorderRadius16,
      borderSide: BorderSide(
        color: colorScheme.outlineVariant.withValues(alpha: 0.72),
      ),
    ),
    suffixIcon: !showClear
        ? null
        : IconButton(
            tooltip: openHandClearSearchLabel(context),
            onPressed: onClear,
            icon: Icon(Icons.clear_rounded, size: iconSize),
          ),
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
        borderRadius: kOpenHandBorderRadius12,
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
      maxWidth: kOpenHandDialogWidthStandard,
      maxHeight: kOpenHandDialogHeightStandard,
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
                    borderRadius: BorderRadius.circular(kOpenHandRadius17),
                  ),
                  child: Icon(
                    Icons.hub_outlined,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                kOpenHandHGap12,
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
                      kOpenHandGap3,
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
                kOpenHandHGap8,
                _GatewayRoundIconActionButton(
                  tooltip: _gatewaySelectAllTooltip(
                    context,
                    filtered: query.isNotEmpty,
                  ),
                  icon: Icons.done_all_rounded,
                  onPressed: visibleKeys.isEmpty
                      ? null
                      : () => _selectModelKeys(visibleKeys),
                ),
                kOpenHandHGap8,
                _GatewayRoundIconActionButton(
                  tooltip: _gatewayDeselectAllTooltip(
                    context,
                    filtered: query.isNotEmpty,
                  ),
                  icon: Icons.remove_done_rounded,
                  onPressed: visibleKeys.isEmpty
                      ? null
                      : () => _deselectModelKeys(visibleKeys),
                ),
                kOpenHandHGap8,
                IconButton(
                  tooltip: openHandCloseLabel(context),
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
              decoration: _gatewaySelectionSearchDecoration(
                context,
                hintText: openHandLocalizedText(
                  context,
                  zh: '搜索模型',
                  zhHant: '搜尋模型',
                  en: 'Search models',
                  fr: 'Rechercher des modèles',
                  de: 'Modelle suchen',
                  ja: 'モデルを検索',
                ),
                showClear: _searchController.text.isNotEmpty,
                onClear: _searchController.clear,
              ),
            ),
          ),
          Divider(height: 1, color: colorScheme.outlineVariant),
          Expanded(
            child: filtered.isEmpty
                ? OpenHandInlineEmptyState(
                    message: openHandLocalizedText(
                      context,
                      zh: '没有匹配的模型',
                      zhHant: '沒有符合的模型',
                      en: 'No matching models',
                      fr: 'Aucun modèle correspondant',
                      de: 'Keine passenden Modelle',
                      ja: '一致するモデルはありません',
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
                              kOpenHandHGap10,
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
                              kOpenHandHGap8,
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
                        shape: const RoundedRectangleBorder(
                          borderRadius: kOpenHandBorderRadius14,
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
                kOpenHandHGap12,
                OpenHandDialogActionButton.primary(
                  label: _messageGatewayDoneLabel(context),
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
      return _messageGatewayAllUnavailableLabel(context);
    }
    if (widget.emptyMeansAll && _selected.isEmpty) {
      return _messageGatewayAllAvailableLabel(context);
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
      curve: removing ? kOpenHandSwitchOutCurve : kOpenHandEntranceCurve,
      reverseCurve: kOpenHandSwitchOutCurve,
    );
    return SizeTransition(
      sizeFactor: animation,
      alignment: AlignmentDirectional.topStart,
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
      WebGatewayLogLevel.info => _webGatewayLightGray,
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
        style: const TextStyle(
          fontFamily: kOpenHandMonospaceFontFamily,
          fontSize: 12,
          height: 1.45,
        ),
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
        borderRadius: kOpenHandBorderRadius8,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          const Icon(Icons.cleaning_services_outlined, size: 18),
          kOpenHandHGap10,
          Expanded(
            child: Text(
              '${_cleanupTargetLabel(context, entry.target)} · ${entry.expiredOnly ? openHandLocalizedText(context, zh: '保留策略', zhHant: '保留策略', en: 'Retention policy', fr: 'Politique de rétention', de: 'Aufbewahrungsregel', ja: '保持ポリシー') : openHandLocalizedText(context, zh: '手动清理', zhHant: '手動清理', en: 'Manual cleanup', fr: 'Nettoyage manuel', de: 'Manuelle Bereinigung', ja: '手動クリーンアップ')} · ${formatYearMonthDayHmsLocal(entry.timestamp)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          kOpenHandHGap10,
          Text(
            openHandLocalizedText(
              context,
              zh: '${entry.deletedFiles} 文件 / ${formatByteSize(entry.bytesFreed)}',
              zhHant:
                  '${entry.deletedFiles} 個檔案 / ${formatByteSize(entry.bytesFreed)}',
              en: '${entry.deletedFiles} files / ${formatByteSize(entry.bytesFreed)}',
              fr: '${entry.deletedFiles} fichiers / ${formatByteSize(entry.bytesFreed)}',
              de: '${entry.deletedFiles} Dateien / ${formatByteSize(entry.bytesFreed)}',
              ja: '${entry.deletedFiles} ファイル / ${formatByteSize(entry.bytesFreed)}',
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
          color: colorScheme.surfaceContainerHigh.withValues(alpha: .60),
          borderRadius: kOpenHandBorderRadius8,
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: .72),
          ),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: .05),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
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
            kOpenHandGap8,
            SizedBox(
              height: 112,
              child: TweenAnimationBuilder<double>(
                key: ValueKey<int>(_animationVersion),
                tween: Tween<double>(begin: 0, end: 1),
                duration: openHandMotionDurationMs(context, 420),
                curve: kOpenHandEntranceCurve,
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

const double _trendLineStrokeWidth = 2.6;
const double _trendPlotHorizontalPadding = 4;
const double _trendPlotVerticalPadding = 6;

Rect _webGatewayTrendPlotRect(Rect chart) {
  final horizontalInset = math.min(
    _trendPlotHorizontalPadding,
    math.max(0, (chart.width - 1) / 2),
  );
  final verticalInset = math.min(
    _trendPlotVerticalPadding,
    math.max(0, (chart.height - 1) / 2),
  );
  return Rect.fromLTRB(
    chart.left + horizontalInset,
    chart.top + verticalInset,
    chart.right - horizontalInset,
    chart.bottom - verticalInset,
  );
}

class _TrendLinePainter extends CustomPainter {
  const _TrendLinePainter({
    required this.values,
    required this.minValue,
    required this.maxValue,
    required this.lineColor,
    required this.gridColor,
    required this.labelColor,
    required this.valueFormatter,
  });

  final List<double> values;
  final double minValue;
  final double maxValue;
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
    final plot = _webGatewayTrendPlotRect(chart);
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
      final x = plot.left + plot.width * i / (values.length - 1);
      final normalized = finiteUnitInterval((values[i] - minValue) / span);
      final y = plot.bottom - plot.height * normalized;
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
    canvas.save();
    canvas.clipRect(chart);
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
        ..strokeWidth = _trendLineStrokeWidth
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
        oldDelegate.minValue != minValue ||
        oldDelegate.maxValue != maxValue ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.labelColor != labelColor;
  }
}

String _messageTypeLabel(BuildContext context, WebGatewayMessageType type) {
  return switch (type) {
    WebGatewayMessageType.text => openHandPlainTextLabel(context),
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
    WebGatewayRuntimeState.stopped => openHandStoppedLabel(context),
    WebGatewayRuntimeState.starting => openHandStartingLabel(context),
    WebGatewayRuntimeState.running => openHandRunningLabel(context),
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
  final minMegabytes = math.max(1, (minBytes / kBytesPerMiB).ceil());
  final maxMegabytes = math.max(
    minMegabytes,
    (maxBytes / kBytesPerMiB).floor(),
  );
  final fallbackMegabytes = (fallbackBytes / kBytesPerMiB)
      .round()
      .clamp(minMegabytes, maxMegabytes)
      .toInt();
  return _boundedInt(
        value,
        fallback: fallbackMegabytes,
        min: minMegabytes,
        max: maxMegabytes,
      ) *
      kBytesPerMiB;
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
    'logs' => _messageGatewayLogsLabel(context),
    'uploads' => _messageGatewayUploadCacheLabel(context),
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

String _messageGatewayAllAvailableLabel(BuildContext context) {
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

String _messageGatewayAllUnavailableLabel(BuildContext context) {
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

String _messageGatewayBlockedLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '拦截',
    zhHant: '攔截',
    en: 'Blocked',
    fr: 'Bloqué',
    de: 'Blockiert',
    ja: 'ブロック',
  );
}

String _messageGatewayClearLogsLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '清空日志',
    zhHant: '清空日誌',
    en: 'Clear logs',
    fr: 'Effacer les journaux',
    de: 'Protokolle leeren',
    ja: 'ログをクリア',
  );
}

String _messageGatewayClientUaMixLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '客户端 UA 分布',
    zhHant: '用戶端 UA 分布',
    en: 'Client UA mix',
    fr: 'Répartition des UA clients',
    de: 'Client-UA-Verteilung',
    ja: 'クライアント UA 分布',
  );
}

String _messageGatewayDeselectAllLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '全不选',
    zhHant: '全不選',
    en: 'Deselect all',
    fr: 'Tout désélectionner',
    de: 'Alle abwählen',
    ja: 'すべて解除',
  );
}

String _messageGatewayDoneLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '完成',
    zhHant: '完成',
    en: 'Done',
    fr: 'Terminé',
    de: 'Fertig',
    ja: '完了',
  );
}

String _messageGatewayFailedLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '失败',
    zhHant: '失敗',
    en: 'Failed',
    fr: 'Échec',
    de: 'Fehler',
    ja: '失敗',
  );
}

String _messageGatewayLatencyCurveLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '耗时曲线',
    zhHant: '耗時曲線',
    en: 'Latency curve',
    fr: 'Courbe de latence',
    de: 'Latenzkurve',
    ja: 'レイテンシ曲線',
  );
}

String _messageGatewayLogDiskLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '日志磁盘',
    zhHant: '日誌磁碟',
    en: 'Log disk',
    fr: 'Disque des journaux',
    de: 'Protokollspeicher',
    ja: 'ログディスク',
  );
}

String _messageGatewayLogsLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '日志',
    zhHant: '日誌',
    en: 'Logs',
    fr: 'Journaux',
    de: 'Protokolle',
    ja: 'ログ',
  );
}

String _messageGatewayNoLatencySamplesLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '暂无耗时样本',
    zhHant: '暫無耗時樣本',
    en: 'No latency samples',
    fr: 'Aucun échantillon de latence',
    de: 'Keine Latenzstichproben',
    ja: 'レイテンシサンプルなし',
  );
}

String _messageGatewayOffLabel(BuildContext context) {
  return openHandOffLabel(context);
}

String _messageGatewayOnLabel(BuildContext context) {
  return openHandOnLabel(context);
}

String _messageGatewayP95LatencyLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: 'P95 延迟',
    zhHant: 'P95 延遲',
    en: 'P95 latency',
    fr: 'Latence P95',
    de: 'P95-Latenz',
    ja: 'P95レイテンシ',
  );
}

String _messageGatewayPortConnectivityTestLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '端口连通性测试',
    zhHant: '連接埠連通性測試',
    en: 'Port connectivity test',
    fr: 'Test de connectivité du port',
    de: 'Port-Konnektivitätstest',
    ja: 'ポート接続テスト',
  );
}

String _messageGatewayProtocolMixLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '协议分布',
    zhHant: '協議分布',
    en: 'Protocol mix',
    fr: 'Répartition des protocoles',
    de: 'Protokollverteilung',
    ja: 'プロトコル分布',
  );
}

String _messageGatewayRequestMixLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '请求分布',
    zhHant: '請求分布',
    en: 'Request mix',
    fr: 'Répartition des requêtes',
    de: 'Anfrageverteilung',
    ja: 'リクエスト分布',
  );
}

String _messageGatewayRequestTrendLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '请求趋势',
    zhHant: '請求趨勢',
    en: 'Request trend',
    fr: 'Tendance des requêtes',
    de: 'Anfragetrend',
    ja: 'リクエスト傾向',
  );
}

String _messageGatewaySelectAllLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '全选',
    zhHant: '全選',
    en: 'Select all',
    fr: 'Tout sélectionner',
    de: 'Alle auswählen',
    ja: 'すべて選択',
  );
}

String _messageGatewaySourceEndpointsLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '来源端点（IP:端口）',
    en: 'Source endpoints',
  );
}

String _messageGatewayStatusMixLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '状态分布',
    zhHant: '狀態分布',
    en: 'Status mix',
    fr: 'Répartition des statuts',
    de: 'Statusverteilung',
    ja: 'ステータス分布',
  );
}

String _messageGatewaySuccessLabel(BuildContext context) {
  return openHandSuccessLabel(context);
}

String _messageGatewayThreadsLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '线程数',
    zhHant: '執行緒數',
    en: 'Threads',
    fr: 'Threads',
    de: 'Threads',
    ja: 'スレッド数',
  );
}

String _messageGatewayUploadCacheLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '上传缓存',
    zhHant: '上傳快取',
    en: 'Upload cache',
    fr: 'Cache d’envoi',
    de: 'Upload-Cache',
    ja: 'アップロードキャッシュ',
  );
}

String _messageGatewayWaitingForTrafficLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '等待请求样本',
    zhHant: '等待請求樣本',
    en: 'Waiting for traffic',
    fr: 'En attente de trafic',
    de: 'Warten auf Datenverkehr',
    ja: 'トラフィック待機中',
  );
}

class _DingTalkGatewayCard extends StatelessWidget {
  const _DingTalkGatewayCard({required this.controller});

  // SVG 在 64 身份区内居中，避免被拉伸到满尺寸。
  static const double _iconSize = 30;

  final MessageGatewayController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller.dingtalk,
      builder: (context, _) {
        final ding = controller.dingtalk;
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        final statusColor = ding.isAuthenticating
            ? cs.primary
            : ding.isLoggingOut
            ? OpenHandStatusColors.warning
            : ding.isPolling
            ? OpenHandStatusColors.success
            : cs.outline;
        final statusPills = <Widget>[
          OpenHandStatusPill(
            icon: ding.isLoggingOut
                ? Icons.logout_rounded
                : ding.isAuthorized
                ? Icons.verified_user_outlined
                : Icons.gpp_bad_outlined,
            label: ding.isLoggingOut
                ? '正在取消授权'
                : ding.isAuthorized
                ? '已授权${ding.authStatus.identity.label.isEmpty ? '' : ' · ${ding.authStatus.identity.label}'}'
                : '未授权',
            color: ding.isLoggingOut
                ? OpenHandStatusColors.warning
                : ding.isAuthorized
                ? OpenHandStatusColors.success
                : OpenHandStatusColors.warning,
          ),
          OpenHandStatusPill(
            icon: ding.isPolling
                ? Icons.sensors_rounded
                : Icons.sensors_off_rounded,
            label: ding.isPolling
                ? ding.isRealtimeListening
                      ? '实时监听中'
                      : ding.isPollingFallback
                      ? '轮询兜底 · ${ding.settings.pollIntervalSeconds}s'
                      : '正在连接实时监听'
                : '实时监听已停止',
            color: ding.isPolling
                ? (ding.isRealtimeListening
                      ? OpenHandStatusColors.success
                      : cs.secondary)
                : cs.outline,
          ),
          if (ding.warningMessage != null)
            OpenHandStatusPill(
              icon: Icons.info_outline_rounded,
              label: ding.warningMessage!,
              color: OpenHandStatusColors.warning,
            ),
        ];
        final factChips = <Widget>[
          _GatewayFactChip(
            icon: Icons.forum_outlined,
            label: '会话 ${ding.conversations.length}',
            color: cs.primary,
          ),
          if (ding.unreadCount > 0)
            _GatewayFactChip(
              icon: Icons.mark_email_unread_outlined,
              label: '未读 ${ding.unreadCount}',
              color: OpenHandStatusColors.warning,
            ),
          _GatewayFactChip(
            icon: ding.isInstalled
                ? Icons.extension_rounded
                : Icons.extension_off_outlined,
            label: ding.isInstalled ? 'dws 已就绪' : '未检测到 dws',
            color: ding.isInstalled ? cs.tertiary : cs.onSurfaceVariant,
          ),
        ];
        return Card(
          key: const ValueKey<String>('dingtalk-message-platform-card'),
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_kGatewayCardRadius),
            side: BorderSide(color: cs.outlineVariant),
          ),
          child: Padding(
            padding: _kGatewayCardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact =
                        constraints.maxWidth < _kGatewayHeaderBreakpoint;
                    final actions = Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: [
                        _DingTalkActionButton(
                          tooltip: ding.isPolling
                              ? ding.isRealtimeListening
                                    ? '停止实时消息监听'
                                    : '停止轮询兜底'
                              : '启动实时消息监听',
                          icon: ding.isPolling
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          onPressed: ding.isAuthorized && !ding.isLoggingOut
                              ? () => ding.isPolling
                                    ? ding.stopPolling()
                                    : ding.startPolling()
                              : null,
                          filled: ding.isPolling,
                        ),
                        _DingTalkActionButton(
                          tooltip: ding.isLoggingOut
                              ? '正在取消钉钉授权'
                              : ding.isAuthenticating
                              ? '取消设备流授权'
                              : ding.isAuthorized
                              ? '取消钉钉授权'
                              : '登录授权',
                          icon: ding.isAuthenticating
                              ? Icons.close_rounded
                              : ding.isAuthorized
                              ? Icons.person_remove_rounded
                              : Icons.verified_user_rounded,
                          onPressed: ding.isLoggingOut
                              ? null
                              : ding.isAuthenticating
                              ? () => ding.cancelAuthorization()
                              : () => _toggleDingTalkAuth(context, ding),
                          loading: ding.isLoggingOut,
                        ),
                        _DingTalkActionButton(
                          tooltip: '消息列表',
                          icon: Icons.inbox_rounded,
                          onPressed: ding.isServiceEnabled
                              ? () => _showDingTalkMessages(context, ding)
                              : null,
                        ),
                        _DingTalkActionButton(
                          tooltip: openHandLocalizedText(
                            context,
                            zh: '查看运行日志',
                            zhHant: '查看運行日誌',
                            en: 'View runtime logs',
                            fr: 'Voir les journaux d’exécution',
                            de: 'Laufzeitprotokolle anzeigen',
                            ja: '実行ログを表示',
                          ),
                          icon: Icons.article_outlined,
                          onPressed: () =>
                              _showDingTalkRuntimeLogs(context, ding),
                        ),
                        _DingTalkActionButton(
                          tooltip: '网关设置',
                          icon: Icons.tune_rounded,
                          onPressed: () => _showDingTalkSettings(context, ding),
                        ),
                      ],
                    );
                    final identity = _GatewayPlatformIdentity(
                      title: openHandLocalizedText(
                        context,
                        zh: '钉钉消息平台',
                        zhHant: '釘釘訊息平台',
                        en: 'DingTalk Message Platform',
                        fr: 'Plateforme de messages DingTalk',
                        de: 'DingTalk-Nachrichtenplattform',
                        ja: 'DingTalk メッセージプラットフォーム',
                      ),
                      description: openHandLocalizedText(
                        context,
                        zh: '钉钉消息接入与 OpenHand AI 会话',
                        zhHant: '釘釘訊息接入與 OpenHand AI 會話',
                        en: 'Connect DingTalk messages to OpenHand AI sessions',
                        fr: 'Connecter DingTalk aux sessions OpenHand AI',
                        de: 'DingTalk-Nachrichten mit OpenHand-AI-Sitzungen verbinden',
                        ja: 'DingTalk メッセージを OpenHand AI セッションに接続',
                      ),
                      statusColor: statusColor,
                      iconChild: SvgPicture.asset(
                        'assets/icons/plugins/dingtalk-workspace-cli.svg',
                        width: _iconSize,
                        height: _iconSize,
                      ),
                    );
                    if (compact) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          identity,
                          kOpenHandGap16,
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: actions,
                          ),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: identity),
                        kOpenHandHGap16,
                        actions,
                      ],
                    );
                  },
                ),
                kOpenHandGap16,
                Wrap(spacing: 10, runSpacing: 10, children: statusPills),
                kOpenHandGap12,
                Wrap(spacing: 8, runSpacing: 8, children: factChips),
                if (ding.errorMessage != null) ...[
                  kOpenHandGap12,
                  Text(
                    ding.errorMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (ding.isAuthenticating && ding.deviceUrl != null) ...[
                  kOpenHandGap12,
                  SelectableText(
                    ding.deviceCode.isEmpty
                        ? '已打开钉钉授权页，请在浏览器完成授权。'
                        : '设备码：${ding.deviceCode}（请在浏览器完成授权）',
                    style: theme.textTheme.bodySmall,
                  ),
                  SelectableText(
                    ding.deviceUrl!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.primary,
                    ),
                  ),
                ],
                if (!ding.isInstalled) ...[
                  kOpenHandGap12,
                  Text(
                    '未检测到 dws，请先在插件板块安装 DingTalk Workspace CLI。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DingTalkActionButton extends StatelessWidget {
  const _DingTalkActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.filled = false,
    this.loading = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool filled;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    final resolvedTooltip = disabled && !loading ? '$tooltip（当前不可用）' : tooltip;
    final child = OpenHandBusyStatusIcon(busy: loading, icon: icon, size: 22);
    final style = _dingtalkDisabledActionStyle(
      context,
      base:
          (filled
                  ? OpenHandStatusColors.runningStopButtonStyle()
                  : IconButton.styleFrom())
              .copyWith(
                shape: const WidgetStatePropertyAll<OutlinedBorder>(
                  CircleBorder(),
                ),
              ),
    );
    return Tooltip(
      message: resolvedTooltip,
      child: IconButton.filledTonal(
        tooltip: resolvedTooltip,
        onPressed: onPressed,
        icon: child,
        style: style,
      ),
    );
  }
}

ButtonStyle _dingtalkDisabledActionStyle(
  BuildContext context, {
  ButtonStyle? base,
}) {
  final colors = Theme.of(context).colorScheme;
  return (base ?? const ButtonStyle()).copyWith(
    backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.disabled)) {
        return colors.surfaceContainerHighest.withValues(alpha: 0.2);
      }
      return base?.backgroundColor?.resolve(states);
    }),
    foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.disabled)) {
        return colors.onSurface.withValues(alpha: 0.3);
      }
      return base?.foregroundColor?.resolve(states);
    }),
  );
}

Future<void> _toggleDingTalkAuth(
  BuildContext context,
  DingTalkMessageGatewayController controller,
) async {
  if (controller.isLoggingOut) return;
  if (controller.isAuthorized) {
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: '取消钉钉授权',
      message: '将退出当前钉钉账号并停止消息监听。',
      confirmLabel: '确认取消授权',
      destructive: true,
      icon: const Icon(Icons.logout_rounded),
    );
    if (confirmed && context.mounted) await controller.logout();
    return;
  }
  await controller.authorize((url) async {
    final executable = Platform.isMacOS
        ? 'open'
        : Platform.isWindows
        ? 'rundll32.exe'
        : 'xdg-open';
    final args = Platform.isWindows
        ? <String>['url.dll,FileProtocolHandler', url]
        : <String>[url];
    final opened = await runDetachedSystemOpen(
      executable,
      args,
      tag: 'dingtalk.auth.browser',
    );
    if (!opened && context.mounted) {
      showOpenHandInfoSnack(context, '无法打开默认浏览器，请复制授权地址完成登录。');
    }
  });
}

const double _kDingTalkMessagesDialogMaxWidth = 1600;
const double _kDingTalkMessagesDialogMaxHeight = 1040;
const double _kDingTalkMessagesDialogWidthFraction = 0.86;
const double _kDingTalkMessagesDialogHeightFraction = 0.88;
const double _kDingTalkMessagesDialogHorizontalMargin = 40;
const double _kDingTalkMessagesDialogVerticalMargin = 56;

Future<void> _showDingTalkMessages(
  BuildContext context,
  DingTalkMessageGatewayController controller,
) async {
  if (!controller.isServiceEnabled) return;
  await showAnimatedDialog<void>(
    context: context,
    builder: (dialogContext) => buildOpenHandResponsiveDialogShell(
      context: dialogContext,
      maxWidth: _kDingTalkMessagesDialogMaxWidth,
      maxHeight: _kDingTalkMessagesDialogMaxHeight,
      maxWidthFraction: _kDingTalkMessagesDialogWidthFraction,
      maxHeightFraction: _kDingTalkMessagesDialogHeightFraction,
      horizontalMargin: _kDingTalkMessagesDialogHorizontalMargin,
      verticalMargin: _kDingTalkMessagesDialogVerticalMargin,
      expandToMax: true,
      child: _DingTalkMessagesDialog(controller: controller),
    ),
  );
}

Future<void> _showDingTalkSettings(
  BuildContext context,
  DingTalkMessageGatewayController controller,
) async {
  await showAnimatedDialog<void>(
    context: context,
    builder: (_) => buildOpenHandDialog(
      maxWidth: kOpenHandDialogWidthStandard,
      child: _DingTalkSettingsDialog(controller: controller),
    ),
  );
}

Future<void> _showDingTalkRuntimeLogs(
  BuildContext context,
  DingTalkMessageGatewayController controller,
) {
  return showOpenHandRuntimeLogDialog(
    context: context,
    title: openHandLocalizedText(
      context,
      zh: '钉钉消息平台运行日志',
      zhHant: '釘釘消息平台運行日誌',
      en: 'DingTalk message platform runtime logs',
      fr: 'Journaux d’exécution de la plateforme DingTalk',
      de: 'Laufzeitprotokolle der DingTalk-Nachrichtenplattform',
      ja: 'DingTalkメッセージプラットフォームの実行ログ',
    ),
    listenable: Listenable.merge(<Listenable>[
      controller,
      controller.runtimeLogListenable,
    ]),
    logs: () {
      final logs = controller.runtimeLogs;
      if (!controller.isInstalled) {
        return <String>[
          '[ERROR] 未检测到 dws，钉钉消息平台尚未安装底层组件。',
          '[ERROR] 请在插件板块安装 DingTalk Workspace CLI 后重试。',
          ...logs,
        ];
      }
      if (!controller.isAuthorized) {
        return <String>[
          '[ERROR] 当前钉钉账号尚未完成授权，消息监听无法启动。',
          '[WARN] 完成设备流授权后，重新启动消息监听即可继续。',
          ...logs,
        ];
      }
      if (!controller.isPolling) {
        return <String>[
          '[ERROR] 消息监听当前未运行。',
          '[WARN] 启动消息监听后将持续记录 dws 执行日志。',
          ...logs,
        ];
      }
      if (logs.isNotEmpty) return logs;
      return const <String>['[INFO] 当前暂无 dws 输出，等待下一次事件或命令。'];
    },
    revision: () => controller.runtimeLogRevision,
    clearLogs: controller.clearRuntimeLogs,
    fileNamePrefix: 'openhand-dingtalk-runtime',
  );
}

class _DingTalkMessageTranslation {
  const _DingTalkMessageTranslation({
    required this.sourceText,
    required this.settingsFingerprint,
    required this.translatedText,
  });

  final String sourceText;
  final String settingsFingerprint;
  final String translatedText;
}

class _DingTalkTranslationManager {
  final AiTranslationService _service = AiTranslationService();
  final Map<String, _DingTalkMessageTranslation> _translations =
      <String, _DingTalkMessageTranslation>{};
  final Set<String> _visibleMessageIds = <String>{};
  final Set<String> _loadingMessageIds = <String>{};
  int _generation = 0;

  bool isLoading(String messageId) => _loadingMessageIds.contains(messageId);

  _DingTalkMessageTranslation? visibleTranslation({
    required String messageId,
    required String sourceText,
    required String settingsFingerprint,
  }) {
    final cached = _translations[messageId];
    if (!_visibleMessageIds.contains(messageId) ||
        cached?.sourceText != sourceText ||
        cached?.settingsFingerprint != settingsFingerprint) {
      return null;
    }
    return cached;
  }

  Future<String?> toggle({
    required String messageId,
    required String sourceText,
    required String settingsFingerprint,
    required AiTranslationSettings settings,
    required List<AiModelConfig> availableModels,
    required AiModelConfig? fallbackModel,
    required bool Function() isMounted,
    required void Function(VoidCallback mutation) update,
    required String logAction,
  }) async {
    if (_visibleMessageIds.contains(messageId)) {
      update(() => _visibleMessageIds.remove(messageId));
      return null;
    }
    final cached = _translations[messageId];
    if (cached != null &&
        cached.sourceText == sourceText &&
        cached.settingsFingerprint == settingsFingerprint) {
      update(() => _visibleMessageIds.add(messageId));
      return null;
    }
    if (_loadingMessageIds.contains(messageId)) return null;
    final generation = _generation;
    update(() => _loadingMessageIds.add(messageId));
    try {
      final result = await _service.translate(
        text: sourceText,
        settings: settings,
        availableModels: availableModels,
        fallbackModel: fallbackModel,
      );
      if (!isMounted() || generation != _generation) return null;
      update(() {
        _loadingMessageIds.remove(messageId);
        _translations.remove(messageId);
        _translations[messageId] = _DingTalkMessageTranslation(
          sourceText: sourceText,
          settingsFingerprint: settingsFingerprint,
          translatedText: result.text,
        );
        while (_translations.length > _dingtalkTranslationCacheMaxEntries) {
          final removed = _translations.keys.first;
          _translations.remove(removed);
          _visibleMessageIds.remove(removed);
        }
        _visibleMessageIds.add(messageId);
      });
      return null;
    } catch (error, stack) {
      if (generation != _generation) return null;
      silentLog('dingtalk_gateway', logAction, error, stack);
      return messageGatewayFailureMessage(error, fallback: '请检查文本翻译设置。');
    } finally {
      if (isMounted() &&
          generation == _generation &&
          _loadingMessageIds.contains(messageId)) {
        update(() => _loadingMessageIds.remove(messageId));
      }
    }
  }

  void clear() {
    _generation++;
    _translations.clear();
    _visibleMessageIds.clear();
    _loadingMessageIds.clear();
  }

  void dispose() {
    clear();
    _service.dispose();
  }
}

class _DingTalkMessagesDialog extends StatefulWidget {
  const _DingTalkMessagesDialog({required this.controller});
  final DingTalkMessageGatewayController controller;

  @override
  State<_DingTalkMessagesDialog> createState() =>
      _DingTalkMessagesDialogState();
}

class _DingTalkServiceLockOverlay extends StatelessWidget {
  const _DingTalkServiceLockOverlay({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.surface.withValues(alpha: 0.86),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.pause_circle_outline_rounded,
              size: 54,
              color: colors.primary,
            ),
            kOpenHandGap12,
            Text(
              '钉钉消息服务未启用',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            kOpenHandGap6,
            Text(
              '启动消息监听后，消息收发与 AI 响应将恢复。',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            kOpenHandGap16,
            FilledButton.tonalIcon(
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded),
              label: const Text('关闭窗口'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DingTalkMessagesDialogState extends State<_DingTalkMessagesDialog> {
  static const Duration _maxVoiceDuration = Duration(minutes: 2);
  static const double _composerIconButtonSize = 48;
  static const Duration _voiceVisualInterval = kOpenHandMotion160;
  static const Duration _voiceOperationTimeout = Duration(seconds: 10);
  static const Duration _voiceCleanupTimeout = Duration(seconds: 5);
  static const int _voiceWaveformSampleCount = 40;
  static const double _messageCacheExtent = 120;
  static const double _messagesScrollbarThickness = 6;
  static const Radius _messagesScrollbarRadius = kOpenHandPillRadius;
  static const double _latestMessageBottomThreshold = 2;
  static const Duration _clipboardAttachmentReadTimeout = Duration(seconds: 2);
  static const Duration _clipboardImageReadTimeout = Duration(seconds: 3);
  static const Duration _clipboardImageWriteTimeout = Duration(seconds: 10);
  static const int _maxPastedAttachmentCacheFiles = 32;
  static const Duration _pastedAttachmentCacheOperationTimeout = Duration(
    seconds: 3,
  );
  static const int _maxAutoMediaLoadAttempts = 512;
  static const int _quotedMessageHistoryPageLimit = 6;
  static const int _quotedMessageMaterializeAttempts = 4;
  static const Duration _quotedMessageHighlightDuration = Duration(
    milliseconds: 1200,
  );
  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final ScrollController _messagesScrollController = ScrollController();
  final AutoFollowProgrammaticScrollWindow _messagesProgrammaticScroll =
      AutoFollowProgrammaticScrollWindow();
  final Stopwatch _messagesScrollActivityStopwatch = Stopwatch()..start();
  final AiTtsPlaybackService _ttsPlaybackService = AiTtsPlaybackService();
  final _DingTalkTranslationManager _translationManager =
      _DingTalkTranslationManager();
  final LatestTaskQueue _pastedAttachmentPruneQueue = LatestTaskQueue();
  final Set<String> _autoMediaLoadAttemptedMessageIds = <String>{};
  final Set<String> _autoMediaLoadPendingMessageIds = <String>{};
  final _DingTalkMessageAnchorRegistry _messageAnchorRegistry =
      _DingTalkMessageAnchorRegistry();
  bool _followScheduled = false;
  String? _followConversationId;
  bool _followJumpToBottom = false;
  int _followRequestVersion = 0;
  String? _selectedId;
  String? _expandedActionMessageId;
  String? _editingConversationId;
  String? _editingMessageId;
  bool _editSubmitting = false;
  bool _autoFollow = true;
  bool _showJumpToLatest = false;
  bool _messagesUserScrollActive = false;
  bool _autoFollowPausedByUserScroll = false;
  String? _quotedJumpTargetMessageId;
  String? _quotedReturnMessageId;
  String? _highlightedMessageId;
  int _messageNavigationVersion = 0;
  Timer? _quotedMessageHighlightTimer;
  bool _closing = false;
  AudioRecorder? _voiceRecorder;
  String? _voicePath;
  String? _voiceConversationId;
  bool _recordingVoice = false;
  bool _voiceRecorderStarted = false;
  bool _voicePaused = false;
  bool _voiceControlBusy = false;
  Duration _voiceElapsed = Duration.zero;
  DateTime? _voiceSegmentStartedAt;
  Duration? _lastMessagesPointerSignalAt;
  Timer? _voiceVisualTimer;
  StreamSubscription<Amplitude>? _voiceAmplitudeSubscription;
  final List<double> _voiceLevels = List<double>.filled(
    _voiceWaveformSampleCount,
    0.08,
    growable: true,
  );
  final ValueNotifier<_DingTalkVoiceVisualState> _voiceVisual =
      ValueNotifier<_DingTalkVoiceVisualState>(
        _DingTalkVoiceVisualState.initial,
      );
  List<_DingTalkPendingAttachment> _pendingAttachments =
      const <_DingTalkPendingAttachment>[];
  bool _attachmentBusy = false;

  @override
  void initState() {
    super.initState();
    _inputFocusNode.onKeyEvent = _handleInputKeyEvent;
    _input.addListener(_handleInputChanged);
    _messagesScrollController.addListener(_handleMessagesScrollChanged);
    _ttsPlaybackService.state.addListener(_handleTtsStateChanged);
    widget.controller.markAllRead();
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    _input.removeListener(_handleInputChanged);
    _ttsPlaybackService.state.removeListener(_handleTtsStateChanged);
    _voiceVisualTimer?.cancel();
    _quotedMessageHighlightTimer?.cancel();
    _messageAnchorRegistry.clear();
    _pastedAttachmentPruneQueue.discardPending();
    unawaited(_cancelVoiceAmplitudeSubscription());
    final recorder = _voiceRecorder;
    _voiceRecorder = null;
    _voiceRecorderStarted = false;
    if (recorder != null) {
      unawaited(_cancelAndDisposeRecorder(recorder));
    }
    _input.dispose();
    _inputFocusNode.dispose();
    _messagesScrollController.removeListener(_handleMessagesScrollChanged);
    _messagesProgrammaticScroll.cancel();
    _messagesScrollController.dispose();
    _voiceVisual.dispose();
    unawaited(_ttsPlaybackService.dispose());
    _translationManager.dispose();
    super.dispose();
  }

  void _handleTtsStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final ttsSettings = context.select<SettingsController, AiTtsSettings>(
      (settings) => settings.aiTtsSettings,
    );
    final translationSettings = context
        .select<SettingsController, AiTranslationSettings>(
          (settings) => settings.aiTranslationSettings,
        );
    final telemetryDebugEnabled = context.select<SettingsController, bool>(
      (settings) => settings.telemetryDebugEnabled,
    );
    final chipAnimationSettings = context
        .select<SettingsController, DialogAnimationSettings>(
          (settings) => settings.chipAnimationSettings,
        );
    final ttsSnapshot = _ttsPlaybackService.state.value;
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final serviceEnabled = widget.controller.isServiceEnabled;
        final conversations = widget.controller.conversations;
        final conversationIndexById = <String, int>{
          for (var index = 0; index < conversations.length; index++)
            conversations[index].id: index,
        };
        // 初次打开只展示空状态，必须由用户明确点击会话后再进入消息内容。
        final selected = conversations
            .where((item) => item.id == _selectedId)
            .firstOrNull;
        // Sliver delegate 在下一次父级 rebuild 前仍可能因滚动/Ticker 再次取 child；
        // 固定本次 build 的消息快照和 key/index 拓扑，禁止与可变列表交叉使用。
        final selectedMessages = selected == null
            ? const <DingTalkGatewayMessage>[]
            : List<DingTalkGatewayMessage>.unmodifiable(selected.messages);
        final messageTopology = selected == null
            ? null
            : DingTalkMessageRenderTopology(selectedMessages);
        final selectedQueuedResponses = selected == null
            ? const <DingTalkQueuedResponse>[]
            : widget.controller.queuedResponses(selected.id);
        final messageActionFallbackModel = selected == null
            ? null
            : widget.controller.messageActionFallbackModel(selected);
        final selectedHasOlderMessages =
            selected != null &&
            widget.controller.hasOlderConversationMessages(selected.id);
        final selectedLoadingOlderMessages =
            selected != null &&
            widget.controller.isLoadingOlderConversationMessages(selected.id);
        final selectedRefreshing =
            selected != null &&
            widget.controller.isRefreshingConversationMessages(selected.id);
        return SizedBox.expand(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                child: Row(
                  children: [
                    const Icon(Icons.forum_rounded),
                    kOpenHandHGap10,
                    Text('钉钉消息', style: Theme.of(context).textTheme.titleLarge),
                    const Spacer(),
                    if (selected != null)
                      AnimatedSwitcher(
                        duration: openHandMotionDuration(
                          context,
                          kOpenHandMotion220,
                        ),
                        switchInCurve: kOpenHandEntranceCurve,
                        switchOutCurve: kOpenHandSwitchOutCurve,
                        transitionBuilder: (child, animation) =>
                            ScaleTransition(
                              scale: animation,
                              child: FadeTransition(
                                opacity: animation,
                                child: child,
                              ),
                            ),
                        child: _showJumpToLatest
                            ? IconButton.filled(
                                key: const ValueKey<String>(
                                  'dingtalk-jump-to-latest',
                                ),
                                tooltip: '一键滚动至最新消息底部',
                                onPressed: _jumpToLatestMessages,
                                icon: const Icon(
                                  Icons.keyboard_double_arrow_down_rounded,
                                ),
                              )
                            : const SizedBox(
                                key: ValueKey<String>(
                                  'dingtalk-jump-to-latest-hidden',
                                ),
                                width: 0,
                                height: 0,
                              ),
                      ),
                    if (selected != null) kOpenHandHGap8,
                    IconButton.filledTonal(
                      tooltip: _autoFollow ? '关闭自动滚动到底部' : '开启自动滚动到底部',
                      onPressed: serviceEnabled ? _toggleAutoFollow : null,
                      style: _dingtalkDisabledActionStyle(context),
                      icon: AnimatedSwitcher(
                        duration: openHandMotionDuration(
                          context,
                          kOpenHandMotion180,
                        ),
                        child: Icon(
                          _autoFollow
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          key: ValueKey<bool>(_autoFollow),
                        ),
                      ),
                    ),
                    kOpenHandHGap8,
                    IconButton.filledTonal(
                      tooltip: selected == null
                          ? '请先选择需要刷新的会话'
                          : selectedRefreshing
                          ? '正在刷新当前会话'
                          : '强制刷新当前会话最新消息',
                      onPressed:
                          !serviceEnabled ||
                              selected == null ||
                              selectedRefreshing
                          ? null
                          : () => unawaited(
                              _refreshCurrentConversation(selected),
                            ),
                      style: _dingtalkDisabledActionStyle(context),
                      icon: AnimatedSwitcher(
                        duration: openHandMotionDuration(
                          context,
                          kOpenHandMotion180,
                        ),
                        child: selectedRefreshing
                            ? const SizedBox(
                                key: ValueKey<String>(
                                  'dingtalk-conversation-refreshing',
                                ),
                                width: 19,
                                height: 19,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                ),
                              )
                            : const Icon(
                                Icons.refresh_rounded,
                                key: ValueKey<String>(
                                  'dingtalk-conversation-refresh',
                                ),
                              ),
                      ),
                    ),
                    kOpenHandHGap8,
                    IconButton.filledTonal(
                      tooltip: '新建会话',
                      onPressed: serviceEnabled ? _addConversation : null,
                      style: _dingtalkDisabledActionStyle(context),
                      icon: const Icon(Icons.add_rounded),
                    ),
                    kOpenHandHGap8,
                    IconButton(
                      tooltip: '关闭',
                      onPressed: _close,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Stack(
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 248,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.surfaceContainerLow,
                            ),
                            child: conversations.isEmpty
                                ? Center(
                                    child: Text(
                                      '暂无消息会话',
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: colors.onSurfaceVariant,
                                          ),
                                    ),
                                  )
                                : ListView.separated(
                                    padding: const EdgeInsets.fromLTRB(
                                      10,
                                      10,
                                      10,
                                      12,
                                    ),
                                    itemCount: conversations.length,
                                    findItemIndexCallback: (key) {
                                      if (key case ValueKey<String>(
                                        value: final conversationId,
                                      )) {
                                        return conversationIndexById[conversationId];
                                      }
                                      return null;
                                    },
                                    separatorBuilder: (_, index) =>
                                        kOpenHandGap4,
                                    itemBuilder: (context, index) {
                                      final item = conversations[index];
                                      final active = item.id == selected?.id;
                                      final responseState = widget.controller
                                          .conversationResponseState(item.id);
                                      return Builder(
                                        key: ValueKey<String>(item.id),
                                        builder: (itemContext) => Material(
                                          color: active
                                              ? colors.primaryContainer
                                                    .withValues(alpha: 0.72)
                                              : Colors.transparent,
                                          borderRadius: kOpenHandBorderRadius12,
                                          shadowColor: Colors.transparent,
                                          child: InkWell(
                                            borderRadius:
                                                kOpenHandBorderRadius12,
                                            hoverColor: colors
                                                .surfaceContainerHighest
                                                .withValues(alpha: 0.55),
                                            focusColor: Colors.transparent,
                                            onTap: () =>
                                                _selectConversation(item.id),
                                            onDoubleTap: () =>
                                                _showConversationMenu(
                                                  itemContext,
                                                  item,
                                                ),
                                            onLongPress: () =>
                                                _showConversationMenu(
                                                  itemContext,
                                                  item,
                                                ),
                                            onSecondaryTap: () =>
                                                _showConversationMenu(
                                                  itemContext,
                                                  item,
                                                ),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 6,
                                                  ),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    item.type ==
                                                            DingTalkConversationType
                                                                .group
                                                        ? Icons.groups_rounded
                                                        : Icons.person_rounded,
                                                    size: 19,
                                                    color: active
                                                        ? colors
                                                              .onPrimaryContainer
                                                        : colors
                                                              .onSurfaceVariant,
                                                  ),
                                                  kOpenHandHGap9,
                                                  Expanded(
                                                    child: Text(
                                                      item.title,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: theme
                                                          .textTheme
                                                          .titleSmall
                                                          ?.copyWith(
                                                            color: active
                                                                ? colors
                                                                      .onPrimaryContainer
                                                                : colors
                                                                      .onSurface,
                                                            fontWeight: active
                                                                ? FontWeight
                                                                      .w700
                                                                : FontWeight
                                                                      .w600,
                                                          ),
                                                    ),
                                                  ),
                                                  AnimatedSwitcher(
                                                    duration:
                                                        openHandMotionDuration(
                                                          context,
                                                          kOpenHandMotion220,
                                                        ),
                                                    switchInCurve:
                                                        kOpenHandEntranceCurve,
                                                    switchOutCurve:
                                                        kOpenHandSwitchOutCurve,
                                                    transitionBuilder:
                                                        (
                                                          child,
                                                          animation,
                                                        ) => FadeTransition(
                                                          opacity: animation,
                                                          child:
                                                              ScaleTransition(
                                                                scale:
                                                                    animation,
                                                                child: child,
                                                              ),
                                                        ),
                                                    child:
                                                        responseState ==
                                                            DingTalkConversationResponseState
                                                                .idle
                                                        ? const SizedBox.shrink(
                                                            key: ValueKey<String>(
                                                              'dingtalk-conversation-status-idle',
                                                            ),
                                                          )
                                                        : Padding(
                                                            key:
                                                                ValueKey<
                                                                  DingTalkConversationResponseState
                                                                >(
                                                                  responseState,
                                                                ),
                                                            padding:
                                                                const EdgeInsets.only(
                                                                  left: 8,
                                                                ),
                                                            child: RepaintBoundary(
                                                              child: _DingTalkConversationStatusCapsule(
                                                                state:
                                                                    responseState,
                                                                selected:
                                                                    active,
                                                              ),
                                                            ),
                                                          ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          child: selected == null
                              ? const Center(child: Text('选择左侧会话开始交流'))
                              : Column(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.fromLTRB(
                                        18,
                                        12,
                                        18,
                                        10,
                                      ),
                                      decoration: BoxDecoration(
                                        border: Border(
                                          bottom: BorderSide(
                                            color: colors.outlineVariant
                                                .withValues(alpha: 0.55),
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            selected.type ==
                                                    DingTalkConversationType
                                                        .group
                                                ? Icons.groups_rounded
                                                : Icons.person_rounded,
                                            size: 19,
                                            color: colors.primary,
                                          ),
                                          kOpenHandHGap8,
                                          Expanded(
                                            child: Text(
                                              selected.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.titleMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                          ),
                                          if (widget.controller
                                              .isConversationResponding(
                                                selected.id,
                                              )) ...[
                                            kOpenHandHGap10,
                                            Flexible(
                                              child: Align(
                                                alignment:
                                                    Alignment.centerRight,
                                                child: Text(
                                                  widget.controller
                                                      .responseStatusText(
                                                        selected.id,
                                                      ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  textAlign: TextAlign.right,
                                                  style: theme
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: colors.primary,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                ),
                                              ),
                                            ),
                                            kOpenHandHGap8,
                                            const _DingTalkRespondingIndicator(),
                                          ],
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: selectedMessages.isEmpty
                                          ? Center(
                                              child: AnimatedSwitcher(
                                                duration:
                                                    openHandMotionDuration(
                                                      context,
                                                      kOpenHandMotion220,
                                                    ),
                                                child: selectedRefreshing
                                                    ? Row(
                                                        key: const ValueKey<String>(
                                                          'dingtalk-initial-history-loading',
                                                        ),
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          const SizedBox(
                                                            width: 20,
                                                            height: 20,
                                                            child:
                                                                CircularProgressIndicator(
                                                                  strokeWidth:
                                                                      2.2,
                                                                ),
                                                          ),
                                                          kOpenHandHGap10,
                                                          Text(
                                                            '正在同步最近 20 条消息…',
                                                            style: theme
                                                                .textTheme
                                                                .bodyMedium
                                                                ?.copyWith(
                                                                  color: colors
                                                                      .onSurfaceVariant,
                                                                ),
                                                          ),
                                                        ],
                                                      )
                                                    : Text(
                                                        '暂无消息，发送一条消息开始交流',
                                                        key: const ValueKey<String>(
                                                          'dingtalk-empty-conversation',
                                                        ),
                                                        style: theme
                                                            .textTheme
                                                            .bodyMedium
                                                            ?.copyWith(
                                                              color: colors
                                                                  .onSurfaceVariant,
                                                            ),
                                                      ),
                                              ),
                                            )
                                          : Listener(
                                              behavior:
                                                  HitTestBehavior.translucent,
                                              onPointerSignal:
                                                  _handleMessagesPointerSignal,
                                              child: OpenHandSafeScrollbar(
                                                controller:
                                                    _messagesScrollController,
                                                thumbVisibility: false,
                                                thickness:
                                                    _messagesScrollbarThickness,
                                                radius:
                                                    _messagesScrollbarRadius,
                                                stabilizeMetrics: true,
                                                child: NotificationListener<Notification>(
                                                  onNotification:
                                                      _handleMessagesNotification,
                                                  child: ListView.builder(
                                                    scrollCacheExtent:
                                                        const ScrollCacheExtent.pixels(
                                                          _messageCacheExtent,
                                                        ),
                                                    key: ValueKey<String>(
                                                      selected.id,
                                                    ),
                                                    controller:
                                                        _messagesScrollController,
                                                    addRepaintBoundaries: false,
                                                    reverse: true,
                                                    keyboardDismissBehavior:
                                                        ScrollViewKeyboardDismissBehavior
                                                            .onDrag,
                                                    physics:
                                                        kOpenHandClampingPhysics,
                                                    primary: false,
                                                    findChildIndexCallback: (key) {
                                                      if (key case ValueKey<
                                                        String
                                                      >(
                                                        value: final identity,
                                                      )) {
                                                        return messageTopology
                                                            ?.reverseIndexOf(
                                                              identity,
                                                            );
                                                      }
                                                      return null;
                                                    },
                                                    padding:
                                                        const EdgeInsets.fromLTRB(
                                                          20,
                                                          18,
                                                          20,
                                                          12,
                                                        ),
                                                    itemCount:
                                                        selectedMessages
                                                            .length +
                                                        (selectedHasOlderMessages ||
                                                                selectedLoadingOlderMessages
                                                            ? 1
                                                            : 0),
                                                    itemBuilder: (context, index) {
                                                      final historyHeaderVisible =
                                                          selectedHasOlderMessages ||
                                                          selectedLoadingOlderMessages;
                                                      if (historyHeaderVisible &&
                                                          index ==
                                                              selectedMessages
                                                                  .length) {
                                                        final loading =
                                                            selectedLoadingOlderMessages;
                                                        return Padding(
                                                          padding:
                                                              const EdgeInsets.only(
                                                                bottom: 12,
                                                              ),
                                                          child: Center(
                                                            child: OutlinedButton.icon(
                                                              onPressed: loading
                                                                  ? null
                                                                  : () => unawaited(
                                                                      _loadOlderMessages(
                                                                        selected,
                                                                      ),
                                                                    ),
                                                              icon: loading
                                                                  ? const SizedBox(
                                                                      width: 16,
                                                                      height:
                                                                          16,
                                                                      child: CircularProgressIndicator(
                                                                        strokeWidth:
                                                                            2,
                                                                      ),
                                                                    )
                                                                  : const Icon(
                                                                      Icons
                                                                          .history_rounded,
                                                                      size: 18,
                                                                    ),
                                                              label: Text(
                                                                loading
                                                                    ? '加载更早消息中…'
                                                                    : '加载更早消息',
                                                              ),
                                                            ),
                                                          ),
                                                        );
                                                      }
                                                      final messageIndex =
                                                          selectedMessages
                                                              .length -
                                                          index -
                                                          1;
                                                      final message =
                                                          selectedMessages[messageIndex];
                                                      final renderIdentity =
                                                          messageTopology!
                                                              .identityAt(
                                                                messageIndex,
                                                              );
                                                      _scheduleVisibleMediaLoad(
                                                        selected.id,
                                                        message,
                                                      );
                                                      final messageTextContent =
                                                          _dingtalkTextContent(
                                                            message.content,
                                                          );
                                                      final textActionEnabled =
                                                          !message.recalled &&
                                                          !message
                                                              .isAutomaticReply &&
                                                          !message
                                                              .isForwardedChatRecord &&
                                                          _hasDingTalkTextContent(
                                                            message.content,
                                                            message.media,
                                                          );
                                                      final translation =
                                                          textActionEnabled
                                                          ? _translationManager.visibleTranslation(
                                                              messageId:
                                                                  message.id,
                                                              sourceText:
                                                                  messageTextContent,
                                                              settingsFingerprint:
                                                                  aiTranslationRequestFingerprint(
                                                                    translationSettings,
                                                                    messageActionFallbackModel,
                                                                  ),
                                                            )
                                                          : null;
                                                      return RepaintBoundary(
                                                        key: ValueKey<String>(
                                                          renderIdentity,
                                                        ),
                                                        child: _DingTalkMessageBubble(
                                                          message: message,
                                                          renderIdentity:
                                                              renderIdentity,
                                                          anchorRegistry:
                                                              _messageAnchorRegistry,
                                                          mine: _isMine(
                                                            message,
                                                          ),
                                                          streaming: widget
                                                              .controller
                                                              .isEchoStreaming(
                                                                message,
                                                              ),
                                                          actionsVisible:
                                                              _expandedActionMessageId ==
                                                              message.id,
                                                          onToggleActions: () {
                                                            if (!mounted) {
                                                              return;
                                                            }
                                                            setState(() {
                                                              _expandedActionMessageId =
                                                                  _expandedActionMessageId ==
                                                                      message.id
                                                                  ? null
                                                                  : message.id;
                                                            });
                                                          },
                                                          mediaLoading: widget
                                                              .controller
                                                              .isMessageMediaCaching(
                                                                message.id,
                                                              ),
                                                          mediaFailed: widget
                                                              .controller
                                                              .isMessageMediaHydrationFailed(
                                                                message.id,
                                                              ),
                                                          onEdit:
                                                              _canEditMessage(
                                                                message,
                                                              )
                                                              ? () =>
                                                                    _beginMessageEdit(
                                                                      selected,
                                                                      message,
                                                                    )
                                                              : null,
                                                          onShowEditHistory:
                                                              message.isEdited
                                                              ? () => unawaited(
                                                                  _showEditHistory(
                                                                    context,
                                                                    message,
                                                                  ),
                                                                )
                                                              : null,
                                                          onToggleAiContextIgnored:
                                                              !message.isAssistant &&
                                                                  !message
                                                                      .recalled &&
                                                                  !message
                                                                      .isAutomaticReply
                                                              ? () =>
                                                                    _toggleMessageAiContextIgnored(
                                                                      selected,
                                                                      message,
                                                                    )
                                                              : null,
                                                          onRetryMedia:
                                                              message
                                                                  .contextualMedia
                                                                  .any(
                                                                    (
                                                                      item,
                                                                    ) => item
                                                                        .localPath
                                                                        .trim()
                                                                        .isEmpty,
                                                                  )
                                                              ? () => unawaited(
                                                                  widget.controller.ensureMessageMediaCached(
                                                                    conversationId:
                                                                        selected
                                                                            .id,
                                                                    messageId:
                                                                        message
                                                                            .id,
                                                                    forceRetry:
                                                                        true,
                                                                  ),
                                                                )
                                                              : null,
                                                          onSaveMedia:
                                                              (
                                                                media,
                                                                path,
                                                              ) => widget
                                                                  .controller
                                                                  .saveMessageMedia(
                                                                    conversationId:
                                                                        selected
                                                                            .id,
                                                                    messageId:
                                                                        message
                                                                            .id,
                                                                    media:
                                                                        media,
                                                                    destinationPath:
                                                                        path,
                                                                  ),
                                                          speechEnabled:
                                                              textActionEnabled &&
                                                              ttsSettings
                                                                  .enabled,
                                                          speechPlaying:
                                                              textActionEnabled &&
                                                              ttsSettings
                                                                  .enabled &&
                                                              ttsSnapshot
                                                                  .playing &&
                                                              ttsSnapshot
                                                                      .messageId ==
                                                                  message.id,
                                                          onToggleSpeech:
                                                              textActionEnabled &&
                                                                  ttsSettings
                                                                      .enabled
                                                              ? () => unawaited(
                                                                  _toggleMessageSpeech(
                                                                    message,
                                                                    ttsSettings,
                                                                    messageActionFallbackModel,
                                                                  ),
                                                                )
                                                              : null,
                                                          translationEnabled:
                                                              textActionEnabled &&
                                                              translationSettings
                                                                  .enabled,
                                                          translationLoading:
                                                              _translationManager
                                                                  .isLoading(
                                                                    message.id,
                                                                  ),
                                                          translationVisible:
                                                              translation !=
                                                              null,
                                                          translatedContent:
                                                              translation
                                                                  ?.translatedText,
                                                          onToggleTranslation:
                                                              textActionEnabled &&
                                                                  translationSettings
                                                                      .enabled
                                                              ? () => unawaited(
                                                                  _toggleMessageTranslation(
                                                                    message,
                                                                    translationSettings,
                                                                    messageActionFallbackModel,
                                                                  ),
                                                                )
                                                              : null,
                                                          onSetFeedback:
                                                              message.isAssistant &&
                                                                  !message
                                                                      .recalled
                                                              ? (
                                                                  feedback,
                                                                ) => unawaited(
                                                                  _setMessageFeedback(
                                                                    selected,
                                                                    message,
                                                                    feedback,
                                                                  ),
                                                                )
                                                              : null,
                                                          onAudit:
                                                              telemetryDebugEnabled
                                                              ? () =>
                                                                    _showMessageAudit(
                                                                      selected,
                                                                      message,
                                                                    )
                                                              : null,
                                                          onOpenForwardedChat:
                                                              message
                                                                  .isForwardedChatRecord
                                                              ? () =>
                                                                    _showForwardedChatRecord(
                                                                      context,
                                                                      selected,
                                                                      message,
                                                                    )
                                                              : null,
                                                          onOpenQuotedMessage:
                                                              message
                                                                      .quotedMessage
                                                                      ?.id
                                                                      .trim()
                                                                      .isNotEmpty ==
                                                                  true
                                                              ? () => unawaited(
                                                                  _jumpToQuotedMessage(
                                                                    selected,
                                                                    message,
                                                                  ),
                                                                )
                                                              : null,
                                                          onReturnToQuotedSource:
                                                              normalizeDingTalkMessageId(
                                                                        message
                                                                            .id,
                                                                      ) ==
                                                                      _quotedJumpTargetMessageId &&
                                                                  _quotedReturnMessageId !=
                                                                      null
                                                              ? () => unawaited(
                                                                  _returnToQuotedSource(
                                                                    selected,
                                                                  ),
                                                                )
                                                              : null,
                                                          highlighted:
                                                              normalizeDingTalkMessageId(
                                                                message.id,
                                                              ) ==
                                                              _highlightedMessageId,
                                                          showRawAction:
                                                              message
                                                                  .isAssistant &&
                                                              textActionEnabled,
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                ),
                                              ),
                                            ),
                                    ),
                                    AnimatedSwitcher(
                                      duration: openHandMotionDuration(
                                        context,
                                        kOpenHandMotion220,
                                      ),
                                      switchInCurve: kOpenHandEntranceCurve,
                                      switchOutCurve: kOpenHandSwitchOutCurve,
                                      child: selectedQueuedResponses.isEmpty
                                          ? const SizedBox.shrink(
                                              key: ValueKey<String>(
                                                'dingtalk-response-queue-empty',
                                              ),
                                            )
                                          : _DingTalkQueuedResponsesPanel(
                                              key: ValueKey<String>(
                                                'dingtalk-response-queue:${selected.id}',
                                              ),
                                              messages: selectedQueuedResponses,
                                              showRespondAction: widget
                                                  .controller
                                                  .isResponseQueuePaused(
                                                    selected.id,
                                                  ),
                                              canRespond: (sequence) => widget
                                                  .controller
                                                  .canRespondToQueuedResponse(
                                                    selected.id,
                                                    sequence,
                                                  ),
                                              onRespond: (sequence) => widget
                                                  .controller
                                                  .respondToQueuedResponse(
                                                    selected.id,
                                                    sequence,
                                                  ),
                                              animationSettings:
                                                  chipAnimationSettings,
                                              onRemove: (sequence) => widget
                                                  .controller
                                                  .removeQueuedResponse(
                                                    selected.id,
                                                    sequence,
                                                  ),
                                              onMove: (from, to) => widget
                                                  .controller
                                                  .moveQueuedResponse(
                                                    selected.id,
                                                    from,
                                                    to,
                                                  ),
                                            ),
                                    ),
                                    _buildComposer(
                                      selected,
                                      chipAnimationSettings,
                                    ),
                                  ],
                                ),
                        ),
                      ],
                    ),
                    Positioned.fill(
                      child: AnimatedSwitcher(
                        duration: openHandMotionDuration(
                          context,
                          kOpenHandMotion220,
                        ),
                        switchInCurve: kOpenHandEntranceCurve,
                        switchOutCurve: kOpenHandSwitchOutCurve,
                        child: serviceEnabled
                            ? const SizedBox.expand(
                                key: ValueKey<String>(
                                  'dingtalk-service-unlocked',
                                ),
                              )
                            : _DingTalkServiceLockOverlay(
                                key: const ValueKey<String>(
                                  'dingtalk-service-locked',
                                ),
                                onClose: _close,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildComposer(
    DingTalkConversation conversation,
    DialogAnimationSettings chipAnimationSettings,
  ) {
    final responding = widget.controller.isConversationResponding(
      conversation.id,
    );
    final responseError =
        widget.controller.responseErrorMessage(conversation.id)?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedSwitcher(
            duration: openHandMotionDuration(context, kOpenHandMotion180),
            switchInCurve: kOpenHandSwitchInCurve,
            switchOutCurve: kOpenHandSwitchOutCurve,
            child: responseError.isNotEmpty
                ? _DingTalkResponseErrorBanner(
                    key: ValueKey<String>(responseError),
                    message: responseError,
                    onDismiss: () =>
                        widget.controller.clearResponseError(conversation.id),
                  )
                : const SizedBox.shrink(
                    key: ValueKey<String>('dingtalk-response-no-error'),
                  ),
          ),
          if (_pendingAttachments.isNotEmpty)
            _buildPendingAttachmentsBar(conversation, chipAnimationSettings),
          AnimatedSwitcher(
            duration: openHandMotionDuration(context, kOpenHandMotion220),
            switchInCurve: kOpenHandSwitchInCurve,
            switchOutCurve: kOpenHandSwitchOutCurve,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.bottomCenter,
              children: <Widget>[...previous, if (current != null) current],
            ),
            child: _recordingVoice && !responding
                ? _buildVoiceRecordingComposer()
                : _buildTextComposer(conversation),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingAttachmentsBar(
    DingTalkConversation conversation,
    DialogAnimationSettings chipAnimationSettings,
  ) {
    final responding = widget.controller.isConversationResponding(
      conversation.id,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final attachment in _pendingAttachments)
            AnimatedRemovableChip(
              key: ValueKey<String>('dingtalk-attachment:${attachment.path}'),
              settings: chipAnimationSettings,
              onRemove: responding
                  ? () {}
                  : () => _removePendingAttachment(attachment.path),
              builder: (context, requestRemove) =>
                  _DingTalkPendingAttachmentChip(
                    attachment: attachment,
                    onTap: () => unawaited(_openPendingAttachment(attachment)),
                    onRemove: _attachmentBusy || responding
                        ? () {}
                        : requestRemove,
                  ),
            ),
        ],
      ),
    );
  }

  Future<void> _openPendingAttachment(
    _DingTalkPendingAttachment attachment,
  ) async {
    if (!widget.controller.isServiceEnabled) return;
    final path = attachment.path.trim();
    if (path.isEmpty || !await _pathExistsBounded(File(path))) {
      if (mounted) showOpenHandErrorSnack(context, '附件文件已不存在。');
      return;
    }
    final kind = DingTalkMediaKindX.fromFileName(attachment.name);
    if (kind == DingTalkMediaKind.file) {
      final opened = await openLocalPathWithSystemApp(
        path,
        tag: 'dingtalk_gateway',
      );
      if (!opened && mounted) showOpenHandErrorSnack(context, '无法打开该附件。');
      return;
    }
    if (!mounted) return;
    final previewKind = switch (kind) {
      DingTalkMediaKind.image => MediaPreviewKind.image,
      DingTalkMediaKind.video => MediaPreviewKind.video,
      DingTalkMediaKind.audio => MediaPreviewKind.audio,
      DingTalkMediaKind.file => MediaPreviewKind.audio,
    };
    unawaited(
      showAnimatedDialog<void>(
        context: context,
        builder: (_) => MediaPreviewDialog.file(
          filePath: path,
          title: attachment.name,
          kind: previewKind,
        ),
      ),
    );
  }

  Widget _buildTextComposer(DingTalkConversation conversation) {
    final responding = widget.controller.isConversationResponding(
      conversation.id,
    );
    return Row(
      key: ValueKey<String>(
        responding ? 'dingtalk-responding-composer' : 'dingtalk-text-composer',
      ),
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: _input,
            focusNode: _inputFocusNode,
            enabled: widget.controller.isServiceEnabled && !responding,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              hintText: _isEditingConversation(conversation)
                  ? '编辑当前钉钉消息内容'
                  : responding
                  ? '响应期间暂不可输入新消息'
                  : '以当前钉钉身份发送消息',
              filled: responding,
              fillColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
              prefixIcon: responding
                  ? const Icon(Icons.lock_clock_rounded, size: 19)
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 13,
              ),
            ),
            onSubmitted: !widget.controller.isServiceEnabled || responding
                ? null
                : (_) => _isEditingConversation(conversation)
                      ? unawaited(_confirmMessageEdit(conversation))
                      : _sendOrStop(conversation),
          ),
        ),
        kOpenHandHGap10,
        if (responding) ...[
          _buildSendButton(conversation),
        ] else if (_isEditingConversation(conversation)) ...[
          _buildEditCancelButton(),
          kOpenHandHGap6,
          _buildEditConfirmButton(conversation),
        ] else ...[
          _buildFileButton(conversation),
          kOpenHandHGap6,
          _buildVoiceButton(conversation),
          kOpenHandHGap6,
          _buildForceResponseButton(conversation),
          kOpenHandHGap8,
          _buildSendButton(conversation),
        ],
      ],
    );
  }

  bool _isEditingConversation(DingTalkConversation conversation) {
    return _editingConversationId == conversation.id &&
        _editingMessageId != null;
  }

  bool _canEditMessage(DingTalkGatewayMessage message) {
    if (_editingConversationId != null ||
        _editSubmitting ||
        message.recalled ||
        message.media.isNotEmpty ||
        message.content.trim().isEmpty) {
      return false;
    }
    return widget.controller.isMessageFromCurrentUser(message);
  }

  void _beginMessageEdit(
    DingTalkConversation conversation,
    DingTalkGatewayMessage message,
  ) {
    if (!_canEditMessage(message)) return;
    final content = stripImageSummaryMarkup(message.content);
    setState(() {
      _editingConversationId = conversation.id;
      _editingMessageId = message.id;
      _input.value = TextEditingValue(
        text: content,
        selection: TextSelection.collapsed(offset: content.length),
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isEditingConversation(conversation)) {
        _inputFocusNode.requestFocus();
      }
    });
  }

  void _cancelMessageEdit() {
    if (_editSubmitting) return;
    _input.clear();
    _inputFocusNode.unfocus();
    if (!mounted) return;
    setState(() {
      _editingConversationId = null;
      _editingMessageId = null;
    });
  }

  Future<void> _confirmMessageEdit(DingTalkConversation conversation) async {
    if (_editSubmitting || !_isEditingConversation(conversation)) return;
    final messageId = _editingMessageId!;
    final text = _input.text.trim();
    if (text.isEmpty) {
      showOpenHandErrorSnack(context, '编辑内容不能为空。');
      return;
    }
    setState(() => _editSubmitting = true);
    try {
      final success = await widget.controller.editMessage(
        conversation.id,
        messageId,
        text,
      );
      if (!mounted) return;
      final stillEditing =
          _editingConversationId == conversation.id &&
          _editingMessageId == messageId;
      if (success && stillEditing) {
        _input.clear();
        _inputFocusNode.unfocus();
        setState(() {
          _editingConversationId = null;
          _editingMessageId = null;
        });
        showOpenHandSuccessSnack(context, '消息已更新。');
      } else if (!success && stillEditing) {
        showOpenHandErrorSnack(
          context,
          widget.controller.errorMessage ?? '消息编辑失败，请稍后重试。',
        );
      }
    } finally {
      if (mounted) setState(() => _editSubmitting = false);
    }
  }

  Future<void> _showEditHistory(
    BuildContext context,
    DingTalkGatewayMessage message,
  ) {
    return showAnimatedDialog<void>(
      context: context,
      builder: (_) => buildOpenHandDialog(
        maxWidth: 680,
        maxHeight: MediaQuery.sizeOf(context).height * 0.78,
        child: _DingTalkMessageEditHistoryDialog(message: message),
      ),
    );
  }

  Future<void> _toggleMessageSpeech(
    DingTalkGatewayMessage message,
    AiTtsSettings settings,
    AiModelConfig? fallbackModel,
  ) async {
    if (!widget.controller.isServiceEnabled) return;
    final content = _dingtalkTextContent(message.content);
    if (!_hasDingTalkTextContent(message.content, message.media)) return;
    try {
      await _ttsPlaybackService.toggleMessage(
        messageId: message.id,
        text: message.isThinkingEcho
            ? unwrapDingTalkThinkingMarkdown(content)
            : content,
        settings: settings,
        availableModels: widget.controller.aiModels,
        fallbackModel: fallbackModel,
      );
    } catch (error, stack) {
      silentLog('dingtalk_gateway', '朗读钉钉消息', error, stack);
      if (mounted) {
        showOpenHandErrorSnack(
          context,
          '朗读失败：${messageGatewayFailureMessage(error, fallback: '请检查文本转语音设置。')}',
        );
      }
    }
  }

  Future<void> _toggleMessageTranslation(
    DingTalkGatewayMessage message,
    AiTranslationSettings settings,
    AiModelConfig? fallbackModel,
  ) async {
    if (!widget.controller.isServiceEnabled) return;
    final content = _dingtalkTextContent(message.content);
    if (!_hasDingTalkTextContent(message.content, message.media)) return;
    final fingerprint = aiTranslationRequestFingerprint(
      settings,
      fallbackModel,
    );
    final failure = await _translationManager.toggle(
      messageId: message.id,
      sourceText: content,
      settingsFingerprint: fingerprint,
      settings: settings,
      availableModels: widget.controller.aiModels,
      fallbackModel: fallbackModel,
      isMounted: () => mounted,
      update: (mutation) {
        if (mounted) setState(mutation);
      },
      logAction: '翻译钉钉消息',
    );
    if (mounted && failure != null) {
      showOpenHandErrorSnack(context, '翻译失败：$failure');
    }
  }

  Future<void> _setMessageFeedback(
    DingTalkConversation conversation,
    DingTalkGatewayMessage message,
    DingTalkGatewayMessageFeedback? feedback,
  ) async {
    if (!widget.controller.isServiceEnabled) return;
    final success = await widget.controller.updateMessageFeedback(
      conversation.id,
      message.id,
      feedback,
    );
    if (!success && mounted) {
      showOpenHandErrorSnack(
        context,
        widget.controller.errorMessage ?? '消息反馈保存失败，请稍后重试。',
      );
    }
  }

  void _toggleMessageAiContextIgnored(
    DingTalkConversation conversation,
    DingTalkGatewayMessage message,
  ) {
    if (!widget.controller.isServiceEnabled) return;
    final ignored = !message.ignoredForAiContext;
    final success = widget.controller.setMessageAiContextIgnored(
      conversation.id,
      message.id,
      ignored,
    );
    if (!mounted) return;
    if (!success) {
      showOpenHandErrorSnack(context, '消息状态已变化，请刷新后重试。');
      return;
    }
    showOpenHandInfoSnack(
      context,
      ignored ? '已忽略，该消息不会参与后续 AI 上下文。' : '已撤销忽略，该消息可再次参与 AI 上下文。',
    );
  }

  void _showMessageAudit(
    DingTalkConversation conversation,
    DingTalkGatewayMessage message,
  ) {
    if (!widget.controller.isServiceEnabled) return;
    final snapshot = widget.controller.loadMessageAuditSnapshot(
      conversation.id,
      message.id,
    );
    unawaited(
      showAnimatedDialog<void>(
        context: context,
        builder: (_) => buildOpenHandDialog(
          maxWidth: 820,
          maxHeight: MediaQuery.sizeOf(context).height * 0.84,
          child: _DingTalkMessageAuditDialog(snapshot: snapshot),
        ),
      ),
    );
  }

  void _showForwardedChatRecord(
    BuildContext context,
    DingTalkConversation conversation,
    DingTalkGatewayMessage message,
  ) {
    if (!widget.controller.isServiceEnabled) return;
    unawaited(
      showAnimatedDialog<void>(
        context: context,
        builder: (_) => buildOpenHandDialog(
          maxWidth: kOpenHandDialogWidthWide,
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
          child: _DingTalkForwardedChatDialog(
            controller: widget.controller,
            conversationId: conversation.id,
            messageId: message.id,
            initialMessage: message,
          ),
        ),
      ),
    );
  }

  Widget _buildEditCancelButton() {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 168),
      child: SizedBox(
        height: 48,
        child: OutlinedButton(
          onPressed: _editSubmitting ? null : _cancelMessageEdit,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 22),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.close_rounded),
              kOpenHandWidth10,
              Text('取消编辑', maxLines: 1, softWrap: false),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditConfirmButton(DingTalkConversation conversation) {
    final messageId = _editingMessageId;
    final currentMessage = messageId == null
        ? null
        : conversation.messages
              .where((message) => message.id == messageId)
              .firstOrNull;
    final enabled =
        !_editSubmitting &&
        currentMessage != null &&
        _input.text.trim().isNotEmpty &&
        _input.text.trim() != currentMessage.content.trim();
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 168),
      child: SizedBox(
        height: 48,
        child: FilledButton(
          onPressed: enabled
              ? () => unawaited(_confirmMessageEdit(conversation))
              : null,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 22),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_editSubmitting)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(Icons.check_rounded),
              kOpenHandHGap10,
              const Text('确认编辑', maxLines: 1, softWrap: false),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceRecordingComposer() {
    return ValueListenableBuilder<_DingTalkVoiceVisualState>(
      key: const ValueKey<String>('dingtalk-voice-composer'),
      valueListenable: _voiceVisual,
      builder: (context, visual, _) => Row(
        children: [
          Expanded(
            child: _DingTalkVoiceRecordingPanel(
              visual: visual,
              maxDuration: _maxVoiceDuration,
            ),
          ),
          kOpenHandHGap10,
          _buildVoiceCancelButton(),
          kOpenHandHGap6,
          _buildVoicePauseButton(),
          kOpenHandHGap8,
          _buildVoiceSendButton(),
        ],
      ),
    );
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !navigator.mounted || route == null) return;
      if (!route.isActive || !route.isCurrent) {
        _closing = false;
        return;
      }
      try {
        navigator.pop();
      } catch (error, stack) {
        _closing = false;
        silentLog('message_gateway', '关闭钉钉消息弹窗', error, stack);
      }
    });
  }

  Future<void> _refreshCurrentConversation(
    DingTalkConversation conversation,
  ) async {
    final addedCount = await widget.controller.refreshConversationMessages(
      conversation.id,
    );
    if (!mounted || _selectedId != conversation.id) return;
    if (addedCount == null) {
      showOpenHandErrorSnack(
        context,
        widget.controller.errorMessage ?? '刷新当前钉钉会话失败，请稍后重试。',
      );
      return;
    }
    showOpenHandInfoSnack(
      context,
      addedCount > 0 ? '已同步 $addedCount 条最新消息' : '当前会话已刷新',
    );
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    if (widget.controller.unreadCount > 0) {
      widget.controller.markAllRead();
    }
    if (!widget.controller.isServiceEnabled) {
      unawaited(_ttsPlaybackService.stop());
      _translationManager.clear();
      if (_recordingVoice) _cancelVoiceRecording();
      if (_editingConversationId != null ||
          _editingMessageId != null ||
          _pendingAttachments.isNotEmpty ||
          _input.text.isNotEmpty) {
        _input.clear();
        _inputFocusNode.unfocus();
        setState(() {
          _editingConversationId = null;
          _editingMessageId = null;
          _editSubmitting = false;
          _pendingAttachments = const <_DingTalkPendingAttachment>[];
          _attachmentBusy = false;
        });
      }
      _messagesProgrammaticScroll.cancel();
      _followRequestVersion++;
    }
    final selectedId = _selectedId;
    if (selectedId != null &&
        widget.controller.isConversationResponding(selectedId)) {
      if (_recordingVoice && _voiceConversationId == selectedId) {
        _cancelVoiceRecording();
      }
      if (_inputFocusNode.hasFocus) _inputFocusNode.unfocus();
    }
    _updateMessagesBottomState();
  }

  void _handleMessagesScrollChanged() {
    _updateMessagesBottomState();
  }

  void _updateMessagesBottomState() {
    if (!mounted) return;
    final controller = _messagesScrollController;
    final awayFromLatest =
        !_autoFollow &&
        controller.hasClients &&
        controller.position.hasContentDimensions &&
        controller.position.pixels - controller.position.minScrollExtent >
            _latestMessageBottomThreshold;
    if (awayFromLatest == _showJumpToLatest) return;
    setState(() => _showJumpToLatest = awayFromLatest);
  }

  void _jumpToLatestMessages() {
    if (!widget.controller.isServiceEnabled) return;
    final controller = _messagesScrollController;
    if (!controller.hasClients || !controller.position.hasContentDimensions) {
      return;
    }
    _messagesProgrammaticScroll.cancel();
    _messageNavigationVersion++;
    _messagesUserScrollActive = false;
    _followJumpToBottom = false;
    final requestVersion = ++_followRequestVersion;
    unawaited(_settleMessagesAtLatest(requestVersion));
  }

  Future<void> _settleMessagesAtLatest(int requestVersion) async {
    if (!mounted || requestVersion != _followRequestVersion) return;
    final controller = _messagesScrollController;
    if (!controller.hasClients || !controller.position.hasContentDimensions) {
      return;
    }
    final position = controller.position;
    if (position.pixels - position.minScrollExtent <=
        _latestMessageBottomThreshold) {
      _updateMessagesBottomState();
      return;
    }
    _messagesProgrammaticScroll.begin();
    try {
      await controller.animateTo(
        position.minScrollExtent,
        duration: openHandMotionDuration(context, kOpenHandMotion260),
        curve: kOpenHandSwitchInCurve,
      );
    } catch (error, stack) {
      if (mounted && requestVersion == _followRequestVersion) {
        silentLog('dingtalk_gateway_ui', '滚动至钉钉最新消息', error, stack);
      }
    } finally {
      _messagesProgrammaticScroll.end();
    }
    if (mounted && requestVersion == _followRequestVersion) {
      _updateMessagesBottomState();
    }
  }

  void _toggleAutoFollow() {
    if (!widget.controller.isServiceEnabled) return;
    final next = !_autoFollow;
    setState(() {
      _autoFollow = next;
      _autoFollowPausedByUserScroll = false;
      if (!next) _followJumpToBottom = false;
    });
    if (next) {
      _scheduleAutoFollow(force: true);
    } else {
      _messagesProgrammaticScroll.cancel();
      _followRequestVersion++;
      _updateMessagesBottomState();
    }
  }

  void _handleMessagesPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) return;
    // 触控板/滚轮属于明确的用户输入，立即终止贴底动画，避免两套滚动
    // 同时写入同一个 ScrollPosition 造成来回抢占。
    _messagesProgrammaticScroll.cancel();
    _messageNavigationVersion++;
    _lastMessagesPointerSignalAt = _messagesScrollActivityStopwatch.elapsed;
    final controller = _messagesScrollController;
    if (controller.hasClients &&
        controller.position.pixels - controller.position.minScrollExtent >
            _latestMessageBottomThreshold) {
      _disableAutoFollow();
    }
  }

  bool _hasRecentMessagesPointerSignal() {
    final last = _lastMessagesPointerSignalAt;
    return last != null &&
        _messagesScrollActivityStopwatch.elapsed - last <=
            kAutoFollowPointerSignalActivityWindow;
  }

  bool _handleMessagesScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    final programmaticScroll = _messagesProgrammaticScroll.active;
    final activity = classifyAutoFollowScrollActivity(
      notification,
      programmaticScroll: programmaticScroll,
      recentPointerSignalScroll: _hasRecentMessagesPointerSignal(),
    );
    final explicitUserScroll = activity.explicitUserScroll;
    final implicitPointerScroll = activity.implicitPointerSignalScroll;
    if (programmaticScroll && !explicitUserScroll) return false;
    final userScrollStarted =
        (explicitUserScroll || implicitPointerScroll) &&
        !_messagesUserScrollActive;
    if (explicitUserScroll) _messagesProgrammaticScroll.cancel();
    if (explicitUserScroll || implicitPointerScroll) {
      _messagesUserScrollActive = true;
    }
    final userScroll =
        explicitUserScroll ||
        implicitPointerScroll ||
        _messagesUserScrollActive;
    if (!userScroll) return false;
    if (userScrollStarted && explicitUserScroll) {
      _messageNavigationVersion++;
    }
    final distanceToBottom =
        notification.metrics.pixels - notification.metrics.minScrollExtent;
    if (distanceToBottom <= _latestMessageBottomThreshold) {
      if (_autoFollowPausedByUserScroll) {
        _autoFollowPausedByUserScroll = false;
        _enableAutoFollowAtLatest();
      }
    } else {
      _autoFollowPausedByUserScroll = true;
      _disableAutoFollow();
    }
    if (activity.userScrollEnded) {
      _messagesUserScrollActive = false;
    }
    return false;
  }

  bool _handleMessagesNotification(Notification notification) {
    if (notification is ScrollNotification) {
      return _handleMessagesScrollNotification(notification);
    }
    return false;
  }

  void _disableAutoFollow() {
    _messagesProgrammaticScroll.cancel();
    _followJumpToBottom = false;
    if (!mounted) return;
    if (!_autoFollow) {
      _updateMessagesBottomState();
      return;
    }
    _followRequestVersion++;
    setState(() => _autoFollow = false);
    _updateMessagesBottomState();
  }

  void _enableAutoFollowAtLatest() {
    _messagesProgrammaticScroll.cancel();
    _followJumpToBottom = false;
    if (!mounted || _autoFollow) {
      _updateMessagesBottomState();
      return;
    }
    _followRequestVersion++;
    setState(() {
      _autoFollow = true;
      _showJumpToLatest = false;
    });
  }

  void _selectConversation(String id) {
    if (!widget.controller.isServiceEnabled) return;
    if (_selectedId == id) return;
    _messageNavigationVersion++;
    _messagesUserScrollActive = false;
    _autoFollowPausedByUserScroll = false;
    _quotedMessageHighlightTimer?.cancel();
    _quotedMessageHighlightTimer = null;
    _messageAnchorRegistry.clear();
    _messagesProgrammaticScroll.cancel();
    if (_messagesScrollController.hasClients) {
      final position = _messagesScrollController.position;
      if (position.hasContentDimensions &&
          (position.pixels - position.minScrollExtent).abs() >= 1) {
        _messagesProgrammaticScroll.begin();
        try {
          position.jumpTo(position.minScrollExtent);
        } finally {
          _messagesProgrammaticScroll.end();
        }
      }
    }
    if (_recordingVoice && _voiceConversationId != id) {
      _cancelVoiceRecording();
    }
    setState(() {
      _selectedId = id;
      _showJumpToLatest = false;
      _quotedJumpTargetMessageId = null;
      _quotedReturnMessageId = null;
      _highlightedMessageId = null;
      _expandedActionMessageId = null;
      _editingConversationId = null;
      _editingMessageId = null;
      _editSubmitting = false;
      _input.clear();
      _pendingAttachments = const <_DingTalkPendingAttachment>[];
    });
    _scheduleAutoFollow(force: true);
  }

  Future<void> _jumpToQuotedMessage(
    DingTalkConversation conversation,
    DingTalkGatewayMessage sourceMessage,
  ) async {
    final quotedMessage = sourceMessage.quotedMessage;
    final targetId = normalizeDingTalkMessageId(quotedMessage?.id);
    if (quotedMessage == null || targetId.isEmpty) {
      showOpenHandInfoSnack(context, '引用消息缺少可定位的标识。');
      return;
    }
    _disableAutoFollow();
    final navigationVersion = ++_messageNavigationVersion;
    var targetIndex = _messageIndexById(conversation.messages, targetId);
    for (
      var attempt = 0;
      targetIndex < 0 &&
          attempt < _quotedMessageHistoryPageLimit &&
          widget.controller.hasOlderConversationMessages(conversation.id);
      attempt += 1
    ) {
      final previousCount = conversation.messages.length;
      await widget.controller.loadOlderConversationMessages(conversation.id);
      if (!mounted ||
          navigationVersion != _messageNavigationVersion ||
          _selectedId != conversation.id) {
        return;
      }
      targetIndex = _messageIndexById(conversation.messages, targetId);
      if (conversation.messages.length == previousCount) break;
    }
    if (targetIndex < 0) {
      if (mounted && navigationVersion == _messageNavigationVersion) {
        showOpenHandInfoSnack(context, '暂时无法在已加载记录中定位该引用消息。');
      }
      return;
    }
    final sourceId = normalizeDingTalkMessageId(sourceMessage.id);
    setState(() {
      _quotedJumpTargetMessageId = targetId;
      _quotedReturnMessageId = sourceId.isEmpty ? null : sourceId;
      _expandedActionMessageId = null;
    });
    final located = await _scrollToMessage(
      conversation,
      targetId,
      navigationVersion,
    );
    if (!mounted || navigationVersion != _messageNavigationVersion) return;
    if (!located) {
      showOpenHandInfoSnack(context, '引用消息已加载，但当前无法完成定位。');
      return;
    }
    _highlightMessage(targetId);
  }

  Future<void> _returnToQuotedSource(DingTalkConversation conversation) async {
    final sourceId = _quotedReturnMessageId;
    if (sourceId == null ||
        _messageIndexById(conversation.messages, sourceId) < 0) {
      showOpenHandInfoSnack(context, '引用处已不在当前消息记录中。');
      return;
    }
    _disableAutoFollow();
    final navigationVersion = ++_messageNavigationVersion;
    final located = await _scrollToMessage(
      conversation,
      sourceId,
      navigationVersion,
    );
    if (!mounted || navigationVersion != _messageNavigationVersion) return;
    if (!located) {
      showOpenHandInfoSnack(context, '当前无法返回引用处。');
      return;
    }
    setState(() {
      _quotedJumpTargetMessageId = null;
      _quotedReturnMessageId = null;
      _expandedActionMessageId = null;
    });
    _highlightMessage(sourceId);
  }

  int _messageIndexById(
    List<DingTalkGatewayMessage> messages,
    String messageId,
  ) {
    final normalizedId = normalizeDingTalkMessageId(messageId);
    return messages.lastIndexWhere(
      (message) => normalizeDingTalkMessageId(message.id) == normalizedId,
    );
  }

  Future<bool> _scrollToMessage(
    DingTalkConversation conversation,
    String messageId,
    int navigationVersion,
  ) async {
    _messagesUserScrollActive = false;
    bool navigationIsCurrent() =>
        mounted &&
        navigationVersion == _messageNavigationVersion &&
        _selectedId == conversation.id;

    for (
      var attempt = 0;
      navigationIsCurrent() && attempt <= _quotedMessageMaterializeAttempts;
      attempt += 1
    ) {
      final targetContext = _messageAnchorRegistry.contextOf(messageId);
      if (targetContext != null) {
        if (!mounted || !targetContext.mounted) return false;
        final scrollDuration = openHandMotionDuration(
          context,
          kOpenHandMotion420,
        );
        _messagesProgrammaticScroll.begin();
        try {
          await Scrollable.ensureVisible(
            targetContext,
            alignment: 0.24,
            duration: scrollDuration,
            curve: kOpenHandEmphasizedCurve,
          );
          return navigationIsCurrent();
        } catch (error, stack) {
          if (navigationIsCurrent()) {
            silentLog('钉钉消息网关', '定位引用消息', error, stack);
          }
          return false;
        } finally {
          _messagesProgrammaticScroll.end();
        }
      }
      if (attempt == _quotedMessageMaterializeAttempts) break;
      if (!await _scrollNearMessage(conversation, messageId)) return false;
      await _awaitMessageLayout();
    }
    return false;
  }

  Future<bool> _scrollNearMessage(
    DingTalkConversation conversation,
    String messageId,
  ) async {
    final targetMessageIndex = _messageIndexById(
      conversation.messages,
      messageId,
    );
    final controller = _messagesScrollController;
    if (targetMessageIndex < 0 ||
        !controller.hasClients ||
        !controller.position.hasContentDimensions) {
      return false;
    }
    final position = controller.position;
    final targetListIndex =
        conversation.messages.length - targetMessageIndex - 1;
    double? estimatedTarget;
    var nearestDistance = 1 << 30;
    for (final entry in _messageAnchorRegistry.entries) {
      final visibleMessageIndex = _messageIndexById(
        conversation.messages,
        entry.key,
      );
      if (visibleMessageIndex < 0) continue;
      final box = entry.value.findRenderObject() as RenderBox?;
      if (box == null || !box.attached || !box.hasSize) continue;
      final visibleListIndex =
          conversation.messages.length - visibleMessageIndex - 1;
      final distance = (targetListIndex - visibleListIndex).abs();
      if (distance >= nearestDistance) continue;
      nearestDistance = distance;
      final estimatedExtent = math.max(56.0, box.size.height + 7);
      estimatedTarget =
          position.pixels +
          (targetListIndex - visibleListIndex) * estimatedExtent;
    }
    estimatedTarget ??=
        position.maxScrollExtent *
        (targetListIndex / math.max(1, conversation.messages.length - 1)).clamp(
          0.0,
          1.0,
        );
    final target = estimatedTarget.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < 1) return true;
    final viewportDistances =
        (target - position.pixels).abs() /
        math.max(1, position.viewportDimension);
    final duration = viewportDistances < 2
        ? kOpenHandMotion320
        : viewportDistances < 6
        ? kOpenHandMotion520
        : kOpenHandMotion660;
    _messagesProgrammaticScroll.begin();
    try {
      await controller.animateTo(
        target,
        duration: openHandMotionDuration(context, duration),
        curve: kOpenHandEmphasizedCurve,
      );
      return true;
    } catch (error, stack) {
      if (mounted) {
        silentLog('钉钉消息网关', '滚动至引用消息附近', error, stack);
      }
      return false;
    } finally {
      _messagesProgrammaticScroll.end();
    }
  }

  Future<void> _awaitMessageLayout() async {
    try {
      await WidgetsBinding.instance.endOfFrame.timeout(
        const Duration(milliseconds: 300),
      );
    } on TimeoutException {
      return;
    }
  }

  void _highlightMessage(String messageId) {
    final normalizedId = normalizeDingTalkMessageId(messageId);
    _quotedMessageHighlightTimer?.cancel();
    setState(() => _highlightedMessageId = normalizedId);
    _quotedMessageHighlightTimer = startSafeTimer(
      _quotedMessageHighlightDuration,
      () {
        _quotedMessageHighlightTimer = null;
        if (!mounted || _highlightedMessageId != normalizedId) return;
        setState(() => _highlightedMessageId = null);
      },
    );
  }

  void _scheduleVisibleMediaLoad(
    String conversationId,
    DingTalkGatewayMessage message,
  ) {
    if (!message.contextualMedia.any(
      (item) => item.kind.isPreviewable && item.localPath.trim().isEmpty,
    )) {
      return;
    }
    final key = '$conversationId\u0000${message.id}';
    final controller = widget.controller;
    if (_autoMediaLoadAttemptedMessageIds.contains(key) ||
        _autoMediaLoadPendingMessageIds.contains(key) ||
        controller.isMessageMediaCaching(message.id) ||
        controller.isMessageMediaHydrationFailed(message.id)) {
      return;
    }
    _autoMediaLoadPendingMessageIds.add(key);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoMediaLoadPendingMessageIds.remove(key);
      if (!mounted || _selectedId != conversationId) return;
      if (controller.isMessageMediaCaching(message.id) ||
          controller.isMessageMediaHydrationFailed(message.id)) {
        return;
      }
      _autoMediaLoadAttemptedMessageIds.add(key);
      while (_autoMediaLoadAttemptedMessageIds.length >
          _maxAutoMediaLoadAttempts) {
        _autoMediaLoadAttemptedMessageIds.remove(
          _autoMediaLoadAttemptedMessageIds.first,
        );
      }
      unawaited(
        controller.ensureMessageMediaCached(
          conversationId: conversationId,
          messageId: message.id,
        ),
      );
    });
  }

  Future<void> _loadOlderMessages(DingTalkConversation conversation) async {
    if (!widget.controller.isServiceEnabled) return;
    if (widget.controller.isLoadingOlderConversationMessages(conversation.id)) {
      return;
    }
    _disableAutoFollow();
    await widget.controller.loadOlderConversationMessages(conversation.id);
  }

  void _handleInputChanged() {
    if (!mounted || _editingConversationId == null) return;
    setState(() {});
  }

  bool _isMine(DingTalkGatewayMessage message) {
    return widget.controller.isMessageFromCurrentUser(message);
  }

  void _scheduleAutoFollow({bool force = false}) {
    final conversationId = _selectedId;
    if (conversationId == null || (!force && !_autoFollow)) return;
    if (_followConversationId != conversationId) {
      _followConversationId = conversationId;
      _followRequestVersion++;
      _followJumpToBottom = false;
    }
    if (force) _followJumpToBottom = true;
    if (_followScheduled) return;
    _followScheduled = true;
    final requestVersion = _followRequestVersion;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _followScheduled = false;
      _runAutoFollow(requestVersion, 0);
    });
  }

  void _runAutoFollow(int requestVersion, int attempt) {
    if (!mounted) return;
    if (requestVersion != _followRequestVersion) {
      _scheduleAutoFollow(force: _followJumpToBottom);
      return;
    }
    final conversationId = _followConversationId;
    if (conversationId == null || conversationId != _selectedId) {
      _scheduleAutoFollow(force: true);
      return;
    }
    final jump = _followJumpToBottom;
    if (!jump && !_autoFollow) return;
    if (!_messagesScrollController.hasClients ||
        !_messagesScrollController.position.hasContentDimensions) {
      _queueAutoFollowRetry(requestVersion, attempt);
      return;
    }
    final position = _messagesScrollController.position;
    final target = position.minScrollExtent;
    if ((target - position.pixels).abs() < 1) {
      _followJumpToBottom = false;
      return;
    }
    _followJumpToBottom = false;
    if (jump) {
      _messagesProgrammaticScroll.begin();
      try {
        position.jumpTo(target);
      } finally {
        _messagesProgrammaticScroll.end();
      }
      _queueAutoFollowRetry(requestVersion, attempt);
      return;
    }
    _messagesProgrammaticScroll.begin();
    try {
      position.jumpTo(target);
    } finally {
      _messagesProgrammaticScroll.end();
    }
  }

  void _queueAutoFollowRetry(int requestVersion, int attempt) {
    if (!mounted || requestVersion != _followRequestVersion) {
      return;
    }
    if (attempt >= 3) {
      _followJumpToBottom = false;
      return;
    }
    _followScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _followScheduled = false;
      if (!mounted) return;
      if (requestVersion != _followRequestVersion) {
        _scheduleAutoFollow(force: _followJumpToBottom);
        return;
      }
      _runAutoFollow(requestVersion, attempt + 1);
    });
  }

  Widget _buildSendButton(DingTalkConversation conversation) {
    final responding = widget.controller.isConversationResponding(
      conversation.id,
    );
    final enabled =
        widget.controller.isServiceEnabled &&
        (responding || (!_attachmentBusy && !widget.controller.isSending));
    return SizedBox(
      width: 124,
      height: 48,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          minimumSize: const Size(124, 48),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        onPressed: !enabled
            ? null
            : responding
            ? () => unawaited(
                widget.controller.stopConversationResponse(conversation.id),
              )
            : () => _sendOrStop(conversation),
        icon: AnimatedSwitcher(
          duration: openHandMotionDuration(context, kOpenHandMotion180),
          child: Icon(
            responding ? Icons.stop_rounded : Icons.arrow_upward_rounded,
            key: ValueKey<bool>(responding),
          ),
        ),
        label: AnimatedSwitcher(
          duration: openHandMotionDuration(context, kOpenHandMotion180),
          child: Text(
            responding ? '停止响应' : '普通发送',
            key: ValueKey<bool>(responding),
          ),
        ),
      ),
    );
  }

  Widget _buildFileButton(DingTalkConversation conversation) {
    final enabled =
        widget.controller.isServiceEnabled &&
        !_attachmentBusy &&
        !widget.controller.isSending &&
        !widget.controller.isConversationResponding(conversation.id);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _input,
      builder: (context, value, _) {
        final adding =
            value.text.trim().isNotEmpty || _pendingAttachments.isNotEmpty;
        return Tooltip(
          message: _attachmentBusy
              ? '正在读取附件'
              : adding
              ? '添加附件'
              : '发送文件',
          child: SizedBox(
            width: _composerIconButtonSize,
            height: _composerIconButtonSize,
            child: FilledButton(
              style: _composerIconButtonStyle(),
              onPressed: enabled
                  ? () => unawaited(_handleFileButton(conversation, adding))
                  : null,
              child: AnimatedSwitcher(
                duration: openHandMotionDuration(context, kOpenHandMotion180),
                child: _attachmentBusy
                    ? const SizedBox(
                        key: ValueKey<String>('attachment-loading'),
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        adding ? Icons.add_rounded : Icons.attach_file_rounded,
                        key: ValueKey<bool>(adding),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildVoiceButton(DingTalkConversation conversation) {
    final enabled =
        widget.controller.isServiceEnabled &&
        !widget.controller.isSending &&
        !widget.controller.isConversationResponding(conversation.id);
    return Tooltip(
      message: '发送语音',
      child: SizedBox(
        width: _composerIconButtonSize,
        height: _composerIconButtonSize,
        child: FilledButton(
          style: _composerIconButtonStyle(),
          onPressed: enabled
              ? () => unawaited(_startVoiceRecording(conversation))
              : null,
          child: const Icon(Icons.mic_none_rounded),
        ),
      ),
    );
  }

  Widget _buildForceResponseButton(DingTalkConversation conversation) {
    final loadingHistory = widget.controller.isRefreshingConversationMessages(
      conversation.id,
    );
    final queuePaused = widget.controller.isResponseQueuePaused(
      conversation.id,
    );
    final enabled =
        widget.controller.isServiceEnabled &&
        !_attachmentBusy &&
        !loadingHistory &&
        !queuePaused &&
        !widget.controller.isSending &&
        !widget.controller.isConversationResponding(conversation.id);
    return Tooltip(
      message: loadingHistory
          ? '正在同步会话历史消息'
          : queuePaused
          ? '请从等待队列选择响应起点'
          : '强制响应历史消息',
      child: SizedBox(
        width: _composerIconButtonSize,
        height: _composerIconButtonSize,
        child: FilledButton.tonal(
          style: _composerIconButtonStyle(),
          onPressed: enabled ? () => _forceRespond(conversation) : null,
          child: AnimatedSwitcher(
            duration: openHandMotionDuration(context, kOpenHandMotion180),
            child: loadingHistory
                ? const SizedBox(
                    key: ValueKey<String>('force-response-history-loading'),
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(
                    Icons.auto_awesome_rounded,
                    key: ValueKey<String>('force-response-ready'),
                  ),
          ),
        ),
      ),
    );
  }

  ButtonStyle _composerButtonStyle() {
    return FilledButton.styleFrom(
      minimumSize: const Size(124, 48),
      padding: const EdgeInsets.symmetric(horizontal: 12),
    );
  }

  ButtonStyle _composerIconButtonStyle() {
    return FilledButton.styleFrom(
      minimumSize: const Size.square(_composerIconButtonSize),
      fixedSize: const Size.square(_composerIconButtonSize),
      padding: EdgeInsets.zero,
      shape: const CircleBorder(),
    );
  }

  Widget _buildVoiceCancelButton() {
    return SizedBox(
      width: 108,
      height: 48,
      child: FilledButton.tonalIcon(
        style: FilledButton.styleFrom(
          minimumSize: const Size(108, 48),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        onPressed: _voiceControlBusy ? null : _cancelVoiceRecording,
        icon: const Icon(Icons.close_rounded),
        label: const Text('取消录制'),
      ),
    );
  }

  Widget _buildVoicePauseButton() {
    return SizedBox(
      width: 108,
      height: 48,
      child: FilledButton.tonalIcon(
        style: FilledButton.styleFrom(
          minimumSize: const Size(108, 48),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        onPressed: !_voiceRecorderStarted || _voiceControlBusy
            ? null
            : () => unawaited(_toggleVoicePause()),
        icon: Icon(
          _voicePaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
        ),
        label: Text(_voicePaused ? '继续录制' : '暂停录制'),
      ),
    );
  }

  Widget _buildVoiceSendButton() {
    return SizedBox(
      width: 124,
      height: 48,
      child: FilledButton.icon(
        style: _composerButtonStyle(),
        onPressed: !_voiceRecorderStarted || _voiceControlBusy
            ? null
            : () => unawaited(_finishVoiceRecording()),
        icon: _voiceControlBusy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.send_rounded),
        label: Text(_voiceControlBusy ? '正在发送' : '停止并发送'),
      ),
    );
  }

  Future<void> _handleFileButton(
    DingTalkConversation conversation,
    bool adding,
  ) async {
    if (_attachmentBusy || !mounted || !widget.controller.isServiceEnabled) {
      return;
    }
    setState(() => _attachmentBusy = true);
    try {
      final picked = await openFiles();
      if (!mounted || !widget.controller.isServiceEnabled || picked.isEmpty) {
        return;
      }
      final selection = await _prepareAttachmentSelection(
        picked.map((file) => file.path),
        existingPaths: adding
            ? _pendingAttachments.map((item) => item.path).toSet()
            : const <String>{},
      );
      if (!mounted) return;
      _showAttachmentSelectionNotices(selection);
      if (selection.attachments.isEmpty) return;
      final shouldAttach =
          adding ||
          _input.text.trim().isNotEmpty ||
          _pendingAttachments.isNotEmpty;
      if (shouldAttach) {
        setState(() {
          _pendingAttachments = <_DingTalkPendingAttachment>[
            ..._pendingAttachments,
            ...selection.attachments,
          ];
        });
        _schedulePastedAttachmentCachePrune();
        return;
      }
      final success = await widget.controller.sendMessageWithAttachments(
        conversation.id,
        '',
        selection.attachments.map((item) => item.path),
      );
      if (!success && mounted) {
        showOpenHandErrorSnack(
          context,
          widget.controller.errorMessage ?? '文件发送失败，请稍后重试。',
        );
      }
    } catch (error, stack) {
      silentLog('dingtalk_gateway', '选择钉钉发送文件', error, stack);
      if (mounted) showOpenHandErrorSnack(context, '选择文件失败：$error');
    } finally {
      if (mounted) setState(() => _attachmentBusy = false);
    }
  }

  Future<String> _writePastedDingTalkImage(
    List<int> bytes, {
    required String extension,
  }) async {
    final directory = Directory(
      p.join(
        OpenHandPaths.defaultMessageGatewayDirectoryPath(),
        'dingtalk_pasted',
      ),
    );
    await createDirectoryBounded(directory);
    final path = p.join(
      directory.path,
      _nextDingTalkTemporaryFileName(
        'pasted',
        _normalizeDingTalkImageExtension(extension),
      ),
    );
    await writeTemporaryFileBytesBounded(
      File(path),
      bytes,
      timeout: _clipboardImageWriteTimeout,
      onSecondaryError: (error, stack) =>
          silentLog('dingtalk_gateway', '清理钉钉剪贴板图片', error, stack),
    );
    return path;
  }

  Future<_DingTalkAttachmentSelection> _prepareAttachmentSelection(
    Iterable<String> rawPaths, {
    required Set<String> existingPaths,
    bool editImages = true,
  }) async {
    final attachments = <_DingTalkPendingAttachment>[];
    final seen = <String>{...existingPaths};
    var limitSkipped = 0;
    var invalid = 0;
    var oversized = 0;
    for (final rawPath in rawPaths) {
      final path = rawPath.trim();
      if (path.isEmpty || !seen.add(path)) continue;
      if (attachments.length + existingPaths.length >=
          kDingTalkMessageAttachmentLimit) {
        limitSkipped += 1;
        continue;
      }
      var resolvedPath = path;
      var displayName = p.basename(path).trim().isEmpty
          ? '文件'
          : p.basename(path);
      final isImage =
          DingTalkMediaKindX.fromFileName(displayName) ==
          DingTalkMediaKind.image;
      if (editImages && isImage) {
        try {
          final bytes = await readBoundedFileBytes(
            File(path),
            maxBytes: kImageEditorSourceMaxBytes,
            idleTimeout: defaultBoundedFileReadIdleTimeout,
            totalTimeout: defaultBoundedFileReadTotalTimeout,
          );
          if (!mounted) {
            return _DingTalkAttachmentSelection(attachments: attachments);
          }
          final edited = await showImageEditorDialog(
            context,
            imageBytes: bytes,
            imageSizeLimitBytes: context
                .read<SettingsController>()
                .aiImageSizeLimitBytes,
          );
          if (!mounted) {
            return _DingTalkAttachmentSelection(attachments: attachments);
          }
          if (edited == null) continue;
          resolvedPath = await _writePastedDingTalkImage(
            edited.bytes,
            extension: edited.format,
          );
          if (!mounted) {
            await _deletePastedAttachmentFile(resolvedPath);
            return _DingTalkAttachmentSelection(attachments: attachments);
          }
          final basename = p.basenameWithoutExtension(displayName).trim();
          displayName =
              '${basename.isEmpty ? '图片' : basename}.${_normalizeDingTalkImageExtension(edited.format)}';
        } on BoundedFileReadException catch (error, stack) {
          silentLog('dingtalk_gateway', '读取待编辑钉钉图片', error, stack);
        } catch (error, stack) {
          silentLog('dingtalk_gateway', '编辑钉钉图片附件', error, stack);
        }
      }
      try {
        final file = File(resolvedPath);
        final stat = await file.stat().timeout(
          defaultBoundedFileReadIdleTimeout,
        );
        if (stat.type != FileSystemEntityType.file || stat.size <= 0) {
          invalid += 1;
          if (resolvedPath != path) {
            await _deletePastedAttachmentFile(resolvedPath);
          }
          continue;
        }
        if (stat.size > kDingTalkMessageAttachmentMaxBytes) {
          oversized += 1;
          if (resolvedPath != path) {
            await _deletePastedAttachmentFile(resolvedPath);
          }
          continue;
        }
        attachments.add(
          _DingTalkPendingAttachment(
            path: resolvedPath,
            name: displayName,
            sizeBytes: stat.size,
          ),
        );
      } catch (error, stack) {
        invalid += 1;
        if (resolvedPath != path) {
          await _deletePastedAttachmentFile(resolvedPath);
        }
        silentLog('dingtalk_gateway', '读取钉钉附件', error, stack);
      }
    }
    return _DingTalkAttachmentSelection(
      attachments: attachments,
      limitSkipped: limitSkipped,
      invalid: invalid,
      oversized: oversized,
    );
  }

  void _showAttachmentSelectionNotices(_DingTalkAttachmentSelection selection) {
    if (!mounted || !selection.hasNotices) return;
    final notices = <String>[];
    if (selection.limitSkipped > 0) {
      notices.add(
        '单条消息最多添加 $kDingTalkMessageAttachmentLimit 个附件，已忽略 ${selection.limitSkipped} 个。',
      );
    }
    if (selection.oversized > 0) {
      notices.add('已忽略 ${selection.oversized} 个超过 512MB 上限的附件。');
    }
    if (selection.invalid > 0) {
      notices.add('已忽略 ${selection.invalid} 个空文件、目录或无法读取的附件。');
    }
    showOpenHandInfoSnack(context, notices.join('\n'), maxLines: 3);
  }

  void _removePendingAttachment(String path) {
    if (_attachmentBusy) return;
    setState(() {
      _pendingAttachments = _pendingAttachments
          .where((item) => item.path != path)
          .toList(growable: false);
    });
  }

  KeyEventResult _handleInputKeyEvent(FocusNode node, KeyEvent event) {
    if (!mounted ||
        event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.keyV) {
      return KeyEventResult.ignored;
    }
    final hardware = HardwareKeyboard.instance;
    final modifier = Platform.isMacOS
        ? hardware.isMetaPressed
        : hardware.isControlPressed;
    if (modifier && !hardware.isShiftPressed && !hardware.isAltPressed) {
      unawaited(_tryPasteAttachmentsFromClipboard());
    }
    return KeyEventResult.ignored;
  }

  Future<void> _tryPasteAttachmentsFromClipboard() async {
    if (_attachmentBusy || !mounted) return;
    final conversationId = _selectedId;
    final existingPaths = _pendingAttachments.map((item) => item.path).toSet();
    setState(() => _attachmentBusy = true);
    try {
      List<String> paths = const <String>[];
      try {
        paths = await getOpenHandClipboardFiles(
          timeout: _clipboardAttachmentReadTimeout,
        );
      } catch (error, stack) {
        silentLog('dingtalk_gateway', '读取钉钉剪贴板文件', error, stack);
      }
      if (!mounted || _selectedId != conversationId) return;
      if (paths.isNotEmpty) {
        final selection = await _prepareAttachmentSelection(
          paths,
          existingPaths: existingPaths,
        );
        if (!mounted || _selectedId != conversationId) return;
        _showAttachmentSelectionNotices(selection);
        if (selection.attachments.isNotEmpty) {
          setState(() {
            _pendingAttachments = <_DingTalkPendingAttachment>[
              ..._pendingAttachments,
              ...selection.attachments,
            ];
          });
          _schedulePastedAttachmentCachePrune();
        }
        return;
      }

      if (_pendingAttachments.length >= kDingTalkMessageAttachmentLimit) {
        _showAttachmentSelectionNotices(
          const _DingTalkAttachmentSelection(
            attachments: <_DingTalkPendingAttachment>[],
            limitSkipped: 1,
          ),
        );
        return;
      }

      Uint8List? imageBytes;
      try {
        imageBytes = await getOpenHandClipboardImage(
          timeout: _clipboardImageReadTimeout,
        );
      } catch (error, stack) {
        silentLog('dingtalk_gateway', '读取钉钉剪贴板图片', error, stack);
        return;
      }
      if (!mounted ||
          _selectedId != conversationId ||
          imageBytes == null ||
          imageBytes.isEmpty) {
        return;
      }
      if (imageBytes.lengthInBytes > kDingTalkMessageAttachmentMaxBytes) {
        _showAttachmentSelectionNotices(
          const _DingTalkAttachmentSelection(
            attachments: <_DingTalkPendingAttachment>[],
            oversized: 1,
          ),
        );
        return;
      }

      final edited = await showImageEditorDialog(
        context,
        imageBytes: imageBytes,
        imageSizeLimitBytes: context
            .read<SettingsController>()
            .aiImageSizeLimitBytes,
      );
      if (!mounted || _selectedId != conversationId || edited == null) return;
      if (edited.bytes.lengthInBytes > kDingTalkMessageAttachmentMaxBytes) {
        _showAttachmentSelectionNotices(
          const _DingTalkAttachmentSelection(
            attachments: <_DingTalkPendingAttachment>[],
            oversized: 1,
          ),
        );
        return;
      }
      String pastedPath;
      try {
        pastedPath = await _writePastedDingTalkImage(
          edited.bytes,
          extension: edited.format,
        );
      } catch (error, stack) {
        silentLog('dingtalk_gateway', '写入钉钉剪贴板图片', error, stack);
        return;
      }
      if (!mounted || _selectedId != conversationId) {
        await _deletePastedAttachmentFile(pastedPath);
        return;
      }
      final selection = await _prepareAttachmentSelection(
        <String>[pastedPath],
        existingPaths: existingPaths,
        editImages: false,
      );
      if (!mounted || _selectedId != conversationId) {
        await _deletePastedAttachmentFile(pastedPath);
        return;
      }
      _showAttachmentSelectionNotices(selection);
      if (selection.attachments.isEmpty) {
        await _deletePastedAttachmentFile(pastedPath);
        return;
      }
      setState(() {
        _pendingAttachments = <_DingTalkPendingAttachment>[
          ..._pendingAttachments,
          ...selection.attachments,
        ];
      });
      _schedulePastedAttachmentCachePrune();
    } catch (error, stack) {
      silentLog('dingtalk_gateway', '读取钉钉剪贴板附件', error, stack);
    } finally {
      if (mounted) setState(() => _attachmentBusy = false);
    }
  }

  Future<void> _deletePastedAttachmentFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists().timeout(_pastedAttachmentCacheOperationTimeout)) {
        await file.delete().timeout(_pastedAttachmentCacheOperationTimeout);
      }
    } catch (error, stack) {
      silentLog('dingtalk_gateway', '删除钉钉剪贴板图片附件', error, stack);
    }
  }

  void _schedulePastedAttachmentCachePrune() {
    unawaited(_pastedAttachmentPruneQueue.enqueue(_prunePastedAttachmentCache));
  }

  Future<void> _prunePastedAttachmentCache() async {
    final directory = Directory(
      p.join(
        OpenHandPaths.defaultMessageGatewayDirectoryPath(),
        'dingtalk_pasted',
      ),
    );
    final protectedPaths = _pendingAttachments
        .map((item) => p.normalize(p.absolute(item.path)))
        .toSet();
    final files = <File>[];
    try {
      final listing = await listDirectoryBounded(
        directory,
        maxEntries: _maxPastedAttachmentCacheFiles * 4,
      );
      for (final entity in listing.entries) {
        if (entity is! File || !p.basename(entity.path).startsWith('pasted-')) {
          continue;
        }
        final path = p.normalize(p.absolute(entity.path));
        if (!protectedPaths.contains(path)) files.add(entity);
      }
      if (files.length <= _maxPastedAttachmentCacheFiles) return;
      files.sort((a, b) => a.path.compareTo(b.path));
      final removeCount = files.length - _maxPastedAttachmentCacheFiles;
      for (var index = 0; index < removeCount; index++) {
        try {
          await files[index].delete().timeout(
            _pastedAttachmentCacheOperationTimeout,
          );
        } catch (error, stack) {
          silentLog('dingtalk_gateway', '清理钉钉剪贴板图片缓存', error, stack);
        }
      }
    } catch (error, stack) {
      silentLog('dingtalk_gateway', '扫描钉钉剪贴板图片缓存', error, stack);
    }
  }

  Future<void> _startVoiceRecording(DingTalkConversation conversation) async {
    if (!widget.controller.isServiceEnabled) return;
    if (_recordingVoice || !mounted) return;
    final recorder = AudioRecorder();
    _resetVoiceVisual();
    setState(() {
      _recordingVoice = true;
      _voiceRecorder = recorder;
      _voiceRecorderStarted = false;
      _voicePaused = false;
      _voiceControlBusy = false;
      _voiceConversationId = conversation.id;
    });
    try {
      if (!await _runVoiceOperation(recorder.hasPermission(), '检查麦克风权限')) {
        throw StateError('未获得麦克风权限，请在系统设置中允许 OpenHand 使用麦克风。');
      }
      if (!mounted || !identical(_voiceRecorder, recorder)) {
        await _cancelAndDisposeRecorder(recorder);
        return;
      }
      final directory = Directory(
        p.join(OpenHandPaths.defaultCacheDirectoryPath(), 'dingtalk_voice'),
      );
      await createDirectoryBounded(directory);
      if (!mounted || !identical(_voiceRecorder, recorder)) {
        await _cancelAndDisposeRecorder(recorder);
        return;
      }
      final path = p.join(
        directory.path,
        _nextDingTalkTemporaryFileName('voice', 'm4a'),
      );
      await _runVoiceOperation(
        recorder.start(
          const RecordConfig(
            bitRate: 64000,
            sampleRate: 16000,
            numChannels: 1,
            noiseSuppress: true,
            echoCancel: true,
          ),
          path: path,
        ),
        '启动录音',
      );
      if (!mounted || !identical(_voiceRecorder, recorder)) {
        await _cancelAndDisposeRecorder(recorder);
        return;
      }
      _voicePath = path;
      _voiceRecorderStarted = true;
      _voicePaused = false;
      _voiceElapsed = Duration.zero;
      _voiceSegmentStartedAt = DateTime.now();
      unawaited(_cancelVoiceAmplitudeSubscription());
      _voiceAmplitudeSubscription = recorder
          .onAmplitudeChanged(const Duration(milliseconds: 120))
          .listen(
            (amplitude) {
              if (!mounted || !identical(_voiceRecorder, recorder)) return;
              final level = _voiceLevelFromAmplitude(amplitude);
              // 仅移动元素，避免对来源不明的定长列表执行 removeAt/add。
              for (var index = 1; index < _voiceLevels.length; index++) {
                _voiceLevels[index - 1] = _voiceLevels[index];
              }
              _voiceLevels[_voiceLevels.length - 1] = level;
              _publishVoiceVisual();
            },
            onError: (Object error, StackTrace stack) {
              silentLog('dingtalk_gateway', '读取钉钉语音波形', error, stack);
            },
          );
      _startVoiceVisualTicker();
      if (mounted) setState(() {});
    } catch (error, stack) {
      silentLog('dingtalk_gateway', '录制钉钉语音', error, stack);
      _voiceVisualTimer?.cancel();
      _voiceVisualTimer = null;
      await _cancelVoiceAmplitudeSubscription();
      await _cancelAndDisposeRecorder(recorder);
      if (!identical(_voiceRecorder, recorder)) return;
      if (mounted) {
        setState(() {
          _recordingVoice = false;
          _voiceRecorder = null;
          _voiceRecorderStarted = false;
          _voicePaused = false;
          _voiceControlBusy = false;
          _voiceSegmentStartedAt = null;
          _voicePath = null;
          _voiceConversationId = null;
        });
        _resetVoiceVisual();
        showOpenHandErrorSnack(context, '$error');
      }
    }
  }

  void _startVoiceVisualTicker() {
    _voiceVisualTimer?.cancel();
    _voiceVisualTimer = startNonOverlappingPeriodicTimer(
      _voiceVisualInterval,
      (_) {
        if (!mounted || !_recordingVoice) return;
        _publishVoiceVisual();
        if (_currentVoiceElapsed() >= _maxVoiceDuration &&
            !_voiceControlBusy &&
            _voiceRecorderStarted) {
          unawaited(_finishVoiceRecording());
        }
      },
      min: _voiceVisualInterval,
      callbackTimeout: const Duration(seconds: 5),
      onError: (error, stack) =>
          silentLog('dingtalk_gateway_ui', '刷新语音波形', error, stack),
    );
    _publishVoiceVisual();
  }

  Duration _currentVoiceElapsed() {
    final segmentStartedAt = _voiceSegmentStartedAt;
    if (segmentStartedAt == null || _voicePaused) return _voiceElapsed;
    return _voiceElapsed + DateTime.now().difference(segmentStartedAt);
  }

  double _voiceLevelFromAmplitude(Amplitude amplitude) {
    final current = amplitude.current.isFinite ? amplitude.current : -60.0;
    return ((current + 60) / 60).clamp(0.08, 1.0).toDouble();
  }

  void _publishVoiceVisual() {
    final elapsed = _currentVoiceElapsed();
    _voiceVisual.value = _DingTalkVoiceVisualState(
      elapsed: elapsed,
      levels: List<double>.unmodifiable(_voiceLevels),
      ready: _voiceRecorderStarted,
      paused: _voicePaused,
    );
  }

  void _resetVoiceVisual() {
    _voiceElapsed = Duration.zero;
    _voiceSegmentStartedAt = null;
    _voicePaused = false;
    for (var index = 0; index < _voiceLevels.length; index++) {
      _voiceLevels[index] = 0.08;
    }
    _voiceVisual.value = _DingTalkVoiceVisualState.initial;
  }

  Future<void> _toggleVoicePause() async {
    final recorder = _voiceRecorder;
    if (recorder == null || !_voiceRecorderStarted || _voiceControlBusy) {
      return;
    }
    if (mounted) setState(() => _voiceControlBusy = true);
    try {
      if (_voicePaused) {
        await _runVoiceOperation(recorder.resume(), '继续录音');
        _voiceSegmentStartedAt = DateTime.now();
        _voicePaused = false;
      } else {
        final elapsed = _currentVoiceElapsed();
        await _runVoiceOperation(recorder.pause(), '暂停录音');
        _voiceElapsed = elapsed;
        _voiceSegmentStartedAt = null;
        _voicePaused = true;
      }
      _publishVoiceVisual();
    } catch (error, stack) {
      silentLog('dingtalk_gateway', '暂停或继续钉钉语音', error, stack);
      if (mounted) showOpenHandErrorSnack(context, '调整录音状态失败：$error');
    } finally {
      if (mounted) setState(() => _voiceControlBusy = false);
    }
  }

  Future<void> _finishVoiceRecording() async {
    if (!widget.controller.isServiceEnabled) {
      _cancelVoiceRecording();
      return;
    }
    final recorder = _voiceRecorder;
    if (recorder == null || !_voiceRecorderStarted || _voiceControlBusy) {
      return;
    }
    if (mounted) setState(() => _voiceControlBusy = true);
    _voiceVisualTimer?.cancel();
    _voiceVisualTimer = null;
    await _cancelVoiceAmplitudeSubscription();
    final conversationId = _voiceConversationId;
    final fallbackPath = _voicePath;
    try {
      String? recordedPath;
      try {
        recordedPath =
            await _runVoiceOperation(recorder.stop(), '停止录音') ?? fallbackPath;
      } finally {
        await _disposeVoiceRecorder(recorder);
      }
      if (conversationId == null || recordedPath == null) return;
      final file = File(recordedPath);
      if (!await _pathExistsBounded(file) ||
          await file.length().timeout(defaultBoundedFileReadIdleTimeout) <= 0) {
        if (mounted) showOpenHandErrorSnack(context, '没有录到有效语音内容。');
        return;
      }
      if (!mounted || !identical(_voiceRecorder, recorder)) return;
      await widget.controller.sendAudio(conversationId, recordedPath);
    } catch (error, stack) {
      silentLog('dingtalk_gateway', '发送录制语音', error, stack);
      if (mounted) showOpenHandErrorSnack(context, '发送语音失败：$error');
    } finally {
      _voiceRecorder = null;
      _voiceRecorderStarted = false;
      _voicePaused = false;
      _voiceControlBusy = false;
      _voicePath = null;
      _voiceConversationId = null;
      _voiceSegmentStartedAt = null;
      if (mounted) {
        setState(() => _recordingVoice = false);
        _resetVoiceVisual();
      }
    }
  }

  void _cancelVoiceRecording() {
    final recorder = _voiceRecorder;
    _voiceVisualTimer?.cancel();
    _voiceVisualTimer = null;
    unawaited(_cancelVoiceAmplitudeSubscription());
    _voiceRecorder = null;
    _voiceRecorderStarted = false;
    _voicePaused = false;
    _voiceControlBusy = false;
    _voicePath = null;
    _voiceConversationId = null;
    _voiceSegmentStartedAt = null;
    if (mounted) setState(() => _recordingVoice = false);
    _resetVoiceVisual();
    if (recorder != null) {
      unawaited(_cancelAndDisposeRecorder(recorder));
    }
  }

  Future<void> _cancelAndDisposeRecorder(AudioRecorder recorder) async {
    await runAsyncCleanupBounded(
      recorder.cancel,
      timeout: _voiceCleanupTimeout,
      onError: (error, stack) =>
          silentLog('dingtalk_gateway', '取消钉钉语音录制', error, stack),
    );
    await _disposeVoiceRecorder(recorder);
  }

  Future<void> _disposeVoiceRecorder(AudioRecorder recorder) async {
    await runAsyncCleanupBounded(
      recorder.dispose,
      timeout: _voiceCleanupTimeout,
      onError: (error, stack) =>
          silentLog('dingtalk_gateway', '释放钉钉语音录音器', error, stack),
    );
  }

  Future<void> _cancelVoiceAmplitudeSubscription() async {
    final subscription = _voiceAmplitudeSubscription;
    _voiceAmplitudeSubscription = null;
    await cancelStreamSubscriptionBounded<Amplitude>(
      subscription,
      timeout: _voiceCleanupTimeout,
      onError: (error, stack) =>
          silentLog('dingtalk_gateway', '取消钉钉语音波形订阅', error, stack),
    );
  }

  Future<T> _runVoiceOperation<T>(Future<T> operation, String action) {
    return operation.timeout(
      _voiceOperationTimeout,
      onTimeout: () => throw StateError('$action超时，请重试。'),
    );
  }

  void _sendOrStop(DingTalkConversation conversation) {
    if (!widget.controller.isServiceEnabled) return;
    if (widget.controller.isConversationResponding(conversation.id)) {
      unawaited(widget.controller.stopConversationResponse(conversation.id));
      return;
    }
    final text = _input.text.trim();
    final attachments = List<_DingTalkPendingAttachment>.from(
      _pendingAttachments,
    );
    if (text.isEmpty && attachments.isEmpty) return;
    _input.clear();
    setState(() => _pendingAttachments = const <_DingTalkPendingAttachment>[]);
    unawaited(
      widget.controller
          .sendMessageWithAttachments(
            conversation.id,
            text,
            attachments.map((item) => item.path),
          )
          .then((success) {
            if (!success && mounted && _selectedId == conversation.id) {
              showOpenHandErrorSnack(
                context,
                widget.controller.errorMessage ?? '消息发送失败，请稍后重试。',
              );
            }
          }),
    );
  }

  void _forceRespond(DingTalkConversation conversation) {
    if (!widget.controller.isServiceEnabled) return;
    final accepted = widget.controller.forceRespondToConversation(
      conversation.id,
    );
    if (!accepted && mounted) {
      showOpenHandErrorSnack(context, '当前会话没有可供强制响应的历史消息，或正在处理其他请求。');
    }
  }

  Future<void> _showConversationMenu(
    BuildContext itemContext,
    DingTalkConversation conversation,
  ) async {
    if (!widget.controller.isServiceEnabled) return;
    final isGroup = conversation.type == DingTalkConversationType.group;
    final detailsLabel = openHandLocalizedText(
      context,
      zh: isGroup ? '群聊详情' : '联系人详情',
      zhHant: isGroup ? '群聊詳情' : '聯絡人詳情',
      en: isGroup ? 'Group details' : 'Contact details',
      fr: isGroup ? 'Détails du groupe' : 'Détails du contact',
      de: isGroup ? 'Gruppendetails' : 'Kontaktdetails',
      ja: isGroup ? 'グループ詳細' : '連絡先の詳細',
    );
    final action =
        await showAnimatedAnchoredPopupMenu<_DingTalkConversationMenuAction>(
          context: itemContext,
          position: PopupMenuPosition.under,
          items: [
            PopupMenuItem(
              value: _DingTalkConversationMenuAction.details,
              child: ListTile(
                dense: true,
                leading: Icon(
                  isGroup ? Icons.groups_rounded : Icons.person_rounded,
                ),
                title: Text(detailsLabel),
              ),
            ),
            PopupMenuItem(
              value: _DingTalkConversationMenuAction.delete,
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.delete_outline_rounded),
                title: Text(
                  '删除会话',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          ],
        );
    if (!mounted || action == null) return;
    if (action == _DingTalkConversationMenuAction.details) {
      await _showConversationDetails(conversation);
      return;
    }
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: '删除本地会话',
      message: '仅从 OpenHand 移除“${conversation.title}”，不会删除钉钉群聊或联系人。',
      confirmLabel: '确认删除',
      destructive: true,
      icon: const Icon(Icons.delete_outline_rounded),
    );
    if (!confirmed || !mounted) return;
    await widget.controller.deleteConversation(conversation.id);
    if (!mounted) return;
    final next = widget.controller.conversations.firstOrNull;
    setState(() {
      _selectedId = next?.id;
      _input.clear();
      _pendingAttachments = const <_DingTalkPendingAttachment>[];
    });
  }

  Future<void> _showConversationDetails(
    DingTalkConversation conversation,
  ) async {
    if (!widget.controller.isServiceEnabled) return;
    await showAnimatedDialog<void>(
      context: context,
      builder: (_) => _DingTalkConversationDetailsDialog(
        controller: widget.controller,
        conversation: conversation,
      ),
    );
  }

  Future<void> _addConversation() async {
    if (!widget.controller.isServiceEnabled) return;
    final target = await showAnimatedDialog<DingTalkConversationTarget>(
      context: context,
      builder: (_) => buildOpenHandDialog(
        maxWidth: kOpenHandDialogWidthStandard,
        maxHeight: kOpenHandDialogHeightStandard,
        child: _DingTalkAddConversationDialog(controller: widget.controller),
      ),
    );
    if (target == null || !mounted) return;
    widget.controller.openConversation(target);
    setState(() => _selectedId = target.id);
  }
}

class _DingTalkPendingAttachment {
  const _DingTalkPendingAttachment({
    required this.path,
    required this.name,
    required this.sizeBytes,
  });

  final String path;
  final String name;
  final int sizeBytes;
}

class _DingTalkAttachmentSelection {
  const _DingTalkAttachmentSelection({
    required this.attachments,
    this.limitSkipped = 0,
    this.invalid = 0,
    this.oversized = 0,
  });

  final List<_DingTalkPendingAttachment> attachments;
  final int limitSkipped;
  final int invalid;
  final int oversized;

  bool get hasNotices => limitSkipped > 0 || invalid > 0 || oversized > 0;
}

IconData _dingtalkAttachmentIcon(String name) {
  return switch (DingTalkMediaKindX.fromFileName(name)) {
    DingTalkMediaKind.image => Icons.image_outlined,
    DingTalkMediaKind.video => Icons.videocam_outlined,
    DingTalkMediaKind.audio => Icons.audiotrack_outlined,
    DingTalkMediaKind.file => Icons.insert_drive_file_outlined,
  };
}

String _normalizeDingTalkImageExtension(String value) {
  return switch (value.trim().toLowerCase()) {
    'jpg' || 'jpeg' || 'webp' || 'gif' || 'png' => value.trim().toLowerCase(),
    _ => 'png',
  };
}

class _DingTalkPendingAttachmentChip extends StatelessWidget {
  const _DingTalkPendingAttachmentChip({
    required this.attachment,
    required this.onRemove,
    this.onTap,
  });

  final _DingTalkPendingAttachment attachment;
  final VoidCallback onRemove;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final kind = DingTalkMediaKindX.fromFileName(attachment.name);
    if (kind == DingTalkMediaKind.image) {
      return Tooltip(
        message: '${attachment.name} · ${formatByteSize(attachment.sizeBytes)}',
        child: SizedBox(
          width: 64,
          height: 64,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: OpenHandTapRegion(
                  onTap: onTap,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest,
                      borderRadius: kOpenHandBorderRadius12,
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(kOpenHandRadius11),
                      child: Image.file(
                        File(attachment.path),
                        fit: BoxFit.cover,
                        cacheWidth: 192,
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) => Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            size: 24,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: _DingTalkAttachmentRemoveButton(onRemove: onRemove),
              ),
            ],
          ),
        ),
      );
    }
    return OpenHandTapRegion(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: kOpenHandBorderRadius16,
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _dingtalkAttachmentIcon(attachment.name),
              size: 16,
              color: colors.onSurfaceVariant,
            ),
            kOpenHandHGap8,
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Text(
                '${attachment.name} · ${formatByteSize(attachment.sizeBytes)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurface),
              ),
            ),
            kOpenHandHGap8,
            InkWell(
              onTap: onRemove,
              borderRadius: kOpenHandBorderRadius8,
              child: Icon(
                Icons.close_rounded,
                size: 16,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DingTalkAttachmentRemoveButton extends StatelessWidget {
  const _DingTalkAttachmentRemoveButton({required this.onRemove});

  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return OpenHandTapRegion(
      onTap: onRemove,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: colors.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            Icons.close_rounded,
            size: 14,
            color: colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

enum _DingTalkConversationMenuAction { details, delete }

class _DingTalkVoiceVisualState {
  const _DingTalkVoiceVisualState({
    required this.elapsed,
    required this.levels,
    required this.ready,
    required this.paused,
  });

  static const _DingTalkVoiceVisualState initial = _DingTalkVoiceVisualState(
    elapsed: Duration.zero,
    levels: <double>[],
    ready: false,
    paused: false,
  );

  final Duration elapsed;
  final List<double> levels;
  final bool ready;
  final bool paused;
}

class _DingTalkVoiceRecordingPanel extends StatelessWidget {
  const _DingTalkVoiceRecordingPanel({
    required this.visual,
    required this.maxDuration,
  });

  final _DingTalkVoiceVisualState visual;
  final Duration maxDuration;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status = !visual.ready
        ? '正在准备麦克风…'
        : visual.paused
        ? '录音已暂停'
        : '正在录制语音';
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: colors.errorContainer.withValues(alpha: 0.58),
        borderRadius: kOpenHandBorderRadius16,
        border: Border.all(color: colors.error.withValues(alpha: 0.42)),
      ),
      child: Row(
        children: [
          Icon(
            visual.paused ? Icons.pause_circle_rounded : Icons.mic_rounded,
            size: 22,
            color: colors.error,
          ),
          kOpenHandHGap10,
          SizedBox(
            width: 92,
            child: Text(
              status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colors.onErrorContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          kOpenHandHGap10,
          Expanded(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _DingTalkVoiceWavePainter(
                  levels: visual.levels,
                  color: colors.error,
                  trackColor: colors.error.withValues(alpha: 0.2),
                ),
                size: const Size(double.infinity, 28),
              ),
            ),
          ),
          kOpenHandHGap12,
          Text(
            '${_formatDingTalkVoiceDuration(visual.elapsed)} / ${_formatDingTalkVoiceDuration(maxDuration)}',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colors.onErrorContainer,
              fontFeatures: const [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DingTalkVoiceWavePainter extends CustomPainter {
  const _DingTalkVoiceWavePainter({
    required this.levels,
    required this.color,
    required this.trackColor,
  });

  final List<double> levels;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final count = levels.isEmpty ? 40 : levels.length;
    const gap = 3.0;
    final barWidth = ((size.width - (count - 1) * gap) / count)
        .clamp(1.0, 5.0)
        .toDouble();
    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = barWidth
      ..strokeCap = StrokeCap.round;
    final valuePaint = Paint()
      ..color = color
      ..strokeWidth = barWidth
      ..strokeCap = StrokeCap.round;
    for (var index = 0; index < count; index++) {
      final x = barWidth / 2 + index * (barWidth + gap);
      final level = levels.isEmpty
          ? 0.08
          : levels[index].clamp(0.08, 1.0).toDouble();
      final trackTop = size.height * 0.38;
      final trackBottom = size.height * 0.62;
      canvas.drawLine(Offset(x, trackTop), Offset(x, trackBottom), trackPaint);
      final halfHeight = (size.height * 0.45 * level)
          .clamp(2.0, size.height)
          .toDouble();
      final center = size.height / 2;
      canvas.drawLine(
        Offset(x, center - halfHeight),
        Offset(x, center + halfHeight),
        valuePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DingTalkVoiceWavePainter oldDelegate) {
    return oldDelegate.levels != levels ||
        oldDelegate.color != color ||
        oldDelegate.trackColor != trackColor;
  }
}

String _formatDingTalkVoiceDuration(Duration duration) {
  final seconds = duration.inSeconds.clamp(0, 5999);
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  return '${twoDigit(minutes)}:${twoDigit(remainder)}';
}

class _DingTalkRespondingIndicator extends StatelessWidget {
  const _DingTalkRespondingIndicator();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2, color: color),
    );
  }
}

class _DingTalkConversationStatusCapsule extends StatelessWidget {
  const _DingTalkConversationStatusCapsule({
    required this.state,
    required this.selected,
  });

  static const Color _approvalColor = Color(0xFFE6A817);
  static const Color _failedColor = Color(0xFFC84B4B);

  final DingTalkConversationResponseState state;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = switch (state) {
      DingTalkConversationResponseState.awaitingApproval => _approvalColor,
      DingTalkConversationResponseState.failed => _failedColor,
      DingTalkConversationResponseState.active =>
        selected ? colors.onPrimaryContainer : colors.primary,
      DingTalkConversationResponseState.idle => colors.outline,
    };
    final label = switch (state) {
      DingTalkConversationResponseState.awaitingApproval => '等待审批',
      DingTalkConversationResponseState.failed => '执行失败',
      DingTalkConversationResponseState.active => '进行中',
      DingTalkConversationResponseState.idle => '',
    };
    final capsule = Container(
      constraints: const BoxConstraints(maxWidth: 82),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.12),
        borderRadius: kOpenHandPillBorderRadius,
        border: Border.all(color: foreground.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state != DingTalkConversationResponseState.failed) ...[
            _DingTalkStatusDot(
              color: foreground,
              pulsing:
                  state == DingTalkConversationResponseState.awaitingApproval,
            ),
            kOpenHandHGap6,
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (state == DingTalkConversationResponseState.failed) return capsule;
    return ClipRRect(
      borderRadius: kOpenHandPillBorderRadius,
      child: OpenHandSweepShimmer(
        sweepColor: foreground.withValues(alpha: 0.18),
        child: capsule,
      ),
    );
  }
}

class _DingTalkStatusDot extends StatefulWidget {
  const _DingTalkStatusDot({required this.color, required this.pulsing});

  final Color color;
  final bool pulsing;

  @override
  State<_DingTalkStatusDot> createState() => _DingTalkStatusDotState();
}

class _DingTalkStatusDotState extends State<_DingTalkStatusDot>
    with SingleTickerProviderStateMixin {
  static const Duration _pulseDuration = kOpenHandMotion1200;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _pulseDuration,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animate = widget.pulsing && openHandTickerMotionEnabled(context);
    if (animate && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!animate) {
      _controller.stop();
    }
    if (!animate) return _buildDot(1);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => _buildDot(0.35 + _controller.value * 0.65),
    );
  }

  Widget _buildDot(double opacity) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(
      color: widget.color.withValues(alpha: opacity),
      shape: BoxShape.circle,
    ),
  );
}

class _DingTalkQueuedResponsesPanel extends StatelessWidget {
  const _DingTalkQueuedResponsesPanel({
    super.key,
    required this.messages,
    required this.animationSettings,
    required this.showRespondAction,
    required this.canRespond,
    required this.onRespond,
    required this.onRemove,
    required this.onMove,
  });

  final List<DingTalkQueuedResponse> messages;
  final DialogAnimationSettings animationSettings;
  final bool showRespondAction;
  final bool Function(int sequence) canRespond;
  final ValueChanged<int> onRespond;
  final ValueChanged<int> onRemove;
  final void Function(int from, int to) onMove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 164),
        child: ListView.builder(
          shrinkWrap: true,
          physics: messages.length > 3
              ? null
              : const NeverScrollableScrollPhysics(),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[index];
            final isFirst = index == 0;
            final isLast = index == messages.length - 1;
            final respondEnabled = canRespond(message.sequence);
            Color actionColor(bool enabled) => enabled
                ? colors.onSurfaceVariant
                : colors.onSurfaceVariant.withValues(alpha: 0.3);
            return AnimatedRemovableChip(
              key: ValueKey<String>('dingtalk-queued:${message.sequence}'),
              settings: animationSettings,
              collapseAxis: Axis.vertical,
              onRemove: () => onRemove(message.sequence),
              builder: (context, requestRemove) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: kOpenHandBorderRadius8,
                    border: Border.all(
                      color: colors.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.hourglass_empty_rounded,
                        size: 14,
                        color: colors.onSurfaceVariant,
                      ),
                      kOpenHandHGap8,
                      Expanded(
                        child: Text(
                          message.content.replaceAll('\n', ' '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: colors.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ),
                        ),
                      ),
                      kOpenHandHGap4,
                      AnimatedSwitcher(
                        duration: openHandMotionDuration(
                          context,
                          kOpenHandMotion180,
                        ),
                        switchInCurve: kOpenHandEntranceCurve,
                        switchOutCurve: kOpenHandSwitchOutCurve,
                        transitionBuilder: (child, animation) => SizeTransition(
                          axis: Axis.horizontal,
                          sizeFactor: animation,
                          child: FadeTransition(
                            opacity: animation,
                            child: child,
                          ),
                        ),
                        child: showRespondAction
                            ? MicroPressFeedback(
                                key: ValueKey<String>(
                                  'respond:${message.sequence}',
                                ),
                                enabled: respondEnabled,
                                child: IconButton(
                                  onPressed: respondEnabled
                                      ? () => onRespond(message.sequence)
                                      : null,
                                  icon: Icon(
                                    Icons.play_arrow_rounded,
                                    size: 15,
                                    color: actionColor(respondEnabled),
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  tooltip: respondEnabled
                                      ? '从此消息开始响应'
                                      : '正在停止当前响应',
                                ),
                              )
                            : SizedBox.shrink(
                                key: ValueKey<String>(
                                  'respond-hidden:${message.sequence}',
                                ),
                              ),
                      ),
                      if (showRespondAction) kOpenHandHGap4,
                      MicroPressFeedback(
                        enabled: !isFirst,
                        child: IconButton(
                          onPressed: isFirst
                              ? null
                              : () => onMove(index, index - 1),
                          icon: Icon(
                            Icons.arrow_upward_rounded,
                            size: 14,
                            color: actionColor(!isFirst),
                          ),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: '上移',
                        ),
                      ),
                      kOpenHandHGap4,
                      MicroPressFeedback(
                        enabled: !isLast,
                        child: IconButton(
                          onPressed: isLast
                              ? null
                              : () => onMove(index, index + 1),
                          icon: Icon(
                            Icons.arrow_downward_rounded,
                            size: 14,
                            color: actionColor(!isLast),
                          ),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: '下移',
                        ),
                      ),
                      kOpenHandHGap4,
                      MicroPressFeedback(
                        child: IconButton(
                          onPressed: requestRemove,
                          icon: Icon(
                            Icons.close_rounded,
                            size: 14,
                            color: colors.onSurfaceVariant,
                          ),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: '删除此等待消息',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DingTalkResponseErrorBanner extends StatelessWidget {
  const _DingTalkResponseErrorBanner({
    required this.message,
    required this.onDismiss,
    super.key,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.errorContainer.withValues(alpha: 0.72),
          borderRadius: kOpenHandBorderRadius14,
          border: Border.all(color: colors.error.withValues(alpha: 0.32)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 18,
                color: colors.onErrorContainer,
              ),
              kOpenHandHGap8,
              Expanded(
                child: Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              kOpenHandHGap6,
              IconButton(
                tooltip: '关闭错误提示',
                visualDensity: VisualDensity.compact,
                onPressed: onDismiss,
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: colors.onErrorContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _dingTalkForwardedChatTitle(DingTalkGatewayMessage message) {
  final names = <String>[];
  for (final item in message.forwardedMessages) {
    final name = item.senderName.trim();
    if (name.isEmpty || names.contains(name)) continue;
    names.add(name);
    if (names.length >= 3) break;
  }
  return switch (names.length) {
    0 => '转发的聊天记录',
    1 => '${names.first}的聊天记录',
    2 => '${names.first}与${names.last}的聊天记录',
    _ => '${names[0]}、${names[1]}等人的聊天记录',
  };
}

Future<void> _openDingTalkMessageLink(
  BuildContext context,
  String? href,
) async {
  final target = href?.trim() ?? '';
  final uri = target.isEmpty ? null : Uri.tryParse(target);
  final scheme = uri?.scheme.toLowerCase();
  final isWebLink = scheme == 'http' || scheme == 'https';
  final isDingTalkLink = scheme == 'dingtalk';
  if (uri == null ||
      (!isWebLink && !isDingTalkLink && scheme != 'mailto') ||
      (isWebLink && (uri.host.isEmpty || uri.userInfo.isNotEmpty))) {
    const error = FormatException('消息链接无效或暂不支持。');
    silentLog('dingtalk_gateway', '打开消息链接', error);
    if (context.mounted) {
      showOpenHandErrorSnack(context, '链接无效或暂不支持打开。');
    }
    return;
  }
  final opened = await openExternalUriWithSystemApp(
    uri,
    tag: 'dingtalk_gateway.message_link',
  );
  if (!context.mounted) return;
  if (!opened) {
    showOpenHandErrorSnack(context, '无法打开链接，请检查系统默认应用设置。');
    return;
  }
  showOpenHandInfoSnack(context, '正在打开链接');
}

typedef _DingTalkMediaSaveCallback =
    Future<DingTalkGatewayMedia> Function(
      DingTalkGatewayMedia media,
      String destinationPath,
    );

const double _dingtalkTextBubbleBottomSpacing = 6;
const double _dingtalkMediaRailBottomSpacing = 4;
const double _dingtalkActionToggleMaxDistance = 8;
const Duration _dingtalkActionToggleMaxDuration = Duration(milliseconds: 350);
const Duration _dingtalkActionToggleDelay = Duration(milliseconds: 80);
const EdgeInsets _dingtalkQuotedCardMotionClearance = EdgeInsets.symmetric(
  horizontal: 4,
);

class _DingTalkMessageAnchorRegistry {
  final Map<String, BuildContext> _contexts = <String, BuildContext>{};

  void bind(String messageId, BuildContext context) {
    final normalizedId = normalizeDingTalkMessageId(messageId);
    if (normalizedId.isNotEmpty) _contexts[normalizedId] = context;
  }

  void unbind(String messageId, BuildContext context) {
    final normalizedId = normalizeDingTalkMessageId(messageId);
    if (identical(_contexts[normalizedId], context)) {
      _contexts.remove(normalizedId);
    }
  }

  BuildContext? contextOf(String messageId) {
    final normalizedId = normalizeDingTalkMessageId(messageId);
    final context = _contexts[normalizedId];
    if (context is Element && !context.mounted) {
      _contexts.remove(normalizedId);
      return null;
    }
    return context;
  }

  Iterable<MapEntry<String, BuildContext>> get entries => _contexts.entries;

  void clear() => _contexts.clear();
}

class _DingTalkMessageBubble extends StatefulWidget {
  const _DingTalkMessageBubble({
    required this.message,
    required this.renderIdentity,
    required this.mine,
    required this.actionsVisible,
    required this.onToggleActions,
    required this.anchorRegistry,
    this.streaming = false,
    this.mediaLoading = false,
    this.mediaFailed = false,
    this.onEdit,
    this.onShowEditHistory,
    this.onToggleAiContextIgnored,
    this.onRetryMedia,
    this.onSaveMedia,
    this.speechEnabled = false,
    this.speechPlaying = false,
    this.onToggleSpeech,
    this.translationEnabled = false,
    this.translationLoading = false,
    this.translationVisible = false,
    this.translatedContent,
    this.onToggleTranslation,
    this.onSetFeedback,
    this.onAudit,
    this.onOpenForwardedChat,
    this.onOpenQuotedMessage,
    this.onReturnToQuotedSource,
    this.highlighted = false,
    this.showRawAction = false,
  });

  final DingTalkGatewayMessage message;
  final String renderIdentity;
  final bool mine;
  final bool actionsVisible;
  final VoidCallback onToggleActions;
  final _DingTalkMessageAnchorRegistry anchorRegistry;

  /// AI 流式回显中：正文按增量渐显并展示呼吸指示点。
  final bool streaming;
  final bool mediaLoading;
  final bool mediaFailed;
  final VoidCallback? onEdit;
  final VoidCallback? onShowEditHistory;
  final VoidCallback? onToggleAiContextIgnored;
  final VoidCallback? onRetryMedia;
  final _DingTalkMediaSaveCallback? onSaveMedia;
  final bool speechEnabled;
  final bool speechPlaying;
  final VoidCallback? onToggleSpeech;
  final bool translationEnabled;
  final bool translationLoading;
  final bool translationVisible;
  final String? translatedContent;
  final VoidCallback? onToggleTranslation;
  final ValueChanged<DingTalkGatewayMessageFeedback?>? onSetFeedback;
  final VoidCallback? onAudit;
  final VoidCallback? onOpenForwardedChat;
  final VoidCallback? onOpenQuotedMessage;
  final VoidCallback? onReturnToQuotedSource;
  final bool highlighted;
  final bool showRawAction;

  @override
  State<_DingTalkMessageBubble> createState() => _DingTalkMessageBubbleState();
}

class _DingTalkMessageBubbleState extends State<_DingTalkMessageBubble> {
  static const double _baseBubbleMaxWidth = 420;
  static const double _mineBubbleWidthFactor = 0.57;
  static const double _mineBubbleMaxWidth = 690;
  static const double _peerBubbleWidthFactor = 0.675;
  static const double _peerBubbleMaxWidth = 870;
  static const int _quotedMessagePreviewMaxLines = 3;
  static const int _maxRenderedTextCharacters = 10000;
  static const int _maxRenderedTextLines = 160;
  static const int _maxRenderedToolTextCharacters = 1600;
  static const int _maxRenderedToolTextLines = 28;
  static const double _actionToggleMaxDistance =
      _dingtalkActionToggleMaxDistance;
  static const Duration _actionToggleMaxDuration =
      _dingtalkActionToggleMaxDuration;
  static const Duration _actionToggleDelay = _dingtalkActionToggleDelay;
  static final RegExp _forwardedPreviewWhitespacePattern = RegExp(r'\s+');
  Offset? _pointerDownPosition;
  DateTime? _pointerDownAt;
  Timer? _pendingActionToggleTimer;
  bool _copyingMedia = false;
  bool _showRawContent = false;
  bool _showFullText = false;
  bool _showExcludedContent = false;
  bool _longContentCollapseLatched = false;

  @override
  void initState() {
    super.initState();
    widget.anchorRegistry.bind(widget.message.id, context);
    _longContentCollapseLatched = _shouldCollapseLongContent(
      _effectiveTextContent(widget),
    );
  }

  @override
  void didUpdateWidget(covariant _DingTalkMessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id ||
        oldWidget.anchorRegistry != widget.anchorRegistry) {
      oldWidget.anchorRegistry.unbind(oldWidget.message.id, context);
    }
    widget.anchorRegistry.bind(widget.message.id, context);
    if (oldWidget.renderIdentity != widget.renderIdentity) {
      _cancelPendingActionToggle();
      _showRawContent = false;
      _showFullText = false;
      _showExcludedContent = false;
      _longContentCollapseLatched = _shouldCollapseLongContent(
        _effectiveTextContent(widget),
      );
      return;
    }
    if (!_longContentCollapseLatched &&
        _shouldCollapseLongContent(_effectiveTextContent(widget))) {
      _longContentCollapseLatched = true;
      _showFullText = false;
    }
    if (oldWidget.message.content != widget.message.content &&
        !widget.streaming &&
        widget.message.isContentHidden) {
      _showExcludedContent = false;
    }
    if (oldWidget.message.recalled != widget.message.recalled ||
        oldWidget.message.ignoredForAiContext !=
            widget.message.ignoredForAiContext) {
      _showExcludedContent = false;
    }
  }

  @override
  void dispose() {
    _cancelPendingActionToggle();
    widget.anchorRegistry.unbind(widget.message.id, context);
    super.dispose();
  }

  void _cancelPendingActionToggle() {
    _pendingActionToggleTimer?.cancel();
    _pendingActionToggleTimer = null;
  }

  String _effectiveTextContent(_DingTalkMessageBubble bubble) {
    final content = bubble.translationVisible
        ? bubble.translatedContent ?? bubble.message.content
        : bubble.message.content;
    return stripImageSummaryMarkup(content);
  }

  bool _shouldCollapseLongContent(String content) {
    final characterLimit = widget.message.isToolCallEcho
        ? _maxRenderedToolTextCharacters
        : _maxRenderedTextCharacters;
    if (content.length > characterLimit) return true;
    final lineLimit = widget.message.isToolCallEcho
        ? _maxRenderedToolTextLines
        : _maxRenderedTextLines;
    var lines = 1;
    for (final codeUnit in content.codeUnits) {
      if (codeUnit == 0x0A && ++lines > lineLimit) return true;
    }
    return false;
  }

  void _handlePointerDown(PointerDownEvent event) {
    _pointerDownPosition = event.position;
    _pointerDownAt = DateTime.now();
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _pointerDownPosition = null;
    _pointerDownAt = null;
    _cancelPendingActionToggle();
  }

  void _handlePointerUp(PointerUpEvent event) {
    final downPosition = _pointerDownPosition;
    final downAt = _pointerDownAt;
    _pointerDownPosition = null;
    _pointerDownAt = null;
    if (downPosition == null || downAt == null) return;
    if (widget.message.isContentHidden && !_showExcludedContent) {
      return;
    }
    final movement = (event.position - downPosition).distance;
    final elapsed = DateTime.now().difference(downAt);
    if (movement > _actionToggleMaxDistance ||
        elapsed > _actionToggleMaxDuration) {
      return;
    }
    _cancelPendingActionToggle();
    _pendingActionToggleTimer = startSafeTimer(_actionToggleDelay, () {
      _pendingActionToggleTimer = null;
      if (!mounted) return;
      widget.onToggleActions();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final baseBubbleColor = widget.mine
        ? colors.primaryContainer
        : colors.surfaceContainerHighest;
    final bubbleColor = widget.message.recalled
        ? Color.alphaBlend(
            colors.surface.withValues(alpha: 0.46),
            baseBubbleColor,
          )
        : widget.message.ignoredForAiContext
        ? Color.alphaBlend(
            colors.tertiaryContainer.withValues(alpha: 0.44),
            baseBubbleColor,
          )
        : baseBubbleColor;
    final foreground = widget.message.recalled
        ? colors.onSurfaceVariant.withValues(alpha: 0.72)
        : widget.message.ignoredForAiContext
        ? colors.onTertiaryContainer.withValues(alpha: 0.74)
        : widget.mine
        ? colors.onPrimaryContainer
        : colors.onSurface;
    final alignment = widget.mine
        ? Alignment.centerRight
        : Alignment.centerLeft;
    final crossAxis = widget.mine
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;
    final senderName = widget.message.senderName.trim();
    final showSenderName =
        !widget.mine &&
        widget.message.conversationType == DingTalkConversationType.group &&
        senderName.isNotEmpty;
    final messageMedia = widget.message.media;
    final effectiveContent = stripImageSummaryMarkup(
      widget.translationVisible
          ? widget.translatedContent ?? widget.message.content
          : widget.message.content,
    );
    final contentExpanded =
        !widget.message.isContentHidden || _showExcludedContent;
    final status = _messageStatus();
    return SizedBox(
      width: double.infinity,
      child: Column(
        textDirection: TextDirection.ltr,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showSenderName)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  senderName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          LayoutBuilder(
            builder: (context, constraints) {
              final widthFactor = widget.mine
                  ? _mineBubbleWidthFactor
                  : _peerBubbleWidthFactor;
              final absoluteMaxWidth = widget.mine
                  ? _mineBubbleMaxWidth
                  : _peerBubbleMaxWidth;
              final maxBubbleWidth = math.min(
                constraints.maxWidth,
                math.min(
                  absoluteMaxWidth,
                  math.max(
                    _baseBubbleMaxWidth,
                    constraints.maxWidth * widthFactor,
                  ),
                ),
              );
              final bubbleAlignment = widget.mine
                  ? Alignment.topRight
                  : Alignment.topLeft;
              final resizeDuration = widget.streaming
                  ? Duration.zero
                  : openHandMotionDuration(context, kOpenHandMotion220);
              final contentTransitionDuration = widget.streaming
                  ? Duration.zero
                  : openHandMotionDuration(context, kOpenHandMotion180);
              final messageContent = AnimatedSwitcher(
                duration: contentTransitionDuration,
                switchInCurve: kOpenHandSwitchInCurve,
                switchOutCurve: kOpenHandSwitchOutCurve,
                layoutBuilder: (current, previous) => Stack(
                  alignment: bubbleAlignment,
                  children: <Widget>[...previous, if (current != null) current],
                ),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SizeTransition(
                    sizeFactor: animation,
                    alignment: AlignmentDirectional.topStart,
                    fixedCrossAxisSizeFactor: 1,
                    child: child,
                  ),
                ),
                child: !contentExpanded
                    ? _buildCollapsedMessageContent(
                        context,
                        bubbleColor: bubbleColor,
                        foreground: foreground,
                      )
                    : IntrinsicWidth(
                        key: const ValueKey<String>(
                          'dingtalk-message-content-expanded',
                        ),
                        child: _buildMessageContent(
                          context,
                          bubbleColor: bubbleColor,
                          foreground: foreground,
                          effectiveContent: effectiveContent,
                          crossAxis: crossAxis,
                          media: messageMedia,
                        ),
                      ),
              );
              final bubbleContent = resizeDuration == Duration.zero
                  ? messageContent
                  : AnimatedSize(
                      duration: resizeDuration,
                      curve: kOpenHandSwitchInCurve,
                      alignment: bubbleAlignment,
                      child: messageContent,
                    );
              final highlightedContent = AnimatedScale(
                scale: widget.highlighted ? 1.012 : 1,
                duration: openHandMotionDuration(context, kOpenHandMotion260),
                curve: kOpenHandEntranceCurve,
                alignment: bubbleAlignment,
                child: contentExpanded
                    ? bubbleContent
                    : _buildNavigationHighlight(context, child: bubbleContent),
              );
              return Align(
                alignment: alignment,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                  child: Listener(
                    onPointerDown: _handlePointerDown,
                    onPointerCancel: _handlePointerCancel,
                    onPointerUp: _handlePointerUp,
                    child: highlightedContent,
                  ),
                ),
              );
            },
          ),
          _DingTalkMessageActionsPanel(
            visible: contentExpanded && widget.actionsVisible,
            mine: widget.mine,
            actions: _buildMessageActions(context, widget.message.media),
            meta: _DingTalkMessageMetaRow(
              createdAt: widget.message.createdAt,
              statusIcon: status.icon,
              statusLabel: status.label,
              onReturnToQuotedSource: widget.onReturnToQuotedSource,
            ),
          ),
          kOpenHandGap7,
        ],
      ),
    );
  }

  BorderRadius get _messageBubbleBorderRadius => BorderRadius.only(
    topLeft: const Radius.circular(kOpenHandRadius17),
    topRight: const Radius.circular(kOpenHandRadius17),
    bottomLeft: Radius.circular(widget.mine ? 17 : 5),
    bottomRight: Radius.circular(widget.mine ? 5 : 17),
  );

  Widget _buildNavigationHighlight(
    BuildContext context, {
    required Widget child,
    double bottomInset = 0,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Stack(
      children: [
        child,
        Positioned.fill(
          bottom: bottomInset,
          child: IgnorePointer(
            child: AnimatedContainer(
              duration: openHandMotionDuration(context, kOpenHandMotion260),
              curve: kOpenHandSwitchInCurve,
              decoration: BoxDecoration(
                borderRadius: _messageBubbleBorderRadius,
                border: Border.all(
                  color: colors.primary.withValues(
                    alpha: widget.highlighted ? 0.82 : 0,
                  ),
                  width: 1.8,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  ({IconData icon, String label}) _messageStatus() {
    if (widget.message.recalled) {
      return (icon: Icons.undo_rounded, label: '已撤回');
    }
    if (widget.message.failed) {
      return (icon: Icons.error_outline_rounded, label: '发送失败');
    }
    if (widget.message.isAutomaticReply) {
      return (icon: Icons.auto_awesome_motion_rounded, label: '钉钉自动回复');
    }
    if (widget.streaming) {
      return (icon: Icons.auto_awesome_rounded, label: 'AI 正在响应');
    }
    final aiState = widget.message.aiResponseState;
    if (aiState != DingTalkMessageAiResponseState.none) {
      return switch (aiState) {
        DingTalkMessageAiResponseState.queued => (
          icon: Icons.hourglass_empty_rounded,
          label: '已加入 AI 响应等待队列',
        ),
        DingTalkMessageAiResponseState.responding => (
          icon: Icons.auto_awesome_rounded,
          label: 'AI 正在响应',
        ),
        DingTalkMessageAiResponseState.responded => (
          icon: Icons.task_alt_rounded,
          label: 'AI 已响应',
        ),
        DingTalkMessageAiResponseState.rejected => (
          icon: Icons.block_rounded,
          label: 'AI 已拒绝响应',
        ),
        DingTalkMessageAiResponseState.dropped => (
          icon: Icons.visibility_off_rounded,
          label: '已被 AI 忽略丢弃',
        ),
        DingTalkMessageAiResponseState.cancelled => (
          icon: Icons.cancel_outlined,
          label: 'AI 响应已取消',
        ),
        DingTalkMessageAiResponseState.failed => (
          icon: Icons.error_outline_rounded,
          label: 'AI 响应失败',
        ),
        DingTalkMessageAiResponseState.none => (
          icon: Icons.info_outline_rounded,
          label: '未处理',
        ),
      };
    }
    if (widget.message.ignoredForAiContext) {
      return (icon: Icons.visibility_off_rounded, label: '已忽略 AI 上下文');
    }
    final read =
        widget.message.readByPeer ||
        (!widget.message.isAssistant && !widget.mine);
    return read
        ? (icon: Icons.mark_email_read_outlined, label: '已读')
        : (icon: Icons.mark_email_unread_outlined, label: '未读');
  }

  Widget _buildMessageContent(
    BuildContext context, {
    required Color bubbleColor,
    required Color foreground,
    required String effectiveContent,
    required CrossAxisAlignment crossAxis,
    required List<DingTalkGatewayMedia> media,
  }) {
    final hasText = _hasDingTalkTextContent(effectiveContent, media);
    final hasQuotedMessage = widget.message.quotedMessage != null;
    final automaticReplyCard = widget.message.automaticReplyCard;
    final childAlignment = widget.mine
        ? Alignment.centerRight
        : Alignment.centerLeft;
    final textBubble = automaticReplyCard != null
        ? _buildAutomaticReplyCard(context, automaticReplyCard)
        : hasText || media.isEmpty
        ? _buildTextBubble(
            context,
            bubbleColor: bubbleColor,
            foreground: foreground,
            effectiveContent: effectiveContent,
            includeFooter: media.isEmpty,
          )
        : null;
    final mediaRail = _DingTalkMediaRail(
      media: media,
      mine: widget.mine,
      loading: widget.mediaLoading,
      failed: widget.mediaFailed,
      onRetry: widget.onRetryMedia,
      onSaveFile: widget.onSaveMedia,
      onInteractiveTap: _cancelPendingActionToggle,
    );
    return Column(
      crossAxisAlignment: crossAxis,
      children: [
        if (widget.message.quotedMessage case final quotedMessage?)
          Align(
            alignment: childAlignment,
            widthFactor: 1,
            child: _buildQuotedMessageCard(
              context,
              quotedMessage: quotedMessage,
              bubbleColor: bubbleColor,
              foreground: foreground,
            ),
          ),
        if (hasQuotedMessage) kOpenHandGap8,
        if (media.isNotEmpty)
          AnimatedOpacity(
            duration: openHandMotionDuration(context, kOpenHandMotion220),
            curve: kOpenHandSwitchInCurve,
            opacity: widget.message.recalled
                ? 0.62
                : widget.message.ignoredForAiContext
                ? 0.68
                : 1,
            child: textBubble == null
                ? _buildNavigationHighlight(
                    context,
                    child: mediaRail,
                    bottomInset: _dingtalkMediaRailBottomSpacing,
                  )
                : mediaRail,
          ),
        if (hasText && media.isNotEmpty) kOpenHandGap8,
        if (textBubble != null)
          Align(
            alignment: childAlignment,
            widthFactor: 1,
            child: IntrinsicWidth(
              child: _buildNavigationHighlight(
                context,
                child: textBubble,
                bottomInset: _dingtalkTextBubbleBottomSpacing,
              ),
            ),
          ),
        if (media.isNotEmpty && widget.message.reactions.isNotEmpty)
          _buildReactionRow(context, foreground, topSpacing: 2),
        if (media.isNotEmpty) _buildMessageStateLabel(context),
      ],
    );
  }

  Widget _buildAutomaticReplyCard(
    BuildContext context,
    DingTalkAutomaticReplyCard card,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final borderRadius = _messageBubbleBorderRadius;
    return AnimatedContainer(
      duration: openHandMotionDuration(context, kOpenHandMotion220),
      curve: kOpenHandSwitchInCurve,
      margin: const EdgeInsets.only(bottom: _dingtalkTextBubbleBottomSpacing),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: borderRadius,
        border: Border.all(color: colors.primary.withValues(alpha: 0.28)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(color: colors.primaryContainer),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 11, 15, 11),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.14),
                        borderRadius: kOpenHandBorderRadius10,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          Icons.auto_awesome_motion_rounded,
                          size: 18,
                          color: colors.primary,
                        ),
                      ),
                    ),
                    kOpenHandHGap9,
                    Flexible(
                      child: Text(
                        card.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (card.textSegments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(15, 14, 15, 12),
                child: Text.rich(
                  TextSpan(
                    children: [
                      for (final segment in card.textSegments)
                        TextSpan(
                          text: segment.text,
                          style: segment.emphasized
                              ? TextStyle(
                                  color: colors.primary,
                                  fontWeight: FontWeight.w900,
                                )
                              : null,
                        ),
                    ],
                  ),
                  textWidthBasis: TextWidthBasis.longestLine,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colors.onSurface,
                    height: 1.42,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            for (var index = 0; index < card.actions.length; index++)
              Padding(
                padding: EdgeInsets.fromLTRB(12, index == 0 ? 0 : 3, 12, 7),
                child: Semantics(
                  button: true,
                  label: card.actions[index].label,
                  hint: '打开钉钉自动回复入口',
                  child: OpenHandOpsPressScale(
                    tone: colors.primary,
                    borderRadius: kOpenHandPillBorderRadius,
                    hoverScale: 1.008,
                    pressScale: 0.975,
                    showHoverOverlay: false,
                    showFocusRing: true,
                    motionClearance: EdgeInsets.zero,
                    onTap: () {
                      _cancelPendingActionToggle();
                      unawaited(
                        _openDingTalkMessageLink(
                          context,
                          card.actions[index].url,
                        ),
                      );
                    },
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color.alphaBlend(
                          colors.primaryContainer.withValues(alpha: 0.32),
                          colors.surfaceContainerHighest,
                        ),
                        borderRadius: kOpenHandPillBorderRadius,
                        border: Border.all(
                          color: colors.primary.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 9,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.arrow_outward_rounded,
                              size: 17,
                              color: colors.primary,
                            ),
                            kOpenHandHGap8,
                            Flexible(
                              child: Text(
                                card.actions[index].label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: colors.onSurface,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (card.privateOnly)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 2, 14, 11),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 14,
                      color: colors.onSurfaceVariant.withValues(alpha: 0.8),
                    ),
                    kOpenHandHGap5,
                    Text(
                      '仅你和对方可见',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            if (widget.message.reactions.isNotEmpty ||
                widget.message.isContentHidden)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.message.reactions.isNotEmpty)
                      _buildReactionRow(
                        context,
                        colors.onSurface,
                        topSpacing: 0,
                      ),
                    _buildMessageStateLabel(context),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuotedMessageCard(
    BuildContext context, {
    required DingTalkQuotedMessage quotedMessage,
    required Color bubbleColor,
    required Color foreground,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final sender = quotedMessage.senderName.trim().isEmpty
        ? '用户'
        : quotedMessage.senderName.trim();
    final content = normalizeDingTalkMediaText(
      stripImageSummaryMarkup(quotedMessage.content),
      quotedMessage.media,
    ).trim();
    final preview = content.isNotEmpty
        ? content
        : quotedMessage.media.map((item) => '[${item.displayName}]').join(' ');
    final previewLines = const LineSplitter().convert(preview);
    final visiblePreview = previewLines.length > _quotedMessagePreviewMaxLines
        ? '${previewLines.take(_quotedMessagePreviewMaxLines).join('\n').trimRight()}…'
        : preview;
    final card = AnimatedContainer(
      duration: openHandMotionDuration(context, kOpenHandMotion220),
      curve: kOpenHandSwitchInCurve,
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          colors.surface.withValues(alpha: widget.mine ? 0.24 : 0.42),
          bubbleColor,
        ),
        borderRadius: kOpenHandBorderRadius12,
        border: Border.all(
          color: colors.primary.withValues(alpha: 0.42),
          width: 1.2,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.only(left: 10),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: colors.primary.withValues(alpha: 0.78),
              width: 3,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.format_quote_rounded,
                  size: 15,
                  color: colors.primary,
                ),
                kOpenHandHGap6,
                Flexible(
                  child: Text(
                    sender,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textWidthBasis: TextWidthBasis.longestLine,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: foreground.withValues(alpha: 0.82),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (visiblePreview.isNotEmpty) ...[
              kOpenHandGap4,
              Text(
                visiblePreview,
                maxLines: _quotedMessagePreviewMaxLines,
                overflow: TextOverflow.ellipsis,
                textWidthBasis: TextWidthBasis.longestLine,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: foreground.withValues(alpha: 0.78),
                  height: 1.4,
                ),
              ),
            ],
            if (quotedMessage.media.isNotEmpty) ...[
              kOpenHandGap8,
              _DingTalkMediaRail(
                media: quotedMessage.media,
                mine: widget.mine,
                loading: widget.mediaLoading,
                failed: widget.mediaFailed,
                onRetry: widget.onRetryMedia,
                onSaveFile: widget.onSaveMedia,
                onInteractiveTap: _cancelPendingActionToggle,
              ),
            ],
          ],
        ),
      ),
    );
    return Semantics(
      button: widget.onOpenQuotedMessage != null,
      label: '引用 $sender 的消息：$preview',
      hint: widget.onOpenQuotedMessage == null ? null : '点击跳转至原消息',
      child: OpenHandOpsPressScale(
        tone: colors.primary,
        borderRadius: kOpenHandBorderRadius12,
        hoverScale: 1.006,
        pressScale: 0.985,
        showHoverOverlay: false,
        showFocusRing: true,
        motionClearance: _dingtalkQuotedCardMotionClearance,
        onTap: widget.onOpenQuotedMessage == null
            ? null
            : () {
                _cancelPendingActionToggle();
                widget.onOpenQuotedMessage?.call();
              },
        child: card,
      ),
    );
  }

  Widget _buildTextBubble(
    BuildContext context, {
    required Color bubbleColor,
    required Color foreground,
    required String effectiveContent,
    bool includeFooter = true,
  }) {
    final colors = Theme.of(context).colorScheme;
    if (widget.message.isForwardedChatRecord && !_showRawContent) {
      return _buildForwardedChatCard(
        context,
        bubbleColor: bubbleColor,
        foreground: foreground,
      );
    }
    return AnimatedContainer(
      duration: openHandMotionDuration(context, kOpenHandMotion220),
      curve: kOpenHandSwitchInCurve,
      margin: const EdgeInsets.only(bottom: _dingtalkTextBubbleBottomSpacing),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bubbleColor,
        border: widget.message.ignoredForAiContext && !widget.message.recalled
            ? Border.all(color: colors.tertiary.withValues(alpha: 0.42))
            : null,
        borderRadius: _messageBubbleBorderRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTextContent(
            context,
            content: effectiveContent,
            foreground: foreground,
          ),
          if (includeFooter && widget.message.reactions.isNotEmpty)
            _buildReactionRow(context, foreground),
          if (includeFooter) _buildMessageStateLabel(context),
        ],
      ),
    );
  }

  Widget _buildForwardedChatCard(
    BuildContext context, {
    required Color bubbleColor,
    required Color foreground,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final messages = widget.message.forwardedMessages;
    final totalCount = widget.message.forwardedMessageCount;
    final preview = messages.take(4).toList(growable: false);
    final borderRadius = _messageBubbleBorderRadius;
    return Semantics(
      button: true,
      label:
          '${_dingTalkForwardedChatTitle(widget.message)}，共 $totalCount 条，点击查看',
      child: AnimatedContainer(
        width: 440,
        duration: openHandMotionDuration(context, kOpenHandMotion220),
        curve: kOpenHandSwitchInCurve,
        margin: const EdgeInsets.only(bottom: _dingtalkTextBubbleBottomSpacing),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: borderRadius,
          border: Border.all(color: colors.primary.withValues(alpha: 0.24)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () {
                  _cancelPendingActionToggle();
                  widget.onOpenForwardedChat?.call();
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 15, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.tertiaryContainer.withValues(
                                alpha: 0.86,
                              ),
                              borderRadius: kOpenHandBorderRadius12,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(9),
                              child: Icon(
                                Icons.forum_rounded,
                                size: 21,
                                color: colors.onTertiaryContainer,
                              ),
                            ),
                          ),
                          kOpenHandHGap12,
                          Expanded(
                            child: Text(
                              _dingTalkForwardedChatTitle(widget.message),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: foreground,
                                fontWeight: FontWeight.w800,
                                height: 1.28,
                              ),
                            ),
                          ),
                          kOpenHandHGap8,
                          Icon(
                            Icons.chevron_right_rounded,
                            color: foreground.withValues(alpha: 0.64),
                          ),
                        ],
                      ),
                      kOpenHandGap12,
                      for (var index = 0; index < preview.length; index++) ...[
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text:
                                    '${preview[index].senderName.trim().isEmpty ? '用户' : preview[index].senderName.trim()}：',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              TextSpan(
                                text: _forwardedPreviewText(preview[index]),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: foreground.withValues(alpha: 0.76),
                            height: 1.5,
                          ),
                        ),
                        if (index != preview.length - 1) kOpenHandGap2,
                      ],
                      kOpenHandGap10,
                      Divider(
                        height: 1,
                        color: foreground.withValues(alpha: 0.12),
                      ),
                      kOpenHandGap9,
                      Row(
                        children: [
                          Icon(
                            Icons.layers_outlined,
                            size: 16,
                            color: colors.secondary,
                          ),
                          kOpenHandHGap6,
                          Expanded(
                            child: Text(
                              totalCount > messages.length
                                  ? '已展示 ${messages.length} / $totalCount 条'
                                  : '共 $totalCount 条聊天记录',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: foreground.withValues(alpha: 0.66),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          kOpenHandHGap8,
                          Text(
                            '查看详情',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: widget.mine ? foreground : colors.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.message.reactions.isNotEmpty ||
                  widget.message.isContentHidden)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  child: Column(
                    children: [
                      if (widget.message.reactions.isNotEmpty)
                        _buildReactionRow(context, foreground, topSpacing: 0),
                      _buildMessageStateLabel(context),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _forwardedPreviewText(DingTalkForwardedMessage message) {
    final content = stripImageSummaryMarkup(
      message.content,
    ).replaceAll(_forwardedPreviewWhitespacePattern, ' ').trim();
    if (content.isNotEmpty) return content;
    return message.media.map((item) => '[${item.displayName}]').join(' ');
  }

  Widget _buildCollapsedMessageContent(
    BuildContext context, {
    required Color bubbleColor,
    required Color foreground,
  }) {
    return _DingTalkExcludedMessageState(
      key: ValueKey<String>(
        widget.message.recalled
            ? 'dingtalk-message-content-recalled-collapsed'
            : 'dingtalk-message-content-ignored-collapsed',
      ),
      recalled: widget.message.recalled,
      expanded: false,
      mine: widget.mine,
      backgroundColor: bubbleColor,
      foreground: foreground,
      onToggle: _toggleExcludedContent,
    );
  }

  void _toggleExcludedContent() {
    _cancelPendingActionToggle();
    if (!widget.message.isContentHidden) return;
    setState(() => _showExcludedContent = !_showExcludedContent);
  }

  List<Widget> _buildMessageActions(
    BuildContext context,
    List<DingTalkGatewayMedia> media,
  ) {
    final hasText = _hasDingTalkTextContent(widget.message.content, media);
    final actions = <Widget>[
      _buildCopyAction(context, media, hasText: hasText),
      if (widget.onToggleAiContextIgnored != null)
        _DingTalkMessageActionButton(
          icon: widget.message.ignoredForAiContext
              ? Icons.visibility_rounded
              : Icons.visibility_off_rounded,
          label: widget.message.ignoredForAiContext ? '撤销忽略' : '忽略',
          onPressed: widget.onToggleAiContextIgnored,
          selected: widget.message.ignoredForAiContext,
        ),
      if (widget.speechEnabled && widget.onToggleSpeech != null)
        _DingTalkMessageActionButton(
          icon: widget.speechPlaying
              ? Icons.stop_circle_outlined
              : Icons.record_voice_over_outlined,
          label: widget.speechPlaying ? '停止' : '朗读',
          onPressed: widget.onToggleSpeech,
        ),
      if (widget.translationEnabled && widget.onToggleTranslation != null)
        _DingTalkMessageActionButton(
          icon: widget.translationLoading
              ? Icons.hourglass_top_rounded
              : widget.translationVisible
              ? Icons.visibility_outlined
              : Icons.translate_rounded,
          label: widget.translationLoading
              ? '翻译中'
              : widget.translationVisible
              ? '查看原始'
              : '翻译',
          onPressed: widget.translationLoading
              ? null
              : widget.onToggleTranslation,
        ),
      if (widget.onSetFeedback != null)
        _DingTalkMessageActionButton(
          icon: widget.message.feedback == DingTalkGatewayMessageFeedback.liked
              ? Icons.thumb_up_alt_rounded
              : Icons.thumb_up_alt_outlined,
          label: '点赞',
          onPressed: () => widget.onSetFeedback!(
            widget.message.feedback == DingTalkGatewayMessageFeedback.liked
                ? null
                : DingTalkGatewayMessageFeedback.liked,
          ),
          selected:
              widget.message.feedback == DingTalkGatewayMessageFeedback.liked,
        ),
      if (widget.onSetFeedback != null)
        _DingTalkMessageActionButton(
          icon:
              widget.message.feedback ==
                  DingTalkGatewayMessageFeedback.needsImprovement
              ? Icons.thumb_down_alt_rounded
              : Icons.thumb_down_alt_outlined,
          label: '需要改进',
          onPressed: () => widget.onSetFeedback!(
            widget.message.feedback ==
                    DingTalkGatewayMessageFeedback.needsImprovement
                ? null
                : DingTalkGatewayMessageFeedback.needsImprovement,
          ),
          selected:
              widget.message.feedback ==
              DingTalkGatewayMessageFeedback.needsImprovement,
        ),
      if (widget.onEdit != null)
        _DingTalkMessageActionButton(
          icon: Icons.edit_outlined,
          label: '编辑',
          onPressed: widget.onEdit,
        ),
      if (widget.onShowEditHistory != null)
        _DingTalkMessageActionButton(
          icon: Icons.history_rounded,
          label: '编辑历史',
          onPressed: widget.onShowEditHistory,
        ),
      if (widget.onAudit != null)
        _DingTalkMessageActionButton(
          icon: Icons.fact_check_outlined,
          label: '审计',
          onPressed: widget.onAudit,
        ),
      if (widget.showRawAction)
        _DingTalkMessageActionButton(
          icon: _showRawContent ? Icons.code_off_outlined : Icons.code_outlined,
          label: _showRawContent ? '显示渲染' : '显示原始',
          onPressed: () => setState(() {
            _showRawContent = !_showRawContent;
          }),
        ),
    ];
    return widget.mine ? actions.reversed.toList(growable: false) : actions;
  }

  Widget _buildTextContent(
    BuildContext context, {
    required String content,
    required Color foreground,
  }) {
    final theme = Theme.of(context);
    final thinking = widget.message.isThinkingEcho;
    final canCollapse =
        _longContentCollapseLatched || _shouldCollapseLongContent(content);
    final collapsed = canCollapse && !_showFullText;
    final bodyStyle = theme.textTheme.bodyMedium?.copyWith(
      color: foreground,
      height: 1.48,
      fontStyle: thinking && !_showRawContent ? FontStyle.italic : null,
    );
    final displayContent = thinking && !_showRawContent
        ? unwrapDingTalkThinkingMarkdown(content)
        : content;
    // 流式回显期间按字素簇渐显增量内容；生成结束后切回可选择的静态渲染。
    final streaming = widget.streaming && !_showRawContent;
    return AnimatedSwitcher(
      duration: widget.streaming
          ? Duration.zero
          : openHandMotionDuration(context, kOpenHandMotion220),
      switchInCurve: kOpenHandSwitchInCurve,
      switchOutCurve: kOpenHandSwitchOutCurve,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topLeft,
        children: <Widget>[...previous, if (current != null) current],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SizeTransition(
          sizeFactor: animation,
          alignment: AlignmentDirectional.topStart,
          fixedCrossAxisSizeFactor: 1,
          child: child,
        ),
      ),
      child: collapsed
          ? Semantics(
              key: const ValueKey<String>('dingtalk-long-message-collapsed'),
              container: true,
              label: streaming ? '长消息已折叠，内容生成中' : '长消息已折叠',
              child: Row(
                children: [
                  Icon(Icons.subject_rounded, size: 20, color: foreground),
                  kOpenHandHGap9,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '长消息已折叠',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: foreground,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          streaming ? '内容持续生成中' : '完整内容已保留',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: foreground.withValues(alpha: 0.72),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  kOpenHandHGap8,
                  TextButton.icon(
                    onPressed: () {
                      _cancelPendingActionToggle();
                      setState(() => _showFullText = true);
                    },
                    icon: const Icon(Icons.unfold_more_rounded, size: 17),
                    label: const Text('展开'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            )
          : Column(
              key: const ValueKey<String>('dingtalk-long-message-expanded'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.message.isAssistant &&
                    widget.message.sourceAiMessageId.isNotEmpty &&
                    !_showRawContent)
                  StreamingTextRevealText(
                    text: displayContent,
                    streaming: streaming,
                    // 气泡外层已有 AnimatedSize，关闭内部尺寸动画避免竞争。
                    animateSize: false,
                    builder: (context, visibleText) => _buildMessageBody(
                      context,
                      theme: theme,
                      text: visibleText,
                      bodyStyle: bodyStyle,
                      foreground: foreground,
                      canCollapse: canCollapse,
                      streaming: true,
                    ),
                    settledBuilder: (context, visibleText) => _buildMessageBody(
                      context,
                      theme: theme,
                      text: visibleText,
                      bodyStyle: bodyStyle,
                      foreground: foreground,
                      canCollapse: canCollapse,
                      streaming: false,
                    ),
                  )
                else
                  _buildMessageBody(
                    context,
                    theme: theme,
                    text: displayContent,
                    bodyStyle: bodyStyle,
                    foreground: foreground,
                    canCollapse: canCollapse,
                    streaming: streaming,
                  ),
                if (streaming) _DingTalkStreamingDots(color: foreground),
                if (canCollapse)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () {
                          _cancelPendingActionToggle();
                          setState(() => _showFullText = false);
                        },
                        icon: const Icon(Icons.unfold_less_rounded, size: 17),
                        label: const Text('折叠'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildMessageBody(
    BuildContext context, {
    required ThemeData theme,
    required String text,
    required TextStyle? bodyStyle,
    required Color foreground,
    required bool canCollapse,
    required bool streaming,
  }) {
    final renderMarkdown =
        widget.mine &&
        widget.message.isAssistant &&
        !_showRawContent &&
        (_showFullText || !canCollapse);
    if (!renderMarkdown) {
      final style = _showRawContent
          ? bodyStyle?.copyWith(fontFamily: 'monospace', fontSize: 12.5)
          : bodyStyle;
      // 流式期间用稳定 key 的静态文本，避免每帧重建可选择文本的手势状态。
      if (streaming) {
        return Text(
          text,
          key: const ValueKey<String>('dingtalk-streaming-plain'),
          textWidthBasis: TextWidthBasis.longestLine,
          style: style,
        );
      }
      if (_showRawContent) {
        return SelectableText(
          text,
          key: ValueKey<String>('raw:$text'),
          textWidthBasis: TextWidthBasis.longestLine,
          style: style,
        );
      }
      return _DingTalkLinkifiedText(
        text: text,
        style: style,
        linkStyle: (style ?? const TextStyle()).copyWith(
          color: widget.mine ? foreground : theme.colorScheme.primary,
          decoration: TextDecoration.underline,
          decorationColor: widget.mine ? foreground : theme.colorScheme.primary,
          decorationThickness: 1.2,
        ),
        onOpenLink: (href) {
          _cancelPendingActionToggle();
          unawaited(_openDingTalkMessageLink(context, href));
        },
      );
    }
    final thinkingFontStyle = widget.message.isThinkingEcho
        ? FontStyle.italic
        : null;
    final codeStyle = theme.textTheme.bodySmall?.copyWith(
      color: foreground,
      fontFamily: kOpenHandMonospaceFontFamily,
      fontWeight: FontWeight.w600,
      fontStyle: thinkingFontStyle,
    );
    final body = OpenHandSafeMarkdownBody(
      key: streaming
          ? const ValueKey<String>('dingtalk-streaming-markdown')
          : ValueKey<String>('markdown:$text'),
      data: text,
      selectable: !streaming,
      streaming: streaming,
      onTapLink: (text, href, title) {
        _cancelPendingActionToggle();
        unawaited(_openDingTalkMessageLink(context, href ?? text));
      },
      imageBuilder: (uri, title, alt) => Text(
        alt?.trim().isNotEmpty == true ? '[${alt!.trim()}]' : '[图片]',
        style: bodyStyle?.copyWith(fontStyle: FontStyle.italic),
      ),
      builders: <String, MarkdownElementBuilder>{
        'code': OpenHandMarkdownInlineCodeBuilder(
          textStyle: codeStyle ?? const TextStyle(),
          backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.58),
        ),
      },
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: bodyStyle,
        h3: theme.textTheme.titleMedium?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w800,
          fontStyle: thinkingFontStyle,
        ),
        h3Padding: const EdgeInsets.only(bottom: 2),
        h4: theme.textTheme.labelLarge?.copyWith(
          color: foreground.withValues(alpha: 0.86),
          fontWeight: FontWeight.w800,
          fontStyle: thinkingFontStyle,
        ),
        h4Padding: const EdgeInsets.only(top: 8, bottom: 2),
        blockSpacing: 10,
        code: codeStyle,
        tableHead: theme.textTheme.labelMedium?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w800,
          fontStyle: thinkingFontStyle,
        ),
        tableBody: bodyStyle?.copyWith(fontSize: 13, height: 1.42),
        tableBorder: TableBorder.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.82),
          width: 0.8,
          borderRadius: BorderRadius.circular(kOpenHandRadius10),
        ),
        tableHeadAlign: TextAlign.left,
        tableVerticalAlignment: TableCellVerticalAlignment.middle,
        tablePadding: const EdgeInsets.symmetric(vertical: 3),
        tableCellsPadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        tableCellsDecoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.38),
        ),
        tableHeadCellsPadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        tableHeadCellsDecoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.74),
        ),
        tableColumnWidth: const IntrinsicColumnWidth(),
        tableScrollbarThumbVisibility: true,
        codeblockDecoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.58),
          borderRadius: BorderRadius.circular(kOpenHandRadius10),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.72),
          ),
        ),
        blockquoteDecoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.42),
          border: Border(
            left: BorderSide(
              color: theme.colorScheme.primary.withValues(alpha: 0.72),
              width: 3,
            ),
          ),
        ),
      ),
    );
    return thinkingFontStyle == null
        ? body
        : DefaultTextStyle.merge(
            style: TextStyle(fontStyle: thinkingFontStyle),
            child: body,
          );
  }

  Widget _buildCopyAction(
    BuildContext context,
    List<DingTalkGatewayMedia> media, {
    required bool hasText,
  }) {
    return _DingTalkMessageActionButton(
      icon: Icons.copy_rounded,
      label: hasText || media.isEmpty ? '复制' : '复制媒体',
      onPressed: _copyingMedia
          ? null
          : () => hasText || media.isEmpty
                ? unawaited(
                    copyOpenHandTextToClipboard(
                      context: context,
                      text: _dingtalkTextContent(widget.message.content),
                      logTag: 'dingtalk_gateway',
                    ),
                  )
                : unawaited(_copyMediaFiles(context, media)),
      busy: _copyingMedia,
    );
  }

  Widget _buildReactionRow(
    BuildContext context,
    Color foreground, {
    double topSpacing = 6,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final reactions = widget.message.reactions
        .map(normalizeDingTalkReaction)
        .where((reaction) => reaction.isNotEmpty)
        .map(
          (label) => (
            label: label,
            isEmoji: isDingTalkReactionEmoji(label),
            users: widget.message.reactionUsers[label] ?? const <String>[],
          ),
        )
        .toList(growable: false);
    if (reactions.isEmpty) return const SizedBox.shrink();
    final motionDuration = openHandMotionDuration(context, kOpenHandMotion220);
    final chipDuration = openHandMotionDuration(context, kOpenHandMotion180);
    final containerColors = <Color>[
      colors.primaryContainer,
      colors.secondaryContainer,
      colors.tertiaryContainer,
    ];
    return Padding(
      padding: EdgeInsets.only(top: topSpacing),
      child: AnimatedSize(
        duration: motionDuration,
        curve: kOpenHandSwitchInCurve,
        alignment: Alignment.topLeft,
        child: Wrap(
          spacing: 5,
          runSpacing: 4,
          children: [
            for (var index = 0; index < reactions.length; index++)
              TweenAnimationBuilder<double>(
                key: ValueKey<String>(
                  'dingtalk-reaction-${reactions[index].label}',
                ),
                duration: chipDuration,
                curve: kOpenHandEntranceCurve,
                tween: Tween<double>(begin: 0, end: 1),
                builder: (context, value, child) {
                  final progress = value.clamp(0.0, 1.0).toDouble();
                  return Opacity(
                    opacity: progress,
                    child: Transform.scale(
                      scale: 0.86 + progress * 0.14,
                      alignment: Alignment.centerLeft,
                      child: child,
                    ),
                  );
                },
                child: Semantics(
                  label:
                      '贴表情：${reactions[index].label}'
                      '${reactions[index].users.isEmpty ? '' : '，用户：${reactions[index].users.join(',')}'}',
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: SizedBox(
                      height: 30,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color.alphaBlend(
                            containerColors[index % containerColors.length]
                                .withValues(alpha: 0.22),
                            colors.surfaceContainerHigh,
                          ),
                          borderRadius: kOpenHandPillBorderRadius,
                          border: Border.all(
                            color:
                                containerColors[index % containerColors.length]
                                    .withValues(alpha: 0.48),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: colors.shadow.withValues(alpha: 0.08),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 9),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 96),
                                child: Text(
                                  reactions[index].label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: foreground,
                                    fontSize: reactions[index].isEmoji
                                        ? 16
                                        : 12,
                                    fontWeight: reactions[index].isEmoji
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    height: 1,
                                  ),
                                ),
                              ),
                              if (reactions[index].users.isNotEmpty) ...[
                                const SizedBox(width: 7),
                                Container(
                                  width: 1,
                                  height: 14,
                                  color: foreground.withValues(alpha: 0.2),
                                ),
                                const SizedBox(width: 7),
                                Flexible(
                                  child: Text(
                                    reactions[index].users.join(','),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: foreground.withValues(alpha: 0.76),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      height: 1,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageStateLabel(BuildContext context) {
    final recalled = widget.message.recalled;
    final ignored = widget.message.ignoredForAiContext;
    return AnimatedSwitcher(
      duration: openHandMotionDuration(context, kOpenHandMotion180),
      switchInCurve: kOpenHandSwitchInCurve,
      switchOutCurve: kOpenHandSwitchOutCurve,
      transitionBuilder: (child, animation) => SizeTransition(
        sizeFactor: animation,
        alignment: AlignmentDirectional.topStart,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: !recalled && !ignored
          ? const SizedBox(
              key: ValueKey<String>('dingtalk-message-state-normal'),
            )
          : _DingTalkExcludedMessageState(
              key: ValueKey<String>(
                recalled
                    ? 'dingtalk-message-state-recalled'
                    : 'dingtalk-message-state-ignored',
              ),
              recalled: recalled,
              expanded: true,
              mine: widget.mine,
              backgroundColor: Colors.transparent,
              foreground: Colors.transparent,
              onToggle: _toggleExcludedContent,
            ),
    );
  }

  Future<void> _copyMediaFiles(
    BuildContext context,
    List<DingTalkGatewayMedia> media,
  ) async {
    if (_copyingMedia) return;
    if (mounted) setState(() => _copyingMedia = true);
    try {
      final content = await _copyDingTalkMediaToClipboard(
        media,
        onUnavailable: widget.onRetryMedia,
      );
      if (context.mounted) {
        showOpenHandSuccessSnack(
          context,
          content == _DingTalkMediaClipboardContent.image
              ? '图片已复制到剪贴板。'
              : '媒体文件已复制到剪贴板。',
        );
      }
    } catch (error, stack) {
      silentLog('dingtalk_gateway', '复制媒体文件', error, stack);
      if (context.mounted) showOpenHandErrorSnack(context, '复制媒体文件失败：$error');
    } finally {
      if (mounted) setState(() => _copyingMedia = false);
    }
  }
}

class _DingTalkLinkifiedText extends StatefulWidget {
  const _DingTalkLinkifiedText({
    required this.text,
    required this.style,
    required this.linkStyle,
    required this.onOpenLink,
  });

  final String text;
  final TextStyle? style;
  final TextStyle linkStyle;
  final ValueChanged<String> onOpenLink;

  @override
  State<_DingTalkLinkifiedText> createState() => _DingTalkLinkifiedTextState();
}

class _DingTalkLinkifiedTextState extends State<_DingTalkLinkifiedText> {
  static const int _maxScannedCharacters = 64 * kBytesPerKiB;
  static const int _maxLinks = 64;
  static final RegExp _urlPattern = RegExp(
    r"""https?://[^\s<>"']+""",
    caseSensitive: false,
  );
  static const String _trailingPunctuation = '）】》」』”’，。！？、,.!?:;';

  List<({int start, int end, String url})> _links = const [];
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void initState() {
    super.initState();
    _refreshLinks();
  }

  @override
  void didUpdateWidget(covariant _DingTalkLinkifiedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _refreshLinks();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _refreshLinks() {
    _disposeRecognizers();
    final scanLength = math.min(widget.text.length, _maxScannedCharacters);
    final scannedText = widget.text.substring(0, scanLength);
    final links = <({int start, int end, String url})>[];
    for (final match in _urlPattern.allMatches(scannedText)) {
      if (links.length >= _maxLinks) break;
      if (scanLength < widget.text.length && match.end == scanLength) break;
      final matchedText = match.group(0)!;
      final url = _trimLinkEnd(matchedText);
      final uri = Uri.tryParse(url);
      final scheme = uri?.scheme.toLowerCase();
      if (url.isEmpty ||
          uri == null ||
          (scheme != 'http' && scheme != 'https') ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        continue;
      }
      links.add((start: match.start, end: match.start + url.length, url: url));
    }
    _links = List.unmodifiable(links);
    for (final link in _links) {
      _recognizers.add(
        TapGestureRecognizer()..onTap = () => widget.onOpenLink(link.url),
      );
    }
  }

  static String _trimLinkEnd(String value) {
    var end = value.length;
    while (end > 0) {
      final last = value[end - 1];
      if (_trailingPunctuation.contains(last)) {
        end--;
        continue;
      }
      final unmatchedClosing = switch (last) {
        ')' => _hasUnmatchedClosing(value, end, '(', ')'),
        ']' => _hasUnmatchedClosing(value, end, '[', ']'),
        '}' => _hasUnmatchedClosing(value, end, '{', '}'),
        _ => false,
      };
      if (!unmatchedClosing) break;
      end--;
    }
    return end == value.length ? value : value.substring(0, end);
  }

  static bool _hasUnmatchedClosing(
    String value,
    int end,
    String opening,
    String closing,
  ) {
    var balance = 0;
    for (var index = 0; index < end; index++) {
      final character = value[index];
      if (character == opening) {
        balance++;
      } else if (character == closing) {
        balance--;
      }
    }
    return balance < 0;
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    if (_links.isEmpty) {
      return SelectableText(
        widget.text,
        textWidthBasis: TextWidthBasis.longestLine,
        style: widget.style,
      );
    }
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (var index = 0; index < _links.length; index++) {
      final link = _links[index];
      if (link.start > cursor) {
        spans.add(TextSpan(text: widget.text.substring(cursor, link.start)));
      }
      spans.add(
        TextSpan(
          text: widget.text.substring(link.start, link.end),
          style: widget.linkStyle,
          recognizer: _recognizers[index],
          mouseCursor: SystemMouseCursors.click,
        ),
      );
      cursor = link.end;
    }
    if (cursor < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(cursor)));
    }
    return SelectableText.rich(
      TextSpan(style: widget.style, children: spans),
      textWidthBasis: TextWidthBasis.longestLine,
    );
  }
}

/// 流式回显呼吸指示点：三个圆点按相位差起伏渐亮，传递"正在生成"的生命力；
/// 遵循全局动效偏好，动画停用时退化为静态圆点。
class _DingTalkStreamingDots extends StatefulWidget {
  const _DingTalkStreamingDots({required this.color});

  final Color color;

  @override
  State<_DingTalkStreamingDots> createState() => _DingTalkStreamingDotsState();
}

class _DingTalkStreamingDotsState extends State<_DingTalkStreamingDots>
    with SingleTickerProviderStateMixin {
  static const Duration _cycle = Duration(milliseconds: 1080);
  static const int _dotCount = 3;
  static const double _dotSize = 5.5;
  static const double _dotSpacing = 4;
  static const double _phaseStep = 0.16;
  static const double _bounceHeight = 2.4;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _cycle,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (openHandTickerMotionEnabled(context)) {
      if (!_controller.isAnimating) _controller.repeat();
    } else if (_controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: List<Widget>.generate(_dotCount, (index) {
            final phase = (_controller.value - index * _phaseStep) % 1.0;
            final wave = math
                .sin(phase * math.pi * 2)
                .clamp(0.0, 1.0)
                .toDouble();
            return Padding(
              padding: EdgeInsets.only(
                right: index == _dotCount - 1 ? 0 : _dotSpacing,
              ),
              child: Transform.translate(
                offset: Offset(0, -wave * _bounceHeight),
                child: Container(
                  width: _dotSize,
                  height: _dotSize,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.32 + wave * 0.5),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _DingTalkMessageActionsPanel extends StatelessWidget {
  const _DingTalkMessageActionsPanel({
    required this.visible,
    required this.mine,
    required this.actions,
    required this.meta,
    this.topSpacing = 0,
  });

  final bool visible;
  final bool mine;
  final List<Widget> actions;
  final Widget meta;
  final double topSpacing;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: AnimatedSize(
        duration: openHandMotionDuration(context, kOpenHandMotion180),
        curve: kOpenHandSwitchInCurve,
        child: visible
            ? TweenAnimationBuilder<double>(
                key: const ValueKey<String>('dingtalk-actions-visible'),
                tween: Tween<double>(begin: 0, end: 1),
                duration: openHandMotionDuration(context, kOpenHandMotion180),
                curve: kOpenHandEntranceCurve,
                builder: (context, value, child) => Opacity(
                  opacity: value.clamp(0.0, 1.0).toDouble(),
                  child: Transform.translate(
                    offset: Offset(0, (1 - value) * 5),
                    child: Transform.scale(
                      alignment: mine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      scale: 0.96 + value * 0.04,
                      child: child,
                    ),
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.only(top: topSpacing),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    textDirection: TextDirection.ltr,
                    crossAxisAlignment: mine
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        textDirection: mine
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                        children: actions,
                      ),
                      kOpenHandGap4,
                      meta,
                    ],
                  ),
                ),
              )
            : const SizedBox(
                key: ValueKey<String>('dingtalk-actions-hidden'),
                width: 0,
                height: 0,
              ),
      ),
    );
  }
}

class _DingTalkExcludedMessageState extends StatelessWidget {
  const _DingTalkExcludedMessageState({
    super.key,
    required this.recalled,
    required this.expanded,
    required this.mine,
    required this.backgroundColor,
    required this.foreground,
    required this.onToggle,
  });

  final bool recalled;
  final bool expanded;
  final bool mine;
  final Color backgroundColor;
  final Color foreground;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final label = recalled ? '消息已撤回' : '已忽略，不参与 AI 上下文';
    if (expanded) {
      final stateColor = recalled
          ? colors.onSurfaceVariant.withValues(alpha: 0.72)
          : colors.tertiary;
      final stateStyle = theme.textTheme.labelSmall?.copyWith(
        color: stateColor,
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w600,
      );
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    recalled
                        ? Icons.undo_rounded
                        : Icons.visibility_off_rounded,
                    size: 14,
                    color: stateColor,
                  ),
                  kOpenHandHGap5,
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: stateStyle,
                    ),
                  ),
                ],
              ),
            ),
            kOpenHandHGap8,
            TextButton(
              onPressed: onToggle,
              style: TextButton.styleFrom(
                foregroundColor: stateColor,
                minimumSize: const Size(0, 28),
                padding: const EdgeInsets.symmetric(horizontal: 7),
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text('折叠', style: stateStyle),
            ),
          ],
        ),
      );
    }

    final stateStyle = theme.textTheme.labelMedium?.copyWith(
      color: foreground,
      fontWeight: FontWeight.w700,
    );
    return IntrinsicWidth(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border.all(
            color: (recalled ? colors.outline : colors.tertiary).withValues(
              alpha: recalled ? 0.24 : 0.38,
            ),
          ),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(kOpenHandRadius17),
            topRight: const Radius.circular(kOpenHandRadius17),
            bottomLeft: Radius.circular(
              mine ? kOpenHandRadius17 : kOpenHandRadius5,
            ),
            bottomRight: Radius.circular(
              mine ? kOpenHandRadius5 : kOpenHandRadius17,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(11, 6, 7, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: colors.surface.withValues(alpha: 0.58),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  recalled ? Icons.undo_rounded : Icons.visibility_off_rounded,
                  size: 16,
                  color: recalled ? foreground : colors.tertiary,
                ),
              ),
              kOpenHandHGap8,
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: stateStyle,
                ),
              ),
              kOpenHandHGap6,
              TextButton(
                onPressed: onToggle,
                style: TextButton.styleFrom(
                  foregroundColor: foreground,
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text('展开', style: stateStyle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DingTalkMessageMetaRow extends StatelessWidget {
  const _DingTalkMessageMetaRow({
    required this.createdAt,
    required this.statusIcon,
    required this.statusLabel,
    this.onReturnToQuotedSource,
  });

  final DateTime createdAt;
  final IconData statusIcon;
  final String statusLabel;
  final VoidCallback? onReturnToQuotedSource;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        _DingTalkMessageMetaPill(
          icon: Icons.schedule_rounded,
          label: formatYearMonthDayHmLocal(createdAt),
        ),
        _DingTalkMessageMetaPill(icon: statusIcon, label: statusLabel),
        if (onReturnToQuotedSource != null)
          _DingTalkMessageActionButton(
            icon: Icons.reply_all_rounded,
            label: '返回至引用处',
            onPressed: onReturnToQuotedSource,
          ),
      ],
    );
  }
}

class _DingTalkMessageMetaPill extends StatelessWidget {
  const _DingTalkMessageMetaPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: _DingTalkMessageActionButton(
        icon: icon,
        label: label,
        onPressed: () {},
      ),
    );
  }
}

class _DingTalkMessageActionButton extends StatelessWidget {
  const _DingTalkMessageActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final baseStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 34),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      textStyle: Theme.of(
        context,
      ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: selected
          ? baseStyle.copyWith(
              backgroundColor: WidgetStatePropertyAll(
                colors.primaryContainer.withValues(alpha: 0.72),
              ),
              foregroundColor: WidgetStatePropertyAll(
                colors.onPrimaryContainer,
              ),
              iconColor: WidgetStatePropertyAll(colors.onPrimaryContainer),
              side: WidgetStatePropertyAll(
                BorderSide(color: colors.primary.withValues(alpha: 0.62)),
              ),
            )
          : baseStyle,
      icon: busy
          ? const SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 16),
      label: Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
      ),
    );
  }
}

class _DingTalkMessageAuditDialog extends StatefulWidget {
  const _DingTalkMessageAuditDialog({required this.snapshot});

  final Future<DingTalkMessageAuditSnapshot?> snapshot;

  @override
  State<_DingTalkMessageAuditDialog> createState() =>
      _DingTalkMessageAuditDialogState();
}

class _DingTalkMessageAuditDialogState
    extends State<_DingTalkMessageAuditDialog> {
  static const int _maxSnapshotCharacters = 240000;
  static const double _metricGap = 10;
  static const double _metricMinWidth = 260;
  static const double _metricHeight = 52;
  static const BorderRadius _auditCardBorderRadius = BorderRadius.all(
    Radius.circular(kOpenHandRadius16),
  );
  bool _copyingSnapshot = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: _auditCardBorderRadius,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(
                    Icons.fact_check_outlined,
                    color: colors.onPrimaryContainer,
                    size: 23,
                  ),
                ),
              ),
              kOpenHandHGap12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '钉钉消息审计',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    kOpenHandGap3,
                    Text(
                      '核对网关消息、关联 AI 消息及运行元数据。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          kOpenHandGap16,
          Expanded(
            child: FutureBuilder<DingTalkMessageAuditSnapshot?>(
              future: widget.snapshot,
              builder: (context, state) {
                if (state.connectionState != ConnectionState.done) {
                  return const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(strokeWidth: 2.4),
                        kOpenHandGap12,
                        Text('正在加载完整审计快照…'),
                      ],
                    ),
                  );
                }
                if (state.hasError || state.data == null) {
                  return Center(
                    child: _DingTalkAuditNotice(
                      icon: Icons.error_outline_rounded,
                      title: '审计快照加载失败',
                      message: state.error?.toString() ?? '消息可能已被删除或会话已失效。',
                    ),
                  );
                }
                return _buildAuditContent(context, state.data!);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuditContent(
    BuildContext context,
    DingTalkMessageAuditSnapshot data,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final message = data.message;
    final payload = <String, Object?>{
      'gateway_message': _safeAuditMap(message.toJson),
      'conversation': <String, Object?>{
        'id': data.conversation.id,
        'title': data.conversation.title,
        'type': data.conversation.type.name,
        'open_conversation_id': data.conversation.openConversationId,
        'ai_session_id': data.conversation.aiSessionId,
      },
      if (data.aiSession != null)
        'ai_session': _safeAuditMap(
          () => data.aiSession!.toJson(includeMessages: false),
        ),
      if (data.aiMessage != null)
        'ai_message': _safeAuditMap(
          () => data.aiMessage!.toJson(includeDerivedFields: true),
        ),
    };
    late final String encoded;
    try {
      encoded = clipTextByCodeUnits(
        const JsonEncoder.withIndent('  ').convert(payload),
        _maxSnapshotCharacters,
        suffix: '\n…审计快照已截断，完整消息仍保留在本地会话数据中。',
      );
    } catch (error, stack) {
      silentLog('dingtalk_gateway', '编码钉钉消息审计快照', error, stack);
      encoded = '{\n  "serialization_error": "无法编码审计快照"\n}';
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 4),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OhPill(
              icon: Icons.hub_outlined,
              label: 'DWS 网关',
              foregroundColor: colors.primary,
            ),
            OhPill(
              icon: message.isAutomaticReply
                  ? Icons.auto_awesome_motion_rounded
                  : message.isAssistant
                  ? Icons.auto_awesome_outlined
                  : Icons.person_outline_rounded,
              label: message.isAutomaticReply
                  ? '钉钉自动回复'
                  : message.isAssistant
                  ? 'AI 消息'
                  : '用户消息',
              foregroundColor: colors.onSurfaceVariant,
            ),
            OhPill(
              icon: data.aiMessage == null
                  ? Icons.link_off_rounded
                  : Icons.link_rounded,
              label: data.aiMessage == null ? '无关联 AI 快照' : '已关联 AI 快照',
              foregroundColor: data.aiMessage == null
                  ? colors.onSurfaceVariant
                  : colors.primary,
            ),
          ],
        ),
        kOpenHandGap14,
        LayoutBuilder(
          builder: (context, constraints) {
            final metrics = <_DingTalkAuditMetricData>[
              _DingTalkAuditMetricData(
                label: '消息标识',
                value: message.id,
                icon: Icons.fingerprint_rounded,
              ),
              _DingTalkAuditMetricData(
                label: '发送时间',
                value: formatYearMonthDayHmLocal(message.createdAt),
                icon: Icons.schedule_rounded,
              ),
              _DingTalkAuditMetricData(
                label: '内容长度',
                value: '${message.content.runes.length} 字符',
                icon: Icons.data_object_rounded,
              ),
              _DingTalkAuditMetricData(
                label: '状态',
                value: message.recalled
                    ? '已撤回'
                    : message.failed
                    ? '发送失败'
                    : '正常',
                icon: Icons.verified_outlined,
              ),
            ];
            final twoColumns =
                constraints.maxWidth >= _metricMinWidth * 2 + _metricGap;
            final columnWidth = twoColumns
                ? (constraints.maxWidth - _metricGap) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: _metricGap,
              runSpacing: _metricGap,
              children: [
                for (final metric in metrics)
                  SizedBox(
                    width: columnWidth,
                    height: _metricHeight,
                    child: _DingTalkAuditMetric(data: metric),
                  ),
              ],
            );
          },
        ),
        kOpenHandGap16,
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: _auditCardBorderRadius,
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.72),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(
              children: [
                Icon(Icons.code_rounded, color: colors.primary, size: 19),
                kOpenHandHGap8,
                Expanded(
                  child: Text(
                    '原始审计快照',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: '复制审计快照',
                  onPressed: _copyingSnapshot
                      ? null
                      : () async => _copySnapshot(context, encoded),
                  icon: _copyingSnapshot
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.copy_all_rounded, size: 18),
                ),
              ],
            ),
          ),
        ),
        kOpenHandGap8,
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerLowest,
            borderRadius: _auditCardBorderRadius,
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.72),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: SelectableText(
              encoded,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                height: 1.48,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _copySnapshot(BuildContext context, String text) async {
    if (_copyingSnapshot) return;
    setState(() => _copyingSnapshot = true);
    try {
      await setOpenHandClipboardText(text);
      if (context.mounted) {
        showOpenHandSuccessSnack(context, '原始审计快照已复制到剪贴板。');
      }
    } catch (error, stack) {
      silentLog('dingtalk_gateway_audit', '复制原始审计快照', error, stack);
      if (context.mounted) {
        showOpenHandErrorSnack(
          context,
          '复制失败：${messageGatewayFailureMessage(error, fallback: '剪贴板暂不可用，请稍后重试。')}',
        );
      }
    } finally {
      if (mounted) setState(() => _copyingSnapshot = false);
    }
  }

  Map<String, Object?> _safeAuditMap(Map<String, Object?> Function() builder) {
    try {
      return builder();
    } catch (error, stack) {
      silentLog('dingtalk_gateway', '序列化钉钉消息审计快照', error, stack);
      return <String, Object?>{'serialization_error': '$error'};
    }
  }
}

class _DingTalkAuditMetricData {
  const _DingTalkAuditMetricData({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;
}

class _DingTalkAuditMetric extends StatelessWidget {
  const _DingTalkAuditMetric({required this.data});

  final _DingTalkAuditMetricData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: _DingTalkMessageAuditDialogState._auditCardBorderRadius,
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.68),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(data.icon, size: 18, color: colors.primary),
            kOpenHandHGap8,
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  kOpenHandGap2,
                  Text(
                    data.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DingTalkAuditNotice extends StatelessWidget {
  const _DingTalkAuditNotice({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.errorContainer.withValues(alpha: 0.52),
        borderRadius: kOpenHandBorderRadius16,
        border: Border.all(color: colors.error.withValues(alpha: 0.42)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: colors.error),
            kOpenHandGap10,
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            kOpenHandGap5,
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DingTalkForwardedChatDialog extends StatefulWidget {
  const _DingTalkForwardedChatDialog({
    required this.controller,
    required this.conversationId,
    required this.messageId,
    required this.initialMessage,
  });

  final DingTalkMessageGatewayController controller;
  final String conversationId;
  final String messageId;
  final DingTalkGatewayMessage initialMessage;

  @override
  State<_DingTalkForwardedChatDialog> createState() =>
      _DingTalkForwardedChatDialogState();
}

class _DingTalkForwardedChatDialogState
    extends State<_DingTalkForwardedChatDialog> {
  static const double _actionToggleMaxDistance =
      _dingtalkActionToggleMaxDistance;
  static const Duration _actionToggleMaxDuration =
      _dingtalkActionToggleMaxDuration;
  static const Duration _actionToggleDelay = _dingtalkActionToggleDelay;
  final AiTtsPlaybackService _ttsPlaybackService = AiTtsPlaybackService();
  final _DingTalkTranslationManager _translationManager =
      _DingTalkTranslationManager();
  final Set<String> _copyingMediaMessageIds = <String>{};
  final Set<String> _expandedIgnoredMessageIds = <String>{};
  Offset? _pointerDownPosition;
  DateTime? _pointerDownAt;
  Timer? _pendingActionToggleTimer;
  String? _expandedMessageId;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
    _ttsPlaybackService.state.addListener(_handleTtsStateChanged);
  }

  @override
  void dispose() {
    _cancelPendingActionToggle();
    widget.controller.removeListener(_handleControllerChanged);
    _ttsPlaybackService.state.removeListener(_handleTtsStateChanged);
    unawaited(_ttsPlaybackService.dispose());
    _translationManager.dispose();
    super.dispose();
  }

  void _handleTtsStateChanged() {
    if (mounted) setState(() {});
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    if (!widget.controller.isServiceEnabled) {
      unawaited(_ttsPlaybackService.stop());
      _translationManager.clear();
      _cancelPendingActionToggle();
      _expandedMessageId = null;
    }
    setState(() {});
  }

  void _cancelPendingActionToggle() {
    _pendingActionToggleTimer?.cancel();
    _pendingActionToggleTimer = null;
  }

  void _handlePointerDown(PointerDownEvent event) {
    _pointerDownPosition = event.position;
    _pointerDownAt = DateTime.now();
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _pointerDownPosition = null;
    _pointerDownAt = null;
    _cancelPendingActionToggle();
  }

  void _handlePointerUp(
    PointerUpEvent event,
    String messageId, {
    required bool ignored,
  }) {
    final downPosition = _pointerDownPosition;
    final downAt = _pointerDownAt;
    _pointerDownPosition = null;
    _pointerDownAt = null;
    if (downPosition == null || downAt == null) return;
    if (ignored && !_expandedIgnoredMessageIds.contains(messageId)) return;
    if ((event.position - downPosition).distance > _actionToggleMaxDistance ||
        DateTime.now().difference(downAt) > _actionToggleMaxDuration) {
      return;
    }
    _cancelPendingActionToggle();
    _pendingActionToggleTimer = startSafeTimer(_actionToggleDelay, () {
      _pendingActionToggleTimer = null;
      if (!mounted) return;
      setState(() {
        _expandedMessageId = _expandedMessageId == messageId ? null : messageId;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final ttsSettings = context.select<SettingsController, AiTtsSettings>(
      (settings) => settings.aiTtsSettings,
    );
    final translationSettings = context
        .select<SettingsController, AiTranslationSettings>(
          (settings) => settings.aiTranslationSettings,
        );
    final telemetryDebugEnabled = context.select<SettingsController, bool>(
      (settings) => settings.telemetryDebugEnabled,
    );
    final conversation = widget.controller.conversations
        .where((item) => item.id == widget.conversationId)
        .firstOrNull;
    final message = conversation?.messages
        .where((item) => item.id == widget.messageId)
        .firstOrNull;
    final currentMessage = message?.isForwardedChatRecord == true
        ? message!
        : widget.initialMessage;
    final fallbackModel = conversation == null
        ? null
        : widget.controller.messageActionFallbackModel(conversation);
    final forwarded = currentMessage.forwardedMessages;
    if (forwarded.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: _DingTalkAuditNotice(
            icon: Icons.forum_outlined,
            title: '聊天记录已失效',
            message: '请关闭后刷新会话再试。',
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.tertiaryContainer,
                  borderRadius: kOpenHandBorderRadius14,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(11),
                  child: Icon(
                    Icons.forum_rounded,
                    color: colors.onTertiaryContainer,
                    size: 24,
                  ),
                ),
              ),
              kOpenHandHGap12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _dingTalkForwardedChatTitle(currentMessage),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                    kOpenHandGap4,
                    Text(
                      currentMessage.forwardedMessageCount > forwarded.length
                          ? '已展示 ${forwarded.length} / ${currentMessage.forwardedMessageCount} 条'
                          : '共 ${currentMessage.forwardedMessageCount} 条聊天记录',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              kOpenHandHGap8,
              IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          kOpenHandGap14,
          Expanded(
            child: ListView.builder(
              scrollCacheExtent: const ScrollCacheExtent.pixels(600),
              padding: const EdgeInsets.only(bottom: 8),
              physics: openHandDialogAwareScrollPhysics(context),
              itemCount: forwarded.length,
              itemBuilder: (context, index) {
                final item = forwarded[index];
                final itemKey = _messageKey(item, index);
                final resolvedMedia = _resolvedMedia(currentMessage, item);
                final itemContent = _dingtalkTextContent(item.content);
                final textActionEnabled = _hasDingTalkTextContent(
                  itemContent,
                  resolvedMedia,
                );
                final translationFingerprint = aiTranslationRequestFingerprint(
                  translationSettings,
                  fallbackModel,
                );
                final translation = textActionEnabled
                    ? _translationManager.visibleTranslation(
                        messageId: itemKey,
                        sourceText: itemContent,
                        settingsFingerprint: translationFingerprint,
                      )
                    : null;
                final contentExpanded =
                    !item.ignoredForAiContext ||
                    _expandedIgnoredMessageIds.contains(itemKey);
                return RepaintBoundary(
                  key: ValueKey<String>('forwarded:$itemKey'),
                  child: _buildMessageRow(
                    context,
                    message: currentMessage,
                    item: item,
                    itemKey: itemKey,
                    media: resolvedMedia,
                    actionsVisible:
                        contentExpanded && _expandedMessageId == itemKey,
                    contentExpanded: contentExpanded,
                    translatedContent: translation?.translatedText,
                    speechEnabled: textActionEnabled && ttsSettings.enabled,
                    speechPlaying:
                        textActionEnabled &&
                        ttsSettings.enabled &&
                        _ttsPlaybackService.state.value.playing &&
                        _ttsPlaybackService.state.value.messageId == itemKey,
                    translationEnabled:
                        textActionEnabled && translationSettings.enabled,
                    translationLoading: _translationManager.isLoading(itemKey),
                    translationVisible: translation != null,
                    telemetryDebugEnabled: telemetryDebugEnabled,
                    fallbackModel: fallbackModel,
                    ttsSettings: ttsSettings,
                    translationSettings: translationSettings,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageRow(
    BuildContext context, {
    required DingTalkGatewayMessage message,
    required DingTalkForwardedMessage item,
    required String itemKey,
    required List<DingTalkGatewayMedia> media,
    required bool contentExpanded,
    required bool actionsVisible,
    required String? translatedContent,
    required bool speechEnabled,
    required bool speechPlaying,
    required bool translationEnabled,
    required bool translationLoading,
    required bool translationVisible,
    required bool telemetryDebugEnabled,
    required AiModelConfig? fallbackModel,
    required AiTtsSettings ttsSettings,
    required AiTranslationSettings translationSettings,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final senderName = item.senderName.trim().isEmpty
        ? '未知成员'
        : item.senderName.trim();
    final content = _dingtalkTextContent(item.content);
    final hasText = _hasDingTalkTextContent(content, media);
    final displayContent = translatedContent ?? content;
    final showText = hasText && displayContent.isNotEmpty;
    final ignoredBackground = Color.alphaBlend(
      colors.tertiaryContainer.withValues(alpha: 0.44),
      colors.surfaceContainerHighest,
    );
    final contentBackground = item.ignoredForAiContext
        ? ignoredBackground
        : colors.surfaceContainerHighest;
    final contentForeground = item.ignoredForAiContext
        ? colors.onTertiaryContainer.withValues(alpha: 0.74)
        : colors.onSurface;
    final palette = <({Color background, Color foreground})>[
      (
        background: colors.primaryContainer,
        foreground: colors.onPrimaryContainer,
      ),
      (
        background: colors.secondaryContainer,
        foreground: colors.onSecondaryContainer,
      ),
      (
        background: colors.tertiaryContainer,
        foreground: colors.onTertiaryContainer,
      ),
      (background: colors.errorContainer, foreground: colors.onErrorContainer),
    ];
    final identity = item.senderId.trim().isEmpty
        ? senderName
        : item.senderId.trim();
    final colorIndex =
        int.parse(stableFnv1a32Hex(identity).substring(0, 2), radix: 16) %
        palette.length;
    final avatarColors = palette[colorIndex];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            label: senderName,
            child: Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: avatarColors.background,
                borderRadius: kOpenHandBorderRadius12,
              ),
              child: Text(
                String.fromCharCode(senderName.runes.first),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: avatarColors.foreground,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          kOpenHandHGap12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  senderName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                kOpenHandGap5,
                AnimatedSize(
                  duration: openHandMotionDuration(context, kOpenHandMotion220),
                  curve: kOpenHandSwitchInCurve,
                  alignment: Alignment.topLeft,
                  child: AnimatedSwitcher(
                    duration: openHandMotionDuration(
                      context,
                      kOpenHandMotion180,
                    ),
                    switchInCurve: kOpenHandSwitchInCurve,
                    switchOutCurve: kOpenHandSwitchOutCurve,
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.topLeft,
                      children: <Widget>[
                        ...previous,
                        if (current != null) current,
                      ],
                    ),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SizeTransition(
                        sizeFactor: animation,
                        alignment: AlignmentDirectional.topStart,
                        fixedCrossAxisSizeFactor: 1,
                        child: child,
                      ),
                    ),
                    child: !contentExpanded
                        ? KeyedSubtree(
                            key: ValueKey<String>('ignored-collapsed:$itemKey'),
                            child: _buildIgnoredCollapsedContent(
                              context,
                              itemKey,
                            ),
                          )
                        : Listener(
                            key: ValueKey<String>('content-expanded:$itemKey'),
                            behavior: HitTestBehavior.translucent,
                            onPointerDown: _handlePointerDown,
                            onPointerCancel: _handlePointerCancel,
                            onPointerUp: (event) => _handlePointerUp(
                              event,
                              itemKey,
                              ignored: item.ignoredForAiContext,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (media.isNotEmpty)
                                  AnimatedOpacity(
                                    duration: openHandMotionDuration(
                                      context,
                                      kOpenHandMotion220,
                                    ),
                                    curve: kOpenHandSwitchInCurve,
                                    opacity: item.ignoredForAiContext
                                        ? 0.68
                                        : 1,
                                    child: _DingTalkMediaRail(
                                      media: media,
                                      mine: false,
                                      loading: widget.controller
                                          .isMessageMediaCaching(message.id),
                                      failed: widget.controller
                                          .isMessageMediaHydrationFailed(
                                            message.id,
                                          ),
                                      onRetry: () => unawaited(
                                        widget.controller
                                            .ensureMessageMediaCached(
                                              conversationId:
                                                  widget.conversationId,
                                              messageId: message.id,
                                              forceRetry: true,
                                            ),
                                      ),
                                      onSaveFile: (media, path) =>
                                          widget.controller.saveMessageMedia(
                                            conversationId:
                                                widget.conversationId,
                                            messageId: message.id,
                                            media: media,
                                            destinationPath: path,
                                          ),
                                      onInteractiveTap:
                                          _cancelPendingActionToggle,
                                    ),
                                  ),
                                if (showText && media.isNotEmpty) kOpenHandGap8,
                                if (showText)
                                  Container(
                                    constraints: const BoxConstraints(
                                      maxWidth: 640,
                                    ),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: item.ignoredForAiContext
                                          ? 10
                                          : 11,
                                    ),
                                    decoration: BoxDecoration(
                                      color: contentBackground,
                                      borderRadius: item.ignoredForAiContext
                                          ? const BorderRadius.only(
                                              topLeft: Radius.circular(
                                                kOpenHandRadius17,
                                              ),
                                              topRight: Radius.circular(
                                                kOpenHandRadius17,
                                              ),
                                              bottomLeft: Radius.circular(
                                                kOpenHandRadius5,
                                              ),
                                              bottomRight: Radius.circular(
                                                kOpenHandRadius17,
                                              ),
                                            )
                                          : const BorderRadius.only(
                                              topLeft: Radius.circular(4),
                                              topRight: Radius.circular(
                                                kOpenHandRadius14,
                                              ),
                                              bottomLeft: Radius.circular(
                                                kOpenHandRadius14,
                                              ),
                                              bottomRight: Radius.circular(
                                                kOpenHandRadius14,
                                              ),
                                            ),
                                      border: Border.all(
                                        color: item.ignoredForAiContext
                                            ? colors.tertiary.withValues(
                                                alpha: 0.42,
                                              )
                                            : colors.outlineVariant.withValues(
                                                alpha: 0.52,
                                              ),
                                      ),
                                    ),
                                    child: _DingTalkLinkifiedText(
                                      text: displayContent,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: contentForeground,
                                            height: 1.5,
                                          ),
                                      linkStyle:
                                          (theme.textTheme.bodyMedium ??
                                                  const TextStyle())
                                              .copyWith(
                                                color: colors.primary,
                                                height: 1.5,
                                                decoration:
                                                    TextDecoration.underline,
                                                decorationColor: colors.primary,
                                                decorationThickness: 1.2,
                                              ),
                                      onOpenLink: (href) {
                                        _cancelPendingActionToggle();
                                        unawaited(
                                          _openDingTalkMessageLink(
                                            context,
                                            href,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                if (item.ignoredForAiContext)
                                  _buildIgnoredExpandedState(context, itemKey),
                              ],
                            ),
                          ),
                  ),
                ),
                _DingTalkMessageActionsPanel(
                  visible: actionsVisible,
                  topSpacing: 7,
                  mine: false,
                  actions: [
                    _DingTalkMessageActionButton(
                      icon: Icons.copy_rounded,
                      label: hasText || media.isEmpty ? '复制' : '复制媒体',
                      busy: _copyingMediaMessageIds.contains(itemKey),
                      onPressed: _copyingMediaMessageIds.contains(itemKey)
                          ? null
                          : () => hasText || media.isEmpty
                                ? unawaited(
                                    copyOpenHandTextToClipboard(
                                      context: context,
                                      text: content,
                                      logTag: 'dingtalk_gateway',
                                    ),
                                  )
                                : unawaited(
                                    _copyMediaFiles(context, itemKey, media),
                                  ),
                    ),
                    _DingTalkMessageActionButton(
                      icon: item.ignoredForAiContext
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                      label: item.ignoredForAiContext ? '撤销忽略' : '忽略',
                      selected: item.ignoredForAiContext,
                      onPressed: () => _toggleAiContextIgnored(
                        context,
                        message,
                        item,
                        itemKey,
                      ),
                    ),
                    if (speechEnabled)
                      _DingTalkMessageActionButton(
                        icon: speechPlaying
                            ? Icons.stop_circle_outlined
                            : Icons.record_voice_over_outlined,
                        label: speechPlaying ? '停止' : '朗读',
                        onPressed: () => unawaited(
                          _toggleSpeech(
                            itemKey,
                            content,
                            ttsSettings,
                            fallbackModel,
                          ),
                        ),
                      ),
                    if (translationEnabled)
                      _DingTalkMessageActionButton(
                        icon: translationLoading
                            ? Icons.hourglass_top_rounded
                            : translationVisible
                            ? Icons.visibility_outlined
                            : Icons.translate_rounded,
                        label: translationLoading
                            ? '翻译中'
                            : translationVisible
                            ? '查看原始'
                            : '翻译',
                        onPressed: translationLoading
                            ? null
                            : () => unawaited(
                                _toggleTranslation(
                                  itemKey,
                                  content,
                                  translationSettings,
                                  fallbackModel,
                                ),
                              ),
                      ),
                    if (telemetryDebugEnabled)
                      _DingTalkMessageActionButton(
                        icon: Icons.fact_check_outlined,
                        label: '审计',
                        onPressed: () => _showAudit(context, message, item),
                      ),
                  ],
                  meta: _DingTalkMessageMetaPill(
                    icon: Icons.schedule_rounded,
                    label: formatYearMonthDayHmLocal(item.createdAt),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIgnoredCollapsedContent(BuildContext context, String itemKey) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: '已忽略，不参与 AI 上下文',
      child: _DingTalkExcludedMessageState(
        recalled: false,
        expanded: false,
        mine: false,
        backgroundColor: Color.alphaBlend(
          colors.tertiaryContainer.withValues(alpha: 0.44),
          colors.surfaceContainerHighest,
        ),
        foreground: colors.onTertiaryContainer.withValues(alpha: 0.74),
        onToggle: () {
          _cancelPendingActionToggle();
          setState(() {
            _expandedIgnoredMessageIds.add(itemKey);
          });
        },
      ),
    );
  }

  Widget _buildIgnoredExpandedState(BuildContext context, String itemKey) {
    return _DingTalkExcludedMessageState(
      recalled: false,
      expanded: true,
      mine: false,
      backgroundColor: Colors.transparent,
      foreground: Colors.transparent,
      onToggle: () {
        _cancelPendingActionToggle();
        setState(() {
          _expandedIgnoredMessageIds.remove(itemKey);
          _expandedMessageId = null;
        });
      },
    );
  }

  String _messageKey(DingTalkForwardedMessage item, int index) {
    final id = normalizeDingTalkMessageId(item.id);
    return '${widget.messageId}:$index:${id.isEmpty ? item.createdAt.microsecondsSinceEpoch : id}';
  }

  Future<void> _toggleSpeech(
    String messageId,
    String content,
    AiTtsSettings settings,
    AiModelConfig? fallbackModel,
  ) async {
    if (!widget.controller.isServiceEnabled) return;
    try {
      await _ttsPlaybackService.toggleMessage(
        messageId: messageId,
        text: content,
        settings: settings,
        availableModels: widget.controller.aiModels,
        fallbackModel: fallbackModel,
      );
    } catch (error, stack) {
      silentLog('dingtalk_gateway', '朗读转发聊天记录消息', error, stack);
      if (mounted) {
        showOpenHandErrorSnack(
          context,
          '朗读失败：${messageGatewayFailureMessage(error, fallback: '请检查文本转语音设置。')}',
        );
      }
    }
  }

  Future<void> _toggleTranslation(
    String messageId,
    String content,
    AiTranslationSettings settings,
    AiModelConfig? fallbackModel,
  ) async {
    if (!widget.controller.isServiceEnabled) return;
    final fingerprint = aiTranslationRequestFingerprint(
      settings,
      fallbackModel,
    );
    final failure = await _translationManager.toggle(
      messageId: messageId,
      sourceText: content,
      settingsFingerprint: fingerprint,
      settings: settings,
      availableModels: widget.controller.aiModels,
      fallbackModel: fallbackModel,
      isMounted: () => mounted,
      update: (mutation) {
        if (mounted) setState(mutation);
      },
      logAction: '翻译转发聊天记录消息',
    );
    if (mounted && failure != null) {
      showOpenHandErrorSnack(context, '翻译失败：$failure');
    }
  }

  void _toggleAiContextIgnored(
    BuildContext context,
    DingTalkGatewayMessage message,
    DingTalkForwardedMessage item,
    String itemKey,
  ) {
    final ignored = !item.ignoredForAiContext;
    final success = widget.controller.setForwardedMessageAiContextIgnored(
      widget.conversationId,
      message.id,
      item,
      ignored,
    );
    if (!context.mounted) return;
    if (!success) {
      showOpenHandErrorSnack(context, '消息状态已变化，请刷新后重试。');
      return;
    }
    setState(() {
      _expandedIgnoredMessageIds.remove(itemKey);
      if (ignored) _expandedMessageId = null;
    });
    showOpenHandInfoSnack(
      context,
      ignored ? '已忽略该消息，不会参与后续 AI 上下文。' : '已撤销忽略。',
    );
  }

  void _showAudit(
    BuildContext context,
    DingTalkGatewayMessage message,
    DingTalkForwardedMessage item,
  ) {
    final conversation = widget.controller.conversations
        .where((value) => value.id == widget.conversationId)
        .firstOrNull;
    if (conversation == null) {
      showOpenHandErrorSnack(context, '会话已失效，请刷新后重试。');
      return;
    }
    final snapshot = DingTalkMessageAuditSnapshot(
      conversation: conversation,
      message: DingTalkGatewayMessage(
        id: item.id,
        conversationId: message.conversationId,
        conversationType: message.conversationType,
        role: DingTalkGatewayMessageRole.user,
        content: item.content,
        createdAt: item.createdAt,
        senderName: item.senderName,
        senderId: item.senderId,
        conversationTitle: message.conversationTitle,
        media: item.media,
        ignoredForAiContext: item.ignoredForAiContext,
      ),
    );
    unawaited(
      showAnimatedDialog<void>(
        context: context,
        builder: (_) => buildOpenHandDialog(
          maxWidth: 820,
          maxHeight: MediaQuery.sizeOf(context).height * 0.84,
          child: _DingTalkMessageAuditDialog(
            snapshot: Future<DingTalkMessageAuditSnapshot?>.value(snapshot),
          ),
        ),
      ),
    );
  }

  Future<void> _copyMediaFiles(
    BuildContext context,
    String messageId,
    List<DingTalkGatewayMedia> media,
  ) async {
    if (_copyingMediaMessageIds.contains(messageId)) return;
    setState(() => _copyingMediaMessageIds.add(messageId));
    try {
      final content = await _copyDingTalkMediaToClipboard(
        media,
        onUnavailable: () {
          unawaited(
            widget.controller.ensureMessageMediaCached(
              conversationId: widget.conversationId,
              messageId: widget.messageId,
              forceRetry: true,
            ),
          );
        },
      );
      if (context.mounted) {
        showOpenHandSuccessSnack(
          context,
          content == _DingTalkMediaClipboardContent.image
              ? '图片已复制到剪贴板。'
              : '媒体文件已复制到剪贴板。',
        );
      }
    } catch (error, stack) {
      silentLog('dingtalk_gateway', '复制转发聊天记录媒体', error, stack);
      if (context.mounted) {
        showOpenHandErrorSnack(context, '复制媒体文件失败：$error');
      }
    } finally {
      if (mounted) setState(() => _copyingMediaMessageIds.remove(messageId));
    }
  }

  List<DingTalkGatewayMedia> _resolvedMedia(
    DingTalkGatewayMessage message,
    DingTalkForwardedMessage item,
  ) {
    return item.media
        .map((childMedia) {
          for (final parentMedia in message.media) {
            if (parentMedia.resourceType == childMedia.resourceType &&
                normalizeDingTalkResourceId(parentMedia.resourceId) ==
                    normalizeDingTalkResourceId(childMedia.resourceId)) {
              return parentMedia;
            }
          }
          return childMedia;
        })
        .toList(growable: false);
  }
}

class _DingTalkMessageEditHistoryDialog extends StatelessWidget {
  const _DingTalkMessageEditHistoryDialog({required this.message});

  final DingTalkGatewayMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final records = message.editHistory;
    final historyHeight = (MediaQuery.sizeOf(context).height * 0.58)
        .clamp(260.0, 520.0)
        .toDouble();
    final versions = <({String label, String content, DateTime? editedAt})>[
      (label: '当前版本', content: message.content, editedAt: null),
      for (var index = records.length - 1; index >= 0; index--)
        (
          label: '第 ${index + 1} 次编辑前',
          content: records[index].content,
          editedAt: records[index].editedAt,
        ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: kOpenHandBorderRadius14,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(
                    Icons.history_rounded,
                    color: colors.onPrimaryContainer,
                    size: 22,
                  ),
                ),
              ),
              kOpenHandHGap12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '消息编辑历史',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    kOpenHandGap3,
                    Text(
                      '共 ${records.length} 次编辑，保留最近版本变化。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          kOpenHandGap16,
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: kOpenHandBorderRadius14,
              border: Border.all(
                color: colors.outlineVariant.withValues(alpha: 0.72),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: colors.primary,
                  ),
                  kOpenHandHGap8,
                  Expanded(
                    child: Text(
                      '每个版本均来自钉钉消息实际编辑成功后的本地记录。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          kOpenHandGap12,
          SizedBox(
            height: historyHeight,
            child: ListView.separated(
              itemCount: versions.length,
              separatorBuilder: (_, index) => kOpenHandGap10,
              itemBuilder: (context, index) {
                final version = versions[index];
                final current = index == 0;
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  decoration: BoxDecoration(
                    color: current
                        ? colors.primaryContainer.withValues(alpha: 0.42)
                        : colors.surface,
                    borderRadius: kOpenHandBorderRadius16,
                    border: Border.all(
                      color: current
                          ? colors.primary.withValues(alpha: 0.58)
                          : colors.outlineVariant.withValues(alpha: 0.78),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            current
                                ? Icons.check_circle_outline_rounded
                                : Icons.restore_rounded,
                            size: 18,
                            color: current
                                ? colors.primary
                                : colors.onSurfaceVariant,
                          ),
                          kOpenHandHGap8,
                          Expanded(
                            child: Text(
                              version.label,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: current
                                    ? colors.onPrimaryContainer
                                    : colors.onSurface,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (version.editedAt != null)
                            Text(
                              formatYearMonthDayHmLocal(version.editedAt!),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                      kOpenHandGap10,
                      SelectableText(
                        version.content,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: current
                              ? colors.onPrimaryContainer
                              : colors.onSurface,
                          height: 1.55,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DingTalkMediaRail extends StatelessWidget {
  const _DingTalkMediaRail({
    required this.media,
    required this.mine,
    required this.loading,
    required this.failed,
    this.onRetry,
    this.onSaveFile,
    this.onInteractiveTap,
  });

  final List<DingTalkGatewayMedia> media;
  final bool mine;
  final bool loading;
  final bool failed;
  final VoidCallback? onRetry;
  final _DingTalkMediaSaveCallback? onSaveFile;
  final VoidCallback? onInteractiveTap;

  static const double _maxWidth = 760;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      widthFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxWidth),
        child: Padding(
          padding: const EdgeInsets.only(
            bottom: _dingtalkMediaRailBottomSpacing,
          ),
          child: Wrap(
            alignment: mine ? WrapAlignment.end : WrapAlignment.start,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in media)
                _DingTalkMediaTile(
                  key: ValueKey<String>(
                    '${item.resourceType.name}:${item.resourceId}',
                  ),
                  media: item,
                  mine: mine,
                  loading: loading,
                  failed: failed,
                  maxWidth: _maxWidth,
                  onRetry: onRetry,
                  onSaveFile: onSaveFile,
                  onInteractiveTap: onInteractiveTap,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DingTalkMediaTile extends StatelessWidget {
  const _DingTalkMediaTile({
    super.key,
    required this.media,
    required this.mine,
    required this.loading,
    required this.failed,
    required this.maxWidth,
    this.onRetry,
    this.onSaveFile,
    this.onInteractiveTap,
  });

  final DingTalkGatewayMedia media;
  final bool mine;
  final bool loading;
  final bool failed;
  final double maxWidth;
  final VoidCallback? onRetry;
  final _DingTalkMediaSaveCallback? onSaveFile;
  final VoidCallback? onInteractiveTap;

  Future<void> _open(BuildContext context) async {
    onInteractiveTap?.call();
    final path = media.localPath.trim();
    if (path.isEmpty || !await _pathExistsBounded(File(path))) {
      onRetry?.call();
      return;
    }
    if (media.kind == DingTalkMediaKind.file) {
      final opened = await openLocalPathWithSystemApp(
        path,
        tag: 'dingtalk_gateway',
      );
      if (!opened && context.mounted) {
        showOpenHandErrorSnack(context, '无法打开该文件。');
      }
      return;
    }
    if (!context.mounted) return;
    final kind = switch (media.kind) {
      DingTalkMediaKind.image => MediaPreviewKind.image,
      DingTalkMediaKind.video => MediaPreviewKind.video,
      DingTalkMediaKind.audio => MediaPreviewKind.audio,
      DingTalkMediaKind.file => MediaPreviewKind.audio,
    };
    unawaited(
      showAnimatedDialog<void>(
        context: context,
        builder: (_) => MediaPreviewDialog.file(
          filePath: path,
          title: media.displayName,
          mimeType: media.mimeType.isEmpty ? null : media.mimeType,
          kind: kind,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final path = media.localPath.trim();
    // 构建阶段不做同步磁盘访问，避免会话切换或滚动时阻塞 UI 线程；
    // 实际打开与图片解码失败会走异步兜底并提供重试入口。
    final available = path.isNotEmpty;
    if (media.kind == DingTalkMediaKind.file) {
      return _DingTalkFileMediaTile(
        media: media,
        failed: failed,
        onSaveFile: onSaveFile,
        onInteractiveTap: onInteractiveTap,
      );
    }
    if (available &&
        (media.kind == DingTalkMediaKind.video ||
            media.kind == DingTalkMediaKind.audio)) {
      final detail = p.basename(path).trim();
      return GeneratedMediaResultCard(
        kind: media.kind == DingTalkMediaKind.video
            ? GeneratedMediaResultKind.video
            : GeneratedMediaResultKind.audio,
        title: media.displayName,
        detail: detail.isEmpty ? media.displayName : detail,
        identity: path,
        textColor: mine ? colors.onPrimaryContainer : colors.onSurface,
        backgroundColor: mine
            ? colors.primaryContainer
            : colors.surfaceContainerHighest,
        videoPath: media.kind == DingTalkMediaKind.video ? path : null,
        videoMimeType: media.kind == DingTalkMediaKind.video
            ? media.mimeType
            : null,
        videoMaxWidth: maxWidth,
        onTap: () => unawaited(_open(context)),
      );
    }
    if (available && media.kind == DingTalkMediaKind.image) {
      return Tooltip(
        message: media.displayName,
        child: Material(
          color: colors.surfaceContainerHighest,
          borderRadius: kOpenHandBorderRadius14,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => unawaited(_open(context)),
            child: SizedBox(
              width: 190,
              height: 142,
              child: Image.file(
                File(path),
                fit: BoxFit.cover,
                cacheWidth: 380,
                errorBuilder: (_, _, _) => _missingContent(context),
              ),
            ),
          ),
        ),
      );
    }
    return Material(
      color: available
          ? colors.surfaceContainerHighest
          : colors.surfaceContainerLow,
      borderRadius: kOpenHandBorderRadius14,
      child: InkWell(
        onTap: loading ? null : () => unawaited(_open(context)),
        borderRadius: kOpenHandBorderRadius14,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                available
                    ? _iconForMedia(media.kind)
                    : loading
                    ? Icons.cloud_download_outlined
                    : failed
                    ? Icons.cloud_off_rounded
                    : Icons.cloud_download_outlined,
                size: 22,
                color: available ? colors.primary : colors.onSurfaceVariant,
              ),
              kOpenHandHGap8,
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  available
                      ? media.displayName
                      : loading
                      ? '正在缓存媒体…'
                      : failed
                      ? '媒体加载失败，点击重试'
                      : '点击加载媒体',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                  ),
                ),
              ),
              if (!available) ...[
                kOpenHandHGap4,
                if (loading)
                  const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (failed)
                  Icon(Icons.refresh_rounded, size: 17, color: colors.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _missingContent(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Center(
        child: IconButton(
          tooltip: '重新加载媒体',
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ),
    );
  }

  IconData _iconForMedia(DingTalkMediaKind kind) => switch (kind) {
    DingTalkMediaKind.image => Icons.image_outlined,
    DingTalkMediaKind.video => Icons.videocam_outlined,
    DingTalkMediaKind.audio => Icons.audiotrack_outlined,
    DingTalkMediaKind.file => Icons.insert_drive_file_outlined,
  };
}

class _DingTalkFileMediaTile extends StatefulWidget {
  const _DingTalkFileMediaTile({
    required this.media,
    required this.failed,
    required this.onSaveFile,
    this.onInteractiveTap,
  });

  final DingTalkGatewayMedia media;
  final bool failed;
  final _DingTalkMediaSaveCallback? onSaveFile;
  final VoidCallback? onInteractiveTap;

  @override
  State<_DingTalkFileMediaTile> createState() => _DingTalkFileMediaTileState();
}

class _DingTalkFileMediaTileState extends State<_DingTalkFileMediaTile> {
  bool _saving = false;
  bool _saveFailed = false;

  String get _path => widget.media.localPath.trim();

  Future<void> _save() async {
    if (_saving || widget.onSaveFile == null) return;
    widget.onInteractiveTap?.call();
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    try {
      var suggestedName = p
          .basename(widget.media.displayName.replaceAll(r'\', '/'))
          .trim()
          .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_');
      if (suggestedName.isEmpty ||
          suggestedName == '.' ||
          suggestedName == '/') {
        suggestedName = '钉钉文件';
      }
      final extension = p.extension(suggestedName).replaceFirst('.', '');
      final location = await getSaveLocation(
        suggestedName: suggestedName,
        acceptedTypeGroups: RegExp(r'^[a-zA-Z0-9]{1,12}$').hasMatch(extension)
            ? <XTypeGroup>[
                XTypeGroup(label: '文件', extensions: <String>[extension]),
              ]
            : const <XTypeGroup>[],
      );
      if (location == null || !mounted) return;
      await widget.onSaveFile!(widget.media, location.path);
      if (!mounted) return;
      showOpenHandSuccessSnack(context, '文件已保存到 ${location.path}', maxLines: 2);
    } catch (error, stack) {
      silentLog('dingtalk_gateway', '保存钉钉文件', error, stack);
      if (!mounted) return;
      setState(() => _saveFailed = true);
      showOpenHandErrorSnack(
        context,
        messageGatewayFailureMessage(error, fallback: '保存文件失败，请稍后重试。'),
        maxLines: 2,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _open() async {
    widget.onInteractiveTap?.call();
    final path = _path;
    if (path.isEmpty || !await _pathExistsBounded(File(path))) {
      if (mounted) showOpenHandErrorSnack(context, '文件已不存在，请重新下载保存。');
      return;
    }
    final opened = await openLocalPathWithSystemApp(
      path,
      tag: 'dingtalk_gateway.open_file',
    );
    if (!opened && mounted) {
      showOpenHandErrorSnack(context, '无法打开该文件。');
    }
  }

  Future<void> _openDirectory() async {
    widget.onInteractiveTap?.call();
    final path = _path;
    if (path.isEmpty || !await _pathExistsBounded(File(path))) {
      if (mounted) showOpenHandErrorSnack(context, '文件已不存在，无法打开所在目录。');
      return;
    }
    final opened = await openLocalPathWithSystemApp(
      p.dirname(path),
      tag: 'dingtalk_gateway.open_file_directory',
    );
    if (!opened && mounted) {
      showOpenHandErrorSnack(context, '无法打开文件所在目录。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final available = _path.isNotEmpty;
    final failed = !available && (_saveFailed || widget.failed);
    final statusLabel = available
        ? widget.media.sizeBytes > 0
              ? formatByteSize(widget.media.sizeBytes)
              : '文件已保存'
        : _saving
        ? '正在保存文件…'
        : failed
        ? '保存失败，请重试'
        : '选择位置并保存';
    return Semantics(
      container: true,
      label: '${widget.media.displayName}，$statusLabel',
      child: AnimatedContainer(
        duration: openHandMotionDuration(context, kOpenHandMotion180),
        curve: kOpenHandSwitchInCurve,
        constraints: const BoxConstraints(maxWidth: 420, minHeight: 62),
        decoration: BoxDecoration(
          color: available
              ? colors.surfaceContainerHighest
              : colors.surfaceContainerLow,
          borderRadius: kOpenHandBorderRadius14,
          border: Border.all(
            color: failed
                ? colors.error.withValues(alpha: 0.48)
                : colors.outlineVariant.withValues(alpha: 0.72),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: MouseRegion(
                  cursor: _saving
                      ? SystemMouseCursors.basic
                      : SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _saving
                        ? null
                        : available
                        ? () => unawaited(_open())
                        : () => unawaited(_save()),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: colors.primaryContainer,
                              borderRadius: kOpenHandBorderRadius10,
                            ),
                            child: Icon(
                              _dingtalkAttachmentIcon(widget.media.displayName),
                              size: 22,
                              color: colors.onPrimaryContainer,
                            ),
                          ),
                          kOpenHandHGap10,
                          Flexible(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.media.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: colors.onSurface,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                kOpenHandGap2,
                                AnimatedSwitcher(
                                  duration: openHandMotionDuration(
                                    context,
                                    kOpenHandMotion180,
                                  ),
                                  child: Text(
                                    statusLabel,
                                    key: ValueKey<String>(statusLabel),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: failed
                                          ? colors.error
                                          : colors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (available)
                MicroPressFeedback(
                  scale: 0.9,
                  child: IconButton(
                    tooltip: '打开文件所在目录',
                    onPressed: _saving
                        ? null
                        : () => unawaited(_openDirectory()),
                    icon: const Icon(Icons.folder_open_rounded, size: 20),
                  ),
                ),
              if (!available)
                MicroPressFeedback(
                  enabled: !_saving && widget.onSaveFile != null,
                  scale: 0.9,
                  child: IconButton(
                    tooltip: '下载并保存文件',
                    onPressed: _saving || widget.onSaveFile == null
                        ? null
                        : () => unawaited(_save()),
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.download_rounded,
                            size: 20,
                            color: colors.primary,
                          ),
                  ),
                ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _DingTalkConversationDetailsDialog extends StatelessWidget {
  const _DingTalkConversationDetailsDialog({
    required this.controller,
    required this.conversation,
  });

  final DingTalkMessageGatewayController controller;
  final DingTalkConversation conversation;

  @override
  Widget build(BuildContext context) {
    final isGroup = conversation.type == DingTalkConversationType.group;
    final title = openHandLocalizedText(
      context,
      zh: isGroup ? '群聊详情' : '联系人详情',
      zhHant: isGroup ? '群聊詳情' : '聯絡人詳情',
      en: isGroup ? 'Group details' : 'Contact details',
      fr: isGroup ? 'Détails du groupe' : 'Détails du contact',
      de: isGroup ? 'Gruppendetails' : 'Kontaktdetails',
      ja: isGroup ? 'グループ詳細' : '連絡先の詳細',
    );
    return FutureBuilder<Object?>(
      future: controller.loadConversationDetails(conversation.id),
      builder: (context, snapshot) {
        final content = snapshot.connectionState != ConnectionState.done
            ? const SizedBox(
                height: 240,
                child: Center(child: CircularProgressIndicator()),
              )
            : snapshot.hasError
            ? KnowledgeDialogNotice(
                icon: Icons.error_outline_rounded,
                message: openHandLocalizedText(
                  context,
                  zh: '读取详情失败，请稍后重试。',
                  zhHant: '讀取詳情失敗，請稍後重試。',
                  en: 'Unable to load details. Try again later.',
                  fr: 'Impossible de charger les détails. Réessayez plus tard.',
                  de: 'Details konnten nicht geladen werden. Bitte später erneut versuchen.',
                  ja: '詳細を読み込めません。後でもう一度お試しください。',
                ),
                tone: KnowledgeDialogNoticeTone.error,
              )
            : snapshot.data == null
            ? KnowledgeDialogNotice(
                icon: Icons.info_outline_rounded,
                message: openHandLocalizedText(
                  context,
                  zh: '暂无可用详情',
                  zhHant: '暫無可用詳情',
                  en: 'No details are available.',
                  fr: 'Aucun détail disponible.',
                  de: 'Keine Details verfügbar.',
                  ja: '利用できる詳細はありません。',
                ),
              )
            : _DingTalkDetailsView(
                value: snapshot.data!,
                conversation: conversation,
              );
        return buildOpenHandAlertDialog(
          icon: Icon(
            isGroup ? Icons.groups_rounded : Icons.person_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: Text(
            '${conversation.title} · $title',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          content: buildOpenHandDialogConstrainedContent(
            width: 760,
            maxHeight: MediaQuery.sizeOf(context).height * 0.78,
            child: AnimatedSwitcher(
              duration: openHandMotionDurationMs(context, 240),
              switchInCurve: kOpenHandSwitchInCurve,
              switchOutCurve: kOpenHandSwitchOutCurve,
              child: content,
            ),
          ),
          actions: [
            OpenHandDialogActionButton.primary(
              onPressed: () => Navigator.of(context).pop(),
              label: openHandCloseLabel(context),
            ),
          ],
        );
      },
    );
  }
}

class _DingTalkDetailsView extends StatefulWidget {
  const _DingTalkDetailsView({required this.value, required this.conversation});

  final Object value;
  final DingTalkConversation conversation;

  @override
  State<_DingTalkDetailsView> createState() => _DingTalkDetailsViewState();
}

class _DingTalkDetailsViewState extends State<_DingTalkDetailsView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final document = _buildDingTalkDetailDocument(widget.value);
    final sections = <Widget>[
      _DingTalkDetailIdentityCard(conversation: widget.conversation),
      if (document.conversation.isNotEmpty)
        _DingTalkDetailCardGroup(
          title: '会话概览',
          icon: Icons.forum_rounded,
          parentScrollController: _scrollController,
          badge: _dingtalkDetailCountLabel(
            context,
            document.conversation.length,
          ),
          child: _DingTalkDetailGrid(data: document.conversation),
        ),
      if (document.contact.isNotEmpty)
        _DingTalkDetailCardGroup(
          title: '联系人资料',
          icon: Icons.person_rounded,
          parentScrollController: _scrollController,
          badge: _dingtalkDetailCountLabel(context, document.contact.length),
          child: _DingTalkDetailGrid(data: document.contact),
        ),
      if (document.profile.isNotEmpty)
        _DingTalkDetailCardGroup(
          title: '员工档案',
          icon: Icons.badge_rounded,
          parentScrollController: _scrollController,
          badge: _dingtalkDetailCountLabel(context, document.profile.length),
          child: _DingTalkDetailGrid(data: document.profile),
        ),
      for (final entry in document.supplemental.entries)
        if (_dingtalkDetailHasContent(entry.value))
          _DingTalkDetailCardGroup(
            title: entry.key,
            icon: _dingtalkDetailSectionIcon(entry.key),
            maxContentHeight: _dingtalkDetailSectionMaxHeight(entry.key),
            parentScrollController: _scrollController,
            badge: _dingtalkDetailCountLabel(
              context,
              _dingtalkDetailItemCount(entry.value),
            ),
            child: _DingTalkDetailValue(value: entry.value),
          ),
    ];
    return SingleChildScrollView(
      controller: _scrollController,
      key: const PageStorageKey<String>('dingtalk-details'),
      physics: kOpenHandClampingPhysics,
      padding: const EdgeInsets.fromLTRB(2, 2, 4, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < sections.length; index++)
            Padding(
              padding: EdgeInsets.only(
                bottom: index == sections.length - 1 ? 0 : 12,
              ),
              child: sections[index],
            ),
          if (document.members.isNotEmpty) ...[
            if (sections.isNotEmpty) kOpenHandGap12,
            _DingTalkDetailCardGroup(
              title: '群成员',
              icon: Icons.people_alt_rounded,
              maxContentHeight: 440,
              parentScrollController: _scrollController,
              badge: _dingtalkDetailCountLabel(
                context,
                document.members.length,
                unit: '人',
              ),
              child: Column(
                children: [
                  for (var index = 0; index < document.members.length; index++)
                    Padding(
                      padding: EdgeInsets.only(top: index == 0 ? 0 : 10),
                      child: _DingTalkMemberCard(
                        details: document.members[index],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DingTalkDetailCardGroup extends StatelessWidget {
  const _DingTalkDetailCardGroup({
    required this.title,
    required this.icon,
    required this.badge,
    required this.child,
    this.maxContentHeight,
    this.parentScrollController,
  });

  final String title;
  final IconData icon;
  final String badge;
  final Widget child;
  final double? maxContentHeight;
  final ScrollController? parentScrollController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainer.withValues(alpha: 0.86),
        borderRadius: kOpenHandBorderRadius14,
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.84),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest.withValues(
                      alpha: 0.78,
                    ),
                    borderRadius: BorderRadius.circular(kOpenHandRadius9),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 18, color: colors.primary),
                ),
                kOpenHandHGap10,
                Expanded(
                  child: Text(
                    _displayDingTalkDetailLabel(context, title),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest.withValues(
                      alpha: 0.7,
                    ),
                    borderRadius: BorderRadius.circular(kOpenHandRadius10),
                  ),
                  child: Text(
                    badge,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            kOpenHandGap12,
            if (maxContentHeight != null)
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxContentHeight!),
                child: NotificationListener<OverscrollNotification>(
                  onNotification: (notification) {
                    final parent = parentScrollController;
                    if (parent == null || !parent.hasClients) return false;
                    final position = parent.position;
                    final target = (position.pixels + notification.overscroll)
                        .clamp(
                          position.minScrollExtent,
                          position.maxScrollExtent,
                        )
                        .toDouble();
                    if ((target - position.pixels).abs() < 0.5) return false;
                    parent.jumpTo(target);
                    return true;
                  },
                  child: SingleChildScrollView(
                    primary: false,
                    physics: kOpenHandClampingPhysics,
                    padding: const EdgeInsets.only(right: 4),
                    child: child,
                  ),
                ),
              )
            else
              child,
          ],
        ),
      ),
    );
  }
}

class _DingTalkDetailGrid extends StatelessWidget {
  const _DingTalkDetailGrid({required this.data});

  final Map<String, Object?> data;

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.toList(growable: false);
    final simpleEntries = entries
        .where((e) => !_dingtalkIsCompound(e.value))
        .toList();
    final compoundEntries = entries
        .where((e) => _dingtalkIsCompound(e.value))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (simpleEntries.isNotEmpty)
          KnowledgeDialogKeyValueList(
            rows: Map<String, Object?>.fromEntries(
              simpleEntries.map(
                (entry) => MapEntry(
                  entry.key,
                  _formatDingTalkDetailValue(
                    context,
                    entry.value,
                    label: entry.key,
                  ),
                ),
              ),
            ),
            labelWidth: openHandIsChineseLocale(context) ? 118 : 138,
          ),
        if (compoundEntries.isNotEmpty) ...[
          if (simpleEntries.isNotEmpty) kOpenHandGap8,
          for (final entry in compoundEntries) ...[
            _DingTalkDetailNestedSection(label: entry.key, value: entry.value),
            kOpenHandGap8,
          ],
        ],
      ],
    );
  }
}

class _DingTalkDetailDocument {
  const _DingTalkDetailDocument({
    required this.conversation,
    required this.contact,
    required this.profile,
    required this.members,
    required this.supplemental,
  });

  final Map<String, Object?> conversation;
  final Map<String, Object?> contact;
  final Map<String, Object?> profile;
  final List<Map<String, Object?>> members;
  final Map<String, Object?> supplemental;
}

_DingTalkDetailDocument _buildDingTalkDetailDocument(Object value) {
  final unwrappedRoot = _unwrapDingTalkDetailValue(value);
  final root = stringKeyedMapFromValue(unwrappedRoot);
  final rootList = unwrappedRoot is List ? unwrappedRoot : null;
  Object? payload(String name, Set<String> aliases) {
    for (final key in aliases) {
      if (root.containsKey(key)) return root[key];
    }
    return null;
  }

  final conversationPayload = payload('会话信息', const <String>{
    '会话信息',
    'conversationInfo',
    'conversation_info',
  });
  final contactPayload = payload('联系人信息', const <String>{
    '联系人信息',
    'contactInfo',
    'contact_info',
    'user',
  });
  final membersPayload =
      payload('群成员', const <String>{'群成员', 'members', 'memberList'}) ??
      rootList;
  final memberProfilesPayload = payload('群成员资料', const <String>{
    '群成员资料',
    'memberProfiles',
    'member_profiles',
  });
  final memberDetailsPayload = payload('群成员详情', const <String>{
    '群成员详情',
    'memberDetails',
    'member_details',
  });
  final memberRolesPayload = payload('群成员身份', const <String>{
    '群成员身份',
    'memberRoles',
    'member_roles',
  });
  final profilePayload = payload('员工档案', const <String>{
    '员工档案',
    '联系人档案',
    'profile',
    'userProfile',
    'user_profile',
  });
  final conversationValue = _unwrapDingTalkDetailValue(
    _findDingTalkDetailValue(conversationPayload, const <String>{
          'conversationInfo',
          'conversation_info',
        }) ??
        conversationPayload,
  );
  final contactValue = _unwrapDingTalkDetailValue(contactPayload);
  final profileValue = _unwrapDingTalkDetailValue(profilePayload);
  final supplemental = <String, Object?>{};
  for (final key in const <String>[
    '群聊设置',
    '禁言配置',
    '群机器人',
    '群身份',
    '可见花名册字段',
    '部门资料',
    '关注状态',
  ]) {
    final raw = payload(key, <String>{key});
    if (raw != null) {
      supplemental[key] = _humanizeDingTalkValue(raw);
    }
  }
  const knownRootKeys = <String>{
    '会话信息',
    'conversationInfo',
    'conversation_info',
    '联系人信息',
    'contactInfo',
    'contact_info',
    'user',
    '群成员',
    'members',
    'memberList',
    '群成员资料',
    'memberProfiles',
    'member_profiles',
    '群成员详情',
    'memberDetails',
    'member_details',
    '群成员身份',
    'memberRoles',
    'member_roles',
    '员工档案',
    '联系人档案',
    'profile',
    'userProfile',
    'user_profile',
    '群聊设置',
    '禁言配置',
    '群机器人',
    '群身份',
    '可见花名册字段',
    '部门资料',
    '关注状态',
  };
  final otherRootFields = <String, Object?>{};
  for (final entry in root.entries) {
    if (knownRootKeys.contains(entry.key) ||
        _dingtalkProtocolDetailKeys.contains(entry.key) ||
        entry.value == null) {
      continue;
    }
    otherRootFields[entry.key] = entry.value;
  }
  if (otherRootFields.isNotEmpty) {
    final humanized = _humanizeDingTalkMap(otherRootFields);
    if (humanized.isNotEmpty) supplemental['其他资料'] = humanized;
  }
  return _DingTalkDetailDocument(
    conversation: _humanizeDingTalkMap(conversationValue),
    contact: _humanizeDingTalkMap(contactValue),
    profile: _humanizeDingTalkMap(profileValue),
    members: _mergeDingTalkMembers(
      _collectDingTalkMembers(membersPayload),
      _collectDingTalkMembers(memberProfilesPayload),
      _collectDingTalkMembers(memberDetailsPayload),
      _collectDingTalkMembers(memberRolesPayload),
    ),
    supplemental: supplemental,
  );
}

class _DingTalkMemberCard extends StatelessWidget {
  const _DingTalkMemberCard({required this.details});

  final Map<String, Object?> details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final name = '${details['姓名'] ?? ''}'.trim();
    final role = '${details['群内角色'] ?? ''}'.trim();
    final fields = Map<String, Object?>.from(details)
      ..remove('姓名')
      ..remove('群内角色');
    final accent = colors.primary;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.64),
        borderRadius: kOpenHandBorderRadius12,
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.68),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: accent.withValues(alpha: 0.18),
                  child: Icon(Icons.person_rounded, size: 16, color: accent),
                ),
                kOpenHandHGap10,
                Expanded(
                  child: Text(
                    name.isEmpty
                        ? openHandLocalizedText(
                            context,
                            zh: '未命名成员',
                            zhHant: '未命名成員',
                            en: 'Unnamed member',
                            fr: 'Membre sans nom',
                            de: 'Unbenanntes Mitglied',
                            ja: '名前なしのメンバー',
                          )
                        : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (role.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: kOpenHandBorderRadius8,
                    ),
                    child: Text(
                      _dingtalkRoleLabel(context, role),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
            if (fields.isNotEmpty) ...[
              kOpenHandGap12,
              _DingTalkDetailGrid(data: fields),
            ],
          ],
        ),
      ),
    );
  }
}

class _DingTalkDetailIdentityCard extends StatelessWidget {
  const _DingTalkDetailIdentityCard({required this.conversation});

  final DingTalkConversation conversation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isGroup = conversation.type == DingTalkConversationType.group;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.74),
        borderRadius: kOpenHandBorderRadius14,
        border: Border.all(color: colors.primary.withValues(alpha: 0.24)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(kOpenHandRadius11),
              ),
              alignment: Alignment.center,
              child: Icon(
                isGroup ? Icons.groups_rounded : Icons.person_rounded,
                size: 20,
                color: colors.onPrimaryContainer,
              ),
            ),
            kOpenHandHGap11,
            Expanded(
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest.withValues(
                        alpha: 0.58,
                      ),
                      borderRadius: kOpenHandBorderRadius8,
                    ),
                    child: Text(
                      isGroup
                          ? openHandLocalizedText(
                              context,
                              zh: '群聊',
                              zhHant: '群聊',
                              en: 'Group',
                              fr: 'Groupe',
                              de: 'Gruppe',
                              ja: 'グループ',
                            )
                          : openHandLocalizedText(
                              context,
                              zh: '联系人',
                              zhHant: '聯絡人',
                              en: 'Contact',
                              fr: 'Contact',
                              de: 'Kontakt',
                              ja: '連絡先',
                            ),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  kOpenHandHGap9,
                  Expanded(
                    child: SelectableText(
                      _dingtalkConversationIdLabel(context, conversation.id),
                      maxLines: 1,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DingTalkDetailValue extends StatelessWidget {
  const _DingTalkDetailValue({required this.value});

  final Object? value;

  @override
  Widget build(BuildContext context) {
    if (value is Map) {
      return _DingTalkDetailGrid(data: stringKeyedMapFromValue(value));
    }
    if (value is List) {
      final list = value as List;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < list.length; index++) ...[
            if (index > 0) kOpenHandGap8,
            _DingTalkDetailNestedSection(
              label: _dingtalkDetailIndexLabel(context, index),
              value: list[index],
            ),
          ],
        ],
      );
    }
    return _DingTalkDetailField(label: '值', value: value);
  }
}

class _DingTalkDetailNestedSection extends StatelessWidget {
  const _DingTalkDetailNestedSection({
    required this.label,
    required this.value,
  });

  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final content = _DingTalkDetailValue(value: value);
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.46),
        borderRadius: kOpenHandBorderRadius12,
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.68),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest.withValues(alpha: 0.76),
                  borderRadius: kOpenHandBorderRadius8,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.account_tree_rounded,
                  size: 16,
                  color: colors.primary,
                ),
              ),
              kOpenHandHGap8,
              Expanded(
                child: Text(
                  _displayDingTalkDetailLabel(context, label),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface.withValues(alpha: 0.9),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2.5,
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest.withValues(alpha: 0.72),
                  borderRadius: kOpenHandBorderRadius12,
                ),
                child: Text(
                  _dingtalkDetailCountLabel(
                    context,
                    _dingtalkDetailItemCount(value),
                  ),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          kOpenHandGap10,
          AnimatedSize(
            duration: openHandMotionDurationMs(context, 220),
            curve: kOpenHandSwitchInCurve,
            alignment: Alignment.topCenter,
            child: content,
          ),
        ],
      ),
    );
  }
}

class _DingTalkDetailField extends StatelessWidget {
  const _DingTalkDetailField({required this.label, required this.value});

  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) {
    return KnowledgeDialogKeyValueList(
      rows: <String, Object?>{
        _displayDingTalkDetailLabel(context, label): _formatDingTalkDetailValue(
          context,
          value,
          label: label,
        ),
      },
      labelWidth: openHandIsChineseLocale(context) ? 118 : 138,
    );
  }
}

const Set<String> _dingtalkProtocolDetailKeys = <String>{
  'arguments',
  'code',
  'data',
  'error',
  'errors',
  'errorCode',
  'errorMsg',
  'friendly_hint',
  'hasMore',
  'message',
  'nextCursor',
  'next_cursor',
  'requestId',
  'request_id',
  'result',
  'success',
  'statusCode',
  'traceId',
};

const Set<String> _dingtalkMemberIdentityKeys = <String>{
  'memberDingtalkId',
  'memberEmpName',
  'memberNick',
  'memberUserId',
  'member_user_id',
  'openDingTalkId',
  'openDingtalkId',
  'orgUserId',
  'org_user_id',
  'orgUserName',
  'userId',
  'user_id',
};

Object? _findDingTalkDetailValue(Object? value, Set<String> keys) {
  if (value is Map) {
    for (final entry in value.entries) {
      if (keys.contains('${entry.key}')) return entry.value;
    }
    for (final entry in value.entries) {
      final found = _findDingTalkDetailValue(entry.value, keys);
      if (found != null) return found;
    }
  } else if (value is List) {
    for (final item in value) {
      final found = _findDingTalkDetailValue(item, keys);
      if (found != null) return found;
    }
  }
  return null;
}

Object? _unwrapDingTalkDetailValue(Object? value) {
  var current = value;
  for (var depth = 0; depth < 5; depth++) {
    if (current is! Map) return current;
    final map = stringKeyedMapFromValue(current);
    final nested = map['result'] ?? map['data'];
    final meaningful = map.keys.where(
      (key) => !_dingtalkProtocolDetailKeys.contains(key),
    );
    if (nested != null && meaningful.isEmpty) {
      current = nested;
      continue;
    }
    return current;
  }
  return current;
}

Map<String, Object?> _humanizeDingTalkMap(
  Object? value, {
  bool member = false,
}) {
  final unwrapped = _unwrapDingTalkDetailValue(value);
  if (unwrapped is List) {
    final merged = <String, Object?>{};
    for (final item in unwrapped.whereType<Map>()) {
      final fields = _humanizeDingTalkMap(item, member: member);
      for (final entry in fields.entries) {
        var label = entry.key;
        var duplicateIndex = 1;
        while (merged.containsKey(label)) {
          duplicateIndex += 1;
          label = '${entry.key} $duplicateIndex';
        }
        merged[label] = entry.value;
      }
    }
    return merged;
  }
  final source = unwrapped;
  if (source is! Map) return <String, Object?>{};
  final raw = stringKeyedMapFromValue(source);
  final result = <String, Object?>{};
  String? preferredName;
  if (member) {
    for (final key in const <String>[
      'memberNick',
      'memberEmpName',
      'memberGroupNick',
      'orgUserName',
      'name',
      'nick',
      'userName',
      'displayName',
    ]) {
      final candidate = '${raw[key] ?? ''}'.trim();
      if (candidate.isNotEmpty) {
        preferredName = candidate;
        break;
      }
    }
  }
  var extraIndex = 0;
  for (final entry in raw.entries) {
    final key = entry.key;
    final normalizedKey = key.trim();
    if (normalizedKey.isEmpty ||
        _dingtalkProtocolDetailKeys.contains(normalizedKey) ||
        entry.value == null) {
      continue;
    }
    if (member &&
        const <String>{
          'memberNick',
          'memberEmpName',
          'orgUserName',
          'name',
          'nick',
          'userName',
          'displayName',
        }.contains(normalizedKey)) {
      continue;
    }
    final label = _canonicalDingTalkDetailLabel(normalizedKey);
    final valueToShow = _sanitizeDingTalkDetailValue(entry.value);
    if (valueToShow is Map && valueToShow.isEmpty) continue;
    if (valueToShow is String && valueToShow.trim().isEmpty) continue;
    var displayLabel = label;
    if (result.containsKey(displayLabel)) {
      extraIndex += 1;
      displayLabel = '$label $extraIndex';
    }
    result[displayLabel] = valueToShow;
  }
  if (preferredName != null) {
    return <String, Object?>{'姓名': preferredName, ...result};
  }
  return result;
}

Object? _sanitizeDingTalkDetailValue(Object? value) {
  if (value is Map) return _humanizeDingTalkMap(value);
  if (value is List) {
    return value
        .map(_sanitizeDingTalkDetailValue)
        .where((item) => item != null)
        .toList(growable: false);
  }
  return value;
}

Object? _humanizeDingTalkValue(Object? value) {
  final unwrapped = _unwrapDingTalkDetailValue(value);
  if (unwrapped is Map) return _humanizeDingTalkMap(unwrapped);
  if (unwrapped is List) {
    return unwrapped
        .map(_humanizeDingTalkValue)
        .where((item) => _dingtalkDetailHasContent(item))
        .toList(growable: false);
  }
  return unwrapped;
}

bool _dingtalkDetailHasContent(Object? value) {
  if (value == null) return false;
  if (value is String) return value.trim().isNotEmpty;
  if (value is Map) return value.isNotEmpty;
  if (value is List) return value.isNotEmpty;
  return true;
}

IconData _dingtalkDetailSectionIcon(String title) {
  return switch (title) {
    '群聊设置' => Icons.tune_rounded,
    '禁言配置' => Icons.volume_off_rounded,
    '群机器人' => Icons.smart_toy_rounded,
    '群身份' || '群成员身份' => Icons.workspace_premium_rounded,
    '可见花名册字段' || '员工档案' => Icons.badge_rounded,
    '部门资料' => Icons.account_tree_rounded,
    '关注状态' => Icons.star_rounded,
    _ => Icons.info_outline_rounded,
  };
}

double? _dingtalkDetailSectionMaxHeight(String title) {
  return switch (title) {
    '群机器人' || '群身份' || '可见花名册字段' || '部门资料' => 440,
    _ => null,
  };
}

String _canonicalDingTalkDetailLabel(String key) {
  const labels = <String, String>{
    'active': '是否激活',
    'avatarUrl': '头像地址',
    'avatarMediaId': '头像媒体标识',
    'botCode': '机器人编码',
    'botName': '机器人名称',
    'botOpenDingTalkId': '机器人账号',
    'corpId': '企业标识',
    'corpName': '企业名称',
    'createAt': '创建时间',
    'createdAt': '创建时间',
    'deptId': '部门标识',
    'deptName': '部门',
    'depts': '所属部门',
    'departmentId': '部门标识',
    'departmentName': '部门',
    'description': '描述',
    'displayName': '姓名',
    'email': '邮箱',
    'employeeStatus': '员工状态',
    'employeeType': '员工类型',
    'extension': '扩展属性',
    'fieldCode': '字段标识',
    'field_code': '字段标识',
    'fieldName': '字段名称',
    'field_name': '字段名称',
    'fieldValue': '字段内容',
    'field_value': '字段内容',
    'gender': '性别',
    'isActive': '是否在职',
    'isAdmin': '管理员权限',
    'isBoss': '企业负责人',
    'isHide': '是否隐藏',
    'isLeader': '主管权限',
    'isFollowing': '是否特别关注',
    'isMuted': '是否被禁言',
    'isNotDisturb': '是否免打扰',
    'isPinned': '是否置顶',
    'isTop': '是否置顶',
    'jobNumber': '工号',
    'newCSpaceIdIM': '钉盘空间标识',
    'memberCount': '成员数量',
    'memberDingtalkId': '钉钉账号',
    'memberAvatarMediaId': '头像媒体标识',
    'memberEmpName': '姓名',
    'memberGroupNick': '群内昵称',
    'memberNick': '姓名',
    'memberRoleDesc': '群内角色',
    'memberRoleType': '角色类型',
    'memberUserId': '成员账号',
    'muteAllMembers': '全员禁言白名单',
    'muteMembers': '禁言成员',
    'muteTime': '操作时间',
    'mobile': '手机号',
    'orgId': '组织标识',
    'orgMasterDisplayName': '直属主管',
    'orgMasterUserId': '直属主管标识',
    'openConversationId': '会话标识',
    'openDingTalkId': '钉钉用户标识',
    'openDingtalkId': '钉钉用户标识',
    'orgName': '组织',
    'orgEmployeeModel': '组织资料',
    'orgUserId': '钉钉用户标识',
    'orgUserName': '姓名',
    'ownerNick': '群主',
    'parentId': '上级部门标识',
    'parentDeptId': '上级部门标识',
    'position': '职位',
    'remark': '备注',
    'singleChat': '聊天类型',
    'status': '状态',
    'type': '类型',
    'id': '标识',
    'settings': '设置',
    'notification': '通知',
    'roleId': '群身份标识',
    'roleName': '群身份名称',
    'openRoleId': '群身份标识',
    'robotCode': '机器人编码',
    'robotName': '机器人名称',
    'groupNick': '个人群昵称',
    'groupRemark': '群备注',
    'top': '是否置顶',
    'unreadCount': '未读消息数',
    'deptUserCount': '部门人数',
    'order': '排序值',
    'createDeptGroup': '是否创建部门群',
    'directSubdepartments': '直属子部门',
    'departmentInfo': '部门详情',
    'roles': '群身份',
    'title': '群聊名称',
    'value': '字段内容',
    'fieldList': '字段列表',
    'fieldValueList': '字段内容列表',
    'labels': '组织角色',
    'workPlace': '办公地点',
    'user_id': '钉钉用户标识',
    'org_user_id': '钉钉用户标识',
    'org_user_name': '姓名',
    'department': '部门',
    'name': '姓名',
    'nick': '姓名',
    'userName': '姓名',
    'userId': '钉钉用户标识',
    'unionId': '钉钉用户标识',
  };
  final translated = labels[key];
  if (translated != null) return translated;
  if (key.contains(RegExp(r'[\u4e00-\u9fff]'))) return key;
  final compact = key.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toLowerCase();
  if (compact.startsWith('setting')) return '设置';
  if (compact.startsWith('notification')) return '通知';
  if (compact.startsWith('member')) return '成员资料';
  if (compact.startsWith('department') || compact.startsWith('dept')) {
    return '部门资料';
  }
  return '其他资料';
}

List<Map<String, Object?>> _collectDingTalkMembers(Object? value) {
  final collected = <Map<String, Object?>>[];
  void visit(Object? current) {
    if (current is Map) {
      final map = stringKeyedMapFromValue(current);
      if (map.keys.any(_dingtalkMemberIdentityKeys.contains)) {
        final details = _humanizeDingTalkMap(map, member: true);
        if (details.isNotEmpty) collected.add(details);
        return;
      }
      for (final item in map.values) {
        visit(item);
      }
    } else if (current is List) {
      for (final item in current) {
        visit(item);
      }
    }
  }

  visit(value);
  final seen = <String>{};
  return collected
      .where((item) {
        final identities = _dingtalkMemberIdentities(item);
        if (identities.isEmpty || identities.any(seen.contains)) return false;
        seen.addAll(identities);
        return true;
      })
      .toList(growable: false);
}

List<Map<String, Object?>> _mergeDingTalkMembers(
  List<Map<String, Object?>> base,
  List<Map<String, Object?>> profiles, [
  List<Map<String, Object?>> details = const <Map<String, Object?>>[],
  List<Map<String, Object?>> roles = const <Map<String, Object?>>[],
]) {
  if (profiles.isEmpty && details.isEmpty && roles.isEmpty) return base;
  final merged = base.map(Map<String, Object?>.from).toList(growable: true);
  final indexes = <String, int>{};
  for (var index = 0; index < merged.length; index++) {
    for (final identity in _dingtalkMemberIdentities(merged[index])) {
      indexes[identity] = index;
    }
  }
  for (final profile in <Map<String, Object?>>[
    ...profiles,
    ...details,
    ...roles,
  ]) {
    final identities = _dingtalkMemberIdentities(profile);
    final existingIndex = identities
        .map((id) => indexes[id])
        .nonNulls
        .firstOrNull;
    if (existingIndex == null) {
      merged.add(profile);
      for (final identity in identities) {
        indexes[identity] = merged.length - 1;
      }
      continue;
    }
    merged[existingIndex] = <String, Object?>{
      ...merged[existingIndex],
      ...profile,
    };
    for (final identity in _dingtalkMemberIdentities(merged[existingIndex])) {
      indexes[identity] = existingIndex;
    }
  }
  return merged;
}

Set<String> _dingtalkMemberIdentities(Map<String, Object?> details) {
  final identities = <String>{};
  for (final entry in details.entries) {
    if (entry.key.startsWith('钉钉用户标识') ||
        entry.key.startsWith('钉钉账号') ||
        entry.key.startsWith('成员账号')) {
      final value = '${entry.value ?? ''}'.trim();
      if (value.isNotEmpty) identities.add(value);
    }
  }
  if (identities.isEmpty) {
    final name = '${details['姓名'] ?? ''}'.trim();
    if (name.isNotEmpty) identities.add(name);
  }
  return identities;
}

bool _dingtalkIsCompound(Object? value) => value is Map || value is List;

int _dingtalkDetailItemCount(Object? value) {
  if (value is Map) return value.length;
  if (value is List) return value.length;
  return 1;
}

String _dingtalkConversationIdLabel(BuildContext context, String id) {
  final label = openHandLocalizedText(
    context,
    zh: '会话标识',
    zhHant: '會話標識',
    en: 'Conversation ID',
    fr: 'Identifiant de conversation',
    de: 'Gesprächs-ID',
    ja: '会話 ID',
  );
  return '$label: $id';
}

const Map<String, ({String zhHant, String en, String fr, String de, String ja})>
_dingtalkExtendedDetailLabels =
    <String, ({String zhHant, String en, String fr, String de, String ja})>{
      '群聊设置': (
        zhHant: '群聊設定',
        en: 'Group settings',
        fr: 'Paramètres du groupe',
        de: 'Gruppeneinstellungen',
        ja: 'グループ設定',
      ),
      '禁言配置': (
        zhHant: '禁言設定',
        en: 'Mute settings',
        fr: 'Paramètres de sourdine',
        de: 'Stummschaltung',
        ja: 'ミュート設定',
      ),
      '群机器人': (
        zhHant: '群機器人',
        en: 'Group bots',
        fr: 'Robots du groupe',
        de: 'Gruppen-Bots',
        ja: 'グループボット',
      ),
      '群身份': (
        zhHant: '群身份',
        en: 'Group roles',
        fr: 'Rôles du groupe',
        de: 'Gruppenrollen',
        ja: 'グループロール',
      ),
      '可见花名册字段': (
        zhHant: '可見花名冊欄位',
        en: 'Visible roster fields',
        fr: 'Champs du registre visibles',
        de: 'Sichtbare Personalfelder',
        ja: '閲覧可能な名簿項目',
      ),
      '部门资料': (
        zhHant: '部門資料',
        en: 'Department details',
        fr: 'Détails du service',
        de: 'Abteilungsdetails',
        ja: '部署の詳細',
      ),
      '关注状态': (
        zhHant: '關注狀態',
        en: 'Following status',
        fr: 'Statut de suivi',
        de: 'Beobachtungsstatus',
        ja: 'フォロー状態',
      ),
      '员工档案': (
        zhHant: '員工檔案',
        en: 'Employee profile',
        fr: 'Dossier employé',
        de: 'Mitarbeiterprofil',
        ja: '従業員プロフィール',
      ),
      '扩展属性': (
        zhHant: '擴展屬性',
        en: 'Extended attributes',
        fr: 'Attributs étendus',
        de: 'Erweiterte Attribute',
        ja: '拡張属性',
      ),
      '补充信息': (
        zhHant: '補充資訊',
        en: 'Additional information',
        fr: 'Informations complémentaires',
        de: 'Zusätzliche Informationen',
        ja: '補足情報',
      ),
      '组织标识': (
        zhHant: '組織標識',
        en: 'Organization ID',
        fr: 'Identifiant de l’organisation',
        de: 'Organisations-ID',
        ja: '組織 ID',
      ),
      '部门标识': (
        zhHant: '部門標識',
        en: 'Department ID',
        fr: 'Identifiant du service',
        de: 'Abteilungs-ID',
        ja: '部署 ID',
      ),
      '所属部门': (
        zhHant: '所屬部門',
        en: 'Departments',
        fr: 'Services',
        de: 'Abteilungen',
        ja: '所属部署',
      ),
      '直属主管': (
        zhHant: '直屬主管',
        en: 'Direct manager',
        fr: 'Responsable direct',
        de: 'Direkte Führungskraft',
        ja: '直属の上司',
      ),
      '直属主管标识': (
        zhHant: '直屬主管標識',
        en: 'Manager ID',
        fr: 'Identifiant du responsable',
        de: 'Vorgesetzten-ID',
        ja: '上司 ID',
      ),
      '管理员权限': (
        zhHant: '管理員權限',
        en: 'Administrator',
        fr: 'Administrateur',
        de: 'Administrator',
        ja: '管理者権限',
      ),
      '主管权限': (
        zhHant: '主管權限',
        en: 'Manager role',
        fr: 'Rôle responsable',
        de: 'Führungsrolle',
        ja: '主管権限',
      ),
      '企业负责人': (
        zhHant: '企業負責人',
        en: 'Organization owner',
        fr: 'Responsable de l’organisation',
        de: 'Organisationsleitung',
        ja: '組織責任者',
      ),
      '是否激活': (
        zhHant: '是否啟用',
        en: 'Active',
        fr: 'Actif',
        de: 'Aktiv',
        ja: '有効',
      ),
      '是否在职': (
        zhHant: '是否在職',
        en: 'Employed',
        fr: 'En poste',
        de: 'Beschäftigt',
        ja: '在職中',
      ),
      '是否隐藏': (
        zhHant: '是否隱藏',
        en: 'Hidden',
        fr: 'Masqué',
        de: 'Ausgeblendet',
        ja: '非表示',
      ),
      '员工状态': (
        zhHant: '員工狀態',
        en: 'Employment status',
        fr: 'Statut employé',
        de: 'Beschäftigungsstatus',
        ja: '雇用状態',
      ),
      '工号': (
        zhHant: '工號',
        en: 'Employee number',
        fr: 'Matricule',
        de: 'Personalnummer',
        ja: '社員番号',
      ),
      '办公地点': (
        zhHant: '辦公地點',
        en: 'Workplace',
        fr: 'Lieu de travail',
        de: 'Arbeitsort',
        ja: '勤務地',
      ),
      '组织角色': (
        zhHant: '組織角色',
        en: 'Organization roles',
        fr: 'Rôles de l’organisation',
        de: 'Organisationsrollen',
        ja: '組織ロール',
      ),
      '组织资料': (
        zhHant: '組織資料',
        en: 'Organization profile',
        fr: 'Profil de l’organisation',
        de: 'Organisationsprofil',
        ja: '組織プロフィール',
      ),
      '成员账号': (
        zhHant: '成員帳號',
        en: 'Member account',
        fr: 'Compte du membre',
        de: 'Mitgliedskonto',
        ja: 'メンバーアカウント',
      ),
      '字段标识': (
        zhHant: '欄位標識',
        en: 'Field ID',
        fr: 'Identifiant du champ',
        de: 'Feld-ID',
        ja: 'フィールド ID',
      ),
      '字段名称': (
        zhHant: '欄位名稱',
        en: 'Field name',
        fr: 'Nom du champ',
        de: 'Feldname',
        ja: 'フィールド名',
      ),
      '字段内容': (
        zhHant: '欄位內容',
        en: 'Field value',
        fr: 'Valeur du champ',
        de: 'Feldwert',
        ja: 'フィールド値',
      ),
      '字段列表': (
        zhHant: '欄位列表',
        en: 'Fields',
        fr: 'Champs',
        de: 'Felder',
        ja: 'フィールド',
      ),
      '字段内容列表': (
        zhHant: '欄位內容列表',
        en: 'Field values',
        fr: 'Valeurs des champs',
        de: 'Feldwerte',
        ja: 'フィールド値',
      ),
      '头像地址': (
        zhHant: '頭像地址',
        en: 'Avatar URL',
        fr: 'URL de l’avatar',
        de: 'Avatar-URL',
        ja: 'アバター URL',
      ),
      '描述': (
        zhHant: '描述',
        en: 'Description',
        fr: 'Description',
        de: 'Beschreibung',
        ja: '説明',
      ),
      '性别': (
        zhHant: '性別',
        en: 'Gender',
        fr: 'Genre',
        de: 'Geschlecht',
        ja: '性別',
      ),
      '员工类型': (
        zhHant: '員工類型',
        en: 'Employee type',
        fr: 'Type d’employé',
        de: 'Beschäftigungsart',
        ja: '雇用形態',
      ),
      '是否特别关注': (
        zhHant: '是否特別關注',
        en: 'Specially followed',
        fr: 'Suivi spécial',
        de: 'Besonders beobachtet',
        ja: '特別フォロー',
      ),
      '是否被禁言': (
        zhHant: '是否被禁言',
        en: 'Muted',
        fr: 'Mis en sourdine',
        de: 'Stummgeschaltet',
        ja: 'ミュート中',
      ),
      '是否免打扰': (
        zhHant: '是否免打擾',
        en: 'Do not disturb',
        fr: 'Ne pas déranger',
        de: 'Nicht stören',
        ja: '通知オフ',
      ),
      '是否置顶': (
        zhHant: '是否置頂',
        en: 'Pinned',
        fr: 'Épinglé',
        de: 'Angeheftet',
        ja: 'ピン留め',
      ),
      '全员禁言白名单': (
        zhHant: '全員禁言白名單',
        en: 'Mute-all allowlist',
        fr: 'Liste autorisée en sourdine globale',
        de: 'Ausnahmen bei globaler Stummschaltung',
        ja: '全員ミュートの許可リスト',
      ),
      '禁言成员': (
        zhHant: '禁言成員',
        en: 'Muted members',
        fr: 'Membres en sourdine',
        de: 'Stummgeschaltete Mitglieder',
        ja: 'ミュート中のメンバー',
      ),
      '操作时间': (
        zhHant: '操作時間',
        en: 'Operation time',
        fr: 'Heure de l’opération',
        de: 'Vorgangszeit',
        ja: '操作時刻',
      ),
      '群身份标识': (
        zhHant: '群身份標識',
        en: 'Group role ID',
        fr: 'Identifiant du rôle de groupe',
        de: 'Gruppenrollen-ID',
        ja: 'グループロール ID',
      ),
      '群身份名称': (
        zhHant: '群身份名稱',
        en: 'Group role name',
        fr: 'Nom du rôle de groupe',
        de: 'Name der Gruppenrolle',
        ja: 'グループロール名',
      ),
      '机器人编码': (
        zhHant: '機器人編碼',
        en: 'Bot code',
        fr: 'Code du robot',
        de: 'Bot-Code',
        ja: 'ボットコード',
      ),
      '机器人名称': (
        zhHant: '機器人名稱',
        en: 'Bot name',
        fr: 'Nom du robot',
        de: 'Bot-Name',
        ja: 'ボット名',
      ),
      '机器人账号': (
        zhHant: '機器人帳號',
        en: 'Bot account',
        fr: 'Compte du robot',
        de: 'Bot-Konto',
        ja: 'ボットアカウント',
      ),
      '个人群昵称': (
        zhHant: '個人群暱稱',
        en: 'Personal group nickname',
        fr: 'Surnom personnel dans le groupe',
        de: 'Persönlicher Gruppenname',
        ja: '個人グループニックネーム',
      ),
      '群备注': (
        zhHant: '群備註',
        en: 'Group note',
        fr: 'Note du groupe',
        de: 'Gruppennotiz',
        ja: 'グループメモ',
      ),
      '上级部门标识': (
        zhHant: '上級部門標識',
        en: 'Parent department ID',
        fr: 'Identifiant du service parent',
        de: 'ID der übergeordneten Abteilung',
        ja: '上位部署 ID',
      ),
      '部门人数': (
        zhHant: '部門人數',
        en: 'Department members',
        fr: 'Effectif du service',
        de: 'Abteilungsmitglieder',
        ja: '部署の人数',
      ),
      '直属子部门': (
        zhHant: '直屬子部門',
        en: 'Direct subdepartments',
        fr: 'Sous-services directs',
        de: 'Direkte Unterabteilungen',
        ja: '直属の下位部署',
      ),
      '部门详情': (
        zhHant: '部門詳情',
        en: 'Department profile',
        fr: 'Profil du service',
        de: 'Abteilungsprofil',
        ja: '部署プロフィール',
      ),
      '未读消息数': (
        zhHant: '未讀訊息數',
        en: 'Unread messages',
        fr: 'Messages non lus',
        de: 'Ungelesene Nachrichten',
        ja: '未読メッセージ数',
      ),
      '排序值': (
        zhHant: '排序值',
        en: 'Sort order',
        fr: 'Ordre de tri',
        de: 'Sortierreihenfolge',
        ja: '並び順',
      ),
      '是否创建部门群': (
        zhHant: '是否建立部門群',
        en: 'Department group enabled',
        fr: 'Groupe de service activé',
        de: 'Abteilungsgruppe aktiviert',
        ja: '部署グループの有効化',
      ),
      '头像媒体标识': (
        zhHant: '頭像媒體標識',
        en: 'Avatar media ID',
        fr: 'Identifiant média de l’avatar',
        de: 'Avatar-Medien-ID',
        ja: 'アバターメディア ID',
      ),
      '未知': (
        zhHant: '未知',
        en: 'Unknown',
        fr: 'Inconnu',
        de: 'Unbekannt',
        ja: '不明',
      ),
      '全职': (
        zhHant: '全職',
        en: 'Full-time',
        fr: 'Temps plein',
        de: 'Vollzeit',
        ja: '正社員',
      ),
      '兼职': (
        zhHant: '兼職',
        en: 'Part-time',
        fr: 'Temps partiel',
        de: 'Teilzeit',
        ja: 'パートタイム',
      ),
      '实习': (
        zhHant: '實習',
        en: 'Intern',
        fr: 'Stagiaire',
        de: 'Praktikum',
        ja: 'インターン',
      ),
      '劳务派遣': (
        zhHant: '勞務派遣',
        en: 'Dispatched worker',
        fr: 'Travailleur détaché',
        de: 'Leiharbeit',
        ja: '派遣社員',
      ),
      '退休返聘': (
        zhHant: '退休返聘',
        en: 'Retiree rehire',
        fr: 'Retraité réembauché',
        de: 'Weiterbeschäftigter Rentner',
        ja: '再雇用',
      ),
      '劳务外包': (
        zhHant: '勞務外包',
        en: 'Outsourced worker',
        fr: 'Travailleur externalisé',
        de: 'Outsourcing-Mitarbeiter',
        ja: '業務委託',
      ),
      '待入职': (
        zhHant: '待入職',
        en: 'Pending onboarding',
        fr: 'Intégration en attente',
        de: 'Eintritt ausstehend',
        ja: '入社待ち',
      ),
      '试用': (
        zhHant: '試用',
        en: 'Probation',
        fr: 'Période d’essai',
        de: 'Probezeit',
        ja: '試用期間',
      ),
      '正式': (
        zhHant: '正式',
        en: 'Regular employee',
        fr: 'Titulaire',
        de: 'Festangestellt',
        ja: '正規社員',
      ),
      '离职': (
        zhHant: '離職',
        en: 'Left company',
        fr: 'A quitté l’entreprise',
        de: 'Ausgeschieden',
        ja: '退職',
      ),
      '待离职': (
        zhHant: '待離職',
        en: 'Leaving pending',
        fr: 'Départ en attente',
        de: 'Austritt ausstehend',
        ja: '退職待ち',
      ),
      '试岗': (
        zhHant: '試崗',
        en: 'Trial assignment',
        fr: 'Poste d’essai',
        de: 'Erprobungsphase',
        ja: '試用勤務',
      ),
      '已退休': (
        zhHant: '已退休',
        en: 'Retired',
        fr: 'Retraité',
        de: 'Ruhestand',
        ja: '退職済み',
      ),
    };

String _displayDingTalkDetailLabel(BuildContext context, String value) {
  final extended = _dingtalkExtendedDetailLabels[value];
  if (extended != null) {
    return openHandLocalizedText(
      context,
      zh: value,
      zhHant: extended.zhHant,
      en: extended.en,
      fr: extended.fr,
      de: extended.de,
      ja: extended.ja,
    );
  }
  const dynamicPrefix = '扩展字段 · ';
  if (value.startsWith(dynamicPrefix)) {
    final suffix = value.substring(dynamicPrefix.length);
    return '${openHandLocalizedText(context, zh: '扩展字段', zhHant: '擴展欄位', en: 'Extended field', fr: 'Champ étendu', de: 'Erweitertes Feld', ja: '拡張フィールド')} · $suffix';
  }
  switch (value) {
    case '设置':
      return openHandLocalizedText(
        context,
        zh: '设置',
        zhHant: '設定',
        en: 'Settings',
        fr: 'Paramètres',
        de: 'Einstellungen',
        ja: '設定',
      );
    case '通知':
      return openHandLocalizedText(
        context,
        zh: '通知',
        zhHant: '通知',
        en: 'Notifications',
        fr: 'Notifications',
        de: 'Benachrichtigungen',
        ja: '通知',
      );
    case '类型':
      return openHandLocalizedText(
        context,
        zh: '类型',
        zhHant: '類型',
        en: 'Type',
        fr: 'Type',
        de: 'Typ',
        ja: '種類',
      );
    case '标识':
      return openHandLocalizedText(
        context,
        zh: '标识',
        zhHant: '標識',
        en: 'Identifier',
        fr: 'Identifiant',
        de: 'Kennung',
        ja: '識別子',
      );
    case '成员资料':
      return openHandLocalizedText(
        context,
        zh: '成员资料',
        zhHant: '成員資料',
        en: 'Member profile',
        fr: 'Profil du membre',
        de: 'Mitgliederprofil',
        ja: 'メンバープロフィール',
      );
    case '会话概览':
      return openHandLocalizedText(
        context,
        zh: '会话概览',
        zhHant: '會話概覽',
        en: 'Conversation overview',
        fr: 'Aperçu de la conversation',
        de: 'Gesprächsübersicht',
        ja: '会話の概要',
      );
    case '联系人资料':
      return openHandLocalizedText(
        context,
        zh: '联系人资料',
        zhHant: '聯絡人資料',
        en: 'Contact profile',
        fr: 'Profil du contact',
        de: 'Kontaktprofil',
        ja: '連絡先プロフィール',
      );
    case '群成员':
      return openHandLocalizedText(
        context,
        zh: '群成员',
        zhHant: '群成員',
        en: 'Group members',
        fr: 'Membres du groupe',
        de: 'Gruppenmitglieder',
        ja: 'グループメンバー',
      );
    case '人':
      return openHandLocalizedText(
        context,
        zh: '人',
        zhHant: '人',
        en: 'people',
        fr: 'personnes',
        de: 'Personen',
        ja: '人',
      );
    case '项':
      return openHandLocalizedText(
        context,
        zh: '项',
        zhHant: '項',
        en: 'items',
        fr: 'éléments',
        de: 'Einträge',
        ja: '項目',
      );
    case '企业标识':
      return openHandLocalizedText(
        context,
        zh: '企业标识',
        zhHant: '企業標識',
        en: 'Organization ID',
        fr: 'Identifiant de l’organisation',
        de: 'Organisations-ID',
        ja: '組織 ID',
      );
    case '企业名称':
      return openHandLocalizedText(
        context,
        zh: '企业名称',
        zhHant: '企業名稱',
        en: 'Organization name',
        fr: 'Nom de l’organisation',
        de: 'Organisationsname',
        ja: '組織名',
      );
    case '创建时间':
      return openHandLocalizedText(
        context,
        zh: '创建时间',
        zhHant: '建立時間',
        en: 'Created',
        fr: 'Créé le',
        de: 'Erstellt',
        ja: '作成日時',
      );
    case '钉盘空间标识':
      return openHandLocalizedText(
        context,
        zh: '钉盘空间标识',
        zhHant: '釘盤空間標識',
        en: 'DingDrive space ID',
        fr: 'Identifiant d’espace DingDrive',
        de: 'DingDrive-Space-ID',
        ja: 'DingDrive スペース ID',
      );
    case '成员数量':
      return openHandLocalizedText(
        context,
        zh: '成员数量',
        zhHant: '成員數量',
        en: 'Member count',
        fr: 'Nombre de membres',
        de: 'Mitgliederzahl',
        ja: 'メンバー数',
      );
    case '会话标识':
      return openHandLocalizedText(
        context,
        zh: '会话标识',
        zhHant: '會話標識',
        en: 'Conversation ID',
        fr: 'Identifiant de conversation',
        de: 'Gesprächs-ID',
        ja: '会話 ID',
      );
    case '群主':
      return openHandLocalizedText(
        context,
        zh: '群主',
        zhHant: '群主',
        en: 'Owner',
        fr: 'Propriétaire',
        de: 'Eigentümer',
        ja: 'オーナー',
      );
    case '群聊名称':
      return openHandLocalizedText(
        context,
        zh: '群聊名称',
        zhHant: '群聊名稱',
        en: 'Group name',
        fr: 'Nom du groupe',
        de: 'Gruppenname',
        ja: 'グループ名',
      );
    case '聊天类型':
      return openHandLocalizedText(
        context,
        zh: '聊天类型',
        zhHant: '聊天類型',
        en: 'Chat type',
        fr: 'Type de conversation',
        de: 'Gesprächstyp',
        ja: 'チャットタイプ',
      );
    case '姓名':
      return openHandLocalizedText(
        context,
        zh: '姓名',
        zhHant: '姓名',
        en: 'Name',
        fr: 'Nom',
        de: 'Name',
        ja: '名前',
      );
    case '群内昵称':
      return openHandLocalizedText(
        context,
        zh: '群内昵称',
        zhHant: '群內暱稱',
        en: 'Group nickname',
        fr: 'Surnom dans le groupe',
        de: 'Gruppenname',
        ja: 'グループ内のニックネーム',
      );
    case '群内角色':
      return openHandLocalizedText(
        context,
        zh: '群内角色',
        zhHant: '群內角色',
        en: 'Group role',
        fr: 'Rôle dans le groupe',
        de: 'Gruppenrolle',
        ja: 'グループ内の役割',
      );
    case '角色类型':
      return openHandLocalizedText(
        context,
        zh: '角色类型',
        zhHant: '角色類型',
        en: 'Role type',
        fr: 'Type de rôle',
        de: 'Rollentyp',
        ja: '役割タイプ',
      );
    case '钉钉账号':
      return openHandLocalizedText(
        context,
        zh: '钉钉账号',
        zhHant: '釘釘帳號',
        en: 'DingTalk account',
        fr: 'Compte DingTalk',
        de: 'DingTalk-Konto',
        ja: 'DingTalk アカウント',
      );
    case '钉钉用户标识':
      return openHandLocalizedText(
        context,
        zh: '钉钉用户标识',
        zhHant: '釘釘使用者標識',
        en: 'DingTalk user ID',
        fr: 'Identifiant utilisateur DingTalk',
        de: 'DingTalk-Benutzer-ID',
        ja: 'DingTalk ユーザー ID',
      );
    case '组织':
      return openHandLocalizedText(
        context,
        zh: '组织',
        zhHant: '組織',
        en: 'Organization',
        fr: 'Organisation',
        de: 'Organisation',
        ja: '組織',
      );
    case '部门':
      return openHandLocalizedText(
        context,
        zh: '部门',
        zhHant: '部門',
        en: 'Department',
        fr: 'Département',
        de: 'Abteilung',
        ja: '部署',
      );
    case '职位':
      return openHandLocalizedText(
        context,
        zh: '职位',
        zhHant: '職位',
        en: 'Position',
        fr: 'Poste',
        de: 'Position',
        ja: '役職',
      );
    case '手机号':
      return openHandLocalizedText(
        context,
        zh: '手机号',
        zhHant: '手機號碼',
        en: 'Phone',
        fr: 'Téléphone',
        de: 'Telefon',
        ja: '電話番号',
      );
    case '邮箱':
      return openHandLocalizedText(
        context,
        zh: '邮箱',
        zhHant: '電子郵件',
        en: 'Email',
        fr: 'E-mail',
        de: 'E-Mail',
        ja: 'メール',
      );
    case '备注':
      return openHandLocalizedText(
        context,
        zh: '备注',
        zhHant: '備註',
        en: 'Note',
        fr: 'Note',
        de: 'Notiz',
        ja: 'メモ',
      );
    case '状态':
      return openHandLocalizedText(
        context,
        zh: '状态',
        zhHant: '狀態',
        en: 'Status',
        fr: 'Statut',
        de: 'Status',
        ja: 'ステータス',
      );
    case '其他资料':
      return openHandLocalizedText(
        context,
        zh: '其他资料',
        zhHant: '其他資料',
        en: 'Additional details',
        fr: 'Informations complémentaires',
        de: 'Zusätzliche Angaben',
        ja: 'その他の詳細',
      );
    case '值':
      return openHandLocalizedText(
        context,
        zh: '值',
        zhHant: '值',
        en: 'Value',
        fr: 'Valeur',
        de: 'Wert',
        ja: '値',
      );
    default:
      return value;
  }
}

String _dingtalkDetailCountLabel(
  BuildContext context,
  int count, {
  String unit = '项',
}) {
  return '$count ${_displayDingTalkDetailLabel(context, unit)}';
}

String _dingtalkDetailIndexLabel(BuildContext context, int index) {
  final item = _displayDingTalkDetailLabel(context, '项');
  final number = index + 1;
  return openHandIsChineseLocale(context) ? '第 $number $item' : '$item $number';
}

String _dingtalkRoleLabel(BuildContext context, String value) {
  switch (value) {
    case '群主':
      return openHandLocalizedText(
        context,
        zh: '群主',
        zhHant: '群主',
        en: 'Owner',
        fr: 'Propriétaire',
        de: 'Eigentümer',
        ja: 'オーナー',
      );
    case '管理员':
      return openHandLocalizedText(
        context,
        zh: '管理员',
        zhHant: '管理員',
        en: 'Administrator',
        fr: 'Administrateur',
        de: 'Administrator',
        ja: '管理者',
      );
    case '成员':
      return openHandLocalizedText(
        context,
        zh: '成员',
        zhHant: '成員',
        en: 'Member',
        fr: 'Membre',
        de: 'Mitglied',
        ja: 'メンバー',
      );
    default:
      return value;
  }
}

String _formatDingTalkDetailValue(
  BuildContext context,
  Object? value, {
  String? label,
}) {
  if (value == null) {
    return openHandLocalizedText(
      context,
      zh: '未返回',
      zhHant: '未返回',
      en: 'Not returned',
      fr: 'Non renseigné',
      de: 'Nicht zurückgegeben',
      ja: '未返却',
    );
  }
  if (value is bool) {
    return value
        ? openHandLocalizedText(
            context,
            zh: '是',
            zhHant: '是',
            en: 'Yes',
            fr: 'Oui',
            de: 'Ja',
            ja: 'はい',
          )
        : openHandLocalizedText(
            context,
            zh: '否',
            zhHant: '否',
            en: 'No',
            fr: 'Non',
            de: 'Nein',
            ja: 'いいえ',
          );
  }
  if (value is num && label != null) {
    if (label == '员工类型' || label == 'Employee type') {
      const values = <int, String>{
        0: '未知',
        1: '全职',
        2: '兼职',
        3: '实习',
        4: '劳务派遣',
        5: '退休返聘',
        6: '劳务外包',
      };
      final translated = values[value.toInt()];
      if (translated != null) {
        return _displayDingTalkDetailLabel(context, translated);
      }
    }
    if (label == '员工状态' || label == 'Employment status') {
      const values = <int, String>{
        -1: '未知',
        1: '待入职',
        2: '试用',
        3: '正式',
        4: '离职',
        5: '待离职',
        6: '试岗',
        7: '已退休',
      };
      final translated = values[value.toInt()];
      if (translated != null) {
        return _displayDingTalkDetailLabel(context, translated);
      }
    }
  }
  final text = '$value'.trim();
  return text.isEmpty
      ? openHandLocalizedText(
          context,
          zh: '空',
          zhHant: '空',
          en: 'Empty',
          fr: 'Vide',
          de: 'Leer',
          ja: '空',
        )
      : text;
}

const Duration _kDingTalkTargetSearchDebounce = Duration(milliseconds: 260);

class _DingTalkTargetSearchCoordinator {
  _DingTalkTargetSearchCoordinator({required this.search});

  final Future<List<DingTalkConversationTarget>> Function(String keyword)
  search;
  final OpenHandDebouncer _debouncer = OpenHandDebouncer(
    delay: _kDingTalkTargetSearchDebounce,
    onError: (error, stack) =>
        silentLog('dingtalk_gateway', '执行会话搜索防抖任务', error, stack),
  );

  List<DingTalkConversationTarget> results =
      const <DingTalkConversationTarget>[];
  bool searching = false;
  int _generation = 0;
  bool _disposed = false;

  void schedule(String value, VoidCallback notify) {
    if (_disposed) return;
    final keyword = value.trim();
    if (keyword.isEmpty) {
      clear();
      notify();
      return;
    }
    final generation = ++_generation;
    _debouncer.schedule(() => _run(keyword, generation, notify));
  }

  void clear() {
    _debouncer.cancel();
    _generation++;
    results = const <DingTalkConversationTarget>[];
    searching = false;
  }

  Future<void> _run(String keyword, int generation, VoidCallback notify) async {
    if (_disposed || generation != _generation) return;
    searching = true;
    notify();
    try {
      final nextResults = await search(keyword);
      if (_disposed || generation != _generation) return;
      results = nextResults;
    } catch (error, stack) {
      silentLog('dingtalk_gateway', '搜索钉钉会话目标', error, stack);
      if (_disposed || generation != _generation) return;
      results = const <DingTalkConversationTarget>[];
    } finally {
      if (!_disposed && generation == _generation) {
        searching = false;
        notify();
      }
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _debouncer.dispose();
  }
}

class _DingTalkAddConversationDialog extends StatefulWidget {
  const _DingTalkAddConversationDialog({required this.controller});

  final DingTalkMessageGatewayController controller;

  @override
  State<_DingTalkAddConversationDialog> createState() =>
      _DingTalkAddConversationDialogState();
}

class _DingTalkAddConversationDialogState
    extends State<_DingTalkAddConversationDialog> {
  final TextEditingController _queryController = TextEditingController();
  late final _DingTalkTargetSearchCoordinator _targetSearch =
      _DingTalkTargetSearchCoordinator(
        search: (keyword) =>
            widget.controller.searchTargets(type: _type, query: keyword),
      );
  DingTalkConversationType _type = DingTalkConversationType.direct;

  @override
  void dispose() {
    _targetSearch.dispose();
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _type == DingTalkConversationType.group
                    ? Icons.groups_rounded
                    : Icons.person_add_alt_1_rounded,
                color: theme.colorScheme.primary,
              ),
              kOpenHandHGap10,
              Text('新建钉钉会话', style: theme.textTheme.titleLarge),
            ],
          ),
          kOpenHandGap20,
          SegmentedButton<DingTalkConversationType>(
            segments: const [
              ButtonSegment(
                value: DingTalkConversationType.direct,
                icon: Icon(Icons.person_rounded),
                label: Text('私聊'),
              ),
              ButtonSegment(
                value: DingTalkConversationType.group,
                icon: Icon(Icons.groups_rounded),
                label: Text('群聊'),
              ),
            ],
            selected: <DingTalkConversationType>{_type},
            onSelectionChanged: (value) {
              final next = value.firstOrNull;
              if (next == null || next == _type) return;
              _targetSearch.clear();
              setState(() {
                _type = next;
              });
              _scheduleSearch(_queryController.text);
            },
          ),
          kOpenHandGap16,
          TextField(
            controller: _queryController,
            autofocus: true,
            onChanged: _scheduleSearch,
            decoration: InputDecoration(
              labelText: _type == DingTalkConversationType.group
                  ? '搜索群聊名称'
                  : '搜索私聊用户姓名',
              hintText: '输入关键词后自动搜索',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _targetSearch.searching
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
          ),
          kOpenHandGap8,
          AnimatedSwitcher(
            duration: kOpenHandMotion180,
            child: _targetSearch.results.isEmpty
                ? Padding(
                    key: const ValueKey<String>('dingtalk-search-empty'),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Center(
                      child: Text(
                        _queryController.text.trim().isEmpty
                            ? '输入名称开始搜索'
                            : '暂无匹配结果',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                : ConstrainedBox(
                    key: const ValueKey<String>('dingtalk-search-results'),
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: Material(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: kOpenHandBorderRadius16,
                      shadowColor: Colors.transparent,
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(8),
                        itemCount: _targetSearch.results.length,
                        separatorBuilder: (_, index) => kOpenHandGap2,
                        itemBuilder: (context, index) {
                          final target = _targetSearch.results[index];
                          return ListTile(
                            dense: true,
                            shape: const RoundedRectangleBorder(
                              borderRadius: kOpenHandBorderRadius12,
                            ),
                            leading: Icon(
                              target.type == DingTalkConversationType.group
                                  ? Icons.groups_rounded
                                  : Icons.person_rounded,
                            ),
                            title: Text(target.title),
                            subtitle: target.subtitle.trim().isEmpty
                                ? null
                                : Text(
                                    target.subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            onTap: () => Navigator.of(context).pop(target),
                          );
                        },
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _scheduleSearch(String value) {
    _targetSearch.schedule(value, () {
      if (mounted) setState(() {});
    });
  }
}

class _DingTalkTargetAllowlistField extends StatelessWidget {
  const _DingTalkTargetAllowlistField({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.targets,
    required this.emptyLabel,
    required this.addLabel,
    required this.onAdd,
    required this.onRemove,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<DingTalkConversationTarget> targets;
  final String emptyLabel;
  final String addLabel;
  final VoidCallback onAdd;
  final ValueChanged<DingTalkConversationTarget> onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(kOpenHandRadius17),
      shadowColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: kOpenHandBorderRadius12,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(9),
                    child: Icon(
                      icon,
                      size: 20,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                kOpenHandHGap11,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleSmall),
                      kOpenHandGap3,
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(addLabel),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    shadowColor: Colors.transparent,
                  ),
                ),
              ],
            ),
            kOpenHandGap11,
            if (targets.isEmpty)
              Text(
                emptyLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  ...targets
                      .take(6)
                      .map(
                        (target) => ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 220),
                          child: InputChip(
                            label: Text(
                              target.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            avatar: Icon(
                              target.type == DingTalkConversationType.group
                                  ? Icons.groups_rounded
                                  : Icons.person_rounded,
                              size: 17,
                            ),
                            onDeleted: () => onRemove(target),
                            deleteIcon: const Icon(
                              Icons.close_rounded,
                              size: 16,
                            ),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                  if (targets.length > 6)
                    InputChip(
                      label: Text('+${targets.length - 6}'),
                      onPressed: onAdd,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _DingTalkAllowlistPickerDialog extends StatefulWidget {
  const _DingTalkAllowlistPickerDialog({
    required this.title,
    required this.icon,
    required this.type,
    required this.selected,
    required this.controller,
  });

  final String title;
  final IconData icon;
  final DingTalkConversationType type;
  final List<DingTalkConversationTarget> selected;
  final DingTalkMessageGatewayController controller;

  @override
  State<_DingTalkAllowlistPickerDialog> createState() =>
      _DingTalkAllowlistPickerDialogState();
}

class _DingTalkAllowlistPickerDialogState
    extends State<_DingTalkAllowlistPickerDialog> {
  late final TextEditingController _queryController = TextEditingController();
  late final Map<String, DingTalkConversationTarget> _selected = {
    for (final target in widget.selected) target.id: target,
  };
  late final _DingTalkTargetSearchCoordinator _targetSearch =
      _DingTalkTargetSearchCoordinator(
        search: (keyword) =>
            widget.controller.searchTargets(type: widget.type, query: keyword),
      );

  @override
  void dispose() {
    _targetSearch.dispose();
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: double.infinity,
      height: 560,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(widget.icon, color: theme.colorScheme.primary),
                kOpenHandHGap10,
                Expanded(
                  child: Text(widget.title, style: theme.textTheme.titleLarge),
                ),
                Text(
                  _dingtalkAllowlistText(
                    context,
                    'selected',
                    count: _selected.length,
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            kOpenHandGap16,
            TextField(
              controller: _queryController,
              autofocus: true,
              onChanged: _scheduleSearch,
              decoration: InputDecoration(
                labelText: _dingtalkAllowlistText(
                  context,
                  'search_label',
                  type: widget.type,
                ),
                hintText: _dingtalkAllowlistText(
                  context,
                  'search_hint',
                  type: widget.type,
                ),
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _targetSearch.searching
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
            ),
            kOpenHandGap10,
            if (_selected.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 82),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _selected.values
                        .map(
                          (target) => InputChip(
                            label: Text(target.title),
                            onDeleted: () =>
                                setState(() => _selected.remove(target.id)),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
              ),
            kOpenHandGap8,
            Expanded(
              child: _targetSearch.results.isEmpty
                  ? Center(
                      child: Text(
                        _queryController.text.trim().isEmpty
                            ? _dingtalkAllowlistText(
                                context,
                                'search_start',
                                type: widget.type,
                              )
                            : _dingtalkAllowlistText(context, 'no_results'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : Material(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: kOpenHandBorderRadius16,
                      shadowColor: Colors.transparent,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(8),
                        itemCount: _targetSearch.results.length,
                        separatorBuilder: (_, index) => kOpenHandGap2,
                        itemBuilder: (context, index) {
                          final target = _targetSearch.results[index];
                          final selected = _selected.containsKey(target.id);
                          return ListTile(
                            dense: true,
                            selected: selected,
                            selectedTileColor:
                                theme.colorScheme.primaryContainer,
                            shape: const RoundedRectangleBorder(
                              borderRadius: kOpenHandBorderRadius12,
                            ),
                            leading: Icon(widget.icon),
                            title: Text(target.title),
                            subtitle: target.subtitle.trim().isEmpty
                                ? null
                                : Text(
                                    target.subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            trailing: Icon(
                              selected
                                  ? Icons.check_circle_rounded
                                  : Icons.add_circle_outline_rounded,
                              color: selected
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                            onTap: () => setState(() {
                              if (selected) {
                                _selected.remove(target.id);
                              } else {
                                _selected[target.id] = target;
                              }
                            }),
                          );
                        },
                      ),
                    ),
            ),
            kOpenHandGap12,
            OpenHandDialogSaveActions(
              busy: false,
              cancelLabel: _dingtalkAllowlistText(context, 'cancel'),
              confirmLabel: _dingtalkAllowlistText(context, 'apply'),
              onConfirm: () => Navigator.of(
                context,
              ).pop(_selected.values.toList(growable: false)),
            ),
          ],
        ),
      ),
    );
  }

  void _scheduleSearch(String value) {
    _targetSearch.schedule(value, () {
      if (mounted) setState(() {});
    });
  }
}

class _DingTalkSettingsDialog extends StatefulWidget {
  const _DingTalkSettingsDialog({required this.controller});
  final DingTalkMessageGatewayController controller;

  @override
  State<_DingTalkSettingsDialog> createState() =>
      _DingTalkSettingsDialogState();
}

String _dingtalkSafeMcpEndpoint(McpServer item) {
  if (item.type == McpServerType.stdio) {
    return <String>[
      item.command.trim(),
      ...item.args,
    ].where((value) => value.trim().isNotEmpty).join(' ');
  }
  final rawUrl = item.url.trim();
  final uri = Uri.tryParse(rawUrl);
  if (uri == null || uri.host.isEmpty) {
    return rawUrl;
  }
  final authority = uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  final path = uri.path.isEmpty ? '/' : uri.path;
  return '${uri.scheme}://$authority$path';
}

class _DingTalkSettingsDialogState extends State<_DingTalkSettingsDialog> {
  late final TextEditingController _intervalController = TextEditingController(
    text: '${widget.controller.settings.pollIntervalSeconds}',
  );
  late final TextEditingController _workerCountController =
      TextEditingController(
        text: '${widget.controller.settings.responseWorkerCount}',
      );
  late final TextEditingController _workingDirectoryController =
      TextEditingController(
        text: widget.controller.settings.workingDirectory.isEmpty
            ? OpenHandPaths.applicationDirectoryPath()
            : widget.controller.settings.workingDirectory,
      );
  late DingTalkOverloadStrategy _overloadStrategy =
      widget.controller.settings.overloadStrategy;
  late DingTalkReminderMode _reminderMode =
      widget.controller.settings.reminderMode;
  late DingTalkResponseMode _responseMode =
      widget.controller.settings.responseMode;
  late final Set<DingTalkResponseEchoType> _responseEchoTypes = widget
      .controller
      .settings
      .responseEchoTypes
      .toSet();
  late String _modelKey = widget.controller.settings.responseModelKey;
  late bool _fullAccessPermission =
      widget.controller.settings.fullAccessPermission;
  late String _templateId = widget.controller.settings.templateId;
  late Set<String> _mcpServers = widget
      .controller
      .settings
      .allowedMcpServerNames
      .toSet();
  late Set<String> _skills = widget.controller.settings.allowedSkillNames
      .toSet();
  late Set<String> _memories = widget.controller.settings.allowedMemoryIds
      .toSet();
  late Set<String> _instructions = widget
      .controller
      .settings
      .allowedInstructionIds
      .toSet();
  late Set<String> _knowledgeSources = widget
      .controller
      .settings
      .allowedKnowledgeBaseSourceIds
      .toSet();
  late Set<String> _workflows = widget.controller.settings.allowedWorkflowIds
      .toSet();
  late Set<String> _dwsCommands = widget
      .controller
      .settings
      .allowedDingTalkDwsCommandIds
      .toSet();
  late Set<AiDingTalkMultimodalCapability> _multimodalCapabilities = widget
      .controller
      .settings
      .enabledMultimodalCapabilities
      .toSet();
  late String _imageGenerationModelKey =
      widget.controller.settings.imageGenerationModelKey;
  late String _videoGenerationModelKey =
      widget.controller.settings.videoGenerationModelKey;
  late String _audioGenerationModelKey =
      widget.controller.settings.audioGenerationModelKey;
  late List<DingTalkConversationTarget> _allowedGroups =
      List<DingTalkConversationTarget>.from(
        widget.controller.settings.allowedGroupTargets,
      );
  late List<DingTalkConversationTarget> _allowedContacts =
      List<DingTalkConversationTarget>.from(
        widget.controller.settings.allowedContactTargets,
      );
  final Set<DingTalkGatewayResourceCatalog> _refreshingResourceCatalogs =
      <DingTalkGatewayResourceCatalog>{};
  List<AiDingTalkDwsCommand> _dwsCatalog = const <AiDingTalkDwsCommand>[];
  bool _dwsCatalogLoading = false;
  String? _dwsCatalogError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // 等首帧挂载完成后再触发目录加载，避免服务层通知在 build 阶段标记
    // 监听组件，导致 setState() or markNeedsBuild() called during build。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadDwsCatalog());
    });
  }

  @override
  void dispose() {
    _intervalController.dispose();
    _workerCountController.dispose();
    _workingDirectoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final responseModel = _resolvedResponseModel();
    final allReasoningOptions =
        responseModel?.resolvedReasoningEffortOptions ??
        const <AiReasoningEffortOption>[];
    final reasoningOptions = allReasoningOptions
        .where((option) => option.isSelectable)
        .toList(growable: false);
    final reasoningAdjustable =
        responseModel?.resolvedReasoningEffortControlEnabled == true &&
        reasoningOptions.isNotEmpty;
    final profile = responseModel?.profileFor(responseModel.modelId);
    final reasoningEffort =
        responseModel?.resolvedReasoningEffort?.trim() ??
        profile?.reasoningEffort?.trim() ??
        '';
    final normalizedEffort = reasoningEffort.toLowerCase();
    final reasoningClosed =
        responseModel?.resolvedThinkingEnabled != true ||
        AiReasoningEffortOption.isOffValue(normalizedEffort);
    final reasoningOption = allReasoningOptions
        .where((option) => option.value.toLowerCase() == normalizedEffort)
        .firstOrNull;
    final reasoningEffortLabel = reasoningClosed
        ? '关闭'
        : reasoningOption?.labelForLocaleName(
                Localizations.localeOf(context).toLanguageTag(),
              ) ??
              (reasoningEffort.isEmpty ? '默认' : reasoningEffort);
    final reasoningTooltip = reasoningAdjustable
        ? '调整响应模型的推理强度，当前为 $reasoningEffortLabel'
        : responseModel == null
        ? '暂无可用响应模型，推理强度保持关闭'
        : responseModel.resolvedThinkingEnabled
        ? '当前模型的推理强度固定为 $reasoningEffortLabel，无法调整'
        : '当前模型不支持推理强度控制，保持关闭';
    final theme = Theme.of(context);
    final responseModeAll = _responseMode == DingTalkResponseMode.all;
    return SizedBox(
      width: double.infinity,
      height: 720,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune_rounded, color: theme.colorScheme.primary),
                kOpenHandHGap10,
                Text('钉钉网关设置', style: theme.textTheme.titleLarge),
              ],
            ),
            kOpenHandGap16,
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(right: 4, bottom: 14),
                children: [
                  TextField(
                    controller: _intervalController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '兜底轮询间隔（秒）',
                      helperText: '实时事件不可用时使用，最小 3 秒，保存后立即生效',
                      prefixIcon: Icon(Icons.schedule_rounded),
                    ),
                  ),
                  kOpenHandGap14,
                  TextField(
                    controller: _workerCountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '工作线程数',
                      helperText: '同时处理的会话数，最小 1，保存后立即生效',
                      prefixIcon: Icon(Icons.account_tree_rounded),
                    ),
                  ),
                  kOpenHandGap14,
                  AnimatedDropdownButtonFormField<DingTalkOverloadStrategy>(
                    initialValue: _overloadStrategy,
                    decoration: const InputDecoration(
                      labelText: '消息过载处理',
                      helperText: '工作线程忙碌时对新到达的 AI 响应消息执行此策略',
                      prefixIcon: Icon(Icons.traffic_rounded),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: DingTalkOverloadStrategy.queue,
                        child: Text('加入等待队列'),
                      ),
                      DropdownMenuItem(
                        value: DingTalkOverloadStrategy.reject,
                        child: Text('拒绝响应'),
                      ),
                      DropdownMenuItem(
                        value: DingTalkOverloadStrategy.drop,
                        child: Text('静默丢弃'),
                      ),
                    ],
                    onChanged: (value) => setState(
                      () => _overloadStrategy =
                          value ?? DingTalkOverloadStrategy.queue,
                    ),
                  ),
                  kOpenHandGap14,
                  AnimatedDropdownButtonFormField<DingTalkReminderMode>(
                    initialValue: _reminderMode,
                    decoration: const InputDecoration(
                      labelText: '提醒方式',
                      prefixIcon: Icon(Icons.notifications_active_rounded),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: DingTalkReminderMode.none,
                        child: Text('不提醒'),
                      ),
                      DropdownMenuItem(
                        value: DingTalkReminderMode.inApp,
                        child: Text('应用内提醒'),
                      ),
                      DropdownMenuItem(
                        value: DingTalkReminderMode.sound,
                        child: Text('应用内提醒并播放声音'),
                      ),
                    ],
                    onChanged: (value) => setState(
                      () => _reminderMode = value ?? DingTalkReminderMode.inApp,
                    ),
                  ),
                  kOpenHandGap14,
                  _DingTalkSettingsCard(
                    icon: Icons.reply_all_rounded,
                    title: '响应消息类型',
                    subtitle:
                        '选择同步回显到钉钉的 AI 消息；正式响应与过程消息随生成进度流式更新，'
                        '工具调用仅在执行终态回显，至少保留一项。',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: DingTalkResponseEchoType.values
                          .map(
                            (type) => FilterChip(
                              avatar: Icon(
                                _responseEchoTypeIcon(type),
                                size: 18,
                              ),
                              label: Text(_responseEchoTypeLabel(type)),
                              selected: _responseEchoTypes.contains(type),
                              // 选中态不显示 RawChip 默认的头像压暗层，避免鼠标移动
                              // 触发重绘时图标短暂出现灰色背景。
                              showCheckmark: false,
                              color: WidgetStateProperty.resolveWith<Color?>(
                                (states) =>
                                    states.contains(WidgetState.selected)
                                    ? theme.colorScheme.primaryContainer
                                    : theme.colorScheme.surfaceContainerHigh,
                              ),
                              onSelected: (selected) {
                                if (!selected &&
                                    _responseEchoTypes.length == 1) {
                                  showOpenHandInfoSnack(
                                    context,
                                    '响应消息类型至少保留一项。',
                                  );
                                  return;
                                }
                                setState(() {
                                  if (selected) {
                                    _responseEchoTypes.add(type);
                                  } else {
                                    _responseEchoTypes.remove(type);
                                  }
                                });
                              },
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ),
                  kOpenHandGap14,
                  _DingTalkSettingsCard(
                    icon: Icons.folder_open_rounded,
                    title: '工作目录',
                    subtitle: 'AI 助手只能读写此目录及其子目录',
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _workingDirectoryController,
                            decoration: const InputDecoration(
                              hintText: '输入绝对路径或 ~/workspace',
                              isDense: true,
                            ),
                          ),
                        ),
                        kOpenHandHGap8,
                        IconButton.filledTonal(
                          tooltip: '选择目录',
                          onPressed: _pickWorkingDirectory,
                          icon: const Icon(Icons.drive_file_move_rounded),
                        ),
                      ],
                    ),
                  ),
                  kOpenHandGap12,
                  _DingTalkSettingsCard(
                    icon: Icons.admin_panel_settings_rounded,
                    title: '审批模式',
                    subtitle: _fullAccessPermission
                        ? '完全访问：执行操作无需审批确认'
                        : '默认权限：写操作会被安全拦截并提示切换到应用内会话审批',
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment<bool>(
                          value: false,
                          icon: Icon(Icons.verified_user_rounded),
                          label: Text('默认权限'),
                        ),
                        ButtonSegment<bool>(
                          value: true,
                          icon: Icon(Icons.lock_open_rounded),
                          label: Text('完全访问'),
                        ),
                      ],
                      selected: <bool>{_fullAccessPermission},
                      onSelectionChanged: (value) =>
                          setState(() => _fullAccessPermission = value.first),
                    ),
                  ),
                  if (_fullAccessPermission) ...[
                    kOpenHandGap8,
                    const _DingTalkInfoBanner(
                      icon: Icons.warning_amber_rounded,
                      text: '完全访问仅关闭审批弹窗，工作目录边界仍然有效。',
                    ),
                  ],
                  kOpenHandGap12,
                  _DingTalkSettingsCard(
                    icon: Icons.mark_chat_read_rounded,
                    title: '响应模式',
                    subtitle: responseModeAll
                        ? '全部响应：不再过滤白名单，响应所有拉取到的群聊 @ 消息和联系人单聊。'
                        : '仅响应白名单：只响应已允许群聊的 @ 消息和已允许联系人的单聊。',
                    child: Row(
                      children: [
                        Icon(
                          responseModeAll
                              ? Icons.public_rounded
                              : Icons.list_alt_rounded,
                          color: responseModeAll
                              ? theme.colorScheme.onPrimaryContainer
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        kOpenHandHGap11,
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '当前响应范围',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              kOpenHandGap2,
                              AnimatedSwitcher(
                                duration: openHandMotionDuration(
                                  context,
                                  kOpenHandMotion180,
                                ),
                                child: Text(
                                  responseModeAll ? '全部响应' : '仅响应白名单',
                                  key: ValueKey<DingTalkResponseMode>(
                                    _responseMode,
                                  ),
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: responseModeAll
                                        ? theme.colorScheme.onPrimaryContainer
                                        : theme.colorScheme.onSurface,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: responseModeAll,
                          onChanged: (enabled) => setState(() {
                            _responseMode = enabled
                                ? DingTalkResponseMode.all
                                : DingTalkResponseMode.allowlist;
                            if (enabled) {
                              _allowedGroups = <DingTalkConversationTarget>[];
                              _allowedContacts = <DingTalkConversationTarget>[];
                            }
                          }),
                          thumbIcon: WidgetStateProperty.resolveWith<Icon?>((
                            states,
                          ) {
                            if (states.contains(WidgetState.selected)) {
                              return const Icon(Icons.check_rounded, size: 16);
                            }
                            return const Icon(Icons.close_rounded, size: 16);
                          }),
                          overlayColor: const WidgetStatePropertyAll(
                            Colors.transparent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  kOpenHandGap12,
                  AnimatedSize(
                    duration: openHandMotionDuration(
                      context,
                      kOpenHandMotion220,
                    ),
                    curve: kOpenHandSwitchInCurve,
                    child: _responseMode == DingTalkResponseMode.allowlist
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _DingTalkTargetAllowlistField(
                                icon: Icons.groups_rounded,
                                title: _dingtalkAllowlistText(
                                  context,
                                  'group_title',
                                ),
                                subtitle: _dingtalkAllowlistText(
                                  context,
                                  'group_subtitle',
                                ),
                                targets: _allowedGroups,
                                emptyLabel: _dingtalkAllowlistText(
                                  context,
                                  'group_empty',
                                ),
                                addLabel: _dingtalkAllowlistText(
                                  context,
                                  'add',
                                  type: DingTalkConversationType.group,
                                ),
                                onAdd: () => _selectAllowedTargets(
                                  type: DingTalkConversationType.group,
                                  title: _dingtalkAllowlistText(
                                    context,
                                    'picker_title',
                                    type: DingTalkConversationType.group,
                                  ),
                                  icon: Icons.groups_rounded,
                                  selected: _allowedGroups,
                                ),
                                onRemove: (target) => setState(() {
                                  _allowedGroups = _allowedGroups
                                      .where((item) => item.id != target.id)
                                      .toList(growable: true);
                                }),
                              ),
                              kOpenHandGap12,
                              _DingTalkTargetAllowlistField(
                                icon: Icons.person_rounded,
                                title: _dingtalkAllowlistText(
                                  context,
                                  'contact_title',
                                ),
                                subtitle: _dingtalkAllowlistText(
                                  context,
                                  'contact_subtitle',
                                ),
                                targets: _allowedContacts,
                                emptyLabel: _dingtalkAllowlistText(
                                  context,
                                  'contact_empty',
                                ),
                                addLabel: _dingtalkAllowlistText(
                                  context,
                                  'add',
                                  type: DingTalkConversationType.direct,
                                ),
                                onAdd: () => _selectAllowedTargets(
                                  type: DingTalkConversationType.direct,
                                  title: _dingtalkAllowlistText(
                                    context,
                                    'picker_title',
                                    type: DingTalkConversationType.direct,
                                  ),
                                  icon: Icons.person_rounded,
                                  selected: _allowedContacts,
                                ),
                                onRemove: (target) => setState(() {
                                  _allowedContacts = _allowedContacts
                                      .where((item) => item.id != target.id)
                                      .toList(growable: true);
                                }),
                              ),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),
                  kOpenHandGap12,
                  _DingTalkSettingsCard(
                    icon: Icons.auto_awesome_rounded,
                    title: 'AI 助手提示词模板',
                    subtitle: '选择钉钉消息会话使用的线程模板',
                    child: AnimatedDropdownButtonFormField<String>(
                      initialValue:
                          _availableTemplateIds().contains(_templateId)
                          ? _templateId
                          : _availableTemplateIds().firstOrNull,
                      isExpanded: true,
                      decoration: const InputDecoration(isDense: true),
                      items: widget.controller.templates
                          .map(
                            (item) => DropdownMenuItem<String>(
                              value: item.id,
                              child: Text(
                                item.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) =>
                          setState(() => _templateId = value ?? 'default'),
                    ),
                  ),
                  kOpenHandGap12,
                  _DingTalkResourceField(
                    icon: Icons.hub_rounded,
                    title: '可用的 MCP',
                    selectedCount: _mcpServers.length,
                    totalCount: widget.controller.mcpServers.length,
                    refreshing: _isRefreshingResourceCatalog(
                      DingTalkGatewayResourceCatalog.mcp,
                    ),
                    onRefresh: () => _refreshResourceCatalog(
                      DingTalkGatewayResourceCatalog.mcp,
                    ),
                    onTap: () => _selectResources(
                      title: '选择 MCP Server',
                      icon: Icons.hub_rounded,
                      options: widget.controller.mcpServers
                          .map(
                            (item) => _DingTalkResourceOption(
                              id: item.name,
                              title: item.name,
                              subtitle: item.summary,
                              icon: Icons.hub_rounded,
                              detailDescription:
                                  '通过 ${item.type.transportValue} 连接的 MCP 服务，可按当前钉钉会话配置注入模型工具上下文。',
                              detailFields: <String, String>{
                                '资源类型': 'MCP Server',
                                '传输方式': item.type.transportValue,
                                '启用状态': item.enabled ? '已启用' : '未启用',
                                '自动探测': item.probeEnabled ? '已开启' : '已关闭',
                                '模板范围': item.visibleTemplateIds == null
                                    ? '全部模板'
                                    : item.visibleTemplateIds!.join('、'),
                                '请求头数量': '${item.headers.length}',
                                '环境变量数量': '${item.environment.length}',
                              },
                              detailSections: <String, String>{
                                if (_dingtalkSafeMcpEndpoint(
                                  item,
                                ).trim().isNotEmpty)
                                  '连接信息': _dingtalkSafeMcpEndpoint(item),
                              },
                            ),
                          )
                          .toList(growable: false),
                      selected: _mcpServers,
                      apply: (value) => _mcpServers = value,
                    ),
                  ),
                  kOpenHandGap10,
                  _DingTalkResourceField(
                    icon: Icons.extension_rounded,
                    title: '拓展能力 · 钉钉 DWS',
                    selectedCount: _dwsCommands.length,
                    totalCount: _dwsCatalog.length,
                    selectionNote: '勾选后直接注入提示词',
                    refreshing: _dwsCatalogLoading,
                    onRefresh: () => _loadDwsCatalog(forceRefresh: true),
                    onTap: _dwsCatalogLoading
                        ? () => showOpenHandInfoSnack(
                            context,
                            'DWS 命令目录正在加载，请稍候。',
                          )
                        : _dwsCatalog.isEmpty
                        ? () => _loadDwsCatalog(forceRefresh: true)
                        : _selectDwsCommands,
                  ),
                  if (_dwsCatalogError != null) ...[
                    kOpenHandGap6,
                    _DingTalkInfoBanner(
                      icon: Icons.info_outline_rounded,
                      text: _dwsCatalogError!,
                    ),
                  ],
                  kOpenHandGap10,
                  _DingTalkResourceField(
                    icon: Icons.auto_awesome_motion_rounded,
                    title: '多模态能力',
                    selectedCount: _multimodalCapabilities.length,
                    totalCount: AiDingTalkMultimodalCapability.values.length,
                    selectionNote: '勾选后直接注入提示词并作为正式响应',
                    showRefresh: false,
                    refreshing: false,
                    onRefresh: () {},
                    onTap: _selectMultimodalCapabilities,
                  ),
                  kOpenHandGap10,
                  _DingTalkResourceField(
                    icon: Icons.auto_fix_high_rounded,
                    title: '技能',
                    selectedCount: _skills.length,
                    totalCount: widget.controller.skills.length,
                    refreshing: _isRefreshingResourceCatalog(
                      DingTalkGatewayResourceCatalog.skills,
                    ),
                    onRefresh: () => _refreshResourceCatalog(
                      DingTalkGatewayResourceCatalog.skills,
                    ),
                    onTap: () => _selectResources(
                      title: '选择技能',
                      icon: Icons.auto_fix_high_rounded,
                      options: widget.controller.skills
                          .map(
                            (item) => _DingTalkResourceOption(
                              id: item.name,
                              title: item.name,
                              subtitle: item.description,
                              icon: Icons.auto_fix_high_rounded,
                              detailDescription: item.description,
                              detailFields: <String, String>{
                                '资源类型': '技能',
                                '技能目录': item.displayDirectoryPath,
                                '清单文件': item.manifestPath,
                                '图标状态': item.hasIcon || item.hasEmojiIcon
                                    ? '已配置'
                                    : '未配置',
                              },
                              detailSections: <String, String>{
                                if (item.defaultPrompt?.trim().isNotEmpty ==
                                    true)
                                  '默认提示词': item.defaultPrompt!.trim(),
                              },
                            ),
                          )
                          .toList(growable: false),
                      selected: _skills,
                      apply: (value) => _skills = value,
                    ),
                  ),
                  kOpenHandGap10,
                  _DingTalkResourceField(
                    icon: Icons.psychology_alt_rounded,
                    title: '记忆',
                    selectedCount: _memories.length,
                    totalCount: widget.controller.memories.length,
                    refreshing: _isRefreshingResourceCatalog(
                      DingTalkGatewayResourceCatalog.memories,
                    ),
                    onRefresh: () => _refreshResourceCatalog(
                      DingTalkGatewayResourceCatalog.memories,
                    ),
                    onTap: () => _selectResources(
                      title: '选择记忆',
                      icon: Icons.psychology_alt_rounded,
                      options: widget.controller.memories
                          .map(
                            (item) => _DingTalkResourceOption(
                              id: item.id,
                              title: item.displayTitle,
                              subtitle: item.preview,
                              icon: Icons.psychology_alt_rounded,
                              detailDescription: item.preview,
                              detailFields: <String, String>{
                                '资源类型': '记忆',
                                '记忆类型': item.type,
                                '创建时间': formatYearMonthDayHm(
                                  item.createdAt.toLocal(),
                                ),
                                '标签': item.tags.isEmpty
                                    ? '无'
                                    : item.tags.join('、'),
                              },
                              detailSections: <String, String>{
                                '记忆内容': item.content,
                              },
                            ),
                          )
                          .toList(growable: false),
                      selected: _memories,
                      apply: (value) => _memories = value,
                    ),
                  ),
                  kOpenHandGap10,
                  _DingTalkResourceField(
                    icon: Icons.rule_rounded,
                    title: '指令',
                    selectedCount: _instructions.length,
                    totalCount: widget.controller.instructions.length,
                    refreshing: _isRefreshingResourceCatalog(
                      DingTalkGatewayResourceCatalog.instructions,
                    ),
                    onRefresh: () => _refreshResourceCatalog(
                      DingTalkGatewayResourceCatalog.instructions,
                    ),
                    onTap: () => _selectResources(
                      title: '选择指令',
                      icon: Icons.rule_rounded,
                      options: widget.controller.instructions
                          .map(
                            (item) => _DingTalkResourceOption(
                              id: item.id,
                              title: item.name,
                              subtitle: item.description,
                              icon: Icons.rule_rounded,
                              detailDescription: item.description,
                              detailFields: <String, String>{
                                '资源类型': '用户指令',
                                '版本': item.version,
                                '启用状态': item.enabled ? '已启用' : '未启用',
                                '适用场景': item.applyTo,
                                '任务类型': item.taskTypes.join('、'),
                                '关键词': item.keywords.join('、'),
                                '更新时间': formatYearMonthDayHm(
                                  item.updatedAt.toLocal(),
                                ),
                              },
                              detailSections: <String, String>{
                                '指令正文': item.body,
                                if (item.notes.isNotEmpty)
                                  '备注': item.notes.join('\n'),
                              },
                            ),
                          )
                          .toList(growable: false),
                      selected: _instructions,
                      apply: (value) => _instructions = value,
                    ),
                  ),
                  kOpenHandGap10,
                  _DingTalkResourceField(
                    icon: Icons.menu_book_rounded,
                    title: '知识库',
                    selectedCount: _knowledgeSources.length,
                    totalCount: widget.controller.knowledgeSources.length,
                    refreshing: _isRefreshingResourceCatalog(
                      DingTalkGatewayResourceCatalog.knowledgeBase,
                    ),
                    onRefresh: () => _refreshResourceCatalog(
                      DingTalkGatewayResourceCatalog.knowledgeBase,
                    ),
                    onTap: () => _selectResources(
                      title: '选择知识库',
                      icon: Icons.menu_book_rounded,
                      options: widget.controller.knowledgeSources
                          .map(
                            (item) => _DingTalkResourceOption(
                              id: item.id,
                              title: item.title,
                              subtitle: item.status,
                              icon: Icons.menu_book_rounded,
                              detailDescription:
                                  '已导入应用知识库的 ${item.kind} 资源，可为钉钉会话提供检索增强上下文。',
                              detailFields: <String, String>{
                                '资源类型': '知识库',
                                '内容类型': item.kind,
                                '索引状态': item.status,
                                'MIME 类型': item.mimeType,
                                '文件大小': formatByteSize(item.sizeBytes),
                                '导入时间': formatYearMonthDayHm(
                                  item.importedAt.toLocal(),
                                ),
                                '索引时间': item.indexedAt == null
                                    ? '尚未索引'
                                    : formatYearMonthDayHm(
                                        item.indexedAt!.toLocal(),
                                      ),
                              },
                              detailSections: <String, String>{
                                if (item.originalPath.trim().isNotEmpty)
                                  '原始路径': item.originalPath,
                                if (item.storedPath.trim().isNotEmpty)
                                  '存储路径': item.storedPath,
                                if (item.contentHash.trim().isNotEmpty)
                                  '内容摘要': item.contentHash,
                                if (item.errorMessage.trim().isNotEmpty)
                                  '异常信息': item.errorMessage,
                              },
                            ),
                          )
                          .toList(growable: false),
                      selected: _knowledgeSources,
                      apply: (value) => _knowledgeSources = value,
                    ),
                  ),
                  kOpenHandGap10,
                  _DingTalkResourceField(
                    icon: Icons.account_tree_rounded,
                    title: '工作流',
                    selectedCount: _workflows.length,
                    totalCount: widget.controller.workflows.length,
                    refreshing: _isRefreshingResourceCatalog(
                      DingTalkGatewayResourceCatalog.workflows,
                    ),
                    onRefresh: () => _refreshResourceCatalog(
                      DingTalkGatewayResourceCatalog.workflows,
                    ),
                    onTap: () => _selectResources(
                      title: '选择工作流',
                      icon: Icons.account_tree_rounded,
                      options: widget.controller.workflows
                          .map(
                            (item) => _DingTalkResourceOption(
                              id: item.id,
                              title: item.name,
                              subtitle: item.description,
                              icon: Icons.account_tree_rounded,
                              workflow: item,
                              detailDescription: item.description,
                              detailDescriptionTitle: '简要介绍',
                              detailLongDescription: item.details,
                              detailFields: <String, String>{
                                '资源类型': '工作流',
                                '启用状态': item.enabled ? '已启用' : '已停用',
                                '标签': item.tags.isEmpty
                                    ? '无'
                                    : item.tags.join('、'),
                              },
                            ),
                          )
                          .toList(growable: false),
                      selected: _workflows,
                      apply: (value) => _workflows = value,
                    ),
                  ),
                  kOpenHandGap14,
                  _DingTalkSettingsCard(
                    icon: Icons.auto_awesome_rounded,
                    title: '响应模型',
                    subtitle: _modelLabel(),
                    onTap: _selectModel,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Builder(
                          builder: (buttonContext) => Tooltip(
                            message: reasoningTooltip,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              excludeFromSemantics: true,
                              onTap: reasoningAdjustable ? null : () {},
                              child: FilledButton.tonalIcon(
                                onPressed: reasoningAdjustable
                                    ? () => unawaited(
                                        _selectReasoningEffort(buttonContext),
                                      )
                                    : null,
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(0, 40),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  shadowColor: Colors.transparent,
                                  shape: const StadiumBorder(),
                                ),
                                icon: Icon(
                                  reasoningAdjustable
                                      ? Icons.psychology_alt_rounded
                                      : responseModel
                                                ?.resolvedThinkingEnabled ==
                                            true
                                      ? Icons.lock_rounded
                                      : Icons.psychology_alt_outlined,
                                  size: 17,
                                ),
                                label: Text('推理 · $reasoningEffortLabel'),
                              ),
                            ),
                          ),
                        ),
                        kOpenHandHGap4,
                        IconButton.filledTonal(
                          tooltip: '选择响应模型',
                          onPressed: _selectModel,
                          style: IconButton.styleFrom(
                            fixedSize: const Size(40, 40),
                            padding: EdgeInsets.zero,
                            shape: const CircleBorder(),
                            shadowColor: Colors.transparent,
                          ),
                          icon: const Icon(Icons.chevron_right_rounded),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            OpenHandDialogSaveActions(
              busy: _saving,
              cancelLabel: '取消',
              confirmLabel: '保存设置',
              onConfirm: _save,
            ),
          ],
        ),
      ),
    );
  }

  List<String> _availableTemplateIds() => widget.controller.templates
      .map((item) => item.id)
      .toList(growable: false);

  Future<void> _pickWorkingDirectory() async {
    final selected = await getDirectoryPath(
      initialDirectory: _workingDirectoryController.text.trim().isEmpty
          ? null
          : _workingDirectoryController.text.trim(),
    );
    if (selected != null && mounted) {
      _workingDirectoryController.text = selected;
    }
  }

  bool _isRefreshingResourceCatalog(DingTalkGatewayResourceCatalog catalog) =>
      _refreshingResourceCatalogs.contains(catalog);

  Future<void> _refreshResourceCatalog(
    DingTalkGatewayResourceCatalog catalog,
  ) async {
    if (_isRefreshingResourceCatalog(catalog)) return;
    setState(() => _refreshingResourceCatalogs.add(catalog));
    try {
      await widget.controller.refreshResourceCatalog(catalog);
      if (!mounted) return;
      setState(() {
        switch (catalog) {
          case DingTalkGatewayResourceCatalog.mcp:
            _mcpServers.retainAll(
              widget.controller.mcpServers.map((item) => item.name),
            );
          case DingTalkGatewayResourceCatalog.skills:
            _skills.retainAll(
              widget.controller.skills.map((item) => item.name),
            );
          case DingTalkGatewayResourceCatalog.memories:
            _memories.retainAll(
              widget.controller.memories.map((item) => item.id),
            );
          case DingTalkGatewayResourceCatalog.instructions:
            _instructions.retainAll(
              widget.controller.instructions.map((item) => item.id),
            );
          case DingTalkGatewayResourceCatalog.knowledgeBase:
            _knowledgeSources.retainAll(
              widget.controller.knowledgeSources.map((item) => item.id),
            );
          case DingTalkGatewayResourceCatalog.workflows:
            _workflows.retainAll(
              widget.controller.workflows.map((item) => item.id),
            );
        }
      });
    } catch (error) {
      if (mounted) showOpenHandErrorSnack(context, '刷新资源失败：$error');
    } finally {
      if (mounted) {
        setState(() => _refreshingResourceCatalogs.remove(catalog));
      }
    }
  }

  Future<void> _loadDwsCatalog({bool forceRefresh = false}) async {
    if (_dwsCatalogLoading) return;
    if (mounted) {
      setState(() {
        _dwsCatalogLoading = true;
        _dwsCatalogError = null;
      });
    }
    try {
      final catalog = await widget.controller.loadDwsCommandCatalog(
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      final available = catalog.map((item) => item.cliPath).toSet();
      setState(() {
        _dwsCatalog = catalog;
        _dwsCommands.retainAll(available);
        if (catalog.isEmpty) {
          final serviceError = widget.controller.dwsCommandCatalogError;
          _dwsCatalogError = serviceError == null || serviceError.isEmpty
              ? widget.controller.isInstalled
                    ? 'dws 未返回可用命令，请点击刷新重试。'
                    : '未找到 dws，请先在插件板块安装后重试。'
              : 'DWS 命令目录加载失败：$serviceError。可点击刷新重试。';
        }
      });
    } catch (error) {
      if (mounted) {
        final message = error.toString().replaceFirst('FormatException: ', '');
        setState(() => _dwsCatalogError = 'DWS 命令目录加载失败：$message。可点击刷新重试。');
      }
      silentLog('message_gateway', '加载钉钉 DWS 命令目录', error, StackTrace.current);
    } finally {
      if (mounted) setState(() => _dwsCatalogLoading = false);
    }
  }

  Future<void> _selectDwsCommands() async {
    if (_dwsCatalogLoading) {
      showOpenHandInfoSnack(context, 'DWS 命令目录正在加载，请稍候。');
      return;
    }
    if (_dwsCatalog.isEmpty) {
      await _loadDwsCatalog(forceRefresh: true);
      if (!mounted || _dwsCatalog.isEmpty) return;
    }
    final options = _dwsCatalog
        .map(
          (item) => _DingTalkResourceOption(
            id: item.cliPath,
            title: item.cliPath,
            subtitle: '${item.productName} · ${item.description}',
            icon: Icons.extension_rounded,
            groupKey: item.productId,
            groupTitle: item.productName.isEmpty
                ? item.productId
                : item.productName,
            detailDescription: item.description.trim().isEmpty
                ? item.summary
                : item.description,
            detailFields: <String, String>{
              '资源类型': '钉钉 DWS 内建工具',
              '所属产品': item.productName,
              '命令路径': item.cliPath,
              '执行效果': item.effect,
              '风险等级': item.risk,
              '确认策略': item.confirmation,
              '参数数量': '${item.parameters.length}',
            },
            detailSections: <String, String>{
              if (item.summary.trim().isNotEmpty) '能力摘要': item.summary,
            },
            detailParameters: item.parameters.entries
                .map((entry) {
                  final schema = stringKeyedMapFromValue(entry.value);
                  return (
                    name: entry.key,
                    type: '${schema['type'] ?? 'string'}',
                    requirement: schema['required'] == true ? '必填' : '可选',
                    description: '${schema['description'] ?? ''}'.trim(),
                  );
                })
                .toList(growable: false),
            detailExamples: item.examples,
          ),
        )
        .toList(growable: false);
    await _selectResources(
      title: '选择钉钉 DWS 拓展能力',
      icon: Icons.extension_rounded,
      options: options,
      selected: _dwsCommands,
      selectionHint: '勾选的能力会作为内建工具直接注入提示词；未勾选能力不会加载。',
      apply: (value) => _dwsCommands = value,
    );
  }

  Future<void> _selectMultimodalCapabilities() async {
    final result = await showAnimatedDialog<_DingTalkMultimodalSelection>(
      context: context,
      builder: (_) => buildOpenHandDialog(
        maxWidth: kOpenHandDialogWidthStandard,
        maxHeight: kOpenHandDialogHeightFull,
        child: _DingTalkMultimodalPickerDialog(
          selected: _multimodalCapabilities,
          imageModelKey: _imageGenerationModelKey,
          videoModelKey: _videoGenerationModelKey,
          audioModelKey: _audioGenerationModelKey,
          models: widget.controller.aiModels,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _multimodalCapabilities = result.capabilities;
      _imageGenerationModelKey = result.imageModelKey;
      _videoGenerationModelKey = result.videoModelKey;
      _audioGenerationModelKey = result.audioModelKey;
    });
  }

  Future<void> _selectResources({
    required String title,
    required IconData icon,
    required List<_DingTalkResourceOption> options,
    required Set<String> selected,
    String? selectionHint,
    required void Function(Set<String>) apply,
  }) async {
    final result = await showAnimatedDialog<Set<String>>(
      context: context,
      builder: (_) => buildOpenHandDialog(
        maxWidth: kOpenHandDialogWidthStandard,
        maxHeight: kOpenHandDialogHeightFull,
        child: _DingTalkResourcePickerDialog(
          title: title,
          icon: icon,
          options: options,
          selected: selected,
          selectionHint: selectionHint,
        ),
      ),
    );
    if (result != null && mounted) setState(() => apply(result));
  }

  Future<void> _selectAllowedTargets({
    required DingTalkConversationType type,
    required String title,
    required IconData icon,
    required List<DingTalkConversationTarget> selected,
  }) async {
    final result = await showAnimatedDialog<List<DingTalkConversationTarget>>(
      context: context,
      builder: (_) => buildOpenHandDialog(
        maxWidth: kOpenHandDialogWidthStandard,
        maxHeight: kOpenHandDialogHeightFull,
        child: _DingTalkAllowlistPickerDialog(
          title: title,
          icon: icon,
          type: type,
          selected: selected,
          controller: widget.controller,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (type == DingTalkConversationType.group) {
        _allowedGroups = List<DingTalkConversationTarget>.from(result);
      } else {
        _allowedContacts = List<DingTalkConversationTarget>.from(result);
      }
    });
  }

  Future<void> _selectModel() async {
    final current = _splitModelKey(_modelKey);
    final selected = await showModelSearchSelector(
      context: context,
      models: widget.controller.aiModels,
      selectedConfigId: current.$1,
      selectedModelId: current.$2,
    );
    if (selected != null && mounted) {
      setState(() => _modelKey = '${selected.$1}::${selected.$2}');
    }
  }

  Future<void> _selectReasoningEffort(BuildContext buttonContext) async {
    final model = _resolvedResponseModel();
    if (model == null || !model.resolvedReasoningEffortControlEnabled) return;
    final options = model.resolvedReasoningEffortOptions
        .where((option) => option.isSelectable)
        .toList(growable: false);
    if (options.isEmpty) return;
    await showReasoningEffortSelector(
      context: context,
      anchorContext: buttonContext,
      options: options,
      currentValue: model.resolvedReasoningEffort,
      onChanged: (effort) async {
        if (!mounted) return false;
        var saved = false;
        try {
          saved = await context
              .read<SettingsController>()
              .updateAiModelReasoningEffort(model.id, model.modelId, effort);
        } catch (_) {
          // 选择器会回滚到已保存的推理强度。
        }
        if (!mounted) return false;
        if (saved) {
          setState(() {});
          return true;
        }
        showOpenHandErrorSnack(context, '推理强度保存失败，请检查当前模型配置。');
        return false;
      },
    );
  }

  Future<void> _save() async {
    final seconds = DingTalkGatewaySettings.normalizePollIntervalSeconds(
      _intervalController.text,
    );
    final workerCount = optionalIntegralIntFromValue(
      _workerCountController.text,
    );
    if (workerCount == null ||
        workerCount < DingTalkGatewaySettings.minResponseWorkerCount ||
        workerCount > DingTalkGatewaySettings.maxResponseWorkerCount) {
      showOpenHandErrorSnack(
        context,
        '工作线程数必须为 ${DingTalkGatewaySettings.minResponseWorkerCount}–${DingTalkGatewaySettings.maxResponseWorkerCount} 的整数。',
      );
      return;
    }
    final rawDirectory = _workingDirectoryController.text.trim();
    final workingDirectory = Directory(
      OpenHandPaths.normalizePath(
        rawDirectory,
        defaultPath: OpenHandPaths.applicationDirectoryPath(),
      ),
    ).absolute.path;
    if (!await _pathExistsBounded(Directory(workingDirectory))) {
      if (mounted) showOpenHandErrorSnack(context, '工作目录不存在，请选择有效目录。');
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.controller.updateSettings(
        DingTalkGatewaySettings(
          pollIntervalSeconds: seconds,
          responseWorkerCount: workerCount,
          overloadStrategy: _overloadStrategy,
          reminderMode: _reminderMode,
          responseMode: _responseMode,
          responseModelKey: _modelKey,
          workingDirectory: workingDirectory,
          fullAccessPermission: _fullAccessPermission,
          templateId: _templateId,
          allowedMcpServerNames: _mcpServers.toList(growable: false),
          allowedSkillNames: _skills.toList(growable: false),
          allowedMemoryIds: _memories.toList(growable: false),
          allowedInstructionIds: _instructions.toList(growable: false),
          allowedKnowledgeBaseSourceIds: _knowledgeSources.toList(
            growable: false,
          ),
          allowedWorkflowIds: _workflows.toList(growable: false),
          allowedDingTalkDwsCommandIds: _dwsCommands.toList(growable: false),
          enabledMultimodalCapabilities: _multimodalCapabilities,
          imageGenerationModelKey: _imageGenerationModelKey,
          videoGenerationModelKey: _videoGenerationModelKey,
          audioGenerationModelKey: _audioGenerationModelKey,
          allowedGroupTargets: _allowedGroups,
          allowedContactTargets: _allowedContacts,
          responseEchoTypes: DingTalkResponseEchoType.values
              .where(_responseEchoTypes.contains)
              .toList(growable: false),
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) showOpenHandErrorSnack(context, '保存设置失败：$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _modelLabel() {
    final key = _splitModelKey(_modelKey);
    if (key.$1.isEmpty || key.$2.isEmpty) {
      final active = widget.controller.activeAiModel;
      return active == null
          ? '跟随当前活跃模型 · 暂无可用模型'
          : '跟随当前活跃模型 · ${active.providerLabel} / ${active.displayName}';
    }
    for (final model in widget.controller.aiModels) {
      if (model.id == key.$1) return '${model.providerLabel} / ${key.$2}';
    }
    return '${key.$1} / ${key.$2}';
  }

  AiModelConfig? _resolvedResponseModel() {
    final key = _splitModelKey(_modelKey);
    if (key.$1.isEmpty || key.$2.isEmpty) {
      return widget.controller.activeAiModel;
    }
    for (final provider in widget.controller.aiModels) {
      if (provider.id == key.$1 && provider.allModelIds.contains(key.$2)) {
        return provider.copyWith(modelId: key.$2);
      }
    }
    return null;
  }

  (String, String) _splitModelKey(String key) {
    final index = key.indexOf('::');
    return index > 0
        ? (key.substring(0, index), key.substring(index + 2))
        : ('', '');
  }

  String _responseEchoTypeLabel(DingTalkResponseEchoType type) =>
      switch (type) {
        DingTalkResponseEchoType.thinking => '思考',
        DingTalkResponseEchoType.process => '过程响应',
        DingTalkResponseEchoType.toolCall => '工具调用',
        DingTalkResponseEchoType.finalResponse => '正式响应',
      };

  IconData _responseEchoTypeIcon(DingTalkResponseEchoType type) =>
      switch (type) {
        DingTalkResponseEchoType.thinking => Icons.psychology_alt_rounded,
        DingTalkResponseEchoType.process => Icons.route_rounded,
        DingTalkResponseEchoType.toolCall => Icons.build_circle_rounded,
        DingTalkResponseEchoType.finalResponse => Icons.mark_chat_read_rounded,
      };
}

typedef _DingTalkMultimodalSelection = ({
  Set<AiDingTalkMultimodalCapability> capabilities,
  String imageModelKey,
  String videoModelKey,
  String audioModelKey,
});

class _DingTalkMultimodalPickerDialog extends StatefulWidget {
  const _DingTalkMultimodalPickerDialog({
    required this.selected,
    required this.imageModelKey,
    required this.videoModelKey,
    required this.audioModelKey,
    required this.models,
  });

  final Set<AiDingTalkMultimodalCapability> selected;
  final String imageModelKey;
  final String videoModelKey;
  final String audioModelKey;
  final List<AiModelConfig> models;

  @override
  State<_DingTalkMultimodalPickerDialog> createState() =>
      _DingTalkMultimodalPickerDialogState();
}

class _DingTalkMultimodalPickerDialogState
    extends State<_DingTalkMultimodalPickerDialog> {
  late final Set<AiDingTalkMultimodalCapability> _selected = widget.selected
      .toSet();
  late String _imageModelKey = widget.imageModelKey;
  late String _videoModelKey = widget.videoModelKey;
  late String _audioModelKey = widget.audioModelKey;

  String _keyFor(AiDingTalkMultimodalCapability capability) =>
      switch (capability) {
        AiDingTalkMultimodalCapability.imageGeneration => _imageModelKey,
        AiDingTalkMultimodalCapability.videoGeneration => _videoModelKey,
        AiDingTalkMultimodalCapability.audioGeneration => _audioModelKey,
      };

  void _setKey(AiDingTalkMultimodalCapability capability, String value) {
    setState(() {
      switch (capability) {
        case AiDingTalkMultimodalCapability.imageGeneration:
          _imageModelKey = value;
        case AiDingTalkMultimodalCapability.videoGeneration:
          _videoModelKey = value;
        case AiDingTalkMultimodalCapability.audioGeneration:
          _audioModelKey = value;
      }
    });
  }

  List<AiModelConfig> _modelsFor(AiDingTalkMultimodalCapability capability) {
    final result = widget.models
        .where(
          (model) => model.allModelIds.any(
            (modelId) => _supportsModel(capability, model, modelId),
          ),
        )
        .toList(growable: false);
    final currentKey = _keyFor(capability);
    final current = _splitModelKey(currentKey);
    final currentProvider = current.$1;
    if (currentProvider.isNotEmpty &&
        result.every((model) => model.id != currentProvider)) {
      for (final model in widget.models) {
        if (model.id == currentProvider &&
            _supportsModel(capability, model, current.$2)) {
          return <AiModelConfig>[...result, model];
        }
      }
    }
    return result;
  }

  Future<void> _selectModel(AiDingTalkMultimodalCapability capability) async {
    final models = _modelsFor(capability);
    if (models.isEmpty) {
      showOpenHandInfoSnack(
        context,
        '暂无支持${capability.displayName}的模型，请先在模型设置中配置。',
      );
      return;
    }
    final current = _splitModelKey(_keyFor(capability));
    final selected = await showModelSearchSelector(
      context: context,
      models: models,
      selectedConfigId: current.$1,
      selectedModelId: current.$2,
      modelFilter: (config, modelId) =>
          _supportsModel(capability, config, modelId),
    );
    if (selected != null && mounted) {
      _setKey(capability, '${selected.$1}::${selected.$2}');
    }
  }

  String _modelLabel(AiDingTalkMultimodalCapability capability) {
    final key = _keyFor(capability);
    final split = _splitModelKey(key);
    if (split.$1.isEmpty || split.$2.isEmpty) return '选择模型';
    for (final model in widget.models) {
      if (model.id == split.$1) return '${model.providerLabel} / ${split.$2}';
    }
    return '${split.$1} / ${split.$2}';
  }

  (String, String) _splitModelKey(String key) {
    final index = key.indexOf('::');
    return index > 0
        ? (key.substring(0, index), key.substring(index + 2))
        : ('', '');
  }

  void _apply() {
    for (final capability in _selected) {
      final key = _keyFor(capability).trim();
      final split = _splitModelKey(key);
      final config = widget.models
          .where((model) => model.id == split.$1)
          .firstOrNull;
      if (split.$1.isEmpty ||
          split.$2.isEmpty ||
          config == null ||
          !_supportsModel(capability, config, split.$2)) {
        showOpenHandInfoSnack(context, '请为已勾选的${capability.displayName}选择模型。');
        return;
      }
    }
    Navigator.of(context).pop((
      capabilities: Set<AiDingTalkMultimodalCapability>.from(_selected),
      imageModelKey: _imageModelKey,
      videoModelKey: _videoModelKey,
      audioModelKey: _audioModelKey,
    ));
  }

  bool _supportsModel(
    AiDingTalkMultimodalCapability capability,
    AiModelConfig config,
    String modelId,
  ) {
    final selected = config.copyWith(modelId: modelId.trim());
    return switch (capability) {
      AiDingTalkMultimodalCapability.imageGeneration =>
        AiImageGenerationService.supportsImageGenerationForModel(selected),
      AiDingTalkMultimodalCapability.videoGeneration =>
        AiImageGenerationService.supportsVideoGenerationForModel(selected),
      AiDingTalkMultimodalCapability.audioGeneration =>
        AiImageGenerationService.supportsAudioGenerationForModel(selected),
    };
  }

  int _supportedModelCount(AiDingTalkMultimodalCapability capability) {
    return widget.models.fold<int>(
      0,
      (count, model) =>
          count +
          model.allModelIds
              .where((modelId) => _supportsModel(capability, model, modelId))
              .length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SizedBox(
      width: double.infinity,
      height: 560,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_motion_rounded, color: colors.primary),
                kOpenHandHGap9,
                Text('多模态能力', style: theme.textTheme.titleLarge),
                const Spacer(),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            kOpenHandGap6,
            Text(
              '默认全不选。勾选后，工具 Schema 会直接注入钉钉会话提示词；生成完成并发送文件后立即结束本轮响应。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            kOpenHandGap14,
            Expanded(
              child: ListView.separated(
                itemCount: AiDingTalkMultimodalCapability.values.length,
                separatorBuilder: (_, index) => kOpenHandGap8,
                itemBuilder: (context, index) {
                  final capability =
                      AiDingTalkMultimodalCapability.values[index];
                  final selected = _selected.contains(capability);
                  final modelCount = _supportedModelCount(capability);
                  return Material(
                    color: selected
                        ? colors.primaryContainer.withValues(alpha: 0.5)
                        : colors.surfaceContainerHighest,
                    borderRadius: kOpenHandBorderRadius14,
                    shadowColor: Colors.transparent,
                    surfaceTintColor: Colors.transparent,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(6, 5, 8, 5),
                      child: Row(
                        children: [
                          Checkbox(
                            value: selected,
                            onChanged: (value) => setState(() {
                              if (value == true) {
                                _selected.add(capability);
                              } else {
                                _selected.remove(capability);
                              }
                            }),
                          ),
                          Icon(switch (capability) {
                            AiDingTalkMultimodalCapability.imageGeneration =>
                              Icons.image_outlined,
                            AiDingTalkMultimodalCapability.videoGeneration =>
                              Icons.movie_creation_outlined,
                            AiDingTalkMultimodalCapability.audioGeneration =>
                              Icons.graphic_eq_rounded,
                          }, color: colors.primary),
                          kOpenHandHGap9,
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  capability.displayName,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                kOpenHandGap2,
                                Text(
                                  selected
                                      ? _modelLabel(capability)
                                      : '$modelCount 个可用模型 · 未启用',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          kOpenHandHGap8,
                          OutlinedButton.icon(
                            onPressed: selected
                                ? () => _selectModel(capability)
                                : null,
                            icon: const Icon(
                              Icons.model_training_rounded,
                              size: 17,
                            ),
                            label: Text(
                              _keyFor(capability).trim().isEmpty
                                  ? '配置模型'
                                  : '更换模型',
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            OpenHandDialogSaveActions(
              busy: false,
              cancelLabel: '取消',
              confirmLabel: '应用选择',
              onConfirm: _apply,
            ),
          ],
        ),
      ),
    );
  }
}

class _DingTalkSettingsCard extends StatelessWidget {
  const _DingTalkSettingsCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.child,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? child;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: kOpenHandBorderRadius12,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(9),
                  child: Icon(
                    icon,
                    size: 20,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              kOpenHandHGap11,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    kOpenHandGap3,
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          if (child != null) ...[kOpenHandGap11, child!],
        ],
      ),
    );
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      shadowColor: Colors.transparent,
      borderRadius: BorderRadius.circular(kOpenHandRadius17),
      child: onTap == null
          ? content
          : InkWell(
              borderRadius: BorderRadius.circular(kOpenHandRadius17),
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              onTap: onTap,
              child: content,
            ),
    );
  }
}

class _DingTalkInfoBanner extends StatelessWidget {
  const _DingTalkInfoBanner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.tertiaryContainer.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(kOpenHandRadius13),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            Icon(icon, size: 18, color: colors.onTertiaryContainer),
            kOpenHandHGap8,
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onTertiaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DingTalkResourceField extends StatelessWidget {
  const _DingTalkResourceField({
    required this.icon,
    required this.title,
    required this.selectedCount,
    required this.totalCount,
    this.selectionNote,
    this.showRefresh = true,
    required this.refreshing,
    required this.onRefresh,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final int selectedCount;
  final int totalCount;
  final String? selectionNote;
  final bool showRefresh;
  final bool refreshing;
  final VoidCallback onRefresh;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      shadowColor: Colors.transparent,
      borderRadius: kOpenHandBorderRadius16,
      child: InkWell(
        borderRadius: kOpenHandBorderRadius16,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 11, 8, 11),
          child: Row(
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              kOpenHandHGap11,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    kOpenHandGap3,
                    Text(
                      selectionNote == null
                          ? '已选 $selectedCount/$totalCount（默认全不选）'
                          : '已选 $selectedCount/$totalCount · $selectionNote',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (showRefresh) ...[
                IconButton.filledTonal(
                  tooltip: '刷新 $title',
                  onPressed: refreshing ? null : onRefresh,
                  style: IconButton.styleFrom(
                    fixedSize: const Size(40, 40),
                    padding: EdgeInsets.zero,
                    shape: const CircleBorder(),
                    shadowColor: Colors.transparent,
                  ),
                  icon: refreshing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
                kOpenHandHGap4,
              ],
              IconButton.filledTonal(
                tooltip: '查看 $title详情',
                onPressed: onTap,
                style: IconButton.styleFrom(
                  fixedSize: const Size(40, 40),
                  padding: EdgeInsets.zero,
                  shape: const CircleBorder(),
                  shadowColor: Colors.transparent,
                ),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

typedef _DingTalkResourceParameterDetail = ({
  String name,
  String type,
  String requirement,
  String description,
});

class _DingTalkResourceOption {
  const _DingTalkResourceOption({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.groupKey,
    this.groupTitle,
    this.workflow,
    this.detailDescription = '',
    this.detailDescriptionTitle = '详细介绍',
    this.detailLongDescription,
    this.detailFields = const <String, String>{},
    this.detailSections = const <String, String>{},
    this.detailParameters = const <_DingTalkResourceParameterDetail>[],
    this.detailExamples = const <String>[],
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final String? groupKey;
  final String? groupTitle;
  final WorkflowDefinition? workflow;
  final String detailDescription;
  final String detailDescriptionTitle;
  final String? detailLongDescription;
  final Map<String, String> detailFields;
  final Map<String, String> detailSections;
  final List<_DingTalkResourceParameterDetail> detailParameters;
  final List<String> detailExamples;
}

class _DingTalkResourceDetailsDialog extends StatelessWidget {
  const _DingTalkResourceDetailsDialog({required this.option});

  final _DingTalkResourceOption option;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final description = option.detailDescription.trim().isNotEmpty
        ? option.detailDescription.trim()
        : option.subtitle.trim().isNotEmpty
        ? option.subtitle.trim()
        : option.detailDescriptionTitle == '简要介绍'
        ? '暂无简要介绍。'
        : '暂无详细介绍。';
    final longDescription = option.detailLongDescription?.trim();
    final fields = option.detailFields.entries
        .where((entry) => entry.value.trim().isNotEmpty)
        .toList(growable: false);
    final sections = option.detailSections.entries
        .where((entry) => entry.value.trim().isNotEmpty)
        .toList(growable: false);
    final parameters = option.detailParameters;
    final examples = option.detailExamples
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final typeLabel = option.detailFields['资源类型']?.trim().isNotEmpty == true
        ? option.detailFields['资源类型']!.trim()
        : option.groupTitle?.trim().isNotEmpty == true
        ? option.groupTitle!.trim()
        : '资源详情';
    return SizedBox(
      width: double.infinity,
      height: 580,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(kOpenHandRadius15),
                    border: Border.all(
                      color: colors.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Icon(option.icon, color: colors.onPrimaryContainer),
                ),
                kOpenHandHGap12,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      kOpenHandGap3,
                      Text(
                        typeLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '关闭详情',
                  onPressed: () => Navigator.of(context).pop(),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    hoverColor: Colors.transparent,
                    focusColor: Colors.transparent,
                    highlightColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                  ),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            kOpenHandGap16,
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(right: 4, bottom: 4),
                children: [
                  _buildDetailSection(
                    context,
                    icon: Icons.subject_rounded,
                    title: option.detailDescriptionTitle,
                    content: description,
                    maxContentHeight: _dingtalkResourceIntroMaxHeight,
                  ),
                  if (option.detailLongDescription != null) ...[
                    kOpenHandGap12,
                    _buildDetailSection(
                      context,
                      icon: Icons.notes_rounded,
                      title: '详细介绍',
                      content: longDescription?.isNotEmpty == true
                          ? longDescription!
                          : '暂无详细介绍。',
                      maxContentHeight: _dingtalkResourceIntroMaxHeight,
                    ),
                  ],
                  if (fields.isNotEmpty) ...[
                    kOpenHandGap12,
                    Text(
                      '关键信息',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    kOpenHandGap8,
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth < 520
                            ? constraints.maxWidth
                            : (constraints.maxWidth - 10) / 2;
                        return Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: fields
                              .map(
                                (entry) => SizedBox(
                                  width: width,
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: colors.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(
                                        kOpenHandRadius13,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          entry.key,
                                          style: theme.textTheme.labelMedium
                                              ?.copyWith(
                                                color: colors.onSurfaceVariant,
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                        kOpenHandGap4,
                                        SelectableText(
                                          entry.value,
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              )
                              .toList(growable: false),
                        );
                      },
                    ),
                  ],
                  for (final section in sections) ...[
                    kOpenHandGap12,
                    _buildDetailSection(
                      context,
                      icon: Icons.layers_rounded,
                      title: section.key,
                      content: section.value,
                    ),
                  ],
                  if (parameters.isNotEmpty) ...[
                    kOpenHandGap12,
                    _buildParameterSection(context, parameters),
                  ],
                  if (examples.isNotEmpty) ...[
                    kOpenHandGap12,
                    _buildCodeExampleSection(context, examples),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailSection(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String content,
    double? maxContentHeight,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kOpenHandRadius15),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: colors.primary),
              kOpenHandHGap7,
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          kOpenHandGap9,
          if (maxContentHeight == null)
            SelectableText(
              content,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxContentHeight),
              child: SingleChildScrollView(
                child: SelectableText(
                  content,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildParameterSection(
    BuildContext context,
    List<_DingTalkResourceParameterDetail> parameters,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final gridColor = colors.outlineVariant.withValues(alpha: 0.72);
    final frameColor = colors.outline.withValues(alpha: 0.82);
    const tableRadius = 14.0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kOpenHandRadius15),
        border: Border.all(color: gridColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.table_rows_rounded, size: 18, color: colors.primary),
              kOpenHandHGap7,
              Text(
                '参数说明',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                '${parameters.length} 项',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          kOpenHandGap12,
          LayoutBuilder(
            builder: (context, constraints) {
              final tableWidth = math.max(constraints.maxWidth, 660.0);
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: tableWidth,
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(tableRadius),
                        child: Table(
                          border: TableBorder(
                            horizontalInside: BorderSide(color: gridColor),
                            verticalInside: BorderSide(color: gridColor),
                          ),
                          columnWidths: const <int, TableColumnWidth>{
                            0: FixedColumnWidth(150),
                            1: FixedColumnWidth(92),
                            2: FixedColumnWidth(72),
                            3: FlexColumnWidth(),
                          },
                          defaultVerticalAlignment:
                              TableCellVerticalAlignment.middle,
                          children: [
                            TableRow(
                              decoration: BoxDecoration(
                                color: colors.surfaceContainerHighest,
                              ),
                              children: const [
                                _DingTalkParameterTableCell(
                                  '参数名',
                                  header: true,
                                ),
                                _DingTalkParameterTableCell('类型', header: true),
                                _DingTalkParameterTableCell('要求', header: true),
                                _DingTalkParameterTableCell('说明', header: true),
                              ],
                            ),
                            for (
                              var index = 0;
                              index < parameters.length;
                              index++
                            )
                              TableRow(
                                decoration: BoxDecoration(
                                  color: index.isOdd
                                      ? colors.surfaceContainerHighest
                                            .withValues(alpha: 0.35)
                                      : colors.surface,
                                ),
                                children: [
                                  _DingTalkParameterTableCell(
                                    parameters[index].name,
                                    monospace: true,
                                  ),
                                  _DingTalkParameterTableCell(
                                    parameters[index].type,
                                    monospace: true,
                                  ),
                                  _DingTalkParameterTableCell(
                                    parameters[index].requirement,
                                  ),
                                  _DingTalkParameterTableCell(
                                    parameters[index].description.isEmpty
                                        ? '—'
                                        : parameters[index].description,
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(tableRadius),
                              border: Border.all(color: frameColor, width: 1.5),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCodeExampleSection(BuildContext context, List<String> examples) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final content = examples.join('\n\n');
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kOpenHandRadius15),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
      child: ClipRRect(
        borderRadius: kOpenHandBorderRadius14,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: colors.surfaceContainerHighest,
              padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.terminal_rounded, size: 18, color: colors.primary),
                  kOpenHandHGap7,
                  Text(
                    '调用示例',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Shell',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontFamily: kOpenHandMonospaceFontFamily,
                    ),
                  ),
                  kOpenHandHGap4,
                  IconButton(
                    tooltip: '复制调用示例',
                    onPressed: () => unawaited(
                      copyOpenHandTextToClipboard(
                        context: context,
                        text: content,
                        logTag: 'message_gateway',
                        logAction: '复制钉钉DWS调用示例',
                      ),
                    ),
                    style: IconButton.styleFrom(
                      fixedSize: const Size(34, 34),
                      padding: EdgeInsets.zero,
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                    ),
                    icon: const Icon(Icons.copy_all_rounded, size: 18),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.outlineVariant),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(14),
              child: SelectableText(
                content,
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.55,
                  fontFamily: kOpenHandMonospaceFontFamily,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DingTalkParameterTableCell extends StatelessWidget {
  const _DingTalkParameterTableCell(
    this.text, {
    this.header = false,
    this.monospace = false,
  });

  final String text;
  final bool header;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      height: 1.4,
      fontWeight: header ? FontWeight.w800 : FontWeight.w500,
      color: header ? theme.colorScheme.onSurfaceVariant : null,
      fontFamily: monospace ? kOpenHandMonospaceFontFamily : null,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: header
          ? Text(text, style: style)
          : SelectableText(text, style: style),
    );
  }
}

class _DingTalkResourcePickerDialog extends StatefulWidget {
  const _DingTalkResourcePickerDialog({
    required this.title,
    required this.icon,
    required this.options,
    required this.selected,
    this.selectionHint,
  });

  final String title;
  final IconData icon;
  final List<_DingTalkResourceOption> options;
  final Set<String> selected;
  final String? selectionHint;

  @override
  State<_DingTalkResourcePickerDialog> createState() =>
      _DingTalkResourcePickerDialogState();
}

class _DingTalkResourcePickerDialogState
    extends State<_DingTalkResourcePickerDialog> {
  late final Set<String> _selected = widget.selected.toSet();
  late final Set<String> _expandedGroups = widget.options
      .where((item) => item.groupKey != null)
      .map((item) => item.groupKey!)
      .take(1)
      .toSet();
  final Set<String> _expandedBranches = <String>{};
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _showOptionDetails(
    BuildContext context,
    _DingTalkResourceOption option,
  ) async {
    final workflow = option.workflow;
    if (workflow != null) {
      final aiController = context.read<AiSessionController>();
      final usageStore = aiController.toolUsagePromotionStore;
      await usageStore.initialize();
      if (!context.mounted) return;
      await showWorkflowDetailsDialog(
        context,
        workflow: workflow,
        usageStore: usageStore,
      );
      return;
    }
    await showAnimatedDialog<void>(
      context: context,
      builder: (_) => buildOpenHandDialog(
        maxWidth: kOpenHandDialogWidthStandard,
        maxHeight: kOpenHandDialogHeightFull,
        child: _DingTalkResourceDetailsDialog(option: option),
      ),
    );
  }

  ButtonStyle _transparentIconButtonStyle(ThemeData theme) {
    return IconButton.styleFrom(
      foregroundColor: theme.colorScheme.onSurfaceVariant,
      backgroundColor: Colors.transparent,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
      highlightColor: Colors.transparent,
      shadowColor: Colors.transparent,
      padding: EdgeInsets.zero,
      fixedSize: const Size(38, 38),
      splashFactory: NoSplash.splashFactory,
    ).copyWith(overlayColor: const WidgetStatePropertyAll(Colors.transparent));
  }

  ButtonStyle _detailsIconButtonStyle(ThemeData theme) {
    final colors = theme.colorScheme;
    return IconButton.styleFrom(
      foregroundColor: colors.onSurfaceVariant,
      backgroundColor: Colors.transparent,
      hoverColor: colors.primaryContainer.withValues(alpha: 0.58),
      focusColor: colors.primaryContainer.withValues(alpha: 0.58),
      highlightColor: colors.primaryContainer.withValues(alpha: 0.78),
      shadowColor: Colors.transparent,
      padding: EdgeInsets.zero,
      fixedSize: const Size(38, 38),
    ).copyWith(
      overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.pressed)) {
          return colors.primary.withValues(alpha: 0.18);
        }
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused)) {
          return colors.primaryContainer.withValues(alpha: 0.58);
        }
        return Colors.transparent;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _query.trim().toLowerCase();
    final options = query.isEmpty
        ? widget.options
        : widget.options
              .where(
                (item) =>
                    item.title.toLowerCase().contains(query) ||
                    item.subtitle.toLowerCase().contains(query),
              )
              .toList(growable: false);
    final isTree = widget.options.any((item) => item.groupKey != null);
    return SizedBox(
      width: double.infinity,
      height: 560,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(widget.icon, color: theme.colorScheme.primary),
                kOpenHandHGap9,
                Text(widget.title, style: theme.textTheme.titleLarge),
                const Spacer(),
              ],
            ),
            kOpenHandGap14,
            TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: '搜索资源',
              ),
            ),
            if (widget.selectionHint?.trim().isNotEmpty == true) ...[
              kOpenHandGap8,
              Text(
                widget.selectionHint!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            kOpenHandGap8,
            Row(
              children: [
                Text(
                  '已选 ${_selected.length}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: widget.options.isEmpty
                      ? null
                      : () => setState(
                          () => _selected.addAll(
                            widget.options.map((item) => item.id),
                          ),
                        ),
                  icon: const Icon(Icons.done_all_rounded),
                  label: const Text('全选'),
                ),
                kOpenHandHGap8,
                OutlinedButton.icon(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => setState(() => _selected.clear()),
                  icon: const Icon(Icons.remove_done_rounded),
                  label: const Text('清空'),
                ),
              ],
            ),
            kOpenHandGap14,
            Expanded(
              child: options.isEmpty
                  ? Center(
                      child: Text(
                        widget.options.isEmpty ? '暂无可用资源' : '没有匹配项',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : isTree
                  ? _buildTreeOptions(context, options)
                  : _buildFlatOptions(context, options),
            ),
            kOpenHandGap10,
            OpenHandDialogSaveActions(
              busy: false,
              cancelLabel: '取消',
              confirmLabel: '应用选择',
              onConfirm: () => Navigator.of(context).pop(_selected),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlatOptions(
    BuildContext context,
    List<_DingTalkResourceOption> options,
  ) {
    return ListView.separated(
      itemCount: options.length,
      separatorBuilder: (_, index) => kOpenHandGap4,
      itemBuilder: (context, index) =>
          _buildOptionTile(context, options[index]),
    );
  }

  Widget _buildTreeOptions(
    BuildContext context,
    List<_DingTalkResourceOption> options,
  ) {
    final groups = <String, List<_DingTalkResourceOption>>{};
    for (final option in options) {
      final key = option.groupKey;
      if (key == null || key.isEmpty) continue;
      groups.putIfAbsent(key, () => <_DingTalkResourceOption>[]).add(option);
    }
    final rows =
        <
          ({
            int level,
            String key,
            String title,
            List<_DingTalkResourceOption> children,
            _DingTalkResourceOption? option,
            bool expanded,
          })
        >[];
    final searching = _query.trim().isNotEmpty;
    for (final entry in groups.entries) {
      final first = entry.value.first;
      final groupTitle = first.groupTitle?.trim().isNotEmpty == true
          ? first.groupTitle!.trim()
          : entry.key;
      final groupExpanded = searching || _expandedGroups.contains(entry.key);
      rows.add((
        level: 0,
        key: entry.key,
        title: groupTitle,
        children: entry.value,
        option: null,
        expanded: groupExpanded,
      ));
      if (!groupExpanded) continue;

      final branches = <String, List<_DingTalkResourceOption>>{};
      final directChildren = <_DingTalkResourceOption>[];
      for (final option in entry.value) {
        final segments = option.title
            .trim()
            .split(kInlineWhitespacePattern)
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
        if (segments.length < 3) {
          directChildren.add(option);
        } else {
          branches
              .putIfAbsent(segments[1], () => <_DingTalkResourceOption>[])
              .add(option);
        }
      }
      for (final option in directChildren) {
        rows.add((
          level: 1,
          key: '',
          title: '',
          children: directChildren,
          option: option,
          expanded: false,
        ));
      }
      for (final branch in branches.entries) {
        final branchKey = '${entry.key}/${branch.key}';
        final branchExpanded =
            searching || _expandedBranches.contains(branchKey);
        rows.add((
          level: 1,
          key: branchKey,
          title: branch.key,
          children: branch.value,
          option: null,
          expanded: branchExpanded,
        ));
        if (!branchExpanded) continue;
        rows.addAll(
          branch.value.map(
            (option) => (
              level: 2,
              key: '',
              title: '',
              children: branch.value,
              option: option,
              expanded: false,
            ),
          ),
        );
      }
    }
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, index) => kOpenHandGap4,
      itemBuilder: (context, index) {
        final row = rows[index];
        final option = row.option;
        if (option != null) {
          return Padding(
            padding: EdgeInsets.only(left: row.level * 28),
            child: _buildOptionTile(context, option),
          );
        }
        return Padding(
          padding: EdgeInsets.only(
            left: row.level * 28,
            top: index == 0 ? 0 : 4,
          ),
          child: _buildTreeNodeHeader(
            context,
            nodeKey: row.key,
            title: row.title,
            children: row.children,
            expanded: row.expanded,
            level: row.level,
          ),
        );
      },
    );
  }

  Widget _buildTreeNodeHeader(
    BuildContext context, {
    required String nodeKey,
    required String title,
    required List<_DingTalkResourceOption> children,
    required bool expanded,
    required int level,
  }) {
    final theme = Theme.of(context);
    final selectedCount = children
        .where((option) => _selected.contains(option.id))
        .length;
    final bool? groupSelected = selectedCount == 0
        ? false
        : selectedCount == children.length
        ? true
        : null;
    final searching = _query.trim().isNotEmpty;
    final nodeOption = _DingTalkResourceOption(
      id: nodeKey,
      title: title,
      subtitle: level == 0 ? 'DWS 产品能力分类' : 'DWS 命令域',
      icon: level == 0 ? Icons.folder_copy_rounded : Icons.account_tree_rounded,
      detailDescription: level == 0
          ? '该产品下的钉钉 DWS 拓展能力集合。'
          : '该命令域下的钉钉 DWS 能力集合。',
      detailFields: <String, String>{
        '资源类型': level == 0 ? 'DWS 产品' : 'DWS 命令域',
        '层级': level == 0 ? '产品' : '命令域',
        '能力数量': '${children.length}',
        '已选择': '$selectedCount',
      },
      detailSections: <String, String>{
        '包含能力':
            children.take(60).map((item) => item.title).join('\n') +
            (children.length > 60 ? '\n……另有 ${children.length - 60} 项' : ''),
      },
    );
    void toggleExpanded() {
      setState(() {
        final target = level == 0 ? _expandedGroups : _expandedBranches;
        if (expanded) {
          target.remove(nodeKey);
        } else {
          target.add(nodeKey);
        }
      });
    }

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: kOpenHandBorderRadius14,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Row(
          children: [
            IconButton(
              tooltip: searching
                  ? '搜索结果已自动展开'
                  : expanded
                  ? '收起 $title'
                  : '展开 $title',
              onPressed: searching ? null : toggleExpanded,
              style: _transparentIconButtonStyle(theme),
              icon: AnimatedRotation(
                turns: expanded ? 0.25 : 0,
                duration: kOpenHandMotion180,
                curve: kOpenHandSwitchInCurve,
                child: const Icon(Icons.keyboard_arrow_right_rounded),
              ),
            ),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(kOpenHandRadius10),
                hoverColor: Colors.transparent,
                focusColor: Colors.transparent,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                onTap: searching ? null : toggleExpanded,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      kOpenHandGap2,
                      Text(
                        level == 0
                            ? '${nodeKey.split('/').first} · ${searching ? '匹配' : ''}${children.length} 项能力 · 已选 $selectedCount'
                            : '${searching ? '匹配 ' : ''}${children.length} 项命令 · 已选 $selectedCount',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: '查看详情',
              onPressed: () =>
                  unawaited(_showOptionDetails(context, nodeOption)),
              style: _detailsIconButtonStyle(theme),
              icon: const Icon(Icons.info_outline_rounded),
            ),
            Checkbox(
              value: groupSelected,
              tristate: true,
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              onChanged: (value) => setState(() {
                if (value == true) {
                  _selected.addAll(children.map((item) => item.id));
                } else {
                  _selected.removeAll(children.map((item) => item.id));
                }
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionTile(
    BuildContext context,
    _DingTalkResourceOption option,
  ) {
    final theme = Theme.of(context);
    final isSelected = _selected.contains(option.id);
    void toggleSelected(bool? value) {
      setState(() {
        if (value == true) {
          _selected.add(option.id);
        } else {
          _selected.remove(option.id);
        }
      });
    }

    return Material(
      color: isSelected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
          : theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(kOpenHandRadius13),
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      child: ListTile(
        onTap: () => toggleSelected(!isSelected),
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        splashColor: Colors.transparent,
        selectedTileColor: Colors.transparent,
        leading: Icon(option.icon),
        title: Text(option.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: option.subtitle.trim().isEmpty
            ? null
            : Text(
                option.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kOpenHandRadius13),
        ),
        contentPadding: const EdgeInsets.only(left: 12, right: 8),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '查看详情',
              onPressed: () => unawaited(_showOptionDetails(context, option)),
              style: _detailsIconButtonStyle(theme),
              icon: const Icon(Icons.info_outline_rounded),
            ),
            Checkbox(
              value: isSelected,
              onChanged: toggleSelected,
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            ),
          ],
        ),
      ),
    );
  }
}
