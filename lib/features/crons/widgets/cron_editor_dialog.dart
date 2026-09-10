import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../app/model/cron_config.dart';
import '../../../app/support/openhand_notification_service.dart';
import '../../../app/theme/openhand_status_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/animated_menu.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/oh_pill.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_form_fields.dart';
import '../../../shared/ui/openhand_reveal_switcher.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/openhand_typography.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/platform_shell.dart';
import '../../../shared/util/text_normalization.dart';
import '../crons_controller.dart';
import '../model/cron_parser.dart';

const double _kCronEditorFieldHeight = 48;
const double _kCronPolicyTwoColumnMinWidth = 560;
const Duration _kCronNotificationTestGap = Duration(milliseconds: 520);

Future<void> showCronEditorDialog(BuildContext context, {CronEntry? existing}) {
  return showAnimatedDialog(
    context: context,
    builder: (_) => _CronEditorDialog(existing: existing),
  );
}

class _CronEditorDialog extends StatefulWidget {
  const _CronEditorDialog({this.existing});

  final CronEntry? existing;

  @override
  State<_CronEditorDialog> createState() => _CronEditorDialogState();
}

enum _NotificationTestScenario { success, failure, timeout, all }

typedef _NotificationTestConfig = ({
  CronNotifyType type,
  CronNotifySeverity severity,
  bool soundEnabled,
  bool vibrationEnabled,
  String message,
  String label,
  String defaultBody,
});

class _CronEditorDialogState extends State<_CronEditorDialog> {
  static const Uuid _uuid = Uuid();

  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _scriptPathController;
  late final TextEditingController _scriptContentController;
  late final TextEditingController _timeoutController;
  late final TextEditingController _retryController;
  late final TextEditingController _tagsController;
  late final TextEditingController _workingDirController;
  late final TextEditingController _envController;
  late final TextEditingController _maxRetryDelayController;
  late final TextEditingController _onSuccessMsgController;
  late final TextEditingController _onFailureMsgController;
  late final TextEditingController _onTimeoutMsgController;
  late final TextEditingController _cronMinController;
  late final TextEditingController _cronHourController;
  late final TextEditingController _cronDomController;
  late final TextEditingController _cronMonController;
  late final TextEditingController _cronDowController;

  late CronScriptType _scriptType;
  late String? _runAsUser;
  late CronNotifyType _onSuccessNotify;
  late CronNotifyType _onFailureNotify;
  late CronNotifyType _onTimeoutNotify;
  late CronNotifySeverity _onSuccessSeverity;
  late CronNotifySeverity _onFailureSeverity;
  late CronNotifySeverity _onTimeoutSeverity;
  late bool _onSuccessSound;
  late bool _onFailureSound;
  late bool _onTimeoutSound;
  late bool _onSuccessVibration;
  late bool _onFailureVibration;
  late bool _onTimeoutVibration;
  late bool _collectAppMetadata;
  late bool _collectHostMetadata;
  late bool _collectEnvironmentSnapshot;

  bool _saving = false;
  String? _cronError;
  String? _formError;
  int _notificationTestGeneration = 0;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameController = TextEditingController(text: e?.name ?? '');
    _descriptionController = TextEditingController(text: e?.description ?? '');
    _scriptPathController = TextEditingController(text: e?.scriptPath ?? '');
    _scriptContentController = TextEditingController(
      text: e?.scriptContent ?? '',
    );
    _timeoutController = TextEditingController(
      text: '${e?.timeoutSeconds ?? kCronDefaultTimeoutSeconds}',
    );
    _retryController = TextEditingController(
      text: '${e?.retryCount ?? kCronDefaultRetryCount}',
    );
    _tagsController = TextEditingController(text: e?.tags.join(', ') ?? '');
    _workingDirController = TextEditingController(
      text: e?.workingDirectory ?? '',
    );
    _envController = TextEditingController(
      text:
          e?.environment.entries
              .map((en) => '${en.key}=${en.value}')
              .join('\n') ??
          '',
    );
    _maxRetryDelayController = TextEditingController(
      text: '${e?.maxRetryDelaySeconds ?? kCronDefaultRetryDelaySeconds}',
    );
    _onSuccessMsgController = TextEditingController(
      text: e?.onSuccessMessage ?? '',
    );
    _onFailureMsgController = TextEditingController(
      text: e?.onFailureMessage ?? '',
    );
    _onTimeoutMsgController = TextEditingController(
      text: e?.onTimeoutMessage ?? '',
    );

    final cronParts = (e?.cronExpression ?? kCronDefaultExpression).split(
      kInlineWhitespacePattern,
    );
    _cronMinController = TextEditingController(
      text: cronParts.isNotEmpty ? cronParts[0] : '*',
    );
    _cronHourController = TextEditingController(
      text: cronParts.length > 1 ? cronParts[1] : '*',
    );
    _cronDomController = TextEditingController(
      text: cronParts.length > 2 ? cronParts[2] : '*',
    );
    _cronMonController = TextEditingController(
      text: cronParts.length > 3 ? cronParts[3] : '*',
    );
    _cronDowController = TextEditingController(
      text: cronParts.length > 4 ? cronParts[4] : '*',
    );

    _scriptType = e?.scriptType ?? CronScriptType.command;
    _runAsUser = e?.runAsUser;
    _onSuccessNotify = e?.onSuccessNotify ?? CronNotifyType.log;
    _onFailureNotify = e?.onFailureNotify ?? CronNotifyType.system;
    _onTimeoutNotify = e?.onTimeoutNotify ?? CronNotifyType.system;
    _onSuccessSeverity = e?.onSuccessSeverity ?? CronNotifySeverity.success;
    _onFailureSeverity = e?.onFailureSeverity ?? CronNotifySeverity.error;
    _onTimeoutSeverity = e?.onTimeoutSeverity ?? CronNotifySeverity.warning;
    _onSuccessSound = e?.onSuccessPlaySound ?? false;
    _onFailureSound = e?.onFailurePlaySound ?? true;
    _onTimeoutSound = e?.onTimeoutPlaySound ?? true;
    _onSuccessVibration = e?.onSuccessVibrate ?? false;
    _onFailureVibration = e?.onFailureVibrate ?? true;
    _onTimeoutVibration = e?.onTimeoutVibrate ?? true;
    _collectAppMetadata = e?.collectAppMetadata ?? true;
    _collectHostMetadata = e?.collectHostMetadata ?? true;
    _collectEnvironmentSnapshot = e?.collectEnvironmentSnapshot ?? false;
  }

  @override
  void dispose() {
    _notificationTestGeneration++;
    _nameController.dispose();
    _descriptionController.dispose();
    _scriptPathController.dispose();
    _scriptContentController.dispose();
    _timeoutController.dispose();
    _retryController.dispose();
    _tagsController.dispose();
    _workingDirController.dispose();
    _envController.dispose();
    _maxRetryDelayController.dispose();
    _onSuccessMsgController.dispose();
    _onFailureMsgController.dispose();
    _onTimeoutMsgController.dispose();
    _cronMinController.dispose();
    _cronHourController.dispose();
    _cronDomController.dispose();
    _cronMonController.dispose();
    _cronDowController.dispose();
    super.dispose();
  }

  bool get _isEditing => widget.existing != null;
  AppLocalizations get l10n => AppLocalizations.of(context)!;

  String get _cronExpression =>
      '${_cronMinController.text.trim()} '
      '${_cronHourController.text.trim()} '
      '${_cronDomController.text.trim()} '
      '${_cronMonController.text.trim()} '
      '${_cronDowController.text.trim()}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final systemUsers = context.select<CronsController, List<String>>(
      (controller) => controller.systemUsers,
    );

    return OpenHandEditorDialogScaffold(
      title: _isEditing ? l10n.cronsEditCronJob : l10n.cronsNewCronJob,
      subtitle: _isEditing
          ? l10n.cronsEditorEditSubtitle
          : l10n.cronsEditorCreateSubtitle,
      icon: _isEditing ? Icons.edit_calendar_outlined : Icons.alarm_add_rounded,
      iconColor: colorScheme.primary,
      busy: _saving,
      closeEnabled: !_saving,
      canPop: !_saving,
      summary: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _nameController,
        builder: (context, value, _) => _buildSummaryBar(value.text),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          buildOpenHandDialogValidationMessage(context, message: _formError),
          if (_formError != null) kOpenHandGap12,
          _buildBasicsSection(),
          kOpenHandGap14,
          _buildTaskSection(theme, colorScheme),
          kOpenHandGap14,
          _buildScheduleSection(theme, colorScheme),
          kOpenHandGap14,
          _buildPolicySection(systemUsers),
          kOpenHandGap14,
          _buildRuntimeSection(theme, colorScheme),
          kOpenHandGap14,
          _buildContextSection(colorScheme),
          kOpenHandGap14,
          _buildNotificationSection(theme, colorScheme),
        ],
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          label: l10n.commonCancel,
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
        OpenHandDialogActionButton.primary(
          label: l10n.commonSave,
          busy: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }

  Widget _buildSummaryBar(String rawName) {
    final colorScheme = Theme.of(context).colorScheme;
    final name = rawName.trim();
    final expression = _cronExpression;
    final valid = _cronError == null && CronParser.isValid(expression);
    final nextRun = valid ? CronParser.nextRun(expression) : null;
    final nextLabel = !valid
        ? l10n.cronsNextRunUnknown
        : nextRun == null
        ? l10n.cronsNextRunUnknown
        : l10n.cronsNextRunAt(formatYearMonthDayHmLocal(nextRun));
    final typeIcon = _scriptType == CronScriptType.script
        ? Icons.description_outlined
        : Icons.terminal_rounded;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (name.isNotEmpty)
          OpenHandSummaryChip(
            icon: Icons.badge_outlined,
            label: name,
            foreground: colorScheme.onSecondaryContainer,
            background: colorScheme.secondaryContainer,
          ),
        OpenHandSummaryChip(
          icon: typeIcon,
          label: _scriptType.label(l10n),
          foreground: colorScheme.onPrimaryContainer,
          background: colorScheme.primaryContainer,
        ),
        OpenHandSummaryChip(
          icon: Icons.schedule_rounded,
          label: '${l10n.cronsExpressionPreview} $expression',
          foreground: colorScheme.onTertiaryContainer,
          background: colorScheme.tertiaryContainer,
          monospace: true,
        ),
        OpenHandSummaryChip(
          icon: valid ? Icons.upcoming_outlined : Icons.error_outline_rounded,
          label: nextLabel,
          foreground: valid
              ? colorScheme.onPrimaryContainer
              : colorScheme.onErrorContainer,
          background: valid
              ? OpenHandStatusColors.info.withValues(alpha: 0.18)
              : colorScheme.errorContainer,
        ),
      ],
    );
  }

  Widget _buildBasicsSection() {
    return OpenHandDialogSectionCard(
      icon: Icons.fingerprint_rounded,
      accent: Theme.of(context).colorScheme.primary,
      title: l10n.cronsSectionBasics,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _nameController,
            autofocus: !_isEditing,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: l10n.cronsFieldName,
              hintText: l10n.cronsFieldNameHint,
            ),
          ),
          kOpenHandGap12,
          TextField(
            controller: _descriptionController,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: l10n.cronsFieldDescription,
              hintText: l10n.commonOptional,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskSection(ThemeData theme, ColorScheme colorScheme) {
    return OpenHandDialogSectionCard(
      icon: Icons.terminal_rounded,
      accent: colorScheme.tertiary,
      title: l10n.cronsSectionTask,
      subtitle: l10n.cronsFieldType,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _CronTypeChoice(
                  selected: _scriptType == CronScriptType.command,
                  icon: Icons.terminal_rounded,
                  label: CronScriptType.command.label(l10n),
                  hint: l10n.cronsScriptTypeCommandHint,
                  onTap: () =>
                      setState(() => _scriptType = CronScriptType.command),
                ),
              ),
              kOpenHandHGap10,
              Expanded(
                child: _CronTypeChoice(
                  selected: _scriptType == CronScriptType.script,
                  icon: Icons.description_outlined,
                  label: CronScriptType.script.label(l10n),
                  hint: l10n.cronsScriptTypeScriptHint,
                  onTap: () =>
                      setState(() => _scriptType = CronScriptType.script),
                ),
              ),
            ],
          ),
          kOpenHandGap14,
          AnimatedSize(
            duration: openHandMotionDuration(context, kOpenHandMotion220),
            curve: kOpenHandSwitchInCurve,
            alignment: Alignment.topCenter,
            child: OpenHandCrossFadeSwitcher(
              child: _scriptType == CronScriptType.script
                  ? KeyedSubtree(
                      key: const ValueKey<String>('cron-script'),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _scriptPathController,
                              readOnly: true,
                              decoration: InputDecoration(
                                labelText: l10n.cronsFieldScriptFilePath,
                                hintText: l10n.cronsFieldScriptFilePathHint,
                              ),
                            ),
                          ),
                          kOpenHandHGap8,
                          FilledButton.tonal(
                            onPressed: _pickScriptFile,
                            child: Text(l10n.cronsBrowse),
                          ),
                        ],
                      ),
                    )
                  : KeyedSubtree(
                      key: const ValueKey<String>('cron-command'),
                      child: TextField(
                        controller: _scriptContentController,
                        maxLines: 6,
                        minLines: 3,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontFamily: kOpenHandMonospaceFontFamily,
                          fontSize: 13,
                        ),
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.all(12),
                          labelText: l10n.cronsFieldCommand,
                          hintText: Platform.isWindows
                              ? l10n.cronsFieldCommandHintWindows
                              : l10n.cronsFieldCommandHintShell,
                          hintStyle: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.5,
                            ),
                            fontFamily: kOpenHandMonospaceFontFamily,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleSection(ThemeData theme, ColorScheme colorScheme) {
    final fields =
        <({TextEditingController? controller, String label, bool frozen})>[
          (controller: null, label: l10n.cronParserFieldSecond, frozen: true),
          (
            controller: _cronMinController,
            label: l10n.cronParserFieldMinute,
            frozen: false,
          ),
          (
            controller: _cronHourController,
            label: l10n.cronParserFieldHour,
            frozen: false,
          ),
          (
            controller: _cronDomController,
            label: l10n.cronParserFieldDayOfMonthShort,
            frozen: false,
          ),
          (
            controller: _cronMonController,
            label: l10n.cronParserFieldMonth,
            frozen: false,
          ),
          (
            controller: _cronDowController,
            label: l10n.cronParserFieldDayOfWeekShort,
            frozen: false,
          ),
        ];

    return OpenHandDialogSectionCard(
      icon: Icons.schedule_rounded,
      accent: OpenHandStatusColors.info,
      title: l10n.cronsSectionSchedule,
      subtitle: l10n.cronsCronSchedule,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: kOpenHandBorderRadius18,
              border: Border.all(
                color: _cronError != null
                    ? colorScheme.error.withValues(alpha: 0.5)
                    : colorScheme.outlineVariant.withValues(alpha: 0.7),
              ),
            ),
            child: Row(
              children: [
                for (var i = 0; i < fields.length; i++) ...[
                  if (i > 0)
                    SizedBox(
                      height: 58,
                      child: VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.55,
                        ),
                      ),
                    ),
                  Expanded(
                    child: _cronComposerCell(
                      theme: theme,
                      colorScheme: colorScheme,
                      controller: fields[i].controller,
                      label: fields[i].label,
                      frozen: fields[i].frozen,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_cronError != null) ...[
            kOpenHandGap8,
            Text(
              _cronError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.error,
              ),
            ),
          ],
          kOpenHandGap8,
          Text(
            l10n.cronsCronScheduleHelper,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cronComposerCell({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required TextEditingController? controller,
    required String label,
    required bool frozen,
  }) {
    final textStyle = theme.textTheme.bodyMedium?.copyWith(
      fontFamily: kOpenHandMonospaceFontFamily,
      fontWeight: FontWeight.w700,
      color: frozen
          ? colorScheme.onSurfaceVariant.withValues(alpha: 0.42)
          : colorScheme.onSurface,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Column(
        children: [
          SizedBox(
            height: 36,
            child: frozen
                ? Center(child: Text(kCronFrozenSecondField, style: textStyle))
                : TextField(
                    controller: controller,
                    textAlign: TextAlign.center,
                    style: textStyle,
                    decoration: const InputDecoration(
                      isDense: true,
                      filled: false,
                      fillColor: Colors.transparent,
                      hoverColor: Colors.transparent,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                    onChanged: (_) => _validateCron(),
                  ),
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPolicySection(List<String> systemUsers) {
    return OpenHandDialogSectionCard(
      icon: Icons.tune_rounded,
      accent: OpenHandStatusColors.warning,
      title: l10n.cronsSectionPolicy,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final twoCol = constraints.maxWidth >= _kCronPolicyTwoColumnMinWidth;
          final timeout = _numberField(
            controller: _timeoutController,
            label: l10n.cronsTimeoutSeconds,
          );
          final retries = _numberField(
            controller: _retryController,
            label: l10n.cronsRetries,
          );
          final delay = _numberField(
            controller: _maxRetryDelayController,
            label: l10n.cronsMaxRetryDelaySeconds,
          );
          final user = _runAsUserField(systemUsers);
          if (!twoCol) {
            return Column(
              children: [
                timeout,
                kOpenHandGap12,
                retries,
                kOpenHandGap12,
                delay,
                kOpenHandGap12,
                user,
              ],
            );
          }
          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: timeout),
                  kOpenHandHGap12,
                  Expanded(child: retries),
                ],
              ),
              kOpenHandGap12,
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: delay),
                  kOpenHandHGap12,
                  Expanded(child: user),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _runAsUserField(List<String> systemUsers) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OpenHandFormLabel(l10n.cronsRunAsUser),
        kOpenHandGap8,
        SizedBox(
          height: _kCronEditorFieldHeight,
          child: AnimatedDropdownButtonFormField<String>(
            initialValue: _runAsUser,
            isExpanded: true,
            decoration: InputDecoration(
              hintText: l10n.cronsDefaultCurrentUser,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
            ),
            items: [
              DropdownMenuItem<String>(child: Text(l10n.cronsDefault)),
              ...systemUsers.map(
                (u) => DropdownMenuItem<String>(
                  value: u,
                  child: Text(u, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
            onChanged: (v) => setState(() => _runAsUser = v),
          ),
        ),
      ],
    );
  }

  Widget _buildRuntimeSection(ThemeData theme, ColorScheme colorScheme) {
    return OpenHandDialogSectionCard(
      icon: Icons.folder_special_outlined,
      accent: colorScheme.secondary,
      title: l10n.cronsSectionRuntime,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _tagsController,
            decoration: InputDecoration(
              labelText: l10n.cronsTagsCommaSeparated,
              hintText: l10n.cronsTagsHint,
            ),
          ),
          kOpenHandGap12,
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _workingDirController,
                  decoration: InputDecoration(
                    labelText: l10n.cronsWorkingDirectory,
                    hintText: l10n.cronsWorkingDirectoryHint,
                  ),
                ),
              ),
              kOpenHandHGap8,
              FilledButton.tonal(
                onPressed: _pickWorkingDirectory,
                child: Text(l10n.cronsBrowse),
              ),
            ],
          ),
          kOpenHandGap12,
          TextField(
            controller: _envController,
            maxLines: 3,
            minLines: 2,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: kOpenHandMonospaceFontFamily,
              fontSize: 12,
            ),
            decoration: InputDecoration(
              labelText: l10n.cronsEnvironmentVariables,
              hintText: l10n.cronsEnvironmentVariablesHint,
              contentPadding: const EdgeInsets.all(12),
              hintStyle: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                fontFamily: kOpenHandMonospaceFontFamily,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContextSection(ColorScheme colorScheme) {
    return OpenHandDialogSectionCard(
      icon: Icons.travel_explore_rounded,
      accent: colorScheme.primary,
      title: l10n.cronsExecutionContextCollection,
      child: Column(
        children: [
          OpenHandAnimatedSwitchTile(
            icon: Icons.apps_rounded,
            title: l10n.cronsCollectAppMetadata,
            description: l10n.cronsCollectAppMetadataSubtitle,
            value: _collectAppMetadata,
            onChanged: (value) => setState(() => _collectAppMetadata = value),
          ),
          kOpenHandGap8,
          OpenHandAnimatedSwitchTile(
            icon: Icons.dns_rounded,
            title: l10n.cronsCollectHostMetadata,
            description: l10n.cronsCollectHostMetadataSubtitle,
            value: _collectHostMetadata,
            onChanged: (value) => setState(() => _collectHostMetadata = value),
          ),
          kOpenHandGap8,
          OpenHandAnimatedSwitchTile(
            icon: Icons.inventory_2_outlined,
            title: l10n.cronsCollectEnvironmentSnapshot,
            description: l10n.cronsCollectEnvironmentSnapshotSubtitle,
            value: _collectEnvironmentSnapshot,
            badge: DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.tertiaryContainer,
                borderRadius: kOpenHandPillBorderRadius,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                child: Text(
                  l10n.cronsSensitive,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onTertiaryContainer,
                  ),
                ),
              ),
            ),
            onChanged: (value) =>
                setState(() => _collectEnvironmentSnapshot = value),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationSection(ThemeData theme, ColorScheme colorScheme) {
    return OpenHandDialogSectionCard(
      icon: Icons.notifications_active_outlined,
      accent: OpenHandStatusColors.success,
      title: l10n.cronsNotificationSettings,
      subtitle: l10n.cronsNotificationSettingsHelper,
      trailing: _buildNotificationTestButton(theme, colorScheme),
      child: Column(
        children: [
          _notifyRow(
            label: l10n.cronsOnSuccess,
            accent: OpenHandStatusColors.success,
            notifyType: _onSuccessNotify,
            severity: _onSuccessSeverity,
            soundEnabled: _onSuccessSound,
            vibrationEnabled: _onSuccessVibration,
            msgController: _onSuccessMsgController,
            onNotifyChanged: (v) => setState(() => _onSuccessNotify = v),
            onSeverityChanged: (v) => setState(() => _onSuccessSeverity = v),
            onSoundChanged: (v) => setState(() => _onSuccessSound = v),
            onVibrationChanged: (v) => setState(() => _onSuccessVibration = v),
          ),
          kOpenHandGap10,
          _notifyRow(
            label: l10n.cronsOnFailure,
            accent: OpenHandStatusColors.error,
            notifyType: _onFailureNotify,
            severity: _onFailureSeverity,
            soundEnabled: _onFailureSound,
            vibrationEnabled: _onFailureVibration,
            msgController: _onFailureMsgController,
            onNotifyChanged: (v) => setState(() => _onFailureNotify = v),
            onSeverityChanged: (v) => setState(() => _onFailureSeverity = v),
            onSoundChanged: (v) => setState(() => _onFailureSound = v),
            onVibrationChanged: (v) => setState(() => _onFailureVibration = v),
          ),
          kOpenHandGap10,
          _notifyRow(
            label: l10n.cronsOnTimeout,
            accent: OpenHandStatusColors.warning,
            notifyType: _onTimeoutNotify,
            severity: _onTimeoutSeverity,
            soundEnabled: _onTimeoutSound,
            vibrationEnabled: _onTimeoutVibration,
            msgController: _onTimeoutMsgController,
            onNotifyChanged: (v) => setState(() => _onTimeoutNotify = v),
            onSeverityChanged: (v) => setState(() => _onTimeoutSeverity = v),
            onSoundChanged: (v) => setState(() => _onTimeoutSound = v),
            onVibrationChanged: (v) => setState(() => _onTimeoutVibration = v),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationTestButton(
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return AnimatedPopupMenuButton<_NotificationTestScenario>(
      tooltip: l10n.cronsTestNotification,
      position: PopupMenuPosition.under,
      style: const ButtonStyle(
        padding: WidgetStatePropertyAll(EdgeInsets.zero),
        minimumSize: WidgetStatePropertyAll(Size.zero),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        overlayColor: WidgetStatePropertyAll(Colors.transparent),
        shadowColor: WidgetStatePropertyAll(Colors.transparent),
        elevation: WidgetStatePropertyAll(0),
        shape: WidgetStatePropertyAll(StadiumBorder()),
      ),
      onSelected: _testNotification,
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _NotificationTestScenario.success,
          child: Text(l10n.cronsTestSuccessNotification),
        ),
        PopupMenuItem(
          value: _NotificationTestScenario.failure,
          child: Text(l10n.cronsTestFailureNotification),
        ),
        PopupMenuItem(
          value: _NotificationTestScenario.timeout,
          child: Text(l10n.cronsTestTimeoutNotification),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _NotificationTestScenario.all,
          child: Text(l10n.cronsTestAllNotifications),
        ),
      ],
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: kOpenHandPillBorderRadius,
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.8),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_active_outlined,
              size: 16,
              color: colorScheme.onSurfaceVariant,
            ),
            kOpenHandHGap6,
            Text(
              l10n.cronsTestNotification,
              style: theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _numberField({
    required TextEditingController controller,
    required String label,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OpenHandFormLabel(label),
        kOpenHandGap8,
        SizedBox(
          height: _kCronEditorFieldHeight,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
          ),
        ),
      ],
    );
  }

  Widget _notifyRow({
    required String label,
    required Color accent,
    required CronNotifyType notifyType,
    required CronNotifySeverity severity,
    required bool soundEnabled,
    required bool vibrationEnabled,
    required TextEditingController msgController,
    required ValueChanged<CronNotifyType> onNotifyChanged,
    required ValueChanged<CronNotifySeverity> onSeverityChanged,
    required ValueChanged<bool> onSoundChanged,
    required ValueChanged<bool> onVibrationChanged,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final vibrationUnsupported =
        vibrationEnabled && !OpenHandNotificationService.supportsVibration;

    return Material(
      color: colorScheme.surface,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: kOpenHandBorderRadius18,
        side: BorderSide(color: accent.withValues(alpha: 0.28)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColoredBox(
              color: accent,
              child: const SizedBox(width: kOpenHandAccentRailWidth),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    kOpenHandGap12,
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: _kCronEditorFieldHeight,
                            child:
                                AnimatedDropdownButtonFormField<CronNotifyType>(
                                  initialValue: notifyType,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                  ),
                                  items: CronNotifyType.values.map((n) {
                                    return DropdownMenuItem(
                                      value: n,
                                      child: Text(n.label(l10n)),
                                    );
                                  }).toList(),
                                  onChanged: (v) {
                                    if (v != null) onNotifyChanged(v);
                                  },
                                ),
                          ),
                        ),
                        kOpenHandHGap8,
                        Expanded(
                          child: SizedBox(
                            height: _kCronEditorFieldHeight,
                            child:
                                AnimatedDropdownButtonFormField<
                                  CronNotifySeverity
                                >(
                                  initialValue: severity,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                  ),
                                  items: CronNotifySeverity.values.map((s) {
                                    return DropdownMenuItem(
                                      value: s,
                                      child: Text(s.label(l10n)),
                                    );
                                  }).toList(),
                                  onChanged: (v) {
                                    if (v != null) onSeverityChanged(v);
                                  },
                                ),
                          ),
                        ),
                        kOpenHandHGap8,
                        Tooltip(
                          message: _soundSupportTooltip(soundEnabled),
                          child: SizedBox.square(
                            dimension: _kCronEditorFieldHeight,
                            child: IconButton.filledTonal(
                              onPressed: () => onSoundChanged(!soundEnabled),
                              icon: Icon(
                                soundEnabled
                                    ? Icons.volume_up_rounded
                                    : Icons.volume_off_rounded,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                        kOpenHandHGap4,
                        Tooltip(
                          message: _vibrationSupportTooltip(vibrationEnabled),
                          child: SizedBox.square(
                            dimension: _kCronEditorFieldHeight,
                            child: IconButton.filledTonal(
                              onPressed: () =>
                                  onVibrationChanged(!vibrationEnabled),
                              icon: Icon(
                                vibrationEnabled
                                    ? Icons.vibration_rounded
                                    : Icons.vibration_outlined,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    kOpenHandGap10,
                    SizedBox(
                      height: _kCronEditorFieldHeight,
                      child: TextField(
                        controller: msgController,
                        decoration: InputDecoration(
                          hintText: l10n.cronsCustomNotificationMessageHint,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                    if (vibrationUnsupported) ...[
                      kOpenHandGap6,
                      Text(
                        l10n.cronsVibrationUnsupportedHint,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _validateCron() {
    final err = CronParser.validate(_cronExpression, l10n: l10n);
    setState(() => _cronError = err);
  }

  Future<void> _pickScriptFile() async {
    final List<XTypeGroup> typeGroups;
    if (Platform.isWindows) {
      typeGroups = [
        const XTypeGroup(label: 'Scripts', extensions: ['ps1', 'bat', 'cmd']),
      ];
    } else {
      typeGroups = [
        const XTypeGroup(label: 'Shell Scripts', extensions: ['sh']),
        const XTypeGroup(label: 'All Files', extensions: ['*']),
      ];
    }
    final file = await openFile(acceptedTypeGroups: typeGroups);
    if (!mounted || file == null) return;
    setState(() => _scriptPathController.text = file.path);
  }

  Future<void> _pickWorkingDirectory() async {
    final path = await getDirectoryPath();
    if (!mounted || path == null) return;
    setState(() => _workingDirController.text = path);
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameController.text.trim();
    final validationError = _validateForm(name);
    if (validationError != null) {
      setState(() => _formError = validationError);
      return;
    }

    final cronExpr = _cronExpression;
    final cronErr = CronParser.validate(cronExpr, l10n: l10n);
    if (cronErr != null) {
      setState(() {
        _cronError = cronErr;
        _formError = null;
      });
      return;
    }

    final timeout = clampedIntFromText(
      _timeoutController.text,
      fallback: kCronDefaultTimeoutSeconds,
      min: kCronMinTimeoutSeconds,
      max: kCronMaxTimeoutSeconds,
    );
    final retryCount = clampedIntFromText(
      _retryController.text,
      fallback: kCronDefaultRetryCount,
      min: kCronMinRetryCount,
      max: kCronMaxRetryCount,
    );
    final maxRetryDelay = clampedIntFromText(
      _maxRetryDelayController.text,
      fallback: kCronDefaultRetryDelaySeconds,
      min: kCronMinRetryDelaySeconds,
      max: kCronMaxRetryDelaySeconds,
    );

    final tags = splitTrimmedNonEmpty(_tagsController.text);
    final env = keyValueMapFromValue(_envController.text);

    final entry = CronEntry(
      id: widget.existing?.id ?? _uuid.v4(),
      name: name,
      description: _descriptionController.text.trim(),
      scriptType: _scriptType,
      scriptPath: _scriptType == CronScriptType.script
          ? _scriptPathController.text.trim()
          : null,
      scriptContent: _scriptType == CronScriptType.command
          ? _scriptContentController.text
          : null,
      cronExpression: cronExpr,
      retryCount: retryCount,
      timeoutSeconds: timeout,
      runAsUser: _runAsUser,
      tags: tags,
      enabled: widget.existing?.enabled ?? true,
      status: widget.existing?.status ?? CronJobStatus.idle,
      onSuccessNotify: _onSuccessNotify,
      onFailureNotify: _onFailureNotify,
      onTimeoutNotify: _onTimeoutNotify,
      onSuccessSeverity: _onSuccessSeverity,
      onFailureSeverity: _onFailureSeverity,
      onTimeoutSeverity: _onTimeoutSeverity,
      onSuccessPlaySound: _onSuccessSound,
      onFailurePlaySound: _onFailureSound,
      onTimeoutPlaySound: _onTimeoutSound,
      onSuccessVibrate: _onSuccessVibration,
      onFailureVibrate: _onFailureVibration,
      onTimeoutVibrate: _onTimeoutVibration,
      onSuccessMessage: nullIfBlank(_onSuccessMsgController.text),
      onFailureMessage: nullIfBlank(_onFailureMsgController.text),
      onTimeoutMessage: nullIfBlank(_onTimeoutMsgController.text),
      collectAppMetadata: _collectAppMetadata,
      collectHostMetadata: _collectHostMetadata,
      collectEnvironmentSnapshot: _collectEnvironmentSnapshot,
      workingDirectory: nullIfBlank(_workingDirController.text),
      environment: env,
      maxRetryDelaySeconds: maxRetryDelay,
    );

    setState(() => _saving = true);
    try {
      final controller = context.read<CronsController>();
      final saved = _isEditing
          ? await controller.updateCron(entry)
          : await controller.addCron(entry);
      if (!mounted) return;
      if (saved) {
        Navigator.of(context).pop();
      } else {
        setState(() {
          _formError =
              controller.errorMessage ?? l10n.settingsPersistenceSaveFailedBody;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _validateForm(String name) {
    if (name.isEmpty) {
      return l10n.cronsValidationNameRequired;
    }
    if (_scriptType == CronScriptType.script &&
        nullIfBlank(_scriptPathController.text) == null) {
      return l10n.cronsValidationScriptRequired;
    }
    if (_scriptType == CronScriptType.command &&
        nullIfBlank(_scriptContentController.text) == null) {
      return l10n.cronsValidationCommandRequired;
    }
    final invalidEnvLines = invalidKeyValueLineNumbersFromText(
      _envController.text,
    );
    if (invalidEnvLines.isNotEmpty) {
      final lines = invalidEnvLines.join(', ');
      return l10n.cronsValidationInvalidEnvironment(lines);
    }
    return null;
  }

  Future<void> _testNotification(_NotificationTestScenario scenario) async {
    final generation = ++_notificationTestGeneration;
    final strings = l10n;
    if (scenario == _NotificationTestScenario.all) {
      await _testAllNotificationsSequentially(strings, generation);
      return;
    }
    await _testSingleNotification(scenario, strings, generation);
  }

  bool _isNotificationTestActive(int generation) =>
      mounted && generation == _notificationTestGeneration;

  Future<void> _testAllNotificationsSequentially(
    AppLocalizations strings,
    int generation,
  ) async {
    final scenarios = <_NotificationTestScenario>[
      _NotificationTestScenario.success,
      _NotificationTestScenario.failure,
      _NotificationTestScenario.timeout,
    ];
    final configs = <_NotificationTestConfig>[
      for (final scenario in scenarios)
        _resolveTestNotificationConfig(scenario, strings),
    ];

    final hasUnsupportedVibration =
        !OpenHandNotificationService.supportsVibration &&
        configs.any((config) => config.vibrationEnabled);

    await OpenHandNotificationService.showInApp(
      title: strings.cronsNotificationSequentialStartTitle,
      body: strings.cronsNotificationSequentialStartBody,
    );
    if (!_isNotificationTestActive(generation)) return;

    for (var i = 0; i < configs.length; i++) {
      await _emitTestNotification(
        configs[i],
        strings,
        generation,
        showVibrationFallbackHint: false,
      );
      if (!_isNotificationTestActive(generation)) return;
      if (i < configs.length - 1) {
        await Future<void>.delayed(_kCronNotificationTestGap);
        if (!_isNotificationTestActive(generation)) return;
      }
    }

    if (hasUnsupportedVibration) {
      await OpenHandNotificationService.showInApp(
        title: strings.cronsNotificationVibrationIgnoredTitle,
        body: strings.cronsNotificationSequentialVibrationIgnoredBody,
      );
      if (!_isNotificationTestActive(generation)) return;
    }

    await OpenHandNotificationService.showInApp(
      title: strings.cronsNotificationSequentialCompletedTitle,
      body: strings.cronsNotificationSequentialCompletedBody,
      level: OpenHandNotificationLevel.success,
    );
  }

  Future<void> _testSingleNotification(
    _NotificationTestScenario scenario,
    AppLocalizations strings,
    int generation,
  ) {
    return _emitTestNotification(
      _resolveTestNotificationConfig(scenario, strings),
      strings,
      generation,
    );
  }

  Future<void> _emitTestNotification(
    _NotificationTestConfig config,
    AppLocalizations strings,
    int generation, {
    bool showVibrationFallbackHint = true,
  }) async {
    if (!_isNotificationTestActive(generation)) return;
    final title = strings.cronsNotificationTestTitle(config.label);
    final body = nullIfBlank(config.message) ?? config.defaultBody;

    if (config.type == CronNotifyType.none ||
        config.type == CronNotifyType.log) {
      await OpenHandNotificationService.showInApp(
        title: title,
        body: strings.cronsNotificationNoEmitBody,
        level: OpenHandNotificationLevel.warning,
      );
      return;
    }

    final level = config.severity.notificationLevel;
    if (config.type == CronNotifyType.system) {
      final shown = await OpenHandNotificationService.showSystem(
        title: title,
        body: body,
        level: level,
        playSound: config.soundEnabled,
        vibrate: config.vibrationEnabled,
      );
      if (!_isNotificationTestActive(generation)) return;
      if (!shown) {
        await OpenHandNotificationService.showInApp(
          title: strings.cronsSystemNotificationUnavailableTitle,
          body: strings.cronsSystemNotificationFallbackBody,
          level: OpenHandNotificationLevel.warning,
          playSound: config.soundEnabled,
          vibrate: config.vibrationEnabled,
        );
      }
    } else {
      await OpenHandNotificationService.showInApp(
        title: title,
        body: body,
        level: level,
        playSound: config.soundEnabled,
        vibrate: config.vibrationEnabled,
      );
    }
    if (!_isNotificationTestActive(generation)) return;

    if (showVibrationFallbackHint &&
        config.vibrationEnabled &&
        !OpenHandNotificationService.supportsVibration) {
      await OpenHandNotificationService.showInApp(
        title: strings.cronsNotificationVibrationIgnoredTitle,
        body: strings.cronsNotificationVibrationIgnoredBody,
      );
    }
  }

  _NotificationTestConfig _resolveTestNotificationConfig(
    _NotificationTestScenario scenario,
    AppLocalizations strings,
  ) {
    return switch (scenario) {
      _NotificationTestScenario.success => (
        type: _onSuccessNotify,
        severity: _onSuccessSeverity,
        soundEnabled: _onSuccessSound,
        vibrationEnabled: _onSuccessVibration,
        message: _onSuccessMsgController.text,
        label: strings.cronsNotificationScenarioSuccess,
        defaultBody: strings.cronsNotificationTestDefaultBodySuccess,
      ),
      _NotificationTestScenario.failure => (
        type: _onFailureNotify,
        severity: _onFailureSeverity,
        soundEnabled: _onFailureSound,
        vibrationEnabled: _onFailureVibration,
        message: _onFailureMsgController.text,
        label: strings.cronsNotificationScenarioFailure,
        defaultBody: strings.cronsNotificationTestDefaultBodyFailure,
      ),
      _NotificationTestScenario.timeout => (
        type: _onTimeoutNotify,
        severity: _onTimeoutSeverity,
        soundEnabled: _onTimeoutSound,
        vibrationEnabled: _onTimeoutVibration,
        message: _onTimeoutMsgController.text,
        label: strings.cronsNotificationScenarioTimeout,
        defaultBody: strings.cronsNotificationTestDefaultBodyTimeout,
      ),
      _NotificationTestScenario.all => (
        type: _onFailureNotify,
        severity: _onFailureSeverity,
        soundEnabled: _onFailureSound,
        vibrationEnabled: _onFailureVibration,
        message: _onFailureMsgController.text,
        label: strings.cronsNotificationScenarioAll,
        defaultBody: strings.cronsNotificationTestDefaultBodyFailure,
      ),
    };
  }

  bool get _supportsSoundAlert {
    return Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isMacOS ||
        Platform.isLinux ||
        Platform.isWindows;
  }

  String get _platformLabel {
    if (Platform.isMacOS) {
      return 'macOS';
    }
    if (Platform.isWindows) {
      return 'Windows';
    }
    if (Platform.isLinux) {
      return 'Linux';
    }
    if (Platform.isAndroid) {
      return 'Android';
    }
    if (Platform.isIOS) {
      return 'iOS';
    }
    return l10n.cronsUnknownPlatform;
  }

  String _soundSupportTooltip(bool enabled) {
    final state = enabled ? l10n.cronsToggleOn : l10n.cronsToggleOff;
    if (_supportsSoundAlert) {
      final detail = isDesktopPlatform()
          ? l10n.cronsSupportBestEffortSystemSound
          : l10n.cronsSupportSupported;
      return _capabilityTooltip(
        label: l10n.cronsSoundLabel,
        state: state,
        platform: _platformLabel,
        support: detail,
      );
    }
    return _capabilityTooltip(
      label: l10n.cronsSoundLabel,
      state: state,
      platform: _platformLabel,
      support: l10n.cronsSupportNotSupportedOnPlatform,
    );
  }

  String _vibrationSupportTooltip(bool enabled) {
    return _capabilityTooltip(
      label: l10n.cronsVibrationLabel,
      state: enabled ? l10n.cronsToggleOn : l10n.cronsToggleOff,
      platform: _platformLabel,
      support: OpenHandNotificationService.supportsVibration
          ? l10n.cronsSupportSupported
          : l10n.cronsSupportNotSupportedWillBeIgnored,
    );
  }

  String _capabilityTooltip({
    required String label,
    required String state,
    required String platform,
    required String support,
  }) {
    return '$label: $state\n'
        '${l10n.cronsPlatformLabel}: $platform\n'
        '${l10n.cronsSupportLabel}: $support';
  }
}

class _CronTypeChoice extends StatelessWidget {
  const _CronTypeChoice({
    required this.selected,
    required this.icon,
    required this.label,
    required this.hint,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tone = selected ? colorScheme.primary : colorScheme.onSurfaceVariant;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: kOpenHandBorderRadius16,
        child: AnimatedContainer(
          duration: openHandMotionDuration(context, kOpenHandMotion180),
          curve: kOpenHandSwitchInCurve,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            color: selected
                ? colorScheme.primaryContainer.withValues(alpha: 0.72)
                : colorScheme.surface,
            borderRadius: kOpenHandBorderRadius16,
            border: Border.all(
              color: selected
                  ? colorScheme.primary.withValues(alpha: 0.62)
                  : colorScheme.outlineVariant,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: selected
                      ? colorScheme.primary.withValues(alpha: 0.16)
                      : colorScheme.surfaceContainerHigh,
                  borderRadius: kOpenHandBorderRadius12,
                ),
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: Center(child: Icon(icon, size: 18, color: tone)),
                ),
              ),
              kOpenHandHGap10,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: selected
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurface,
                      ),
                    ),
                    kOpenHandGap2,
                    Text(
                      hint,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
