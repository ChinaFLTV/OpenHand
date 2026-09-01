part of 'harness_session_dashboard.dart';

class _HeComposer extends StatelessWidget {
  const _HeComposer({
    required this.isCollapsed,
    required this.onCollapsedChanged,
    required this.autoFollowEnabled,
    required this.onToggleAutoFollow,
    required this.fullAccessPermission,
    required this.onToggleFullAccessPermission,
    required this.manualPhaseEnabled,
    required this.manualPhaseTitle,
    required this.manualPhaseController,
    required this.manualPhaseFocusNode,
    required this.manualPhaseHelperText,
    required this.manualPhaseHintText,
    required this.primaryActionLabel,
    required this.primaryActionIcon,
    required this.primaryActionEnabled,
    required this.onPrimaryAction,
    this.isManualReviewPhase = false,
    this.onReviewPass,
    this.onReviewFail,
    this.reviewSubmitting = false,
  });

  final bool isCollapsed;
  final ValueChanged<bool> onCollapsedChanged;
  final bool autoFollowEnabled;
  final VoidCallback onToggleAutoFollow;
  final bool fullAccessPermission;
  final ValueChanged<bool> onToggleFullAccessPermission;
  final bool manualPhaseEnabled;
  final String manualPhaseTitle;
  final TextEditingController manualPhaseController;
  final FocusNode manualPhaseFocusNode;
  final String manualPhaseHelperText;
  final String manualPhaseHintText;
  final String primaryActionLabel;
  final IconData primaryActionIcon;
  final bool primaryActionEnabled;
  final VoidCallback onPrimaryAction;

  final bool isManualReviewPhase;
  final VoidCallback? onReviewPass;
  final VoidCallback? onReviewFail;
  final bool reviewSubmitting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final disabledFg = colorScheme.onSurface.withValues(alpha: 0.38);
    final disabledBorder = colorScheme.outlineVariant.withValues(alpha: 0.48);
    final disabledBg = colorScheme.surfaceContainerHighest.withValues(
      alpha: 0.78,
    );
    final defaultAccessLabel = openHandDefaultAccessLabel(context);
    final fullAccessLabel = openHandFullAccessLabel(context);

    Widget disabledOutlinedButton({
      required IconData icon,
      required String label,
    }) {
      return SizedBox(
        height: 52,
        child: OutlinedButton.icon(
          onPressed: null,
          icon: Icon(icon, size: 18),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            disabledForegroundColor: disabledFg,
            side: BorderSide(color: disabledBorder),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            backgroundColor: disabledBg,
            shape: const RoundedRectangleBorder(
              borderRadius: kOpenHandBorderRadius16,
            ),
          ),
        ),
      );
    }

    final buttonFg = fullAccessPermission
        ? OpenHandStatusColors.warning
        : colorScheme.onSurfaceVariant;
    final buttonBg = fullAccessPermission
        ? OpenHandConsolePalette.warning.withValues(alpha: 0.15)
        : colorScheme.surfaceContainerHighest;
    final buttonBorderColor = fullAccessPermission
        ? OpenHandStatusColors.warning.withValues(alpha: 0.5)
        : colorScheme.outlineVariant;
    final permissionButton = SizedBox(
      height: 52,
      child: Builder(
        builder: (btnContext) {
          return OutlinedButton(
            onPressed: () {
              showAnimatedAnchoredPopupMenu<bool>(
                context: btnContext,
                items: [
                  PopupMenuItem<bool>(
                    value: false,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.admin_panel_settings_outlined,
                          size: 20,
                        ),
                        kOpenHandHGap12,
                        Expanded(child: Text(defaultAccessLabel)),
                        if (!fullAccessPermission)
                          const Icon(Icons.check_rounded, size: 20)
                        else
                          kOpenHandHGap20,
                      ],
                    ),
                  ),
                  PopupMenuItem<bool>(
                    value: true,
                    child: Row(
                      children: [
                        const Icon(Icons.gpp_maybe_outlined, size: 20),
                        kOpenHandHGap12,
                        Expanded(child: Text(fullAccessLabel)),
                        if (fullAccessPermission)
                          const Icon(Icons.check_rounded, size: 20)
                        else
                          kOpenHandHGap20,
                      ],
                    ),
                  ),
                ],
              ).then((value) {
                if (!btnContext.mounted || value == null) return;
                onToggleFullAccessPermission(value);
              });
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              backgroundColor: buttonBg,
              foregroundColor: buttonFg,
              side: BorderSide(color: buttonBorderColor),
              shape: const RoundedRectangleBorder(
                borderRadius: kOpenHandBorderRadius16,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  fullAccessPermission
                      ? Icons.gpp_maybe_outlined
                      : Icons.admin_panel_settings_outlined,
                  size: 18,
                  color: buttonFg,
                ),
                kOpenHandHGap8,
                Text(
                  fullAccessPermission ? fullAccessLabel : defaultAccessLabel,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                kOpenHandHGap4,
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: buttonFg,
                ),
              ],
            ),
          );
        },
      ),
    );

    final manualPhaseTitleStyle = theme.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w700,
      color: colorScheme.primary,
    );
    final manualPhaseHelperStyle = theme.textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
      height: 1.45,
    );
    final manualPhaseHintStyle = theme.textTheme.bodyMedium?.copyWith(
      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
    );
    final manualPhaseInputStyle = theme.textTheme.bodyMedium?.copyWith(
      height: 1.45,
    );

    double measureTextHeight(String text, TextStyle? style, double maxWidth) {
      if (!maxWidth.isFinite || maxWidth <= 0) {
        return 0;
      }

      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
      )..layout(maxWidth: maxWidth);

      return painter.size.height;
    }

    final expandedContent = AnimatedContainer(
      duration: openHandMotionDuration(context, kOpenHandMotion260),
      curve: kOpenHandEmphasizedCurve,
      width: double.infinity,
      height: manualPhaseEnabled ? 176 : 80,
      decoration: BoxDecoration(
        color: manualPhaseEnabled
            ? colorScheme.surfaceContainerLow
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: kOpenHandBorderRadius16,
        border: Border.all(
          color: manualPhaseEnabled
              ? colorScheme.primary.withValues(alpha: 0.28)
              : disabledBorder,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: manualPhaseEnabled
          ? LayoutBuilder(
              builder: (context, constraints) {
                const titleGap = 6.0;
                const editorGap = 10.0;
                const minEditorHeight = 48.0;

                final titleHeight = measureTextHeight(
                  manualPhaseTitle,
                  manualPhaseTitleStyle,
                  constraints.maxWidth,
                );
                final helperHeight = measureTextHeight(
                  manualPhaseHelperText,
                  manualPhaseHelperStyle,
                  constraints.maxWidth,
                );
                final canShowHelper =
                    constraints.maxHeight >=
                    titleHeight + titleGap + helperHeight;
                final reservedHeight =
                    titleHeight + (canShowHelper ? titleGap + helperHeight : 0);
                final remainingHeight = constraints.maxHeight - reservedHeight;
                final canShowEditor =
                    remainingHeight >= editorGap + minEditorHeight;
                final editorHeight = canShowEditor
                    ? (remainingHeight - editorGap).clamp(0.0, double.infinity)
                    : 0.0;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      manualPhaseTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: manualPhaseTitleStyle,
                    ),
                    if (canShowHelper) ...[
                      const SizedBox(height: titleGap),
                      Text(
                        manualPhaseHelperText,
                        style: manualPhaseHelperStyle,
                      ),
                    ],
                    if (canShowEditor) ...[
                      const SizedBox(height: editorGap),
                      SizedBox(
                        height: editorHeight,
                        child: TextField(
                          controller: manualPhaseController,
                          focusNode: manualPhaseFocusNode,
                          maxLines: null,
                          expands: true,
                          inputFormatters: <TextInputFormatter>[
                            LengthLimitingTextInputFormatter(
                              kHarnessManualPhaseInputMaxCharacters,
                            ),
                          ],
                          textAlignVertical: TextAlignVertical.top,
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            isCollapsed: true,
                            hintText: manualPhaseHintText,
                            hintStyle: manualPhaseHintStyle,
                          ),
                          style: manualPhaseInputStyle,
                        ),
                      ),
                    ],
                  ],
                );
              },
            )
          : Align(
              alignment: Alignment.topLeft,
              child: Text(
                openHandLocalizedText(
                  context,
                  zh: 'Harness Engineering 使用自动化流水线，不支持手动输入',
                  zhHant: 'Harness Engineering 使用自動化流水線，不支援手動輸入',
                  en: 'Harness Engineering uses an automated pipeline; manual input is not available',
                  fr: 'Harness Engineering utilise un pipeline automatisé ; la saisie manuelle n’est pas disponible',
                  de: 'Harness Engineering nutzt eine automatisierte Pipeline; manuelle Eingabe ist nicht verfügbar',
                  ja: 'Harness Engineering は自動パイプラインを使用するため、手動入力は利用できません',
                ),
                style: theme.textTheme.bodyMedium?.copyWith(color: disabledFg),
              ),
            ),
    );

    final actionRow = Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                disabledOutlinedButton(icon: Icons.hub_outlined, label: '--'),
                kOpenHandHGap10,
                disabledOutlinedButton(
                  icon: Icons.attach_file_rounded,
                  label: openHandLocalizedText(
                    context,
                    zh: '附件',
                    zhHant: '附件',
                    en: 'Attach',
                    fr: 'Joindre',
                    de: 'Anhängen',
                    ja: '添付',
                  ),
                ),
                kOpenHandHGap10,
                permissionButton,
                kOpenHandHGap10,
                disabledOutlinedButton(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: openHandLocalizedText(
                    context,
                    zh: '聊天模式',
                    zhHant: '聊天模式',
                    en: 'Chat Mode',
                    fr: 'Mode chat',
                    de: 'Chatmodus',
                    ja: 'チャットモード',
                  ),
                ),
                kOpenHandHGap10,
              ],
            ),
          ),
        ),
        Tooltip(
          message: isCollapsed
              ? openHandLocalizedText(
                  context,
                  zh: '展开输入框',
                  zhHant: '展開輸入框',
                  en: 'Expand Composer',
                  fr: 'Développer la zone de saisie',
                  de: 'Eingabebereich erweitern',
                  ja: '入力欄を展開',
                )
              : openHandLocalizedText(
                  context,
                  zh: '折叠输入框',
                  zhHant: '摺疊輸入框',
                  en: 'Collapse Composer',
                  fr: 'Réduire la zone de saisie',
                  de: 'Eingabebereich einklappen',
                  ja: '入力欄を折りたたむ',
                ),
          child: SizedBox(
            width: 52,
            height: 52,
            child: FilledButton(
              onPressed: () => onCollapsedChanged(!isCollapsed),
              style: FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(52, 52),
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
              ),
              child: AnimatedRotation(
                turns: isCollapsed ? 0.5 : 0,
                duration: openHandMotionDuration(context, kOpenHandMotion220),
                curve: kOpenHandSwitchInCurve,
                child: const Icon(Icons.keyboard_arrow_down_rounded),
              ),
            ),
          ),
        ),
        kOpenHandHGap10,
        SizedBox(
          width: 52,
          height: 52,
          child: FilledButton(
            onPressed: onToggleAutoFollow,
            style: FilledButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(52, 52),
              backgroundColor: autoFollowEnabled
                  ? colorScheme.primary
                  : colorScheme.surfaceContainerHighest,
              foregroundColor: autoFollowEnabled
                  ? colorScheme.onPrimary
                  : colorScheme.onSurfaceVariant,
              side: autoFollowEnabled
                  ? null
                  : BorderSide(color: colorScheme.outlineVariant),
            ),
            child: Icon(
              autoFollowEnabled
                  ? Icons.vertical_align_bottom_rounded
                  : Icons.vertical_align_bottom_outlined,
            ),
          ),
        ),
        kOpenHandHGap10,
        // 人工审查阶段直接显示通过和驳回操作。
        if (manualPhaseEnabled && isManualReviewPhase) ...[
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: (primaryActionEnabled && !reviewSubmitting)
                  ? onReviewFail
                  : null,
              icon: Icon(
                reviewSubmitting
                    ? Icons.hourglass_top_rounded
                    : Icons.thumb_down_alt_rounded,
                size: 18,
              ),
              label: Text(
                reviewSubmitting
                    ? _harnessSessionSubmittingLabel(context)
                    : openHandLocalizedText(
                        context,
                        zh: '验收不通过',
                        zhHant: '驗收不通過',
                        en: 'Fail',
                        fr: 'Refuser',
                        de: 'Ablehnen',
                        ja: '不合格',
                      ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: colorScheme.error,
                side: BorderSide(
                  color: colorScheme.error.withValues(alpha: 0.5),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: const RoundedRectangleBorder(
                  borderRadius: kOpenHandBorderRadius16,
                ),
              ),
            ),
          ),
          kOpenHandHGap10,
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: (primaryActionEnabled && !reviewSubmitting)
                  ? onReviewPass
                  : null,
              icon: Icon(
                reviewSubmitting
                    ? Icons.hourglass_top_rounded
                    : Icons.thumb_up_alt_rounded,
                size: 18,
              ),
              label: Text(
                reviewSubmitting
                    ? _harnessSessionSubmittingLabel(context)
                    : openHandLocalizedText(
                        context,
                        zh: '验收通过',
                        zhHant: '驗收通過',
                        en: 'Pass',
                        fr: 'Valider',
                        de: 'Bestehen',
                        ja: '合格',
                      ),
              ),
            ),
          ),
        ] else
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: primaryActionEnabled ? onPrimaryAction : null,
              icon: Icon(primaryActionIcon, size: 18),
              label: Text(primaryActionLabel),
            ),
          ),
      ],
    );

    return Card(
      color: colorScheme.surfaceContainerHigh,
      child: AnimatedContainer(
        duration: openHandMotionDuration(context, kOpenHandMotion260),
        curve: kOpenHandEmphasizedCurve,
        padding: EdgeInsets.fromLTRB(18, 14, 18, isCollapsed ? 10 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OpenHandCollapsibleFade(
              collapsed: isCollapsed,
              child: expandedContent,
            ),
            AnimatedContainer(
              duration: openHandMotionDuration(context, kOpenHandMotion260),
              curve: kOpenHandEmphasizedCurve,
              height: isCollapsed ? 0 : 14,
            ),
            actionRow,
          ],
        ),
      ),
    );
  }
}

class _HePhaseApprovalBanner extends StatelessWidget {
  const _HePhaseApprovalBanner({
    required this.nextPhase,
    this.approvalIssue,
    required this.manualPhaseEnabled,
    required this.hasQueuedManualPhaseInput,
    required this.manualPhaseActionLabel,
    required this.manualPhaseSwitchBackLabel,
    required this.manualPhaseActiveDescription,
    required this.manualPhaseQueuedDescription,
    required this.manualPhaseIcon,
    this.onManualPhaseToggle,
    required this.onApprove,
    required this.onReject,
  });

  final HarnessPhase nextPhase;
  final String? approvalIssue;
  final bool manualPhaseEnabled;
  final bool hasQueuedManualPhaseInput;
  final String manualPhaseActionLabel;
  final String manualPhaseSwitchBackLabel;
  final String manualPhaseActiveDescription;
  final String manualPhaseQueuedDescription;
  final IconData manualPhaseIcon;
  final VoidCallback? onManualPhaseToggle;
  final VoidCallback? onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    const accent = _hePausedTone;
    final backgroundColor = Color.alphaBlend(
      accent.withValues(
        alpha: theme.brightness == Brightness.dark ? 0.24 : 0.12,
      ),
      colorScheme.surface,
    );
    final phaseName = _heHarnessPhaseLabel(context, nextPhase);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: kOpenHandBorderRadius16,
        border: Border.all(color: accent.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.pause_circle_filled_rounded,
                size: 20,
                color: accent,
              ),
              kOpenHandHGap10,
              Expanded(
                child: Text(
                  openHandLocalizedText(
                    context,
                    zh: '即将推进到下一阶段：$phaseName',
                    zhHant: '即將推進到下一階段：$phaseName',
                    en: 'Ready to advance to next phase: $phaseName',
                    fr: 'Prêt à passer à la phase suivante : $phaseName',
                    de: 'Bereit für die nächste Phase: $phaseName',
                    ja: '次のフェーズへ進めます：$phaseName',
                  ),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          kOpenHandGap6,
          Text(
            openHandLocalizedText(
              context,
              zh: '请确认是否继续执行，或中止流水线。',
              zhHant: '請確認是否繼續執行，或中止流水線。',
              en: 'Confirm to continue, or abort the pipeline.',
              fr: 'Confirmez pour continuer ou interrompre le pipeline.',
              de: 'Bestätigen zum Fortfahren oder Pipeline abbrechen.',
              ja: '続行するか、パイプラインを中止してください。',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (onManualPhaseToggle != null && manualPhaseEnabled) ...[
            kOpenHandGap12,
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  accent.withValues(
                    alpha: theme.brightness == Brightness.dark ? 0.16 : 0.10,
                  ),
                  colorScheme.surface,
                ),
                borderRadius: kOpenHandBorderRadius16,
                border: Border.all(color: accent.withValues(alpha: 0.24)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(manualPhaseIcon, size: 16, color: accent),
                  ),
                  kOpenHandHGap8,
                  Expanded(
                    child: Text(
                      manualPhaseActiveDescription,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (onManualPhaseToggle != null &&
              hasQueuedManualPhaseInput) ...[
            kOpenHandGap12,
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  colorScheme.primary.withValues(
                    alpha: theme.brightness == Brightness.dark ? 0.14 : 0.08,
                  ),
                  colorScheme.surface,
                ),
                borderRadius: kOpenHandBorderRadius16,
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.20),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.history_toggle_off_rounded,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                  kOpenHandHGap8,
                  Expanded(
                    child: Text(
                      manualPhaseQueuedDescription,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (approvalIssue != null) ...[
            kOpenHandGap12,
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  _heFailedTone.withValues(
                    alpha: theme.brightness == Brightness.dark ? 0.18 : 0.08,
                  ),
                  colorScheme.surface,
                ),
                borderRadius: kOpenHandBorderRadius16,
                border: Border.all(
                  color: _heFailedTone.withValues(alpha: 0.24),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.error_outline_rounded,
                      size: 16,
                      color: _heFailedTone,
                    ),
                  ),
                  kOpenHandHGap8,
                  Expanded(
                    child: Text(
                      approvalIssue!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          kOpenHandGap12,
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              if (onManualPhaseToggle != null) ...[
                SizedBox(
                  height: kOpenHandDialogActionButtonHeight,
                  child: OutlinedButton.icon(
                    onPressed: onManualPhaseToggle,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accent,
                      side: BorderSide(color: accent.withValues(alpha: 0.34)),
                    ),
                    icon: Icon(
                      manualPhaseEnabled
                          ? Icons.smart_toy_outlined
                          : manualPhaseIcon,
                      size: 18,
                    ),
                    label: Text(
                      manualPhaseEnabled
                          ? manualPhaseSwitchBackLabel
                          : manualPhaseActionLabel,
                    ),
                  ),
                ),
              ],
              SizedBox(
                width: kOpenHandDialogActionButtonWidth,
                height: kOpenHandDialogActionButtonHeight,
                child: OutlinedButton(
                  onPressed: onReject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colorScheme.error,
                    side: BorderSide(
                      color: colorScheme.error.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    openHandLocalizedText(
                      context,
                      zh: '中止',
                      zhHant: '中止',
                      en: 'Abort',
                      fr: 'Interrompre',
                      de: 'Abbrechen',
                      ja: '中止',
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: kOpenHandDialogActionButtonWidth,
                height: kOpenHandDialogActionButtonHeight,
                child: FilledButton.icon(
                  onPressed: onApprove,
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: Text(openHandContinueLabel(context)),
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HePendingPhaseEditor extends StatelessWidget {
  const _HePendingPhaseEditor({
    required this.roleConfig,
    required this.onChanged,
  });

  final HarnessRoleConfig roleConfig;
  final ValueChanged<HarnessRoleConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cliNames = kHarnessCliCatalog
        .where((c) => c.supportsHeadless)
        .toList();
    final settingsController = Provider.of<SettingsController?>(context);
    final settingsModels =
        settingsController?.aiModels ?? const <AiModelConfig>[];
    final configuredAiModelConfigId = roleConfig.aiModelConfigId?.trim();
    final hasConfiguredAiModelConfig =
        configuredAiModelConfigId != null &&
        configuredAiModelConfigId.isNotEmpty;
    final hasMatchingAiModelConfig =
        hasConfiguredAiModelConfig &&
        settingsModels.any((item) => item.id == configuredAiModelConfigId);
    final effectiveAiModelConfigId = _hePreferredAiModelConfigId(
      settingsModels: settingsModels,
      configuredId: roleConfig.aiModelConfigId,
      fallbackId: settingsController?.selectedAiModelId,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.65),
        borderRadius: kOpenHandBorderRadius16,
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            openHandLocalizedText(
              context,
              zh: '更改执行配置',
              zhHant: '變更執行設定',
              en: 'Change Execution Config',
              fr: 'Modifier la configuration d’exécution',
              de: 'Ausführungskonfiguration ändern',
              ja: '実行設定を変更',
            ),
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colorScheme.primary,
            ),
          ),
          kOpenHandGap8,
          Row(
            children: [
              ChoiceChip(
                label: Text('CLI', style: theme.textTheme.bodySmall),
                selected: roleConfig.isCliMode,
                onSelected: (selected) {
                  if (selected) {
                    onChanged(
                      roleConfig.copyWith(
                        executionMode: HarnessExecutionMode.cli,
                      ),
                    );
                  }
                },
                visualDensity: VisualDensity.compact,
              ),
              kOpenHandHGap8,
              ChoiceChip(
                label: Text('URL/API', style: theme.textTheme.bodySmall),
                selected: roleConfig.isUrlMode,
                onSelected: (selected) {
                  if (selected) {
                    onChanged(
                      roleConfig.copyWith(
                        executionMode: HarnessExecutionMode.url,
                        aiModelConfigId: effectiveAiModelConfigId,
                        clearAiModelConfigId:
                            effectiveAiModelConfigId == null &&
                            !hasConfiguredAiModelConfig,
                      ),
                    );
                  }
                },
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          kOpenHandGap8,
          if (roleConfig.isUrlMode)
            _HeUrlModelField(
              settingsModels: settingsModels,
              roleConfig: roleConfig,
              hasConfiguredAiModelConfig: hasConfiguredAiModelConfig,
              hasMatchingAiModelConfig: hasMatchingAiModelConfig,
              onChanged: onChanged,
            )
          else
            Row(
              children: [
                Expanded(
                  child: AnimatedDropdownButtonFormField<String>(
                    initialValue:
                        cliNames.any((c) => c.name == roleConfig.cliName)
                        ? roleConfig.cliName
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'CLI',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(borderRadius: _br12),
                    ),
                    items: cliNames.map((cli) {
                      return DropdownMenuItem(
                        value: cli.name,
                        child: Text(
                          cli.name,
                          style: theme.textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      final currentModelId = roleConfig.modelId.trim();
                      onChanged(
                        roleConfig.copyWith(
                          cliName: value,
                          modelId: currentModelId,
                        ),
                      );
                    },
                  ),
                ),
                kOpenHandHGap10,
                Expanded(
                  child: _HeModelDropdown(
                    roleConfig: roleConfig,
                    onChanged: onChanged,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

String _harnessSessionSubmittingLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '提交中',
    zhHant: '提交中',
    en: 'Submitting',
    fr: 'Envoi',
    de: 'Wird gesendet',
    ja: '送信中',
  );
}
