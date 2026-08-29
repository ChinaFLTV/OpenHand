import 'package:flutter/material.dart';

import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/openhand_form_fields.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/openhand_typography.dart';
import '../service/workflow_curl_parser.dart';

Future<WorkflowCurlImport?> showWorkflowCurlImportDialog(BuildContext context) {
  return showAnimatedDialog<WorkflowCurlImport>(
    context: context,
    builder: (_) => const _WorkflowCurlImportDialog(),
  );
}

class _WorkflowCurlImportDialog extends StatefulWidget {
  const _WorkflowCurlImportDialog();

  @override
  State<_WorkflowCurlImportDialog> createState() =>
      _WorkflowCurlImportDialogState();
}

class _WorkflowCurlImportDialogState extends State<_WorkflowCurlImportDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return buildOpenHandDialog(
      width: 680,
      maxHeight: MediaQuery.sizeOf(context).height * 0.82,
      insetPadding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(22, 18, 16, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[
                  colors.primaryContainer.withValues(alpha: 0.88),
                  colors.tertiaryContainer.withValues(alpha: 0.54),
                ],
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: colors.surface.withValues(alpha: 0.84),
                    borderRadius: BorderRadius.circular(kOpenHandRadius14),
                    border: Border.all(
                      color: colors.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Icon(
                    Icons.terminal_rounded,
                    color: colors.primary,
                    size: 24,
                  ),
                ),
                kOpenHandHGap12,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '导入 cURL',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      kOpenHandGap3,
                      Text(
                        '自动解析请求方式、URL、请求头、查询参数和请求体。',
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
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const OpenHandFormLabel('cURL 命令', required: true),
                  kOpenHandGap7,
                  TextField(
                    controller: _controller,
                    autofocus: true,
                    minLines: 7,
                    maxLines: 14,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: kOpenHandMonospaceFontFamily,
                      height: 1.45,
                    ),
                    decoration: InputDecoration(
                      hintText:
                          "curl -X POST 'https://api.example.com/items' \\\n  -H 'Content-Type: application/json' \\\n  --data-raw '{\"name\":\"OpenHand\"}'",
                      filled: true,
                      fillColor: colors.surfaceContainerLowest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(kOpenHandRadius14),
                      ),
                    ),
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                  ),
                  AnimatedSize(
                    duration: openHandMotionDuration(
                      context,
                      kOpenHandMotion180,
                    ),
                    curve: Curves.easeOutCubic,
                    child: _error == null
                        ? const SizedBox.shrink()
                        : Container(
                            margin: const EdgeInsets.only(top: 12),
                            padding: const EdgeInsets.all(11),
                            decoration: BoxDecoration(
                              color: colors.errorContainer,
                              borderRadius: BorderRadius.circular(
                                kOpenHandRadius12,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.error_outline_rounded,
                                  size: 18,
                                  color: colors.onErrorContainer,
                                ),
                                kOpenHandHGap8,
                                Expanded(
                                  child: Text(
                                    _error!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.onErrorContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                kOpenHandHGap10,
                FilledButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.download_done_rounded, size: 18),
                  label: const Text('解析并导入'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _submit() {
    try {
      final result = parseWorkflowCurl(_controller.text);
      Navigator.of(context).pop(result);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }
}
