import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../../app/model/app_info.dart';
import '../../../app/model/app_language.dart';
import '../../../app/model/app_proxy_settings.dart';
import '../../../app/model/app_settings_snapshot.dart';
import '../../../app/model/dialog_animation_settings.dart';
import '../../../app/model/editor_code_theme.dart';
import '../../../app/model/editor_indent.dart';
import '../../../app/model/editor_shortcut.dart';
import '../../../app/model/openhand_shortcut.dart';
import '../../../app/state/settings_controller.dart';
import '../../../app/state/settings_store.dart';
import '../../../app/support/app_restart_service.dart';
import '../../../app/support/input_repair_service.dart';
import '../../../app/support/openhand_paths.dart';
import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../../../app/support/system_proxy.dart';
import '../../../app/support/url_validation.dart';
import '../../../app/theme/openhand_status_colors.dart';
import '../../../app/theme/openhand_theme_preset.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/fps/openhand_fps_monitor.dart';
import '../../../shared/net/bounded_http_request.dart';
import '../../../shared/net/http_response_utils.dart';
import '../../../shared/net/tcp_port_utils.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/animated_expandable.dart';
import '../../../shared/ui/animated_menu.dart';
import '../../../shared/ui/app_update_dialog.dart';
import '../../../shared/ui/appear_once.dart';
import '../../../shared/ui/auto_follow_scroll_guard.dart';
import '../../../shared/ui/buffered_console_log.dart';
import '../../../shared/ui/error_snackbar.dart';
import '../../../shared/ui/feature_page_shell.dart';
import '../../../shared/ui/first_frame_pulse_box.dart';
import '../../../shared/ui/highlight_pulse.dart';
import '../../../shared/ui/hover_lift.dart';
import '../../../shared/ui/interaction_timings.dart';
import '../../../shared/ui/key_tweakable_slider.dart';
import '../../../shared/ui/list_removal_transition.dart';
import '../../../shared/ui/micro_press_feedback.dart';
import '../../../shared/ui/model_search_selector.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/oh_pill.dart';
import '../../../shared/ui/openhand_busy_indicators.dart';
import '../../../shared/ui/openhand_clipboard.dart';
import '../../../shared/ui/openhand_console_log_panel.dart';
import '../../../shared/ui/openhand_console_log_view.dart';
import '../../../shared/ui/openhand_deferred_slider.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_form_fields.dart';
import '../../../shared/ui/openhand_inline_empty_state.dart';
import '../../../shared/ui/openhand_ops_charts.dart';
import '../../../shared/ui/openhand_reveal_switcher.dart';
import '../../../shared/ui/openhand_safe_scrollbar.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/openhand_table_metric_cells.dart';
import '../../../shared/ui/openhand_table_pagination.dart';
import '../../../shared/ui/openhand_tap_region.dart';
import '../../../shared/ui/openhand_tooltip_dismissal.dart';
import '../../../shared/ui/openhand_typography.dart';
import '../../../shared/ui/persistence_issue_card.dart';
import '../../../shared/ui/reasoning_effort_selector.dart';
import '../../../shared/ui/reorder_proxy_decorator.dart';
import '../../../shared/ui/rolling_text.dart';
import '../../../shared/util/async_concurrency.dart';
import '../../../shared/util/bounded_directory_io.dart';
import '../../../shared/util/bounded_file_io.dart';
import '../../../shared/util/bounded_xfile_io.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/csv_encoding.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/localized_text.dart';
import '../../../shared/util/reader_file_type.dart';
import '../../../shared/util/stable_hash.dart';
import '../../../shared/util/text_clip.dart';
import '../../../shared/util/text_normalization.dart';
import '../../../shared/util/timer_safety.dart';
import '../../../shared/util/user_failure_message.dart';
import '../../ai/index.dart';
import '../../crons/crons_controller.dart';
import '../../harness/index.dart';
import '../../hooks/hooks_controller.dart';
import '../../instructions/instructions_controller.dart';
import '../../mcp/index.dart';
import '../../memory/index.dart';
import '../../message_gateway/index.dart' show MessageGatewayController;
import '../../services/index.dart'
    show
        AiModelHealthController,
        AiModelHealthIndicator,
        AiModelHealthSettingsPanel,
        aiModelProxyDispatchModeLabel;
import '../../skills/skills_controller.dart';
import '../data_cleanup/data_cleanup_models.dart';
import '../data_cleanup/data_cleanup_service.dart';
import '../service/throttle_cloud_sync_service.dart';
import 'openrouter_model_sync_dialog.dart';
import 'prompt_cache_breakpoint_bar.dart';
import 'thread_session_management_dialog.dart';
part '_settings_ai_model_editor.dart';
part '_settings_editor_lsp.dart';
part '_settings_command_rules.dart';
part '_settings_sandbox.dart';
part '_settings_shortcut_widgets.dart';
part '_settings_animation_sections.dart';
part '_settings_builtin_tools.dart';
part '_settings_web_search_editor.dart';
part '_settings_web_fetch_editor.dart';
part '_settings_web_fetch_runtime_dialog.dart';
part '_settings_helper_widgets.dart';
part '_settings_offline_speech.dart';
part '_settings_user_profile.dart';
part '_settings_data_cleanup.dart';
part '_settings_system_proxy.dart';
part '_settings_proxy_test_dialog.dart';
part '_settings_active_tool_calls.dart';
part '_settings_ai_usage.dart';

typedef _SettingsPathGetter = String Function(SettingsController controller);
typedef _SettingsPathOperation = Future<bool> Function(String path);

const int _kSettingsToolResultCompressionWindowMaxChars = 8 * kBytesPerKiB;
const int _kSettingsToolResultCompressionMaxPathHits = 200;
const int _kSettingsWriteToolSummaryMaxChars = 8 * kBytesPerKiB;
const int _kThrottleConfigImportMaxBytes = 1 * kBytesPerMiB;
bool _settingsMotionEnabled(BuildContext context) {
  return openHandTickerMotionEnabled(context);
}

void _syncControllerText(TextEditingController controller, String text) {
  if (controller.text == text) return;
  controller.value = controller.value.copyWith(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
    composing: TextRange.empty,
  );
}

void _syncControllerValue<T>(
  TextEditingController controller,
  T previous,
  T current, {
  String Function(T value)? format,
}) {
  if (previous == current) return;
  _syncControllerText(controller, format?.call(current) ?? '$current');
}

List<T> _reorderedCopy<T>(List<T> values, int oldIndex, int newIndex) {
  final result = List<T>.of(values);
  result.insert(newIndex, result.removeAt(oldIndex));
  return result;
}

List<T> _replacedCopy<T>(List<T> values, int index, T value) {
  return List<T>.of(values)..[index] = value;
}

Future<bool> _confirmClearLocalCache({
  required BuildContext context,
  required String toolLabel,
  required String titleZhVerb,
  required String titleEnVerb,
  required String contentZh,
  required String contentEn,
}) {
  return showOpenHandConfirmDialog(
    context: context,
    title: openHandLocalizedText(
      context,
      zh: '$titleZhVerb $toolLabel 本地缓存？',
      en: '$titleEnVerb $toolLabel local cache?',
    ),
    message: openHandLocalizedText(context, zh: contentZh, en: contentEn),
    cancelLabel: openHandCancelLabel(context),
    confirmLabel: openHandLocalizedText(context, zh: '确认清理', en: 'Clear'),
    destructive: true,
  );
}

Future<bool> _confirmClearToolTelemetry({
  required BuildContext context,
  required String toolLabel,
}) {
  return showOpenHandConfirmDialog(
    context: context,
    title: openHandLocalizedText(
      context,
      zh: '清空 $toolLabel 调用日志？',
      en: 'Clear $toolLabel call history?',
    ),
    message: openHandLocalizedText(
      context,
      zh: '会同时清掉最近 200 条调用记录与每引擎累计成功率/耗时统计。本地缓存 (summary) 不受影响。',
      en: 'Removes the recent call ring buffer (up to 200 entries) and all per-engine success-rate/latency aggregates. Cached summaries are not affected.',
    ),
    cancelLabel: openHandCancelLabel(context),
    confirmLabel: _settingsClearLabel(context),
    destructive: true,
  );
}

Future<void> _exportToolTelemetry<T>({
  required BuildContext context,
  required String logTag,
  required String fileStem,
  required bool asCsv,
  required Future<List<T>> Function() loadCalls,
  required String Function(List<T> calls) encodeJson,
  required String Function(List<T> calls) encodeCsv,
}) async {
  try {
    final ext = asCsv ? 'csv' : 'json';
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
    final location = await getSaveLocation(
      suggestedName: '$fileStem-calls-$ts.$ext',
      acceptedTypeGroups: [
        XTypeGroup(label: ext.toUpperCase(), extensions: [ext]),
      ],
    );
    if (location == null) return;
    final calls = await loadCalls();
    final body = asCsv ? encodeCsv(calls) : encodeJson(calls);
    await writeFileAtomically(File(location.path), body);
    if (!context.mounted) return;
    showOpenHandSuccessSnack(
      context,
      openHandLocalizedText(
        context,
        zh: '已导出 ${calls.length} 条记录到 ${location.path}',
        en: 'Exported ${calls.length} entries to ${location.path}',
      ),
      duration: kOpenHandMotion1800,
    );
  } catch (error, stack) {
    silentLog(logTag, '导出遥测数据', error, stack);
    if (!context.mounted) return;
    final detail = userFailureMessage(error, fallback: '无法导出遥测数据。');
    showOpenHandErrorSnack(
      context,
      openHandLocalizedText(
        context,
        zh: '导出失败：$detail',
        en: 'Export failed: $detail',
      ),
    );
  }
}

String _encodeJsonList(Iterable<Object?> values) {
  return prettyPrintJson(values.toList(growable: false));
}

List<Widget> _buildToolTelemetryHeader({
  required BuildContext context,
  required String description,
  required bool hasData,
  required bool hasCalls,
  required bool loading,
  required bool clearing,
  required bool exporting,
  required VoidCallback onExportJson,
  required VoidCallback onExportCsv,
  required VoidCallback onRefresh,
  required VoidCallback onClear,
}) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  final exportEnabled = !loading && !clearing && !exporting && hasCalls;
  return <Widget>[
    Text(
      openHandLocalizedText(
        context,
        zh: '调用日志 / 引擎健康度',
        en: 'Call History / Engine Health',
      ),
      style: theme.textTheme.titleSmall,
    ),
    kOpenHandGap4,
    Text(
      description,
      style: theme.textTheme.bodySmall?.copyWith(
        color: colorScheme.onSurfaceVariant,
      ),
    ),
    kOpenHandGap8,
    Row(
      children: [
        const Spacer(),
        TextButton.icon(
          onPressed: exportEnabled ? onExportJson : null,
          icon: const Icon(Icons.code, size: 16),
          label: Text(openHandExportJsonLabel(context)),
        ),
        kOpenHandHGap4,
        TextButton.icon(
          onPressed: exportEnabled ? onExportCsv : null,
          icon: OpenHandBusyStatusIcon(
            busy: exporting,
            icon: Icons.table_chart,
            size: 16,
          ),
          label: Text(openHandExportCsvLabel(context)),
        ),
        kOpenHandHGap4,
        TextButton.icon(
          onPressed: loading || clearing ? null : onRefresh,
          icon: OpenHandBusyStatusIcon(
            busy: loading,
            icon: Icons.refresh,
            size: 16,
          ),
          label: Text(openHandRefreshLabel(context)),
        ),
        kOpenHandHGap4,
        TextButton.icon(
          onPressed: !hasData || loading || clearing ? null : onClear,
          icon: OpenHandBusyStatusIcon(
            busy: clearing,
            icon: Icons.delete_sweep,
            size: 16,
            color: colorScheme.error,
          ),
          label: Text(
            openHandLocalizedText(
              context,
              zh: clearing ? '清空中…' : '清空记录',
              en: clearing ? 'Clearing…' : 'Clear Logs',
            ),
            style: TextStyle(color: colorScheme.error),
          ),
        ),
      ],
    ),
  ];
}

List<Widget> _buildToolTelemetryBody({
  required BuildContext context,
  required bool loading,
  required String emptyMessage,
  required List<Widget> engineRows,
  required Widget? callList,
}) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  if (engineRows.isEmpty && callList == null && !loading) {
    return <Widget>[
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          emptyMessage,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ];
  }
  return <Widget>[
    if (engineRows.isNotEmpty) ...[
      Text(
        openHandLocalizedText(context, zh: '引擎健康度', en: 'Engine Health'),
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      kOpenHandGap6,
      ...engineRows,
      kOpenHandGap12,
    ],
    if (callList != null) ...[
      Text(
        openHandLocalizedText(context, zh: '最近调用', en: 'Recent Calls'),
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      kOpenHandGap6,
      callList,
    ],
  ];
}

/// WebSearch / WebFetch 共用的「缓存 TTL + 容量上限」输入行。
///
/// 上下限两者一致、取自 [AiWebEngineCachePolicy]；只有默认 TTL 因用途不同而由
/// 调用方传入，提示文案直接由它渲染，避免把一处的默认值抄到另一处
/// （此前抓取缓存实际默认 15 分钟，提示却写 5 分钟）。
Widget _buildWebEngineCacheFields({
  required BuildContext context,
  required TextEditingController ttlController,
  required TextEditingController maxBytesController,
  required int defaultTtlSeconds,
  required int currentMaxBytes,
  required ValueChanged<int> onTtlChanged,
  required ValueChanged<int> onMaxBytesChanged,
}) {
  const defaultMaxBytes = AiWebEngineCachePolicy.defaultMaxBytes;
  const minMaxBytes = AiWebEngineCachePolicy.minMaxBytes;
  const maxMaxBytes = AiWebEngineCachePolicy.maxMaxBytes;
  final defaultTtlMinutes = defaultTtlSeconds ~/ 60;
  return Row(
    children: [
      Expanded(
        child: TextField(
          controller: ttlController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: openHandLocalizedText(
              context,
              zh: '缓存 TTL (秒)',
              en: 'Cache TTL (seconds)',
            ),
            helperText: openHandLocalizedText(
              context,
              zh: '默认 $defaultTtlSeconds 秒 = $defaultTtlMinutes 分钟; 设为 0 关闭缓存',
              en:
                  'Default ${defaultTtlSeconds}s '
                  '($defaultTtlMinutes min); 0 disables caching',
            ),
          ),
          onChanged: (text) => onTtlChanged(
            clampedIntFromText(
              text,
              fallback: 0,
              min: AiWebEngineCachePolicy.minTtlSeconds,
              max: AiWebEngineCachePolicy.maxTtlSeconds,
            ),
          ),
        ),
      ),
      kOpenHandHGap12,
      Expanded(
        child: TextField(
          controller: maxBytesController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: openHandLocalizedText(
              context,
              zh: '缓存上限 (MB)',
              en: 'Cache Cap (MB)',
            ),
            helperText: openHandLocalizedText(
              context,
              zh:
                  '默认 ${formatByteSize(defaultMaxBytes)}；'
                  '范围 ${formatByteSize(minMaxBytes)}–${formatByteSize(maxMaxBytes)}',
              en:
                  'Default ${formatByteSize(defaultMaxBytes)}; '
                  'range ${formatByteSize(minMaxBytes)}–${formatByteSize(maxMaxBytes)}',
            ),
          ),
          onChanged: (text) => onMaxBytesChanged(
            megabytesTextToBytes(
              text,
              fallbackBytes: currentMaxBytes,
              minBytes: minMaxBytes,
              maxBytes: maxMaxBytes,
            ),
          ),
        ),
      ),
    ],
  );
}

Widget _buildToolCacheActions({
  required BuildContext context,
  required int? bytesOnDisk,
  required bool loading,
  required bool clearing,
  required VoidCallback onRefresh,
  required VoidCallback onClear,
}) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  return Row(
    children: [
      Expanded(
        child: Text(
          openHandLocalizedText(
            context,
            zh: '当前已占用：${formatNullableByteSize(bytesOnDisk, pendingLabel: '…')}',
            en: 'On disk: ${formatNullableByteSize(bytesOnDisk, pendingLabel: '…')}',
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      kOpenHandHGap12,
      TextButton.icon(
        onPressed: loading || clearing ? null : onRefresh,
        icon: OpenHandBusyStatusIcon(
          busy: loading,
          icon: Icons.refresh,
          size: 16,
        ),
        label: Text(openHandRefreshLabel(context)),
      ),
      kOpenHandHGap4,
      FilledButton.tonalIcon(
        style: FilledButton.styleFrom(
          foregroundColor: colorScheme.onPrimary,
          disabledForegroundColor: colorScheme.onSurface.withValues(
            alpha: 0.38,
          ),
        ),
        onPressed: loading || clearing ? null : onClear,
        icon: clearing
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colorScheme.onPrimary,
                ),
              )
            : Icon(Icons.delete_sweep, size: 16, color: colorScheme.onPrimary),
        label: Text(
          openHandLocalizedText(
            context,
            zh: clearing ? '清理中…' : '清理缓存',
            en: clearing ? 'Clearing…' : 'Clear Cache',
          ),
        ),
      ),
    ],
  );
}

Widget _buildToolEngineStatRow<T extends WebEngineSampleBase>({
  required BuildContext context,
  required String engineName,
  required double successRate,
  required String summary,
  required String? lastError,
  required bool inCooldown,
  required int? cooldownUntilMs,
  required String? quotaError,
  required VoidCallback onResetCooldown,
  required List<T> samples,
}) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  final percentage = successRate * 100;
  final percentageColor = percentage >= 80
      ? Colors.green.shade600
      : percentage >= 50
      ? Colors.orange.shade600
      : colorScheme.error;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 92,
              child: Text(
                engineName,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: kOpenHandMonospaceFontFamily,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            kOpenHandHGap6,
            SizedBox(
              width: 84,
              child: Stack(
                children: [
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: kOpenHandBorderRadius4,
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: finiteUnitInterval(successRate),
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: percentageColor,
                        borderRadius: kOpenHandBorderRadius4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            kOpenHandHGap8,
            SizedBox(
              width: 48,
              child: Text(
                '${percentage.toStringAsFixed(0)}%',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: percentageColor,
                ),
              ),
            ),
            Expanded(
              child: Text(
                summary,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (lastError != null)
              Tooltip(
                message: lastError,
                child: Icon(
                  Icons.error_outline,
                  size: 14,
                  color: colorScheme.error,
                ),
              ),
          ],
        ),
        ..._buildToolEngineStatusDetails<T>(
          context: context,
          inCooldown: inCooldown,
          cooldownUntilMs: cooldownUntilMs,
          quotaError: quotaError,
          onResetCooldown: onResetCooldown,
          samples: samples,
        ),
      ],
    ),
  );
}

List<Widget> _buildToolEngineStatusDetails<T extends WebEngineSampleBase>({
  required BuildContext context,
  required bool inCooldown,
  required int? cooldownUntilMs,
  required String? quotaError,
  required VoidCallback onResetCooldown,
  required List<T> samples,
}) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  return <Widget>[
    if (inCooldown || quotaError != null)
      Padding(
        padding: const EdgeInsets.only(top: 4, left: 98),
        child: Row(
          children: [
            if (inCooldown) ...[
              _SettingsStatusChip(
                icon: Icons.pause_circle_outline,
                label: openHandLocalizedText(
                  context,
                  zh: '降级中 · 剩余 ${_settingsFormatRemainingUntilMs(cooldownUntilMs)}',
                  en: 'cooldown · ${_settingsFormatRemainingUntilMs(cooldownUntilMs)} left',
                ),
                backgroundColor: colorScheme.errorContainer,
                foregroundColor: colorScheme.onErrorContainer,
              ),
              kOpenHandHGap6,
              InkWell(
                onTap: onResetCooldown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: Text(
                    openHandResetLabel(context),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.primary,
                      decoration: TextDecoration.underline,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ],
            if (quotaError != null) ...[
              if (inCooldown) kOpenHandHGap6,
              Tooltip(
                message: quotaError,
                child: _SettingsStatusChip(
                  icon: Icons.speed,
                  label: openHandLocalizedText(
                    context,
                    zh: '配额/限流',
                    en: 'rate limit',
                  ),
                  backgroundColor: colorScheme.tertiaryContainer,
                  foregroundColor: colorScheme.onTertiaryContainer,
                ),
              ),
            ],
          ],
        ),
      ),
    if (samples.length >= 2)
      Padding(
        padding: const EdgeInsets.only(top: 4, left: 98),
        child: SizedBox(
          width: 240,
          height: 28,
          child: CustomPaint(
            painter: _ToolTelemetrySparklinePainter<T>(
              samples: samples,
              successColor: Colors.green.shade600,
              failureColor: colorScheme.error,
              lineColor: colorScheme.primary.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
  ];
}

(Color, Color, String) _toolCacheStatusStyle(
  ColorScheme colorScheme,
  String status,
) {
  return switch (status) {
    'hit' => (
      colorScheme.primaryContainer,
      colorScheme.onPrimaryContainer,
      'cache hit',
    ),
    'miss-stored' => (
      colorScheme.tertiaryContainer,
      colorScheme.onTertiaryContainer,
      'fresh',
    ),
    'miss-empty' => (
      colorScheme.surfaceContainerHighest,
      colorScheme.onSurfaceVariant,
      'empty',
    ),
    'disabled' => (
      colorScheme.surfaceContainerHighest,
      colorScheme.onSurfaceVariant,
      'cache off',
    ),
    'bypass' => (
      colorScheme.errorContainer,
      colorScheme.onErrorContainer,
      'bypass',
    ),
    _ => (
      colorScheme.surfaceContainerHighest,
      colorScheme.onSurfaceVariant,
      status,
    ),
  };
}

Widget _buildToolCallLogRow({
  required BuildContext context,
  required int timestampMs,
  required String cacheStatus,
  required String title,
  required String summary,
  required List<({String label, bool success})> engineResults,
}) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  final (chipBackground, chipForeground, chipLabel) = _toolCacheStatusStyle(
    colorScheme,
    cacheStatus,
  );
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            _settingsFormatMonthDayHmsFromEpochMs(timestampMs),
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: kOpenHandMonospaceFontFamily,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        kOpenHandHGap6,
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: chipBackground,
            borderRadius: kOpenHandBorderRadius4,
          ),
          child: Text(
            chipLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: chipForeground,
              fontSize: 11,
            ),
          ),
        ),
        kOpenHandHGap8,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              Text(
                summary,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (engineResults.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: engineResults
                        .map(
                          (result) => Text(
                            result.label,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: kOpenHandMonospaceFontFamily,
                              fontSize: 10,
                              color: result.success
                                  ? colorScheme.onSurfaceVariant
                                  : colorScheme.error,
                            ),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ToolAdvancedNumberRow extends StatelessWidget {
  const _ToolAdvancedNumberRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          SizedBox(
            width: 100,
            child: _SettingsIntField(
              value: value,
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolAdvancedCooldownTierRow extends StatelessWidget {
  const _ToolAdvancedCooldownTierRow({
    required this.label,
    required this.failures,
    required this.seconds,
    required this.onChangedFailures,
    required this.onChangedSeconds,
  });

  final String label;
  final int failures;
  final int seconds;
  final ValueChanged<int> onChangedFailures;
  final ValueChanged<int> onChangedSeconds;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 56, child: Text(label, style: textStyle)),
          Text(
            openHandLocalizedText(context, zh: '连续失败 ', en: 'fails ≥ '),
            style: textStyle,
          ),
          SizedBox(
            width: 60,
            child: _SettingsIntField(
              value: failures,
              min: AiWebEngineResiliencePolicy.minCooldownFailures,
              max: AiWebEngineResiliencePolicy.maxCooldownFailures,
              onChanged: onChangedFailures,
            ),
          ),
          Text(
            openHandLocalizedText(
              context,
              zh: ' 次  →  冷却 ',
              en: '  →  cooldown ',
            ),
            style: textStyle,
          ),
          SizedBox(
            width: 80,
            child: _SettingsIntField(
              value: seconds,
              min: AiWebEngineResiliencePolicy.minCooldownSeconds,
              max: AiWebEngineResiliencePolicy.maxCooldownSeconds,
              onChanged: onChangedSeconds,
            ),
          ),
          Text(
            openHandLocalizedText(context, zh: ' 秒', en: ' s'),
            style: textStyle,
          ),
        ],
      ),
    );
  }
}

List<Widget> _buildWebEngineResilienceSettingsSection({
  required BuildContext context,
  required ThemeData theme,
  required ColorScheme colorScheme,
  required AiWebEngineResilienceSettings resilience,
  required ValueChanged<AiWebEngineResilienceSettings> onChanged,
}) {
  return [
    Text(
      openHandLocalizedText(
        context,
        zh: '高级（健壮性）',
        en: 'Advanced (resilience)',
      ),
      style: theme.textTheme.titleSmall,
    ),
    kOpenHandGap8,
    Text(
      openHandLocalizedText(
        context,
        zh: '失败自动降级（cooldown）阈值',
        en: 'Failure auto-cooldown thresholds',
      ),
      style: theme.textTheme.bodySmall?.copyWith(
        color: colorScheme.onSurfaceVariant,
      ),
    ),
    kOpenHandGap6,
    _ToolAdvancedCooldownTierRow(
      label: openHandLocalizedText(context, zh: '一级', en: 'Tier 1'),
      failures: resilience.cooldownTier1Failures,
      seconds: resilience.cooldownTier1Seconds,
      onChangedFailures: (value) =>
          onChanged(resilience.copyWith(cooldownTier1Failures: value)),
      onChangedSeconds: (value) =>
          onChanged(resilience.copyWith(cooldownTier1Seconds: value)),
    ),
    _ToolAdvancedCooldownTierRow(
      label: openHandLocalizedText(context, zh: '二级', en: 'Tier 2'),
      failures: resilience.cooldownTier2Failures,
      seconds: resilience.cooldownTier2Seconds,
      onChangedFailures: (value) =>
          onChanged(resilience.copyWith(cooldownTier2Failures: value)),
      onChangedSeconds: (value) =>
          onChanged(resilience.copyWith(cooldownTier2Seconds: value)),
    ),
    _ToolAdvancedCooldownTierRow(
      label: openHandLocalizedText(context, zh: '三级', en: 'Tier 3'),
      failures: resilience.cooldownTier3Failures,
      seconds: resilience.cooldownTier3Seconds,
      onChangedFailures: (value) =>
          onChanged(resilience.copyWith(cooldownTier3Failures: value)),
      onChangedSeconds: (value) =>
          onChanged(resilience.copyWith(cooldownTier3Seconds: value)),
    ),
    kOpenHandGap4,
    _ToolAdvancedNumberRow(
      label: openHandLocalizedText(
        context,
        zh: '配额/限流冷却（秒）',
        en: 'Quota cooldown (s)',
      ),
      value: resilience.cooldownQuotaSeconds,
      min: AiWebEngineResiliencePolicy.minCooldownSeconds,
      max: AiWebEngineResiliencePolicy.maxCooldownSeconds,
      onChanged: (value) =>
          onChanged(resilience.copyWith(cooldownQuotaSeconds: value)),
    ),
    kOpenHandGap12,
    Text(
      openHandLocalizedText(
        context,
        zh: '健康度告警（0 = 关闭，至少 5 次调用后才会触发）',
        en: 'Health alerts (0 = off; needs ≥5 calls)',
      ),
      style: theme.textTheme.bodySmall?.copyWith(
        color: colorScheme.onSurfaceVariant,
      ),
    ),
    kOpenHandGap6,
    _ToolAdvancedNumberRow(
      label: openHandLocalizedText(
        context,
        zh: '成功率低于（%）',
        en: 'Success rate below (%)',
      ),
      value: resilience.alertSuccessRatePct,
      min: 0,
      max: AiWebEngineResiliencePolicy.maxAlertSuccessRatePct,
      onChanged: (value) =>
          onChanged(resilience.copyWith(alertSuccessRatePct: value)),
    ),
    _ToolAdvancedNumberRow(
      label: openHandLocalizedText(
        context,
        zh: '平均耗时高于（毫秒）',
        en: 'Avg duration above (ms)',
      ),
      value: resilience.alertAvgDurationMs,
      min: 0,
      max: AiWebEngineResiliencePolicy.maxAlertAvgDurationMs,
      onChanged: (value) =>
          onChanged(resilience.copyWith(alertAvgDurationMs: value)),
    ),
    kOpenHandGap12,
    Text(
      openHandLocalizedText(
        context,
        zh: '速率限制（每引擎每分钟最大调用数；0 = 不限）',
        en: 'Rate limit (per engine, per minute; 0 = off)',
      ),
      style: theme.textTheme.bodySmall?.copyWith(
        color: colorScheme.onSurfaceVariant,
      ),
    ),
    kOpenHandGap6,
    _ToolAdvancedNumberRow(
      label: openHandLocalizedText(context, zh: '上限', en: 'Cap'),
      value: resilience.throttlePerMinute,
      min: 0,
      max: AiWebEngineResiliencePolicy.maxThrottlePerMinute,
      onChanged: (value) =>
          onChanged(resilience.copyWith(throttlePerMinute: value)),
    ),
  ];
}

class _ToolTelemetrySparklinePainter<T extends WebEngineSampleBase>
    extends CustomPainter {
  const _ToolTelemetrySparklinePainter({
    required this.samples,
    required this.successColor,
    required this.failureColor,
    required this.lineColor,
  });

  static const int _maxSamples = 50;
  static const double _verticalInset = 2;
  static const double _lineWidth = 1.2;
  static const double _dotRadius = 1.6;

  final List<T> samples;
  final Color successColor;
  final Color failureColor;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) return;
    final tail = samples.length > _maxSamples
        ? samples.sublist(samples.length - _maxSamples)
        : samples;
    final maxDuration = tail.fold<int>(0, (current, sample) {
      final duration = sample.durationMs;
      return duration > current ? duration : current;
    });
    final scaleY = maxDuration == 0
        ? 0.0
        : (size.height - _verticalInset * 2) / maxDuration;
    final stepX = size.width / (tail.length - 1);

    Offset pointAt(int index) => Offset(
      index * stepX,
      size.height - _verticalInset - tail[index].durationMs * scaleY,
    );

    final firstPoint = pointAt(0);
    final path = Path()..moveTo(firstPoint.dx, firstPoint.dy);
    for (var index = 1; index < tail.length; index++) {
      final point = pointAt(index);
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..strokeWidth = _lineWidth
        ..style = PaintingStyle.stroke,
    );

    final successPaint = Paint()..color = successColor;
    final failurePaint = Paint()..color = failureColor;
    for (var index = 0; index < tail.length; index++) {
      canvas.drawCircle(
        pointAt(index),
        _dotRadius,
        tail[index].success ? successPaint : failurePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ToolTelemetrySparklinePainter<T> old) {
    return old.samples != samples ||
        old.successColor != successColor ||
        old.failureColor != failureColor ||
        old.lineColor != lineColor;
  }
}

enum _SettingsSection {
  header,
  general,
  shortcuts,
  ai,
  activeToolCalls,
  builtinTools,
  mcp,
  skills,
  memory,
  crons,
  hermesTalker,
  editor,
  appData,
  system,
  about,
}

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

/// 打开统一的 AI 模型编辑弹窗；保存后返回 `true`。
Future<bool> showAiModelEditorDialog(
  BuildContext context, {
  AiModelConfig? initialModel,
}) async {
  final submitted = await showAnimatedDialog<bool>(
    context: context,
    builder: (dialogContext) =>
        _AiModelEditorDialog(initialModel: initialModel),
  );
  return submitted == true;
}

/// 复用全局设置中的完整模型参数编辑器，供中转站配置暴露模型。
Future<AiModelProfileEditorResult?> showAiModelProfileEditorDialog(
  BuildContext context, {
  required String modelId,
  required AiModelProfile initialProfile,
  required AiModelProfile effectiveProfile,
  required AiProtocolType protocolType,
  List<String> existingModelIds = const <String>[],
}) async {
  final result = await showAnimatedDialog<_ModelProfileEditorResult>(
    context: context,
    builder: (_) => _ModelProfileEditorDialog(
      modelId: modelId,
      existingModelIds: existingModelIds,
      initialProfile: initialProfile,
      effectiveProfile: effectiveProfile,
      protocolType: protocolType,
      showDuplicateAction: false,
      onDuplicate: (sourceModelId, _) => sourceModelId,
    ),
  );
  if (result == null) return null;
  return AiModelProfileEditorResult(
    modelId: result.modelId,
    profile: result.profile,
  );
}

class AiModelProfileEditorResult {
  const AiModelProfileEditorResult({
    required this.modelId,
    required this.profile,
  });

  final String modelId;
  final AiModelProfile profile;
}

String _aiModelProxyEndpointBlockedMessage(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '该 Base URL 指向 OpenHand 当前的 AI 模型中转站，不能作为模型提供商，以避免请求无限循环。',
    zhHant: '此 Base URL 指向 OpenHand 目前的 AI 模型中轉站，不能作為模型提供商，以避免請求無限循環。',
    en: "This Base URL points to OpenHand's current AI model proxy and cannot be used as a provider to prevent request loops.",
    fr: "Cette URL de base pointe vers le proxy de modèles IA actuel d'OpenHand et ne peut pas servir de fournisseur afin d'éviter les boucles de requêtes.",
    de: 'Diese Basis-URL verweist auf den aktuellen OpenHand-KI-Modellproxy und kann zur Vermeidung von Anforderungsschleifen nicht als Anbieter verwendet werden.',
    ja: 'この Base URL は OpenHand の現在の AI モデルプロキシを指すため、リクエストのループを防ぐ目的でプロバイダーには使用できません。',
  );
}

/// 测试模型提供商并保存已探测的接口类型。
Future<void> testAiModelConfiguration(
  BuildContext context,
  AiModelConfig model,
) async {
  final settingsController = context.read<SettingsController>();
  if (settingsController.isAiModelProviderEndpointBlocked(model.baseUrl)) {
    showOpenHandErrorSnack(
      context,
      _aiModelProxyEndpointBlockedMessage(context),
    );
    return;
  }
  final service = AiChatService();
  try {
    final result = await service.testModel(model);
    if (!context.mounted) return;
    final remembersChatRoute =
        result.chatApiFamily == AiApiFamily.responses ||
        result.chatApiFamily == AiApiFamily.chatCompletions;
    if (remembersChatRoute) {
      final saved = await context
          .read<SettingsController>()
          .updateAiModelVerifiedChatApiFamily(model.id, result.chatApiFamily);
      if (!context.mounted) return;
      if (!saved) {
        showOpenHandErrorSnack(
          context,
          AppLocalizations.of(context)!.settingsPersistenceSaveFailedBody,
        );
        return;
      }
    }
    final endpointLabel = switch (result.chatApiFamily) {
      AiApiFamily.responses => 'Responses',
      AiApiFamily.chatCompletions => 'Chat Completions',
      _ => null,
    };
    final routeMessage = endpointLabel == null
        ? ''
        : openHandLocalizedText(
            context,
            zh: '已记住 $endpointLabel 接口。',
            zhHant: '已記住 $endpointLabel 介面。',
            en: '$endpointLabel endpoint saved.',
            fr: 'Endpoint $endpointLabel enregistré.',
            de: '$endpointLabel-Endpunkt gespeichert.',
            ja: '$endpointLabel エンドポイントを保存しました。',
          );
    final l10n = AppLocalizations.of(context)!;
    flashOpenHandSnack(
      context,
      '${l10n.aiModelTestSuccess(model.providerLabel)}${routeMessage.isEmpty ? '' : ' $routeMessage'}',
      kind: OpenHandSnackKind.success,
    );
  } on AiChatException catch (error) {
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context)!;
    showFriendlyErrorSnackBar(
      context,
      message: l10n.aiModelTestFailure(
        model.providerLabel,
        _normalizeAiModelCardTestMessage(error.message, l10n.chatRequestFailed),
      ),
      fallback: l10n.chatRequestFailed,
      sources: error.sources,
    );
  } catch (error) {
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context)!;
    showFriendlyErrorSnackBar(
      context,
      message: l10n.aiModelTestFailure(
        model.providerLabel,
        _normalizeAiModelCardTestMessage('$error', l10n.chatRequestFailed),
      ),
      fallback: l10n.chatRequestFailed,
    );
  } finally {
    service.dispose();
  }
}

String _normalizeAiModelCardTestMessage(String raw, String fallback) {
  final lines = raw
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
      .where((line) => line.isNotEmpty);
  final normalized = lines.join('\n').trim();
  return normalized.isEmpty ? fallback : normalized;
}

/// 构建统一的模型提供商卡片，供设置页与中转站提供商弹窗复用。
Widget buildAiModelProviderCard({
  required AiModelConfig model,
  required int dragIndex,
  required bool isSelected,
  required bool isTesting,
  required bool isFirst,
  required bool isLast,
  required bool actionsEnabled,
  required VoidCallback onSelect,
  required VoidCallback onTest,
  required VoidCallback onHealthCheck,
  required VoidCallback onHealthCheckCancel,
  required VoidCallback onEdit,
  required VoidCallback onMoveUp,
  required VoidCallback onMoveDown,
  required VoidCallback onDelete,
  required void Function(String modelId) onActiveModelChanged,
}) {
  return _AiModelTile(
    model: model,
    dragIndex: dragIndex,
    isSelected: isSelected,
    isTesting: isTesting,
    isFirst: isFirst,
    isLast: isLast,
    actionsEnabled: actionsEnabled,
    onSelect: onSelect,
    onTest: onTest,
    onHealthCheck: onHealthCheck,
    onHealthCheckCancel: onHealthCheckCancel,
    onEdit: onEdit,
    onMoveUp: onMoveUp,
    onMoveDown: onMoveDown,
    onDelete: onDelete,
    onActiveModelChanged: onActiveModelChanged,
  );
}

class _SettingsViewState extends State<SettingsView> {
  late final TextEditingController _skillsPathController;
  late final FocusNode _skillsPathFocusNode;
  late final TextEditingController _memoryFileController;
  late final FocusNode _memoryFileFocusNode;
  late final ScrollController _editorLspListScrollController;
  late final ScrollController _shortcutListScrollController;
  late final ScrollController _editorShortcutListScrollController;
  late final TextEditingController _compressionThresholdController;
  late final FocusNode _compressionThresholdFocusNode;
  late final TextEditingController _toolResultCompressionThresholdController;
  late final FocusNode _toolResultCompressionThresholdFocusNode;
  late final TextEditingController _aiInputCacheUpdateIntervalController;
  late final FocusNode _aiInputCacheUpdateIntervalFocusNode;
  late final TextEditingController _aiInputCacheBreakpointCountController;
  late final FocusNode _aiInputCacheBreakpointCountFocusNode;
  late final TextEditingController _aiBudgetUsdPerSessionController;
  late final FocusNode _aiBudgetUsdPerSessionFocusNode;
  late final TextEditingController
  _toolResultCompressionHeadTailWindowController;
  late final FocusNode _toolResultCompressionHeadTailWindowFocusNode;
  late final TextEditingController _toolResultCompressionMaxPathHitsController;
  late final FocusNode _toolResultCompressionMaxPathHitsFocusNode;
  late final TextEditingController _writeToolSummaryMaxCharsController;
  late final FocusNode _writeToolSummaryMaxCharsFocusNode;
  late final TextEditingController _toolCallLimitController;
  late final FocusNode _toolCallLimitFocusNode;
  late final TextEditingController _sequentialToolRoundLimitController;
  late final FocusNode _sequentialToolRoundLimitFocusNode;
  late final TextEditingController _maxRecentErrorsController;
  late final FocusNode _maxRecentErrorsFocusNode;
  late final TextEditingController _maxPlanHistoryEntriesController;
  late final FocusNode _maxPlanHistoryEntriesFocusNode;
  late final TextEditingController _maxTruncationContinuationsController;
  late final FocusNode _maxTruncationContinuationsFocusNode;
  late final TextEditingController _estimatedCharactersPerTokenController;
  late final FocusNode _estimatedCharactersPerTokenFocusNode;
  late final TextEditingController _imageSizeLimitController;
  late final FocusNode _imageSizeLimitFocusNode;
  late final TextEditingController _connectTimeoutController;
  late final FocusNode _connectTimeoutFocusNode;
  late final TextEditingController _responseTimeoutController;
  late final FocusNode _responseTimeoutFocusNode;
  late final TextEditingController _streamIdleTimeoutController;
  late final FocusNode _streamIdleTimeoutFocusNode;
  late final TextEditingController _streamMaxCharsPerSecondController;
  late final FocusNode _streamMaxCharsPerSecondFocusNode;
  late final TextEditingController _streamMaxMessageCardsPerSecondController;
  late final FocusNode _streamMaxMessageCardsPerSecondFocusNode;
  late final TextEditingController _streamThrottleDurationController;
  late final FocusNode _streamThrottleDurationFocusNode;
  late final TextEditingController _mcpLazyLoadingThresholdController;
  late final FocusNode _mcpLazyLoadingThresholdFocusNode;
  late final TextEditingController _mcpAutoProbeConcurrencyController;
  late final FocusNode _mcpAutoProbeConcurrencyFocusNode;
  final Set<String> _testingAiModelIds = <String>{};
  final Set<String> _mutatingAiModelIds = <String>{};
  final Set<String> _removingAiModelIds = <String>{};
  bool _isSyncingOpenRouterModels = false;
  final List<AiModelConfig> _animatedAiModels = <AiModelConfig>[];
  final OpenHandKeyedSingleFlight<String, void> _editorLspManifestRefreshes =
      OpenHandKeyedSingleFlight<String, void>();
  final AiTtsPlaybackService _ttsSettingsPlaybackService =
      AiTtsPlaybackService();

  void _refreshEditorLspManifestState() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _skillsPathController = TextEditingController();
    _skillsPathFocusNode = FocusNode();
    _memoryFileController = TextEditingController();
    _memoryFileFocusNode = FocusNode();
    _editorLspListScrollController = ScrollController();
    _shortcutListScrollController = ScrollController();
    _editorShortcutListScrollController = ScrollController();
    _compressionThresholdController = TextEditingController();
    _compressionThresholdFocusNode = FocusNode();
    _toolResultCompressionThresholdController = TextEditingController();
    _toolResultCompressionThresholdFocusNode = FocusNode();
    _aiInputCacheUpdateIntervalController = TextEditingController();
    _aiInputCacheUpdateIntervalFocusNode = FocusNode();
    _aiInputCacheBreakpointCountController = TextEditingController();
    _aiInputCacheBreakpointCountFocusNode = FocusNode();
    _aiBudgetUsdPerSessionController = TextEditingController();
    _aiBudgetUsdPerSessionFocusNode = FocusNode();
    _toolResultCompressionHeadTailWindowController = TextEditingController();
    _toolResultCompressionHeadTailWindowFocusNode = FocusNode();
    _toolResultCompressionMaxPathHitsController = TextEditingController();
    _toolResultCompressionMaxPathHitsFocusNode = FocusNode();
    _writeToolSummaryMaxCharsController = TextEditingController();
    _writeToolSummaryMaxCharsFocusNode = FocusNode();
    _toolCallLimitController = TextEditingController();
    _toolCallLimitFocusNode = FocusNode();
    _sequentialToolRoundLimitController = TextEditingController();
    _sequentialToolRoundLimitFocusNode = FocusNode();
    _maxRecentErrorsController = TextEditingController();
    _maxRecentErrorsFocusNode = FocusNode();
    _maxPlanHistoryEntriesController = TextEditingController();
    _maxPlanHistoryEntriesFocusNode = FocusNode();
    _maxTruncationContinuationsController = TextEditingController();
    _maxTruncationContinuationsFocusNode = FocusNode();
    _estimatedCharactersPerTokenController = TextEditingController();
    _estimatedCharactersPerTokenFocusNode = FocusNode();
    _imageSizeLimitController = TextEditingController();
    _imageSizeLimitFocusNode = FocusNode();
    _connectTimeoutController = TextEditingController();
    _connectTimeoutFocusNode = FocusNode();
    _responseTimeoutController = TextEditingController();
    _responseTimeoutFocusNode = FocusNode();
    _streamIdleTimeoutController = TextEditingController();
    _streamIdleTimeoutFocusNode = FocusNode();
    _streamMaxCharsPerSecondController = TextEditingController();
    _streamMaxCharsPerSecondFocusNode = FocusNode();
    _streamMaxMessageCardsPerSecondController = TextEditingController();
    _streamMaxMessageCardsPerSecondFocusNode = FocusNode();
    _streamThrottleDurationController = TextEditingController();
    _streamThrottleDurationFocusNode = FocusNode();
    _mcpLazyLoadingThresholdController = TextEditingController();
    _mcpLazyLoadingThresholdFocusNode = FocusNode();
    _mcpAutoProbeConcurrencyController = TextEditingController();
    _mcpAutoProbeConcurrencyFocusNode = FocusNode();
  }

  void _syncAnimatedAiModels(List<AiModelConfig> aiModels) {
    if (_mutatingAiModelIds.isNotEmpty) {
      final ids = aiModels.map((model) => model.id).toSet();
      _testingAiModelIds.removeWhere((id) => !ids.contains(id));
      return;
    }
    final sameLength = _animatedAiModels.length == aiModels.length;
    final sameOrder =
        sameLength &&
        _animatedAiModels.asMap().entries.every(
          (entry) => entry.value.id == aiModels[entry.key].id,
        );
    if (sameOrder) {
      _animatedAiModels
        ..clear()
        ..addAll(aiModels);
      final ids = aiModels.map((model) => model.id).toSet();
      _testingAiModelIds.removeWhere((id) => !ids.contains(id));
      return;
    }
    _animatedAiModels
      ..clear()
      ..addAll(aiModels);
    _testingAiModelIds.removeWhere(
      (id) => !_animatedAiModels.any((model) => model.id == id),
    );
  }

  int _indexOfAnimatedAiModel(String id) {
    return _animatedAiModels.indexWhere((model) => model.id == id);
  }

  Widget _buildAiModelRow(BuildContext context, AiModelConfig model) {
    final settingsController = context.read<SettingsController>();
    final index = _indexOfAnimatedAiModel(model.id);
    final isPresent = index != -1;
    final isMutating = _mutatingAiModelIds.contains(model.id);
    return Padding(
      key: ValueKey<String>(model.id),
      padding: const EdgeInsets.only(bottom: 14),
      child: OpenHandListRemovalTransition(
        collapsed: _removingAiModelIds.contains(model.id),
        child: buildAiModelProviderCard(
          model: model,
          dragIndex: index < 0 ? 0 : index,
          isSelected: settingsController.selectedAiModelId == model.id,
          isTesting: _testingAiModelIds.contains(model.id),
          isFirst: !isPresent || index == 0,
          isLast: !isPresent || index == _animatedAiModels.length - 1,
          actionsEnabled: isPresent && !isMutating,
          onSelect: isPresent
              ? () => settingsController.updateSelectedAiModel(model.id)
              : () {},
          onTest: isPresent ? () => _testAiModel(model) : () {},
          onHealthCheck: isPresent
              ? () =>
                    context.read<AiModelHealthController>().checkProvider(model)
              : () {},
          onHealthCheckCancel: context
              .read<AiModelHealthController>()
              .cancelCheck,
          onEdit: isPresent
              ? () => _showAiModelDialog(context, initialModel: model)
              : () {},
          onMoveUp: isPresent ? () => _moveAiModel(model.id, -1) : () {},
          onMoveDown: isPresent ? () => _moveAiModel(model.id, 1) : () {},
          onDelete: isPresent
              ? () => _confirmDeleteAiModel(context, model)
              : () {},
          onActiveModelChanged: isPresent
              ? (modelId) => settingsController.updateProviderActiveModel(
                  model.id,
                  modelId,
                  alsoSelectProvider: false,
                )
              : (_) {},
        ),
      ),
    );
  }

  Future<void> _deleteAiModelWithAnimation(AiModelConfig model) async {
    final settingsController = context.read<SettingsController>();
    final l10n = AppLocalizations.of(context)!;
    final index = _indexOfAnimatedAiModel(model.id);
    if (index == -1) {
      final deleted = await settingsController.deleteAiModel(model.id);
      if (!mounted) return;
      if (!deleted) {
        _showPersistenceFailureSnackBar(context);
        return;
      }
      flashOpenHandSnack(
        context,
        l10n.aiModelDeleteSuccess,
        kind: OpenHandSnackKind.success,
      );
      return;
    }
    setState(() {
      _mutatingAiModelIds.add(model.id);
      _removingAiModelIds.add(model.id);
    });
    await awaitOpenHandListRemoval(context);
    final deleted = await settingsController.deleteAiModel(model.id);
    if (!mounted) return;
    if (!deleted) {
      setState(() {
        _removingAiModelIds.remove(model.id);
        _mutatingAiModelIds.remove(model.id);
      });
      _showPersistenceFailureSnackBar(context);
      return;
    }
    setState(() {
      final currentIndex = _indexOfAnimatedAiModel(model.id);
      if (currentIndex != -1) _animatedAiModels.removeAt(currentIndex);
      _removingAiModelIds.remove(model.id);
      _mutatingAiModelIds.remove(model.id);
      _testingAiModelIds.remove(model.id);
    });
    flashOpenHandSnack(
      context,
      l10n.aiModelDeleteSuccess,
      kind: OpenHandSnackKind.success,
    );
  }

  Future<void> _moveAiModel(String id, int direction) async {
    if (_mutatingAiModelIds.isNotEmpty) {
      return;
    }
    final fromIndex = _indexOfAnimatedAiModel(id);
    final toIndex = fromIndex + direction;
    if (fromIndex < 0 ||
        toIndex < 0 ||
        toIndex >= _animatedAiModels.length ||
        fromIndex == toIndex) {
      return;
    }
    final settingsController = context.read<SettingsController>();
    final model = _animatedAiModels[fromIndex];
    setState(() {
      _mutatingAiModelIds.add(id);
      _animatedAiModels
        ..removeAt(fromIndex)
        ..insert(toIndex, model);
    });
    final moved = await settingsController.moveAiModel(fromIndex, toIndex);
    if (!mounted) return;
    if (!moved) {
      final rollbackIndex = _indexOfAnimatedAiModel(id);
      setState(() {
        if (rollbackIndex != -1) {
          _animatedAiModels
            ..removeAt(rollbackIndex)
            ..insert(fromIndex, model);
        }
        _mutatingAiModelIds.remove(id);
      });
      _showPersistenceFailureSnackBar(context);
      return;
    }
    setState(() {
      _mutatingAiModelIds.remove(id);
    });
  }

  Future<void> _reorderAiModels(int oldIndex, int newIndex) async {
    if (_mutatingAiModelIds.isNotEmpty) return;
    if (oldIndex < 0 ||
        oldIndex >= _animatedAiModels.length ||
        newIndex < 0 ||
        newIndex >= _animatedAiModels.length ||
        oldIndex == newIndex) {
      return;
    }
    dismissOpenHandTooltipsSafely(debugLabel: '拖动模型提供商前收起工具提示');
    final model = _animatedAiModels[oldIndex];
    setState(() {
      _mutatingAiModelIds.add(model.id);
      _animatedAiModels
        ..removeAt(oldIndex)
        ..insert(newIndex, model);
    });
    final moved = await context.read<SettingsController>().moveAiModel(
      oldIndex,
      newIndex,
    );
    if (!mounted) return;
    if (!moved) {
      final currentIndex = _indexOfAnimatedAiModel(model.id);
      setState(() {
        if (currentIndex != -1) {
          _animatedAiModels
            ..removeAt(currentIndex)
            ..insert(oldIndex, model);
        }
        _mutatingAiModelIds.remove(model.id);
      });
      _showPersistenceFailureSnackBar(context);
      return;
    }
    setState(() => _mutatingAiModelIds.remove(model.id));
  }

  @override
  void dispose() {
    _skillsPathController.dispose();
    _skillsPathFocusNode.dispose();
    _memoryFileController.dispose();
    _memoryFileFocusNode.dispose();
    _editorLspListScrollController.dispose();
    _shortcutListScrollController.dispose();
    _editorShortcutListScrollController.dispose();
    _compressionThresholdController.dispose();
    _compressionThresholdFocusNode.dispose();
    _toolResultCompressionThresholdController.dispose();
    _toolResultCompressionThresholdFocusNode.dispose();
    _aiInputCacheUpdateIntervalController.dispose();
    _aiInputCacheUpdateIntervalFocusNode.dispose();
    _aiInputCacheBreakpointCountController.dispose();
    _aiInputCacheBreakpointCountFocusNode.dispose();
    _aiBudgetUsdPerSessionController.dispose();
    _aiBudgetUsdPerSessionFocusNode.dispose();
    _toolResultCompressionHeadTailWindowController.dispose();
    _toolResultCompressionHeadTailWindowFocusNode.dispose();
    _toolResultCompressionMaxPathHitsController.dispose();
    _toolResultCompressionMaxPathHitsFocusNode.dispose();
    _writeToolSummaryMaxCharsController.dispose();
    _writeToolSummaryMaxCharsFocusNode.dispose();
    _toolCallLimitController.dispose();
    _toolCallLimitFocusNode.dispose();
    _sequentialToolRoundLimitController.dispose();
    _sequentialToolRoundLimitFocusNode.dispose();
    _maxRecentErrorsController.dispose();
    _maxRecentErrorsFocusNode.dispose();
    _maxPlanHistoryEntriesController.dispose();
    _maxPlanHistoryEntriesFocusNode.dispose();
    _maxTruncationContinuationsController.dispose();
    _maxTruncationContinuationsFocusNode.dispose();
    _estimatedCharactersPerTokenController.dispose();
    _estimatedCharactersPerTokenFocusNode.dispose();
    _imageSizeLimitController.dispose();
    _imageSizeLimitFocusNode.dispose();
    _connectTimeoutController.dispose();
    _connectTimeoutFocusNode.dispose();
    _responseTimeoutController.dispose();
    _responseTimeoutFocusNode.dispose();
    _streamIdleTimeoutController.dispose();
    _streamIdleTimeoutFocusNode.dispose();
    _streamMaxCharsPerSecondController.dispose();
    _streamMaxCharsPerSecondFocusNode.dispose();
    _streamMaxMessageCardsPerSecondController.dispose();
    _streamMaxMessageCardsPerSecondFocusNode.dispose();
    _streamThrottleDurationController.dispose();
    _streamThrottleDurationFocusNode.dispose();
    _mcpLazyLoadingThresholdController.dispose();
    _mcpLazyLoadingThresholdFocusNode.dispose();
    _mcpAutoProbeConcurrencyController.dispose();
    _mcpAutoProbeConcurrencyFocusNode.dispose();
    unawaited(_ttsSettingsPlaybackService.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsController = context.watch<SettingsController>();
    final appInfo = context.read<AppInfo>();

    // 受控输入回填：设置变化时同步文本框；焦点停留在输入框上时保留用户正在输入的内容。
    final syncedTextFields = <(TextEditingController, FocusNode, String)>[
      (
        _skillsPathController,
        _skillsPathFocusNode,
        settingsController.skillsStoragePath,
      ),
      (
        _compressionThresholdController,
        _compressionThresholdFocusNode,
        '${settingsController.aiMessageCompressionThresholdChars}',
      ),
      (
        _toolResultCompressionThresholdController,
        _toolResultCompressionThresholdFocusNode,
        '${settingsController.aiToolResultCompressionThresholdChars}',
      ),
      (
        _toolResultCompressionHeadTailWindowController,
        _toolResultCompressionHeadTailWindowFocusNode,
        '${settingsController.aiToolResultCompressionHeadTailWindowChars}',
      ),
      (
        _toolResultCompressionMaxPathHitsController,
        _toolResultCompressionMaxPathHitsFocusNode,
        '${settingsController.aiToolResultCompressionMaxPathHits}',
      ),
      (
        _aiInputCacheUpdateIntervalController,
        _aiInputCacheUpdateIntervalFocusNode,
        '${settingsController.aiInputCacheUpdateInterval}',
      ),
      (
        _aiInputCacheBreakpointCountController,
        _aiInputCacheBreakpointCountFocusNode,
        '${settingsController.aiInputCacheBreakpointCount}',
      ),
      (
        _aiBudgetUsdPerSessionController,
        _aiBudgetUsdPerSessionFocusNode,
        _formatBudgetUsd(settingsController.aiBudgetUsdPerSession),
      ),
      (
        _writeToolSummaryMaxCharsController,
        _writeToolSummaryMaxCharsFocusNode,
        '${settingsController.aiWriteToolSummaryMaxChars}',
      ),
      (
        _toolCallLimitController,
        _toolCallLimitFocusNode,
        '${settingsController.aiSingleRoundToolCallLimit}',
      ),
      (
        _sequentialToolRoundLimitController,
        _sequentialToolRoundLimitFocusNode,
        '${settingsController.aiSequentialToolRoundLimit}',
      ),
      (
        _maxRecentErrorsController,
        _maxRecentErrorsFocusNode,
        '${settingsController.aiMaxRecentErrors}',
      ),
      (
        _maxPlanHistoryEntriesController,
        _maxPlanHistoryEntriesFocusNode,
        '${settingsController.aiMaxPlanHistoryEntries}',
      ),
      (
        _maxTruncationContinuationsController,
        _maxTruncationContinuationsFocusNode,
        '${settingsController.aiMaxTruncationContinuations}',
      ),
      (
        _estimatedCharactersPerTokenController,
        _estimatedCharactersPerTokenFocusNode,
        '${settingsController.aiEstimatedCharactersPerToken}',
      ),
      (
        _imageSizeLimitController,
        _imageSizeLimitFocusNode,
        formatMegabytesInput(settingsController.aiImageSizeLimitBytes),
      ),
      (
        _connectTimeoutController,
        _connectTimeoutFocusNode,
        '${settingsController.aiConnectTimeoutSeconds}',
      ),
      (
        _responseTimeoutController,
        _responseTimeoutFocusNode,
        '${settingsController.aiResponseTimeoutSeconds}',
      ),
      (
        _streamIdleTimeoutController,
        _streamIdleTimeoutFocusNode,
        '${settingsController.aiStreamIdleTimeoutSeconds}',
      ),
      (
        _streamMaxCharsPerSecondController,
        _streamMaxCharsPerSecondFocusNode,
        '${settingsController.aiStreamMaxCharsPerSecond}',
      ),
      (
        _streamMaxMessageCardsPerSecondController,
        _streamMaxMessageCardsPerSecondFocusNode,
        '${settingsController.aiStreamMaxMessageCardsPerSecond}',
      ),
      (
        _streamThrottleDurationController,
        _streamThrottleDurationFocusNode,
        '${settingsController.aiStreamThrottleDurationSeconds}',
      ),
      (
        _mcpLazyLoadingThresholdController,
        _mcpLazyLoadingThresholdFocusNode,
        '${settingsController.mcpLazyLoadingThresholdTokens}',
      ),
      (
        _mcpAutoProbeConcurrencyController,
        _mcpAutoProbeConcurrencyFocusNode,
        '${settingsController.mcpAutoProbeConcurrency}',
      ),
    ];
    for (final (controller, focusNode, value) in syncedTextFields) {
      syncTextControllerText(controller, value, focusNode: focusNode);
    }

    final sections = <_SettingsSection>[
      _SettingsSection.header,
      _SettingsSection.general,
      _SettingsSection.shortcuts,
      _SettingsSection.ai,
      _SettingsSection.activeToolCalls,
      _SettingsSection.builtinTools,
      _SettingsSection.mcp,
      _SettingsSection.skills,
      _SettingsSection.memory,
      _SettingsSection.crons,
      _SettingsSection.hermesTalker,
      _SettingsSection.editor,
      _SettingsSection.appData,
      _SettingsSection.system,
      _SettingsSection.about,
    ];

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OpenHandVerticalRevealSwitcher(
                slideBeginOffsetY: -0.1,
                child: settingsController.persistenceIssue == null
                    ? const SizedBox.shrink(
                        key: ValueKey('settings-persistence-issue-empty'),
                      )
                    : Padding(
                        key: const ValueKey(
                          'settings-persistence-issue-active',
                        ),
                        padding: const EdgeInsets.only(bottom: 6),
                        child: _SettingsPersistenceIssueCard(
                          issue: settingsController.persistenceIssue!,
                          onDismiss: settingsController.clearPersistenceIssue,
                        ),
                      ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(0, 2, 0, 8),
                  itemCount: sections.length,
                  separatorBuilder: (context, index) => kOpenHandGap18,
                  itemBuilder: (context, index) {
                    return _buildSettingsSection(
                      context,
                      settingsController,
                      appInfo,
                      sections[index],
                    );
                  },
                ),
              ),
            ],
          ),
          // 保存成功后统一触发顶部高亮，并遵循全局动效设置。
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: _SettingsSavePulse(
                signal: settingsController.saveSuccessSignal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSection(
    BuildContext context,
    SettingsController settingsController,
    AppInfo appInfo,
    _SettingsSection section,
  ) {
    final l10n = AppLocalizations.of(context)!;
    return switch (section) {
      _SettingsSection.header => FeaturePageHeader(
        title: l10n.settingsTitle,
        subtitle: l10n.settingsSubtitle,
      ),
      _SettingsSection.general => _SettingsGroupCard(
        title: l10n.settingsCategoryGeneral,
        description: l10n.settingsGeneralSubtitle,
        children: [
          _ResponsiveSettingRow(
            title: l10n.themeSectionTitle,
            subtitle: l10n.themeSectionBody,
            controlMaxWidth: 440,
            control: SizedBox(
              width: double.infinity,
              child: SegmentedButton<ThemeMode>(
                segments: [
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.system,
                    icon: const Icon(Icons.contrast_outlined),
                    label: Text(l10n.themeSystem, softWrap: false),
                  ),
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.light,
                    icon: const Icon(Icons.light_mode_outlined),
                    label: Text(l10n.themeLight, softWrap: false),
                  ),
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.dark,
                    icon: const Icon(Icons.dark_mode_outlined),
                    label: Text(l10n.themeDark, softWrap: false),
                  ),
                ],
                selected: <ThemeMode>{settingsController.themeMode},
                onSelectionChanged: (selection) async {
                  if (selection.isEmpty) {
                    return;
                  }
                  final saved = await settingsController.updateThemeMode(
                    selection.first,
                  );
                  if (!context.mounted || saved) {
                    return;
                  }
                  _showPersistenceFailureSnackBar(context);
                },
              ),
            ),
          ),
          _ResponsiveSettingRow(
            title: l10n.themePaletteSectionTitle,
            subtitle: l10n.themePaletteSectionBody,
            controlMaxWidth: 440,
            control: SizedBox(
              width: double.infinity,
              child: AnimatedDropdownButtonFormField<OpenHandThemePreset>(
                initialValue: settingsController.themePreset,
                decoration: InputDecoration(
                  prefixIcon: Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: 12,
                      end: 8,
                    ),
                    child: _ThemePresetSwatch(
                      color: settingsController.themePreset.seedColor,
                    ),
                  ),
                ),
                items: OpenHandThemePreset.values
                    .map(
                      (preset) => DropdownMenuItem<OpenHandThemePreset>(
                        value: preset,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _ThemePresetSwatch(color: preset.seedColor),
                            kOpenHandHGap12,
                            Text(preset.label(l10n)),
                          ],
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) async {
                  if (value == null) {
                    return;
                  }
                  final saved = await settingsController.updateThemePreset(
                    value,
                  );
                  if (!context.mounted || saved) {
                    return;
                  }
                  _showPersistenceFailureSnackBar(context);
                },
              ),
            ),
          ),
          _ResponsiveSettingRow(
            title: l10n.languageSectionTitle,
            subtitle: l10n.languageSectionBody,
            controlMaxWidth: 440,
            control: SizedBox(
              width: double.infinity,
              child: AnimatedDropdownButtonFormField<AppLanguage>(
                initialValue: settingsController.language,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.translate_outlined),
                ),
                items: AppLanguage.values
                    .map(
                      (language) => DropdownMenuItem<AppLanguage>(
                        value: language,
                        child: Text(language.label(l10n)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) async {
                  if (value == null) {
                    return;
                  }
                  final saved = await settingsController.updateLanguage(value);
                  if (!context.mounted || saved) {
                    return;
                  }
                  _showPersistenceFailureSnackBar(context);
                },
              ),
            ),
          ),
          _ResponsiveSettingRow(
            title: l10n.settingsReduceMotionLabel,
            subtitle: l10n.settingsReduceMotionBody,
            controlMaxWidth: 120,
            control: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Switch(
                value: settingsController.reduceMotion,
                onChanged: (value) async {
                  final saved = await settingsController.updateReduceMotion(
                    value,
                  );
                  if (!context.mounted || saved) {
                    return;
                  }
                  _showPersistenceFailureSnackBar(context);
                },
              ),
            ),
          ),
          _AnimationRestoreDefaultsSection(
            settingsController: settingsController,
          ),
          _DialogAnimationSettingsSection(
            settingsController: settingsController,
          ),
          _MenuAnimationSettingsSection(settingsController: settingsController),
          _PageAnimationSettingsSection(settingsController: settingsController),
          _PanelAnimationSettingsSection(
            settingsController: settingsController,
          ),
          _ChipAnimationSettingsSection(settingsController: settingsController),
          _ListItemAnimationSettingsSection(
            settingsController: settingsController,
          ),
        ],
      ),
      _SettingsSection.shortcuts => _SettingsGroupCard(
        title: AppLocalizations.of(context)!.settingsShortcuts,
        description: AppLocalizations.of(
          context,
        )!.settingsConfigureKeyCombinationsForCommonActions,
        children: [_buildShortcutsSection(context, settingsController)],
      ),
      _SettingsSection.ai => _SettingsGroupCard(
        title: l10n.settingsCategoryAi,
        description: l10n.settingsAiSubtitle,
        children: [_buildAiModelsSection(context, settingsController)],
      ),
      _SettingsSection.activeToolCalls => const Column(
        children: [
          _ActiveToolCallsPanel(),
          kOpenHandGap18,
          _ToolHardeningParamsPanel(),
        ],
      ),
      _SettingsSection.builtinTools => _SettingsGroupCard(
        title: AppLocalizations.of(context)!.settingsBuiltInTools,
        description: AppLocalizations.of(
          context,
        )!.settingsManageTheBuiltInAiTools,
        children: [_buildBuiltinToolsSection(context, settingsController)],
      ),
      _SettingsSection.mcp => _SettingsGroupCard(
        title: l10n.mcpSectionTitle,
        description: l10n.mcpSectionBody,
        children: [_buildMcpSettingsSection(context, settingsController)],
      ),
      _SettingsSection.skills => _SettingsGroupCard(
        title: l10n.settingsCategorySkills,
        description: l10n.settingsSkillsSubtitle,
        children: [_buildSkillsSection(context, settingsController)],
      ),
      _SettingsSection.memory => _SettingsGroupCard(
        title: l10n.settingsCategoryMemory,
        description: l10n.settingsMemorySubtitle,
        children: [_buildMemorySection(context, settingsController)],
      ),
      _SettingsSection.crons => _SettingsGroupCard(
        title: AppLocalizations.of(context)!.settingsCrons,
        description: AppLocalizations.of(
          context,
        )!.settingsControlsRetentionAndColdStartCleanup,
        children: [_buildCronsSection(context, settingsController)],
      ),
      _SettingsSection.hermesTalker => _SettingsGroupCard(
        title: AppLocalizations.of(context)!.settingsHermesTalker,
        description: AppLocalizations.of(
          context,
        )!.settingsConfigureHermesTalkerSelfLearningEvery,
        children: [_buildHermesTalkerSection(context, settingsController)],
      ),
      _SettingsSection.editor => _SettingsGroupCard(
        title: AppLocalizations.of(context)!.settingsEditor,
        description: AppLocalizations.of(
          context,
        )!.settingsManagePerLanguageLspBackendsInstall,
        children: [_buildEditorSection(context, settingsController)],
      ),
      _SettingsSection.appData => _SettingsGroupCard(
        title: AppLocalizations.of(context)!.settingsAppData,
        description: AppLocalizations.of(
          context,
        )!.settingsManageTheLocalFilesAndDatabase,
        children: const [_DataCleanupSection()],
      ),
      _SettingsSection.system => _SettingsGroupCard(
        title: l10n.proxySectionTitle,
        description: l10n.proxySectionBody,
        children: [
          _SystemProxySection(controller: settingsController),
          const _InputRepairSection(),
        ],
      ),
      _SettingsSection.about => _SettingsGroupCard(
        title: l10n.aboutSectionTitle,
        description: l10n.aboutSectionBody,
        children: [
          _ReadonlySettingRow(label: l10n.aboutVersion, value: appInfo.version),
          _ReadonlySettingRow(
            label: l10n.aboutBuild,
            value: appInfo.buildNumber,
          ),
          _ReadonlySettingRow(
            label: l10n.aboutPackage,
            value: appInfo.packageName,
          ),
          _ReadonlySettingRow(
            label: l10n.aboutPlatforms,
            value: l10n.aboutPlatformsValue,
          ),
          _ReadonlySettingRow(
            label: l10n.settingsFilePathLabel,
            value: settingsController.displaySettingsFilePath,
          ),
          if (!kIsWeb) ...[
            kOpenHandGap18,
            _ResponsiveSettingRow(
              title: openHandLocalizedText(
                context,
                zh: '检查更新',
                zhHant: '檢查更新',
                en: 'Check for Updates',
                fr: 'Rechercher des mises à jour',
                de: 'Nach Updates suchen',
                ja: 'アップデートを確認',
              ),
              subtitle: openHandLocalizedText(
                context,
                zh: '从 GitHub Release 检查是否有新版本可用。',
                zhHant: '從 GitHub Release 檢查是否有新版本可用。',
                en: 'Check GitHub Releases for a newer version.',
                fr: 'Vérifie les GitHub Releases pour une nouvelle version.',
                de: 'Prüft GitHub Releases auf eine neuere Version.',
                ja: 'GitHub Releases から新しいバージョンの有無を確認します。',
              ),
              control: FilledButton.icon(
                onPressed: () => _showUpdateCheckDialog(context, appInfo),
                icon: const Icon(Icons.system_update_outlined, size: 18),
                label: Text(
                  openHandLocalizedText(
                    context,
                    zh: '检查更新',
                    zhHant: '檢查更新',
                    en: 'Check',
                    fr: 'Vérifier',
                    de: 'Prüfen',
                    ja: '確認',
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    };
  }

  Widget _buildAiModelsSection(
    BuildContext context,
    SettingsController settingsController,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final aiModels = settingsController.aiModels;
    _syncAnimatedAiModels(aiModels);
    final allowCommandRules = settingsController.aiAllowCommandRules;
    final denyCommandRules = settingsController.aiDenyCommandRules;
    final compressionControl = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey<String>('settingsCompressionThresholdField'),
          controller: _compressionThresholdController,
          focusNode: _compressionThresholdFocusNode,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: InputDecoration(
            labelText: l10n.aiCompressionThresholdLabel,
            hintText:
                '${AppSettingsSnapshot.defaultAiMessageCompressionThresholdChars}',
          ),
          onSubmitted: (value) => _saveCompressionThreshold(context, value),
        ),
        kOpenHandGap12,
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const ValueKey<String>(
              'settingsCompressionThresholdSaveButton',
            ),
            onPressed: () => _saveCompressionThreshold(
              context,
              _compressionThresholdController.text,
            ),
            icon: const Icon(Icons.save_outlined),
            label: Text(l10n.aiCompressionThresholdSave),
          ),
        ),
      ],
    );
    final toolResultCompressionControl = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey<String>(
            'settingsToolResultCompressionThresholdField',
          ),
          controller: _toolResultCompressionThresholdController,
          focusNode: _toolResultCompressionThresholdFocusNode,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: InputDecoration(
            labelText: l10n.aiToolResultCompressionThresholdLabel,
            hintText:
                '${AppSettingsSnapshot.defaultAiToolResultCompressionThresholdChars}',
          ),
          onSubmitted: (value) =>
              _saveToolResultCompressionThreshold(context, value),
        ),
        kOpenHandGap12,
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const ValueKey<String>(
              'settingsToolResultCompressionThresholdSaveButton',
            ),
            onPressed: () => _saveToolResultCompressionThreshold(
              context,
              _toolResultCompressionThresholdController.text,
            ),
            icon: const Icon(Icons.save_outlined),
            label: Text(l10n.aiToolResultCompressionThresholdSave),
          ),
        ),
      ],
    );
    final toolResultCompressionEnabledControl = Align(
      alignment: Alignment.centerLeft,
      child: _SettingsSwitch(
        key: const ValueKey<String>(
          'settingsToolResultCompressionEnabledSwitch',
        ),
        value: settingsController.aiToolResultCompressionEnabled,
        onChanged: (value) async {
          await settingsController.updateAiToolResultCompressionEnabled(value);
        },
      ),
    );
    final microCompressionEnabledControl = Align(
      alignment: Alignment.centerLeft,
      child: _SettingsSwitch(
        key: const ValueKey<String>('settingsMicroCompressionEnabledSwitch'),
        value: settingsController.aiMicroCompressionEnabled,
        onChanged: (value) async {
          await settingsController.updateAiMicroCompressionEnabled(value);
        },
      ),
    );
    final messageContentFormatControl = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: AnimatedDropdownButtonFormField<AiMessageContentFormat>(
        key: const ValueKey<String>('settingsAiMessageContentFormatDropdown'),
        initialValue: settingsController.aiMessageContentFormat,
        items: <DropdownMenuItem<AiMessageContentFormat>>[
          DropdownMenuItem<AiMessageContentFormat>(
            value: AiMessageContentFormat.markdown,
            child: Text(l10n.aiMessageContentFormatMarkdown),
          ),
          DropdownMenuItem<AiMessageContentFormat>(
            value: AiMessageContentFormat.plainText,
            child: Text(l10n.aiMessageContentFormatPlainText),
          ),
          DropdownMenuItem<AiMessageContentFormat>(
            value: AiMessageContentFormat.html,
            child: Text(l10n.aiMessageContentFormatHtml),
          ),
        ],
        onChanged: (value) async {
          if (value == null) return;
          await settingsController.updateAiMessageContentFormat(value);
          if (!context.mounted) return;
          if (value == AiMessageContentFormat.html) {
            flashOpenHandSnack(
              context,
              l10n.aiMessageContentFormatHtmlTokenWarning,
            );
          }
        },
      ),
    );
    final htmlRenderFallbackControl = SizedBox(
      width: double.infinity,
      child: AnimatedDropdownButtonFormField<AiHtmlRenderFallback>(
        key: const ValueKey<String>('settingsAiHtmlRenderFallbackDropdown'),
        initialValue: settingsController.aiHtmlRenderFallback,
        items: <DropdownMenuItem<AiHtmlRenderFallback>>[
          DropdownMenuItem<AiHtmlRenderFallback>(
            value: AiHtmlRenderFallback.markdown,
            child: Text(l10n.aiHtmlRenderFallbackMarkdown),
          ),
          DropdownMenuItem<AiHtmlRenderFallback>(
            value: AiHtmlRenderFallback.plainText,
            child: Text(l10n.aiHtmlRenderFallbackPlainText),
          ),
        ],
        onChanged: (value) async {
          if (value == null) return;
          await settingsController.updateAiHtmlRenderFallback(value);
        },
      ),
    );
    final htmlContentRichnessControl = SizedBox(
      width: double.infinity,
      child: AnimatedDropdownButtonFormField<AiHtmlContentRichness>(
        key: const ValueKey<String>('settingsAiHtmlContentRichnessDropdown'),
        initialValue: settingsController.aiHtmlContentRichness,
        items: <DropdownMenuItem<AiHtmlContentRichness>>[
          DropdownMenuItem<AiHtmlContentRichness>(
            value: AiHtmlContentRichness.balanced,
            child: Text(l10n.aiHtmlContentRichnessBalanced),
          ),
          DropdownMenuItem<AiHtmlContentRichness>(
            value: AiHtmlContentRichness.rich,
            child: Text(l10n.aiHtmlContentRichnessRich),
          ),
          DropdownMenuItem<AiHtmlContentRichness>(
            value: AiHtmlContentRichness.vivid,
            child: Text(l10n.aiHtmlContentRichnessVivid),
          ),
        ],
        onChanged: (value) async {
          if (value == null) return;
          await settingsController.updateAiHtmlContentRichness(value);
        },
      ),
    );
    final ttsSettings = settingsController.aiTtsSettings;
    final translationSettings = settingsController.aiTranslationSettings;
    final offlineSpeechSettings = settingsController.offlineSpeechSettings;
    final ttsEnabledControl = Align(
      alignment: Alignment.centerLeft,
      child: _SettingsSwitch(
        key: const ValueKey<String>('settingsAiTtsEnabledSwitch'),
        value: ttsSettings.enabled,
        onChanged: (value) async {
          await settingsController.updateAiTtsEnabled(value);
        },
      ),
    );
    final translationEnabledControl = Align(
      alignment: Alignment.centerLeft,
      child: _SettingsSwitch(
        key: const ValueKey<String>('settingsAiTranslationEnabledSwitch'),
        value: translationSettings.enabled,
        onChanged: (value) async {
          await settingsController.updateAiTranslationEnabled(value);
        },
      ),
    );
    final toolResultCompressionHeadTailWindowControl = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey<String>(
            'settingsToolResultCompressionHeadTailWindowField',
          ),
          controller: _toolResultCompressionHeadTailWindowController,
          focusNode: _toolResultCompressionHeadTailWindowFocusNode,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: InputDecoration(
            labelText: l10n.aiToolResultCompressionHeadTailWindowLabel,
            hintText:
                '${AppSettingsSnapshot.defaultAiToolResultCompressionHeadTailWindowChars}',
          ),
          onSubmitted: (value) =>
              _saveToolResultCompressionHeadTailWindow(context, value),
        ),
        kOpenHandGap12,
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const ValueKey<String>(
              'settingsToolResultCompressionHeadTailWindowSaveButton',
            ),
            onPressed: () => _saveToolResultCompressionHeadTailWindow(
              context,
              _toolResultCompressionHeadTailWindowController.text,
            ),
            icon: const Icon(Icons.save_outlined),
            label: Text(l10n.aiToolResultCompressionHeadTailWindowSave),
          ),
        ),
      ],
    );
    final toolResultCompressionMaxPathHitsControl = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey<String>(
            'settingsToolResultCompressionMaxPathHitsField',
          ),
          controller: _toolResultCompressionMaxPathHitsController,
          focusNode: _toolResultCompressionMaxPathHitsFocusNode,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: InputDecoration(
            labelText: l10n.aiToolResultCompressionMaxPathHitsLabel,
            hintText:
                '${AppSettingsSnapshot.defaultAiToolResultCompressionMaxPathHits}',
          ),
          onSubmitted: (value) =>
              _saveToolResultCompressionMaxPathHits(context, value),
        ),
        kOpenHandGap12,
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const ValueKey<String>(
              'settingsToolResultCompressionMaxPathHitsSaveButton',
            ),
            onPressed: () => _saveToolResultCompressionMaxPathHits(
              context,
              _toolResultCompressionMaxPathHitsController.text,
            ),
            icon: const Icon(Icons.save_outlined),
            label: Text(l10n.aiToolResultCompressionMaxPathHitsSave),
          ),
        ),
      ],
    );
    final writeToolSummaryMaxCharsControl = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey<String>('settingsWriteToolSummaryMaxCharsField'),
          controller: _writeToolSummaryMaxCharsController,
          focusNode: _writeToolSummaryMaxCharsFocusNode,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: InputDecoration(
            labelText: l10n.aiWriteToolSummaryMaxCharsLabel,
            hintText:
                '${AppSettingsSnapshot.defaultAiWriteToolSummaryMaxChars}',
          ),
          onSubmitted: (value) => _saveWriteToolSummaryMaxChars(context, value),
        ),
        kOpenHandGap12,
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const ValueKey<String>(
              'settingsWriteToolSummaryMaxCharsSaveButton',
            ),
            onPressed: () => _saveWriteToolSummaryMaxChars(
              context,
              _writeToolSummaryMaxCharsController.text,
            ),
            icon: const Icon(Icons.save_outlined),
            label: Text(l10n.aiWriteToolSummaryMaxCharsSave),
          ),
        ),
      ],
    );
    final toolCallLimitControl = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey<String>('settingsToolCallLimitField'),
          controller: _toolCallLimitController,
          focusNode: _toolCallLimitFocusNode,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: InputDecoration(
            labelText: AppLocalizations.of(
              context,
            )!.settingsPerResponseToolCallLimit,
            hintText:
                '${AppSettingsSnapshot.defaultAiSingleRoundToolCallLimit}',
          ),
          onSubmitted: (value) => _saveToolCallLimit(context, value),
        ),
        kOpenHandGap12,
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const ValueKey<String>('settingsToolCallLimitSaveButton'),
            onPressed: () =>
                _saveToolCallLimit(context, _toolCallLimitController.text),
            icon: const Icon(Icons.save_outlined),
            label: Text(AppLocalizations.of(context)!.settingsSaveLimit),
          ),
        ),
      ],
    );
    final sequentialToolRoundLimitControl = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey<String>('settingsSequentialToolRoundLimitField'),
          controller: _sequentialToolRoundLimitController,
          focusNode: _sequentialToolRoundLimitFocusNode,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: InputDecoration(
            labelText: AppLocalizations.of(
              context,
            )!.settingsSequentialToolRoundLimit,
            hintText:
                '${AppSettingsSnapshot.defaultAiSequentialToolRoundLimit}',
          ),
          onSubmitted: (value) => _saveSequentialToolRoundLimit(context, value),
        ),
        kOpenHandGap12,
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const ValueKey<String>(
              'settingsSequentialToolRoundLimitSaveButton',
            ),
            onPressed: () => _saveSequentialToolRoundLimit(
              context,
              _sequentialToolRoundLimitController.text,
            ),
            icon: const Icon(Icons.save_outlined),
            label: Text(AppLocalizations.of(context)!.settingsSaveLimit),
          ),
        ),
      ],
    );
    final maxRecentErrorsControl = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey<String>('settingsMaxRecentErrorsField'),
          controller: _maxRecentErrorsController,
          focusNode: _maxRecentErrorsFocusNode,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: InputDecoration(
            labelText: l10n.aiMaxRecentErrorsLabel,
            hintText: '${AppSettingsSnapshot.defaultAiMaxRecentErrors}',
          ),
          onSubmitted: (value) => _saveMaxRecentErrors(context, value),
        ),
        kOpenHandGap12,
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const ValueKey<String>('settingsMaxRecentErrorsSaveButton'),
            onPressed: () =>
                _saveMaxRecentErrors(context, _maxRecentErrorsController.text),
            icon: const Icon(Icons.save_outlined),
            label: Text(l10n.aiMaxRecentErrorsSave),
          ),
        ),
      ],
    );
    final maxPlanHistoryEntriesControl = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey<String>('settingsMaxPlanHistoryEntriesField'),
          controller: _maxPlanHistoryEntriesController,
          focusNode: _maxPlanHistoryEntriesFocusNode,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: InputDecoration(
            labelText: l10n.aiMaxPlanHistoryEntriesLabel,
            hintText: '${AppSettingsSnapshot.defaultAiMaxPlanHistoryEntries}',
          ),
          onSubmitted: (value) => _saveMaxPlanHistoryEntries(context, value),
        ),
        kOpenHandGap12,
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const ValueKey<String>(
              'settingsMaxPlanHistoryEntriesSaveButton',
            ),
            onPressed: () => _saveMaxPlanHistoryEntries(
              context,
              _maxPlanHistoryEntriesController.text,
            ),
            icon: const Icon(Icons.save_outlined),
            label: Text(l10n.aiMaxPlanHistoryEntriesSave),
          ),
        ),
      ],
    );
    final maxTruncationContinuationsControl = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey<String>(
            'settingsMaxTruncationContinuationsField',
          ),
          controller: _maxTruncationContinuationsController,
          focusNode: _maxTruncationContinuationsFocusNode,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: InputDecoration(
            labelText: l10n.aiMaxTruncationContinuationsLabel,
            hintText:
                '${AppSettingsSnapshot.defaultAiMaxTruncationContinuations}',
          ),
          onSubmitted: (value) =>
              _saveMaxTruncationContinuations(context, value),
        ),
        kOpenHandGap12,
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const ValueKey<String>(
              'settingsMaxTruncationContinuationsSaveButton',
            ),
            onPressed: () => _saveMaxTruncationContinuations(
              context,
              _maxTruncationContinuationsController.text,
            ),
            icon: const Icon(Icons.save_outlined),
            label: Text(l10n.aiMaxTruncationContinuationsSave),
          ),
        ),
      ],
    );
    final estimatedCharactersPerTokenControl = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey<String>(
            'settingsEstimatedCharactersPerTokenField',
          ),
          controller: _estimatedCharactersPerTokenController,
          focusNode: _estimatedCharactersPerTokenFocusNode,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: InputDecoration(
            labelText: l10n.aiEstimatedCharactersPerTokenLabel,
            hintText:
                '${AppSettingsSnapshot.defaultAiEstimatedCharactersPerToken}',
          ),
          onSubmitted: (value) =>
              _saveEstimatedCharactersPerToken(context, value),
        ),
        kOpenHandGap12,
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const ValueKey<String>(
              'settingsEstimatedCharactersPerTokenSaveButton',
            ),
            onPressed: () => _saveEstimatedCharactersPerToken(
              context,
              _estimatedCharactersPerTokenController.text,
            ),
            icon: const Icon(Icons.save_outlined),
            label: Text(l10n.aiEstimatedCharactersPerTokenSave),
          ),
        ),
      ],
    );
    final imageSizeLimitControl = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey<String>('settingsImageSizeLimitField'),
          controller: _imageSizeLimitController,
          focusNode: _imageSizeLimitFocusNode,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: InputDecoration(
            labelText: l10n.aiImageSizeLimitFieldLabel,
            hintText:
                (AppSettingsSnapshot.defaultAiImageSizeLimitBytes /
                        kBytesPerMiB)
                    .toStringAsFixed(0),
            helperText: l10n.aiImageSizeLimitBody,
          ),
          onSubmitted: (value) => _saveImageSizeLimit(context, value),
        ),
        kOpenHandGap12,
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const ValueKey<String>('settingsImageSizeLimitSaveButton'),
            onPressed: () =>
                _saveImageSizeLimit(context, _imageSizeLimitController.text),
            icon: const Icon(Icons.save_outlined),
            label: Text(l10n.aiImageSizeLimitSave),
          ),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _AiUsageSettingsSection(),
        kOpenHandGap16,
        _SettingsSubsectionCard(
          title: AppLocalizations.of(context)!.settingsSessionSettings,
          description: AppLocalizations.of(
            context,
          )!.settingsConfigureDefaultBehaviourForNewSessions,
          child: Column(
            // 强制左对齐：默认 CrossAxisAlignment.center 会
            // 把"节流参数"独立的 title / body Text 居中渲染，与上下方
            // _ResponsiveSettingRow（内部 Row+Column start 对齐）视觉断裂。
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ResponsiveSettingRow(
                title: AppLocalizations.of(context)!.settingsSendTimeoutS,
                subtitle: AppLocalizations.of(
                  context,
                )!.settingsMaximumWaitTimeToEstablishThe,
                control: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _connectTimeoutController,
                      focusNode: _connectTimeoutFocusNode,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(
                          context,
                        )!.settingsSendTimeoutS,
                        hintText:
                            '${AppSettingsSnapshot.defaultAiConnectTimeoutSeconds}',
                      ),
                      onSubmitted: (value) =>
                          _saveConnectTimeout(context, value),
                    ),
                    kOpenHandGap12,
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: () => _saveConnectTimeout(
                          context,
                          _connectTimeoutController.text,
                        ),
                        icon: const Icon(Icons.save_outlined),
                        label: Text(
                          AppLocalizations.of(context)!.settingsSaveTimeout,
                        ),
                      ),
                    ),
                  ],
                ),
                controlMaxWidth: 360,
              ),
              kOpenHandGap18,
              _ResponsiveSettingRow(
                title: AppLocalizations.of(context)!.settingsResponseTimeoutS,
                subtitle: AppLocalizations.of(
                  context,
                )!.settingsMaximumWaitForACompleteResponse,
                control: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _responseTimeoutController,
                      focusNode: _responseTimeoutFocusNode,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(
                          context,
                        )!.settingsResponseTimeoutS,
                        hintText:
                            '${AppSettingsSnapshot.defaultAiResponseTimeoutSeconds}',
                      ),
                      onSubmitted: (value) =>
                          _saveResponseTimeout(context, value),
                    ),
                    kOpenHandGap12,
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: () => _saveResponseTimeout(
                          context,
                          _responseTimeoutController.text,
                        ),
                        icon: const Icon(Icons.save_outlined),
                        label: Text(
                          AppLocalizations.of(context)!.settingsSaveTimeout,
                        ),
                      ),
                    ),
                  ],
                ),
                controlMaxWidth: 360,
              ),
              kOpenHandGap18,
              _ResponsiveSettingRow(
                title: AppLocalizations.of(context)!.settingsStreamIdleTimeoutS,
                subtitle: AppLocalizations.of(
                  context,
                )!.settingsMaximumIdleWaitBetweenStreamChunks,
                control: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _streamIdleTimeoutController,
                      focusNode: _streamIdleTimeoutFocusNode,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(
                          context,
                        )!.settingsStreamIdleTimeoutS,
                        hintText:
                            '${AppSettingsSnapshot.defaultAiStreamIdleTimeoutSeconds}',
                      ),
                      onSubmitted: (value) =>
                          _saveStreamIdleTimeout(context, value),
                    ),
                    kOpenHandGap12,
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: () => _saveStreamIdleTimeout(
                          context,
                          _streamIdleTimeoutController.text,
                        ),
                        icon: const Icon(Icons.save_outlined),
                        label: Text(
                          AppLocalizations.of(context)!.settingsSaveTimeout,
                        ),
                      ),
                    ),
                  ],
                ),
                controlMaxWidth: 360,
              ),
              kOpenHandGap18,
              Text(
                AppLocalizations.of(context)!.aiThrottleSettingsLabel,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              kOpenHandGap6,
              Text(
                AppLocalizations.of(context)!.aiThrottleSettingsBody,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              kOpenHandGap18,
              // 先决定是否启用/自适应，再调整具体速率。
              _ResponsiveSettingRow(
                title: openHandLocalizedText(
                  context,
                  zh: '启用流式输出节流',
                  zhHant: '啟用串流輸出節流',
                  en: 'Enable Stream Throttle',
                  fr: 'Activer la limitation du flux',
                  de: 'Stream-Drosselung aktivieren',
                  ja: 'ストリーム出力のスロットリングを有効化',
                ),
                subtitle: openHandLocalizedText(
                  context,
                  zh: '一键开关字符 / 卡片节流。关闭后所有节流参数失效，AI 输出按真实速率全速渲染。',
                  zhHant: '一鍵開關字元 / 卡片節流。關閉後所有節流參數失效，AI 輸出會按真實速率全速渲染。',
                  en: 'Master switch for char/card throttling. When off, AI output renders at full speed.',
                  fr: 'Interrupteur global pour la limitation des caractères et cartes. Désactivé, la sortie IA s’affiche à pleine vitesse.',
                  de: 'Hauptschalter für Zeichen-/Kartendrosselung. Ausgeschaltet rendert die KI-Ausgabe mit voller Geschwindigkeit.',
                  ja: '文字とカードのスロットリングの一括スイッチです。オフにすると AI 出力は実際の速度で全速描画されます。',
                ),
                control: Align(
                  alignment: Alignment.centerLeft,
                  child: _SettingsSwitch(
                    value: settingsController.aiStreamThrottleEnabled,
                    onChanged: (v) =>
                        settingsController.updateAiStreamThrottleEnabled(v),
                  ),
                ),
              ),
              kOpenHandGap18,
              _ResponsiveSettingRow(
                title: openHandLocalizedText(
                  context,
                  zh: '节流自动模式',
                  zhHant: '節流自動模式',
                  en: 'Auto-Adaptive Throttle',
                  fr: 'Limitation adaptative',
                  de: 'Adaptive Drosselung',
                  ja: '自動適応スロットリング',
                ),
                subtitle: openHandLocalizedText(
                  context,
                  zh: '按平台 / 设备性能自动选速率：桌面 ${AppSettingsSnapshot.autoStreamMaxCharsPerSecondDesktop} 字符/秒、移动 ${AppSettingsSnapshot.autoStreamMaxCharsPerSecondMobile} 字符/秒；卡片统一 ${AppSettingsSnapshot.autoStreamMaxMessageCardsPerSecondAuto}/秒。最近 1s FPS<55 自动再降速 50%。开启后忽略下方手动配置。',
                  zhHant:
                      '依平台 / 裝置效能自動選速率：桌面 ${AppSettingsSnapshot.autoStreamMaxCharsPerSecondDesktop} 字元/秒、行動 ${AppSettingsSnapshot.autoStreamMaxCharsPerSecondMobile} 字元/秒；卡片統一 ${AppSettingsSnapshot.autoStreamMaxMessageCardsPerSecondAuto}/秒。最近 1s FPS<55 時自動再降速 50%。開啟後會忽略下方手動設定。',
                  en: 'Auto-pick rates by platform: desktop ${AppSettingsSnapshot.autoStreamMaxCharsPerSecondDesktop} chars/s, mobile ${AppSettingsSnapshot.autoStreamMaxCharsPerSecondMobile} chars/s; cards ${AppSettingsSnapshot.autoStreamMaxMessageCardsPerSecondAuto}/s. When recent FPS<55, halves the rate. Manual values below ignored when on.',
                  fr: 'Choisit les débits selon la plateforme : desktop ${AppSettingsSnapshot.autoStreamMaxCharsPerSecondDesktop} car./s, mobile ${AppSettingsSnapshot.autoStreamMaxCharsPerSecondMobile} car./s ; cartes ${AppSettingsSnapshot.autoStreamMaxMessageCardsPerSecondAuto}/s. Si le FPS récent est <55, le débit est divisé par 2. Les valeurs manuelles sont ignorées.',
                  de: 'Wählt Raten je nach Plattform: Desktop ${AppSettingsSnapshot.autoStreamMaxCharsPerSecondDesktop} Zeichen/s, mobil ${AppSettingsSnapshot.autoStreamMaxCharsPerSecondMobile} Zeichen/s; Karten ${AppSettingsSnapshot.autoStreamMaxMessageCardsPerSecondAuto}/s. Bei FPS <55 in der letzten Sekunde wird halbiert. Manuelle Werte werden ignoriert.',
                  ja: 'プラットフォームに応じて速度を自動選択します。デスクトップ ${AppSettingsSnapshot.autoStreamMaxCharsPerSecondDesktop} 文字/秒、モバイル ${AppSettingsSnapshot.autoStreamMaxCharsPerSecondMobile} 文字/秒、カードは ${AppSettingsSnapshot.autoStreamMaxMessageCardsPerSecondAuto}/秒。直近 1 秒の FPS が 55 未満ならさらに 50% 低下します。オンの間は下の手動設定を無視します。',
                ),
                control: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _SettingsSwitch(
                        value: settingsController.aiStreamThrottleAutoMode,
                        onChanged: settingsController.aiStreamThrottleEnabled
                            ? (v) => settingsController
                                  .updateAiStreamThrottleAutoMode(v)
                            : null,
                      ),
                    ),
                    if (settingsController.aiStreamThrottleAutoMode) ...[
                      kOpenHandGap8,
                      const _AutoModeFpsIndicator(),
                    ],
                  ],
                ),
              ),
              kOpenHandGap18,
              // 流式输出节流：每秒最多向卡片追加渲染的字符数
              _ResponsiveSettingRow(
                title: _settingsViewMaxRenderCharsSecLabel(context),
                subtitle: openHandLocalizedText(
                  context,
                  zh: 'AI 侧高速吐字时，UI 端按此速率均匀放出，避免卡片增量渲染卡顿、ANR 与列表抖动。0 表示关闭节流。默认 10。',
                  zhHant:
                      'AI 端高速輸出字元時，UI 端會按此速率均勻放出，避免卡片增量渲染卡頓、ANR 與列表抖動。0 表示關閉節流。預設 10。',
                  en: 'When AI streams chars at high speed, UI appends at this rate to avoid stutter, ANR and list bouncing. 0 disables throttling. Default 10.',
                  fr: 'Quand l’IA émet vite, l’UI ajoute les caractères à ce débit pour éviter les saccades, ANR et rebonds de liste. 0 désactive la limitation. Défaut 10.',
                  de: 'Wenn die KI schnell Zeichen streamt, fügt die UI sie mit dieser Rate an, um Ruckeln, ANR und Listenspringen zu vermeiden. 0 deaktiviert die Drosselung. Standard 10.',
                  ja: 'AI が高速に文字を出力する場合、UI はこの速度で均等に追加し、カードの差分描画のカクつきやリスト揺れを避けます。0 は無効化、既定は 10 です。',
                ),
                control: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _streamMaxCharsPerSecondController,
                      focusNode: _streamMaxCharsPerSecondFocusNode,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: InputDecoration(
                        labelText: _settingsViewMaxRenderCharsSecLabel(context),
                        hintText:
                            '${AppSettingsSnapshot.defaultAiStreamMaxCharsPerSecond}',
                      ),
                      onSubmitted: (value) =>
                          _saveStreamMaxCharsPerSecond(context, value),
                    ),
                    if (settingsController.aiStreamMaxCharsPerSecond <= 0) ...[
                      kOpenHandGap8,
                      _ThrottleDisabledBadge(
                        message: openHandLocalizedText(
                          context,
                          zh: '节流已关闭：AI 端字符将按真实速率全速渲染。',
                          zhHant: '節流已關閉：AI 端字元會按真實速率全速渲染。',
                          en: 'Throttle disabled: chars will be rendered at full speed.',
                          fr: 'Limitation désactivée : les caractères seront rendus à pleine vitesse.',
                          de: 'Drosselung deaktiviert: Zeichen werden mit voller Geschwindigkeit gerendert.',
                          ja: 'スロットリング無効: 文字は実際の速度で全速描画されます。',
                        ),
                      ),
                    ],
                    kOpenHandGap12,
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: () => _saveStreamMaxCharsPerSecond(
                          context,
                          _streamMaxCharsPerSecondController.text,
                        ),
                        icon: const Icon(Icons.save_outlined),
                        label: Text(
                          AppLocalizations.of(context)!.settingsSaveTimeout,
                        ),
                      ),
                    ),
                  ],
                ),
                controlMaxWidth: 360,
              ),
              kOpenHandGap18,
              // 卡片限速：每秒最多新追加多少张消息卡片
              _ResponsiveSettingRow(
                title: _settingsViewMaxRenderCardsSecLabel(context),
                subtitle: openHandLocalizedText(
                  context,
                  zh: 'AI 短时间内连续追加多张工具/助手卡片时，按此速率均匀放出，消除会话窗口的上下弹跳与抽搐。0 表示关闭节流。默认 1。',
                  zhHant:
                      'AI 短時間內連續追加多張工具/助手卡片時，會按此速率均勻放出，消除會話視窗上下彈跳與抖動。0 表示關閉節流。預設 1。',
                  en: 'When AI emits many tool/assistant cards in a burst, UI emits at this rate to eliminate jitter. 0 disables throttling. Default 1.',
                  fr: 'Quand l’IA ajoute plusieurs cartes outil/assistant d’un coup, l’UI les affiche à ce débit pour supprimer les rebonds. 0 désactive la limitation. Défaut 1.',
                  de: 'Wenn die KI viele Tool-/Assistentenkarten auf einmal erzeugt, gibt die UI sie mit dieser Rate aus, um Springen zu vermeiden. 0 deaktiviert die Drosselung. Standard 1.',
                  ja: 'AI が短時間に複数のツール/アシスタントカードを追加する場合、この速度で均等に表示し、会話画面の上下揺れを抑えます。0 は無効化、既定は 1 です。',
                ),
                control: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _streamMaxMessageCardsPerSecondController,
                      focusNode: _streamMaxMessageCardsPerSecondFocusNode,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: InputDecoration(
                        labelText: _settingsViewMaxRenderCardsSecLabel(context),
                        hintText:
                            '${AppSettingsSnapshot.defaultAiStreamMaxMessageCardsPerSecond}',
                      ),
                      onSubmitted: (value) =>
                          _saveStreamMaxMessageCardsPerSecond(context, value),
                    ),
                    if (settingsController.aiStreamMaxMessageCardsPerSecond <=
                        0) ...[
                      kOpenHandGap8,
                      _ThrottleDisabledBadge(
                        message: openHandLocalizedText(
                          context,
                          zh: '节流已关闭：AI 端新增卡片将按真实速率全速追加。',
                          zhHant: '節流已關閉：AI 端新增卡片會按真實速率全速追加。',
                          en: 'Throttle disabled: new cards will be appended at full speed.',
                          fr: 'Limitation désactivée : les nouvelles cartes seront ajoutées à pleine vitesse.',
                          de: 'Drosselung deaktiviert: neue Karten werden mit voller Geschwindigkeit angefügt.',
                          ja: 'スロットリング無効: 新しいカードは実際の速度で全速追加されます。',
                        ),
                      ),
                    ],
                    kOpenHandGap12,
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: () => _saveStreamMaxMessageCardsPerSecond(
                          context,
                          _streamMaxMessageCardsPerSecondController.text,
                        ),
                        icon: const Icon(Icons.save_outlined),
                        label: Text(
                          AppLocalizations.of(context)!.settingsSaveTimeout,
                        ),
                      ),
                    ),
                  ],
                ),
                controlMaxWidth: 360,
              ),
              // 节流持续时长入口。
              kOpenHandGap18,
              _ResponsiveSettingRow(
                title: _settingsViewThrottleDurationSLabel(context),
                subtitle: openHandLocalizedText(
                  context,
                  zh: '在该时长内按字符 / 卡片速率均匀放出；时长耗尽后剩余流式响应直接按 AI 实际接收节奏追加。0 = 持续节流（默认）。',
                  zhHant:
                      '在該時長內按字元 / 卡片速率均勻放出；時長耗盡後剩餘串流回應會直接按 AI 實際接收節奏追加。0 = 持續節流（預設）。',
                  en: 'Throttle char/card output for this duration; afterwards the remainder streams at the AI actual arrival rate. 0 = continuous throttle (default).',
                  fr: 'Limite les caractères/cartes pendant cette durée ; ensuite le reste suit le rythme réel d’arrivée de l’IA. 0 = limitation continue (défaut).',
                  de: 'Drosselt Zeichen/Karten für diese Dauer; danach folgt der Rest der tatsächlichen KI-Ankunftsrate. 0 = kontinuierliche Drosselung (Standard).',
                  ja: 'この時間中は文字/カードの速度を均等化します。終了後の残りは AI の実際の受信ペースで追加されます。0 = 継続スロットリング（既定）。',
                ),
                control: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _streamThrottleDurationController,
                      focusNode: _streamThrottleDurationFocusNode,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: InputDecoration(
                        labelText: _settingsViewThrottleDurationSLabel(context),
                        hintText:
                            '${AppSettingsSnapshot.defaultAiStreamThrottleDurationSeconds}',
                      ),
                      onSubmitted: (value) =>
                          _saveStreamThrottleDurationSeconds(context, value),
                    ),
                    if (settingsController.aiStreamThrottleDurationSeconds <=
                        0) ...[
                      kOpenHandGap8,
                      _ThrottleDisabledBadge(
                        message: openHandLocalizedText(
                          context,
                          zh: '当前为持续节流：整个流式响应都按节流速率均匀放出。',
                          zhHant: '目前為持續節流：整個串流回應都會按節流速率均勻放出。',
                          en: 'Continuous throttle: the entire stream is paced.',
                          fr: 'Limitation continue : tout le flux est cadencé.',
                          de: 'Kontinuierliche Drosselung: der gesamte Stream wird getaktet.',
                          ja: '継続スロットリング: ストリーム全体を一定速度で表示します。',
                        ),
                      ),
                    ],
                    kOpenHandGap12,
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: () => _saveStreamThrottleDurationSeconds(
                          context,
                          _streamThrottleDurationController.text,
                        ),
                        icon: const Icon(Icons.save_outlined),
                        label: Text(
                          AppLocalizations.of(context)!.settingsSaveTimeout,
                        ),
                      ),
                    ),
                  ],
                ),
                controlMaxWidth: 360,
              ),
              kOpenHandGap18,
              // 节流配置 export / import 入口。
              _ResponsiveSettingRow(
                title: openHandLocalizedText(
                  context,
                  zh: '导入 / 导出节流配置',
                  zhHant: '匯入 / 匯出節流設定',
                  en: 'Import / Export Throttle Config',
                  fr: 'Importer / exporter la config de limitation',
                  de: 'Drosselungskonfiguration importieren / exportieren',
                  ja: 'スロットリング設定のインポート / エクスポート',
                ),
                subtitle: openHandLocalizedText(
                  context,
                  zh: '将全局开关、自动模式、持续时间及字符/卡片速率导出为 JSON，便于备份和跨设备同步；云端连接凭据不会写入文档。',
                  zhHant:
                      '將全域開關、自動模式、持續時間及字元/卡片速率匯出為 JSON，方便備份與跨裝置同步；雲端連線憑證不會寫入文件。',
                  en: 'Export the global switch, auto mode, duration, and character/card rates as JSON for backup or cross-device sync. Cloud credentials are excluded.',
                  fr: 'Exporte l’interrupteur global, le mode auto, la durée et les débits en JSON pour la sauvegarde ou la synchronisation. Les identifiants cloud sont exclus.',
                  de: 'Exportiert globalen Schalter, Automatikmodus, Dauer und Raten als JSON für Sicherung oder Gerätesynchronisierung. Cloud-Zugangsdaten werden ausgeschlossen.',
                  ja: '全体スイッチ、自動モード、継続時間、文字/カード速度を JSON に書き出します。クラウド認証情報は含まれません。',
                ),
                control: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () => _exportAiStreamThrottleConfig(context),
                      icon: const Icon(Icons.upload_rounded, size: 18),
                      label: Text(openHandExportJsonLabel(context)),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _importAiStreamThrottleConfig(context),
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: Text(
                        openHandLocalizedText(
                          context,
                          zh: '从 JSON 导入',
                          zhHant: '從 JSON 匯入',
                          en: 'Import JSON',
                          fr: 'Importer JSON',
                          de: 'JSON importieren',
                          ja: 'JSON をインポート',
                        ),
                      ),
                    ),
                  ],
                ),
                controlMaxWidth: 360,
              ),
              kOpenHandGap18,
              _ResponsiveSettingRow(
                title: openHandLocalizedText(
                  context,
                  zh: '节流配置云端同步',
                  zhHant: '節流設定雲端同步',
                  en: 'Cloud Sync',
                  fr: 'Synchronisation cloud',
                  de: 'Cloud-Synchronisierung',
                  ja: 'クラウド同期',
                ),
                subtitle: openHandLocalizedText(
                  context,
                  zh: '支持通过自定义 HTTP、iCloud 或 GitHub Gist 推送 / 拉取节流配置。',
                  zhHant: '支援透過自訂 HTTP、iCloud 或 GitHub Gist 推送 / 拉取節流設定。',
                  en: 'Push or pull throttle settings through custom HTTP, iCloud, or GitHub Gist.',
                  fr: 'Synchronisez la limitation via HTTP personnalisé, iCloud ou GitHub Gist.',
                  de: 'Drosselungseinstellungen über eigenes HTTP, iCloud oder GitHub Gist synchronisieren.',
                  ja: 'カスタム HTTP、iCloud、GitHub Gist でスロットリング設定を同期できます。',
                ),
                control: const _ThrottleCloudSyncEditor(),
                controlMaxWidth: 720,
              ),
              kOpenHandGap18,
              _ResponsiveSettingRow(
                title: l10n.settingsAutoTitle,
                subtitle: l10n.settingsWhenEnabledATitleIsAutomatically,
                control: Align(
                  alignment: Alignment.centerLeft,
                  child: _SettingsSwitch(
                    value: settingsController.aiAutoTitleEnabled,
                    onChanged: (value) =>
                        settingsController.updateAiAutoTitleEnabled(value),
                  ),
                ),
              ),
              kOpenHandGap18,
              _ResponsiveSettingRow(
                title: l10n.settingsTitleFetchMode,
                subtitle: l10n.settingsTitleFetchModeDescription,
                controlMaxWidth: 360,
                control: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<AiAutoTitleFetchMode>(
                    segments: [
                      ButtonSegment<AiAutoTitleFetchMode>(
                        value: AiAutoTitleFetchMode.asynchronous,
                        icon: const Icon(Icons.bolt_outlined),
                        label: Text(
                          l10n.settingsTitleFetchModeAsync,
                          softWrap: false,
                        ),
                      ),
                      ButtonSegment<AiAutoTitleFetchMode>(
                        value: AiAutoTitleFetchMode.synchronous,
                        icon: const Icon(Icons.sync_rounded),
                        label: Text(
                          l10n.settingsTitleFetchModeSync,
                          softWrap: false,
                        ),
                      ),
                    ],
                    selected: {settingsController.aiAutoTitleFetchMode},
                    onSelectionChanged: settingsController.aiAutoTitleEnabled
                        ? (selection) async {
                            if (selection.isEmpty) return;
                            final mode = selection.first;
                            await settingsController.updateAiAutoTitleFetchMode(
                              mode,
                            );
                          }
                        : null,
                  ),
                ),
              ),
              kOpenHandGap18,
              _ResponsiveSettingRow(
                title: openHandLocalizedText(
                  context,
                  zh: '标题获取最大重试次数',
                  zhHant: '標題取得最大重試次數',
                  en: 'Title Retry Max Count',
                  fr: 'Nombre max. de tentatives de titre',
                  de: 'Max. Titel-Wiederholungen',
                  ja: 'タイトル取得の最大再試行回数',
                ),
                subtitle: openHandLocalizedText(
                  context,
                  zh: '当自动标题生成失败后，后续每次打开该会话时尝试重新获取标题的最大次数。超过此次数后将使用回退策略。',
                  zhHant: '當自動標題生成失敗後，後續每次開啟該會話時嘗試重新取得標題的最大次數。超過此次數後會使用回退策略。',
                  en: 'Maximum number of retries to regenerate a session title on subsequent opens after the initial auto-title generation fails.',
                  fr: 'Nombre maximal de nouvelles tentatives pour générer le titre d’une session lors des ouvertures suivantes après un échec initial.',
                  de: 'Maximale Anzahl erneuter Versuche, einen Sitzungstitel bei späterem Öffnen neu zu erzeugen, nachdem die erste automatische Generierung fehlgeschlagen ist.',
                  ja: '自動タイトル生成が失敗したあと、このセッションを開くたびにタイトル再生成を試す最大回数です。超過後はフォールバックを使います。',
                ),
                controlMaxWidth: 200,
                control: Row(
                  children: [
                    Expanded(
                      child: OpenHandDeferredSlider(
                        value: settingsController.aiAutoTitleMaxRetryCount
                            .toDouble(),
                        min: AppSettingsSnapshot.minAiAutoTitleMaxRetryCount
                            .toDouble(),
                        max: AppSettingsSnapshot.maxAiAutoTitleMaxRetryCount
                            .toDouble(),
                        divisions:
                            AppSettingsSnapshot.maxAiAutoTitleMaxRetryCount -
                            AppSettingsSnapshot.minAiAutoTitleMaxRetryCount,
                        onCommit: (value) => settingsController
                            .updateAiAutoTitleMaxRetryCount(value.round()),
                      ),
                    ),
                    kOpenHandHGap8,
                    Text(
                      '${settingsController.aiAutoTitleMaxRetryCount}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              kOpenHandGap18,
              _ResponsiveSettingRow(
                title: AppLocalizations.of(context)!.settingsDefaultSessionMode,
                subtitle: AppLocalizations.of(
                  context,
                )!.settingsDefaultInteractionModeForNewSessions,
                control: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    segments: [
                      ButtonSegment<String>(
                        value: 'chat',
                        icon: const Icon(Icons.chat_outlined),
                        label: Text(
                          AppLocalizations.of(context)!.settingsChat,
                          softWrap: false,
                        ),
                      ),
                      ButtonSegment<String>(
                        value: 'plan',
                        icon: const Icon(Icons.account_tree_outlined),
                        label: Text(
                          AppLocalizations.of(context)!.settingsPlan,
                          softWrap: false,
                        ),
                      ),
                    ],
                    selected: {settingsController.aiDefaultSessionMode},
                    onSelectionChanged: (values) {
                      if (values.isNotEmpty) {
                        settingsController.updateAiDefaultSessionMode(
                          values.first,
                        );
                      }
                    },
                  ),
                ),
                controlMaxWidth: 360,
              ),
              kOpenHandGap18,
              _ResponsiveSettingRow(
                title: AppLocalizations.of(context)!.settingsDefaultFullAccess,
                subtitle: AppLocalizations.of(
                  context,
                )!.settingsWhenEnabledNewSessionsStartIn,
                control: Align(
                  alignment: Alignment.centerLeft,
                  child: _SettingsSwitch(
                    value: settingsController.aiDefaultFullAccessPermission,
                    onChanged: (value) => settingsController
                        .updateAiDefaultFullAccessPermission(value),
                  ),
                ),
              ),
              kOpenHandGap18,
              _ResponsiveSettingRow(
                title: AppLocalizations.of(context)!.settingsUserProfile,
                subtitle: AppLocalizations.of(
                  context,
                )!.settingsMaintainAGlobalUserProfileLanguage,
                control: const Align(
                  alignment: Alignment.centerLeft,
                  child: _UserProfileSettingsButton(),
                ),
              ),
              kOpenHandGap18,
              _ResponsiveSettingRow(
                title: AppLocalizations.of(
                  context,
                )!.settingsThreadSessionManagementTitle,
                subtitle: AppLocalizations.of(
                  context,
                )!.settingsThreadSessionManagementSubtitle,
                control: Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    onPressed: () => showThreadSessionManagementDialog(context),
                    icon: const Icon(Icons.dynamic_feed_outlined),
                    label: Text(
                      AppLocalizations.of(
                        context,
                      )!.settingsThreadSessionManagementOpen,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        kOpenHandGap16,
        _SettingsSubsectionCard(
          title: AppLocalizations.of(context)!.settingsModelProviderManagement,
          description: AppLocalizations.of(
            context,
          )!.settingsAddSelectTestAndMaintainModel,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AiModelHealthSettingsPanel(),
              kOpenHandGap16,
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: _isSyncingOpenRouterModels
                        ? null
                        : () => _showAiModelDialog(context),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(l10n.aiModelAdd),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _isSyncingOpenRouterModels
                        ? null
                        : () => _syncOpenRouterModels(),
                    icon: _isSyncingOpenRouterModels
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_sync_rounded),
                    label: Text(
                      openHandLocalizedText(
                        context,
                        zh: '从 OpenRouter 同步模型参数',
                        zhHant: '從 OpenRouter 同步模型參數',
                        en: 'Sync model parameters from OpenRouter',
                        fr: 'Synchroniser les paramètres depuis OpenRouter',
                        de: 'Modellparameter von OpenRouter synchronisieren',
                        ja: 'OpenRouter からモデルパラメータを同期',
                      ),
                    ),
                  ),
                ],
              ),
              kOpenHandGap16,
              AnimatedSwitcher(
                duration: openHandMotionDuration(context, kOpenHandMotion260),
                reverseDuration: openHandMotionDuration(
                  context,
                  kOpenHandMotion220,
                ),
                switchInCurve: kOpenHandEntranceCurve,
                switchOutCurve: kOpenHandSwitchOutCurve,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.98, end: 1.0).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: kOpenHandEntranceCurve,
                          reverseCurve: kOpenHandSwitchOutCurve,
                        ),
                      ),
                      alignment: Alignment.topCenter,
                      child: child,
                    ),
                  );
                },
                child: _animatedAiModels.isEmpty
                    ? KeyedSubtree(
                        key: const ValueKey<String>('aiModelsEmpty'),
                        child: _SettingsStateBox(
                          icon: Icons.hub_outlined,
                          title: l10n.aiModelsEmptyTitle,
                          body: l10n.aiModelsEmptyBody,
                        ),
                      )
                    : ConstrainedBox(
                        key: const ValueKey<String>('aiModelsList'),
                        constraints: const BoxConstraints(maxHeight: 520),
                        child: ReorderableListView.builder(
                          primary: false,
                          shrinkWrap: true,
                          buildDefaultDragHandles: false,
                          proxyDecorator: (child, index, animation) =>
                              buildOpenHandReorderProxy(
                                context,
                                child,
                                animation,
                              ),
                          itemCount: _animatedAiModels.length,
                          onReorderItem: _reorderAiModels,
                          itemBuilder: (context, index) => _buildAiModelRow(
                            context,
                            _animatedAiModels[index],
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
        kOpenHandGap16,
        _SettingsSubsectionCard(
          title: l10n.aiCompressionThresholdLabel,
          description: l10n.aiCompressionThresholdBody,
          child: Column(
            children: [
              _ResponsiveSettingRow(
                title: AppLocalizations.of(context)!.settingsCompressionTrigger,
                subtitle: AppLocalizations.of(
                  context,
                )!.settingsOnceTheUncompressedHistoryInA,
                control: compressionControl,
                controlMaxWidth: 360,
              ),
              kOpenHandGap18,
              _ResponsiveSettingRow(
                title: AppLocalizations.of(
                  context,
                )!.settingsToolCallOutputCompressionThreshold,
                subtitle: AppLocalizations.of(
                  context,
                )!.settingsWhenAToolCallReturnsMore,
                control: toolResultCompressionControl,
                controlMaxWidth: 360,
              ),
              kOpenHandGap18,
              _ResponsiveSettingRow(
                title: l10n.aiToolResultCompressionEnabledLabel,
                subtitle: l10n.aiToolResultCompressionEnabledBody,
                control: toolResultCompressionEnabledControl,
                controlMaxWidth: 360,
              ),
              kOpenHandGap18,
              _ResponsiveSettingRow(
                title: l10n.aiMicroCompressionEnabledLabel,
                subtitle: l10n.aiMicroCompressionEnabledBody,
                control: microCompressionEnabledControl,
                controlMaxWidth: 360,
              ),
              kOpenHandGap18,
              _ResponsiveSettingRow(
                title: l10n.aiToolResultCompressionHeadTailWindowLabel,
                subtitle: l10n.aiToolResultCompressionHeadTailWindowBody,
                control: toolResultCompressionHeadTailWindowControl,
                controlMaxWidth: 360,
              ),
              kOpenHandGap18,
              _ResponsiveSettingRow(
                title: l10n.aiToolResultCompressionMaxPathHitsLabel,
                subtitle: l10n.aiToolResultCompressionMaxPathHitsBody,
                control: toolResultCompressionMaxPathHitsControl,
                controlMaxWidth: 360,
              ),
              kOpenHandGap18,
              _ResponsiveSettingRow(
                title: l10n.aiWriteToolSummaryMaxCharsLabel,
                subtitle: l10n.aiWriteToolSummaryMaxCharsBody,
                control: writeToolSummaryMaxCharsControl,
                controlMaxWidth: 360,
              ),
              kOpenHandGap18,
              _ResponsiveSettingRow(
                title: AppLocalizations.of(
                  context,
                )!.settingsPerResponseToolCallLimit,
                subtitle: AppLocalizations.of(
                  context,
                )!.settingsDefaultsTo40IfOneAssistant,
                control: toolCallLimitControl,
                controlMaxWidth: 360,
              ),
              kOpenHandGap18,
              _ResponsiveSettingRow(
                title: AppLocalizations.of(
                  context,
                )!.settingsSequentialToolRoundLimit,
                subtitle: AppLocalizations.of(
                  context,
                )!.settingsDefaultsTo24RoundsIfThe,
                control: sequentialToolRoundLimitControl,
                controlMaxWidth: 360,
              ),
              kOpenHandGap18,
              _ResponsiveSettingRow(
                title: l10n.aiMaxRecentErrorsLabel,
                subtitle: l10n.aiMaxRecentErrorsBody,
                control: maxRecentErrorsControl,
                controlMaxWidth: 360,
              ),
              kOpenHandGap18,
              _ResponsiveSettingRow(
                title: l10n.aiMaxPlanHistoryEntriesLabel,
                subtitle: l10n.aiMaxPlanHistoryEntriesBody,
                control: maxPlanHistoryEntriesControl,
                controlMaxWidth: 360,
              ),
              kOpenHandGap18,
              _ResponsiveSettingRow(
                title: l10n.aiMaxTruncationContinuationsLabel,
                subtitle: l10n.aiMaxTruncationContinuationsBody,
                control: maxTruncationContinuationsControl,
                controlMaxWidth: 360,
              ),
              kOpenHandGap18,
              _ResponsiveSettingRow(
                title: l10n.aiEstimatedCharactersPerTokenLabel,
                subtitle: l10n.aiEstimatedCharactersPerTokenBody,
                control: estimatedCharactersPerTokenControl,
                controlMaxWidth: 360,
              ),
              kOpenHandGap18,
              _ResponsiveSettingRow(
                title: AppLocalizations.of(context)!.settingsImageSizeLimit,
                subtitle: AppLocalizations.of(
                  context,
                )!.settingsDefaultsTo1mbImageAttachmentsLarger,
                control: imageSizeLimitControl,
                controlMaxWidth: 360,
              ),
            ],
          ),
        ),
        kOpenHandGap16,
        _SettingsSubsectionCard(
          title: l10n.aiMessageContentSectionLabel,
          description: l10n.aiMessageContentFormatBody,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ResponsiveSettingRow(
                title: l10n.aiMessageContentFormatLabel,
                control: messageContentFormatControl,
              ),
              _AnimatedSettingReveal(
                visible:
                    settingsController.aiMessageContentFormat ==
                    AiMessageContentFormat.html,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 18),
                      child: _ResponsiveSettingRow(
                        title: l10n.aiHtmlContentRichnessLabel,
                        subtitle: l10n.aiHtmlContentRichnessBody,
                        control: htmlContentRichnessControl,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 18),
                      child: _ResponsiveSettingRow(
                        title: l10n.aiHtmlRenderFallbackLabel,
                        subtitle: l10n.aiHtmlRenderFallbackBody,
                        control: htmlRenderFallbackControl,
                      ),
                    ),
                  ],
                ),
              ),
              kOpenHandGap18,
              _ResponsiveSettingRow(
                title: openHandLocalizedText(
                  context,
                  zh: '开启文本转语音',
                  en: 'Enable Text To Speech',
                ),
                subtitle: openHandLocalizedText(
                  context,
                  zh: '开启后，聚焦消息卡片时会显示“朗读”胶囊。默认优先使用系统 TTS，服务不可用时按优先级回退。',
                  en: 'When enabled, focused message cards show a Read pill. System TTS is the default fallback.',
                ),
                control: ttsEnabledControl,
              ),
              _AnimatedSettingReveal(
                visible: ttsSettings.enabled,
                child: Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: _AiTtsSettingsPanel(
                    settings: ttsSettings,
                    onChanged: settingsController.updateAiTtsSettings,
                    playbackService: _ttsSettingsPlaybackService,
                    availableModels: settingsController.aiModels,
                    recentModelSelections:
                        settingsController.recentModelSelections,
                  ),
                ),
              ),
              kOpenHandGap18,
              _ResponsiveSettingRow(
                title: openHandLocalizedText(
                  context,
                  zh: '开启文本翻译',
                  en: 'Enable Text Translation',
                ),
                subtitle: openHandLocalizedText(
                  context,
                  zh: '开启后，聚焦可翻译的消息卡片时会显示“翻译/查看原始”胶囊。仅翻译用户文本、AI 思考文本和非 HTML 正式响应文本。',
                  en: 'When enabled, focused translatable messages show a Translate / Original pill for user text, reasoning text, and non-HTML assistant text.',
                ),
                control: translationEnabledControl,
              ),
              _AnimatedSettingReveal(
                visible: translationSettings.enabled,
                child: Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: _AiTranslationSettingsPanel(
                    settings: translationSettings,
                    onChanged: settingsController.updateAiTranslationSettings,
                    availableModels: settingsController.aiModels,
                    recentModelSelections:
                        settingsController.recentModelSelections,
                  ),
                ),
              ),
              kOpenHandGap18,
              _OfflineSpeechModelPanel(
                kind: OfflineSpeechKind.recognition,
                settings: offlineSpeechSettings.recognition,
                textPolishingSettings: offlineSpeechSettings.textPolishing,
                silenceTimeoutSeconds:
                    offlineSpeechSettings.silenceTimeoutSeconds,
                availableModels: settingsController.aiModels,
                recentModelSelections: settingsController.recentModelSelections,
                onTextPolishingChanged: (next) =>
                    settingsController.updateOfflineSpeechSettings(
                      settingsController.offlineSpeechSettings
                          .updateTextPolishing(next),
                    ),
                onSilenceTimeoutChanged: (seconds) =>
                    settingsController.updateOfflineSpeechSettings(
                      settingsController.offlineSpeechSettings
                          .setSilenceTimeoutSeconds(seconds),
                    ),
                onChanged: (next) =>
                    settingsController.updateOfflineSpeechSettings(
                      settingsController.offlineSpeechSettings.update(
                        OfflineSpeechKind.recognition,
                        next,
                      ),
                    ),
              ),
              kOpenHandGap18,
              _OfflineSpeechModelPanel(
                kind: OfflineSpeechKind.synthesis,
                settings: offlineSpeechSettings.synthesis,
                onChanged: (next) =>
                    settingsController.updateOfflineSpeechSettings(
                      settingsController.offlineSpeechSettings.update(
                        OfflineSpeechKind.synthesis,
                        next,
                      ),
                    ),
              ),
            ],
          ),
        ),
        kOpenHandGap16,
        _SettingsSubsectionCard(
          title: AppLocalizations.of(context)!.settingsCostControl,
          description: AppLocalizations.of(
            context,
          )!.settingsReduceTokenCostsByFreezingThe,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ResponsiveSettingRow(
                title: AppLocalizations.of(context)!.settingsEnableInputCache,
                subtitle: AppLocalizations.of(
                  context,
                )!.settingsDisabledByDefaultWhenEnabledEvery,
                control: Align(
                  alignment: Alignment.centerLeft,
                  child: _SettingsSwitch(
                    key: const ValueKey<String>(
                      'settingsAiInputCacheEnabledSwitch',
                    ),
                    value: settingsController.aiInputCacheEnabled,
                    onChanged: (value) async {
                      await settingsController.updateAiInputCacheEnabled(value);
                    },
                  ),
                ),
                controlMaxWidth: 360,
              ),
              kOpenHandGap18,
              _ResponsiveSettingRow(
                title: AppLocalizations.of(
                  context,
                )!.settingsCacheBreakpointUpdateMode,
                subtitle: AppLocalizations.of(
                  context,
                )!.settingsChooseTheSlidingUnitForThe,
                control: Align(
                  alignment: Alignment.centerLeft,
                  child: AnimatedDropdownButton<String>(
                    key: const ValueKey<String>(
                      'settingsAiInputCacheUpdateModeDropdown',
                    ),
                    value: settingsController.aiInputCacheUpdateMode,
                    onChanged: (value) async {
                      if (value == null) return;
                      await settingsController.updateAiInputCacheUpdateMode(
                        value,
                      );
                    },
                    items: <DropdownMenuItem<String>>[
                      DropdownMenuItem<String>(
                        value: AppSettingsSnapshot
                            .aiInputCacheUpdateModeAllMessages,
                        child: Text(
                          AppLocalizations.of(
                            context,
                          )!.settingsByMessageCountUserAssistant,
                        ),
                      ),
                      DropdownMenuItem<String>(
                        value: AppSettingsSnapshot
                            .aiInputCacheUpdateModeUserMessages,
                        child: Text(
                          AppLocalizations.of(
                            context,
                          )!.settingsByUserMessageCountOnly,
                        ),
                      ),
                      DropdownMenuItem<String>(
                        value: AppSettingsSnapshot.aiInputCacheUpdateModeTokens,
                        child: Text(
                          AppLocalizations.of(
                            context,
                          )!.settingsByAccumulatedTokens,
                        ),
                      ),
                    ],
                  ),
                ),
                controlMaxWidth: 360,
              ),
              kOpenHandGap18,
              _ResponsiveSettingRow(
                title: AppLocalizations.of(
                  context,
                )!.settingsCacheBreakpointUpdateInterval,
                subtitle: AppLocalizations.of(
                  context,
                )!.settingsDefault10MeaningDependsOnThe,
                control: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      key: const ValueKey<String>(
                        'settingsAiInputCacheUpdateIntervalField',
                      ),
                      controller: _aiInputCacheUpdateIntervalController,
                      focusNode: _aiInputCacheUpdateIntervalFocusNode,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(
                        hintText:
                            '${AppSettingsSnapshot.defaultAiInputCacheUpdateInterval}',
                      ),
                      onSubmitted: (value) =>
                          _saveAiInputCacheUpdateInterval(context, value),
                    ),
                    kOpenHandGap12,
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        key: const ValueKey<String>(
                          'settingsAiInputCacheUpdateIntervalSaveButton',
                        ),
                        onPressed: () => _saveAiInputCacheUpdateInterval(
                          context,
                          _aiInputCacheUpdateIntervalController.text,
                        ),
                        icon: const Icon(Icons.save_rounded),
                        label: Text(AppLocalizations.of(context)!.settingsSave),
                      ),
                    ),
                  ],
                ),
                controlMaxWidth: 360,
              ),
              kOpenHandGap18,
              _ResponsiveSettingRow(
                title: AppLocalizations.of(
                  context,
                )!.settingsCacheBreakpointCount,
                subtitle: AppLocalizations.of(
                  context,
                )!.settingsDefault4Range14Anthropic,
                control: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      key: const ValueKey<String>(
                        'settingsAiInputCacheBreakpointCountField',
                      ),
                      controller: _aiInputCacheBreakpointCountController,
                      focusNode: _aiInputCacheBreakpointCountFocusNode,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(
                        hintText:
                            '${AppSettingsSnapshot.defaultAiInputCacheBreakpointCount}',
                      ),
                      onSubmitted: (value) =>
                          _saveAiInputCacheBreakpointCount(context, value),
                    ),
                    kOpenHandGap12,
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        key: const ValueKey<String>(
                          'settingsAiInputCacheBreakpointCountSaveButton',
                        ),
                        onPressed: () => _saveAiInputCacheBreakpointCount(
                          context,
                          _aiInputCacheBreakpointCountController.text,
                        ),
                        icon: const Icon(Icons.save_rounded),
                        label: Text(AppLocalizations.of(context)!.settingsSave),
                      ),
                    ),
                  ],
                ),
                controlMaxWidth: 360,
              ),
              kOpenHandGap18,
              _buildAiInputCacheBreakpointPositionsRow(context),
              kOpenHandGap18,
              _ResponsiveSettingRow(
                title: AppLocalizations.of(
                  context,
                )!.settingsAiBudgetUsdPerSession,
                subtitle: AppLocalizations.of(
                  context,
                )!.settingsAiBudgetUsdPerSessionBody,
                control: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      key: const ValueKey<String>(
                        'settingsAiBudgetUsdPerSessionField',
                      ),
                      controller: _aiBudgetUsdPerSessionController,
                      focusNode: _aiBudgetUsdPerSessionFocusNode,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      decoration: const InputDecoration(hintText: '0'),
                      onSubmitted: (value) =>
                          _saveAiBudgetUsdPerSession(context, value),
                    ),
                    kOpenHandGap12,
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        key: const ValueKey<String>(
                          'settingsAiBudgetUsdPerSessionSaveButton',
                        ),
                        onPressed: () => _saveAiBudgetUsdPerSession(
                          context,
                          _aiBudgetUsdPerSessionController.text,
                        ),
                        icon: const Icon(Icons.save_rounded),
                        label: Text(AppLocalizations.of(context)!.settingsSave),
                      ),
                    ),
                  ],
                ),
                controlMaxWidth: 360,
              ),
            ],
          ),
        ),
        kOpenHandGap16,
        _SettingsSubsectionCard(
          title: AppLocalizations.of(context)!.settingsCommandSafety,
          description: AppLocalizations.of(
            context,
          )!.settingsControlWriteCommandConfirmationForBash,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ResponsiveSettingRow(
                title: AppLocalizations.of(
                  context,
                )!.settingsWriteCommandConfirmation,
                subtitle: AppLocalizations.of(
                  context,
                )!.settingsEnabledByDefaultWhenTheAi,
                control: _SettingsSwitch(
                  value: settingsController.aiWriteCommandConfirmationEnabled,
                  onChanged: (value) async {
                    final saved = await settingsController
                        .updateAiWriteCommandConfirmationEnabled(value);
                    if (!context.mounted || saved) {
                      return;
                    }
                    _showPersistenceFailureSnackBar(context);
                  },
                ),
              ),
              _SandboxSettingsSection(
                settingsController: settingsController,
                onPersistenceFailure: () =>
                    _showPersistenceFailureSnackBar(context),
              ),
              kOpenHandGap18,
              Text(
                AppLocalizations.of(context)!.settingsAllowCommandList,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              kOpenHandGap8,
              Text(
                AppLocalizations.of(
                  context,
                )!.settingsMatchingWriteLikeBashCommandsSkip,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              kOpenHandGap14,
              FilledButton.icon(
                onPressed: () => _showAllowCommandRuleDialog(context),
                icon: const Icon(Icons.verified_outlined),
                label: Text(AppLocalizations.of(context)!.settingsAddAllowRule),
              ),
              kOpenHandGap16,
              if (allowCommandRules.isEmpty)
                _SettingsStateBox(
                  icon: Icons.verified_user_outlined,
                  title: AppLocalizations.of(
                    context,
                  )!.settingsNoAllowRulesConfigured,
                  body: AppLocalizations.of(
                    context,
                  )!.settingsAddARuleToLetMatching,
                )
              else
                SizedBox(
                  height: math.min(360.0, allowCommandRules.length * 94.0),
                  child: ListView.separated(
                    primary: false,
                    padding: EdgeInsets.zero,
                    itemCount: allowCommandRules.length,
                    separatorBuilder: (context, index) => kOpenHandGap12,
                    itemBuilder: (context, index) {
                      final rule = allowCommandRules[index];
                      return AppearOnce(
                        key: ValueKey<String>('allow-rule-${rule.id}'),
                        child: _CommandRuleTile.allow(
                          rule: rule,
                          onEdit: () => _showAllowCommandRuleDialog(
                            context,
                            initialRule: rule,
                          ),
                          onDelete: () =>
                              _deleteAllowCommandRule(context, rule),
                        ),
                      );
                    },
                  ),
                ),
              kOpenHandGap18,
              Text(
                AppLocalizations.of(context)!.settingsDenyCommandList,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              kOpenHandGap8,
              Text(
                AppLocalizations.of(
                  context,
                )!.settingsMatchingBashCommandsAreBlockedBefore,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              kOpenHandGap14,
              FilledButton.icon(
                onPressed: () => _showDenyCommandRuleDialog(context),
                icon: const Icon(Icons.block_rounded),
                label: Text(AppLocalizations.of(context)!.settingsAddRule),
              ),
              kOpenHandGap16,
              if (denyCommandRules.isEmpty)
                _SettingsStateBox(
                  icon: Icons.rule_folder_outlined,
                  title: AppLocalizations.of(
                    context,
                  )!.settingsNoDenyRulesConfigured,
                  body: AppLocalizations.of(
                    context,
                  )!.settingsAddARuleToBlockMatching,
                )
              else
                SizedBox(
                  height: math.min(360.0, denyCommandRules.length * 94.0),
                  child: ListView.separated(
                    primary: false,
                    padding: EdgeInsets.zero,
                    itemCount: denyCommandRules.length,
                    separatorBuilder: (context, index) => kOpenHandGap12,
                    itemBuilder: (context, index) {
                      final rule = denyCommandRules[index];
                      return AppearOnce(
                        key: ValueKey<String>('deny-rule-${rule.id}'),
                        child: _CommandRuleTile.deny(
                          rule: rule,
                          onEdit: () => _showDenyCommandRuleDialog(
                            context,
                            initialRule: rule,
                          ),
                          onDelete: () => _deleteDenyCommandRule(context, rule),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        kOpenHandGap16,
        _buildTelemetrySubsection(context, settingsController),
      ],
    );
  }

  Widget _buildTelemetrySubsection(
    BuildContext context,
    SettingsController settingsController,
  ) {
    return _SettingsSubsectionCard(
      title: AppLocalizations.of(context)!.settingsTelemetry,
      description: AppLocalizations.of(
        context,
      )!.settingsWhenEnabledOpenhandCapturesRawAi,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ResponsiveSettingRow(
            title: AppLocalizations.of(context)!.settingsDebugMode,
            subtitle: AppLocalizations.of(
              context,
            )!.settingsOffByDefaultWhenEnabledEvery,
            control: Switch(
              key: const ValueKey<String>('settingsTelemetryDebugSwitch'),
              value: settingsController.telemetryDebugEnabled,
              onChanged: (value) async {
                final saved = await settingsController
                    .updateTelemetryDebugEnabled(value);
                if (!context.mounted || saved) {
                  return;
                }
                _showPersistenceFailureSnackBar(context);
              },
            ),
          ),
          kOpenHandGap18,
          _ResponsiveSettingRow(
            title: AppLocalizations.of(context)!.settingsCaptureRawPayload,
            subtitle: AppLocalizations.of(
              context,
            )!.settingsEnabledByDefaultOnlyActiveWhen,
            control: Switch(
              key: const ValueKey<String>('settingsTelemetryRawPayloadSwitch'),
              value: settingsController.telemetryCaptureRawPayload,
              onChanged: settingsController.telemetryDebugEnabled
                  ? (value) async {
                      final saved = await settingsController
                          .updateTelemetryCaptureRawPayload(value);
                      if (!context.mounted || saved) {
                        return;
                      }
                      _showPersistenceFailureSnackBar(context);
                    }
                  : null,
            ),
          ),
          kOpenHandGap18,
          _ResponsiveSettingRow(
            title: AppLocalizations.of(context)!.settingsCaptureEnvironment,
            subtitle: AppLocalizations.of(
              context,
            )!.settingsOffByDefaultOnlyActiveWhen,
            control: Switch(
              key: const ValueKey<String>(
                'settingsTelemetryCaptureEnvironmentSwitch',
              ),
              value: settingsController.telemetryCaptureEnvironment,
              onChanged: settingsController.telemetryDebugEnabled
                  ? (value) async {
                      final saved = await settingsController
                          .updateTelemetryCaptureEnvironment(value);
                      if (!context.mounted || saved) {
                        return;
                      }
                      _showPersistenceFailureSnackBar(context);
                    }
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShortcutsSection(
    BuildContext context,
    SettingsController settingsController,
  ) {
    final bindings = settingsController.shortcutBindings;
    const actions = OpenHandShortcutAction.values;
    return _SettingsSubsectionCard(
      title: AppLocalizations.of(context)!.settingsShortcutBindings,
      description: AppLocalizations.of(
        context,
      )!.settingsClickRecordThenPressTheNew,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
        child: PrimaryScrollController.none(
          child: OpenHandSafeScrollbar(
            controller: _shortcutListScrollController,
            child: ListView.separated(
              controller: _shortcutListScrollController,
              primary: false,
              padding: EdgeInsets.zero,
              itemCount: actions.length,
              separatorBuilder: (context, index) => kOpenHandGap12,
              itemBuilder: (context, index) {
                final action = actions[index];
                return _ShortcutBindingTile(
                  actionStorageKey: openHandShortcutActionStorageKey(action),
                  title: _shortcutActionTitle(context, action),
                  subtitle: _shortcutActionSubtitle(context, action),
                  value: formatShortcutLabel(bindings[action] ?? const <int>[]),
                  onRecord: () => _showShortcutRecorderDialog(context, action),
                  onReset: () async {
                    final saved = await settingsController.resetShortcutBinding(
                      action,
                    );
                    if (!context.mounted || saved) {
                      return;
                    }
                    _showPersistenceFailureSnackBar(context);
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSkillsSection(
    BuildContext context,
    SettingsController settingsController,
  ) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey<String>('settingsSkillsPathField'),
          controller: _skillsPathController,
          focusNode: _skillsPathFocusNode,
          decoration: InputDecoration(
            labelText: l10n.skillsStorageCurrentPath,
            hintText: settingsController.defaultSkillsStorageLabel,
          ),
          onSubmitted: (value) => _saveSkillsPath(context, value),
        ),
        kOpenHandGap12,
        Text(
          l10n.skillsStorageSectionBody,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        kOpenHandGap18,
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              key: const ValueKey<String>('settingsSkillsSaveButton'),
              onPressed: () =>
                  _saveSkillsPath(context, _skillsPathController.text),
              icon: const Icon(Icons.save_outlined),
              label: Text(l10n.skillsStorageSave),
            ),
            OutlinedButton.icon(
              onPressed: () => _browseSkillsDirectory(context),
              icon: const Icon(Icons.folder_open_outlined),
              label: Text(l10n.skillsStorageBrowse),
            ),
            OutlinedButton.icon(
              onPressed: () => _openSkillsDirectory(context),
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(l10n.skillsStorageOpen),
            ),
            OutlinedButton.icon(
              onPressed: () => _resetSkillsPath(context),
              icon: const Icon(Icons.restart_alt_rounded),
              label: Text(l10n.skillsStorageReset),
            ),
          ],
        ),
        kOpenHandGap18,
        _ReadonlySettingRow(
          label: l10n.skillsStorageCurrentPath,
          value: settingsController.displaySkillsStoragePath,
        ),
        _ReadonlySettingRow(
          label: l10n.skillsStorageDefaultPath,
          value: settingsController.defaultSkillsStorageLabel,
        ),
      ],
    );
  }

  Widget _buildCronsSection(
    BuildContext context,
    SettingsController settingsController,
  ) {
    final enabled = settingsController.cronAutoCleanupEnabled;
    final retention = settingsController.cronAutoCleanupRetentionDays;
    const minR = AppSettingsSnapshot.minCronAutoCleanupRetentionDays;
    const maxR = AppSettingsSnapshot.maxCronAutoCleanupRetentionDays;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ResponsiveSettingRow(
          title: AppLocalizations.of(
            context,
          )!.settingsAutoCleanupExecutionHistory,
          subtitle: AppLocalizations.of(
            context,
          )!.settingsOnEveryColdStartAnAsync,
          control: Switch(
            value: enabled,
            onChanged: (value) async {
              final saved = await settingsController
                  .updateCronAutoCleanupEnabled(value);
              if (!context.mounted || saved) return;
              _showPersistenceFailureSnackBar(context);
            },
          ),
        ),
        kOpenHandGap18,
        Text(
          AppLocalizations.of(
            context,
          )!.settingsRetentionWindowRetentionDayS(retention),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        OpenHandDeferredSlider(
          min: minR.toDouble(),
          max: maxR.toDouble(),
          divisions: maxR - minR,
          value: retention.clamp(minR, maxR).toDouble(),
          labelBuilder: (value) => '${value.round()}',
          onCommit: enabled
              ? (value) async {
                  final saved = await settingsController
                      .updateCronAutoCleanupRetentionDays(value.round());
                  if (!context.mounted || saved) return;
                  _showPersistenceFailureSnackBar(context);
                }
              : null,
        ),
        Text(
          AppLocalizations.of(
            context,
          )!.settingsRangeMinrMaxrDaysDefault7(minR, maxR),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildHermesTalkerSection(
    BuildContext context,
    SettingsController settingsController,
  ) {
    final enabled = settingsController.selfLearningEnabled;
    final concurrency = settingsController.selfLearningConcurrency;
    const minC = AppSettingsSnapshot.minSelfLearningConcurrency;
    const maxC = AppSettingsSnapshot.maxSelfLearningConcurrency;
    final flushMs = settingsController.selfLearningStreamFlushIntervalMs;
    const minFlushMs = AppSettingsSnapshot.minSelfLearningStreamFlushIntervalMs;
    const maxFlushMs = AppSettingsSnapshot.maxSelfLearningStreamFlushIntervalMs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ResponsiveSettingRow(
          title: AppLocalizations.of(context)!.settingsEnableSelfLearning,
          subtitle: AppLocalizations.of(
            context,
          )!.settingsWhenOffTheSchedulerSkipsEvery,
          control: Switch(
            value: enabled,
            onChanged: (value) async {
              final saved = await settingsController.updateSelfLearningEnabled(
                value,
              );
              if (!context.mounted || saved) return;
              _showPersistenceFailureSnackBar(context);
            },
          ),
        ),
        kOpenHandGap18,
        Text(
          AppLocalizations.of(
            context,
          )!.settingsConcurrentWorkersConcurrency(concurrency),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        OpenHandDeferredSlider(
          min: minC.toDouble(),
          max: maxC.toDouble(),
          divisions: maxC - minC,
          value: concurrency.toDouble(),
          labelBuilder: (value) => '${value.round()}',
          onCommit: enabled
              ? (value) async {
                  final saved = await settingsController
                      .updateSelfLearningConcurrency(value.round());
                  if (!context.mounted || saved) return;
                  _showPersistenceFailureSnackBar(context);
                }
              : null,
        ),
        Text(
          AppLocalizations.of(
            context,
          )!.settingsCapsHowManySessionsCanBe(minC, maxC),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        kOpenHandGap18,
        Text(
          AppLocalizations.of(context)!.selfLearningFlushIntervalLabel(flushMs),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        OpenHandDeferredSlider(
          min: minFlushMs.toDouble(),
          max: maxFlushMs.toDouble(),
          divisions: (maxFlushMs - minFlushMs) ~/ 100,
          value: flushMs.toDouble().clamp(
            minFlushMs.toDouble(),
            maxFlushMs.toDouble(),
          ),
          labelBuilder: (value) => '${value.round()}ms',
          onCommit: (value) async {
            final saved = await settingsController
                .updateSelfLearningStreamFlushIntervalMs(value.round());
            if (!context.mounted || saved) return;
            _showPersistenceFailureSnackBar(context);
          },
        ),
        Text(
          AppLocalizations.of(
            context,
          )!.selfLearningFlushIntervalHelper(minFlushMs, maxFlushMs),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        kOpenHandGap18,
        _ResponsiveSettingRow(
          title: AppLocalizations.of(context)!.settingsShowSelfLearningMessages,
          subtitle: AppLocalizations.of(
            context,
          )!.settingsWhenOffSelfLearningCardsAre,
          control: Switch(
            value: settingsController.showSelfLearningMessages,
            onChanged: (value) async {
              final saved = await settingsController
                  .updateShowSelfLearningMessages(value);
              if (!context.mounted || saved) return;
              _showPersistenceFailureSnackBar(context);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMemorySection(
    BuildContext context,
    SettingsController settingsController,
  ) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ResponsiveSettingRow(
          title: l10n.memoryEnabledLabel,
          subtitle: l10n.memoryEnabledBody,
          control: Switch(
            value: settingsController.memoryEnabled,
            onChanged: (value) async {
              final saved = await settingsController.updateMemoryEnabled(value);
              if (!context.mounted || saved) {
                return;
              }
              _showPersistenceFailureSnackBar(context);
            },
          ),
        ),
        kOpenHandGap14,
        Text(
          l10n.memoryFileBody,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        kOpenHandGap18,
        _ReadonlySettingRow(
          label: l10n.userMemoryFileLabel,
          value: context.read<MemoryController>().userMemoryFilePath,
        ),
        _ReadonlySettingRow(
          label: l10n.memoryFileDefaultPath,
          value: context.read<MemoryController>().storageDirectoryPath,
        ),
      ],
    );
  }

  // 内置工具设置

  Widget _buildBuiltinToolsSection(
    BuildContext context,
    SettingsController settingsController,
  ) {
    final configs = settingsController.builtinToolConfigs;
    final sorted = List<AiBuiltinToolConfig>.from(configs)
      ..sort((a, b) {
        final cmp = a.sortOrder.compareTo(b.sortOrder);
        return cmp != 0 ? cmp : a.kind.index.compareTo(b.kind.index);
      });
    final enabledCount = sorted.where((c) => c.enabled).length;
    final machineTerminalToolConfigs = sorted
        .where((config) => config.kind.isMachineTerminalTool)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingsSubsectionCard(
          title: openHandLocalizedText(
            context,
            zh: '内建工具懒加载',
            en: 'Built-in tool lazy loading',
          ),
          description: openHandLocalizedText(
            context,
            zh: '控制是否折叠内建工具 schema。自动模式使用内建工具专用阈值，并以 MCP 阈值作为上限：${settingsController.mcpLazyLoadingThresholdTokens} tokens。',
            en: 'Controls whether built-in tool schemas are folded. Auto mode uses a built-in-tool threshold capped by the MCP threshold: ${settingsController.mcpLazyLoadingThresholdTokens} tokens.',
          ),
          child: _ResponsiveSettingRow(
            title: openHandLocalizedText(context, zh: '加载模式', en: 'Load mode'),
            subtitle: openHandLocalizedText(
              context,
              zh: '关闭时全部直接携带；自动时超过阈值才懒加载；开启时按工具配置折叠非强制加载项。',
              en: 'Off sends every schema. Auto defers only above the threshold. On follows per-tool force-load settings.',
            ),
            controlMaxWidth: 440,
            control: SizedBox(
              width: double.infinity,
              child: SegmentedButton<AiBuiltinToolLazyLoadingMode>(
                segments: <ButtonSegment<AiBuiltinToolLazyLoadingMode>>[
                  ButtonSegment<AiBuiltinToolLazyLoadingMode>(
                    value: AiBuiltinToolLazyLoadingMode.disabled,
                    icon: const Icon(Icons.toggle_off_outlined),
                    label: Text(openHandOffLabel(context), softWrap: false),
                  ),
                  ButtonSegment<AiBuiltinToolLazyLoadingMode>(
                    value: AiBuiltinToolLazyLoadingMode.auto,
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: Text(openHandAutoLabel(context), softWrap: false),
                  ),
                  ButtonSegment<AiBuiltinToolLazyLoadingMode>(
                    value: AiBuiltinToolLazyLoadingMode.enabled,
                    icon: const Icon(Icons.toggle_on_rounded),
                    label: Text(openHandOnLabel(context), softWrap: false),
                  ),
                ],
                selected: <AiBuiltinToolLazyLoadingMode>{
                  settingsController.builtinToolLazyLoadingMode,
                },
                onSelectionChanged: (selection) async {
                  if (selection.isEmpty) return;
                  final saved = await settingsController
                      .updateBuiltinToolLazyLoadingMode(selection.first);
                  if (!context.mounted || saved) return;
                  _showPersistenceFailureSnackBar(context);
                },
              ),
            ),
          ),
        ),
        kOpenHandGap14,
        _MachineTerminalBuiltinToolSummaryCard(
          configs: machineTerminalToolConfigs,
          onEnableAll: machineTerminalToolConfigs.isEmpty
              ? null
              : () => _toggleMachineTerminalBuiltinTools(
                  context,
                  settingsController,
                  enabled: true,
                ),
          onDisableAll: machineTerminalToolConfigs.isEmpty
              ? null
              : () => _toggleMachineTerminalBuiltinTools(
                  context,
                  settingsController,
                  enabled: false,
                ),
        ),
        kOpenHandGap14,
        _SettingsSubsectionCard(
          title: AppLocalizations.of(context)!.settingsToolCatalogOverview,
          description: AppLocalizations.of(context)!
              .settingsSortedLengthBuiltInToolsEnabledcount(
                sorted.length,
                enabledCount,
              ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  resourceUsageStatisticsButton(
                    context,
                    onPressed: () => showResourceUsageStatisticsDialog(
                      context,
                      kind: AiResourceUsageKind.tool,
                      resourceLabels: <String, String>{
                        for (final config in sorted) ...<String, String>{
                          config.effectiveName: config.effectiveName,
                          if (AiToolRuntimeService.builtinToolDefault(
                                config.kind,
                              )
                              case final tool?)
                            tool.definition.name: config.effectiveName,
                        },
                      },
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => _showBuiltinToolResetConfirmDialog(
                      context,
                      settingsController,
                    ),
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: Text(AppLocalizations.of(context)!.settingsResetAll),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      _toggleAllBuiltinTools(context, settingsController, true);
                    },
                    icon: const Icon(Icons.check_circle_outline_rounded),
                    label: Text(
                      AppLocalizations.of(context)!.settingsEnableAll,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      _toggleAllBuiltinTools(
                        context,
                        settingsController,
                        false,
                      );
                    },
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                    label: Text(
                      AppLocalizations.of(context)!.settingsDisableAll,
                    ),
                  ),
                ],
              ),
              kOpenHandGap16,
              if (sorted.isEmpty)
                _SettingsStateBox(
                  icon: Icons.build_circle_outlined,
                  title: AppLocalizations.of(
                    context,
                  )!.settingsNoBuiltInToolConfigurations,
                  body: AppLocalizations.of(
                    context,
                  )!.settingsClickResetAllToRestoreThe,
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 520),
                  child: ListView.separated(
                    primary: false,
                    padding: EdgeInsets.zero,
                    itemCount: sorted.length,
                    separatorBuilder: (context, index) => kOpenHandGap10,
                    itemBuilder: (context, index) {
                      final config = sorted[index];
                      return _BuiltinToolTile(
                        config: config,
                        isFirst: index == 0,
                        isLast: index == sorted.length - 1,
                        onToggle: (enabled) async {
                          final updated = config.copyWith(enabled: enabled);
                          await settingsController.updateBuiltinToolConfig(
                            updated,
                          );
                        },
                        onEdit: () => _showBuiltinToolEditorDialog(
                          context,
                          settingsController,
                          config: config,
                        ),
                        onMoveUp: index > 0
                            ? () {
                                final realOldIndex = configs.indexOf(config);
                                final realNewIndex = configs.indexOf(
                                  sorted[index - 1],
                                );
                                if (realOldIndex >= 0 && realNewIndex >= 0) {
                                  settingsController.moveBuiltinToolConfig(
                                    realOldIndex,
                                    realNewIndex,
                                  );
                                }
                              }
                            : null,
                        onMoveDown: index < sorted.length - 1
                            ? () {
                                final realOldIndex = configs.indexOf(config);
                                final realNewIndex = configs.indexOf(
                                  sorted[index + 1],
                                );
                                if (realOldIndex >= 0 && realNewIndex >= 0) {
                                  settingsController.moveBuiltinToolConfig(
                                    realOldIndex,
                                    realNewIndex,
                                  );
                                }
                              }
                            : null,
                        onDelete: config.isCustom
                            ? () => _confirmDeleteBuiltinTool(
                                context,
                                settingsController,
                                config,
                              )
                            : null,
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _toggleAllBuiltinTools(
    BuildContext context,
    SettingsController settingsController,
    bool enabled,
  ) async {
    final configs = settingsController.builtinToolConfigs;
    final updated = configs
        .map((c) => c.copyWith(enabled: enabled))
        .toList(growable: false);
    final saved = await settingsController.updateBuiltinToolConfigs(updated);
    if (!context.mounted || saved) return;
    _showPersistenceFailureSnackBar(context);
  }

  Future<void> _toggleMachineTerminalBuiltinTools(
    BuildContext context,
    SettingsController settingsController, {
    required bool enabled,
  }) async {
    final configs = settingsController.builtinToolConfigs;
    var changed = false;
    final updated = configs
        .map((config) {
          if (!config.kind.isMachineTerminalTool || config.enabled == enabled) {
            return config;
          }
          changed = true;
          return config.copyWith(enabled: enabled);
        })
        .toList(growable: false);
    if (!changed) return;
    final saved = await settingsController.updateBuiltinToolConfigs(updated);
    if (!context.mounted || saved) return;
    _showPersistenceFailureSnackBar(context);
  }

  Future<void> _showBuiltinToolResetConfirmDialog(
    BuildContext context,
    SettingsController settingsController,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      icon: const Icon(Icons.restart_alt_rounded),
      title: l10n.settingsResetBuiltInToolConfigs,
      message: l10n.settingsThisWillRestoreAllBuiltIn,
      cancelLabel: l10n.settingsCancel,
      confirmLabel: l10n.settingsReset,
    );
    if (!confirmed || !context.mounted) return;
    final saved = await settingsController.resetBuiltinToolConfigs();
    if (!context.mounted || saved) return;
    _showPersistenceFailureSnackBar(context);
  }

  Future<void> _confirmDeleteBuiltinTool(
    BuildContext context,
    SettingsController settingsController,
    AiBuiltinToolConfig config,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      icon: const Icon(Icons.delete_outline_rounded),
      title: l10n.settingsDeleteCustomTool,
      message: l10n.settingsAreYouSureYouWantTo(config.effectiveName),
      cancelLabel: l10n.settingsCancel,
      confirmLabel: l10n.settingsDelete,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final saved = await settingsController.removeBuiltinToolConfig(config.kind);
    if (!context.mounted || saved) return;
    _showPersistenceFailureSnackBar(context);
  }

  Future<void> _showBuiltinToolEditorDialog(
    BuildContext context,
    SettingsController settingsController, {
    required AiBuiltinToolConfig config,
  }) async {
    final defaults = AiToolRuntimeService.builtinToolDefault(config.kind);
    final result = await showAnimatedDialog<AiBuiltinToolConfig>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _BuiltinToolEditorDialog(
          initial: config,
          defaultName: defaults?.definition.name,
          defaultDescription: defaults?.definition.description,
          defaultParameters: defaults?.definition.parameters,
          availableModels: settingsController.aiModels,
          recentModelSelections: settingsController.recentModelSelections,
        );
      },
    );
    if (result == null || !context.mounted) return;
    final saved = await settingsController.updateBuiltinToolConfig(result);
    if (!context.mounted || saved) return;
    _showPersistenceFailureSnackBar(context);
  }

  Widget _buildMcpSettingsSection(
    BuildContext context,
    SettingsController settingsController,
  ) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ResponsiveSettingRow(
          title: l10n.mcpEnabledLabel,
          subtitle: l10n.mcpEnabledBody,
          control: Switch(
            value: settingsController.mcpEnabled,
            onChanged: (value) async {
              final saved = await settingsController.updateMcpEnabled(value);
              if (!context.mounted || saved) {
                return;
              }
              _showPersistenceFailureSnackBar(context);
            },
          ),
        ),
        kOpenHandGap14,
        _ReadonlySettingRow(
          label: l10n.mcpFilePathLabel,
          value: settingsController.displayMcpServersFilePath,
        ),
        kOpenHandGap12,
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton.icon(
              onPressed: () => _openMcpDirectory(context),
              icon: const Icon(Icons.folder_open_rounded),
              label: Text(l10n.mcpOpenDirectory),
            ),
            OutlinedButton.icon(
              onPressed: () => _resetStdioPackageCache(context),
              icon: const Icon(Icons.cleaning_services_outlined),
              label: Text(l10n.mcpStdioCacheResetAction),
            ),
          ],
        ),
        kOpenHandGap14,
        _ResponsiveSettingRow(
          title: l10n.mcpStdioMirrorModeLabel,
          subtitle: l10n.mcpStdioMirrorModeBody,
          controlMaxWidth: 460,
          control: _McpStdioMirrorModeControl(
            settingsController: settingsController,
            onPersistenceFailure: () =>
                _showPersistenceFailureSnackBar(context),
            onReconnect: () => _reconnectMcpServersForMirrorChange(context),
          ),
        ),
        kOpenHandGap14,
        _ResponsiveSettingRow(
          title: l10n.mcpAutoProbeConcurrencyLabel,
          subtitle: l10n.mcpAutoProbeConcurrencyBody,
          control: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey<String>(
                  'settingsMcpAutoProbeConcurrencyField',
                ),
                controller: _mcpAutoProbeConcurrencyController,
                focusNode: _mcpAutoProbeConcurrencyFocusNode,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: InputDecoration(
                  labelText: l10n.mcpAutoProbeConcurrencyLabel,
                  hintText:
                      '${AppSettingsSnapshot.defaultMcpAutoProbeConcurrency}',
                ),
                onSubmitted: (value) =>
                    _saveMcpAutoProbeConcurrency(context, value),
              ),
              kOpenHandGap12,
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  key: const ValueKey<String>(
                    'settingsMcpAutoProbeConcurrencySaveButton',
                  ),
                  onPressed: () => _saveMcpAutoProbeConcurrency(
                    context,
                    _mcpAutoProbeConcurrencyController.text,
                  ),
                  icon: const Icon(Icons.save_outlined),
                  label: Text(l10n.mcpAutoProbeConcurrencySave),
                ),
              ),
            ],
          ),
        ),
        kOpenHandGap14,
        _ResponsiveSettingRow(
          title: l10n.mcpKeywordIndexUpdateModeLabel,
          subtitle: l10n.mcpKeywordIndexUpdateModeBody,
          control: _McpKeywordIndexUpdateModeControl(
            settingsController: settingsController,
            onPersistenceFailure: () =>
                _showPersistenceFailureSnackBar(context),
          ),
        ),
        kOpenHandGap18,
        _McpLazyLoadingHelpBanner(text: l10n.mcpLazyLoadingHowItWorks),
        kOpenHandGap8,
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: () => _openCurrentSessionLoadedToolsDialog(context),
            icon: const Icon(Icons.search_rounded, size: 18),
            label: Text(l10n.mcpLazyLoadingViewLoadedAction),
          ),
        ),
        kOpenHandGap8,
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => _resetToolSearchExportLastDir(context),
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: Text(l10n.mcpToolSearchExportLastDirResetAction),
          ),
        ),
        // 恢复入口：重发上次在反悔窗口中取消的 ToolSearch 操作。
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: ValueListenableBuilder<bool>(
            valueListenable: context
                .read<ToolSearchReplayDispatcher>()
                .replayableListenable,
            builder: (ctx, hasReplayable, _) {
              return TextButton.icon(
                onPressed: hasReplayable
                    ? () => _replayLastCancelledToolSearch(ctx)
                    : null,
                icon: const Icon(Icons.replay_rounded, size: 18),
                label: Text(l10n.mcpToolSearchReplayLastCancelAction),
              );
            },
          ),
        ),
        kOpenHandGap12,
        _ResponsiveSettingRow(
          title: l10n.mcpLazyLoadingModeLabel,
          subtitle: l10n.mcpLazyLoadingModeBody,
          controlMaxWidth: 440,
          control: SizedBox(
            width: double.infinity,
            child: SegmentedButton<McpLazyLoadingMode>(
              segments: <ButtonSegment<McpLazyLoadingMode>>[
                ButtonSegment<McpLazyLoadingMode>(
                  value: McpLazyLoadingMode.disabled,
                  icon: const Icon(Icons.toggle_off_outlined),
                  label: Text(l10n.mcpLazyLoadingModeDisabled, softWrap: false),
                ),
                ButtonSegment<McpLazyLoadingMode>(
                  value: McpLazyLoadingMode.auto,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: Text(l10n.mcpLazyLoadingModeAuto, softWrap: false),
                ),
                ButtonSegment<McpLazyLoadingMode>(
                  value: McpLazyLoadingMode.enabled,
                  icon: const Icon(Icons.toggle_on_rounded),
                  label: Text(l10n.mcpLazyLoadingModeEnabled, softWrap: false),
                ),
              ],
              selected: <McpLazyLoadingMode>{
                settingsController.mcpLazyLoadingMode,
              },
              onSelectionChanged: (selection) async {
                if (selection.isEmpty) return;
                final saved = await settingsController.updateMcpLazyLoadingMode(
                  selection.first,
                );
                if (!context.mounted || saved) return;
                _showPersistenceFailureSnackBar(context);
              },
            ),
          ),
        ),
        kOpenHandGap14,
        _ResponsiveSettingRow(
          title: l10n.mcpLazyLoadingThresholdLabel,
          subtitle: l10n.mcpLazyLoadingThresholdBody,
          controlMaxWidth: 360,
          control: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey<String>(
                  'settingsMcpLazyLoadingThresholdField',
                ),
                controller: _mcpLazyLoadingThresholdController,
                focusNode: _mcpLazyLoadingThresholdFocusNode,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: InputDecoration(
                  labelText: l10n.mcpLazyLoadingThresholdLabel,
                  hintText:
                      '${AppSettingsSnapshot.defaultMcpLazyLoadingThresholdTokens}',
                ),
                onSubmitted: (value) =>
                    _saveMcpLazyLoadingThreshold(context, value),
              ),
              kOpenHandGap12,
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  key: const ValueKey<String>(
                    'settingsMcpLazyLoadingThresholdSaveButton',
                  ),
                  onPressed: () => _saveMcpLazyLoadingThreshold(
                    context,
                    _mcpLazyLoadingThresholdController.text,
                  ),
                  icon: const Icon(Icons.save_outlined),
                  label: Text(l10n.mcpLazyLoadingThresholdSave),
                ),
              ),
            ],
          ),
        ),
        kOpenHandGap18,
        FirstFramePulseBox(
          child: _buildHarnessToolSearchHistoryRow(
            context,
            settingsController,
            l10n,
          ),
        ),
        kOpenHandGap18,
        FirstFramePulseBox(
          child: _buildToolSearchReplayCancelWindowRow(
            context,
            settingsController,
            l10n,
          ),
        ),
      ],
    );
  }

  /// Harness ToolSearch 历史 LRU 桶上限滑块，1..64，默认 8。
  /// 与 cron retention 同款 Slider，无需 TextEditingController。
  Widget _buildHarnessToolSearchHistoryRow(
    BuildContext context,
    SettingsController settingsController,
    AppLocalizations l10n,
  ) {
    final cap = settingsController.harnessToolSearchHistoryMaxPhases;
    const minCap = AppSettingsSnapshot.minHarnessToolSearchHistoryMaxPhases;
    const maxCap = AppSettingsSnapshot.maxHarnessToolSearchHistoryMaxPhases;
    const defaultCap =
        AppSettingsSnapshot.defaultHarnessToolSearchHistoryMaxPhases;
    return _ResponsiveSettingRow(
      title: l10n.settingsHarnessToolSearchHistoryCapLabel,
      subtitle: l10n.settingsHarnessToolSearchHistoryCapBody,
      controlMaxWidth: 360,
      control: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.settingsHarnessToolSearchHistoryCapValue(cap),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              IconButton(
                tooltip: l10n.settingsHarnessToolSearchHistoryCapResetTooltip(
                  defaultCap,
                ),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                onPressed: cap == defaultCap
                    ? null
                    : () async {
                        final saved = await settingsController
                            .updateHarnessToolSearchHistoryMaxPhases(
                              defaultCap,
                            );
                        if (!context.mounted || saved) return;
                        _showPersistenceFailureSnackBar(context);
                      },
              ),
            ],
          ),
          KeyTweakableSlider(
            value: cap,
            min: minCap,
            max: maxCap,
            onChanged: (next) async {
              final saved = await settingsController
                  .updateHarnessToolSearchHistoryMaxPhases(next);
              if (!context.mounted || saved) return;
              _showPersistenceFailureSnackBar(context);
            },
            buildSlider: (context, value) => OpenHandDeferredSlider(
              min: minCap.toDouble(),
              max: maxCap.toDouble(),
              divisions: maxCap - minCap,
              value: value.clamp(minCap, maxCap).toDouble(),
              labelBuilder: (current) => '${current.round()}',
              onCommit: (v) async {
                final saved = await settingsController
                    .updateHarnessToolSearchHistoryMaxPhases(v.round());
                if (!context.mounted || saved) return;
                _showPersistenceFailureSnackBar(context);
              },
            ),
          ),
          Text(
            l10n.settingsHarnessToolSearchHistoryCapRange(minCap, maxCap),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// ToolSearch 历史「重放」按钮的反悔窗口（秒）。1..30，默认 3。
  Widget _buildToolSearchReplayCancelWindowRow(
    BuildContext context,
    SettingsController settingsController,
    AppLocalizations l10n,
  ) {
    final seconds = settingsController.toolSearchReplayCancelWindowSeconds;
    const minSec = AppSettingsSnapshot.minToolSearchReplayCancelWindowSeconds;
    const maxSec = AppSettingsSnapshot.maxToolSearchReplayCancelWindowSeconds;
    const defaultSec =
        AppSettingsSnapshot.defaultToolSearchReplayCancelWindowSeconds;
    return _ResponsiveSettingRow(
      title: l10n.settingsToolSearchReplayCancelWindowLabel,
      subtitle: l10n.settingsToolSearchReplayCancelWindowBody,
      controlMaxWidth: 360,
      control: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.settingsToolSearchReplayCancelWindowValue(seconds),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              IconButton(
                tooltip: l10n.settingsToolSearchReplayCancelWindowResetTooltip(
                  defaultSec,
                ),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                onPressed: seconds == defaultSec
                    ? null
                    : () async {
                        final saved = await settingsController
                            .updateToolSearchReplayCancelWindowSeconds(
                              defaultSec,
                            );
                        if (!context.mounted || saved) return;
                        _showPersistenceFailureSnackBar(context);
                      },
              ),
            ],
          ),
          KeyTweakableSlider(
            value: seconds,
            min: minSec,
            max: maxSec,
            onChanged: (next) async {
              final saved = await settingsController
                  .updateToolSearchReplayCancelWindowSeconds(next);
              if (!context.mounted || saved) return;
              _showPersistenceFailureSnackBar(context);
            },
            buildSlider: (context, value) => OpenHandDeferredSlider(
              min: minSec.toDouble(),
              max: maxSec.toDouble(),
              divisions: maxSec - minSec,
              value: value.clamp(minSec, maxSec).toDouble(),
              labelBuilder: (current) => '${current.round()}s',
              onCommit: (v) async {
                final saved = await settingsController
                    .updateToolSearchReplayCancelWindowSeconds(v.round());
                if (!context.mounted || saved) return;
                _showPersistenceFailureSnackBar(context);
              },
            ),
          ),
          Text(
            l10n.settingsToolSearchReplayCancelWindowRange(minSec, maxSec),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveSkillsPath(BuildContext context, String rawPath) async {
    final l10n = AppLocalizations.of(context)!;
    final settingsController = context.read<SettingsController>();
    final skillsController = context.read<SkillsController>();
    await _saveReloadablePathSetting(
      context: context,
      fieldController: _skillsPathController,
      rawPath: rawPath,
      currentPath: (controller) => controller.skillsStoragePath,
      saveSetting: settingsController.updateSkillsStoragePath,
      reloadRuntime: skillsController.reloadFromPath,
      restoreSetting: (previousPath) => _restoreSkillsPath(
        settingsController,
        skillsController,
        previousPath,
      ),
      successMessage: l10n.skillsPathSaved,
      failureMessage: l10n.skillOperationFailed,
    );
  }

  Future<void> _browseSkillsDirectory(BuildContext context) async {
    final selectedPath = await getDirectoryPath();
    if (!context.mounted || selectedPath == null || selectedPath.isEmpty) {
      return;
    }
    _skillsPathController.text = selectedPath;
    await _saveSkillsPath(context, selectedPath);
  }

  Future<void> _openSkillsDirectory(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await context.read<SkillsController>().openStorageDirectory();
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      flashOpenHandSnack(
        context,
        l10n.skillOperationFailed,
        kind: OpenHandSnackKind.error,
      );
    }
  }

  Future<void> _resetSkillsPath(BuildContext context) async {
    final defaultPath = context
        .read<SettingsController>()
        .defaultSkillsStoragePath;
    _skillsPathController.text = defaultPath;
    await _saveSkillsPath(context, defaultPath);
  }

  Future<void> _saveReloadablePathSetting({
    required BuildContext context,
    required TextEditingController fieldController,
    required String rawPath,
    required _SettingsPathGetter currentPath,
    required _SettingsPathOperation saveSetting,
    required _SettingsPathOperation reloadRuntime,
    required _SettingsPathOperation restoreSetting,
    required String successMessage,
    required String failureMessage,
  }) async {
    final settingsController = context.read<SettingsController>();
    final previousPath = currentPath(settingsController);
    try {
      final saved = await saveSetting(rawPath);
      if (!saved) {
        if (!context.mounted) {
          return;
        }
        fieldController.text = currentPath(settingsController);
        _showPersistenceFailureSnackBar(context);
        return;
      }
      final reloaded = await reloadRuntime(currentPath(settingsController));
      if (!reloaded) {
        final rolledBack = await restoreSetting(previousPath);
        if (!context.mounted) {
          return;
        }
        fieldController.text = currentPath(settingsController);
        if (!rolledBack && settingsController.persistenceIssue != null) {
          _showPersistenceFailureSnackBar(context);
          return;
        }
        flashOpenHandSnack(context, failureMessage);
        return;
      }
      if (!context.mounted) {
        return;
      }
      fieldController.text = currentPath(settingsController);
      flashOpenHandSnack(context, successMessage);
    } catch (_) {
      final rolledBack = await restoreSetting(previousPath);
      if (!context.mounted) {
        return;
      }
      fieldController.text = currentPath(settingsController);
      if (!rolledBack && settingsController.persistenceIssue != null) {
        _showPersistenceFailureSnackBar(context);
        return;
      }
      flashOpenHandSnack(context, failureMessage);
    }
  }

  Future<bool> _restoreSkillsPath(
    SettingsController settingsController,
    SkillsController skillsController,
    String previousPath,
  ) async {
    if (settingsController.skillsStoragePath != previousPath) {
      final restored = await settingsController.updateSkillsStoragePath(
        previousPath,
      );
      if (!restored) {
        return false;
      }
    }
    return skillsController.reloadFromPath(previousPath);
  }

  Future<void> _saveBoundedIntegerSetting({
    required BuildContext context,
    required String rawValue,
    required int min,
    required int max,
    required TextEditingController fieldController,
    required int Function(SettingsController controller) currentValue,
    required Future<bool> Function(SettingsController controller, int value)
    saveValue,
    required String successMessage,
    String? invalidMessage,
    OpenHandSnackKind invalidKind = OpenHandSnackKind.info,
    OpenHandSnackKind successKind = OpenHandSnackKind.info,
  }) async {
    final parsedValue = optionalIntFromValue(rawValue);
    if (parsedValue == null || parsedValue < min || parsedValue > max) {
      flashOpenHandSnack(
        context,
        invalidMessage ??
            AppLocalizations.of(
              context,
            )!.settingsEnterAValueBetweenMinAnd(min, max),
        kind: invalidKind,
      );
      return;
    }

    final settingsController = context.read<SettingsController>();
    final saved = await saveValue(settingsController, parsedValue);
    if (!context.mounted) {
      return;
    }
    fieldController.text = '${currentValue(settingsController)}';
    if (!saved) {
      _showPersistenceFailureSnackBar(context);
      return;
    }
    flashOpenHandSnack(context, successMessage, kind: successKind);
  }

  Future<void> _saveConnectTimeout(
    BuildContext context,
    String rawValue,
  ) async {
    await _saveBoundedIntegerSetting(
      context: context,
      rawValue: rawValue,
      min: AppSettingsSnapshot.minAiConnectTimeoutSeconds,
      max: AppSettingsSnapshot.maxAiConnectTimeoutSeconds,
      fieldController: _connectTimeoutController,
      currentValue: (controller) => controller.aiConnectTimeoutSeconds,
      saveValue: (controller, value) =>
          controller.updateAiConnectTimeoutSeconds(value),
      successMessage: AppLocalizations.of(context)!.settingsSendTimeoutSaved,
    );
  }

  Future<void> _saveResponseTimeout(
    BuildContext context,
    String rawValue,
  ) async {
    await _saveBoundedIntegerSetting(
      context: context,
      rawValue: rawValue,
      min: AppSettingsSnapshot.minAiResponseTimeoutSeconds,
      max: AppSettingsSnapshot.maxAiResponseTimeoutSeconds,
      fieldController: _responseTimeoutController,
      currentValue: (controller) => controller.aiResponseTimeoutSeconds,
      saveValue: (controller, value) =>
          controller.updateAiResponseTimeoutSeconds(value),
      successMessage: AppLocalizations.of(
        context,
      )!.settingsResponseTimeoutSaved,
    );
  }

  Future<void> _saveStreamIdleTimeout(
    BuildContext context,
    String rawValue,
  ) async {
    await _saveBoundedIntegerSetting(
      context: context,
      rawValue: rawValue,
      min: AppSettingsSnapshot.minAiStreamIdleTimeoutSeconds,
      max: AppSettingsSnapshot.maxAiStreamIdleTimeoutSeconds,
      fieldController: _streamIdleTimeoutController,
      currentValue: (controller) => controller.aiStreamIdleTimeoutSeconds,
      saveValue: (controller, value) =>
          controller.updateAiStreamIdleTimeoutSeconds(value),
      successMessage: AppLocalizations.of(
        context,
      )!.settingsStreamIdleTimeoutSaved,
    );
  }

  Future<void> _saveStreamMaxCharsPerSecond(
    BuildContext context,
    String rawValue,
  ) async {
    await _saveBoundedIntegerSetting(
      context: context,
      rawValue: rawValue,
      min: AppSettingsSnapshot.minAiStreamMaxCharsPerSecond,
      max: AppSettingsSnapshot.maxAiStreamMaxCharsPerSecond,
      fieldController: _streamMaxCharsPerSecondController,
      currentValue: (controller) => controller.aiStreamMaxCharsPerSecond,
      saveValue: (controller, value) =>
          controller.updateAiStreamMaxCharsPerSecond(value),
      successMessage: openHandLocalizedText(
        context,
        zh: '每秒最大输出渲染字符已保存。',
        zhHant: '每秒最大輸出渲染字元已儲存。',
        en: 'Max render chars / sec saved.',
        fr: 'Nombre maximal de caractères rendus par seconde enregistré.',
        de: 'Maximale Render-Zeichen pro Sekunde gespeichert.',
        ja: '1 秒あたりの最大描画文字数を保存しました。',
      ),
    );
  }

  Future<void> _saveStreamMaxMessageCardsPerSecond(
    BuildContext context,
    String rawValue,
  ) async {
    await _saveBoundedIntegerSetting(
      context: context,
      rawValue: rawValue,
      min: AppSettingsSnapshot.minAiStreamMaxMessageCardsPerSecond,
      max: AppSettingsSnapshot.maxAiStreamMaxMessageCardsPerSecond,
      fieldController: _streamMaxMessageCardsPerSecondController,
      currentValue: (controller) => controller.aiStreamMaxMessageCardsPerSecond,
      saveValue: (controller, value) =>
          controller.updateAiStreamMaxMessageCardsPerSecond(value),
      successMessage: openHandLocalizedText(
        context,
        zh: '每秒最大输出消息卡片数已保存。',
        zhHant: '每秒最大輸出訊息卡片數已儲存。',
        en: 'Max render cards / sec saved.',
        fr: 'Nombre maximal de cartes rendues par seconde enregistré.',
        de: 'Maximale Render-Karten pro Sekunde gespeichert.',
        ja: '1 秒あたりの最大描画カード数を保存しました。',
      ),
    );
  }

  /// 保存节流持续时长（秒）。0 = 持续节流。
  Future<void> _saveStreamThrottleDurationSeconds(
    BuildContext context,
    String rawValue,
  ) async {
    await _saveBoundedIntegerSetting(
      context: context,
      rawValue: rawValue,
      min: AppSettingsSnapshot.minAiStreamThrottleDurationSeconds,
      max: AppSettingsSnapshot.maxAiStreamThrottleDurationSeconds,
      fieldController: _streamThrottleDurationController,
      currentValue: (controller) => controller.aiStreamThrottleDurationSeconds,
      saveValue: (controller, value) =>
          controller.updateAiStreamThrottleDurationSeconds(value),
      successMessage: openHandLocalizedText(
        context,
        zh: '节流持续时长已保存。',
        zhHant: '節流持續時長已儲存。',
        en: 'Throttle duration saved.',
        fr: 'Durée de limitation enregistrée.',
        de: 'Drosselungsdauer gespeichert.',
        ja: 'スロットリング継続時間を保存しました。',
      ),
    );
  }

  /// 把当前节流配置序列化为 JSON 文件。
  Future<void> _exportAiStreamThrottleConfig(BuildContext context) async {
    final controller = context.read<SettingsController>();
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    const typeGroup = XTypeGroup(label: 'JSON', extensions: <String>['json']);
    FileSaveLocation? location;
    try {
      location = await getSaveLocation(
        suggestedName: 'openhand-throttle-config-$ts.json',
        acceptedTypeGroups: const <XTypeGroup>[typeGroup],
      );
    } catch (error, stack) {
      silentLog('settings', '打开节流配置保存位置', error, stack);
      if (!context.mounted) return;
      flashOpenHandSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '打开保存对话框失败。',
          zhHant: '開啟儲存對話框失敗。',
          en: 'Failed to open save dialog.',
          fr: 'Impossible d’ouvrir la boîte de dialogue d’enregistrement.',
          de: 'Speicherdialog konnte nicht geöffnet werden.',
          ja: '保存ダイアログを開けませんでした。',
        ),
        kind: OpenHandSnackKind.error,
      );
      return;
    }
    if (location == null) return;
    try {
      final doc = controller.exportAiStreamThrottleConfig();
      await writeFileAtomically(File(location.path), prettyPrintJson(doc));
    } catch (error, stack) {
      silentLog('settings', '写入节流配置', error, stack);
      if (!context.mounted) return;
      flashOpenHandSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '导出失败。',
          zhHant: '匯出失敗。',
          en: 'Export failed.',
          fr: 'Échec de l’exportation.',
          de: 'Export fehlgeschlagen.',
          ja: 'エクスポートに失敗しました。',
        ),
        kind: OpenHandSnackKind.error,
      );
      return;
    }
    if (!context.mounted) return;
    flashOpenHandSnack(
      context,
      openHandLocalizedText(
        context,
        zh: '已导出节流配置。',
        zhHant: '已匯出節流設定。',
        en: 'Throttle config exported.',
        fr: 'Configuration de limitation exportée.',
        de: 'Drosselungskonfiguration exportiert.',
        ja: 'スロットリング設定をエクスポートしました。',
      ),
      kind: OpenHandSnackKind.success,
    );
  }

  /// 从 JSON 文件 import 节流配置；缺失字段保持现值。
  Future<void> _importAiStreamThrottleConfig(BuildContext context) async {
    final controller = context.read<SettingsController>();
    const typeGroup = XTypeGroup(label: 'JSON', extensions: <String>['json']);
    XFile? file;
    try {
      file = await openFile(acceptedTypeGroups: const <XTypeGroup>[typeGroup]);
    } catch (error, stack) {
      silentLog('settings', '打开节流配置文件', error, stack);
      if (!context.mounted) return;
      flashOpenHandSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '打开文件对话框失败。',
          zhHant: '開啟檔案對話框失敗。',
          en: 'Failed to open file dialog.',
          fr: 'Impossible d’ouvrir la boîte de dialogue de fichier.',
          de: 'Dateidialog konnte nicht geöffnet werden.',
          ja: 'ファイルダイアログを開けませんでした。',
        ),
        kind: OpenHandSnackKind.error,
      );
      return;
    }
    if (file == null) return;
    Map<String, Object?> nextDoc;
    try {
      final bytes = await readBoundedXFileBytes(
        file,
        maxBytes: _kThrottleConfigImportMaxBytes,
      );
      final raw = utf8.decode(bytes);
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException('JSON 根节点必须是对象');
      }
      nextDoc = stringKeyedMapFromValue(decoded);
    } catch (error, stack) {
      silentLog('settings', '解析节流配置', error, stack);
      if (!context.mounted) return;
      final maxSize = formatByteSize(_kThrottleConfigImportMaxBytes);
      flashOpenHandSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '导入失败，请确认 JSON 配置有效且未超过 $maxSize。',
          zhHant: '匯入失敗，請確認 JSON 設定有效且未超過 $maxSize。',
          en: 'Import failed. Check that the JSON configuration is valid and no larger than $maxSize.',
          fr: 'Échec de l’importation. Vérifiez que la configuration JSON est valide et ne dépasse pas $maxSize.',
          de: 'Import fehlgeschlagen. Die JSON-Konfiguration muss gültig und höchstens $maxSize groß sein.',
          ja: 'インポートに失敗しました。JSON 設定が有効で $maxSize 以下か確認してください。',
        ),
        kind: OpenHandSnackKind.error,
      );
      return;
    }
    if (!context.mounted) return;
    // 应用前先弹「冲突预览」对话框，让用户看清哪些字段
    // 会被覆盖；用户确认后才真正写入。
    // 跨版本兼容：老 doc（v1）缺 `duration_seconds` 时，
    // 先 migrate 到当前 schema 再做 diff，避免预览里出现 5→— 这种
    // 容易被误读为"清空"的展示。migrate 不会破坏未识别字段，向前兼容。
    final current = controller.exportAiStreamThrottleConfig();
    final migratedNext = migrateAiStreamThrottleConfig(nextDoc);
    final diffs = _diffThrottleConfig(current, migratedNext);
    if (diffs.isEmpty) {
      flashOpenHandSnack(
        context,
        _settingsViewNoChangesDetectedLabel(context),
        kind: OpenHandSnackKind.success,
      );
      return;
    }
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      content: buildOpenHandDialogConstrainedContent(
        width: 600,
        maxHeight: 420,
        child: _ThrottleImportDiffContent(diffs: diffs, showActions: false),
      ),
      title: openHandLocalizedText(
        context,
        zh: '导入节流配置？',
        zhHant: '匯入節流設定？',
        en: 'Import throttle config?',
        fr: 'Importer la configuration de limitation ?',
        de: 'Drosselungskonfiguration importieren?',
        ja: 'スロットリング設定をインポートしますか？',
      ),
      cancelLabel: AppLocalizations.of(context)!.commonCancel,
      confirmLabel: openHandLocalizedText(
        context,
        zh: '导入 ${diffs.length} 项',
        zhHant: '匯入 ${diffs.length} 項',
        en: 'Import ${diffs.length}',
        fr: 'Importer ${diffs.length}',
        de: '${diffs.length} importieren',
        ja: '${diffs.length} 件をインポート',
      ),
    );
    if (!confirmed) return;
    if (!context.mounted) return;
    try {
      final outcome = await controller.importAiStreamThrottleConfig(nextDoc);
      if (!context.mounted) return;
      flashOpenHandSnack(
        context,
        switch (outcome) {
          AiStreamThrottleConfigImportOutcome.applied => openHandLocalizedText(
            context,
            zh: '节流配置已导入并应用。',
            zhHant: '節流設定已匯入並套用。',
            en: 'Throttle config imported.',
            fr: 'Configuration de limitation importée.',
            de: 'Drosselungskonfiguration importiert.',
            ja: 'スロットリング設定をインポートして適用しました。',
          ),
          AiStreamThrottleConfigImportOutcome.unchanged =>
            _settingsViewNoChangesDetectedLabel(context),
          AiStreamThrottleConfigImportOutcome.failed => openHandLocalizedText(
            context,
            zh: '导入失败，配置未能保存。',
            zhHant: '匯入失敗，設定未能儲存。',
            en: 'Import failed. The settings could not be saved.',
            fr: 'Échec de l’importation. Les réglages n’ont pas été enregistrés.',
            de: 'Import fehlgeschlagen. Die Einstellungen konnten nicht gespeichert werden.',
            ja: 'インポートに失敗しました。設定を保存できませんでした。',
          ),
        },
        kind: outcome == AiStreamThrottleConfigImportOutcome.failed
            ? OpenHandSnackKind.error
            : OpenHandSnackKind.success,
      );
    } catch (error, stack) {
      silentLog('settings', '应用节流配置', error, stack);
      if (!context.mounted) return;
      final detail = userFailureMessage(error, fallback: '无法应用节流配置。');
      flashOpenHandSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '应用失败：$detail',
          zhHant: '套用失敗：$detail',
          en: 'Apply failed: $detail',
          fr: 'Échec de l’application : $detail',
          de: 'Anwenden fehlgeschlagen: $detail',
          ja: '適用に失敗しました: $detail',
        ),
        kind: OpenHandSnackKind.error,
      );
    }
  }

  Future<void> _saveCompressionThreshold(
    BuildContext context,
    String rawValue,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final parsedValue = optionalPositiveIntFromText(rawValue);
    if (parsedValue == null) {
      flashOpenHandSnack(
        context,
        l10n.aiCompressionThresholdInvalid,
        kind: OpenHandSnackKind.error,
      );
      return;
    }
    final saved = await context
        .read<SettingsController>()
        .updateAiMessageCompressionThresholdChars(parsedValue);
    if (!context.mounted) {
      return;
    }
    if (!saved) {
      _compressionThresholdController.text =
          '${context.read<SettingsController>().aiMessageCompressionThresholdChars}';
      _showPersistenceFailureSnackBar(context);
      return;
    }
    _compressionThresholdController.text =
        '${context.read<SettingsController>().aiMessageCompressionThresholdChars}';
    flashOpenHandSnack(
      context,
      l10n.aiCompressionThresholdSaved,
      kind: OpenHandSnackKind.success,
    );
  }

  Future<void> _saveToolResultCompressionThreshold(
    BuildContext context,
    String rawValue,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final parsedValue = optionalPositiveIntFromText(rawValue);
    if (parsedValue == null) {
      flashOpenHandSnack(
        context,
        l10n.aiToolResultCompressionThresholdInvalid,
        kind: OpenHandSnackKind.error,
      );
      return;
    }
    final saved = await context
        .read<SettingsController>()
        .updateAiToolResultCompressionThresholdChars(parsedValue);
    if (!context.mounted) {
      return;
    }
    if (!saved) {
      _toolResultCompressionThresholdController.text =
          '${context.read<SettingsController>().aiToolResultCompressionThresholdChars}';
      _showPersistenceFailureSnackBar(context);
      return;
    }
    _toolResultCompressionThresholdController.text =
        '${context.read<SettingsController>().aiToolResultCompressionThresholdChars}';
    flashOpenHandSnack(
      context,
      l10n.aiToolResultCompressionThresholdSaved,
      kind: OpenHandSnackKind.success,
    );
  }

  Future<void> _saveToolResultCompressionHeadTailWindow(
    BuildContext context,
    String rawValue,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    await _saveBoundedIntegerSetting(
      context: context,
      rawValue: rawValue,
      min: 0,
      max: _kSettingsToolResultCompressionWindowMaxChars,
      fieldController: _toolResultCompressionHeadTailWindowController,
      currentValue: (controller) =>
          controller.aiToolResultCompressionHeadTailWindowChars,
      saveValue: (controller, value) =>
          controller.updateAiToolResultCompressionHeadTailWindowChars(value),
      invalidMessage: l10n.aiToolResultCompressionHeadTailWindowInvalid,
      successMessage: l10n.aiToolResultCompressionHeadTailWindowSaved,
      successKind: OpenHandSnackKind.success,
    );
  }

  Future<void> _saveToolResultCompressionMaxPathHits(
    BuildContext context,
    String rawValue,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    await _saveBoundedIntegerSetting(
      context: context,
      rawValue: rawValue,
      min: 0,
      max: _kSettingsToolResultCompressionMaxPathHits,
      fieldController: _toolResultCompressionMaxPathHitsController,
      currentValue: (controller) =>
          controller.aiToolResultCompressionMaxPathHits,
      saveValue: (controller, value) =>
          controller.updateAiToolResultCompressionMaxPathHits(value),
      invalidMessage: l10n.aiToolResultCompressionMaxPathHitsInvalid,
      invalidKind: OpenHandSnackKind.error,
      successMessage: l10n.aiToolResultCompressionMaxPathHitsSaved,
      successKind: OpenHandSnackKind.success,
    );
  }

  Future<void> _saveAiInputCacheUpdateInterval(
    BuildContext context,
    String rawValue,
  ) async {
    await _saveBoundedIntegerSetting(
      context: context,
      rawValue: rawValue,
      min: AppSettingsSnapshot.minAiInputCacheUpdateInterval,
      max: AppSettingsSnapshot.maxAiInputCacheUpdateInterval,
      fieldController: _aiInputCacheUpdateIntervalController,
      currentValue: (controller) => controller.aiInputCacheUpdateInterval,
      saveValue: (controller, value) =>
          controller.updateAiInputCacheUpdateInterval(value),
      invalidMessage: AppLocalizations.of(context)!
          .settingsPleaseEnterAnIntegerBetweenAppsettingssn(
            AppSettingsSnapshot.minAiInputCacheUpdateInterval,
            AppSettingsSnapshot.maxAiInputCacheUpdateInterval,
          ),
      successMessage: AppLocalizations.of(
        context,
      )!.settingsCacheBreakpointUpdateIntervalSaved,
    );
  }

  Future<void> _saveAiInputCacheBreakpointCount(
    BuildContext context,
    String rawValue,
  ) async {
    await _saveBoundedIntegerSetting(
      context: context,
      rawValue: rawValue,
      min: AppSettingsSnapshot.minAiInputCacheBreakpointCount,
      max: AppSettingsSnapshot.maxAiInputCacheBreakpointCount,
      fieldController: _aiInputCacheBreakpointCountController,
      currentValue: (controller) => controller.aiInputCacheBreakpointCount,
      saveValue: (controller, value) =>
          controller.updateAiInputCacheBreakpointCount(value),
      invalidMessage: AppLocalizations.of(context)!
          .settingsPleaseEnterAnIntegerBetweenAppsettingssn2(
            AppSettingsSnapshot.minAiInputCacheBreakpointCount,
            AppSettingsSnapshot.maxAiInputCacheBreakpointCount,
          ),
      successMessage: AppLocalizations.of(
        context,
      )!.settingsCacheBreakpointCountSaved,
    );
  }

  // 单会话预算输入：去掉小数尾零，0 显示为 "0"。
  static String _formatBudgetUsd(double value) {
    if (value <= 0) return '0';
    final fixed = value.toStringAsFixed(2);
    if (fixed.endsWith('.00')) return fixed.substring(0, fixed.length - 3);
    if (fixed.endsWith('0')) return fixed.substring(0, fixed.length - 1);
    return fixed;
  }

  Future<void> _saveAiBudgetUsdPerSession(
    BuildContext context,
    String rawValue,
  ) async {
    final trimmed = rawValue.trim();
    final parsed = trimmed.isEmpty ? 0.0 : optionalDoubleFromText(trimmed);
    if (parsed == null ||
        parsed < AppSettingsSnapshot.minAiBudgetUsdPerSession ||
        parsed > AppSettingsSnapshot.maxAiBudgetUsdPerSession) {
      flashOpenHandSnack(
        context,
        AppLocalizations.of(context)!.settingsAiBudgetUsdPerSessionInvalid,
      );
      return;
    }
    final saved = await context
        .read<SettingsController>()
        .updateAiBudgetUsdPerSession(parsed);
    if (!context.mounted) return;
    final current = context.read<SettingsController>().aiBudgetUsdPerSession;
    _aiBudgetUsdPerSessionController.text = _formatBudgetUsd(current);
    if (!saved) {
      _showPersistenceFailureSnackBar(context);
      return;
    }
    flashOpenHandSnack(
      context,
      AppLocalizations.of(context)!.settingsAiBudgetUsdPerSessionSaved,
    );
  }

  /// 历史候选点滑块行：N-1 个可拖拽拇指 + 当前消息尾部固定锚。
  /// 拖拽实时更新本地草稿，松手时通过 SettingsController 持久化。
  Widget _buildAiInputCacheBreakpointPositionsRow(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final count = controller.aiInputCacheBreakpointCount;
    final thumbCount = (count - 1).clamp(0, 3);
    // 没有可拖拽候选点时（count=1），整行收起，避免空白控件。
    if (thumbCount == 0) {
      return const SizedBox.shrink();
    }
    final raw = controller.aiInputCacheBreakpointPositions;
    // 缺省为均匀候选位置，例如 count=4 → [0.25, 0.5, 0.75]。
    final List<double> values = (raw.length == thumbCount)
        ? List<double>.from(raw)
        : List<double>.generate(thumbCount, (i) => (i + 1) / count);
    final liveKey = ValueKey<int>(thumbCount);
    return _ResponsiveSettingRow(
      title: AppLocalizations.of(context)!.settingsCacheBreakpointPositions,
      subtitle: AppLocalizations.of(
        context,
      )!.settingsDragTheThumbcountThumbsToPosition(thumbCount),
      control: PromptCacheBreakpointBar(
        key: liveKey,
        initialValues: List<double>.unmodifiable(values),
        thumbCount: thumbCount,
        onCommit: (positions) =>
            _saveAiInputCacheBreakpointPositions(context, positions),
        onReset: () =>
            _saveAiInputCacheBreakpointPositions(context, const <double>[]),
      ),
      controlMaxWidth: 460,
    );
  }

  Future<void> _saveAiInputCacheBreakpointPositions(
    BuildContext context,
    List<double> positions,
  ) async {
    final saved = await context
        .read<SettingsController>()
        .updateAiInputCacheBreakpointPositions(positions);
    if (!context.mounted) return;
    if (!saved) {
      _showPersistenceFailureSnackBar(context);
      return;
    }
    flashOpenHandSnack(
      context,
      AppLocalizations.of(context)!.settingsCacheBreakpointPositionsSaved,
    );
  }

  Future<void> _saveWriteToolSummaryMaxChars(
    BuildContext context,
    String rawValue,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    await _saveBoundedIntegerSetting(
      context: context,
      rawValue: rawValue,
      min: 0,
      max: _kSettingsWriteToolSummaryMaxChars,
      fieldController: _writeToolSummaryMaxCharsController,
      currentValue: (controller) => controller.aiWriteToolSummaryMaxChars,
      saveValue: (controller, value) =>
          controller.updateAiWriteToolSummaryMaxChars(value),
      invalidMessage: l10n.aiWriteToolSummaryMaxCharsInvalid,
      invalidKind: OpenHandSnackKind.error,
      successMessage: l10n.aiWriteToolSummaryMaxCharsSaved,
      successKind: OpenHandSnackKind.success,
    );
  }

  Future<void> _saveToolCallLimit(BuildContext context, String rawValue) async {
    final parsedValue = optionalPositiveIntFromText(rawValue);
    if (parsedValue == null) {
      flashOpenHandSnack(
        context,
        AppLocalizations.of(context)!.settingsEnterAToolCallLimitGreater,
      );
      return;
    }
    final saved = await context
        .read<SettingsController>()
        .updateAiSingleRoundToolCallLimit(parsedValue);
    if (!context.mounted) {
      return;
    }
    final settingsController = context.read<SettingsController>();
    if (!saved) {
      _toolCallLimitController.text =
          '${settingsController.aiSingleRoundToolCallLimit}';
      _showPersistenceFailureSnackBar(context);
      return;
    }
    _toolCallLimitController.text =
        '${settingsController.aiSingleRoundToolCallLimit}';
    flashOpenHandSnack(
      context,
      AppLocalizations.of(context)!.settingsThePerResponseToolCallLimit,
    );
  }

  Future<void> _saveSequentialToolRoundLimit(
    BuildContext context,
    String rawValue,
  ) async {
    final parsedValue = optionalPositiveIntFromText(rawValue);
    if (parsedValue == null) {
      flashOpenHandSnack(
        context,
        AppLocalizations.of(context)!.settingsEnterASequentialToolRoundLimit,
      );
      return;
    }
    final saved = await context
        .read<SettingsController>()
        .updateAiSequentialToolRoundLimit(parsedValue);
    if (!context.mounted) {
      return;
    }
    final settingsController = context.read<SettingsController>();
    if (!saved) {
      _sequentialToolRoundLimitController.text =
          '${settingsController.aiSequentialToolRoundLimit}';
      _showPersistenceFailureSnackBar(context);
      return;
    }
    _sequentialToolRoundLimitController.text =
        '${settingsController.aiSequentialToolRoundLimit}';
    flashOpenHandSnack(
      context,
      AppLocalizations.of(context)!.settingsTheSequentialToolRoundLimitHas,
    );
  }

  Future<void> _saveMaxRecentErrors(
    BuildContext context,
    String rawValue,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    await _saveBoundedIntegerSetting(
      context: context,
      rawValue: rawValue,
      min: AppSettingsSnapshot.minAiMaxRecentErrors,
      max: AppSettingsSnapshot.maxAiMaxRecentErrors,
      fieldController: _maxRecentErrorsController,
      currentValue: (controller) => controller.aiMaxRecentErrors,
      saveValue: (controller, value) =>
          controller.updateAiMaxRecentErrors(value),
      invalidMessage: l10n.aiMaxRecentErrorsInvalid,
      invalidKind: OpenHandSnackKind.error,
      successMessage: l10n.aiMaxRecentErrorsSaved,
      successKind: OpenHandSnackKind.success,
    );
  }

  Future<void> _saveMcpLazyLoadingThreshold(
    BuildContext context,
    String rawValue,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    await _saveBoundedIntegerSetting(
      context: context,
      rawValue: rawValue,
      min: AppSettingsSnapshot.minMcpLazyLoadingThresholdTokens,
      max: AppSettingsSnapshot.maxMcpLazyLoadingThresholdTokens,
      fieldController: _mcpLazyLoadingThresholdController,
      currentValue: (controller) => controller.mcpLazyLoadingThresholdTokens,
      saveValue: (controller, value) =>
          controller.updateMcpLazyLoadingThresholdTokens(value),
      invalidMessage: l10n.mcpLazyLoadingThresholdInvalid,
      invalidKind: OpenHandSnackKind.error,
      successMessage: l10n.mcpLazyLoadingThresholdSaved,
      successKind: OpenHandSnackKind.success,
    );
  }

  Future<void> _saveMcpAutoProbeConcurrency(
    BuildContext context,
    String rawValue,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    await _saveBoundedIntegerSetting(
      context: context,
      rawValue: rawValue,
      min: AppSettingsSnapshot.minMcpAutoProbeConcurrency,
      max: AppSettingsSnapshot.maxMcpAutoProbeConcurrency,
      fieldController: _mcpAutoProbeConcurrencyController,
      currentValue: (controller) => controller.mcpAutoProbeConcurrency,
      saveValue: (controller, value) =>
          controller.updateMcpAutoProbeConcurrency(value),
      invalidMessage: l10n.mcpAutoProbeConcurrencyInvalid,
      invalidKind: OpenHandSnackKind.error,
      successMessage: l10n.mcpAutoProbeConcurrencySaved,
      successKind: OpenHandSnackKind.success,
    );
  }

  Future<void> _saveMaxPlanHistoryEntries(
    BuildContext context,
    String rawValue,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    await _saveBoundedIntegerSetting(
      context: context,
      rawValue: rawValue,
      min: AppSettingsSnapshot.minAiMaxPlanHistoryEntries,
      max: AppSettingsSnapshot.maxAiMaxPlanHistoryEntries,
      fieldController: _maxPlanHistoryEntriesController,
      currentValue: (controller) => controller.aiMaxPlanHistoryEntries,
      saveValue: (controller, value) =>
          controller.updateAiMaxPlanHistoryEntries(value),
      invalidMessage: l10n.aiMaxPlanHistoryEntriesInvalid,
      invalidKind: OpenHandSnackKind.error,
      successMessage: l10n.aiMaxPlanHistoryEntriesSaved,
      successKind: OpenHandSnackKind.success,
    );
  }

  Future<void> _saveMaxTruncationContinuations(
    BuildContext context,
    String rawValue,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    await _saveBoundedIntegerSetting(
      context: context,
      rawValue: rawValue,
      min: AppSettingsSnapshot.minAiMaxTruncationContinuations,
      max: AppSettingsSnapshot.maxAiMaxTruncationContinuations,
      fieldController: _maxTruncationContinuationsController,
      currentValue: (controller) => controller.aiMaxTruncationContinuations,
      saveValue: (controller, value) =>
          controller.updateAiMaxTruncationContinuations(value),
      invalidMessage: l10n.aiMaxTruncationContinuationsInvalid,
      invalidKind: OpenHandSnackKind.error,
      successMessage: l10n.aiMaxTruncationContinuationsSaved,
      successKind: OpenHandSnackKind.success,
    );
  }

  Future<void> _saveEstimatedCharactersPerToken(
    BuildContext context,
    String rawValue,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    await _saveBoundedIntegerSetting(
      context: context,
      rawValue: rawValue,
      min: AppSettingsSnapshot.minAiEstimatedCharactersPerToken,
      max: AppSettingsSnapshot.maxAiEstimatedCharactersPerToken,
      fieldController: _estimatedCharactersPerTokenController,
      currentValue: (controller) => controller.aiEstimatedCharactersPerToken,
      saveValue: (controller, value) =>
          controller.updateAiEstimatedCharactersPerToken(value),
      invalidMessage: l10n.aiEstimatedCharactersPerTokenInvalid,
      invalidKind: OpenHandSnackKind.error,
      successMessage: l10n.aiEstimatedCharactersPerTokenSaved,
      successKind: OpenHandSnackKind.success,
    );
  }

  Future<void> _saveImageSizeLimit(
    BuildContext context,
    String rawValue,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final parsedValue = optionalDoubleFromText(rawValue);
    if (parsedValue == null || parsedValue <= 0) {
      flashOpenHandSnack(
        context,
        l10n.aiImageSizeLimitInvalid,
        kind: OpenHandSnackKind.error,
      );
      return;
    }
    final bytes = megabytesTextToBytes(
      rawValue,
      fallbackBytes: AppSettingsSnapshot.defaultAiImageSizeLimitBytes,
      minBytes: AppSettingsSnapshot.minAiImageSizeLimitBytes,
      maxBytes: AppSettingsSnapshot.maxAiImageSizeLimitBytes,
    );
    final saved = await context
        .read<SettingsController>()
        .updateAiImageSizeLimitBytes(bytes);
    if (!context.mounted) {
      return;
    }
    if (!saved) {
      _imageSizeLimitController.text = formatMegabytesInput(
        context.read<SettingsController>().aiImageSizeLimitBytes,
      );
      _showPersistenceFailureSnackBar(context);
      return;
    }
    final effectiveBytes = context
        .read<SettingsController>()
        .aiImageSizeLimitBytes;
    _imageSizeLimitController.text = formatMegabytesInput(effectiveBytes);
    flashOpenHandSnack(
      context,
      l10n.aiImageSizeLimitSaved,
      kind: OpenHandSnackKind.success,
    );
  }

  Future<void> _showDenyCommandRuleDialog(
    BuildContext context, {
    AiDenyCommandRule? initialRule,
  }) async {
    final settingsController = context.read<SettingsController>();
    final submittedRule = await showAnimatedDialog<AiDenyCommandRule>(
      context: context,
      builder: (dialogContext) {
        return _DenyCommandRuleDialog(
          initialRule: initialRule,
          draftRuleId:
              initialRule?.id ?? settingsController.createAiDenyCommandRuleId(),
        );
      },
    );
    if (!context.mounted || submittedRule == null) {
      return;
    }
    await Future<void>.delayed(Duration.zero);
    if (!context.mounted) {
      return;
    }
    final saved = initialRule == null
        ? await settingsController.addAiDenyCommandRule(submittedRule)
        : await settingsController.updateAiDenyCommandRule(submittedRule);
    if (!context.mounted) {
      return;
    }
    if (!saved) {
      _showPersistenceFailureSnackBar(context);
      return;
    }
    flashOpenHandSnack(
      context,
      (initialRule == null
          ? AppLocalizations.of(context)!.settingsTheDenyCommandRuleHasBeen
          : AppLocalizations.of(context)!.settingsTheDenyCommandRuleHasBeen2),
    );
  }

  Future<void> _deleteDenyCommandRule(
    BuildContext context,
    AiDenyCommandRule rule,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: l10n.settingsDeleteDenyRule,
      message: rule.pattern,
      cancelLabel: l10n.commonCancel,
      confirmLabel: l10n.commonDelete,
      destructive: true,
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    final deleted = await context
        .read<SettingsController>()
        .deleteAiDenyCommandRule(rule.id);
    if (!context.mounted) {
      return;
    }
    if (!deleted) {
      _showPersistenceFailureSnackBar(context);
      return;
    }
    flashOpenHandSnack(
      context,
      AppLocalizations.of(context)!.settingsTheDenyCommandRuleHasBeen,
    );
  }

  Future<void> _showAllowCommandRuleDialog(
    BuildContext context, {
    AiAllowCommandRule? initialRule,
  }) async {
    final settingsController = context.read<SettingsController>();
    final submittedRule = await showAnimatedDialog<AiAllowCommandRule>(
      context: context,
      builder: (dialogContext) {
        return _AllowCommandRuleDialog(
          initialRule: initialRule,
          draftRuleId:
              initialRule?.id ??
              settingsController.createAiAllowCommandRuleId(),
        );
      },
    );
    if (!context.mounted || submittedRule == null) {
      return;
    }
    await Future<void>.delayed(Duration.zero);
    if (!context.mounted) {
      return;
    }
    final saved = initialRule == null
        ? await settingsController.addAiAllowCommandRule(submittedRule)
        : await settingsController.updateAiAllowCommandRule(submittedRule);
    if (!context.mounted) {
      return;
    }
    if (!saved) {
      _showPersistenceFailureSnackBar(context);
      return;
    }
    flashOpenHandSnack(
      context,
      (initialRule == null
          ? AppLocalizations.of(context)!.settingsTheAllowCommandRuleHasBeen
          : AppLocalizations.of(context)!.settingsTheAllowCommandRuleHasBeen2),
    );
  }

  Future<void> _deleteAllowCommandRule(
    BuildContext context,
    AiAllowCommandRule rule,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: l10n.settingsDeleteAllowRule,
      message: rule.pattern,
      cancelLabel: l10n.commonCancel,
      confirmLabel: l10n.commonDelete,
      destructive: true,
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    final deleted = await context
        .read<SettingsController>()
        .deleteAiAllowCommandRule(rule.id);
    if (!context.mounted) {
      return;
    }
    if (!deleted) {
      _showPersistenceFailureSnackBar(context);
      return;
    }
    flashOpenHandSnack(
      context,
      AppLocalizations.of(context)!.settingsTheAllowCommandRuleHasBeen,
    );
  }

  Future<void> _openMcpDirectory(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await context.read<McpController>().openStorageDirectory();
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      flashOpenHandSnack(
        context,
        l10n.mcpOperationFailed,
        kind: OpenHandSnackKind.error,
      );
    }
  }

  /// 设置页快捷入口：弹出当前活跃会话已通过 ToolSearch 加载的 MCP 工具列表。
  /// 无活跃会话时仅 toast 提示，不弹 dialog（避免与空列表占位混淆）。
  void _openCurrentSessionLoadedToolsDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final aiCtrl = context.read<AiSessionController>();
    final sessionId = aiCtrl.currentSessionId;
    if (sessionId == null) {
      flashOpenHandSnack(context, l10n.mcpLazyLoadingNoActiveSession);
      return;
    }
    final names = aiCtrl.loadedMcpToolNamesForSession(sessionId);
    final history = aiCtrl.loadedMcpToolHistoryForSession(sessionId);
    showToolSearchLoadedDialog(
      context,
      names: names,
      history: history,
      onClear: () => aiCtrl.clearLoadedMcpToolsForSession(sessionId),
    );
  }

  /// 清除 ToolSearch 历史导出对话框记忆的「上次落地目录」，让下次导出回到
  /// 系统默认位置（macOS Documents / Windows %USERPROFILE% 等）。
  Future<void> _resetToolSearchExportLastDir(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    await ToolSearchHistoryExportPrefs.clear();
    if (!context.mounted) return;
    flashOpenHandSnack(context, l10n.mcpToolSearchExportLastDirResetToast);
  }

  /// stdio 镜像设置变更后的一键重连：刷新全部 MCP 服务，让子进程携带新
  /// env（含 mirror override）重新拉起。
  Future<void> _reconnectMcpServersForMirrorChange(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final mcp = context.read<McpController>();
    // refresh() 会重新加载 servers 并对每个 enabled server 触发 force=true 的
    // 工具重拉，这会用新的 env（含 mirror override）重新 spawn 子进程，
    // 刚好覆盖「立刻按新设置重启」的诉求。
    unawaited(mcp.refresh());
    flashOpenHandSnack(
      context,
      l10n.mcpStdioMirrorModeReconnectDone,
      kind: OpenHandSnackKind.success,
    );
  }

  /// 一键重置 stdio MCP 隔离包缓存（~/.openhand/mcp/package-cache）。
  /// 弹确认对话框 → 删整个目录 → toast 反馈。失败时落 silentLog 并提示用户手删。
  Future<void> _resetStdioPackageCache(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: l10n.mcpStdioCacheResetConfirmTitle,
      message: l10n.mcpStdioCacheResetConfirmBody,
      cancelLabel: l10n.mcpStdioCacheResetCancel,
      confirmLabel: l10n.mcpStdioCacheResetConfirm,
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await resetMcpStdioIsolatedCache();
      if (!context.mounted) return;
      flashOpenHandSnack(
        context,
        l10n.mcpStdioCacheResetDone,
        kind: OpenHandSnackKind.success,
      );
    } catch (error, stack) {
      silentLog('settings', '重置标准输入输出软件包缓存', error, stack);
      if (!context.mounted) return;
      flashOpenHandSnack(
        context,
        l10n.mcpStdioCacheResetFailed,
        kind: OpenHandSnackKind.error,
      );
    }
  }

  /// 重发上次在反悔窗口中取消的 ToolSearch 操作。
  Future<void> _replayLastCancelledToolSearch(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final dispatcher = context.read<ToolSearchReplayDispatcher>();
    final fired = await dispatcher.replayLastCancelled();
    if (!context.mounted) return;
    flashOpenHandSnack(
      context,
      fired
          ? l10n.mcpToolSearchReplayLastCancelToastFired
          : l10n.mcpToolSearchReplayLastCancelToastEmpty,
    );
  }

  Future<void> _showAiModelDialog(
    BuildContext context, {
    AiModelConfig? initialModel,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final submitted = await showAnimatedDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return _AiModelEditorDialog(initialModel: initialModel);
      },
    );

    if (!context.mounted || submitted != true) {
      return;
    }
    flashOpenHandSnack(
      context,
      l10n.aiModelSaveSuccess,
      kind: OpenHandSnackKind.success,
    );
  }

  Future<void> _syncOpenRouterModels() async {
    if (_isSyncingOpenRouterModels) return;
    setState(() => _isSyncingOpenRouterModels = true);
    try {
      final result = await showOpenRouterModelSyncDialog(context);
      if (!mounted || result == null) return;
      flashOpenHandSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '已同步 ${result.upserted} 个模型参数，跳过 ${result.skipped} 个，失败 ${result.failed} 个。',
          zhHant:
              '已同步 ${result.upserted} 個模型參數，跳過 ${result.skipped} 個，失敗 ${result.failed} 個。',
          en: 'Synced ${result.upserted} model profiles; skipped ${result.skipped}, failed ${result.failed}.',
          fr: '${result.upserted} profils synchronisés ; ${result.skipped} ignorés, ${result.failed} échecs.',
          de: '${result.upserted} Modellprofile synchronisiert; ${result.skipped} übersprungen, ${result.failed} fehlgeschlagen.',
          ja: '${result.upserted} 件のモデル設定を同期しました。スキップ ${result.skipped} 件、失敗 ${result.failed} 件。',
        ),
        kind: OpenHandSnackKind.success,
      );
    } finally {
      if (mounted) setState(() => _isSyncingOpenRouterModels = false);
    }
  }

  Future<void> _testAiModel(AiModelConfig model) async {
    if (_testingAiModelIds.contains(model.id)) {
      return;
    }
    setState(() {
      _testingAiModelIds.add(model.id);
    });
    try {
      await testAiModelConfiguration(context, model);
    } finally {
      if (mounted) {
        setState(() {
          _testingAiModelIds.remove(model.id);
        });
      }
    }
  }

  Future<void> _confirmDeleteAiModel(
    BuildContext context,
    AiModelConfig model,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: l10n.aiModelDeleteConfirmTitle,
      message: '${l10n.aiModelDeleteConfirmBody}\n\n${model.providerLabel}',
      cancelLabel: l10n.commonCancel,
      confirmLabel: l10n.commonDelete,
      destructive: true,
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    await _deleteAiModelWithAnimation(model);
  }

  void _showPersistenceFailureSnackBar(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    flashOpenHandSnack(
      context,
      l10n.settingsPersistenceSaveFailedBody,
      kind: OpenHandSnackKind.error,
    );
  }

  Future<void> _showShortcutRecorderDialog(
    BuildContext context,
    OpenHandShortcutAction action,
  ) async {
    final settingsController = context.read<SettingsController>();
    final shortcutBinding = await showAnimatedDialog<List<int>>(
      context: context,
      builder: (dialogContext) {
        return _ShortcutRecorderDialog(
          title: _shortcutActionTitle(dialogContext, action),
          initialKeyIds:
              settingsController.shortcutBindings[action] ?? const <int>[],
        );
      },
    );
    if (!context.mounted || shortcutBinding == null) {
      return;
    }
    final saved = await settingsController.updateShortcutBinding(
      action,
      shortcutBinding,
    );
    if (!context.mounted) {
      return;
    }
    if (!saved) {
      _showPersistenceFailureSnackBar(context);
      return;
    }
    flashOpenHandSnack(
      context,
      AppLocalizations.of(context)!.settingsTheShortcutHasBeenUpdated,
    );
  }

  Future<void> _showEditorShortcutRecorderDialog(
    BuildContext context,
    EditorShortcutAction action,
  ) async {
    final settingsController = context.read<SettingsController>();
    final shortcutBinding = await showAnimatedDialog<List<int>>(
      context: context,
      builder: (dialogContext) {
        return _ShortcutRecorderDialog(
          title: _editorShortcutActionTitle(dialogContext, action),
          initialKeyIds:
              settingsController.editorShortcutBindings[action] ??
              const <int>[],
        );
      },
    );
    if (!context.mounted || shortcutBinding == null) {
      return;
    }
    final saved = await settingsController.updateEditorShortcutBinding(
      action,
      shortcutBinding,
    );
    if (!context.mounted) {
      return;
    }
    if (!saved) {
      _showPersistenceFailureSnackBar(context);
      return;
    }
    flashOpenHandSnack(
      context,
      AppLocalizations.of(context)!.settingsTheEditorShortcutHasBeenUpdated,
    );
  }

  String _shortcutActionTitle(
    BuildContext context,
    OpenHandShortcutAction action,
  ) {
    return switch (action) {
      OpenHandShortcutAction.sendMessage => AppLocalizations.of(
        context,
      )!.settingsSendMessage,
      OpenHandShortcutAction.toggleComposer => AppLocalizations.of(
        context,
      )!.settingsCollapseOrExpandComposer,
      OpenHandShortcutAction.selectPreviousModel => AppLocalizations.of(
        context,
      )!.settingsPreviousModel,
      OpenHandShortcutAction.selectNextModel => AppLocalizations.of(
        context,
      )!.settingsNextModel,
      OpenHandShortcutAction.toggleAutoFollow => AppLocalizations.of(
        context,
      )!.settingsToggleAutoFollow,
      OpenHandShortcutAction.selectPreviousSession => AppLocalizations.of(
        context,
      )!.settingsPreviousSession,
      OpenHandShortcutAction.selectNextSession => AppLocalizations.of(
        context,
      )!.settingsNextSession,
      OpenHandShortcutAction.undoLastFileMutation => AppLocalizations.of(
        context,
      )!.settingsUndoLastFileMutation,
    };
  }

  String _editorShortcutActionTitle(
    BuildContext context,
    EditorShortcutAction action,
  ) {
    return switch (action) {
      EditorShortcutAction.saveFile => AppLocalizations.of(
        context,
      )!.settingsSaveFile,
      EditorShortcutAction.triggerCompletion => AppLocalizations.of(
        context,
      )!.settingsTriggerCompletion,
      EditorShortcutAction.showSignatureHelp => AppLocalizations.of(
        context,
      )!.settingsShowSignatureHelp,
      EditorShortcutAction.find => AppLocalizations.of(context)!.settingsFind,
      EditorShortcutAction.replace => AppLocalizations.of(
        context,
      )!.settingsFindAndReplace,
      EditorShortcutAction.goToLine => AppLocalizations.of(
        context,
      )!.settingsGoToLine,
      EditorShortcutAction.showDocumentSymbols => AppLocalizations.of(
        context,
      )!.settingsDocumentSymbols,
      EditorShortcutAction.showWorkspaceSymbols => AppLocalizations.of(
        context,
      )!.settingsWorkspaceSymbols,
      EditorShortcutAction.goToDefinition => AppLocalizations.of(
        context,
      )!.settingsGoToDefinition,
      EditorShortcutAction.findReferences => AppLocalizations.of(
        context,
      )!.settingsFindReferences,
      EditorShortcutAction.goToImplementation => AppLocalizations.of(
        context,
      )!.settingsGoToImplementation,
      EditorShortcutAction.showHoverInfo => AppLocalizations.of(
        context,
      )!.settingsShowHoverInfo,
      EditorShortcutAction.renameSymbol => AppLocalizations.of(
        context,
      )!.settingsRenameSymbol,
      EditorShortcutAction.showCodeActions => AppLocalizations.of(
        context,
      )!.settingsCodeActions,
      EditorShortcutAction.formatDocument => AppLocalizations.of(
        context,
      )!.settingsFormatDocument,
    };
  }

  String _shortcutActionSubtitle(
    BuildContext context,
    OpenHandShortcutAction action,
  ) {
    return switch (action) {
      OpenHandShortcutAction.sendMessage => AppLocalizations.of(
        context,
      )!.settingsDefaultsToCtrlEnterAndTriggers,
      OpenHandShortcutAction.toggleComposer => AppLocalizations.of(
        context,
      )!.settingsDefaultsToCtrlPForQuickly,
      OpenHandShortcutAction.selectPreviousModel => AppLocalizations.of(
        context,
      )!.settingsDefaultsToCtrlLeftAndWraps,
      OpenHandShortcutAction.selectNextModel => AppLocalizations.of(
        context,
      )!.settingsDefaultsToCtrlRightAndWraps,
      OpenHandShortcutAction.toggleAutoFollow => AppLocalizations.of(
        context,
      )!.settingsDefaultsToCtrlSForToggling,
      OpenHandShortcutAction.selectPreviousSession => AppLocalizations.of(
        context,
      )!.settingsDefaultsToCtrlUpAndWraps,
      OpenHandShortcutAction.selectNextSession => AppLocalizations.of(
        context,
      )!.settingsDefaultsToCtrlDownAndWraps,
      OpenHandShortcutAction.undoLastFileMutation => AppLocalizations.of(
        context,
      )!.settingsDefaultsToCtrlShiftZForUndo,
    };
  }

  String _editorShortcutActionSubtitle(
    BuildContext context,
    EditorShortcutAction action,
  ) {
    final defaultLabel = formatShortcutLabel(
      defaultEditorShortcutBindings()[action] ?? const <int>[],
    );
    return switch (action) {
      EditorShortcutAction.saveFile => AppLocalizations.of(
        context,
      )!.settingsDefaultsToDefaultlabelAndSavesThe(defaultLabel),
      EditorShortcutAction.triggerCompletion => AppLocalizations.of(
        context,
      )!.settingsDefaultsToDefaultlabelAndOpensThe(defaultLabel),
      EditorShortcutAction.showSignatureHelp => AppLocalizations.of(
        context,
      )!.settingsDefaultsToDefaultlabelAndShowsMethod(defaultLabel),
      EditorShortcutAction.find => AppLocalizations.of(
        context,
      )!.settingsDefaultsToDefaultlabelAndTogglesThe(defaultLabel),
      EditorShortcutAction.replace => AppLocalizations.of(
        context,
      )!.settingsDefaultsToDefaultlabelAndTogglesThe2(defaultLabel),
      EditorShortcutAction.goToLine => AppLocalizations.of(
        context,
      )!.settingsDefaultsToDefaultlabelAndTogglesThe3(defaultLabel),
      EditorShortcutAction.showDocumentSymbols => AppLocalizations.of(
        context,
      )!.settingsDefaultsToDefaultlabelAndTogglesThe4(defaultLabel),
      EditorShortcutAction.showWorkspaceSymbols => AppLocalizations.of(
        context,
      )!.settingsDefaultsToDefaultlabelAndTogglesThe5(defaultLabel),
      EditorShortcutAction.goToDefinition => AppLocalizations.of(
        context,
      )!.settingsDefaultsToDefaultlabelAndJumpsTo(defaultLabel),
      EditorShortcutAction.findReferences => AppLocalizations.of(
        context,
      )!.settingsDefaultsToDefaultlabelAndFindsReferences(defaultLabel),
      EditorShortcutAction.goToImplementation => AppLocalizations.of(
        context,
      )!.settingsDefaultsToDefaultlabelAndJumpsTo2(defaultLabel),
      EditorShortcutAction.showHoverInfo => AppLocalizations.of(
        context,
      )!.settingsDefaultsToDefaultlabelAndShowsType(defaultLabel),
      EditorShortcutAction.renameSymbol => AppLocalizations.of(
        context,
      )!.settingsDefaultsToDefaultlabelAndStartsRename(defaultLabel),
      EditorShortcutAction.showCodeActions => AppLocalizations.of(
        context,
      )!.settingsDefaultsToDefaultlabelAndShowsAvailable(defaultLabel),
      EditorShortcutAction.formatDocument => AppLocalizations.of(
        context,
      )!.settingsDefaultsToDefaultlabelAndFormatsThe(defaultLabel),
    };
  }

  void _showUpdateCheckDialog(BuildContext context, AppInfo appInfo) {
    showAppUpdateDialog(context: context, appInfo: appInfo);
  }
}

List<Widget> _intersperse(List<Widget> items, Widget separator) {
  if (items.isEmpty) {
    return const <Widget>[];
  }
  final output = <Widget>[];
  for (var index = 0; index < items.length; index++) {
    output.add(items[index]);
    if (index != items.length - 1) {
      output.add(separator);
    }
  }
  return output;
}

// 弹窗动画设置

class _McpStdioMirrorModeControl extends StatelessWidget {
  const _McpStdioMirrorModeControl({
    required this.settingsController,
    required this.onPersistenceFailure,
    required this.onReconnect,
  });

  final SettingsController settingsController;
  final VoidCallback onPersistenceFailure;
  final VoidCallback onReconnect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selected = settingsController.mcpStdioMirrorMode;
    final source = resolveMcpMirrorEffectiveSource();
    final injects = source.injects;
    final reasonText = switch (source) {
      McpMirrorEffectiveSource.envOn ||
      McpMirrorEffectiveSource.envOff => l10n.mcpStdioMirrorModeReasonEnv,
      McpMirrorEffectiveSource.settingForceOn ||
      McpMirrorEffectiveSource.settingForceOff =>
        l10n.mcpStdioMirrorModeReasonSetting,
      McpMirrorEffectiveSource.autoLocaleZh ||
      McpMirrorEffectiveSource.autoLocaleOther =>
        l10n.mcpStdioMirrorModeReasonLocale(Platform.localeName),
    };
    final statusBg = injects
        ? colorScheme.primaryContainer.withValues(alpha: 0.45)
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.55);
    final statusFg = injects
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;
    final statusBorder = injects
        ? colorScheme.primary.withValues(alpha: 0.30)
        : colorScheme.outlineVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<McpStdioMirrorMode>(
          segments: <ButtonSegment<McpStdioMirrorMode>>[
            ButtonSegment<McpStdioMirrorMode>(
              value: McpStdioMirrorMode.auto,
              icon: const Icon(Icons.auto_awesome_outlined),
              label: Text(l10n.mcpStdioMirrorModeAuto, softWrap: false),
            ),
            ButtonSegment<McpStdioMirrorMode>(
              value: McpStdioMirrorMode.forceOn,
              icon: const Icon(Icons.cloud_done_outlined),
              label: Text(l10n.mcpStdioMirrorModeForceOn, softWrap: false),
            ),
            ButtonSegment<McpStdioMirrorMode>(
              value: McpStdioMirrorMode.forceOff,
              icon: const Icon(Icons.cloud_off_outlined),
              label: Text(l10n.mcpStdioMirrorModeForceOff, softWrap: false),
            ),
          ],
          selected: <McpStdioMirrorMode>{selected},
          onSelectionChanged: (selection) async {
            if (selection.isEmpty) return;
            final saved = await settingsController.updateMcpStdioMirrorMode(
              selection.first,
            );
            if (!context.mounted || saved) return;
            onPersistenceFailure();
          },
        ),
        kOpenHandGap10,
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: statusBg,
            borderRadius: kOpenHandBorderRadius10,
            border: Border.all(color: statusBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    injects ? Icons.cloud_done_outlined : Icons.public_outlined,
                    size: 18,
                    color: statusFg,
                  ),
                  kOpenHandHGap8,
                  Expanded(
                    child: Text(
                      injects
                          ? l10n.mcpStdioMirrorModeStatusInjected
                          : l10n.mcpStdioMirrorModeStatusBypassed,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: statusFg,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              kOpenHandGap4,
              Padding(
                padding: const EdgeInsets.only(left: 26),
                child: Text(
                  l10n.mcpStdioMirrorModeStatusReason(reasonText),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: statusFg.withValues(alpha: 0.78),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        kOpenHandGap8,
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: onReconnect,
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: Text(l10n.mcpStdioMirrorModeReconnectAction),
          ),
        ),
      ],
    );
  }
}

class _McpKeywordIndexUpdateModeControl extends StatelessWidget {
  const _McpKeywordIndexUpdateModeControl({
    required this.settingsController,
    required this.onPersistenceFailure,
  });

  final SettingsController settingsController;
  final VoidCallback onPersistenceFailure;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final mode = settingsController.mcpKeywordIndexUpdateMode;
    final intervalValue = settingsController.mcpKeywordIndexIntervalValue;
    final intervalUnit = settingsController.mcpKeywordIndexIntervalUnit;
    final scheduledTimeOfDay =
        settingsController.mcpKeywordIndexScheduledTimeOfDay;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<McpKeywordIndexUpdateMode>(
          segments: <ButtonSegment<McpKeywordIndexUpdateMode>>[
            ButtonSegment<McpKeywordIndexUpdateMode>(
              value: McpKeywordIndexUpdateMode.coldStart,
              icon: const Icon(Icons.bolt_outlined),
              label: Text(
                l10n.mcpKeywordIndexUpdateModeColdStart,
                softWrap: false,
              ),
            ),
            ButtonSegment<McpKeywordIndexUpdateMode>(
              value: McpKeywordIndexUpdateMode.interval,
              icon: const Icon(Icons.timelapse_outlined),
              label: Text(
                l10n.mcpKeywordIndexUpdateModeInterval,
                softWrap: false,
              ),
            ),
            ButtonSegment<McpKeywordIndexUpdateMode>(
              value: McpKeywordIndexUpdateMode.scheduled,
              icon: const Icon(Icons.schedule_outlined),
              label: Text(
                l10n.mcpKeywordIndexUpdateModeScheduled,
                softWrap: false,
              ),
            ),
          ],
          selected: <McpKeywordIndexUpdateMode>{mode},
          onSelectionChanged: (selection) async {
            if (selection.isEmpty) return;
            final saved = await settingsController
                .updateMcpKeywordIndexUpdateMode(selection.first);
            if (!context.mounted || saved) return;
            onPersistenceFailure();
          },
        ),
        kOpenHandGap12,
        if (mode == McpKeywordIndexUpdateMode.interval)
          _McpKeywordIndexIntervalForm(
            settingsController: settingsController,
            intervalValue: intervalValue,
            intervalUnit: intervalUnit,
            onPersistenceFailure: onPersistenceFailure,
          ),
        if (mode == McpKeywordIndexUpdateMode.scheduled)
          _McpKeywordIndexScheduledForm(
            settingsController: settingsController,
            scheduledTimeOfDay: scheduledTimeOfDay,
            onPersistenceFailure: onPersistenceFailure,
          ),
        if (mode == McpKeywordIndexUpdateMode.coldStart)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.55,
              ),
              borderRadius: kOpenHandBorderRadius10,
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Text(
              l10n.mcpKeywordIndexUpdateModeColdStartHint,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
            ),
          ),
      ],
    );
  }
}

class _McpKeywordIndexIntervalForm extends StatefulWidget {
  const _McpKeywordIndexIntervalForm({
    required this.settingsController,
    required this.intervalValue,
    required this.intervalUnit,
    required this.onPersistenceFailure,
  });

  final SettingsController settingsController;
  final int intervalValue;
  final McpKeywordIndexIntervalUnit intervalUnit;
  final VoidCallback onPersistenceFailure;

  @override
  State<_McpKeywordIndexIntervalForm> createState() =>
      _McpKeywordIndexIntervalFormState();
}

class _McpKeywordIndexIntervalFormState
    extends State<_McpKeywordIndexIntervalForm> {
  late final TextEditingController _valueController;
  late final FocusNode _valueFocusNode;

  @override
  void initState() {
    super.initState();
    _valueController = TextEditingController(text: '${widget.intervalValue}');
    _valueFocusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _McpKeywordIndexIntervalForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_valueFocusNode.hasFocus &&
        _valueController.text != '${widget.intervalValue}') {
      _valueController.text = '${widget.intervalValue}';
    }
  }

  @override
  void dispose() {
    _valueController.dispose();
    _valueFocusNode.dispose();
    super.dispose();
  }

  Future<void> _saveValue(String text) async {
    final parsed = optionalIntFromText(text);
    if (parsed == null) {
      _valueController.text = '${widget.intervalValue}';
      return;
    }
    final saved = await widget.settingsController
        .updateMcpKeywordIndexIntervalValue(parsed);
    if (!mounted || saved) return;
    widget.onPersistenceFailure();
  }

  Future<void> _saveUnit(McpKeywordIndexIntervalUnit unit) async {
    final saved = await widget.settingsController
        .updateMcpKeywordIndexIntervalUnit(unit);
    if (!mounted || saved) return;
    widget.onPersistenceFailure();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: TextField(
            controller: _valueController,
            focusNode: _valueFocusNode,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: InputDecoration(
              labelText: l10n.mcpKeywordIndexIntervalValueLabel,
              hintText:
                  '${AppSettingsSnapshot.defaultMcpKeywordIndexIntervalValue}',
            ),
            onSubmitted: _saveValue,
            onEditingComplete: () => _saveValue(_valueController.text),
          ),
        ),
        kOpenHandHGap12,
        Expanded(
          flex: 3,
          child: AnimatedDropdownButtonFormField<McpKeywordIndexIntervalUnit>(
            initialValue: widget.intervalUnit,
            decoration: InputDecoration(
              labelText: l10n.mcpKeywordIndexIntervalUnitLabel,
            ),
            items: <DropdownMenuItem<McpKeywordIndexIntervalUnit>>[
              DropdownMenuItem(
                value: McpKeywordIndexIntervalUnit.minute,
                child: Text(l10n.mcpKeywordIndexIntervalUnitMinute),
              ),
              DropdownMenuItem(
                value: McpKeywordIndexIntervalUnit.hour,
                child: Text(l10n.mcpKeywordIndexIntervalUnitHour),
              ),
              DropdownMenuItem(
                value: McpKeywordIndexIntervalUnit.day,
                child: Text(l10n.mcpKeywordIndexIntervalUnitDay),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              _saveUnit(value);
            },
          ),
        ),
      ],
    );
  }
}

class _McpKeywordIndexScheduledForm extends StatelessWidget {
  const _McpKeywordIndexScheduledForm({
    required this.settingsController,
    required this.scheduledTimeOfDay,
    required this.onPersistenceFailure,
  });

  final SettingsController settingsController;
  final String scheduledTimeOfDay;
  final VoidCallback onPersistenceFailure;

  TimeOfDay get _timeOfDay {
    final parsed = parseHourMinuteOfDay(scheduledTimeOfDay, fallbackHour: 2);
    return TimeOfDay(hour: parsed.hour, minute: parsed.minute);
  }

  Future<void> _pickTime(BuildContext context) async {
    final picked = await showAnimatedDialog<TimeOfDay>(
      context: context,
      builder: (dialogContext) => TimePickerDialog(initialTime: _timeOfDay),
    );
    if (picked == null) return;
    final saved = await settingsController
        .updateMcpKeywordIndexScheduledTimeOfDay(
          formatHourMinuteParts(hour: picked.hour, minute: picked.minute),
        );
    if (!context.mounted || saved) return;
    onPersistenceFailure();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.55,
              ),
              borderRadius: kOpenHandBorderRadius10,
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.schedule_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                kOpenHandHGap8,
                Expanded(
                  child: Text(
                    l10n.mcpKeywordIndexScheduledLabel(scheduledTimeOfDay),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        kOpenHandHGap12,
        FilledButton.tonalIcon(
          onPressed: () => _pickTime(context),
          icon: const Icon(Icons.edit_calendar_outlined),
          label: Text(l10n.mcpKeywordIndexScheduledPickAction),
        ),
      ],
    );
  }
}

class _McpLazyLoadingHelpBanner extends StatelessWidget {
  const _McpLazyLoadingHelpBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: kOpenHandBorderRadius12,
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.search_rounded, size: 18, color: colorScheme.primary),
          kOpenHandHGap10,
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 节流被关闭（rate=0）时显示的醒目提示徽章。
///
/// 用户在设置面板把「每秒最大输出渲染字符」或「每秒最大输
/// 出消息卡片数」改成 0 后，应用端就完全跳过了对应方向的背压。这条徽
/// 章高亮当前状态，避免用户在排查"输出卡顿/抽搐"时误以为节流仍在生效。
class _ThrottleDisabledBadge extends StatelessWidget {
  const _ThrottleDisabledBadge({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.55),
        borderRadius: kOpenHandBorderRadius12,
        border: Border.all(color: scheme.error.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.flash_off_rounded, size: 18, color: scheme.error),
          kOpenHandHGap8,
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onErrorContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 自动模式开启时显示的"实时 FPS"小指示器。
///
/// 直接读 [OpenHandFpsMonitor]，1s 一次刷新。
/// 被动采样下空闲期不产帧：无新鲜数据时显示「空闲」而非陈旧值；
/// 卡顿判定跟随 [OpenHandFpsMonitor.isStrugglingRecently]（超预算帧
/// 占比），与自动模式的实际降速决策一致。
class _AutoModeFpsIndicator extends StatefulWidget {
  const _AutoModeFpsIndicator();

  @override
  State<_AutoModeFpsIndicator> createState() => _AutoModeFpsIndicatorState();
}

class _AutoModeFpsIndicatorState extends State<_AutoModeFpsIndicator> {
  Timer? _timer;
  double _fps = 0;
  bool _struggling = false;

  @override
  void initState() {
    super.initState();
    _timer = startSafePeriodicTimer(
      const Duration(seconds: 1),
      (_) {
        if (!mounted) return;
        setState(() {
          _fps = OpenHandFpsMonitor.instance.recentFps;
          _struggling = OpenHandFpsMonitor.instance.isStrugglingRecently;
        });
      },
      onError: (error, stack) =>
          silentLog('settings', '刷新自动模式帧率', error, stack),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final idle = _fps <= 0;
    final low = !idle && _struggling;
    final color = low
        ? scheme.error
        : idle
        ? scheme.onSurfaceVariant
        : scheme.primary;
    final fpsLabel = _fps.toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: kOpenHandPillBorderRadius,
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            low
                ? Icons.south_rounded
                : idle
                ? Icons.pause_circle_outline_rounded
                : Icons.bolt_rounded,
            size: 14,
            color: color,
          ),
          kOpenHandHGap6,
          Text(
            idle
                ? openHandLocalizedText(
                    context,
                    zh: '实时 FPS：空闲',
                    zhHant: '即時 FPS：空閒',
                    en: 'FPS: idle',
                    fr: 'FPS : inactif',
                    de: 'FPS: inaktiv',
                    ja: 'FPS: アイドル',
                  )
                : openHandLocalizedText(
                    context,
                    zh: '实时 FPS：$fpsLabel${low ? ' · 已降速' : ''}',
                    zhHant: '即時 FPS：$fpsLabel${low ? ' · 已降速' : ''}',
                    en: 'FPS: $fpsLabel${low ? ' · slowed' : ''}',
                    fr: 'FPS : $fpsLabel${low ? ' · ralenti' : ''}',
                    de: 'FPS: $fpsLabel${low ? ' · verlangsamt' : ''}',
                    ja: 'FPS: $fpsLabel${low ? ' · 低速化' : ''}',
                  ),
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// 节流配置 import 时的 diff 行：字段名 + 当前值 + 即将应用的值。
class _ThrottleDiffRow {
  const _ThrottleDiffRow(this.label, this.before, this.after);
  final String label;
  final String before;
  final String after;
}

List<_ThrottleDiffRow> _diffThrottleConfig(
  Map<String, Object?> current,
  Map<String, Object?> next,
) {
  String format(Object? value) {
    if (value == null) return '—';
    if (value is bool) return value ? 'on' : 'off';
    if (value is Map) return jsonEncode(value);
    return value.toString();
  }

  final rows = <_ThrottleDiffRow>[];
  void add(String key) {
    final before = current[key];
    final after = next[key];
    if (before == after) return;
    rows.add(_ThrottleDiffRow(key, format(before), format(after)));
  }

  for (final key in throttleCloudSyncConfigFieldKeys) {
    add(key);
  }
  return rows;
}

/// 节流配置 import 冲突预览弹窗：列出 diff，用户确认后再 apply。
///
/// 直接 apply 容易让用户误覆盖未察觉的字段；先把所有差异
/// 项以 「key · before → after」 行形式展示，并提供 取消 / 应用 两个
/// OpenHandDialogActionButton 让用户做最后决策。
class _ThrottleImportDiffDialog extends StatelessWidget {
  const _ThrottleImportDiffDialog({required this.diffs});

  final List<_ThrottleDiffRow> diffs;

  @override
  Widget build(BuildContext context) {
    return buildOpenHandResponsiveDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthStandard,
      maxHeight: kOpenHandDialogHeightCompact,
      safeAreaMinimum: kOpenHandDialogDefaultInsetPadding,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: _ThrottleImportDiffContent(diffs: diffs, showActions: true),
      ),
    );
  }
}

class _ThrottleImportDiffContent extends StatelessWidget {
  const _ThrottleImportDiffContent({
    required this.diffs,
    required this.showActions,
  });

  final List<_ThrottleDiffRow> diffs;
  final bool showActions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.compare_arrows_rounded, size: 20, color: scheme.primary),
            kOpenHandHGap8,
            Expanded(
              child: Text(
                openHandLocalizedText(
                  context,
                  zh: '节流配置 · 冲突预览',
                  zhHant: '節流設定 · 衝突預覽',
                  en: 'Throttle Config · Diff Preview',
                  fr: 'Config de limitation · Aperçu des différences',
                  de: 'Drosselungskonfiguration · Differenzvorschau',
                  ja: 'スロットリング設定 · 差分プレビュー',
                ),
                style: theme.textTheme.titleLarge,
              ),
            ),
          ],
        ),
        kOpenHandGap8,
        Text(
          openHandLocalizedText(
            context,
            zh: '以下字段会被新 JSON 覆盖；确认后才正式生效。',
            zhHant: '以下欄位會被新的 JSON 覆蓋；確認後才會正式生效。',
            en: 'Below fields will be overwritten after confirmation.',
            fr: 'Les champs ci-dessous seront remplacés après confirmation.',
            de: 'Die folgenden Felder werden nach der Bestätigung überschrieben.',
            ja: '以下のフィールドは確認後に新しい JSON で上書きされます。',
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        kOpenHandGap12,
        Flexible(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: kOpenHandBorderRadius12,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              physics: openHandDialogAwareScrollPhysics(context),
              itemCount: diffs.length,
              separatorBuilder: (_, _) => Divider(
                height: 12,
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
              itemBuilder: (_, i) {
                final r = diffs[i];
                return Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Text(
                        r.label,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontFamily: kOpenHandMonospaceFontFamily,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 5,
                      child: Text(
                        r.before,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.error,
                          decoration: TextDecoration.lineThrough,
                          fontFamily: kOpenHandMonospaceFontFamily,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                    kOpenHandHGap6,
                    Expanded(
                      flex: 5,
                      child: Text(
                        r.after,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                          fontFamily: kOpenHandMonospaceFontFamily,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        if (showActions) ...[
          kOpenHandGap16,
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OpenHandDialogActionButton.secondary(
                onPressed: () => Navigator.of(context).pop(false),
                label: AppLocalizations.of(context)!.commonCancel,
              ),
              kOpenHandHGap8,
              OpenHandDialogActionButton.primary(
                onPressed: () => Navigator.of(context).pop(true),
                label: openHandLocalizedText(
                  context,
                  zh: '应用 ${diffs.length} 项',
                  zhHant: '套用 ${diffs.length} 項',
                  en: 'Apply ${diffs.length}',
                  fr: 'Appliquer ${diffs.length}',
                  de: '${diffs.length} anwenden',
                  ja: '${diffs.length} 件を適用',
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 节流配置云端同步编辑器：provider 选择 + endpoint / token 输入 +
/// push / pull 按钮。
///
/// 支持 custom、iCloud 和 GitHub Gist。
class _ThrottleCloudSyncEditor extends StatefulWidget {
  const _ThrottleCloudSyncEditor();

  @override
  State<_ThrottleCloudSyncEditor> createState() =>
      _ThrottleCloudSyncEditorState();
}

class _ThrottleCloudSyncEditorState extends State<_ThrottleCloudSyncEditor> {
  late final TextEditingController _endpointCtrl;
  late final TextEditingController _tokenCtrl;
  late final FocusNode _endpointFocus;
  late final FocusNode _tokenFocus;
  late final ThrottleCloudSyncService _cloudSyncService;
  bool _busy = false;
  String _status = '';
  bool _statusError = false;

  @override
  void initState() {
    super.initState();
    final c = context.read<SettingsController>();
    _endpointCtrl = TextEditingController(
      text: c.aiStreamThrottleCloudSyncEndpoint,
    );
    _tokenCtrl = TextEditingController(text: c.aiStreamThrottleCloudSyncToken);
    _endpointFocus = FocusNode();
    _tokenFocus = FocusNode();
    _cloudSyncService = ThrottleCloudSyncService(
      registerCloudChangeHandler: false,
    );
  }

  @override
  void dispose() {
    _endpointCtrl.dispose();
    _tokenCtrl.dispose();
    _endpointFocus.dispose();
    _tokenFocus.dispose();
    unawaited(_cloudSyncService.dispose());
    super.dispose();
  }

  Future<SettingsController?> _beginSyncOperation() async {
    if (_busy) return null;
    setState(() {
      _busy = true;
      _status = '';
      _statusError = false;
    });
    final c = context.read<SettingsController>();
    final saved = await c.updateAiStreamThrottleCloudSyncCredentials(
      endpoint: _endpointCtrl.text,
      token: _tokenCtrl.text,
    );
    if (!mounted) return null;
    if (saved) return c;
    setState(() {
      _busy = false;
      _statusError = true;
      _status = openHandLocalizedText(
        context,
        zh: '同步凭据保存失败，请先解决设置持久化问题。',
        zhHant: '同步憑證儲存失敗，請先解決設定持久化問題。',
        en: 'Could not save sync credentials. Resolve the settings persistence issue first.',
        fr: 'Impossible d’enregistrer les identifiants. Résolvez d’abord le problème de persistance des réglages.',
        de: 'Synchronisierungsdaten konnten nicht gespeichert werden. Beheben Sie zuerst das Speicherproblem der Einstellungen.',
        ja: '同期認証情報を保存できませんでした。先に設定の保存問題を解決してください。',
      );
    });
    return null;
  }

  Future<void> _push() async {
    final c = await _beginSyncOperation();
    if (c == null) return;
    final provider = ThrottleCloudSyncProvider.fromStorage(
      c.aiStreamThrottleCloudSyncProvider,
    );
    final result = await _cloudSyncService.push(
      provider: provider,
      endpoint: c.aiStreamThrottleCloudSyncEndpoint,
      token: c.aiStreamThrottleCloudSyncToken,
      config: c.exportAiStreamThrottleConfig(),
      updatedAtMs: c.aiStreamThrottleConfigUpdatedAtMs,
      gistId: provider == ThrottleCloudSyncProvider.gistGitHub
          ? c.aiStreamThrottleCloudSyncEndpoint.trim()
          : '',
    );
    if (!mounted) return;
    final createdGistId = result.createdGistId;
    if (result.ok && createdGistId.isNotEmpty) {
      _endpointCtrl.text = createdGistId;
      final saved = await c.updateAiStreamThrottleCloudSyncCredentials(
        endpoint: createdGistId,
        token: _tokenCtrl.text,
      );
      if (!mounted) return;
      if (!saved) {
        setState(() {
          _busy = false;
          _statusError = true;
          _status = openHandLocalizedText(
            context,
            zh: 'Gist 已创建，但 ID 保存失败。请复制后重试：$createdGistId',
            zhHant: 'Gist 已建立，但 ID 儲存失敗。請複製後重試：$createdGistId',
            en: 'The Gist was created, but its ID could not be saved. Copy it and retry: $createdGistId',
            fr: 'Le Gist a été créé, mais son ID n’a pas pu être enregistré. Copiez-le puis réessayez : $createdGistId',
            de: 'Der Gist wurde erstellt, aber seine ID konnte nicht gespeichert werden. Kopieren und erneut versuchen: $createdGistId',
            ja: 'Gist は作成されましたが、ID を保存できませんでした。コピーして再試行してください：$createdGistId',
          );
        });
        return;
      }
    }
    setState(() {
      _busy = false;
      _statusError = !result.ok;
      _status = result.ok
          ? openHandLocalizedText(
              context,
              zh: createdGistId.isEmpty
                  ? '已推送到云端。'
                  : '已创建并保存 Gist：$createdGistId',
              zhHant: createdGistId.isEmpty
                  ? '已推送到雲端。'
                  : '已建立並儲存 Gist：$createdGistId',
              en: createdGistId.isEmpty
                  ? 'Pushed to the cloud.'
                  : 'Gist created and saved: $createdGistId',
              fr: createdGistId.isEmpty
                  ? 'Configuration envoyée dans le cloud.'
                  : 'Gist créé et enregistré : $createdGistId',
              de: createdGistId.isEmpty
                  ? 'In die Cloud übertragen.'
                  : 'Gist erstellt und gespeichert: $createdGistId',
              ja: createdGistId.isEmpty
                  ? 'クラウドへプッシュしました。'
                  : 'Gist を作成して保存しました：$createdGistId',
            )
          : openHandLocalizedText(
              context,
              zh: '推送失败：${result.message}',
              zhHant: '推送失敗：${result.message}',
              en: 'Push failed: ${result.message}',
              fr: 'Échec de l’envoi : ${result.message}',
              de: 'Push fehlgeschlagen: ${result.message}',
              ja: 'プッシュに失敗しました: ${result.message}',
            );
    });
  }

  Future<void> _pull() async {
    final c = await _beginSyncOperation();
    if (c == null) return;
    final provider = ThrottleCloudSyncProvider.fromStorage(
      c.aiStreamThrottleCloudSyncProvider,
    );
    final result = await _cloudSyncService.pull(
      provider: provider,
      endpoint: c.aiStreamThrottleCloudSyncEndpoint,
      token: c.aiStreamThrottleCloudSyncToken,
      gistId: provider == ThrottleCloudSyncProvider.gistGitHub
          ? c.aiStreamThrottleCloudSyncEndpoint.trim()
          : '',
    );
    if (!mounted) return;
    if (!result.ok || result.config == null) {
      setState(() {
        _busy = false;
        _statusError = true;
        _status = openHandLocalizedText(
          context,
          zh: '拉取失败：${result.message}',
          zhHant: '拉取失敗：${result.message}',
          en: 'Pull failed: ${result.message}',
          fr: 'Échec de la récupération : ${result.message}',
          de: 'Pull fehlgeschlagen: ${result.message}',
          ja: 'プルに失敗しました: ${result.message}',
        );
      });
      return;
    }
    final current = c.exportAiStreamThrottleConfig();
    final diffs = _diffThrottleConfig(current, result.config!);
    setState(() => _busy = false);
    if (diffs.isEmpty) {
      setState(() {
        _statusError = false;
        _status = _settingsViewNoChangesDetectedLabel(context);
      });
      return;
    }
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (dialogContext) => _ThrottleImportDiffDialog(diffs: diffs),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final outcome = await c.importAiStreamThrottleConfig(
      result.config!,
      overrideUpdatedAtMs: result.updatedAtMs > 0 ? result.updatedAtMs : null,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _statusError = outcome == AiStreamThrottleConfigImportOutcome.failed;
      _status = switch (outcome) {
        AiStreamThrottleConfigImportOutcome.applied => openHandLocalizedText(
          context,
          zh: '已应用云端配置。',
          zhHant: '已套用雲端設定。',
          en: 'Cloud config applied.',
          fr: 'Configuration cloud appliquée.',
          de: 'Cloud-Konfiguration angewendet.',
          ja: 'クラウド設定を適用しました。',
        ),
        AiStreamThrottleConfigImportOutcome.unchanged =>
          _settingsViewNoChangesDetectedLabel(context),
        AiStreamThrottleConfigImportOutcome.failed => openHandLocalizedText(
          context,
          zh: '应用失败，配置未能保存。',
          zhHant: '套用失敗，設定未能儲存。',
          en: 'Apply failed. The settings could not be saved.',
          fr: 'Échec de l’application. Les réglages n’ont pas été enregistrés.',
          de: 'Anwenden fehlgeschlagen. Die Einstellungen konnten nicht gespeichert werden.',
          ja: '適用に失敗しました。設定を保存できませんでした。',
        ),
      };
    });
  }

  static String _providerHintMessage(
    BuildContext context,
    ThrottleCloudSyncProvider provider,
  ) {
    switch (provider) {
      case ThrottleCloudSyncProvider.iCloud:
        if (Platform.isMacOS || Platform.isIOS) {
          return openHandLocalizedText(
            context,
            zh: 'iCloud Drive 同步已启用：通过 NSUbiquitousKeyValueStore 与同账号其他 Apple 设备自动同步（容量上限 1MB）。',
            zhHant:
                'iCloud Drive 同步已啟用：透過 NSUbiquitousKeyValueStore 與同帳號其他 Apple 裝置自動同步（容量上限 1MB）。',
            en: 'iCloud sync is wired via NSUbiquitousKeyValueStore (1MB cap). Throttle config is mirrored across same-account Apple devices.',
            fr: 'La synchro iCloud utilise NSUbiquitousKeyValueStore (limite 1 Mo) et réplique la config entre appareils Apple du même compte.',
            de: 'iCloud-Synchronisierung nutzt NSUbiquitousKeyValueStore (1 MB Limit) und spiegelt die Konfiguration auf Apple-Geräten desselben Kontos.',
            ja: 'iCloud 同期は NSUbiquitousKeyValueStore（上限 1MB）を使い、同じアカウントの Apple デバイス間で設定を同期します。',
          );
        }
        return openHandLocalizedText(
          context,
          zh: 'iCloud 同步仅支持 macOS / iOS；当前平台请使用「自定义 HTTP」或 GitHub Gist。',
          zhHant: 'iCloud 同步僅支援 macOS / iOS；目前平台請使用「自訂 HTTP」或 GitHub Gist。',
          en: 'iCloud sync is macOS / iOS only; use Custom HTTP or GitHub Gist on this platform.',
          fr: 'La synchro iCloud est limitée à macOS / iOS ; utilisez HTTP personnalisé ou GitHub Gist sur cette plateforme.',
          de: 'iCloud-Synchronisierung ist nur für macOS/iOS verfügbar; verwenden Sie auf dieser Plattform Custom HTTP oder GitHub Gist.',
          ja: 'iCloud 同期は macOS / iOS のみ対応です。このプラットフォームではカスタム HTTP または GitHub Gist を使ってください。',
        );
      case ThrottleCloudSyncProvider.gistGitHub:
        return openHandLocalizedText(
          context,
          zh: 'GitHub Gist 同步：填写已有 secret gist 的 ID；首次推送可留空，创建成功后会自动保存 ID。「PAT」需带 gist scope。',
          zhHant:
              'GitHub Gist 同步：填寫既有 secret gist 的 ID；首次推送可留空，建立成功後會自動儲存 ID。「PAT」需帶 gist scope。',
          en: 'GitHub Gist sync: enter an existing secret gist ID, or leave it empty on the first push to create and save one automatically. The PAT needs gist scope.',
          fr: 'Synchro GitHub Gist : indiquez l’ID d’un secret gist existant, ou laissez-le vide au premier envoi pour le créer et l’enregistrer automatiquement. Le PAT doit avoir le scope gist.',
          de: 'GitHub-Gist-Sync: vorhandene Secret-Gist-ID eintragen oder beim ersten Push leer lassen, um sie automatisch zu erstellen und zu speichern. PAT braucht gist-Scope.',
          ja: 'GitHub Gist 同期：既存の secret gist ID を入力します。初回プッシュ時は空欄にすると、自動で作成して ID を保存します。PAT には gist scope が必要です。',
        );
      case ThrottleCloudSyncProvider.custom:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = context.read<SettingsController>();
    final providerEnum = ThrottleCloudSyncProvider.fromStorage(
      context.select<SettingsController, String>(
        (controller) => controller.aiStreamThrottleCloudSyncProvider,
      ),
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: kOpenHandBorderRadius14,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: SegmentedButton<ThrottleCloudSyncProvider>(
              segments: <ButtonSegment<ThrottleCloudSyncProvider>>[
                ButtonSegment(
                  value: ThrottleCloudSyncProvider.custom,
                  icon: const Icon(Icons.cloud_outlined, size: 16),
                  label: Text(
                    openHandLocalizedText(
                      context,
                      zh: '自定义 HTTP',
                      zhHant: '自訂 HTTP',
                      en: 'Custom HTTP',
                      fr: 'HTTP personnalisé',
                      de: 'Eigenes HTTP',
                      ja: 'カスタム HTTP',
                    ),
                  ),
                ),
                const ButtonSegment(
                  value: ThrottleCloudSyncProvider.iCloud,
                  icon: Icon(Icons.cloud_circle_outlined, size: 16),
                  label: Text('iCloud'),
                ),
                const ButtonSegment(
                  value: ThrottleCloudSyncProvider.gistGitHub,
                  icon: Icon(Icons.code_rounded, size: 16),
                  label: Text('Gist'),
                ),
              ],
              selected: <ThrottleCloudSyncProvider>{providerEnum},
              onSelectionChanged: _busy
                  ? null
                  : (s) {
                      if (s.isEmpty) return;
                      c.updateAiStreamThrottleCloudSyncProvider(
                        s.first.storageValue,
                      );
                    },
            ),
          ),
          kOpenHandGap12,
          if (providerEnum != ThrottleCloudSyncProvider.custom &&
              providerEnum != ThrottleCloudSyncProvider.gistGitHub)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer.withValues(alpha: 0.5),
                borderRadius: kOpenHandBorderRadius10,
              ),
              child: Text(
                _providerHintMessage(context, providerEnum),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onTertiaryContainer,
                ),
              ),
            ),
          if (providerEnum == ThrottleCloudSyncProvider.gistGitHub) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer.withValues(alpha: 0.5),
                borderRadius: kOpenHandBorderRadius10,
              ),
              child: Text(
                _providerHintMessage(context, providerEnum),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onTertiaryContainer,
                ),
              ),
            ),
            kOpenHandGap8,
            TextField(
              controller: _endpointCtrl,
              focusNode: _endpointFocus,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: openHandLocalizedText(
                  context,
                  zh: 'Gist ID（首次推送可留空）',
                  zhHant: 'Gist ID（首次推送可留空）',
                  en: 'Gist ID (leave empty for first push)',
                  fr: 'ID Gist (vide au premier envoi)',
                  de: 'Gist-ID (beim ersten Push leer lassen)',
                  ja: 'Gist ID（初回プッシュ時は空欄可）',
                ),
                hintText: '83a1b9b0...',
              ),
            ),
            kOpenHandGap8,
            TextField(
              controller: _tokenCtrl,
              focusNode: _tokenFocus,
              enabled: !_busy,
              obscureText: true,
              decoration: InputDecoration(
                labelText: openHandLocalizedText(
                  context,
                  zh: 'GitHub PAT (需 gist scope)',
                  zhHant: 'GitHub PAT (需 gist scope)',
                  en: 'GitHub PAT (gist scope)',
                  fr: 'PAT GitHub (scope gist)',
                  de: 'GitHub PAT (gist-Scope)',
                  ja: 'GitHub PAT（gist scope）',
                ),
                hintText: 'github_pat_••••••••',
              ),
            ),
          ],
          if (providerEnum == ThrottleCloudSyncProvider.custom) ...[
            TextField(
              controller: _endpointCtrl,
              focusNode: _endpointFocus,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: openHandLocalizedText(
                  context,
                  zh: 'HTTP 端点地址',
                  zhHant: 'HTTP 端點位址',
                  en: 'HTTP Endpoint URL',
                  fr: 'URL du point de terminaison HTTP',
                  de: 'HTTP-Endpunkt-URL',
                  ja: 'HTTP エンドポイント URL',
                ),
                hintText: 'https://example.com/openhand/throttle',
              ),
            ),
            kOpenHandGap8,
            TextField(
              controller: _tokenCtrl,
              focusNode: _tokenFocus,
              enabled: !_busy,
              obscureText: true,
              decoration: InputDecoration(
                labelText: openHandLocalizedText(
                  context,
                  zh: 'Bearer Token (可选)',
                  zhHant: 'Bearer Token (可選)',
                  en: 'Bearer Token (optional)',
                  fr: 'Bearer Token (facultatif)',
                  de: 'Bearer Token (optional)',
                  ja: 'Bearer Token（任意）',
                ),
                hintText: '••••••••',
              ),
            ),
          ],
          kOpenHandGap12,
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _push,
                icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                label: Text(
                  openHandLocalizedText(
                    context,
                    zh: '推送到云端',
                    zhHant: '推送到雲端',
                    en: 'Push',
                    fr: 'Envoyer',
                    de: 'Push',
                    ja: 'プッシュ',
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _pull,
                icon: const Icon(Icons.cloud_download_outlined, size: 18),
                label: Text(
                  openHandLocalizedText(
                    context,
                    zh: '从云端拉取',
                    zhHant: '從雲端拉取',
                    en: 'Pull',
                    fr: 'Récupérer',
                    de: 'Pull',
                    ja: 'プル',
                  ),
                ),
              ),
            ],
          ),
          if (_status.isNotEmpty) ...[
            kOpenHandGap10,
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color:
                    (_statusError
                            ? scheme.errorContainer
                            : scheme.primaryContainer)
                        .withValues(alpha: 0.6),
                borderRadius: kOpenHandBorderRadius10,
              ),
              child: Text(
                _status,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _statusError
                      ? scheme.onErrorContainer
                      : scheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// 本库内复用的文案。

String _settingsClearLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '确认清空', en: 'Clear');
}

String _settingsLocalCacheLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '本地缓存', en: 'Local Cache');
}

String _settingsViewMaxRenderCardsSecLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '每秒最大输出消息卡片数',
    zhHant: '每秒最大輸出訊息卡片數',
    en: 'Max Render Cards / Sec',
    fr: 'Cartes rendues max / s',
    de: 'Max. Render-Karten / s',
    ja: '1 秒あたりの最大描画カード数',
  );
}

String _settingsViewMaxRenderCharsSecLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '每秒最大输出渲染字符',
    zhHant: '每秒最大輸出渲染字元',
    en: 'Max Render Chars / Sec',
    fr: 'Caractères rendus max / s',
    de: 'Max. Render-Zeichen / s',
    ja: '1 秒あたりの最大描画文字数',
  );
}

String _settingsViewNoChangesDetectedLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '配置无变化。',
    zhHant: '設定無變化。',
    en: 'No changes detected.',
    fr: 'Aucune modification détectée.',
    de: 'Keine Änderungen erkannt.',
    ja: '変更はありません。',
  );
}

String _settingsViewThrottleDurationSLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '节流持续时长（秒）',
    zhHant: '節流持續時長（秒）',
    en: 'Throttle Duration (s)',
    fr: 'Durée de limitation (s)',
    de: 'Drosselungsdauer (s)',
    ja: 'スロットリング継続時間（秒）',
  );
}
