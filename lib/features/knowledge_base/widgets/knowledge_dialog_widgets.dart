import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../app/theme/openhand_status_colors.dart';
import '../../../shared/ui/micro_press_feedback.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/oh_pill.dart';
import '../../../shared/ui/openhand_json_tree.dart';
import '../../../shared/ui/openhand_reveal_switcher.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/openhand_typography.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/localized_text.dart';

// 知识库对话框统一圆角档位。

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

Color knowledgeSourceKindAccent(String kind, ColorScheme colorScheme) {
  return switch (kind.trim().toLowerCase()) {
    'markdown' || 'note' => OpenHandStatusColors.success,
    'code' => colorScheme.tertiary,
    'pdf' => OpenHandStatusColors.error,
    'html' => OpenHandStatusColors.info,
    'docx' => colorScheme.primary,
    'spreadsheet' || 'table' => OpenHandStatusColors.caution,
    'presentation' => OpenHandStatusColors.warning,
    'structured' => colorScheme.secondary,
    _ => colorScheme.primary,
  };
}

/// 导入入口共用文案。
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
    'text' => openHandTextLabel(context),
    'code' => knowledgeCodeLabel(context),
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
    'failed' => knowledgeFailedLabel(context),
    'indexing' => openHandLocalizedText(
      context,
      zh: '索引中',
      zhHant: '索引中',
      en: 'Indexing',
      fr: 'Indexation',
      de: 'Indexierung',
      ja: 'インデックス中',
    ),
    'pending' => knowledgePendingLabel(context),
    'cancelled' => knowledgeStoppedLabel(context),
    _ => normalized.isEmpty ? '-' : status.trim(),
  };
}

/// 知识库文档预览共用的 Markdown 样式。
MarkdownStyleSheet knowledgeMarkdownStyleSheet(BuildContext context) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  return MarkdownStyleSheet.fromTheme(theme).copyWith(
    p: theme.textTheme.bodyMedium?.copyWith(
      height: _kKnowledgeMarkdownLineHeight,
    ),
    code: theme.textTheme.bodyMedium?.copyWith(
      fontFamily: kOpenHandMonospaceFontFamily,
      color: colorScheme.onSurface,
    ),
    codeblockDecoration: BoxDecoration(
      color: colorScheme.surfaceContainerHigh,
      borderRadius: _kKnowledgeMarkdownBlockRadius,
    ),
    blockquoteDecoration: BoxDecoration(
      color: colorScheme.surfaceContainerHigh,
      borderRadius: _kKnowledgeMarkdownBlockRadius,
      border: Border(
        left: BorderSide(
          color: colorScheme.primary,
          width: _kKnowledgeBlockquoteBarWidth,
        ),
      ),
    ),
  );
}

const double _kKnowledgeMarkdownLineHeight = 1.42;
const double _kKnowledgeBlockquoteBarWidth = 3;
const BorderRadius _kKnowledgeMarkdownBlockRadius = BorderRadius.all(
  Radius.circular(kOpenHandRadius10),
);
const double kKnowledgeDialogMetricMinWidth = 168;
const double kKnowledgeDialogMetricGridGap = 10;
const double kKnowledgeDialogActionChipHeight = 36;
const double kKnowledgeDialogJsonDefaultMaxHeight = 320;
const Duration kKnowledgeDialogTabSwitchDuration = kOpenHandMotion280;

Color knowledgeDialogHealthColor(BuildContext context, String status) {
  final colorScheme = Theme.of(context).colorScheme;
  return switch (status.trim().toLowerCase()) {
    'healthy' || 'green' || 'ok' || 'ready' => OpenHandStatusColors.success,
    'loading' || 'yellow' || 'pending' => OpenHandStatusColors.warning,
    'unhealthy' || 'red' || 'error' || 'failed' => colorScheme.error,
    _ => colorScheme.tertiary,
  };
}

/// 知识库弹窗顶部的错误提示，出现与消失沿用全局动效。
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
      duration: kOpenHandMotion180,
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
    this.child,
    this.subtitle,
    this.accent,
    this.trailing,
    this.margin = const EdgeInsets.only(bottom: 12),
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget? child;
  final Color? accent;
  final Widget? trailing;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tone = accent ?? colorScheme.primary;
    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            tone.withValues(alpha: 0.07),
            colorScheme.surfaceContainerLow,
          ),
          borderRadius: kOpenHandBorderRadius20,
          border: Border.all(color: tone.withValues(alpha: 0.18)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: tone.withValues(alpha: 0.16),
                      borderRadius: kOpenHandBorderRadius12,
                    ),
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: Center(child: Icon(icon, size: 18, color: tone)),
                    ),
                  ),
                  kOpenHandHGap10,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (subtitle != null &&
                            subtitle!.trim().isNotEmpty) ...[
                          kOpenHandGap2,
                          Text(
                            subtitle!.trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[kOpenHandHGap8, trailing!],
                ],
              ),
              if (child != null) ...[kOpenHandGap14, child!],
            ],
          ),
        ),
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
                kOpenHandHGap12,
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
    this.label,
  });

  final Object? value;
  final double? maxHeight;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return OpenHandJsonTreeView(
      text: prettyPrintJson(value),
      label: label,
      logTag: 'knowledge_base',
      bodyMaxHeight: maxHeight ?? kKnowledgeDialogJsonDefaultMaxHeight,
    );
  }
}

class KnowledgeDialogLoading extends StatelessWidget {
  const KnowledgeDialogLoading({super.key, this.message, this.height = 180});

  final String? message;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final text = message?.trim() ?? '';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          colorScheme.primary.withValues(alpha: 0.07),
          colorScheme.surfaceContainerLow,
        ),
        borderRadius: kOpenHandBorderRadius16,
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.16)),
      ),
      child: SizedBox(
        height: height,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.8,
                  color: colorScheme.primary,
                ),
              ),
              if (text.isNotEmpty) ...[
                kOpenHandGap14,
                Text(
                  text,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
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
        kOpenHandHGap10,
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
        borderRadius: BorderRadius.circular(kOpenHandRadius12),
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
                kOpenHandGap10,
                Align(alignment: Alignment.centerRight, child: action),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: content),
              kOpenHandHGap10,
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
        borderRadius: BorderRadius.circular(kOpenHandRadius12),
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
        borderRadius: kOpenHandPillBorderRadius,
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colorScheme.onPrimaryContainer),
          kOpenHandHGap5,
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

class KnowledgeDialogMetric {
  const KnowledgeDialogMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;
}

class KnowledgeDialogMetricGrid extends StatelessWidget {
  const KnowledgeDialogMetricGrid({super.key, required this.items});

  final List<KnowledgeDialogMetric> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : kKnowledgeDialogMetricMinWidth;
        final columns = maxWidth >= 720
            ? 3
            : maxWidth >= 480
            ? 2
            : 1;
        final itemWidth = columns <= 1
            ? maxWidth
            : (maxWidth - kKnowledgeDialogMetricGridGap * (columns - 1)) /
                  columns;
        return Wrap(
          spacing: kKnowledgeDialogMetricGridGap,
          runSpacing: kKnowledgeDialogMetricGridGap,
          children: [
            for (final item in items)
              SizedBox(
                width: itemWidth,
                child: _KnowledgeDialogMetricCard(item: item),
              ),
          ],
        );
      },
    );
  }
}

class _KnowledgeDialogMetricCard extends StatelessWidget {
  const _KnowledgeDialogMetricCard({required this.item});

  final KnowledgeDialogMetric item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final value = item.value.trim().isEmpty ? '-' : item.value.trim();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          item.accent.withValues(alpha: 0.12),
          colorScheme.surfaceContainerLow,
        ),
        borderRadius: kOpenHandBorderRadius16,
        border: Border.all(color: item.accent.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: item.accent.withValues(alpha: 0.18),
                borderRadius: kOpenHandBorderRadius10,
              ),
              child: SizedBox(
                width: 34,
                height: 34,
                child: Center(
                  child: Icon(item.icon, size: 18, color: item.accent),
                ),
              ),
            ),
            kOpenHandHGap10,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  kOpenHandGap2,
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: item.accent,
                      fontWeight: FontWeight.w900,
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

enum KnowledgeDialogActionTone { accent, destructive }

class KnowledgeDialogActionChip extends StatelessWidget {
  const KnowledgeDialogActionChip({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.accent,
    this.tone = KnowledgeDialogActionTone.accent,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? accent;
  final KnowledgeDialogActionTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = tone == KnowledgeDialogActionTone.destructive
        ? colorScheme.error
        : (accent ?? colorScheme.primary);
    final enabled = onPressed != null;
    return MicroPressFeedback(
      enabled: enabled,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: kOpenHandPillBorderRadius,
          child: AnimatedOpacity(
            duration: openHandMotionDuration(context, kOpenHandMotion180),
            opacity: enabled ? 1 : 0.48,
            child: AnimatedContainer(
              duration: openHandMotionDuration(context, kOpenHandMotion180),
              curve: kOpenHandSwitchInCurve,
              height: kKnowledgeDialogActionChipHeight,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  color.withValues(alpha: 0.14),
                  colorScheme.surfaceContainerLow,
                ),
                borderRadius: kOpenHandPillBorderRadius,
                border: Border.all(color: color.withValues(alpha: 0.28)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: color),
                  kOpenHandHGap8,
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
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

class KnowledgeDialogTabItem {
  const KnowledgeDialogTabItem({
    required this.icon,
    required this.label,
    required this.child,
    this.accent,
  });

  final IconData icon;
  final String label;
  final Widget child;
  final Color? accent;
}

class KnowledgeDialogTabScaffold extends StatelessWidget {
  const KnowledgeDialogTabScaffold({
    super.key,
    required this.index,
    required this.onChanged,
    required this.tabs,
  });

  final int index;
  final ValueChanged<int> onChanged;
  final List<KnowledgeDialogTabItem> tabs;

  @override
  Widget build(BuildContext context) {
    if (tabs.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final safeIndex = index.clamp(0, tabs.length - 1);
    final viewport = SizedBox.expand(
      key: ValueKey<int>(safeIndex),
      child: tabs[safeIndex].child,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              colorScheme.primary.withValues(alpha: 0.06),
              colorScheme.surfaceContainerLow,
            ),
            borderRadius: kOpenHandBorderRadius16,
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.42),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    _KnowledgeDialogTabChip(
                      selected: i == safeIndex,
                      icon: tabs[i].icon,
                      label: tabs[i].label,
                      accent: tabs[i].accent ?? colorScheme.primary,
                      onPressed: i == safeIndex ? null : () => onChanged(i),
                    ),
                ],
              ),
            ),
          ),
        ),
        kOpenHandGap12,
        Expanded(
          child: openHandTickerMotionEnabled(context)
              ? AnimatedSwitcher(
                  duration: openHandMotionDuration(
                    context,
                    kKnowledgeDialogTabSwitchDuration,
                  ),
                  switchInCurve: kOpenHandEntranceCurve,
                  switchOutCurve: kOpenHandSwitchOutCurve,
                  layoutBuilder: (currentChild, previousChildren) {
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        ...previousChildren,
                        if (currentChild != null) currentChild,
                      ],
                    );
                  },
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position:
                            Tween<Offset>(
                              begin: const Offset(0.03, 0.05),
                              end: Offset.zero,
                            ).animate(
                              CurvedAnimation(
                                parent: animation,
                                curve: kOpenHandEntranceCurve,
                              ),
                            ),
                        child: child,
                      ),
                    );
                  },
                  child: viewport,
                )
              : viewport,
        ),
      ],
    );
  }
}

class _KnowledgeDialogTabChip extends StatelessWidget {
  const _KnowledgeDialogTabChip({
    required this.selected,
    required this.icon,
    required this.label,
    required this.accent,
    required this.onPressed,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final foreground = selected ? accent : colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: MicroPressFeedback(
        enabled: onPressed != null,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: kOpenHandPillBorderRadius,
            child: AnimatedContainer(
              duration: openHandMotionDuration(context, kOpenHandMotion180),
              curve: kOpenHandEntranceCurve,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: selected
                    ? Color.alphaBlend(
                        accent.withValues(alpha: 0.18),
                        colorScheme.surface,
                      )
                    : Colors.transparent,
                borderRadius: kOpenHandPillBorderRadius,
                border: Border.all(
                  color: selected
                      ? accent.withValues(alpha: 0.36)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: foreground),
                  kOpenHandHGap8,
                  Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: foreground,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
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

class KnowledgeDialogLogList extends StatelessWidget {
  const KnowledgeDialogLogList({
    super.key,
    required this.logs,
    required this.emptyMessage,
  });

  final List<({DateTime createdAt, String action, String detail})> logs;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return KnowledgeDialogNotice(
        icon: Icons.history_toggle_off_rounded,
        message: emptyMessage,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < logs.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == logs.length - 1 ? 0 : 8),
            child: _KnowledgeDialogLogTile(log: logs[i]),
          ),
      ],
    );
  }
}

class _KnowledgeDialogLogTile extends StatelessWidget {
  const _KnowledgeDialogLogTile({required this.log});

  final ({DateTime createdAt, String action, String detail}) log;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = _accentFor(colorScheme, log.action);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          accent.withValues(alpha: 0.10),
          colorScheme.surfaceContainerLow,
        ),
        borderRadius: kOpenHandBorderRadius12,
        border: Border.all(color: accent.withValues(alpha: 0.20)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_iconFor(log.action), size: 16, color: accent),
            kOpenHandHGap10,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          log.action,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      kOpenHandHGap8,
                      Text(
                        formatYearMonthDayHmsLocal(log.createdAt),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  if (log.detail.trim().isNotEmpty) ...[
                    kOpenHandGap4,
                    Text(
                      log.detail.trim(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(String action) {
    final normalized = action.toLowerCase();
    if (normalized.contains('delete') || normalized.contains('删除')) {
      return Icons.delete_outline_rounded;
    }
    if (normalized.contains('create') ||
        normalized.contains('rebuild') ||
        normalized.contains('重建')) {
      return Icons.build_circle_outlined;
    }
    if (normalized.contains('search') ||
        normalized.contains('scroll') ||
        normalized.contains('查询') ||
        normalized.contains('滚动')) {
      return Icons.manage_search_rounded;
    }
    return Icons.receipt_long_outlined;
  }

  Color _accentFor(ColorScheme colorScheme, String action) {
    final normalized = action.toLowerCase();
    if (normalized.contains('delete') || normalized.contains('删除')) {
      return colorScheme.error;
    }
    if (normalized.contains('create') ||
        normalized.contains('rebuild') ||
        normalized.contains('重建')) {
      return OpenHandStatusColors.success;
    }
    if (normalized.contains('search') ||
        normalized.contains('scroll') ||
        normalized.contains('查询') ||
        normalized.contains('滚动')) {
      return OpenHandStatusColors.info;
    }
    return colorScheme.primary;
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
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(kOpenHandRadius12),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(kOpenHandRadius12),
      borderSide: BorderSide(
        color: colorScheme.outlineVariant.withValues(alpha: 0.84),
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(kOpenHandRadius12),
      borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
    ),
  );
}

/// 明细弹窗键值列表按语言适配的标签列宽。
double knowledgeDetailLabelWidth(bool isChinese) => isChinese ? 112 : 132;

String knowledgeDialogValue(Object? value) {
  if (value == null) return '-';
  if (value is Map || value is List) return jsonEncode(value);
  final text = '$value'.trim();
  return text.isEmpty ? '-' : text;
}

/// Qdrant collection 管理与状态弹窗共用行卡。
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
    final name = '${item['name'] ?? ''}'.trim();
    final status = '${item['status'] ?? ''}'.trim();
    final points = '${item['points_count'] ?? item['points'] ?? ''}'.trim();
    final vectors =
        '${item['indexed_vectors_count'] ?? item['vectors_count'] ?? ''}'
            .trim();
    final accent = status.isEmpty
        ? colorScheme.tertiary
        : knowledgeDialogHealthColor(context, status);
    final pills = <Widget>[
      if (status.isNotEmpty)
        OpenHandFactChip(icon: Icons.circle, label: status, color: accent)
      else
        OpenHandFactChip(
          icon: Icons.dataset_outlined,
          label: openHandLocalizedText(
            context,
            zh: 'Qdrant collection',
            zhHant: 'Qdrant collection',
            en: 'Qdrant collection',
            fr: 'Collection Qdrant',
            de: 'Qdrant-Collection',
            ja: 'Qdrant collection',
          ),
          color: accent,
        ),
      if (points.isNotEmpty)
        OpenHandFactChip(
          icon: Icons.scatter_plot_outlined,
          label: points,
          color: OpenHandStatusColors.info,
        ),
      if (vectors.isNotEmpty)
        OpenHandFactChip(
          icon: Icons.polyline_outlined,
          label: vectors,
          color: colorScheme.secondary,
        ),
    ];
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            accent.withValues(alpha: 0.10),
            colorScheme.surfaceContainerLow,
          ),
          borderRadius: kOpenHandBorderRadius16,
          border: Border.all(color: accent.withValues(alpha: 0.22)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: kOpenHandBorderRadius12,
                ),
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: Center(
                    child: Icon(
                      Icons.dataset_outlined,
                      size: 18,
                      color: accent,
                    ),
                  ),
                ),
              ),
              kOpenHandHGap10,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? '-' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    kOpenHandGap6,
                    Wrap(spacing: 6, runSpacing: 6, children: pills),
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
                onPressed: busy || name.isEmpty ? null : onInfo,
                icon: const Icon(Icons.info_outline_rounded),
              ),
              IconButton(
                tooltip: openHandDeleteLabel(context),
                onPressed: busy || name.isEmpty ? null : onDelete,
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: colorScheme.error,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 知识库弹窗共用文案。

String knowledgeQdrantAdminLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: 'Qdrant 管理',
    zhHant: 'Qdrant 管理',
    en: 'Qdrant Admin',
    fr: 'Admin Qdrant',
    de: 'Qdrant-Admin',
    ja: 'Qdrant 管理',
  );
}

String knowledgeCodeLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '代码',
    zhHant: '程式碼',
    en: 'Code',
    fr: 'Code',
    de: 'Code',
    ja: 'コード',
  );
}

String knowledgeContentHashLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '内容哈希',
    zhHant: '內容雜湊',
    en: 'Content hash',
    fr: 'Hash du contenu',
    de: 'Inhalts-Hash',
    ja: 'コンテンツハッシュ',
  );
}

String knowledgeChunkIdLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '分块 ID',
    zhHant: '分塊 ID',
    en: 'Chunk ID',
    fr: 'ID du fragment',
    de: 'Abschnitts-ID',
    ja: 'チャンク ID',
  );
}

String knowledgeRefreshLabel(BuildContext context) {
  return openHandRefreshLabel(context);
}

String knowledgeRecallScoreLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '召回分数',
    zhHant: '召回分數',
    en: 'Score',
    fr: 'Score',
    de: 'Score',
    ja: 'スコア',
  );
}

String knowledgeOverviewLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '基础信息',
    zhHant: '基本資訊',
    en: 'Overview',
    fr: 'Vue d’ensemble',
    de: 'Übersicht',
    ja: '概要',
  );
}

String knowledgeCopyIdLabel(BuildContext context) {
  return openHandCopyIdLabel(context);
}

String knowledgeCopyContentLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '复制内容',
    zhHant: '複製內容',
    en: 'Copy Content',
    fr: 'Copier le contenu',
    de: 'Inhalt kopieren',
    ja: '内容をコピー',
  );
}

String knowledgeCopyPathLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '复制路径',
    zhHant: '複製路徑',
    en: 'Copy Path',
    fr: 'Copier le chemin',
    de: 'Pfad kopieren',
    ja: 'パスをコピー',
  );
}

String knowledgeFailedLabel(BuildContext context) {
  return openHandFailedLabel(context);
}

String knowledgeStoppedLabel(BuildContext context) {
  return openHandStoppedLabel(context);
}

String knowledgeChunkIdCopiedMessage(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '已复制分块 ID。',
    zhHant: '已複製分塊 ID。',
    en: 'Chunk ID copied.',
    fr: 'ID du fragment copié.',
    de: 'Abschnitts-ID kopiert.',
    ja: 'チャンク ID をコピーしました。',
  );
}

String knowledgePendingLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '待处理',
    zhHant: '待處理',
    en: 'Pending',
    fr: 'En attente',
    de: 'Ausstehend',
    ja: '保留中',
  );
}

String knowledgeUndoLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '撤销',
    zhHant: '復原',
    en: 'Undo',
    fr: 'Annuler',
    de: 'Rückgängig',
    ja: '元に戻す',
  );
}

String knowledgeDocumentTimeLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '文档时间',
    zhHant: '文件時間',
    en: 'Document time',
    fr: 'Date du document',
    de: 'Dokumentzeit',
    ja: 'ドキュメント日時',
  );
}

String knowledgeTimeFieldLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '时间字段',
    zhHant: '時間欄位',
    en: 'Time field',
    fr: 'Champ temporel',
    de: 'Zeitfeld',
    ja: '時間フィールド',
  );
}

String knowledgeUpdatedAtLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '更新时间',
    zhHant: '更新時間',
    en: 'Updated at',
    fr: 'Mis à jour le',
    de: 'Aktualisiert am',
    ja: '更新日時',
  );
}

String knowledgeFinalScoreLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '最终分数',
    zhHant: '最終分數',
    en: 'Final score',
    fr: 'Score final',
    de: 'Endscore',
    ja: '最終スコア',
  );
}

String knowledgeSourceIdLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '来源 ID',
    zhHant: '來源 ID',
    en: 'Source ID',
    fr: 'ID de la source',
    de: 'Quellen-ID',
    ja: 'ソース ID',
  );
}

String knowledgeSourceMissingMessage(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '来源不存在。',
    zhHant: '來源不存在。',
    en: 'Source not found.',
    fr: 'Source introuvable.',
    de: 'Quelle nicht gefunden.',
    ja: 'ソースが見つかりません。',
  );
}

String knowledgeQueryLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '查询',
    zhHant: '查詢',
    en: 'Query',
    fr: 'Requête',
    de: 'Abfrage',
    ja: 'クエリ',
  );
}

String knowledgeTagsLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '标签',
    zhHant: '標籤',
    en: 'Tags',
    fr: 'Étiquettes',
    de: 'Tags',
    ja: 'タグ',
  );
}

String knowledgeTitleLabel(BuildContext context) {
  return openHandTitleLabel(context);
}

String knowledgeStatusLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '状态',
    zhHant: '狀態',
    en: 'Status',
    fr: 'État',
    de: 'Status',
    ja: '状態',
  );
}

String knowledgePathCopiedMessage(BuildContext context) {
  return openHandPathCopiedLabel(context);
}

String knowledgeRedoLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '重做',
    zhHant: '重做',
    en: 'Redo',
    fr: 'Rétablir',
    de: 'Wiederholen',
    ja: 'やり直す',
  );
}

String knowledgeRerankScoreLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '重排分数',
    zhHant: '重排分數',
    en: 'Rerank score',
    fr: 'Score de reclassement',
    de: 'Rerank-Score',
    ja: '再ランクスコア',
  );
}

String knowledgeErrorLabel(BuildContext context) {
  return openHandErrorLabel(context);
}

String knowledgeEstimatedTokensLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '预估 token',
    zhHant: '預估 token',
    en: 'Estimated tokens',
    fr: 'Tokens estimés',
    de: 'Geschätzte Tokens',
    ja: '推定トークン',
  );
}

String knowledgePreviewLabel(BuildContext context) {
  return openHandPreviewLabel(context);
}
