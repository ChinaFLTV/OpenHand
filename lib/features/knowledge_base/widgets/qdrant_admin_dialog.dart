import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/support/silent_log.dart';
import '../../../app/theme/openhand_status_colors.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_form_fields.dart';
import '../../../shared/ui/openhand_reveal_switcher.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/openhand_typography.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/localized_text.dart';
import '../knowledge_base_controller.dart';
import '../knowledge_base_errors.dart';
import 'knowledge_dialog_widgets.dart';

Future<void> showQdrantAdminDialog(BuildContext context) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => const QdrantAdminDialog(),
  );
}

class QdrantAdminDialog extends StatefulWidget {
  const QdrantAdminDialog({super.key});

  @override
  State<QdrantAdminDialog> createState() => _QdrantAdminDialogState();
}

class _QdrantAdminDialogState extends State<QdrantAdminDialog> {
  late Future<List<Map<String, Object?>>> _collectionsFuture;
  Map<String, Object?>? _collectionInfo;
  Map<String, Object?>? _scrollResult;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _collectionsFuture = _loadCollections();
  }

  Future<List<Map<String, Object?>>> _loadCollections() async {
    try {
      return await context
          .read<KnowledgeBaseController>()
          .listQdrantCollections();
    } catch (error, stack) {
      silentLog('qdrant_admin_dialog', '加载 Qdrant 集合', error, stack);
      Error.throwWithStackTrace(error, stack);
    }
  }

  void _refresh() {
    setState(() {
      _error = null;
      _collectionsFuture = _loadCollections();
    });
  }

  Future<void> _loadInfo(String collection) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final info = await context
          .read<KnowledgeBaseController>()
          .loadQdrantCollectionInfo(collection);
      if (mounted) setState(() => _collectionInfo = info);
    } catch (error, stack) {
      silentLog('qdrant_admin_dialog', '读取 Qdrant 集合信息', error, stack);
      if (mounted) {
        setState(
          () => _error = knowledgeBaseFailureMessage(
            error,
            fallback: '读取 Qdrant 集合信息失败，请稍后重试。',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scroll() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await context
          .read<KnowledgeBaseController>()
          .scrollQdrantPoints();
      if (mounted) setState(() => _scrollResult = result);
    } catch (error, stack) {
      silentLog('qdrant_admin_dialog', '滚动读取 Qdrant Points', error, stack);
      if (mounted) {
        setState(
          () => _error = knowledgeBaseFailureMessage(
            error,
            fallback: '滚动读取 Qdrant Points 失败，请稍后重试。',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteCollection(String collection) async {
    final controller = context.read<KnowledgeBaseController>();
    if (!controller.settings.enableDangerousAdminOperations) {
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '请先在知识库配置中启用危险管理操作。',
          zhHant: '請先在知識庫設定中啟用危險管理操作。',
          en: 'Enable dangerous admin operations in Knowledge Base settings first.',
          fr: 'Activez d’abord les opérations admin dangereuses dans les paramètres de la base de connaissances.',
          de: 'Aktivieren Sie zuerst gefährliche Admin-Aktionen in den Wissensdatenbank-Einstellungen.',
          ja: '先にナレッジベース設定で危険な管理操作を有効にしてください。',
        ),
      );
      return;
    }
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '删除 Qdrant collection？',
        zhHant: '刪除 Qdrant collection？',
        en: 'Delete Qdrant collection?',
        fr: 'Supprimer la collection Qdrant ?',
        de: 'Qdrant-Collection löschen?',
        ja: 'Qdrant collection を削除しますか？',
      ),
      message: openHandLocalizedText(
        context,
        zh: '将删除 collection "$collection" 及其中所有 points。此操作不可撤销。',
        zhHant: '將刪除 collection "$collection" 及其中所有 points。此操作無法復原。',
        en: 'This deletes collection "$collection" and all points in it. This cannot be undone.',
        fr: 'Supprime la collection "$collection" et tous ses points. Cette action est irréversible.',
        de: 'Löscht die Collection "$collection" und alle enthaltenen Points. Dies kann nicht rückgängig gemacht werden.',
        ja: 'collection "$collection" とそのすべての points を削除します。この操作は元に戻せません。',
      ),
      confirmLabel: openHandLocalizedText(
        context,
        zh: '删除 Collection',
        zhHant: '刪除 Collection',
        en: 'Delete collection',
        fr: 'Supprimer la collection',
        de: 'Collection löschen',
        ja: 'Collection を削除',
      ),
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await controller.deleteQdrantCollection(collection);
      if (!mounted) return;
      showOpenHandSuccessSnack(
        context,
        openHandLocalizedText(
          context,
          zh: 'Collection 已删除。',
          zhHant: 'Collection 已刪除。',
          en: 'Collection deleted.',
          fr: 'Collection supprimée.',
          de: 'Collection gelöscht.',
          ja: 'Collection を削除しました。',
        ),
      );
      _refresh();
    } catch (error, stack) {
      silentLog('qdrant_admin_dialog', '删除 Qdrant Collection', error, stack);
      if (mounted) {
        setState(
          () => _error = knowledgeBaseFailureMessage(
            error,
            fallback: '删除 Qdrant Collection 失败，请稍后重试。',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<KnowledgeBaseController>();
    final operationBusy = _busy || controller.loading || controller.busy;
    final isChineseLayout = openHandIsChineseLocale(context);
    final colorScheme = Theme.of(context).colorScheme;
    return OpenHandEditorDialogScaffold(
      title: knowledgeQdrantAdminLabel(context),
      subtitle: openHandLocalizedText(
        context,
        zh: '检查集合、滚动读取 points，并在启用危险操作后删除 collection。',
        zhHant: '檢查集合、捲動讀取 points，並在啟用危險操作後刪除 collection。',
        en: 'Inspect collections, scroll points, and delete a collection after enabling dangerous ops.',
        fr: 'Inspectez les collections, lisez les points, et supprimez une collection si les ops dangereuses sont activées.',
        de: 'Collections prüfen, Points scrollen und nach Freigabe gefährlicher Aktionen löschen.',
        ja: 'コレクションを確認し、points を取得し、危険操作を有効にした後に削除できます。',
      ),
      icon: Icons.dns_outlined,
      iconColor: colorScheme.tertiary,
      busy: operationBusy,
      closeEnabled: !_busy,
      canPop: !_busy,
      maxWidth: kOpenHandDialogWidthExtraWide,
      maxHeight: kOpenHandDialogHeightFull,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KnowledgeDialogErrorNotice(message: _error),
          KnowledgeDialogSection(
            title: openHandLocalizedText(
              context,
              zh: 'Collections 列表',
              zhHant: 'Collections 清單',
              en: 'Collections',
              fr: 'Collections',
              de: 'Collections',
              ja: 'Collections',
            ),
            icon: Icons.dataset_outlined,
            accent: colorScheme.tertiary,
            child: FutureBuilder<List<Map<String, Object?>>>(
              future: _collectionsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return KnowledgeDialogLoading(
                    height: 120,
                    message: knowledgeRefreshLabel(context),
                  );
                }
                if (snapshot.hasError) {
                  return KnowledgeDialogNotice(
                    icon: Icons.error_outline_rounded,
                    message: knowledgeBaseFailureMessage(
                      snapshot.error!,
                      fallback: '加载 Qdrant 集合失败，请稍后重试。',
                    ),
                    tone: KnowledgeDialogNoticeTone.error,
                  );
                }
                final collections =
                    snapshot.data ?? const <Map<String, Object?>>[];
                if (collections.isEmpty) {
                  return KnowledgeDialogNotice(
                    icon: Icons.info_outline_rounded,
                    message: openHandLocalizedText(
                      context,
                      zh: '没有 collection 或 Qdrant 不可用。',
                      zhHant: '沒有 collection 或 Qdrant 不可用。',
                      en: 'No collection found or Qdrant unavailable.',
                      fr: 'Aucune collection trouvée ou Qdrant indisponible.',
                      de: 'Keine Collection gefunden oder Qdrant ist nicht verfügbar.',
                      ja: 'collection がないか、Qdrant を利用できません。',
                    ),
                  );
                }
                return Column(
                  children: [
                    for (var i = 0; i < collections.length; i++)
                      KnowledgeCollectionTile(
                        item: collections[i],
                        margin: EdgeInsets.only(
                          bottom: i == collections.length - 1 ? 0 : 8,
                        ),
                        busy: operationBusy,
                        onInfo: () =>
                            _loadInfo('${collections[i]['name'] ?? ''}'),
                        onDelete: () => _deleteCollection(
                          '${collections[i]['name'] ?? ''}',
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          KnowledgeDialogSection(
            title: openHandLocalizedText(
              context,
              zh: 'Points / 搜索 / 滚动读取',
              zhHant: 'Points / 搜尋 / 捲動讀取',
              en: 'Points / Search / Scroll',
              fr: 'Points / Recherche / Scroll',
              de: 'Points / Suche / Scroll',
              ja: 'Points / 検索 / スクロール',
            ),
            icon: Icons.manage_search_rounded,
            accent: OpenHandStatusColors.info,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KnowledgeDialogKeyValueList(
                  rows: {
                    openHandLocalizedText(
                      context,
                      zh: '当前 collection',
                      zhHant: '目前 collection',
                      en: 'Current collection',
                      fr: 'Collection actuelle',
                      de: 'Aktuelle Collection',
                      ja: '現在の collection',
                    ): controller.settings.effectiveCollectionName,
                  },
                  labelWidth: isChineseLayout ? 150 : 170,
                ),
                kOpenHandGap12,
                FilledButton.tonalIcon(
                  onPressed: operationBusy ? null : _scroll,
                  icon: const Icon(Icons.list_alt_rounded),
                  label: Text(
                    openHandLocalizedText(
                      context,
                      zh: '滚动读取前 20 个 points',
                      zhHant: '捲動讀取前 20 個 points',
                      en: 'Scroll first 20 points',
                      fr: 'Lire les 20 premiers points',
                      de: 'Erste 20 Points scrollen',
                      ja: '先頭 20 points をスクロール取得',
                    ),
                  ),
                ),
                OpenHandVerticalRevealSwitcher(
                  presentKey: const ValueKey<String>('scroll-result'),
                  slideBeginOffsetY: 0.04,
                  child: _scrollResult == null
                      ? null
                      : Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: KnowledgeDialogJsonBox(value: _scrollResult),
                        ),
                ),
              ],
            ),
          ),
          OpenHandVerticalRevealSwitcher(
            presentKey: const ValueKey<String>('collection-info'),
            slideBeginOffsetY: 0.04,
            child: _collectionInfo == null
                ? null
                : KnowledgeDialogSection(
                    title: openHandLocalizedText(
                      context,
                      zh: 'Collection 结构 / 配置',
                      zhHant: 'Collection 結構 / 設定',
                      en: 'Collection schema / config',
                      fr: 'Schéma / configuration de collection',
                      de: 'Collection-Schema / Konfiguration',
                      ja: 'Collection スキーマ / 設定',
                    ),
                    icon: Icons.schema_outlined,
                    accent: colorScheme.secondary,
                    child: KnowledgeDialogJsonBox(value: _collectionInfo),
                  ),
          ),
          KnowledgeDialogSection(
            title: openHandLocalizedText(
              context,
              zh: '操作日志',
              zhHant: '操作日誌',
              en: 'Operation Log',
              fr: 'Journal des opérations',
              de: 'Aktionsprotokoll',
              ja: '操作ログ',
            ),
            icon: Icons.receipt_long_outlined,
            accent: colorScheme.primary,
            margin: EdgeInsets.zero,
            child: controller.qdrantAdminLogs.isEmpty
                ? KnowledgeDialogNotice(
                    icon: Icons.history_toggle_off_rounded,
                    message: openHandLocalizedText(
                      context,
                      zh: '暂无操作。',
                      zhHant: '暫無操作。',
                      en: 'No operations yet.',
                      fr: 'Aucune opération pour le moment.',
                      de: 'Noch keine Aktionen.',
                      ja: '操作はまだありません。',
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final log in controller.qdrantAdminLogs)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '${formatYearMonthDayHmsLocal(log.createdAt)} · ${log.action} · ${log.detail}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontFamily: kOpenHandMonospaceFontFamily,
                                  height: 1.4,
                                ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: _busy ? null : _refresh,
          icon: Icons.refresh_rounded,
          label: knowledgeRefreshLabel(context),
        ),
        OpenHandDialogActionButton.primary(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          label: openHandCloseLabel(context),
        ),
      ],
    );
  }
}
