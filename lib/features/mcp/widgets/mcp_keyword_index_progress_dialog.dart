import 'dart:async';

import 'package:flutter/material.dart';
import 'package:openhand/shared/ui/openhand_spacing.dart';
import 'package:provider/provider.dart';

import '../../../app/support/silent_log.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../mcp_controller.dart';
import '../mcp_errors.dart';
import '../service/mcp_keyword_index.dart';

/// 「构建关键词映射」按钮触发的进度弹窗。负责：
///   * 调用 [McpController.buildKeywordIndex]
///   * 实时把 [McpKeywordIndexProgress] 渲染为线性进度条 + 当前服务名 + 计数
///   * 构建完成后切换到摘要态（总服务 / 总工具 / 索引体积 / 用时）
///
/// 防抖：调用方在按钮 onPressed 里通过 `controller.isBuildingKeywordIndex`
/// 自行 disable；服务层亦做了单飞兜底。
Future<void> showMcpKeywordIndexProgressDialog(BuildContext context) {
  return showAnimatedDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _McpKeywordIndexProgressDialog(),
  );
}

class _McpKeywordIndexProgressDialog extends StatefulWidget {
  const _McpKeywordIndexProgressDialog();

  @override
  State<_McpKeywordIndexProgressDialog> createState() =>
      _McpKeywordIndexProgressDialogState();
}

class _McpKeywordIndexProgressDialogState
    extends State<_McpKeywordIndexProgressDialog> {
  McpKeywordIndexProgress? _latest;
  McpKeywordIndexBuildResult? _result;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _kickoff());
  }

  Future<void> _kickoff() async {
    if (!mounted) return;
    final controller = context.read<McpController>();
    try {
      final result = await controller.buildKeywordIndex(
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _latest = p);
        },
      );
      if (!mounted) return;
      setState(() => _result = result);
    } catch (error, stack) {
      silentLog(
        'mcp_keyword_index_progress_dialog',
        '构建 MCP 关键词索引',
        error,
        stack,
      );
      if (!mounted) return;
      setState(() {
        _errorMessage = mcpFailureMessage(
          error,
          fallback: AppLocalizations.of(context)!.mcpOperationFailed,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final progress = _latest;
    final result = _result;
    final errorMessage = _errorMessage;
    final isDone = result != null || errorMessage != null;
    final ratio = (progress != null && progress.serverCount > 0)
        ? unitRatio(progress.serverIndex, progress.serverCount)
        : null;

    final body = <Widget>[];
    if (errorMessage != null) {
      body.add(
        Text(
          '${l10n.mcpKeywordIndexBuildFailed}\n$errorMessage',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      );
    } else if (result != null) {
      final idx = result.index;
      body.add(
        Text(
          l10n.mcpKeywordIndexBuildSummary(
            idx.totalServers,
            idx.totalTools,
            idx.byName.length +
                idx.byDescription.length +
                idx.bySearchHint.length,
            (idx.durationMs / 1000).toStringAsFixed(2),
          ),
          style: theme.textTheme.bodyMedium,
        ),
      );
      if (result.skippedServers > 0) {
        body.add(kOpenHandGap8);
        body.add(
          Text(
            l10n.mcpKeywordIndexBuildSkipped(result.skippedServers),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        );
      }
      if (result.errors.isNotEmpty) {
        body.add(kOpenHandGap8);
        body.add(
          Text(
            result.errors.take(4).join('\n'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        );
      }
    } else {
      body.add(LinearProgressIndicator(value: ratio, minHeight: 4));
      body.add(kOpenHandGap12);
      body.add(
        Text(
          progress == null
              ? l10n.mcpKeywordIndexBuildStarting
              : l10n.mcpKeywordIndexBuildProgress(
                  progress.serverIndex,
                  progress.serverCount,
                  progress.serverName,
                  progress.totalToolsScanned,
                ),
          style: theme.textTheme.bodyMedium,
        ),
      );
      if (progress != null && progress.skipped > 0) {
        body.add(kOpenHandGap6);
        body.add(
          Text(
            l10n.mcpKeywordIndexBuildSkipped(progress.skipped),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        );
      }
    }

    return buildOpenHandAlertDialog(
      title: Text(l10n.mcpKeywordIndexBuildTitle),
      content: buildOpenHandDialogConstrainedContent(
        minWidth: 360,
        maxWidth: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: body,
        ),
      ),
      actions: <Widget>[
        if (isDone)
          OpenHandDialogActionButton.primary(
            label: l10n.commonClose,
            onPressed: () => Navigator.of(context).maybePop(),
          )
        else
          OpenHandDialogActionButton.secondary(
            onPressed: () => Navigator.of(context).maybePop(),
            label: l10n.commonRunInBackground,
          ),
      ],
    );
  }
}
