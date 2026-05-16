import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/animated_menu.dart';
import '../../shared/ui/hover_lift.dart';
import '../../shared/ui/image_editor_dialog.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import 'model/local_skill.dart';
import 'skill_market_dialog.dart';
import 'skills_controller.dart';

enum _SkillCardAction { openDirectory, edit, delete }

const List<String> _skillEmojiOptions = <String>[
  '🧠',
  '📄',
  '🛠️',
  '🔎',
  '🧪',
  '📊',
  '🗂️',
  '🧩',
  '🤖',
  '📝',
  '🎯',
  '💡',
  '🚀',
  '🔒',
  '🧹',
  '🎨',
  '🗃️',
  '🧭',
  '📚',
  '🛰️',
  '🌐',
  '🧾',
  '⚙️',
  '📦',
];

class SkillsView extends StatefulWidget {
  const SkillsView({super.key});

  @override
  State<SkillsView> createState() => _SkillsViewState();
}

/// A [PopupMenuEntry] that displays an emoji grid.  Each emoji button
/// calls [Navigator.pop] with its value so the result is returned via
/// [showAnimatedMenu].
class _EmojiGridPopupEntry extends PopupMenuEntry<String> {
  const _EmojiGridPopupEntry({required this.emojis, this.selectedEmoji});

  final List<String> emojis;
  final String? selectedEmoji;

  @override
  double get height => 200;

  @override
  bool represents(String? value) => emojis.contains(value);

  @override
  State<_EmojiGridPopupEntry> createState() => _EmojiGridPopupEntryState();
}

class _EmojiGridPopupEntryState extends State<_EmojiGridPopupEntry> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        width: 320,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: widget.emojis
              .map(
                (emoji) => TextButton(
                  onPressed: () => Navigator.of(context).pop(emoji),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    padding: EdgeInsets.zero,
                    backgroundColor: emoji == widget.selectedEmoji
                        ? colorScheme.primaryContainer
                        : colorScheme.surfaceContainerHigh,
                    foregroundColor: colorScheme.onSurface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(emoji, style: const TextStyle(fontSize: 24)),
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }
}

class _SkillsViewState extends State<SkillsView> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final skillsController = context.watch<SkillsController>();
    final filteredSkills = _filterSkills(skillsController.skills);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 980;
            final actions = Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.end,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: stacked ? constraints.maxWidth : 320,
                    maxWidth: stacked ? constraints.maxWidth : 340,
                  ),
                  child: SearchBar(
                    controller: _searchController,
                    hintText: l10n.skillsSearchHint,
                    leading: const Icon(Icons.search_rounded),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: skillsController.isLoading
                      ? null
                      : () => _refreshSkills(context),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(l10n.skillsRefresh),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _showSkillMarket(context),
                  icon: const Icon(Icons.storefront_rounded),
                  label: Text(
                    _localizedSkillsText(
                      context,
                      zh: '技能市场',
                      en: 'Skill Market',
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _openSkillsDirectory(context),
                  icon: const Icon(Icons.folder_open_rounded),
                  label: Text(l10n.skillsOpenDirectory),
                ),
                OutlinedButton.icon(
                  onPressed: () => _importSkillDirectory(context),
                  icon: const Icon(Icons.drive_folder_upload_outlined),
                  label: Text(l10n.skillsImport),
                ),
                FilledButton.icon(
                  onPressed: () => _showCreateSkillDialog(context),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(l10n.skillsNewSkill),
                ),
              ],
            );

            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PageHeader(
                    title: l10n.skillsPageTitle,
                    subtitle: l10n.skillsPageSubtitle,
                  ),
                  const SizedBox(height: 20),
                  actions,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _PageHeader(
                    title: l10n.skillsPageTitle,
                    subtitle: l10n.skillsPageSubtitle,
                  ),
                ),
                const SizedBox(width: 20),
                Flexible(
                  child: Align(alignment: Alignment.topRight, child: actions),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        Expanded(
          child: AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 220),
            child: _buildBody(
              context,
              filteredSkills: filteredSkills,
              skillsController: skillsController,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context, {
    required List<LocalSkill> filteredSkills,
    required SkillsController skillsController,
  }) {
    final l10n = AppLocalizations.of(context)!;
    if (skillsController.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (skillsController.errorMessage != null) {
      return _SkillsStateCard(
        key: const ValueKey<String>('skills-error'),
        icon: Icons.error_outline_rounded,
        title: l10n.skillsStorageStatusError,
        body: skillsController.errorMessage!,
        primaryActionLabel: l10n.skillsRefresh,
        onPrimaryAction: () => _refreshSkills(context),
      );
    }
    if (skillsController.skills.isEmpty) {
      return _SkillsStateCard(
        key: const ValueKey<String>('skills-empty'),
        icon: Icons.extension_off_outlined,
        title: l10n.skillsEmptyTitle,
        body: l10n.skillsEmptyBody,
      );
    }
    if (filteredSkills.isEmpty) {
      return _SkillsStateCard(
        key: const ValueKey<String>('skills-no-results'),
        icon: Icons.search_off_rounded,
        title: l10n.skillsNoResultsTitle,
        body: l10n.skillsNoResultsBody,
        primaryActionLabel: l10n.skillsRefresh,
        onPrimaryAction: () => setState(() {
          _searchController.clear();
          _searchQuery = '';
        }),
      );
    }

    return LayoutBuilder(
      key: const ValueKey<String>('skills-grid'),
      builder: (context, constraints) {
        final maxCrossAxisExtent = constraints.maxWidth < 820
            ? constraints.maxWidth
            : 380.0;
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(0, 2, 0, 12),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: maxCrossAxisExtent,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            mainAxisExtent: 272,
          ),
          itemCount: filteredSkills.length,
          itemBuilder: (context, index) {
            final skill = filteredSkills[index];
            return _SkillCard(
              skill: skill,
              onOpen: () => _showSkillPreview(context, skill),
              onActionSelected: (action) {
                switch (action) {
                  case _SkillCardAction.openDirectory:
                    _openSkillDirectory(context, skill);
                  case _SkillCardAction.edit:
                    _showEditSkillDialog(context, skill);
                  case _SkillCardAction.delete:
                    _confirmDeleteSkill(context, skill);
                }
              },
            );
          },
        );
      },
    );
  }

  List<LocalSkill> _filterSkills(List<LocalSkill> skills) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return skills;
    }
    return skills
        .where((skill) {
          final name = skill.name.toLowerCase();
          final description = skill.description.toLowerCase();
          final defaultPrompt = (skill.defaultPrompt ?? '').toLowerCase();
          final path = skill.relativeDirectoryPath.toLowerCase();
          return name.contains(query) ||
              description.contains(query) ||
              defaultPrompt.contains(query) ||
              path.contains(query);
        })
        .toList(growable: false);
  }

  Future<void> _refreshSkills(BuildContext context) async {
    await context.read<SkillsController>().refresh();
  }

  Future<void> _importSkillDirectory(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final selectedPath = await getDirectoryPath();
    if (!context.mounted || selectedPath == null || selectedPath.isEmpty) {
      return;
    }

    try {
      final skill = await context.read<SkillsController>().importSkillDirectory(
        selectedPath,
      );
      if (!context.mounted) {
        return;
      }
      _showSnackBar(
        context,
        '${l10n.skillsImportSuccess}: ${skill.name}',
        kind: _SnackKind.success,
      );
    } catch (e) {
      if (!context.mounted) {
        return;
      }
      _showSnackBar(context, l10n.skillOperationFailed, kind: _SnackKind.error);
    }
  }

  Future<void> _showCreateSkillDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final createdSkillName = await showAnimatedDialog<String>(
      context: context,
      builder: (dialogContext) {
        return const _CreateSkillDialog();
      },
    );
    if (!context.mounted || createdSkillName == null) {
      return;
    }
    _showSnackBar(
      context,
      '${l10n.skillTemplateCreated}: $createdSkillName',
      kind: _SnackKind.success,
    );
  }

  Future<void> _showSkillMarket(BuildContext context) async {
    await showSkillMarketDialog(context);
  }

  Future<void> _openSkillsDirectory(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await context.read<SkillsController>().openStorageDirectory();
    } catch (e) {
      if (!context.mounted) {
        return;
      }
      _showSnackBar(context, l10n.skillOperationFailed, kind: _SnackKind.error);
    }
  }

  Future<void> _openSkillDirectory(
    BuildContext context,
    LocalSkill skill,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await context.read<SkillsController>().openSkillDirectory(skill);
    } catch (e) {
      if (!context.mounted) {
        return;
      }
      _showSnackBar(context, l10n.skillOperationFailed, kind: _SnackKind.error);
    }
  }

  Future<void> _showSkillPreview(BuildContext context, LocalSkill skill) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final content = await context.read<SkillsController>().readSkillManifest(
        skill,
      );
      if (!context.mounted) {
        return;
      }
      await showAnimatedDialog<void>(
        context: context,
        builder: (dialogContext) {
          return Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900, maxHeight: 720),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      skill.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      skill.displayDirectoryPath,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (skill.defaultPrompt != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          skill.defaultPrompt!,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: ColoredBox(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerLow,
                          child: Markdown(
                            data: content,
                            selectable: true,
                            padding: const EdgeInsets.all(20),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: Text(l10n.skillsPreviewClose),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (!context.mounted) {
        return;
      }
      _showSnackBar(context, l10n.skillOperationFailed, kind: _SnackKind.error);
    }
  }

  Future<void> _showEditSkillDialog(
    BuildContext context,
    LocalSkill skill,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final initialContent = await context
          .read<SkillsController>()
          .readSkillManifest(skill);
      if (!context.mounted) {
        return;
      }

      final submitted = await showAnimatedDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return _EditSkillDialog(skill: skill, initialContent: initialContent);
        },
      );

      if (!context.mounted || submitted != true) {
        return;
      }
      _showSnackBar(context, l10n.skillsEditSuccess, kind: _SnackKind.success);
    } catch (e) {
      if (!context.mounted) {
        return;
      }
      _showSnackBar(context, l10n.skillOperationFailed, kind: _SnackKind.error);
    }
  }

  Future<void> _confirmDeleteSkill(
    BuildContext context,
    LocalSkill skill,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.skillsDeleteConfirmTitle),
          content: Text('${l10n.skillsDeleteConfirmBody}\n\n${skill.name}'),
          actions: [
            OpenHandDialogActionButton.secondary(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              label: l10n.skillsEditorCancel,
            ),
            OpenHandDialogActionButton.destructive(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              label: l10n.skillsDeleteConfirmAction,
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) {
      return;
    }

    try {
      await context.read<SkillsController>().deleteSkill(skill);
      if (!context.mounted) {
        return;
      }
      _showSnackBar(
        context,
        l10n.skillsDeleteSuccess,
        kind: _SnackKind.success,
      );
    } catch (e) {
      if (!context.mounted) {
        return;
      }
      _showSnackBar(context, l10n.skillOperationFailed, kind: _SnackKind.error);
    }
  }

  void _showSnackBar(
    BuildContext context,
    String message, {
    _SnackKind kind = _SnackKind.info,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      switch (kind) {
        case _SnackKind.success:
          OpenHandSnackBar.show(
            context,
            messenger,
            OpenHandSnackBar.success(context, message),
          );
        case _SnackKind.error:
          OpenHandSnackBar.show(
            context,
            messenger,
            OpenHandSnackBar.error(context, message),
          );
        case _SnackKind.info:
          OpenHandSnackBar.show(
            context,
            messenger,
            SnackBar(content: Text(message)),
          );
      }
    });
  }
}

enum _SnackKind { info, success, error }

String _localizedSkillsText(
  BuildContext context, {
  required String zh,
  required String en,
}) {
  return Localizations.localeOf(context).languageCode.toLowerCase() == 'zh'
      ? zh
      : en;
}

class _EditSkillDialog extends StatefulWidget {
  const _EditSkillDialog({required this.skill, required this.initialContent});

  final LocalSkill skill;
  final String initialContent;

  @override
  State<_EditSkillDialog> createState() => _EditSkillDialogState();
}

class _EditSkillDialogState extends State<_EditSkillDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _contentController;
  String? _selectedEmoji;
  Uint8List? _selectedImageBytes;
  String? _existingIconPath;
  LocalSkillIconKind? _existingIconKind;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.skill.name);
    _descriptionController = TextEditingController(
      text: widget.skill.description,
    );
    _contentController = TextEditingController(text: widget.initialContent);
    _selectedEmoji = widget.skill.hasEmojiIcon ? widget.skill.emojiIcon : null;
    if (_selectedEmoji == null &&
        widget.skill.hasIcon &&
        widget.skill.iconPath != null &&
        File(widget.skill.iconPath!).existsSync()) {
      _existingIconPath = widget.skill.iconPath;
      _existingIconKind = widget.skill.iconKind;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return PopScope(
      canPop: !_isSaving,
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960, maxHeight: 760),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${l10n.skillsEdit}: ${widget.skill.name}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            controller: _nameController,
                            enabled: !_isSaving,
                            decoration: InputDecoration(
                              labelText: l10n.skillsCreateNameLabel,
                            ),
                            validator: (value) {
                              if ((value?.trim() ?? '').isEmpty) {
                                return l10n.skillsCreateNameRequired;
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          FormField<bool>(
                            initialValue: _hasEffectiveIcon,
                            validator: (value) {
                              if (!_hasEffectiveIcon) {
                                return l10n.skillsCreateIconRequired;
                              }
                              return null;
                            },
                            builder: (field) {
                              final theme = Theme.of(context);
                              final colorScheme = theme.colorScheme;

                              return InputDecorator(
                                isEmpty: !_hasEffectiveIcon,
                                decoration: InputDecoration(
                                  labelText: l10n.skillsCreateIconLabel,
                                  hintText: l10n.skillsCreateIconHint,
                                  errorText: field.errorText,
                                ),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: Container(
                                        width: 48,
                                        height: 48,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color:
                                              colorScheme.surfaceContainerHigh,
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                        child: _buildSelectedIconPreview(),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _buildIconLabel(l10n),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color: _hasEffectiveIcon
                                                  ? colorScheme.onSurface
                                                  : colorScheme
                                                        .onSurfaceVariant,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Builder(
                                      builder: (btnContext) {
                                        return OutlinedButton.icon(
                                          onPressed: _isSaving
                                              ? null
                                              : () {
                                                  _showEmojiMenu(
                                                    btnContext,
                                                    onSelected: (emoji) {
                                                      field.didChange(true);
                                                      setState(() {
                                                        _selectedEmoji = emoji;
                                                        _selectedImageBytes =
                                                            null;
                                                        _existingIconPath =
                                                            null;
                                                        _existingIconKind =
                                                            null;
                                                        _errorMessage = null;
                                                      });
                                                    },
                                                  );
                                                },
                                          icon: const Icon(
                                            Icons.emoji_emotions_outlined,
                                          ),
                                          label: Text(
                                            _hasEffectiveIcon
                                                ? l10n.skillsCreateIconChange
                                                : l10n.skillsCreateIconChoose,
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton.icon(
                                      onPressed: _isSaving
                                          ? null
                                          : () => _pickLocalImage(field),
                                      icon: const Icon(Icons.image_outlined),
                                      label: Text(
                                        _selectedImageBytes != null ||
                                                _existingIconPath != null
                                            ? l10n.skillsCreateImageChange
                                            : l10n.skillsCreateImageChoose,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _descriptionController,
                            enabled: !_isSaving,
                            maxLines: 3,
                            decoration: InputDecoration(
                              labelText: l10n.skillsCreateDescriptionLabel,
                            ),
                            validator: (value) {
                              if ((value?.trim() ?? '').isEmpty) {
                                return l10n.skillsCreateDescriptionRequired;
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _contentController,
                            enabled: !_isSaving,
                            minLines: 14,
                            maxLines: 20,
                            textAlignVertical: TextAlignVertical.top,
                            decoration: InputDecoration(
                              labelText: l10n.skillsEditorLabel,
                              alignLabelWithHint: true,
                            ),
                            validator: (value) {
                              if ((value?.trim() ?? '').isEmpty) {
                                return l10n.skillsCreateContentRequired;
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                if (_isSaving) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: 132,
                      height: 52,
                      child: OutlinedButton(
                        onPressed: _isSaving
                            ? null
                            : () => Navigator.of(context).pop(false),
                        child: Text(l10n.skillsEditorCancel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 132,
                      height: 52,
                      child: FilledButton(
                        onPressed: _isSaving ? null : _handleSave,
                        child: Text(l10n.skillsEditorSave),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleSave() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final updatedName = _nameController.text.trim();
    final updatedDescription = _descriptionController.text.trim();
    final updatedContent = _contentController.text;
    final preserveExistingIcon =
        _selectedEmoji == null &&
        _selectedImageBytes == null &&
        _existingIconPath != null &&
        _existingIconKind != null;
    final iconChanged = _hasIconChanged();
    if (updatedName == widget.skill.name &&
        updatedDescription == widget.skill.description &&
        updatedContent == widget.initialContent &&
        !iconChanged) {
      Navigator.of(context).pop(false);
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await context.read<SkillsController>().updateSkill(
        skill: widget.skill,
        name: updatedName,
        emojiIcon: _selectedEmoji,
        imageIconBytes: _selectedImageBytes,
        shortDescription: updatedDescription,
        manifestContent: updatedContent,
        preserveExistingIcon: preserveExistingIcon,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _errorMessage = l10n.skillOperationFailed;
      });
    }
  }

  bool get _hasEffectiveIcon =>
      _selectedEmoji != null ||
      _selectedImageBytes != null ||
      (_existingIconPath != null && _existingIconKind != null);

  bool _hasIconChanged() {
    final startedWithExistingIcon =
        widget.skill.emojiIcon == null &&
        widget.skill.hasIcon &&
        widget.skill.iconPath != null &&
        widget.skill.iconKind != null &&
        File(widget.skill.iconPath!).existsSync();
    if (_selectedImageBytes != null) {
      return true;
    }
    if (widget.skill.emojiIcon != null) {
      return _selectedEmoji != widget.skill.emojiIcon;
    }
    if (startedWithExistingIcon) {
      return _existingIconPath == null || _existingIconKind == null;
    }
    return _selectedEmoji != null;
  }

  String _buildIconLabel(AppLocalizations l10n) {
    if (_selectedImageBytes != null) {
      return l10n.skillsCreateImageSelected;
    }
    if (_selectedEmoji != null) {
      return _selectedEmoji!;
    }
    final existingIconPath = _existingIconPath;
    if (existingIconPath != null) {
      final segments = File(existingIconPath).uri.pathSegments;
      if (segments.isNotEmpty) {
        return segments.last;
      }
      return l10n.skillsCreateImageSelected;
    }
    return l10n.skillsCreateIconHint;
  }

  Widget _buildSelectedIconPreview() {
    if (_selectedImageBytes != null) {
      return Image.memory(_selectedImageBytes!, fit: BoxFit.cover);
    }
    if (_selectedEmoji != null) {
      return _SkillEmojiGlyph(emoji: _selectedEmoji!, fontSize: 28);
    }
    final existingIconPath = _existingIconPath;
    final existingIconKind = _existingIconKind;
    if (existingIconPath != null && existingIconKind != null) {
      final iconFile = File(existingIconPath);
      final fallback = Text(widget.skill.initials);
      return switch (existingIconKind) {
        LocalSkillIconKind.svg => SvgPicture.file(
          iconFile,
          fit: BoxFit.cover,
          placeholderBuilder: (context) => fallback,
          errorBuilder: (context, error, stackTrace) => fallback,
        ),
        LocalSkillIconKind.raster => Image.file(
          iconFile,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => fallback,
        ),
      };
    }
    return const _SkillEmojiGlyph(emoji: '🙂', fontSize: 28);
  }

  void _showEmojiMenu(
    BuildContext btnContext, {
    required ValueChanged<String> onSelected,
  }) {
    final button = btnContext.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(btnContext).overlay!.context.findRenderObject()!
            as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );
    showAnimatedMenu<String>(
      context: btnContext,
      position: position,
      items: [
        _EmojiGridPopupEntry(
          emojis: _skillEmojiOptions,
          selectedEmoji: _selectedEmoji,
        ),
      ],
    ).then((emoji) {
      if (!mounted || emoji == null) return;
      onSelected(emoji);
    });
  }

  Future<void> _pickLocalImage(FormFieldState<bool> field) async {
    final selectedFile = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(
          label: 'images',
          extensions: <String>['png', 'jpg', 'jpeg', 'webp', 'gif'],
        ),
      ],
    );
    if (!mounted || selectedFile == null) {
      return;
    }

    try {
      final sourceBytes = await selectedFile.readAsBytes();
      if (!mounted) {
        return;
      }
      final editedImage = await showImageEditorDialog(
        context,
        imageBytes: sourceBytes,
      );
      if (!mounted || editedImage == null) {
        return;
      }
      field.didChange(true);
      setState(() {
        _selectedEmoji = null;
        _selectedImageBytes = editedImage.bytes;
        _existingIconPath = null;
        _existingIconKind = null;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = AppLocalizations.of(context)!.imageEditorProcessFailed;
      });
    }
  }
}

class _CreateSkillDialog extends StatefulWidget {
  const _CreateSkillDialog();

  @override
  State<_CreateSkillDialog> createState() => _CreateSkillDialogState();
}

class _CreateSkillDialogState extends State<_CreateSkillDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  String? _selectedEmoji;
  Uint8List? _selectedImageBytes;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return PopScope(
      canPop: !_isSaving,
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920, maxHeight: 760),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.skillsCreateDialogTitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            controller: _nameController,
                            enabled: !_isSaving,
                            decoration: InputDecoration(
                              labelText: l10n.skillsCreateNameLabel,
                            ),
                            validator: (value) {
                              if ((value?.trim() ?? '').isEmpty) {
                                return l10n.skillsCreateNameRequired;
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          FormField<bool>(
                            initialValue: _selectedEmoji != null,
                            validator: (value) {
                              if (_selectedEmoji == null &&
                                  _selectedImageBytes == null) {
                                return l10n.skillsCreateIconRequired;
                              }
                              return null;
                            },
                            builder: (field) {
                              final theme = Theme.of(context);
                              final colorScheme = theme.colorScheme;
                              final selectedEmoji = _selectedEmoji;
                              final selectedImageBytes = _selectedImageBytes;

                              return InputDecorator(
                                isEmpty:
                                    selectedEmoji == null &&
                                    selectedImageBytes == null,
                                decoration: InputDecoration(
                                  labelText: l10n.skillsCreateIconLabel,
                                  hintText: l10n.skillsCreateIconHint,
                                  errorText: field.errorText,
                                ),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: Container(
                                        width: 48,
                                        height: 48,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color:
                                              colorScheme.surfaceContainerHigh,
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                        child: selectedImageBytes != null
                                            ? Image.memory(
                                                selectedImageBytes,
                                                fit: BoxFit.cover,
                                              )
                                            : _SkillEmojiGlyph(
                                                emoji: selectedEmoji ?? '🙂',
                                                fontSize: 28,
                                              ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        selectedImageBytes != null
                                            ? l10n.skillsCreateImageSelected
                                            : selectedEmoji ??
                                                  l10n.skillsCreateIconHint,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color:
                                                  selectedEmoji == null &&
                                                      selectedImageBytes == null
                                                  ? colorScheme.onSurfaceVariant
                                                  : colorScheme.onSurface,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Builder(
                                      builder: (btnContext) {
                                        return OutlinedButton.icon(
                                          onPressed: _isSaving
                                              ? null
                                              : () {
                                                  _showEmojiMenu(
                                                    btnContext,
                                                    onSelected: (emoji) {
                                                      field.didChange(true);
                                                      setState(() {
                                                        _selectedEmoji = emoji;
                                                        _selectedImageBytes =
                                                            null;
                                                      });
                                                    },
                                                  );
                                                },
                                          icon: const Icon(
                                            Icons.emoji_emotions_outlined,
                                          ),
                                          label: Text(
                                            selectedEmoji == null
                                                ? l10n.skillsCreateIconChoose
                                                : l10n.skillsCreateIconChange,
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton.icon(
                                      onPressed: _isSaving
                                          ? null
                                          : () => _pickLocalImage(field),
                                      icon: const Icon(Icons.image_outlined),
                                      label: Text(
                                        selectedImageBytes == null
                                            ? l10n.skillsCreateImageChoose
                                            : l10n.skillsCreateImageChange,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _descriptionController,
                            enabled: !_isSaving,
                            maxLines: 3,
                            decoration: InputDecoration(
                              labelText: l10n.skillsCreateDescriptionLabel,
                            ),
                            validator: (value) {
                              if ((value?.trim() ?? '').isEmpty) {
                                return l10n.skillsCreateDescriptionRequired;
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _contentController,
                            enabled: !_isSaving,
                            minLines: 14,
                            maxLines: 20,
                            textAlignVertical: TextAlignVertical.top,
                            decoration: InputDecoration(
                              labelText: l10n.skillsEditorLabel,
                              alignLabelWithHint: true,
                            ),
                            validator: (value) {
                              if ((value?.trim() ?? '').isEmpty) {
                                return l10n.skillsCreateContentRequired;
                              }
                              return null;
                            },
                          ),
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              _errorMessage!,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (_isSaving) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: 132,
                      height: 52,
                      child: OutlinedButton(
                        onPressed: _isSaving
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: Text(l10n.commonCancel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 132,
                      height: 52,
                      child: FilledButton(
                        onPressed: _isSaving ? null : _handleSave,
                        child: Text(l10n.commonSave),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleSave() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final skill = await context.read<SkillsController>().createSkill(
        name: _nameController.text.trim(),
        emojiIcon: _selectedEmoji,
        imageIconBytes: _selectedImageBytes,
        shortDescription: _descriptionController.text.trim(),
        manifestContent: _contentController.text,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(skill.name);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _errorMessage = l10n.skillOperationFailed;
      });
    }
  }

  void _showEmojiMenu(
    BuildContext btnContext, {
    required ValueChanged<String> onSelected,
  }) {
    final button = btnContext.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(btnContext).overlay!.context.findRenderObject()!
            as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );
    showAnimatedMenu<String>(
      context: btnContext,
      position: position,
      items: [
        _EmojiGridPopupEntry(
          emojis: _skillEmojiOptions,
          selectedEmoji: _selectedEmoji,
        ),
      ],
    ).then((emoji) {
      if (!mounted || emoji == null) return;
      onSelected(emoji);
    });
  }

  Future<void> _pickLocalImage(FormFieldState<bool> field) async {
    final selectedFile = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(
          label: 'images',
          extensions: <String>['png', 'jpg', 'jpeg', 'webp', 'gif'],
        ),
      ],
    );
    if (!mounted || selectedFile == null) {
      return;
    }

    try {
      final sourceBytes = await selectedFile.readAsBytes();
      if (!mounted) {
        return;
      }
      final editedImage = await showImageEditorDialog(
        context,
        imageBytes: sourceBytes,
      );
      if (!mounted || editedImage == null) {
        return;
      }
      field.didChange(true);
      setState(() {
        _selectedEmoji = null;
        _selectedImageBytes = editedImage.bytes;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = AppLocalizations.of(context)!.imageEditorProcessFailed;
      });
    }
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.displaySmall),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SkillCard extends StatelessWidget {
  const _SkillCard({
    required this.skill,
    required this.onOpen,
    required this.onActionSelected,
  });

  final LocalSkill skill;
  final VoidCallback onOpen;
  final ValueChanged<_SkillCardAction> onActionSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return HoverLift(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SkillCardAvatar(skill: skill),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            skill.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            skill.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedPopupMenuButton<_SkillCardAction>(
                      onSelected: onActionSelected,
                      itemBuilder: (context) {
                        return [
                          PopupMenuItem<_SkillCardAction>(
                            value: _SkillCardAction.openDirectory,
                            child: Text(l10n.skillsOpenDirectory),
                          ),
                          PopupMenuItem<_SkillCardAction>(
                            value: _SkillCardAction.edit,
                            child: Text(l10n.skillsEdit),
                          ),
                          PopupMenuItem<_SkillCardAction>(
                            value: _SkillCardAction.delete,
                            child: Text(l10n.skillsDelete),
                          ),
                        ];
                      },
                    ),
                  ],
                ),
                if (skill.defaultPrompt != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.auto_awesome_outlined,
                          size: 18,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            skill.defaultPrompt!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const Spacer(),
                Chip(
                  avatar: const Icon(Icons.description_outlined, size: 18),
                  label: Text(
                    skill.displayDirectoryPath,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SkillCardAvatar extends StatelessWidget {
  const _SkillCardAvatar({required this.skill});

  final LocalSkill skill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: skill.hasIcon
          ? _SkillCardIcon(
              skill: skill,
              fallback: _SkillCardAvatarFallback(skill: skill),
            )
          : skill.hasEmojiIcon
          ? _SkillCardEmojiIcon(skill: skill)
          : _SkillCardAvatarFallback(skill: skill),
    );
  }
}

class _SkillCardIcon extends StatelessWidget {
  const _SkillCardIcon({required this.skill, required this.fallback});

  final LocalSkill skill;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final iconPath = skill.iconPath;
    final iconKind = skill.iconKind;
    if (iconPath == null || iconKind == null) {
      return fallback;
    }

    return SizedBox.expand(
      child: switch (iconKind) {
        LocalSkillIconKind.svg => SvgPicture.file(
          File(iconPath),
          fit: BoxFit.cover,
          placeholderBuilder: (context) => fallback,
          errorBuilder: (context, error, stackTrace) => fallback,
        ),
        LocalSkillIconKind.raster => Image.file(
          File(iconPath),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => fallback,
        ),
      },
    );
  }
}

class _SkillCardEmojiIcon extends StatelessWidget {
  const _SkillCardEmojiIcon({required this.skill});

  final LocalSkill skill;

  @override
  Widget build(BuildContext context) {
    return _SkillEmojiGlyph(emoji: skill.emojiIcon!, fontSize: 24);
  }
}

class _SkillEmojiGlyph extends StatelessWidget {
  const _SkillEmojiGlyph({required this.emoji, required this.fontSize});

  final String emoji;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Center(
        child: Transform.translate(
          offset: const Offset(0, -1),
          child: Text(
            emoji,
            textAlign: TextAlign.center,
            textHeightBehavior: const TextHeightBehavior(
              applyHeightToFirstAscent: false,
              applyHeightToLastDescent: false,
            ),
            strutStyle: StrutStyle(
              fontSize: fontSize,
              height: 1,
              forceStrutHeight: true,
            ),
            style: TextStyle(
              fontSize: fontSize,
              height: 1,
              leadingDistribution: TextLeadingDistribution.even,
            ),
          ),
        ),
      ),
    );
  }
}

class _SkillCardAvatarFallback extends StatelessWidget {
  const _SkillCardAvatarFallback({required this.skill});

  final LocalSkill skill;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Text(
      skill.initials,
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(color: colorScheme.onPrimaryContainer),
    );
  }
}

class _SkillsStateCard extends StatelessWidget {
  const _SkillsStateCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.primaryActionLabel,
    this.onPrimaryAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? primaryActionLabel;
  final VoidCallback? onPrimaryAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 56, color: theme.colorScheme.primary),
                const SizedBox(height: 18),
                Text(title, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 12),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (primaryActionLabel != null && onPrimaryAction != null) ...[
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: onPrimaryAction,
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: Text(primaryActionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
