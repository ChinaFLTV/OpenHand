part of 'settings_view.dart';

/// "用户画像" 设置项触发按钮，位于 AI 设置 → 会话设置。
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

class _UserProfileSettingsButtonState extends State<_UserProfileSettingsButton>
    with OpenHandHoverState<_UserProfileSettingsButton> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final memoryController = context.watch<MemoryController>();
    final profile = memoryController.userProfile;
    final hasProfile = profile != null && profile.content.trim().isNotEmpty;
    final motionEnabled = _settingsMotionEnabled(context);
    final preview = hasProfile
        ? _previewContent(profile.content)
        : openHandLocalizedText(
            context,
            zh: '未设置 — 点击建立你的全局用户画像',
            en: 'Not set — click to build your global profile',
          );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: MouseRegion(
        onEnter: (_) => setOpenHandHovered(true),
        onExit: (_) => setOpenHandHovered(false),
        child: MicroPressFeedback(
          child: Material(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: kOpenHandBorderRadius14,
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
                        borderRadius: kOpenHandBorderRadius12,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.account_circle_outlined,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    kOpenHandHGap14,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Text(
                                openHandLocalizedText(
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
                              kOpenHandHGap8,
                              if (hasProfile)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.tertiaryContainer,
                                    borderRadius: kOpenHandPillBorderRadius,
                                  ),
                                  child: Text(
                                    openHandLocalizedText(
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
                          kOpenHandGap6,
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
                    kOpenHandHGap8,
                    AnimatedSlide(
                      offset: Offset(
                        openHandHovered && motionEnabled ? 0.18 : 0,
                        0,
                      ),
                      duration: openHandMotionDuration(context, kOpenHandMotion180),
                      curve: kOpenHandSwitchInCurve,
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
    final flat = collapseInlineWhitespace(content);
    return clipTextByCodeUnits(flat, 160, suffix: '…');
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
  final ValueNotifier<int> _errorPulse = ValueNotifier<int>(0);

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
    _errorPulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasExisting =
        context
            .read<MemoryController>()
            .userProfile
            ?.content
            .trim()
            .isNotEmpty ??
        false;

    return PopScope(
      canPop: !_isSaving,
      child: buildOpenHandResponsiveDialogShell(
        context: context,
        maxWidth: kOpenHandDialogWidthStandard,
        safeAreaMinimum: kOpenHandDialogDefaultInsetPadding,
        child: Stack(
          children: [
            Padding(
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
                      kOpenHandHGap10,
                      Expanded(
                        child: Text(
                          openHandLocalizedText(
                            context,
                            zh: '用户画像 · User Profile',
                            en: 'User Profile',
                          ),
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
                    ],
                  ),
                  kOpenHandGap6,
                  Text(
                    openHandLocalizedText(
                      context,
                      zh: '用一段话描述你希望 AI 长期记住的偏好、关注领域与交流风格。该画像将作为系统提示词的固定上下文模块，跨所有线程模板自动生效；自我学习也会基于本字段做增量优化。',
                      en: 'Describe in one paragraph the long-term preferences, focus areas and communication style you want the AI to remember. The profile is injected as a fixed system-prompt module across all thread templates; self-learning incrementally refines it.',
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  kOpenHandGap16,
                  Expanded(
                    child: TextField(
                      controller: _contentController,
                      enabled: !_isSaving,
                      expands: true,
                      maxLength: UserMemoryEntry.maxContentCharacters,
                      maxLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: InputDecoration(
                        labelText: openHandLocalizedText(
                          context,
                          zh: '画像内容',
                          en: 'Profile Content',
                        ),
                        alignLabelWithHint: true,
                        hintText: openHandLocalizedText(
                          context,
                          zh: '示例：语言风格轻松可爱；关注娱乐圈明星、技术新闻；偏好亲切自然、不啰嗦的回复…',
                          en: 'e.g. casual & warm tone; loves entertainment industry & tech news; prefers concise replies…',
                        ),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  OpenHandDialogErrorText(message: _errorMessage),
                  OpenHandDialogBusyBar(busy: _isSaving),
                  kOpenHandGap16,
                  SizedBox(
                    width: double.infinity,
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      runAlignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 10,
                      children: [
                        if (hasExisting)
                          OpenHandDialogActionButton.destructive(
                            onPressed: _isSaving ? null : _handleClear,
                            icon: Icons.delete_outline_rounded,
                            label: openHandLocalizedText(
                              context,
                              zh: '清空画像',
                              en: 'Clear',
                            ),
                          ),
                        OpenHandDialogActionButton.secondary(
                          onPressed: _isSaving
                              ? null
                              : () => Navigator.of(context).pop(false),
                          label: openHandCancelLabel(context),
                        ),
                        OpenHandDialogActionButton.primary(
                          onPressed: _isSaving ? null : _handleSave,
                          icon: Icons.save_outlined,
                          busy: _isSaving,
                          label: openHandSaveLabel(context),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: HighlightPulse(
                  signal: _errorPulse,
                  color: OpenHandStatusColors.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleSave() async {
    final content = _contentController.text;
    final failureMessage = openHandLocalizedText(
      context,
      zh: '保存用户画像失败，请稍后重试。',
      en: 'Failed to save the profile. Please try again.',
    );
    if (content.trim().isEmpty) {
      setState(() {
        _errorMessage = openHandLocalizedText(
          context,
          zh: '画像内容不能为空，若要清空请使用左侧"清空画像"。',
          en: 'Profile content cannot be empty. Use "Clear" to remove it.',
        );
      });
      _errorPulse.value++;
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
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = failureMessage;
      });
      _errorPulse.value++;
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
    final failureMessage = openHandLocalizedText(
      context,
      zh: '清空画像失败。',
      en: 'Failed to clear the profile.',
    );
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '清空用户画像？',
        en: 'Clear user profile?',
      ),
      message: openHandLocalizedText(
        context,
        zh: '此操作将永久删除当前用户画像。',
        en: 'This permanently deletes the current user profile.',
      ),
      cancelLabel: openHandCancelLabel(context),
      confirmLabel: openHandClearLabel(context),
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      final deleted = await controller.deleteMemory(entry);
      if (!deleted) throw StateError(failureMessage);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = failureMessage;
      });
      _errorPulse.value++;
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }
}
