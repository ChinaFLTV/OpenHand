import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/state/settings_controller.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/util/localized_text.dart';
import '../knowledge_base_controller.dart';

Future<void> showKnowledgeImportDialog(BuildContext context) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => const KnowledgeImportDialog(),
  );
}

class KnowledgeImportDialog extends StatefulWidget {
  const KnowledgeImportDialog({super.key});

  @override
  State<KnowledgeImportDialog> createState() => _KnowledgeImportDialogState();
}

class _KnowledgeImportDialogState extends State<KnowledgeImportDialog> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _content = TextEditingController();
  final TextEditingController _tags = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final controller = context.read<KnowledgeBaseController>();
    final settings = context.read<SettingsController>();
    final embeddingModel = controller.resolveEmbeddingModel(settings.aiModels);
    final isZh = openHandIsChineseLocale(context);
    if (embeddingModel == null) {
      OpenHandSnackBar.showError(
        context,
        isZh ? '请先配置可用的嵌入模型。' : 'Configure an embedding model first.',
      );
      return;
    }
    setState(() => _saving = true);
    final source = await controller.importNote(
      title: _title.text,
      content: _content.text,
      embeddingModel: embeddingModel,
      tags: _tags.text
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (source == null) {
      OpenHandSnackBar.showError(
        context,
        controller.error ?? (isZh ? '笔记导入失败。' : 'Note import failed.'),
      );
      return;
    }
    Navigator.of(context).pop();
    OpenHandSnackBar.showSuccess(
      context,
      isZh ? '笔记已导入并建立索引。' : 'Note imported and indexed.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isZh = openHandIsChineseLocale(context);
    return buildOpenHandAlertDialog(
      title: Text(isZh ? '新建知识库笔记' : 'New Knowledge Note'),
      content: buildOpenHandDialogConstrainedContent(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              decoration: InputDecoration(
                labelText: isZh ? '标题' : 'Title',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tags,
              decoration: InputDecoration(
                labelText: isZh ? '标签（逗号分隔）' : 'Tags (comma-separated)',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _content,
              minLines: 8,
              maxLines: 14,
              decoration: InputDecoration(
                labelText: isZh ? '内容' : 'Content',
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(isZh ? '取消' : 'Cancel'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_rounded),
          label: Text(isZh ? '保存并索引' : 'Save and Index'),
        ),
      ],
    );
  }
}
