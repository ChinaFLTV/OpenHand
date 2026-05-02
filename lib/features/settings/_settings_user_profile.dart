part of 'settings_view.dart';

/// "用户画像" 设置项触发按钮 (2026-04-25 迁移至 AI 设置 → 会话设置).
///
/// 通过 `context.watch<MemoryController>()` 实时跟随画像变更，按钮副标题会
/// 同步显示当前画像内容预览或 "未设置"。点击后弹出
/// [_UserProfileEditorDialog] 进行预览 / 更新；弹窗的进出场动画由
/// [showAnimatedDialog] 自动读取全局弹窗动画设置。
class _UserProfileSettingsButton extends StatefulWidget {
  const _UserProfileSettingsButton();

  @override
  State<_UserProfileSettingsButton> createState() =>
      _UserProfileSettingsButtonState();
}

class _UserProfileSettingsButtonState
    extends State<_UserProfileSettingsButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final memoryController = context.watch<MemoryController>();
    final profile = memoryController.userProfile;
    final hasProfile = profile != null && profile.content.trim().isNotEmpty;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final preview = hasProfile
        ? _previewContent(profile.content)
        : _localizedText(
            context,
            zh: '未设置 — 点击建立你的全局用户画像',
            en: 'Not set — click to build your global profile',
          );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: MouseRegion(
        onEnter: (_) {
          if (!_hovered) setState(() => _hovered = true);
        },
        onExit: (_) {
          if (_hovered) setState(() => _hovered = false);
        },
        child: MicroPressFeedback(
          child: Material(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _showUserProfileDialog(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.account_circle_outlined,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(
                            _localizedText(
                              context,
                              zh: hasProfile ? '查看 / 更新用户画像' : '建立用户画像',
                              en: hasProfile
                                  ? 'View / Update Profile'
                                  : 'Set Up Profile',
                            ),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (hasProfile)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.tertiaryContainer,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                _localizedText(
                                  context,
                                  zh: '已配置',
                                  en: 'Configured',
                                ),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.onTertiaryContainer,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedSlide(
                  offset: Offset(_hovered && !reduceMotion ? 0.18 : 0, 0),
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
        ),
      ),
    );
  }

  static String _previewContent(String content) {
    final flat = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.length <= 160) return flat;
    return '${flat.substring(0, 157)}…';
  }

  static Future<void> _showUserProfileDialog(BuildContext context) async {
    await showAnimatedDialog<bool>(
      context: context,
      builder: (dialogContext) => const _UserProfileEditorDialog(),
    );
  }
}

/// 用户画像编辑/预览弹窗。复用 [showAnimatedDialog] 因此动画行为与全局
/// "弹窗动画"设置完全保持一致。
///
/// 提供：预览当前画像内容、编辑保存、清空（删除）三种操作。底层落地仍
/// 走 [MemoryController.upsertUserProfile] / [MemoryController.deleteMemory]，
/// 所以保存后内存模块、自我学习、提示词构造层都会自动同步。
class _UserProfileEditorDialog extends StatefulWidget {
  const _UserProfileEditorDialog();

  @override
  State<_UserProfileEditorDialog> createState() =>
      _UserProfileEditorDialogState();
}

class _UserProfileEditorDialogState extends State<_UserProfileEditorDialog> {
  late final TextEditingController _contentController;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final controller = context.read<MemoryController>();
    _contentController = TextEditingController(
      text: controller.userProfile?.content ?? '',
    );
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasExisting = context
            .read<MemoryController>()
            .userProfile
            ?.content
            .trim()
            .isNotEmpty ??
        false;

    return PopScope(
      canPop: !_isSaving,
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.account_circle_outlined,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _localizedText(
                          context,
                          zh: '用户画像 · User Profile',
                          en: 'User Profile',
                        ),
                        style: theme.textTheme.headlineSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _localizedText(
                    context,
                    zh:
                        '用一段话描述你希望 AI 长期记住的偏好、关注领域与交流风格。该画像将作为系统提示词的固定上下文模块，跨所有线程模板自动生效；自我学习也会基于本字段做增量优化。',
                    en:
                        'Describe in one paragraph the long-term preferences, focus areas and communication style you want the AI to remember. The profile is injected as a fixed system-prompt module across all thread templates; self-learning incrementally refines it.',
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: TextField(
                    controller: _contentController,
                    enabled: !_isSaving,
                    expands: true,
                    maxLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: InputDecoration(
                      labelText: _localizedText(
                        context,
                        zh: '画像内容',
                        en: 'Profile Content',
                      ),
                      alignLabelWithHint: true,
                      hintText: _localizedText(
                        context,
                        zh: '示例：语言风格轻松可爱；关注娱乐圈明星、技术新闻；偏好亲切自然、不啰嗦的回复…',
                        en:
                            'e.g. casual & warm tone; loves entertainment industry & tech news; prefers concise replies…',
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.error,
                    ),
                  ),
                ],
                if (_isSaving) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (hasExisting)
                      TextButton.icon(
                        onPressed: _isSaving ? null : _handleClear,
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: colorScheme.error,
                        ),
                        label: Text(
                          _localizedText(context, zh: '清空画像', en: 'Clear'),
                          style: TextStyle(color: colorScheme.error),
                        ),
                      ),
                    const Spacer(),
                    OutlinedButton(
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: Text(
                        _localizedText(context, zh: '取消', en: 'Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _isSaving ? null : _handleSave,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(
                        _localizedText(context, zh: '保存', en: 'Save'),
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
    final content = _contentController.text;
    if (content.trim().isEmpty) {
      setState(() {
        _errorMessage = _localizedText(
          context,
          zh: '画像内容不能为空，若要清空请使用左侧"清空画像"。',
          en: 'Profile content cannot be empty. Use "Clear" to remove it.',
        );
      });
      return;
    }
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      await context.read<MemoryController>().upsertUserProfile(
            content: content,
          );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = '$error';
      });
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _handleClear() async {
    final controller = context.read<MemoryController>();
    final entry = controller.userProfile;
    if (entry == null) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      await controller.deleteMemory(entry);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = '$error';
      });
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }
}
