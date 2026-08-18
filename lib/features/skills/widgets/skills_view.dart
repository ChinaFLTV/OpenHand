import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/animated_menu.dart';
import '../../../shared/ui/feature_page_shell.dart';
import '../../../shared/ui/feature_state_card.dart';
import '../../../shared/ui/hover_lift.dart';
import '../../../shared/ui/image_editor_dialog.dart';
import '../../../shared/ui/list_removal_transition.dart';
import '../../../shared/ui/local_file_media.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/util/localized_text.dart';
import '../../ai/index.dart'
    show
        AiResourceUsageKind,
        resourceUsageStatisticsLabel,
        showResourceUsageStatisticsDialog;
import '../model/local_skill.dart';
import '../skills_controller.dart';
import 'skill_market_dialog.dart';

enum _SkillCardAction { openDirectory, edit, delete }

/// 技能图标预览框的边长（逻辑像素）。
const double _kSkillIconPreviewExtent = 48;
const EdgeInsets _kSkillDialogContentPadding = EdgeInsets.all(24);

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

/// 以网格显示技能表情，点击后通过当前菜单路由返回所选值。
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
                      borderRadius: BorderRadius.circular(kOpenHandRadius14),
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

Future<String?> _showSkillEmojiMenu(
  BuildContext context, {
  required String? selectedEmoji,
}) {
  return showAnimatedAnchoredPopupMenu<String>(
    context: context,
    items: <PopupMenuEntry<String>>[
      _EmojiGridPopupEntry(
        emojis: _skillEmojiOptions,
        selectedEmoji: selectedEmoji,
      ),
    ],
  );
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

    final actions = FeaturePageToolbar(
      primaryActions: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 320, maxWidth: 340),
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
      ],
      secondaryActions: [
        FeaturePageToolbarIconButton(
          tooltip: resourceUsageStatisticsLabel(context),
          icon: Icons.insights_rounded,
          onPressed: () => showResourceUsageStatisticsDialog(
            context,
            kind: AiResourceUsageKind.skill,
            resourceLabels: <String, String>{
              for (final skill in skillsController.skills) ...<String, String>{
                skill.relativeDirectoryPath: skill.name,
                skill.name: skill.name,
              },
            },
          ),
        ),
        FeaturePageToolbarIconButton(
          tooltip: openHandSkillMarketLabel(context),
          icon: Icons.storefront_rounded,
          onPressed: () => _showSkillMarket(context),
        ),
        FeaturePageToolbarIconButton(
          tooltip: l10n.skillsOpenDirectory,
          icon: Icons.folder_open_rounded,
          onPressed: () => _openSkillsDirectory(context),
        ),
        FeaturePageToolbarIconButton(
          tooltip: l10n.skillsImport,
          icon: Icons.drive_folder_upload_outlined,
          onPressed: () => _importSkillDirectory(context),
        ),
        FeaturePageToolbarIconButton(
          tooltip: l10n.skillsNewSkill,
          icon: Icons.add_rounded,
          onPressed: () => _showCreateSkillDialog(context),
        ),
      ],
    );

    return FeaturePageShell(
      title: l10n.skillsPageTitle,
      subtitle: l10n.skillsPageSubtitle,
      actions: actions,
      body: _buildBody(
        context,
        filteredSkills: filteredSkills,
        skillsController: skillsController,
      ),
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
      return FeatureStateCard.centered(
        key: const ValueKey<String>('skills-error'),
        icon: Icons.error_outline_rounded,
        tone: FeatureStateTone.error,
        title: l10n.skillsStorageStatusError,
        body: skillsController.errorMessage!,
        action: OpenHandDialogActionButton.primary(
          onPressed: () => _refreshSkills(context),
          label: l10n.skillsRefresh,
        ),
      );
    }
    if (skillsController.skills.isEmpty) {
      return FeatureStateCard.centered(
        key: const ValueKey<String>('skills-empty'),
        icon: Icons.extension_off_outlined,
        title: l10n.skillsEmptyTitle,
        body: l10n.skillsEmptyBody,
      );
    }
    if (filteredSkills.isEmpty) {
      return FeatureStateCard.centered(
        key: const ValueKey<String>('skills-no-results'),
        icon: Icons.search_off_rounded,
        tone: FeatureStateTone.neutral,
        title: l10n.skillsNoResultsTitle,
        body: l10n.skillsNoResultsBody,
        action: OpenHandDialogActionButton.primary(
          onPressed: () => setState(() {
            _searchController.clear();
            _searchQuery = '';
          }),
          label: l10n.skillsRefresh,
        ),
      );
    }

    return LayoutBuilder(
      key: const ValueKey<String>('skills-grid'),
      builder: (context, constraints) {
        final maxCrossAxisExtent = constraints.maxWidth < 820
            ? constraints.maxWidth
            : 380.0;
        return OpenHandRemovableListScope(
          builder: (context, removal) => GridView.builder(
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
              // 定高网格：退场走就地淡出缩小，收高度只会在原位留洞。
              return OpenHandListRemovalTransition(
                collapsed: removal.isRemoving(skill.directoryPath),
                shrinkExtent: false,
                child: _SkillCard(
                  skill: skill,
                  onOpen: () => _showSkillPreview(context, skill),
                  onActionSelected: (action) {
                    switch (action) {
                      case _SkillCardAction.openDirectory:
                        _openSkillDirectory(context, skill);
                      case _SkillCardAction.edit:
                        _showEditSkillDialog(context, skill);
                      case _SkillCardAction.delete:
                        _confirmDeleteSkill(context, removal, skill);
                    }
                  },
                ),
              );
            },
          ),
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
      flashOpenHandSnack(
        context,
        '${l10n.skillsImportSuccess}: ${skill.name}',
        kind: OpenHandSnackKind.success,
      );
    } catch (e) {
      if (!context.mounted) return;
      flashOpenHandErrorOnCatch(context, l10n.skillOperationFailed);
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
    flashOpenHandSnack(
      context,
      '${l10n.skillTemplateCreated}: $createdSkillName',
      kind: OpenHandSnackKind.success,
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
      if (!context.mounted) return;
      flashOpenHandErrorOnCatch(context, l10n.skillOperationFailed);
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
      if (!context.mounted) return;
      flashOpenHandErrorOnCatch(context, l10n.skillOperationFailed);
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
          return buildOpenHandToolDialogShell(
            context: dialogContext,
            maxHeight: kOpenHandDialogHeightTall,
            child: Padding(
              padding: _kSkillDialogContentPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    skill.name,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  kOpenHandGap8,
                  Text(
                    skill.displayDirectoryPath,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (skill.defaultPrompt != null) ...[
                    kOpenHandGap12,
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(kOpenHandRadius18),
                      ),
                      child: Text(
                        skill.defaultPrompt!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                  kOpenHandGap16,
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(kOpenHandRadius24),
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
                  kOpenHandGap16,
                  Center(
                    child: OpenHandDialogActionButton.primary(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      label: l10n.skillsPreviewClose,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (!context.mounted) return;
      flashOpenHandErrorOnCatch(context, l10n.skillOperationFailed);
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
      flashOpenHandSnack(
        context,
        l10n.skillsEditSuccess,
        kind: OpenHandSnackKind.success,
      );
    } catch (e) {
      if (!context.mounted) return;
      flashOpenHandErrorOnCatch(context, l10n.skillOperationFailed);
    }
  }

  Future<void> _confirmDeleteSkill(
    BuildContext context,
    OpenHandListRemoval removal,
    LocalSkill skill,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: l10n.skillsDeleteConfirmTitle,
      message: '${l10n.skillsDeleteConfirmBody}\n\n${skill.name}',
      cancelLabel: l10n.skillsEditorCancel,
      confirmLabel: l10n.skillsDeleteConfirmAction,
      destructive: true,
    );
    if (!confirmed || !context.mounted) {
      return;
    }

    try {
      final skillsController = context.read<SkillsController>();
      await removal.run(
        skill.directoryPath,
        () => skillsController.deleteSkill(skill),
      );
      if (!context.mounted) {
        return;
      }
      flashOpenHandSnack(
        context,
        l10n.skillsDeleteSuccess,
        kind: OpenHandSnackKind.success,
      );
    } catch (e) {
      if (!context.mounted) return;
      flashOpenHandErrorOnCatch(context, l10n.skillOperationFailed);
    }
  }
}

/// 技能新建 / 编辑弹窗共用的表单状态与字段渲染。
///
/// 两个弹窗此前各写一份名称 / 图标 / 描述 / 正文表单，图标选择分支还因为
/// 新建弹窗不处理「已有图标」而逐渐分叉（按钮文案条件、错误提示位置都不一致）。
/// 统一后新建弹窗的 `_existingIcon*` 恒为 null，其余行为完全一致。
mixin _SkillFormState<T extends StatefulWidget> on State<T> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  String? _selectedEmoji;
  Uint8List? _selectedImageBytes;
  String? _existingIconPath;
  LocalSkillIconKind? _existingIconKind;
  bool _isSaving = false;
  String? _errorMessage;

  /// 已有图标解析失败时的占位文字（取技能名首字母）。
  String get _iconFallbackInitials;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  bool get _hasEffectiveIcon =>
      _selectedEmoji != null ||
      _selectedImageBytes != null ||
      (_existingIconPath != null && _existingIconKind != null);

  bool get _hasImageIcon =>
      _selectedImageBytes != null || _existingIconPath != null;

  Widget _buildSkillFormFields(BuildContext context, AppLocalizations l10n) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _nameController,
            enabled: !_isSaving,
            decoration: InputDecoration(labelText: l10n.skillsCreateNameLabel),
            validator: (value) {
              if ((value?.trim() ?? '').isEmpty) {
                return l10n.skillsCreateNameRequired;
              }
              return null;
            },
          ),
          kOpenHandGap16,
          FormField<bool>(
            initialValue: _hasEffectiveIcon,
            validator: (value) {
              if (!_hasEffectiveIcon) return l10n.skillsCreateIconRequired;
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
                      borderRadius: BorderRadius.circular(kOpenHandRadius16),
                      child: Container(
                        width: _kSkillIconPreviewExtent,
                        height: _kSkillIconPreviewExtent,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(
                            kOpenHandRadius16,
                          ),
                        ),
                        child: _buildSelectedIconPreview(),
                      ),
                    ),
                    kOpenHandHGap12,
                    Expanded(
                      child: Text(
                        _buildIconLabel(l10n),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: _hasEffectiveIcon
                              ? colorScheme.onSurface
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    kOpenHandHGap12,
                    Builder(
                      builder: (btnContext) {
                        return OutlinedButton.icon(
                          onPressed: _isSaving
                              ? null
                              : () async {
                                  final emoji = await _showSkillEmojiMenu(
                                    btnContext,
                                    selectedEmoji: _selectedEmoji,
                                  );
                                  if (!mounted || emoji == null) return;
                                  field.didChange(true);
                                  setState(() {
                                    _selectedEmoji = emoji;
                                    _selectedImageBytes = null;
                                    _existingIconPath = null;
                                    _existingIconKind = null;
                                    _errorMessage = null;
                                  });
                                },
                          icon: const Icon(Icons.emoji_emotions_outlined),
                          label: Text(
                            _hasEffectiveIcon
                                ? l10n.skillsCreateIconChange
                                : l10n.skillsCreateIconChoose,
                          ),
                        );
                      },
                    ),
                    kOpenHandHGap8,
                    OutlinedButton.icon(
                      onPressed: _isSaving
                          ? null
                          : () => _pickLocalImage(field),
                      icon: const Icon(Icons.image_outlined),
                      label: Text(
                        _hasImageIcon
                            ? l10n.skillsCreateImageChange
                            : l10n.skillsCreateImageChoose,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          kOpenHandGap16,
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
          kOpenHandGap16,
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
    );
  }

  String _buildIconLabel(AppLocalizations l10n) {
    if (_selectedImageBytes != null) return l10n.skillsCreateImageSelected;
    final selectedEmoji = _selectedEmoji;
    if (selectedEmoji != null) return selectedEmoji;
    final existingIconPath = _existingIconPath;
    if (existingIconPath != null) {
      final fileName = p.basename(existingIconPath).trim();
      if (fileName.isNotEmpty && fileName != '.') return fileName;
      return l10n.skillsCreateImageSelected;
    }
    return l10n.skillsCreateIconHint;
  }

  Widget _buildSelectedIconPreview() {
    final selectedImageBytes = _selectedImageBytes;
    if (selectedImageBytes != null) {
      // 图标预览框固定 48 逻辑像素；限定解码尺寸避免整张原图进内存。
      final decodeExtent =
          (_kSkillIconPreviewExtent * MediaQuery.devicePixelRatioOf(context))
              .round();
      return Image.memory(
        selectedImageBytes,
        fit: BoxFit.cover,
        cacheWidth: decodeExtent,
        cacheHeight: decodeExtent,
      );
    }
    final selectedEmoji = _selectedEmoji;
    if (selectedEmoji != null) {
      return _SkillEmojiGlyph(emoji: selectedEmoji, fontSize: 28);
    }
    final existingIconPath = _existingIconPath;
    final existingIconKind = _existingIconKind;
    if (existingIconPath != null && existingIconKind != null) {
      final fallback = Text(_iconFallbackInitials);
      return switch (existingIconKind) {
        LocalSkillIconKind.svg => buildLocalSvgPicture(
          existingIconPath,
          fit: BoxFit.cover,
          fallback: fallback,
        ),
        LocalSkillIconKind.raster => buildLocalRasterImage(
          existingIconPath,
          fit: BoxFit.cover,
          fallback: fallback,
        ),
      };
    }
    return const _SkillEmojiGlyph(emoji: '🙂', fontSize: 28);
  }

  Future<void> _pickLocalImage(FormFieldState<bool> field) async {
    try {
      final picked = await pickAndEditImage(context);
      if (!mounted || picked == null) return;
      field.didChange(true);
      setState(() {
        _selectedEmoji = null;
        _selectedImageBytes = picked.editedImage.bytes;
        _existingIconPath = null;
        _existingIconKind = null;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = AppLocalizations.of(context)!.imageEditorProcessFailed;
      });
    }
  }
}

class _EditSkillDialog extends StatefulWidget {
  const _EditSkillDialog({required this.skill, required this.initialContent});

  final LocalSkill skill;
  final String initialContent;

  @override
  State<_EditSkillDialog> createState() => _EditSkillDialogState();
}

class _EditSkillDialogState extends State<_EditSkillDialog>
    with _SkillFormState<_EditSkillDialog> {
  @override
  String get _iconFallbackInitials => widget.skill.initials;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.skill.name;
    _descriptionController.text = widget.skill.description;
    _contentController.text = widget.initialContent;
    _selectedEmoji = widget.skill.hasEmojiIcon ? widget.skill.emojiIcon : null;
    if (_selectedEmoji == null &&
        widget.skill.hasIcon &&
        widget.skill.iconPath != null) {
      _existingIconPath = widget.skill.iconPath;
      _existingIconKind = widget.skill.iconKind;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      canPop: !_isSaving,
      child: buildOpenHandToolDialogShell(
        context: context,
        maxWidth: kOpenHandDialogWidthExtraWide,
        maxHeight: kOpenHandDialogHeightTall,
        child: Padding(
          padding: _kSkillDialogContentPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${l10n.skillsEdit}: ${widget.skill.name}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              kOpenHandGap16,
              Expanded(
                child: SingleChildScrollView(
                  child: _buildSkillFormFields(context, l10n),
                ),
              ),
              OpenHandDialogErrorText(message: _errorMessage, topGap: 16),
              OpenHandDialogSaveActions(
                busy: _isSaving,
                cancelLabel: l10n.skillsEditorCancel,
                confirmLabel: l10n.skillsEditorSave,
                onConfirm: _handleSave,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleSave() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final updatedName = _nameController.text.trim();
    final updatedDescription = _descriptionController.text.trim();
    final updatedContent = _contentController.text;
    final preserveExistingIcon =
        _selectedEmoji == null &&
        _selectedImageBytes == null &&
        _existingIconPath != null &&
        _existingIconKind != null;
    if (updatedName == widget.skill.name &&
        updatedDescription == widget.skill.description &&
        updatedContent == widget.initialContent &&
        !_hasIconChanged()) {
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
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = l10n.skillOperationFailed;
      });
    }
  }

  bool _hasIconChanged() {
    final startedWithExistingIcon =
        widget.skill.emojiIcon == null &&
        widget.skill.hasIcon &&
        widget.skill.iconPath != null &&
        widget.skill.iconKind != null;
    if (_selectedImageBytes != null) return true;
    if (widget.skill.emojiIcon != null) {
      return _selectedEmoji != widget.skill.emojiIcon;
    }
    if (startedWithExistingIcon) {
      return _existingIconPath == null || _existingIconKind == null;
    }
    return _selectedEmoji != null;
  }
}

class _CreateSkillDialog extends StatefulWidget {
  const _CreateSkillDialog();

  @override
  State<_CreateSkillDialog> createState() => _CreateSkillDialogState();
}

class _CreateSkillDialogState extends State<_CreateSkillDialog>
    with _SkillFormState<_CreateSkillDialog> {
  @override
  String get _iconFallbackInitials => '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      canPop: !_isSaving,
      child: buildOpenHandToolDialogShell(
        context: context,
        maxWidth: kOpenHandDialogWidthExtraWide,
        maxHeight: kOpenHandDialogHeightTall,
        child: Padding(
          padding: _kSkillDialogContentPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.skillsCreateDialogTitle,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              kOpenHandGap16,
              Expanded(
                child: SingleChildScrollView(
                  child: _buildSkillFormFields(context, l10n),
                ),
              ),
              OpenHandDialogErrorText(message: _errorMessage, topGap: 16),
              OpenHandDialogSaveActions(
                busy: _isSaving,
                cancelLabel: l10n.commonCancel,
                confirmLabel: l10n.commonSave,
                onConfirm: _handleSave,
                onCancel: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleSave() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) return;
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
      if (!mounted) return;
      Navigator.of(context).pop(skill.name);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = l10n.skillOperationFailed;
      });
    }
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
                    kOpenHandHGap14,
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
                          kOpenHandGap6,
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
                    kOpenHandHGap8,
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
                  kOpenHandGap16,
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(kOpenHandRadius18),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.auto_awesome_outlined,
                          size: 18,
                          color: colorScheme.primary,
                        ),
                        kOpenHandHGap10,
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
        borderRadius: BorderRadius.circular(kOpenHandRadius18),
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
        LocalSkillIconKind.svg => buildLocalSvgPicture(
          iconPath,
          fit: BoxFit.cover,
          fallback: fallback,
        ),
        LocalSkillIconKind.raster => buildLocalRasterImage(
          iconPath,
          fit: BoxFit.cover,
          fallback: fallback,
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
