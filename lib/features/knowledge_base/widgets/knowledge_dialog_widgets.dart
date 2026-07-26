import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../app/theme/openhand_status_colors.dart';
import '../../../shared/ui/openhand_inline_notice.dart';
import '../../../shared/ui/openhand_reveal_switcher.dart';
import '../../../shared/ui/openhand_typography.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/localized_text.dart';

IconData knowledgeSourceKindIcon(String kind) {
  return switch (kind.trim().toLowerCase()) {
    'markdown' => Icons.notes_rounded,
    'code' => Icons.code_rounded,
    'pdf' => Icons.picture_as_pdf_outlined,
    'html' => Icons.language_rounded,
    'docx' => Icons.article_outlined,
    'spreadsheet' => Icons.table_chart_outlined,
    'presentation' => Icons.slideshow_outlined,
    'table' => Icons.dataset_outlined,
    'structured' => Icons.data_object_rounded,
    _ => Icons.description_outlined,
  };
}

/// 导入入口共用的三条文案。
///
/// 知识库视图与导入弹窗此前各自内联了同一份六语言字面量，改一处措辞就得
/// 同步改另一处。
String knowledgeEmbeddingModelMissingMessage(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '请先配置可用的嵌入模型。',
    zhHant: '請先設定可用的嵌入模型。',
    en: 'Configure an embedding model first.',
    fr: 'Configurez d’abord un modèle d’embedding.',
    de: 'Konfigurieren Sie zuerst ein Embedding-Modell.',
    ja: '先に利用可能な埋め込みモデルを設定してください。',
  );
}

String knowledgeIndexingProgressTitle(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '构建知识库向量',
    zhHant: '建立知識庫向量',
    en: 'Building Knowledge Vectors',
    fr: 'Construction des vecteurs',
    de: 'Wissensvektoren werden erstellt',
    ja: 'ナレッジベースベクトルを構築',
  );
}

String knowledgeIndexingStoppedMessage(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '已停止构建向量。',
    zhHant: '已停止建立向量。',
    en: 'Vector indexing stopped.',
    fr: 'Indexation vectorielle arrêtée.',
    de: 'Vektorindexierung gestoppt.',
    ja: 'ベクトルのインデックス作成を停止しました。',
  );
}

String localizedKnowledgeSourceKind(BuildContext context, String kind) {
  final normalized = kind.trim().toLowerCase();
  return switch (normalized) {
    'markdown' => openHandLocalizedText(
      context,
      zh: 'Markdown 文档',
      zhHant: 'Markdown 文件',
      en: 'Markdown',
      fr: 'Markdown',
      de: 'Markdown',
      ja: 'Markdown',
    ),
    'text' => openHandLocalizedText(
      context,
      zh: '文本',
      zhHant: '文字',
      en: 'Text',
      fr: 'Texte',
      de: 'Text',
      ja: 'テキスト',
    ),
    'code' => openHandLocalizedText(
      context,
      zh: '代码',
      zhHant: '程式碼',
      en: 'Code',
      fr: 'Code',
      de: 'Code',
      ja: 'コード',
    ),
    'pdf' => 'PDF',
    'html' => openHandLocalizedText(
      context,
      zh: '网页 HTML',
      zhHant: '網頁 HTML',
      en: 'HTML',
      fr: 'HTML',
      de: 'HTML',
      ja: 'HTML',
    ),
    'docx' => openHandLocalizedText(
      context,
      zh: 'Word 文档',
      zhHant: 'Word 文件',
      en: 'Word document',
      fr: 'Document Word',
      de: 'Word-Dokument',
      ja: 'Word ドキュメント',
    ),
    'spreadsheet' => openHandLocalizedText(
      context,
      zh: '电子表格',
      zhHant: '試算表',
      en: 'Spreadsheet',
      fr: 'Feuille de calcul',
      de: 'Tabelle',
      ja: 'スプレッドシート',
    ),
    'presentation' => openHandLocalizedText(
      context,
      zh: '演示文稿',
      zhHant: '簡報',
      en: 'Presentation',
      fr: 'Présentation',
      de: 'Präsentation',
      ja: 'プレゼンテーション',
    ),
    'table' => openHandLocalizedText(
      context,
      zh: '表格数据',
      zhHant: '表格資料',
      en: 'Table data',
      fr: 'Données tabulaires',
      de: 'Tabellendaten',
      ja: '表データ',
    ),
    'structured' => openHandLocalizedText(
      context,
      zh: '结构化数据',
      zhHant: '結構化資料',
      en: 'Structured data',
      fr: 'Données structurées',
      de: 'Strukturierte Daten',
      ja: '構造化データ',
    ),
    'note' => openHandLocalizedText(
      context,
      zh: '笔记',
      zhHant: '筆記',
      en: 'Note',
      fr: 'Note',
      de: 'Notiz',
      ja: 'ノート',
    ),
    _ => normalized.isEmpty ? '-' : kind.trim(),
  };
}

String localizedKnowledgeSourceStatus(BuildContext context, String status) {
  final normalized = status.trim().toLowerCase();
  return switch (normalized) {
    'indexed' => openHandLocalizedText(
      context,
      zh: '已索引',
      zhHant: '已索引',
      en: 'Indexed',
      fr: 'Indexé',
      de: 'Indexiert',
      ja: 'インデックス済み',
    ),
    'failed' => openHandLocalizedText(
      context,
      zh: '失败',
      zhHant: '失敗',
      en: 'Failed',
      fr: 'Échec',
      de: 'Fehlgeschlagen',
      ja: '失敗',
    ),
    'indexing' => openHandLocalizedText(
      context,
      zh: '索引中',
      zhHant: '索引中',
      en: 'Indexing',
      fr: 'Indexation',
      de: 'Indexierung',
      ja: 'インデックス中',
    ),
    'pending' => openHandLocalizedText(
      context,
      zh: '待处理',
      zhHant: '待處理',
      en: 'Pending',
      fr: 'En attente',
      de: 'Ausstehend',
      ja: '保留中',
    ),
    'cancelled' => openHandLocalizedText(
      context,
      zh: '已停止',
      zhHant: '已停止',
      en: 'Stopped',
      fr: 'Arrêté',
      de: 'Gestoppt',
      ja: '停止済み',
    ),
    _ => normalized.isEmpty ? '-' : status.trim(),
  };
}

/// 知识库弹窗顶部的错误提示：出现与消失走全局动效的纵向展开。
///
/// Qdrant 管理与状态两个弹窗此前各写了一份 `if (_error != null) Padding(...)`，
/// 报错出现时下方内容会被硬生生顶下去一次。
class KnowledgeDialogErrorNotice extends StatelessWidget {
  const KnowledgeDialogErrorNotice({
    super.key,
    required this.message,
    this.bottomSpacing = 12,
  });

  /// 为 null 表示无错误，此时收起为零高度。
  final String? message;

  final double bottomSpacing;

  @override
  Widget build(BuildContext context) {
    final text = message;
    return OpenHandVerticalRevealSwitcher(
      duration: kOpenHandInlineErrorRevealDuration,
      presentKey: ValueKey<String>(text ?? ''),
      child: text == null
          ? null
          : Padding(
              padding: EdgeInsets.only(bottom: bottomSpacing),
              child: KnowledgeDialogNotice(
                icon: Icons.error_outline_rounded,
                error: true,
                message: text,
              ),
            ),
    );
  }
}

class KnowledgeDialogSection extends StatelessWidget {
  const KnowledgeDialogSection({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.subtitle,
    this.margin = const EdgeInsets.only(bottom: 12),
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      margin: margin,
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.84),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.78,
                  ),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 17, color: colorScheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!.trim(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.28,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class KnowledgeDialogKeyValueList extends StatelessWidget {
  const KnowledgeDialogKeyValueList({
    super.key,
    required this.rows,
    this.labelWidth = 156,
  });

  final Map<String, Object?> rows;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final entries = rows.entries.toList(growable: false);
    if (entries.isEmpty) {
      return Text(
        '-',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Column(
      children: [
        for (var index = 0; index < entries.length; index++)
          Container(
            padding: EdgeInsets.only(
              top: index == 0 ? 0 : 7,
              bottom: index == entries.length - 1 ? 0 : 7,
            ),
            decoration: BoxDecoration(
              border: index == entries.length - 1
                  ? null
                  : Border(
                      bottom: BorderSide(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.52,
                        ),
                      ),
                    ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: labelWidth,
                  child: Text(
                    entries[index].key,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      height: 1.28,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SelectableText(
                    knowledgeDialogValue(entries[index].value),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class KnowledgeDialogJsonBox extends StatelessWidget {
  const KnowledgeDialogJsonBox({
    super.key,
    required this.value,
    this.maxHeight,
  });

  final Object? value;
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final text = prettyPrintJson(value);
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight ?? 320),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.64),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.56),
        ),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: kOpenHandMonospaceFontFamily,
            height: 1.38,
          ),
        ),
      ),
    );
  }
}

enum KnowledgeDialogNoticeTone { neutral, warning, error }

class KnowledgeDialogNotice extends StatelessWidget {
  const KnowledgeDialogNotice({
    super.key,
    required this.icon,
    required this.message,
    this.error = false,
    this.tone,
    this.trailing,
  });

  final IconData icon;
  final String message;
  final bool error;
  final KnowledgeDialogNoticeTone? tone;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = _KnowledgeDialogNoticeColors.resolve(
      context,
      tone ??
          (error
              ? KnowledgeDialogNoticeTone.error
              : KnowledgeDialogNoticeTone.neutral),
    );
    final content = Row(
      children: [
        Icon(icon, size: 19, color: colors.icon),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.foreground,
              height: 1.32,
              fontWeight: colors.fontWeight,
            ),
          ),
        ),
      ],
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final action = trailing;
          if (action == null) return content;
          final compact =
              constraints.hasBoundedWidth && constraints.maxWidth < 520;
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                content,
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerRight, child: action),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: content),
              const SizedBox(width: 10),
              Align(alignment: Alignment.centerRight, child: action),
            ],
          );
        },
      ),
    );
  }
}

class KnowledgeDialogNoticeAction extends StatelessWidget {
  const KnowledgeDialogNoticeAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tone = KnowledgeDialogNoticeTone.neutral,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final KnowledgeDialogNoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = _KnowledgeDialogNoticeColors.resolve(context, tone);
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 17, color: colors.icon),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.foreground,
        backgroundColor: colors.actionBackground,
        side: BorderSide(color: colors.actionBorder),
        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
          height: 1.1,
        ),
      ),
    );
  }
}

class _KnowledgeDialogNoticeColors {
  const _KnowledgeDialogNoticeColors({
    required this.background,
    required this.border,
    required this.foreground,
    required this.icon,
    required this.actionBackground,
    required this.actionBorder,
    this.fontWeight,
  });

  final Color background;
  final Color border;
  final Color foreground;
  final Color icon;
  final Color actionBackground;
  final Color actionBorder;
  final FontWeight? fontWeight;

  static _KnowledgeDialogNoticeColors resolve(
    BuildContext context,
    KnowledgeDialogNoticeTone tone,
  ) {
    final scheme = Theme.of(context).colorScheme;
    if (tone == KnowledgeDialogNoticeTone.neutral) {
      return _KnowledgeDialogNoticeColors(
        background: scheme.surfaceContainerHighest.withValues(alpha: 0.56),
        border: scheme.outlineVariant.withValues(alpha: 0.62),
        foreground: scheme.onSurfaceVariant,
        icon: scheme.onSurfaceVariant,
        actionBackground: scheme.surfaceContainerHighest,
        actionBorder: scheme.outlineVariant,
      );
    }
    final surface = scheme.surfaceContainerHigh;
    final foreground = scheme.onSurface;
    final accent = switch (tone) {
      KnowledgeDialogNoticeTone.neutral => scheme.onSurfaceVariant,
      KnowledgeDialogNoticeTone.warning => OpenHandStatusColors.warning,
      KnowledgeDialogNoticeTone.error => OpenHandStatusColors.error,
    };
    final tintAlpha = switch (tone) {
      KnowledgeDialogNoticeTone.neutral => 0.10,
      KnowledgeDialogNoticeTone.warning => 0.10,
      KnowledgeDialogNoticeTone.error => 0.10,
    };
    final borderAlpha = switch (tone) {
      KnowledgeDialogNoticeTone.neutral => 0.30,
      KnowledgeDialogNoticeTone.warning => 0.34,
      KnowledgeDialogNoticeTone.error => 0.30,
    };
    return _KnowledgeDialogNoticeColors(
      background: Color.alphaBlend(
        accent.withValues(alpha: tintAlpha),
        surface.withValues(alpha: 0.92),
      ),
      border: accent.withValues(alpha: borderAlpha),
      foreground: foreground,
      icon: accent,
      fontWeight: FontWeight.w600,
      actionBackground: Color.alphaBlend(
        accent.withValues(alpha: 0.10),
        scheme.surfaceContainerHighest,
      ),
      actionBorder: accent.withValues(alpha: 0.28),
    );
  }
}

class KnowledgeDialogTextBox extends StatelessWidget {
  const KnowledgeDialogTextBox({
    super.key,
    required this.text,
    this.maxHeight = 280,
    this.emptyText = '-',
  });

  final String text;
  final double maxHeight;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final value = text.trim().isEmpty ? emptyText : text;
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.54),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.56),
        ),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: kOpenHandMonospaceFontFamily,
            height: 1.38,
            color: colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class KnowledgeDialogChip extends StatelessWidget {
  const KnowledgeDialogChip({
    super.key,
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colorScheme.onPrimaryContainer),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

InputDecoration knowledgeDialogInputDecoration(
  BuildContext context,
  String label, {
  bool alignLabelWithHint = false,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  return InputDecoration(
    labelText: label,
    alignLabelWithHint: alignLabelWithHint,
    isDense: true,
    filled: true,
    fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.46),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: colorScheme.outlineVariant.withValues(alpha: 0.84),
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
    ),
  );
}

/// 明细弹窗键值列表的标签列宽。
///
/// 中文标签更短，其余语言需要更宽的列才不会折行；集中一处，避免各弹窗抄写
/// 同一组魔法数字 后逐渐对不齐。
double knowledgeDetailLabelWidth(bool isChinese) => isChinese ? 112 : 132;

String knowledgeDialogValue(Object? value) {
  if (value == null) return '-';
  if (value is Map || value is List) return jsonEncode(value);
  final text = '$value'.trim();
  return text.isEmpty ? '-' : text;
}

/// Qdrant collection 行卡：管理弹窗与状态弹窗共用。
///
/// 两处此前各维护一份同名 `_CollectionTile`，一份用内联多语言文本、一份用
/// 生成的 l10n，样式也悄悄分叉；此处统一为唯一实现。
class KnowledgeCollectionTile extends StatelessWidget {
  const KnowledgeCollectionTile({
    super.key,
    required this.item,
    required this.busy,
    required this.onInfo,
    required this.onDelete,
    this.margin,
  });

  final Map<String, Object?> item;
  final bool busy;
  final VoidCallback onInfo;
  final VoidCallback onDelete;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final name = '${item['name'] ?? ''}';
    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.dataset_outlined, size: 20, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  name.isEmpty ? '-' : name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  jsonEncode(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontFamily: kOpenHandMonospaceFontFamily,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: openHandLocalizedText(
              context,
              zh: '查看配置',
              zhHant: '查看設定',
              en: 'View config',
              fr: 'Voir la configuration',
              de: 'Konfiguration anzeigen',
              ja: '設定を表示',
            ),
            onPressed: busy ? null : onInfo,
            icon: const Icon(Icons.info_outline_rounded),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: openHandDeleteLabel(context),
            onPressed: busy ? null : onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }
}
