import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as crypto;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../app/support/input_repair_service.dart';
import '../../app/support/safe_subprocess.dart';
import '../../app/support/silent_log.dart';
import '../../app/support/system_proxy.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/db/atomic_file_operations.dart';
import '../../shared/net/http_response_utils.dart';
import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/animated_expandable.dart';
import '../../shared/ui/animated_menu.dart';
import '../../shared/ui/appear_once.dart';
import '../../shared/ui/auto_follow_scroll_guard.dart';
import '../../shared/ui/frame_coalesced_rebuild.dart';
import '../../shared/ui/hover_lift.dart';
import '../../shared/ui/interaction_timings.dart';
import '../../shared/ui/media_preview_dialog.dart';
import '../../shared/ui/motion_durations.dart';
import '../../shared/ui/motion_preference.dart';
import '../../shared/ui/oh_pill.dart';
import '../../shared/ui/openhand_busy_indicators.dart';
import '../../shared/ui/openhand_clipboard.dart';
import '../../shared/ui/openhand_dialog_action_button.dart';
import '../../shared/ui/openhand_form_fields.dart';
import '../../shared/ui/openhand_inline_empty_state.dart';
import '../../shared/ui/openhand_reveal_switcher.dart';
import '../../shared/ui/openhand_safe_scrollbar.dart';
import '../../shared/ui/openhand_scroll_behaviors.dart';
import '../../shared/ui/openhand_snack_bar.dart';
import '../../shared/ui/openhand_spacing.dart';
import '../../shared/ui/openhand_tap_region.dart';
import '../../shared/ui/openhand_typography.dart';
import '../../shared/ui/resizable_splitter.dart';
import '../../shared/util/async_concurrency.dart';
import '../../shared/util/bounded_base64.dart';
import '../../shared/util/bounded_delete.dart';
import '../../shared/util/bounded_directory_io.dart';
import '../../shared/util/bounded_file_io.dart';
import '../../shared/util/byte_size_format.dart';
import '../../shared/util/date_time_format.dart';
import '../../shared/util/hex_encoding.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/localized_text.dart';
import '../../shared/util/rolling_hash.dart';
import '../../shared/util/text_clip.dart';
import '../../shared/util/text_normalization.dart';
import '../../shared/util/timer_safety.dart';
import '../../shared/util/user_failure_message.dart';
import '../ai/index.dart';
import 'lsp/web_reverse_lsp_client.dart';
import 'web_reverse_account_snapshots_dialog.dart';
import 'web_reverse_ai_crypto_dialog.dart';
import 'web_reverse_animations_dialog.dart';
import 'web_reverse_callgraph_dialog.dart';
import 'web_reverse_cdp_console_dialog.dart';
import 'web_reverse_cdp_http.dart';
import 'web_reverse_clipboard.dart';
import 'web_reverse_collection_export_dialog.dart';
import 'web_reverse_console_cluster_dialog.dart';
import 'web_reverse_cookie_editor_dialog.dart';
import 'web_reverse_cors_preflight_dialog.dart';
import 'web_reverse_coverage_dialog.dart';
import 'web_reverse_cpu_throttle_dialog.dart';
import 'web_reverse_css_coverage_dialog.dart';
import 'web_reverse_device_emulation_dialog.dart';
import 'web_reverse_dialog_utils.dart';
import 'web_reverse_dom_mutation_dialog.dart';
import 'web_reverse_dom_search_dialog.dart';
import 'web_reverse_file_io.dart';
import 'web_reverse_frame_tree_dialog.dart';
import 'web_reverse_geo_override_dialog.dart';
import 'web_reverse_har_io.dart';
import 'web_reverse_har_persistence_dialog.dart';
import 'web_reverse_headless_batch_dialog.dart';
import 'web_reverse_heap_snapshot_dialog.dart';
import 'web_reverse_input_sim_dialog.dart';
import 'web_reverse_issues_dialog.dart';
import 'web_reverse_jwt_refresh_dialog.dart';
import 'web_reverse_launch_diagnosis.dart';
import 'web_reverse_mitmproxy_bridge.dart';
import 'web_reverse_mock_rules_dialog.dart';
import 'web_reverse_perf_trace_dialog.dart';
import 'web_reverse_postmessage_dialog.dart';
import 'web_reverse_profile_actions.dart';
import 'web_reverse_pure_helpers.dart';
import 'web_reverse_rendering_dialog.dart';
import 'web_reverse_repl_dialog.dart';
import 'web_reverse_replay_dialog.dart';
import 'web_reverse_request_breakpoints_dialog.dart';
import 'web_reverse_resend_request_dialog.dart';
import 'web_reverse_screenshot_markup.dart';
import 'web_reverse_select_button.dart';
import 'web_reverse_session_config.dart';
import 'web_reverse_session_controller.dart';
import 'web_reverse_signature_diff_dialog.dart';
import 'web_reverse_sourcemap_dialog.dart';
import 'web_reverse_storage_dialog.dart';
import 'web_reverse_sw_debug_dialog.dart';
import 'web_reverse_throttle_dialog.dart';
import 'web_reverse_vitals_dialog.dart';
import 'web_reverse_watch_dialog.dart';
import 'web_reverse_waterfall_dialog.dart';
import 'web_reverse_webauthn_dialog.dart';
import 'web_reverse_websocket_dialog.dart';
import 'web_reverse_ws_inject_dialog.dart';

part 'web_reverse_dashboard_dialog.network.part.dart';
part 'web_reverse_dashboard_dialog.console.part.dart';
part 'web_reverse_dashboard_dialog.detail.part.dart';
part 'web_reverse_dashboard_dialog.toolbar.part.dart';
part 'web_reverse_dashboard_dialog.panels.part.dart';
part 'web_reverse_dashboard_dialog.advanced.part.dart';
part 'web_reverse_dashboard_dialog.sources.part.dart';
part 'web_reverse_dashboard_dialog.browser.part.dart';
part 'web_reverse_dashboard_dialog.snippets.part.dart';
part 'web_reverse_dashboard_dialog.elements.part.dart';
part 'web_reverse_dashboard_dialog.crypto.part.dart';
part 'web_reverse_dashboard_dialog.hooks.part.dart';
part 'web_reverse_dashboard_dialog.crons.part.dart';
part 'web_reverse_dashboard_dialog.breakpoints.part.dart';
part 'web_reverse_dashboard_dialog.realtime.part.dart';

// ── 视觉常量 ───────────────────────────────────────────────────────────
// 工具栏所有元素统一高度 36，沿用 Material outlined 风格的胶囊形。
// 数据来源：Chrome DevTools 工具栏元素自身约 26-30px；这里做了桌面侧
// 略大一点的视觉，保证 macOS 上点击命中区充足。
/// 把 URL 交给系统默认处理器（open / start / xdg-open）。
const Duration _kOpenExternalUrlTimeout = Duration(seconds: 5);

const double _kToolbarHeight = 36;
const double _kToolbarRadius = 999;
const double _kToolbarDisabledOutlineAlpha = 0.4;

/// 浏览器工具条上「胶囊按钮 / 下拉锚点」的统一描边；禁用态描边淡化。
BoxDecoration _toolbarChipDecoration(ColorScheme cs, {required bool enabled}) {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(_kToolbarRadius),
    border: Border.all(
      color: enabled
          ? cs.outlineVariant
          : cs.outlineVariant.withValues(alpha: _kToolbarDisabledOutlineAlpha),
    ),
  );
}

const EdgeInsets _kDashboardDialogInsetPadding = EdgeInsets.all(24);
const Duration _kSwitchDuration = kOpenHandMotion220;
const Duration _kDevToolsDiscoveryTimeout = Duration(seconds: 3);
const int _kDevToolsDiscoveryMaxResponseBytes = 4 * kBytesPerMiB;
const Curve _kSwitchInCurve = Curves.easeOutCubic;
const Curve _kSwitchOutCurve = Curves.easeInCubic;


bool _wrMotionEnabled(BuildContext context) {
  return openHandTickerMotionEnabled(context);
}

int _pageTargetsOrderHash(List<CdpPageTargetSnapshot> targets) {
  return rollingHash30(targets, (target) => target.id.hashCode);
}

int _pageTargetsTitleHash(List<CdpPageTargetSnapshot> targets) {
  return rollingHash30(targets, (target) => target.title.hashCode);
}

String _formatHeaderLines(Map<String, String> headers) {
  if (headers.isEmpty) return '';
  return headers.entries
      .map((entry) => '${entry.key}: ${entry.value}')
      .join('\n');
}

Map<String, String> _parseHeaderLines(String text) {
  final headers = <String, String>{};
  for (final rawLine in const LineSplitter().convert(text)) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final separator = line.indexOf(':');
    if (separator <= 0) continue;
    final name = line.substring(0, separator).trim();
    if (name.isEmpty) continue;
    headers[name] = line.substring(separator + 1).trim();
  }
  return headers;
}

class _DashboardScriptCodeEditor extends StatelessWidget {
  const _DashboardScriptCodeEditor({
    required this.controller,
    required this.focusNode,
    required this.bindings,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final Map<ShortcutActivator, VoidCallback> bindings;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CallbackShortcuts(
      bindings: bindings,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: kOpenHandBorderRadius12,
          border: Border.all(color: cs.outlineVariant),
        ),
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          maxLines: null,
          expands: true,
          maxLength: WebReverseSessionController.maxSavedScriptCodeChars,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
          buildCounter: openHandHiddenTextFieldCounter,
          textAlignVertical: TextAlignVertical.top,
          style: const TextStyle(
            fontFamily: kOpenHandMonospaceFontFamily,
            fontSize: 13,
          ),
          decoration: const InputDecoration(
            border: InputBorder.none,
            isDense: true,
          ),
        ),
      ),
    );
  }
}

class _DashboardScriptNameField extends StatelessWidget {
  const _DashboardScriptNameField({
    required this.controller,
    required this.label,
  });

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLength: WebReverseSessionController.maxSavedScriptNameChars,
      maxLengthEnforcement: MaxLengthEnforcement.enforced,
      buildCounter: openHandHiddenTextFieldCounter,
      decoration: InputDecoration(
        isDense: true,
        border: const OutlineInputBorder(),
        labelText: label,
      ),
    );
  }
}

Map<ShortcutActivator, VoidCallback> _dashboardScriptEditorBindings({
  required VoidCallback onSave,
  VoidCallback? onRun,
}) {
  return <ShortcutActivator, VoidCallback>{
    const SingleActivator(LogicalKeyboardKey.keyS, meta: true): onSave,
    const SingleActivator(LogicalKeyboardKey.keyS, control: true): onSave,
    if (onRun != null) ...<ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.keyR, meta: true): onRun,
      const SingleActivator(LogicalKeyboardKey.keyR, control: true): onRun,
    },
  };
}

mixin _DashboardScriptEditorLifecycle<W extends StatefulWidget>
    on State<W>, FrameCoalescedRebuild<W> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _codeCtrl = TextEditingController();
  final FocusNode _codeFocus = FocusNode();
  String? _selectedId;
  bool _dirty = false;
  bool _syncingScriptFields = false;

  Listenable get _dashboardScriptController;

  void _syncSelectionFromController();

  void _markDirty();

  void _syncDashboardScriptSelection<E>({
    required List<E> items,
    required String Function(E item) itemId,
    required String Function(E item) itemName,
    required String Function(E item) itemCode,
    void Function(E item)? syncAdditionalFields,
    VoidCallback? clearAdditionalFields,
  }) {
    if (items.isEmpty) {
      _syncingScriptFields = true;
      try {
        _selectedId = null;
        _nameCtrl.clear();
        _codeCtrl.clear();
        clearAdditionalFields?.call();
        _dirty = false;
      } finally {
        _syncingScriptFields = false;
      }
      return;
    }
    var selected = items.first;
    for (final item in items) {
      if (itemId(item) == _selectedId) {
        selected = item;
        break;
      }
    }
    if (_selectedId == itemId(selected)) return;
    _setDashboardScriptSelection(
      id: itemId(selected),
      name: itemName(selected),
      code: itemCode(selected),
      syncAdditionalFields: () => syncAdditionalFields?.call(selected),
    );
  }

  void _setDashboardScriptSelection({
    required String id,
    required String name,
    required String code,
    VoidCallback? syncAdditionalFields,
  }) {
    _syncingScriptFields = true;
    try {
      _selectedId = id;
      _nameCtrl.text = name;
      _codeCtrl.text = code;
      syncAdditionalFields?.call();
      _dirty = false;
    } finally {
      _syncingScriptFields = false;
    }
  }

  void _updateDashboardScriptDirty<E>({
    required Iterable<E> items,
    required String Function(E item) itemId,
    required String Function(E item) itemName,
    required String Function(E item) itemCode,
    bool Function(E item)? additionalFieldsMatch,
  }) {
    if (_syncingScriptFields) return;
    final selectedId = _selectedId;
    E? selected;
    if (selectedId != null) {
      for (final item in items) {
        if (itemId(item) == selectedId) {
          selected = item;
          break;
        }
      }
    }
    final dirty = selectedId == null
        ? _nameCtrl.text.isNotEmpty || _codeCtrl.text.isNotEmpty
        : selected == null ||
              itemName(selected) != _nameCtrl.text ||
              itemCode(selected) != _codeCtrl.text ||
              !(additionalFieldsMatch?.call(selected) ?? true);
    if (_dirty == dirty) return;
    _dirty = dirty;
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _dashboardScriptController.addListener(_onDashboardControllerChanged);
    _syncSelectionFromController();
    _nameCtrl.addListener(_markDirty);
    _codeCtrl.addListener(_markDirty);
  }

  @override
  void dispose() {
    _dashboardScriptController.removeListener(_onDashboardControllerChanged);
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  void _onDashboardControllerChanged() =>
      scheduleCoalescedRebuild(_syncSelectionFromController);
}

class _DashboardScriptResultPreview extends StatelessWidget {
  const _DashboardScriptResultPreview({required this.text});

  final String? text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedSize(
      duration: _wrMotionEnabled(context) ? _kSwitchDuration : Duration.zero,
      curve: _kSwitchInCurve,
      child: text == null
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.06),
                  borderRadius: kOpenHandBorderRadius10,
                  border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle_outline_rounded,
                      size: 14,
                      color: cs.primary,
                    ),
                    kOpenHandHGap6,
                    Expanded(
                      child: SelectableText(
                        text!,
                        maxLines: 6,
                        style: const TextStyle(
                          fontFamily: kOpenHandMonospaceFontFamily,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _DashboardScriptWorkspace extends StatelessWidget {
  const _DashboardScriptWorkspace({
    required this.sidebarWidth,
    required this.libraryIcon,
    required this.libraryTitle,
    required this.createTooltip,
    required this.onCreate,
    required this.emptyLibraryLabel,
    required this.itemCount,
    required this.itemBuilder,
    required this.emptyEditorLabel,
    required this.editor,
  });

  final double sidebarWidth;
  final IconData libraryIcon;
  final String libraryTitle;
  final String createTooltip;
  final VoidCallback onCreate;
  final String emptyLibraryLabel;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final String emptyEditorLabel;
  final Widget? editor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final paneDecoration = BoxDecoration(
      color: colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(kOpenHandRadius16),
      border: Border.all(color: colorScheme.outlineVariant),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: sidebarWidth,
            child: Container(
              decoration: paneDecoration,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
                    child: Row(
                      children: [
                        Icon(libraryIcon, size: 16, color: colorScheme.primary),
                        kOpenHandHGap8,
                        Expanded(
                          child: Text(
                            libraryTitle,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: createTooltip,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          onPressed: onCreate,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: itemCount == 0
                        ? OpenHandInlineEmptyState(
                            message: emptyLibraryLabel,
                            dense: true,
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: itemCount,
                            separatorBuilder: (_, _) =>
                                kOpenHandGap2,
                            itemBuilder: itemBuilder,
                          ),
                  ),
                ],
              ),
            ),
          ),
          kOpenHandHGap12,
          Expanded(
            child: AnimatedContainer(
              duration: _wrMotionEnabled(context)
                  ? _kSwitchDuration
                  : Duration.zero,
              curve: _kSwitchInCurve,
              decoration: paneDecoration,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child:
                  editor ?? OpenHandInlineEmptyState(message: emptyEditorLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardToggleTile extends StatefulWidget {
  const _DashboardToggleTile({
    required this.title,
    required this.enabled,
    required this.selected,
    required this.onTap,
    required this.onToggle,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool enabled;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;

  @override
  State<_DashboardToggleTile> createState() => _DashboardToggleTileState();
}

class _DashboardToggleTileState extends State<_DashboardToggleTile>
    with OpenHandHoverState<_DashboardToggleTile> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final background = widget.selected
        ? cs.primary.withValues(alpha: 0.12)
        : (openHandHovered ? cs.surfaceContainerHighest : Colors.transparent);
    final border = widget.selected
        ? cs.primary.withValues(alpha: 0.45)
        : cs.outlineVariant.withValues(alpha: 0);
    final title = Text(
      widget.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: widget.enabled ? cs.onSurface : cs.onSurfaceVariant,
      ),
    );
    return MouseRegion(
      onEnter: (_) => setOpenHandHovered(true),
      onExit: (_) => setOpenHandHovered(false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: _wrMotionEnabled(context)
              ? kOpenHandMotion160
              : Duration.zero,
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
          decoration: BoxDecoration(
            color: background,
            borderRadius: kOpenHandBorderRadius10,
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.enabled
                      ? Colors.green.shade400
                      : cs.outlineVariant,
                ),
              ),
              kOpenHandHGap8,
              Expanded(
                child: widget.subtitle == null
                    ? title
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          title,
                          Text(
                            widget.subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
              ),
              Transform.scale(
                scale: 0.75,
                child: Switch(
                  value: widget.enabled,
                  onChanged: widget.onToggle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Web 逆向 CDP 仪表盘，统一承载浏览器、网络、控制台、源码和性能等面板。
/// 完整原生能力仍可通过「打开官方 DevTools」进入浏览器检查器。
Future<void> showWebReverseDashboardDialog(
  BuildContext context, {
  required WebReverseSessionController controller,
  required String sessionId,
  required Future<void> Function() onRestartBrowser,
  Future<bool> Function(bool enabled)? onCdpMcpEnabledChanged,
}) {
  return webReverseToolDialogs.show<void>(
    context: context,
    builder: (_) => _WebReverseDashboardDialog(
      controller: controller,
      sessionId: sessionId,
      onCdpMcpEnabledChanged: onCdpMcpEnabledChanged,
      onRestartBrowser: onRestartBrowser,
    ),
  );
}

class _WebReverseDashboardDialog extends StatefulWidget {
  const _WebReverseDashboardDialog({
    required this.controller,
    required this.sessionId,
    required this.onCdpMcpEnabledChanged,
    required this.onRestartBrowser,
  });
  final WebReverseSessionController controller;
  final String sessionId;
  final Future<bool> Function(bool enabled)? onCdpMcpEnabledChanged;
  final Future<void> Function() onRestartBrowser;

  @override
  State<_WebReverseDashboardDialog> createState() =>
      _WebReverseDashboardDialogState();
}

enum _Tab {
  browser,
  overview,
  network,
  console,
  sources,
  breakpoints,
  realtime,
  snippets,
  elements,
  hooks,
  crons,
  crypto,
  performance,
  memory,
  application,
  security,
  recorder,
}

class _WebReverseDashboardDialogState
    extends State<_WebReverseDashboardDialog> {
  static const int _browserTabRestoreConcurrency = 4;
  static const Duration _browserTabRestoreCommandTimeout = Duration(seconds: 6);
  static const Duration _browserTabRestoreTotalTimeout = Duration(seconds: 45);
  static const _kLastTabMetaKey = 'web_reverse_dashboard_last_tab';
  static const _kBrowserTabOrderMetaKey = 'web_reverse_browser_tab_order';
  static const _kBrowserTabUrlsMetaKey = 'web_reverse_browser_tab_urls';
  static const _kBrowserCurrentTargetMetaKey =
      'web_reverse_browser_current_target';
  static const _kReplHistoryMetaKey = 'web_reverse_console_repl_history';
  static const _kBreakpointsMetaKey = 'web_reverse_sources_breakpoints';
  // Stream E：除行断点外的其它 4 类 + pauseOnExceptions 也需要持久化。
  // 历史会话只写过 `_kBreakpointsMetaKey`（{url,line}），现已升级为
  // {url,line,condition?}；restoreBreakpoints 兼容旧格式。
  static const _kXhrBreakpointsMetaKey = 'web_reverse_xhr_breakpoints';
  static const _kEventListenerBreakpointsMetaKey =
      'web_reverse_event_listener_breakpoints';
  static const _kDomBreakpointsMetaKey = 'web_reverse_dom_breakpoints';
  static const _kCspBreakpointsMetaKey = 'web_reverse_csp_breakpoints';
  Future<void>? _browserTabRestoreTask;
  int? _browserTabsRestoredGeneration;
  static const _kPauseExceptionsMetaKey = 'web_reverse_pause_on_exceptions';
  static const _kInterceptRulesMetaKey = 'web_reverse_intercept_rules';
  static const _kLspCommandMetaKey = 'web_reverse_lsp_command';
  static const _kLspArgsMetaKey = 'web_reverse_lsp_args';
  static const _kHeapSnapAMetaKey = 'web_reverse_memory_snap_a';
  static const _kHeapSnapBMetaKey = 'web_reverse_memory_snap_b';
  static const _kSnippetsMetaKey = 'web_reverse_snippets';
  static const _kHooksMetaKey = 'web_reverse_hooks';
  static const _kCronsMetaKey = 'web_reverse_crons';
  _Tab _tab = _Tab.network;
  bool _cdpMcpToggleBusy = false;

  // Network 面板状态
  String _networkFilter = '';
  _ResourceFilter _resourceFilter = _ResourceFilter.all;
  CdpNetworkEntry? _selectedRequest;
  final TextEditingController _filterCtrl = TextEditingController();

  // dashboard 上次记录的请求计数；用于 AnimatedList 增量插入。
  int _lastNetworkSize = 0;
  int _lastInspectorRevision = -1;
  // 上次 rebuild 时记录的 dashboard 关键计数 / 状态；只有这些值变化才整体
  // rebuild 头部 / toolbar，避免 60fps screencast 帧把 dashboard 拖进
  // setState 旋涡。
  int _lastConsoleSize = 0;
  int _lastErrorCount = 0;
  bool _lastIsRunning = false;
  String _lastErrMsg = '';
  // 上次记录的浏览器面板 tab 列表标识：targets 数量 / currentId 任一变化
  // 即让 _BrowserBody 整体 rebuild 拿到新 tab strip。
  int _lastTabsLen = 0;
  String? _lastCurTabId;
  // tab 页面上的调整“顺序”与“标题”不改变 length / current，需要用轻量
  // 指纹触发 dashboard rebuild，否则 `_TabStrip` 不会拿到新 list。
  int _lastTabsOrderHash = 0;
  int _lastTabsTitleHash = 0;
  final GlobalKey<AnimatedListState> _networkListKey =
      GlobalKey<AnimatedListState>();
  // Sources 面板 GlobalKey：Initiator 中点击栈帧 / 重定向链时，
  // controller.sourceJumpRequest 触发，dashboard 切到 Sources tab
  // 后再通过这个 key 调 `_SourcesPanelState.requestJumpTo(url,line,col)`
  // 完成「选择脚本 → 滚动到目标行 → 高亮」。
  final GlobalKey<_SourcesPanelState> _sourcesPanelKey =
      GlobalKey<_SourcesPanelState>();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    widget.controller.sourceJumpRequest.addListener(_onSourceJumpRequested);
    _lastNetworkSize = widget.controller.networkRequestCount;
    _lastInspectorRevision = widget.controller.inspectorRevision;
    _lastConsoleSize = widget.controller.consoleMessageCount;
    _lastErrorCount = widget.controller.errorCount;
    _lastIsRunning = widget.controller.isRunning;
    _lastErrMsg = widget.controller.errorMessage ?? '';
    _lastTabsLen = widget.controller.pageTargets.length;
    _lastCurTabId = widget.controller.currentPageTargetId;
    _lastTabsOrderHash = _pageTargetsOrderHash(widget.controller.pageTargets);
    _lastTabsTitleHash = _pageTargetsTitleHash(widget.controller.pageTargets);
    // 读取上次离开 dashboard 时停在的 tab。会话维度持久化到 metadata，
    // 用 enum.name 序列化；解析失败 / 没记录时保持 _Tab.network 默认。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final session = _dashboardSession();
      if (session == null) return;
      final raw = session.metadata[_kLastTabMetaKey];
      if (raw is String && raw.isNotEmpty) {
        for (final t in _Tab.values) {
          if (t.name == raw) {
            setState(() => _tab = t);
            break;
          }
        }
      }
      // 应用上次记录的 tab 顺序。
      final orderRaw = session.metadata[_kBrowserTabOrderMetaKey];
      if (orderRaw is List) {
        widget.controller.applyPageTargetOrder(orderRaw);
      }
      // 恢复 REPL 命令历史。
      final replRaw = session.metadata[_kReplHistoryMetaKey];
      if (replRaw is List) {
        final hist = replRaw.whereType<String>().toList(growable: false);
        if (hist.isNotEmpty) widget.controller.replaceReplHistory(hist);
      }
      // 恢复网络拦截规则。
      final rulesRaw = session.metadata[_kInterceptRulesMetaKey];
      if (rulesRaw is List) {
        final rules = rulesRaw
            .whereType<Map>()
            .map(
              (m) =>
                  WebReverseInterceptRule.fromJson(stringKeyedMapFromValue(m)),
            )
            .toList(growable: false);
        if (rules.isNotEmpty) widget.controller.setInterceptRules(rules);
      }
      // 恢复 snippet pad 内容。
      final snipRaw = session.metadata[_kSnippetsMetaKey];
      if (snipRaw is List) {
        final snips = snipRaw
            .whereType<Map>()
            .map((m) => WebReverseSnippet.fromJson(stringKeyedMapFromValue(m)))
            .where((s) => s.id.isNotEmpty)
            .toList(growable: false);
        if (snips.isNotEmpty) widget.controller.replaceSnippets(snips);
      }
      // 恢复 JS Hook 库。replaceHooks 会按 enabled 重新装载。
      final hookRaw = session.metadata[_kHooksMetaKey];
      if (hookRaw is List) {
        final hooks = hookRaw
            .whereType<Map>()
            .map((m) => WebReverseHook.fromJson(stringKeyedMapFromValue(m)))
            .where((h) => h.id.isNotEmpty)
            .toList(growable: false);
        if (hooks.isNotEmpty) unawaited(widget.controller.replaceHooks(hooks));
      }
      // 恢复定时任务。replaceCrons 会按 enabled 重新 schedule。
      final cronRaw = session.metadata[_kCronsMetaKey];
      if (cronRaw is List) {
        final crons = cronRaw
            .whereType<Map>()
            .map((m) => WebReverseCron.fromJson(stringKeyedMapFromValue(m)))
            .where((c) => c.id.isNotEmpty)
            .toList(growable: false);
        if (crons.isNotEmpty) unawaited(widget.controller.replaceCrons(crons));
      }
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    widget.controller.sourceJumpRequest.removeListener(_onSourceJumpRequested);
    _filterCtrl.dispose();
    super.dispose();
  }

  AiSession? _dashboardSession() {
    final sessions = context.read<AiSessionController>().sessions;
    for (final session in sessions) {
      if (session.id == widget.sessionId) return session;
    }
    return null;
  }

  WebReverseSessionConfig? _dashboardConfig() {
    final session = _dashboardSession();
    if (session == null) return null;
    return WebReverseSessionConfig.fromJson(
      session.metadata['web_reverse_config'],
    );
  }

  bool get _cdpMcpEnabled => _dashboardConfig()?.cdpMcpEnabled == true;

  Future<void> _setCdpMcpEnabled(bool enabled) async {
    if (_cdpMcpToggleBusy) return;
    final updater = widget.onCdpMcpEnabledChanged;
    if (updater == null) {
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '当前窗口无法更新 MCP 设置',
          zhHant: '目前視窗無法更新 MCP 設定',
          en: 'This window cannot update MCP settings',
          fr: 'Cette fenêtre ne peut pas mettre à jour les réglages MCP',
          de: 'Dieses Fenster kann die MCP-Einstellungen nicht aktualisieren',
          ja: 'このウィンドウでは MCP 設定を更新できません',
        ),
        duration: kOpenHandSnackBarBriefDuration,
      );
      return;
    }
    setState(() => _cdpMcpToggleBusy = true);
    var ok = false;
    try {
      ok = await updater(enabled).timeout(const Duration(seconds: 12));
    } catch (error, stack) {
      silentLog(
        'web_reverse_dashboard_dialog',
        '切换 CDP MCP 状态：$enabled',
        error,
        stack,
      );
    } finally {
      if (mounted) setState(() => _cdpMcpToggleBusy = false);
    }
    if (!mounted) return;
    if (!ok) {
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: 'AI 侧 CDP MCP 设置更新失败',
          zhHant: 'AI 側 CDP MCP 設定更新失敗',
          en: 'Failed to update AI-side CDP MCP',
          fr: 'Échec de la mise à jour du MCP CDP côté IA',
          de: 'AI-seitiges CDP-MCP konnte nicht aktualisiert werden',
          ja: 'AI 側 CDP MCP 設定の更新に失敗しました',
        ),
        duration: kOpenHandSnackBarBriefDuration,
      );
      return;
    }
    showOpenHandInfoSnack(
      context,
      enabled
          ? openHandLocalizedText(
              context,
              zh: '已启用 AI 侧 CDP MCP，正在后台准备工具目录',
              zhHant: '已啟用 AI 側 CDP MCP，正在背景準備工具目錄',
              en: 'AI-side CDP MCP enabled; preparing tools in background',
              fr: 'MCP CDP côté IA activé ; préparation des outils en arrière-plan',
              de: 'AI-seitiges CDP-MCP aktiviert; Tools werden im Hintergrund vorbereitet',
              ja: 'AI 側 CDP MCP を有効化しました。バックグラウンドでツールを準備しています',
            )
          : openHandLocalizedText(
              context,
              zh: '已禁用 AI 侧 CDP MCP，并停止本会话临时 MCP',
              zhHant: '已停用 AI 側 CDP MCP，並停止本會話臨時 MCP',
              en: 'AI-side CDP MCP disabled; transient MCP stopped',
              fr: 'MCP CDP côté IA désactivé ; MCP temporaire arrete',
              de: 'AI-seitiges CDP-MCP deaktiviert; temporares MCP gestoppt',
              ja: 'AI 側 CDP MCP を無効化し、このセッションの一時 MCP を停止しました',
            ),
      duration: kOpenHandSnackBarBriefDuration,
    );
  }

  /// 当 Initiator 区段点击栈帧 / 重定向链时被调用：先把当前 tab 切到
  /// Sources，post-frame 后再 dispatch 到 `_SourcesPanelState`，最后
  /// 清空 controller 上的 sourceJumpRequest 防止下次重入误触发。
  void _onSourceJumpRequested() {
    final req = widget.controller.sourceJumpRequest.value;
    if (req == null || !mounted) return;
    if (_tab != _Tab.sources) setState(() => _tab = _Tab.sources);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _sourcesPanelKey.currentState?.requestJumpTo(
        url: req.url,
        line: req.line,
        col: req.col,
      );
      widget.controller.clearSourceJumpRequest();
    });
  }

  void _onChanged() {
    if (!mounted) return;
    final ctrl = widget.controller;
    final newSize = ctrl.networkRequestCount;
    final newConsole = ctrl.consoleMessageCount;
    final newRevision = ctrl.inspectorRevision;
    final newErr = ctrl.errorCount;
    final newRunning = ctrl.isRunning;
    final newErrMsg = ctrl.errorMessage ?? '';
    final newTabsLen = ctrl.pageTargets.length;
    final newCurTab = ctrl.currentPageTargetId;
    final newTabsOrderHash = _pageTargetsOrderHash(ctrl.pageTargets);
    final newTabsTitleHash = _pageTargetsTitleHash(ctrl.pageTargets);
    // 关键：screencast 帧抵达不会改变这些计数，所以这里就早退。让浏览器
    // 面板内的 [_ScreencastImage] 自行 AnimatedBuilder 局部 repaint。
    final dashboardDirty =
        newRevision != _lastInspectorRevision ||
        newSize != _lastNetworkSize ||
        newConsole != _lastConsoleSize ||
        newErr != _lastErrorCount ||
        newRunning != _lastIsRunning ||
        newErrMsg != _lastErrMsg ||
        newTabsLen != _lastTabsLen ||
        newCurTab != _lastCurTabId ||
        newTabsOrderHash != _lastTabsOrderHash ||
        newTabsTitleHash != _lastTabsTitleHash;
    if (newSize > _lastNetworkSize) {
      // FIFO 淘汰时 networkRequests 头部会被砍掉，导致新条目实际索引小于 newSize-1；
      // 这里只对追加场景做 AnimatedList 的 insert，不去精细同步淘汰，依赖 ValueKey
      // 让 list 在被打断时安全 rebuild（_NetworkBody 在过滤变化时也会整体 rebuild）。
      final delta = newSize - _lastNetworkSize;
      final state = _networkListKey.currentState;
      if (state != null) {
        for (var i = 0; i < delta; i++) {
          state.insertItem(_lastNetworkSize + i, duration: _kSwitchDuration);
        }
      }
    }
    _lastNetworkSize = newSize;
    _lastInspectorRevision = newRevision;
    _lastConsoleSize = newConsole;
    _lastErrorCount = newErr;
    _lastIsRunning = newRunning;
    _lastErrMsg = newErrMsg;
    _lastTabsLen = newTabsLen;
    _lastCurTabId = newCurTab;
    _lastTabsOrderHash = newTabsOrderHash;
    _lastTabsTitleHash = newTabsTitleHash;
    if (dashboardDirty) setState(() {});
  }

  /// 让 part 文件能从外部触发 dashboard 重建（part 文件不能直接调 setState）。
  void rebuildFromExternal(VoidCallback mutate) {
    setState(mutate);
  }

  Future<void> _persistSessionMetadata(
    Map<String, Object?> metadata, {
    required String action,
  }) async {
    if (!mounted) return;
    final session = context.read<AiSessionController>();
    try {
      await session.updateSessionMetadata(widget.sessionId, metadata);
    } catch (error, stack) {
      silentLog('web_reverse_dashboard_dialog', action, error, stack);
    }
  }

  /// 切换 tab 并把选择持久化到 session metadata，下次打开 dashboard 自动恢复。
  void _setTab(_Tab next) {
    if (next == _tab) return;
    setState(() => _tab = next);
    // 异步写回 metadata，失败不阻塞 UI；merge 写入避免覆盖其它键。
    unawaited(
      _persistSessionMetadata(<String, Object?>{
        _kLastTabMetaKey: next.name,
      }, action: '保存 Dashboard 标签页'),
    );
  }

  /// 浏览器刚拉起时由 _BrowserBody 调用：把上次持久化的 URL 列表逐条
  /// `Page.navigate` / `createTarget` 恢复到当前浏览器实例。已有的第一个
  /// target 复用 navigate；其余全部 createTarget。单 target 超时 6s 兜底，
  /// 整体不阻塞 UI。
  Future<void> restoreBrowserTabs() {
    if (!mounted || !widget.controller.isBrowserAlive) {
      return Future<void>.value();
    }
    final generation = widget.controller.cdpConnectionGeneration;
    if (_browserTabsRestoredGeneration == generation) {
      return Future<void>.value();
    }
    final pending = _browserTabRestoreTask;
    if (pending != null) return pending;
    late final Future<void> task;
    task = _restoreBrowserTabs().whenComplete(() {
      if (identical(_browserTabRestoreTask, task)) {
        _browserTabRestoreTask = null;
      }
      if (widget.controller.cdpConnectionGeneration == generation) {
        _browserTabsRestoredGeneration = generation;
      } else if (mounted && widget.controller.isBrowserAlive) {
        unawaited(restoreBrowserTabs());
      }
    });
    _browserTabRestoreTask = task;
    return task;
  }

  Future<void> _restoreBrowserTabs() async {
    if (!mounted) return;
    final session = _dashboardSession();
    if (session == null) return;
    final urlsRaw = session.metadata[_kBrowserTabUrlsMetaKey];
    final orderRaw = session.metadata[_kBrowserTabOrderMetaKey];
    final wantUrls = normalizeWebReverseTabRestoreUrls(orderRaw, urlsRaw);
    if (wantUrls.isEmpty) return;
    final ctrl = widget.controller;
    final hasFirst = ctrl.pageTargets.isNotEmpty;
    final restoreStopwatch = Stopwatch()..start();
    if (hasFirst) {
      try {
        await ctrl
            .navigate(wantUrls.first)
            .timeout(_browserTabRestoreCommandTimeout);
      } catch (error, stack) {
        silentLog(
          'web_reverse_dashboard_dialog',
          '恢复首个页面：${wantUrls.first}',
          error,
          stack,
        );
      }
    }
    final startIndex = hasFirst ? 1 : 0;
    await forEachIndexWithConcurrencyLimit(
      itemCount: wantUrls.length - startIndex,
      maxConcurrency: _browserTabRestoreConcurrency,
      shouldContinue: () =>
          mounted &&
          ctrl.isBrowserAlive &&
          restoreStopwatch.elapsed < _browserTabRestoreTotalTimeout,
      task: (offset) async {
        final url = wantUrls[startIndex + offset];
        try {
          await ctrl
              .createPageTarget(url: url)
              .timeout(_browserTabRestoreCommandTimeout);
        } catch (error, stack) {
          silentLog('web_reverse_dashboard_dialog', '恢复页面：$url', error, stack);
        }
      },
    );
  }

  /// 持久化 console REPL 历史到 session metadata，控制台面板每次执行命令
  /// 都会调用一次。fire-and-forget 不阻塞 UI。
  void persistConsoleReplHistory() {
    if (!mounted) return;
    unawaited(
      _persistSessionMetadata(<String, Object?>{
        _kReplHistoryMetaKey: widget.controller.replHistory,
      }, action: '保存控制台历史'),
    );
  }

  /// 持久化 Sources tab 用户设过的断点。Sources 面板每次 set/remove 后调一次。
  /// Stream E：除行断点外，DOM / EventListener / XHR / CSP / pauseOnExceptions
  /// 也会一并写入 session metadata，下次打开 dashboard 时由 restoreBreakpoints
  /// 恢复。行断点条件表达式同样持久化（注意：仅写到本会话 metadata 不会随
  /// share 导出）。
  void persistBreakpoints() {
    if (!mounted) return;
    final c = widget.controller;
    final bps = c.userBreakpoints
        .map((b) {
          final cond = c.breakpointCondition(url: b.url, line: b.line);
          return <String, Object?>{
            'url': b.url,
            'line': b.line,
            if (cond.isNotEmpty) 'condition': cond,
          };
        })
        .toList(growable: false);
    final dom = c.domBreakpoints
        .map((b) => <String, Object?>{'selector': b.selector, 'type': b.type})
        .toList(growable: false);
    unawaited(
      _persistSessionMetadata(<String, Object?>{
        _kBreakpointsMetaKey: bps,
        _kXhrBreakpointsMetaKey: c.xhrBreakpoints.toList(growable: false),
        _kEventListenerBreakpointsMetaKey: c.eventListenerBreakpoints.toList(
          growable: false,
        ),
        _kDomBreakpointsMetaKey: dom,
        _kCspBreakpointsMetaKey: c.cspViolationBreakpoints.toList(
          growable: false,
        ),
        _kPauseExceptionsMetaKey: c.pauseOnExceptions,
      }, action: '保存 Sources 断点'),
    );
  }

  /// 持久化脚本注入库。snippet 增删改后立即调一次，写回 session metadata。
  void persistSnippets() {
    if (!mounted) return;
    final items = widget.controller.snippets
        .map((s) => s.toJson())
        .toList(growable: false);
    unawaited(
      _persistSessionMetadata(<String, Object?>{
        _kSnippetsMetaKey: items,
      }, action: '保存脚本注入库'),
    );
  }

  /// 持久化 JS Hook 库。hook 新增 / 启用 / 编辑 / 删除后立即调一次。
  void persistHooks() {
    if (!mounted) return;
    final items = widget.controller.hooks
        .map((h) => h.toJson())
        .toList(growable: false);
    unawaited(
      _persistSessionMetadata(<String, Object?>{
        _kHooksMetaKey: items,
      }, action: '保存 JavaScript Hook'),
    );
  }

  /// 持久化定时任务。cron 增删改 / 启禁后立即调一次。
  void persistCrons() {
    if (!mounted) return;
    final items = widget.controller.crons
        .map((c) => c.toJson())
        .toList(growable: false);
    unawaited(
      _persistSessionMetadata(<String, Object?>{
        _kCronsMetaKey: items,
      }, action: '保存定时任务'),
    );
  }

  /// 持久化网络拦截规则。规则编辑 dialog 保存时调一次。
  void persistInterceptRules() {
    if (!mounted) return;
    final rules = widget.controller.interceptRules
        .map((r) => r.toJson())
        .toList(growable: false);
    unawaited(
      _persistSessionMetadata(<String, Object?>{
        _kInterceptRulesMetaKey: rules,
      }, action: '保存网络拦截规则'),
    );
  }

  /// 读取本会话曾保存过的 LSP 命令配置（命令名 + args 列表）。
  ({String command, List<String> args})? readLspConfig() {
    if (!mounted) return null;
    final session = _dashboardSession();
    if (session == null) return null;
    final cmd = session.metadata[_kLspCommandMetaKey];
    final args = session.metadata[_kLspArgsMetaKey];
    if (cmd is! String || cmd.trim().isEmpty) return null;
    final argList = stringListFromValue(args);
    return (command: cmd.trim(), args: argList);
  }

  /// 持久化 LSP 配置，立即落盘 session metadata。
  void persistLspConfig({required String command, required List<String> args}) {
    if (!mounted) return;
    unawaited(
      _persistSessionMetadata(<String, Object?>{
        _kLspCommandMetaKey: command.trim(),
        _kLspArgsMetaKey: args,
      }, action: '保存 LSP 配置'),
    );
  }

  /// 持久化最近两个 heap snapshot：A/B 两个槽位，存的是 raw json + 对应
  /// metadata（采集时间戳、字节数）。下次打开 Dashboard 时由 Memory 面板
  /// 自行 readHeapSnapshots 读回。
  void persistHeapSnapshots({
    required ({String json, int bytes, DateTime ts})? snapA,
    required ({String json, int bytes, DateTime ts})? snapB,
  }) {
    if (!mounted) return;
    Map<String, Object?>? toJson(({String json, int bytes, DateTime ts})? s) {
      if (s == null) return null;
      return <String, Object?>{
        'json': s.json,
        'bytes': s.bytes,
        'ts_ms': s.ts.millisecondsSinceEpoch,
      };
    }

    unawaited(
      _persistSessionMetadata(<String, Object?>{
        _kHeapSnapAMetaKey: toJson(snapA),
        _kHeapSnapBMetaKey: toJson(snapB),
      }, action: '保存堆快照'),
    );
  }

  /// 读回上次保存的 heap snapshots。任一槽位无效时返回 null。
  ({
    ({String json, int bytes, DateTime ts})? snapA,
    ({String json, int bytes, DateTime ts})? snapB,
  })?
  readHeapSnapshots() {
    if (!mounted) return null;
    final session = _dashboardSession();
    if (session == null) return null;
    ({String json, int bytes, DateTime ts})? parse(Object? raw) {
      final map = stringKeyedMapFromValue(raw);
      if (map.isEmpty) return null;
      final json = map['json'];
      final bytes = nonNegativeIntFromValue(map['bytes'], fallback: 0);
      final tsMs = optionalIntFromValue(map['ts_ms']);
      if (json is! String || json.isEmpty || tsMs == null) return null;
      return (
        json: json,
        bytes: bytes,
        ts: DateTime.fromMillisecondsSinceEpoch(tsMs),
      );
    }

    final a = parse(session.metadata[_kHeapSnapAMetaKey]);
    final b = parse(session.metadata[_kHeapSnapBMetaKey]);
    if (a == null && b == null) return null;
    return (snapA: a, snapB: b);
  }

  /// 浏览器从 dead 切回 alive 时调用：恢复持久化的断点（先 enableDebugger）。
  /// Stream E：除行断点外，依次恢复 pauseOnExceptions / XHR / EventListener /
  /// DOM / CSP；任何单项失败用 silentLog 吞掉，确保后续步骤继续。DOM 断点
  /// 依赖目标 selector 在页面上能 querySelector 到；若 selector 已失效则跳
  /// 过——下次手动添加即可。
  Future<void> restoreBreakpoints() async {
    if (!mounted) return;
    final session = _dashboardSession();
    if (session == null) return;
    final meta = session.metadata;
    final rawBps = meta[_kBreakpointsMetaKey];
    final rawXhr = meta[_kXhrBreakpointsMetaKey];
    final rawEvent = meta[_kEventListenerBreakpointsMetaKey];
    final rawDom = meta[_kDomBreakpointsMetaKey];
    final rawCsp = meta[_kCspBreakpointsMetaKey];
    final rawPause = meta[_kPauseExceptionsMetaKey];
    final hasAny =
        (rawBps is List && rawBps.isNotEmpty) ||
        (rawXhr is List && rawXhr.isNotEmpty) ||
        (rawEvent is List && rawEvent.isNotEmpty) ||
        (rawDom is List && rawDom.isNotEmpty) ||
        (rawCsp is List && rawCsp.isNotEmpty) ||
        (rawPause is String && rawPause != 'none');
    if (!hasAny) return;
    await widget.controller.enableDebugger();
    final c = widget.controller;

    // 恢复异常暂停模式。
    if (rawPause is String && (rawPause == 'uncaught' || rawPause == 'all')) {
      try {
        await c.setPauseOnExceptions(rawPause);
      } catch (error, stack) {
        silentLog('web_reverse_dashboard_dialog', '恢复暂停模式', error, stack);
      }
    }
    // 行断点（含 condition）。旧格式只有 url/line 时 condition 缺省。
    if (rawBps is List) {
      for (final item in rawBps.take(
        WebReverseSessionController.maxSourceBreakpoints,
      )) {
        if (item is! Map) continue;
        final url = '${item['url'] ?? ''}';
        final line = intFromValue(item['line'], fallback: -1);
        final condition = (item['condition'] as String?)?.trim() ?? '';
        if (url.isEmpty || line < 0) continue;
        try {
          await c.setBreakpointByUrl(
            url: url,
            lineNumber: line,
            condition: condition.isEmpty ? null : condition,
          );
        } catch (error, stack) {
          silentLog(
            'web_reverse_dashboard_dialog',
            '恢复断点：$url:$line',
            error,
            stack,
          );
        }
      }
    }
    if (rawXhr is List) {
      for (final s in rawXhr.take(
        WebReverseSessionController.maxXhrBreakpoints,
      )) {
        if (s is! String) continue;
        try {
          await c.addXhrBreakpoint(s);
        } catch (error, stack) {
          silentLog(
            'web_reverse_dashboard_dialog',
            '恢复 XHR 断点：$s',
            error,
            stack,
          );
        }
      }
    }
    if (rawEvent is List) {
      for (final s in rawEvent.take(
        WebReverseSessionController.maxEventListenerBreakpoints,
      )) {
        if (s is! String || s.isEmpty) continue;
        try {
          await c.setEventListenerBreakpoint(s);
        } catch (error, stack) {
          silentLog('web_reverse_dashboard_dialog', '恢复事件断点：$s', error, stack);
        }
      }
    }
    if (rawDom is List) {
      for (final item in rawDom.take(
        WebReverseSessionController.maxDomBreakpoints,
      )) {
        if (item is! Map) continue;
        final sel = '${item['selector'] ?? ''}';
        final t = '${item['type'] ?? ''}';
        if (sel.isEmpty || t.isEmpty) continue;
        try {
          await c.addDomBreakpoint(selector: sel, type: t);
        } catch (error, stack) {
          silentLog(
            'web_reverse_dashboard_dialog',
            '恢复 DOM 断点：$sel',
            error,
            stack,
          );
        }
      }
    }
    if (rawCsp is List) {
      final types = <String>{};
      for (final s in rawCsp.take(2)) {
        if (s is String && s.isNotEmpty) types.add(s);
      }
      if (types.isNotEmpty) {
        try {
          await c.setCspViolationBreakpoints(types);
        } catch (error, stack) {
          silentLog('web_reverse_dashboard_dialog', '恢复 CSP 断点', error, stack);
        }
      }
    }
  }

  /// 持久化浏览器面板状态：当前 tab 顺序 + 每个 target 的最后 URL。下次
  /// 重启浏览器（会话 / Chrome 进程级）时上层用这个数据恢复用户操作场景。
  /// 给 [_BrowserBodyState] 通过 ancestor lookup 调用。
  Future<void> persistBrowserPanelState() async {
    if (!mounted) return;
    final ctrl = widget.controller;
    final order = ctrl.pageTargetOrder;
    final currentId = ctrl.currentPageTargetId;
    // 尝试拉每个 target 的真实 URL；失败则用 snapshot 里的。控制总耗时
    // ≤ 500ms，超时即用 snapshot。
    final urls = <String, String>{};
    CdpPageTargetSnapshot? currentTarget;
    for (final t in ctrl.pageTargets) {
      urls[t.id] = t.url;
      if (t.id == currentId) currentTarget = t;
    }
    unawaited(
      _persistSessionMetadata(<String, Object?>{
        _kBrowserTabOrderMetaKey: order,
        _kBrowserTabUrlsMetaKey: urls,
        _kBrowserCurrentTargetMetaKey: currentTarget == null
            ? null
            : <String, Object?>{
                'id': currentTarget.id,
                'url': currentTarget.url,
                'title': currentTarget.title,
              },
      }, action: '保存浏览器标签页'),
    );
  }

  bool _isZh() => openHandIsChineseLocale(context);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final reduceMotion = !_wrMotionEnabled(context);
    final ctrl = widget.controller;
    final isZh = _isZh();
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        // Cmd+Shift+R / Ctrl+Shift+R 启停 Recorder。
        const SingleActivator(
          LogicalKeyboardKey.keyR,
          meta: true,
          shift: true,
        ): () =>
            _toggleRecorder(ctrl),
        const SingleActivator(
          LogicalKeyboardKey.keyR,
          control: true,
          shift: true,
        ): () =>
            _toggleRecorder(ctrl),
        // Shift + ? 打开快捷键速查面板。`?` 在大多数键盘上需要 shift+/，
        // SingleActivator 的 includeRepeats 默认 true 不影响这里。
        const SingleActivator(LogicalKeyboardKey.slash, shift: true): () =>
            _showShortcutsHelp(),
      },
      // 注意：不要在这里包 `Focus(autofocus: true)` —— 它会抢走对话框内
      // TextField 的初始焦点，且会让 macOS IMK 上下文持续失效，导致此后
      // 任何 TextField 都无法输入 / 复制 / 粘贴。Dialog 由 showAnimatedDialog
      // 套上 `_EscapeDismissDialogScope` 提供 ESC 关闭，ModalRoute 自身的
      // 焦点 scope 已足以让 CallbackShortcuts 接收到键盘事件。
      child: buildOpenHandToolDialogShell(
        context: context,
        maxWidth: kOpenHandDialogWidthFull,
        maxHeight: kOpenHandDialogHeightTall,
        insetPadding: _kDashboardDialogInsetPadding,
        backgroundColor: cs.surfaceContainer,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          // 关键：所有子项横向拉到 Dialog 全宽，避免不同 tab 切换时
          // body 内容更窄导致 Column 把 toolbar 行整体回缩并重新居中
          // （Network 行能拉满工具条变左对齐；Console / 性能行 body 窄、
          // 工具条又默认 MainAxisSize.min，外层 stretch 会强制铺满）。
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(theme, cs, isZh),
            Divider(height: 1, color: cs.outlineVariant),
            AnimatedSize(
              duration: reduceMotion ? Duration.zero : _kSwitchDuration,
              curve: _kSwitchInCurve,
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: reduceMotion ? Duration.zero : _kSwitchDuration,
                switchInCurve: _kSwitchInCurve,
                switchOutCurve: _kSwitchOutCurve,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SizeTransition(
                    sizeFactor: animation,
                    axisAlignment: -1,
                    child: child,
                  ),
                ),
                child: (ctrl.errorMessage ?? '').trim().isNotEmpty
                    ? _DiagnosisBanner(
                        key: const ValueKey('diagnosis-banner'),
                        controller: ctrl,
                        reduceMotion: reduceMotion,
                      )
                    : const SizedBox.shrink(
                        key: ValueKey('diagnosis-banner-empty'),
                      ),
              ),
            ),
            _buildToolbar(theme, cs, isZh, ctrl, reduceMotion),
            Divider(height: 1, color: cs.outlineVariant),
            Expanded(
              child: AnimatedSwitcher(
                duration: reduceMotion ? Duration.zero : _kSwitchDuration,
                switchInCurve: _kSwitchInCurve,
                switchOutCurve: _kSwitchOutCurve,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.02),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey<_Tab>(_tab),
                  child: _buildBody(theme, cs, isZh, ctrl, reduceMotion),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shift + ? 打开快捷键速查面板：分类列出 dashboard / 浏览器面板 /
  /// recorder / network 等所有键盘快捷键。
  void _showShortcutsHelp() {
    webReverseToolDialogs.show<void>(
      context: context,
      builder: (_) => const _ShortcutsHelpDialog(),
    );
  }

  Future<void> _toggleRecorder(WebReverseSessionController ctrl) async {
    if (ctrl.isRecording) {
      await ctrl.stopRecording();
    } else {
      await ctrl.startRecording();
    }
    if (!mounted) return;
    showOpenHandInfoSnack(
      context,
      ctrl.isRecording
          ? openHandLocalizedText(
              context,
              zh: '已开始录制（Cmd+Shift+R 再次按下停止）',
              zhHant: '已開始錄製（Cmd+Shift+R 再次按下停止）',
              en: 'Recording started',
              fr: 'Enregistrement démarré',
              de: 'Aufzeichnung gestartet',
              ja: '録画を開始しました',
            )
          : openHandLocalizedText(
              context,
              zh: '已停止录制',
              zhHant: '已停止錄製',
              en: 'Recording stopped',
              fr: 'Enregistrement arrêté',
              de: 'Aufzeichnung gestoppt',
              ja: '録画を停止しました',
            ),
      duration: kOpenHandSnackBarBriefDuration,
    );
  }

  Widget _buildHeader(ThemeData theme, ColorScheme cs, bool isZh) {
    final ctrl = widget.controller;
    final version = ctrl.browserVersion ?? '-';
    final cdpRuntimeMeta = context.select<AiSessionController, Object?>((
      controller,
    ) {
      for (final session in controller.sessions) {
        if (session.id == widget.sessionId) {
          return webReverseCurrentCdpRuntimeMetadata(session.metadata);
        }
      }
      return null;
    });
    final bridgeStatus = _CdpMcpBridgeHeaderStatus.fromRuntime(
      context,
      cdpRuntimeMeta,
      controller: ctrl,
    );
    final cdpMcpEnabled = _cdpMcpEnabled;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: kOpenHandBorderRadius10,
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.travel_explore_rounded,
              color: cs.onPrimaryContainer,
              size: 20,
            ),
          ),
          kOpenHandHGap12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  openHandLocalizedText(
                    context,
                    zh: 'Web 逆向调试面板',
                    zhHant: 'Web 逆向除錯面板',
                    en: 'Web Reverse Debugger',
                    fr: 'Débogueur Web reverse',
                    de: 'Web-Reverse-Debugger',
                    ja: 'Web リバースデバッガー',
                  ),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                kOpenHandGap2,
                Text(
                  _cdpHeaderSubtitle(ctrl, version),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          kOpenHandHGap10,
          _CdpMcpBridgeToggle(
            enabled: cdpMcpEnabled,
            busy: _cdpMcpToggleBusy,
            reduceMotion: !_wrMotionEnabled(context),
            onChanged: _setCdpMcpEnabled,
          ),
          kOpenHandHGap6,
          _CdpMcpBridgeStatusPill(
            status: bridgeStatus,
            reduceMotion: !_wrMotionEnabled(context),
          ),
          kOpenHandHGap6,
          IconButton(
            tooltip: openHandCloseLabel(context),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  String _cdpHeaderSubtitle(WebReverseSessionController ctrl, String version) {
    final normalizedVersion = nonBlankStringOr(version, '-');
    final port = ctrl.cdpPort;
    final cdpLabel = ctrl.isBrowserAlive
        ? port == null
              ? openHandLocalizedText(
                  context,
                  zh: 'CDP 待同步',
                  zhHant: 'CDP 待同步',
                  en: 'CDP pending',
                  fr: 'CDP en attente',
                  de: 'CDP ausstehend',
                  ja: 'CDP 同期待ち',
                )
              : 'CDP :$port'
        : port == null
        ? openHandLocalizedText(
            context,
            zh: 'CDP 离线',
            zhHant: 'CDP 離線',
            en: 'CDP offline',
            fr: 'CDP hors ligne',
            de: 'CDP offline',
            ja: 'CDP オフライン',
          )
        : openHandLocalizedText(
            context,
            zh: 'CDP 离线 · 上次 :$port',
            zhHant: 'CDP 離線 · 上次 :$port',
            en: 'CDP offline · last :$port',
            fr: 'CDP hors ligne · dernier :$port',
            de: 'CDP offline · zuletzt :$port',
            ja: 'CDP オフライン · 前回 :$port',
          );
    return '$normalizedVersion · $cdpLabel';
  }

  Widget _buildBody(
    ThemeData theme,
    ColorScheme cs,
    bool isZh,
    WebReverseSessionController ctrl,
    bool reduceMotion,
  ) {
    return switch (_tab) {
      _Tab.browser => _BrowserBody(
        controller: ctrl,
        onRestartBrowser: widget.onRestartBrowser,
      ),
      _Tab.overview => _OverviewBody(controller: ctrl),
      _Tab.network => _NetworkBody(
        state: this,
        controller: ctrl,
        isZh: isZh,
        reduceMotion: reduceMotion,
      ),
      _Tab.console => _ConsoleBody(
        controller: ctrl,
        filter: _networkFilter,
        reduceMotion: reduceMotion,
      ),
      _Tab.sources => _SourcesPanel(
        key: _sourcesPanelKey,
        controller: ctrl,
        reduceMotion: reduceMotion,
      ),
      _Tab.snippets => _SnippetsBody(
        controller: ctrl,
        onPersist: persistSnippets,
      ),
      _Tab.elements => _ElementsBody(
        controller: ctrl,
        reduceMotion: reduceMotion,
      ),
      _Tab.hooks => _HooksBody(controller: ctrl, onPersist: persistHooks),
      _Tab.crons => _CronsBody(controller: ctrl, onPersist: persistCrons),
      _Tab.breakpoints => _BreakpointsBody(
        controller: ctrl,
        onPersist: persistBreakpoints,
        onJumpToSource: (url, line) {
          if (_tab != _Tab.sources) setState(() => _tab = _Tab.sources);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _sourcesPanelKey.currentState?.requestJumpTo(url: url, line: line);
          });
        },
      ),
      _Tab.realtime => _RealtimeBody(controller: ctrl),
      _Tab.crypto => _CryptoPadBody(reduceMotion: reduceMotion),
      _Tab.performance => _PerformancePanel(
        controller: ctrl,
        isZh: isZh,
        reduceMotion: reduceMotion,
      ),
      _Tab.memory => _MemoryPanel(
        controller: ctrl,
        isZh: isZh,
        reduceMotion: reduceMotion,
      ),
      _Tab.application => _ApplicationPanel(
        controller: ctrl,
        isZh: isZh,
        reduceMotion: reduceMotion,
      ),
      _Tab.security => _SecurityPanel(controller: ctrl),
      _Tab.recorder => _RecorderPanel(controller: ctrl),
    };
  }

  Future<void> _openOfficialDevTools(WebReverseSessionController ctrl) async {
    await _openOfficialDevToolsForController(context, ctrl);
  }
}

/// 打开浏览器官方 DevTools 前端：先读 `/json/list` 拿 `devtoolsFrontendUrl`，
/// 再用平台命令打开。失败时降级到 `/json/list` 列表页 + SnackBar 提示。
/// 提取为顶层函数让 [_BrowserBody] 的右键菜单也能直接复用。
Future<void> _openOfficialDevToolsForController(
  BuildContext context,
  WebReverseSessionController ctrl,
) async {
  final port = ctrl.cdpPort;
  if (port == null) return;
  String? frontendUrl;
  final deadline = MonotonicDeadline(
    _kDevToolsDiscoveryTimeout,
    timeoutMessage: '读取 DevTools 目标列表超时。',
  );
  try {
    frontendUrl = await withWebReverseCdpHttpClient<String?>(
      connectionTimeout: _kDevToolsDiscoveryTimeout,
      idleTimeout: _kDevToolsDiscoveryTimeout,
      action: (client) async {
        final req = await client
            .getUrl(webReverseCdpHttpUri(port, '/json/list'))
            .timeout(deadline.remaining());
        final res = await req.close().timeout(deadline.remaining());
        final remainingReadTime = deadline.remaining();
        final body = await readBoundedHttpResponseText(
          res,
          maxBytes: _kDevToolsDiscoveryMaxResponseBytes,
          idleTimeout: remainingReadTime,
          totalTimeout: remainingReadTime,
        );
        final list = jsonDecode(body);
        if (list is List) {
          Map<String, Object?>? best;
          final targets = stringKeyedMapListFromValue(list);
          for (final m in targets) {
            final type = '${m['type'] ?? ''}';
            final url = '${m['url'] ?? ''}';
            if (type == 'page' && !url.startsWith('about:')) {
              best = m;
              break;
            }
          }
          best ??= targets.where((m) => m['type'] == 'page').firstOrNull;
          best ??= targets.firstOrNull;
          final fe = best?['devtoolsFrontendUrl'] as String?;
          if (fe != null && fe.isNotEmpty) {
            return fe.startsWith('http') ? fe : 'http://127.0.0.1:$port$fe';
          }
        }
        return null;
      },
    );
  } catch (error, stack) {
    silentLog('web_reverse_dashboard_dialog', '读取 DevTools 目标列表', error, stack);
  } finally {
    deadline.stop();
  }
  final url =
      frontendUrl ?? webReverseCdpHttpUri(port, '/json/list').toString();
  try {
    if (Platform.isMacOS) {
      await runTrackedProcessOrFailed(
        '/usr/bin/open',
        [url],
        timeout: _kOpenExternalUrlTimeout,
        tag: 'web_reverse.open_devtools',
      );
    } else if (Platform.isWindows) {
      await runTrackedProcessOrFailed(
        'cmd',
        ['/c', 'start', '', url],
        timeout: _kOpenExternalUrlTimeout,
        tag: 'web_reverse.open_devtools',
      );
    } else if (Platform.isLinux) {
      await runTrackedProcessOrFailed(
        'xdg-open',
        [url],
        timeout: _kOpenExternalUrlTimeout,
        tag: 'web_reverse.open_devtools',
      );
    }
  } catch (error, stack) {
    silentLog('web_reverse_dashboard_dialog', '打开 DevTools 链接', error, stack);
  }
  if (!context.mounted) return;
  if (frontendUrl == null) {
    showOpenHandInfoSnack(
      context,
      openHandLocalizedText(
        context,
        zh: '未找到可用的 DevTools 前端，已退到 /json/list 列表页',
        zhHant: '未找到可用的 DevTools 前端，已退到 /json/list 列表頁',
        en: 'No DevTools frontend found; opened /json/list fallback',
        fr: 'Aucun frontend DevTools trouvé ; ouverture de /json/list',
        de: 'Kein DevTools-Frontend gefunden; /json/list wurde geoffnet',
        ja: '利用可能な DevTools フロントエンドが見つからないため /json/list を開きました',
      ),
    );
  }
}

enum _CdpMcpBridgeHeaderTone { disabled, ready, preparing, failed, unavailable }

class _CdpMcpBridgeHeaderStatus {
  const _CdpMcpBridgeHeaderStatus({
    required this.tone,
    required this.icon,
    required this.label,
    required this.tooltip,
  });

  final _CdpMcpBridgeHeaderTone tone;
  final IconData icon;
  final String label;
  final String tooltip;

  static _CdpMcpBridgeHeaderStatus fromRuntime(
    BuildContext context,
    Object? runtime, {
    required WebReverseSessionController controller,
  }) {
    final runtimeStatus = WebReverseCdpMcpRuntimeStatus.fromRuntime(
      runtime,
      controllerBrowserAlive: controller.isBrowserAlive,
      controllerPort: controller.cdpPort,
    );

    late final _CdpMcpBridgeHeaderTone tone;
    late final IconData icon;
    late final String label;
    if (runtimeStatus.rawStatus == 'disabled') {
      tone = _CdpMcpBridgeHeaderTone.disabled;
      icon = Icons.hub_outlined;
      label = openHandLocalizedText(
        context,
        zh: 'AI CDP 未启用',
        zhHant: 'AI CDP 未啟用',
        en: 'AI CDP disabled',
        fr: 'CDP IA désactivé',
        de: 'AI-CDP deaktiviert',
        ja: 'AI CDP 無効',
      );
    } else if (runtimeStatus.ready) {
      tone = _CdpMcpBridgeHeaderTone.ready;
      icon = Icons.hub_rounded;
      label = openHandLocalizedText(
        context,
        zh: 'AI CDP 就绪 · ${runtimeStatus.toolCount}',
        zhHant: 'AI CDP 就緒 · ${runtimeStatus.toolCount}',
        en: 'AI CDP ready · ${runtimeStatus.toolCount}',
        fr: 'CDP IA prêt · ${runtimeStatus.toolCount}',
        de: 'AI-CDP bereit · ${runtimeStatus.toolCount}',
        ja: 'AI CDP 準備完了 · ${runtimeStatus.toolCount}',
      );
    } else if (!runtimeStatus.browserAlive) {
      tone = _CdpMcpBridgeHeaderTone.unavailable;
      icon = Icons.power_off_rounded;
      label = openHandLocalizedText(
        context,
        zh: 'AI CDP 离线',
        zhHant: 'AI CDP 離線',
        en: 'AI CDP offline',
        fr: 'CDP IA hors ligne',
        de: 'AI-CDP offline',
        ja: 'AI CDP オフライン',
      );
    } else if (runtimeStatus.rawStatus == 'preparing') {
      tone = _CdpMcpBridgeHeaderTone.preparing;
      icon = Icons.sync_rounded;
      label = openHandLocalizedText(
        context,
        zh: 'AI CDP 准备中',
        zhHant: 'AI CDP 準備中',
        en: 'AI CDP preparing',
        fr: 'Préparation du CDP IA',
        de: 'AI-CDP wird vorbereitet',
        ja: 'AI CDP 準備中',
      );
    } else if (runtimeStatus.rawStatus == 'failed') {
      tone = _CdpMcpBridgeHeaderTone.failed;
      icon = Icons.error_outline_rounded;
      label = openHandLocalizedText(
        context,
        zh: 'AI CDP 异常',
        zhHant: 'AI CDP 異常',
        en: 'AI CDP failed',
        fr: 'Échec du CDP IA',
        de: 'AI-CDP fehlgeschlagen',
        ja: 'AI CDP 異常',
      );
    } else {
      tone = _CdpMcpBridgeHeaderTone.unavailable;
      icon = Icons.link_off_rounded;
      label = openHandLocalizedText(
        context,
        zh: 'AI CDP 待同步',
        zhHant: 'AI CDP 待同步',
        en: 'AI CDP pending',
        fr: 'CDP IA en attente',
        de: 'AI-CDP ausstehend',
        ja: 'AI CDP 同期待ち',
      );
    }

    final lines = <String>[
      openHandLocalizedText(
        context,
        zh: 'AI 侧 CDP MCP 桥接状态',
        zhHant: 'AI 側 CDP MCP 橋接狀態',
        en: 'AI-side CDP MCP bridge',
        fr: 'Pont MCP CDP côté IA',
        de: 'AI-seitige CDP-MCP-Bridge',
        ja: 'AI 側 CDP MCP ブリッジ状態',
      ),
      '${openHandLocalizedText(context, zh: '状态', zhHant: '狀態', en: 'Status', fr: 'Etat', de: 'Status', ja: '状態')}: ${runtimeStatus.rawStatus.isEmpty ? 'unknown' : runtimeStatus.rawStatus}',
      '${openHandLocalizedText(context, zh: '可调用工具', zhHant: '可呼叫工具', en: 'Callable tools', fr: 'Outils appelables', de: 'Aufrufbare Tools', ja: '呼び出し可能ツール')}: ${runtimeStatus.toolCount}',
      if (runtimeStatus.port != null)
        '${openHandLocalizedText(context, zh: 'CDP 端口', zhHant: 'CDP 連接埠', en: 'CDP port', fr: 'Port CDP', de: 'CDP-Port', ja: 'CDP ポート')}: ${runtimeStatus.port}',
      if (runtimeStatus.serverName.isNotEmpty)
        'MCP: ${runtimeStatus.serverName}',
      if (runtimeStatus.message.isNotEmpty) runtimeStatus.message,
      if (runtimeStatus.warningMessage.isNotEmpty)
        '${openHandLocalizedText(context, zh: '提示', zhHant: '提示', en: 'Warning', fr: 'Avertissement', de: 'Warnung', ja: '警告')}: ${runtimeStatus.warningMessage}',
      if (runtimeStatus.errorMessage.isNotEmpty)
        '${openHandErrorLabel(context)}: ${runtimeStatus.errorMessage}',
    ];
    return _CdpMcpBridgeHeaderStatus(
      tone: tone,
      icon: icon,
      label: label,
      tooltip: lines.join('\n'),
    );
  }
}

class _CdpMcpBridgeToggle extends StatelessWidget {
  const _CdpMcpBridgeToggle({
    required this.enabled,
    required this.busy,
    required this.reduceMotion,
    required this.onChanged,
  });

  final bool enabled;
  final bool busy;
  final bool reduceMotion;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = enabled ? cs.primary : cs.onSurfaceVariant;
    return Tooltip(
      message: openHandLocalizedText(
        context,
        zh: '手动启用后，本会话才会通过 npx 准备 chrome-devtools-mcp；关闭会停止临时 MCP。',
        zhHant: '手動啟用後，本會話才會透過 npx 準備 chrome-devtools-mcp；關閉會停止臨時 MCP。',
        en: 'Enable manually to prepare chrome-devtools-mcp through npx for this session; disabling stops the transient MCP.',
        fr: 'Activez manuellement pour préparer chrome-devtools-mcp via npx pour cette session ; la désactivation arrête le MCP temporaire.',
        de: 'Manuell aktivieren, um chrome-devtools-mcp per npx für diese Sitzung vorzubereiten; Deaktivieren stoppt das temporäre MCP.',
        ja: '手動で有効化すると、このセッション用に npx 経由で chrome-devtools-mcp を準備します。無効化すると一時 MCP を停止します。',
      ),
      waitDuration: kOpenHandTooltipWait,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : _kSwitchDuration,
        curve: _kSwitchInCurve,
        height: 32,
        padding: const EdgeInsets.only(left: 10, right: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: enabled ? 0.12 : 0.08),
          borderRadius: kOpenHandPillBorderRadius,
          border: Border.all(color: color.withValues(alpha: 0.32)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: reduceMotion ? Duration.zero : _kSwitchDuration,
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: busy
                  ? SizedBox(
                      key: const ValueKey('busy'),
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: color,
                      ),
                    )
                  : Icon(
                      enabled ? Icons.hub_rounded : Icons.hub_outlined,
                      key: ValueKey<bool>(enabled),
                      size: 15,
                      color: color,
                    ),
            ),
            kOpenHandHGap6,
            Text(
              enabled
                  ? openHandLocalizedText(
                      context,
                      zh: 'MCP 开',
                      zhHant: 'MCP 開',
                      en: 'MCP on',
                      fr: 'MCP actif',
                      de: 'MCP ein',
                      ja: 'MCP オン',
                    )
                  : openHandLocalizedText(
                      context,
                      zh: 'MCP 关',
                      zhHant: 'MCP 關',
                      en: 'MCP off',
                      fr: 'MCP inactif',
                      de: 'MCP aus',
                      ja: 'MCP オフ',
                    ),
              style: theme.textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
            Transform.scale(
              scale: 0.72,
              child: Switch.adaptive(
                value: enabled,
                onChanged: busy ? null : onChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CdpMcpBridgeStatusPill extends StatelessWidget {
  const _CdpMcpBridgeStatusPill({
    required this.status,
    required this.reduceMotion,
  });

  final _CdpMcpBridgeHeaderStatus status;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = switch (status.tone) {
      _CdpMcpBridgeHeaderTone.ready => cs.tertiary,
      _CdpMcpBridgeHeaderTone.disabled => cs.onSurfaceVariant,
      _CdpMcpBridgeHeaderTone.preparing => cs.primary,
      _CdpMcpBridgeHeaderTone.failed => cs.error,
      _CdpMcpBridgeHeaderTone.unavailable => cs.onSurfaceVariant,
    };
    return Tooltip(
      message: status.tooltip,
      waitDuration: kOpenHandTooltipWait,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : _kSwitchDuration,
        curve: _kSwitchInCurve,
        height: 32,
        constraints: const BoxConstraints(maxWidth: 210),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: kOpenHandPillBorderRadius,
          border: Border.all(color: color.withValues(alpha: 0.34)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(status.icon, size: 15, color: color),
            kOpenHandHGap6,
            Flexible(
              child: Text(
                status.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewBody extends StatefulWidget {
  const _OverviewBody({required this.controller});
  final WebReverseSessionController controller;

  @override
  State<_OverviewBody> createState() => _OverviewBodyState();
}

class _OverviewBodyState extends State<_OverviewBody> {
  bool _busy = false;

  WebReverseSessionController get controller => widget.controller;

  Future<void> _exportSnapshot() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ts = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      const typeGroup = XTypeGroup(label: 'JSON', extensions: <String>['json']);
      final location = await getSaveLocation(
        suggestedName: 'web-reverse-snapshot-$ts.json',
        acceptedTypeGroups: const <XTypeGroup>[typeGroup],
      );
      if (location == null) return;
      final snap = controller.exportSnapshot();
      final jsonStr = prettyPrintJson(snap);
      await writeFileAtomically(File(location.path), jsonStr);
      if (!mounted) return;
      showOpenHandSuccessSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '快照已保存到 ${location.path}',
          zhHant: '快照已儲存到 ${location.path}',
          en: 'Snapshot saved to ${location.path}',
          fr: 'Instantané enregistré dans ${location.path}',
          de: 'Snapshot gespeichert unter ${location.path}',
          ja: 'スナップショットを ${location.path} に保存しました',
        ),
        duration: kOpenHandSnackBarNormalDuration,
      );
    } catch (error, stack) {
      silentLog('web_reverse_dashboard_dialog', '导出快照', error, stack);
      if (!mounted) return;
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '快照导出失败',
          zhHant: '快照匯出失敗',
          en: 'Snapshot export failed',
          fr: 'Échec de l’export de l’instantané',
          de: 'Snapshot-Export fehlgeschlagen',
          ja: 'スナップショットのエクスポートに失敗しました',
        ),
        duration: kOpenHandSnackBarNormalDuration,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importSnapshot() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      const typeGroup = XTypeGroup(label: 'JSON', extensions: <String>['json']);
      final file = await openFile(acceptedTypeGroups: const [typeGroup]);
      if (file == null) return;
      final read = await readWebReverseTextFile(file);
      if (!mounted) return;
      if (read.isTooLarge) {
        showOpenHandErrorSnack(
          context,
          webReverseTextFileTooLargeMessage(
            read.tooLargeBytes!,
            context: context,
          ),
          duration: kOpenHandSnackBarNormalDuration,
        );
        return;
      }
      final raw = read.text!;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        if (!mounted) return;
        showOpenHandErrorSnack(
          context,
          openHandLocalizedText(
            context,
            zh: '快照格式无效',
            zhHant: '快照格式無效',
            en: 'Invalid snapshot format',
            fr: 'Format d’instantané invalide',
            de: 'Ungültiges Snapshot-Format',
            ja: 'スナップショット形式が無効です',
          ),
          duration: kOpenHandSnackBarNormalDuration,
        );
        return;
      }
      final count = controller.importSnapshot(decoded.cast<String, Object?>());
      if (!mounted) return;
      if (count < 0) {
        showOpenHandErrorSnack(
          context,
          openHandLocalizedText(
            context,
            zh: '快照版本不兼容',
            zhHant: '快照版本不相容',
            en: 'Snapshot version unsupported',
            fr: 'Version d’instantané non prise en charge',
            de: 'Snapshot-Version wird nicht unterstützt',
            ja: 'スナップショットのバージョンはサポートされていません',
          ),
          duration: kOpenHandSnackBarNormalDuration,
        );
      } else {
        showOpenHandSuccessSnack(
          context,
          openHandLocalizedText(
            context,
            zh: '已导入 $count 条网络记录',
            zhHant: '已匯入 $count 筆網路記錄',
            en: 'Imported $count network entries',
            fr: '$count entrées réseau importées',
            de: '$count Netzwerkeintrage importiert',
            ja: '$count 件のネットワーク記録をインポートしました',
          ),
          duration: kOpenHandSnackBarNormalDuration,
        );
      }
    } catch (error, stack) {
      silentLog('web_reverse_dashboard_dialog', '导入快照', error, stack);
      if (!mounted) return;
      showOpenHandErrorSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '快照导入失败',
          zhHant: '快照匯入失敗',
          en: 'Snapshot import failed',
          fr: 'Échec de l’import de l’instantané',
          de: 'Snapshot-Import fehlgeschlagen',
          ja: 'スナップショットのインポートに失敗しました',
        ),
        duration: kOpenHandSnackBarNormalDuration,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ctrl = controller;
    final antiBot = ctrl.detectAntiBot();
    final stats = <(String, String)>[
      (openHandRequestsLabel(context), '${ctrl.networkRequestCount}'),
      (openHandErrorsLabel(context), '${ctrl.networkErrorCount}'),
      (
        openHandLocalizedText(
          context,
          zh: '控制台条目',
          zhHant: '主控台項目',
          en: 'Console',
          fr: 'Console',
          de: 'Konsole',
          ja: 'コンソール',
        ),
        '${ctrl.consoleMessageCount}',
      ),
      (
        openHandLocalizedText(
          context,
          zh: '运行状态',
          zhHant: '執行狀態',
          en: 'Status',
          fr: 'État',
          de: 'Status',
          ja: '状態',
        ),
        ctrl.isRunning
            ? openHandLocalizedText(
                context,
                zh: '运行中',
                zhHant: '執行中',
                en: 'Running',
                fr: 'En cours',
                de: 'Aktiv',
                ja: '実行中',
              )
            : openHandStoppedLabel(context),
      ),
      (openHandBrowserLabel(context), ctrl.browserVersion ?? '-'),
      (
        openHandLocalizedText(
          context,
          zh: 'CDP 端口',
          zhHant: 'CDP 連接埠',
          en: 'CDP Port',
          fr: 'Port CDP',
          de: 'CDP-Port',
          ja: 'CDP ポート',
        ),
        '${ctrl.cdpPort ?? '-'}',
      ),
    ];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (antiBot.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: cs.tertiaryContainer.withValues(alpha: 0.8),
              borderRadius: kOpenHandBorderRadius12,
              border: Border.all(color: cs.tertiary.withValues(alpha: 0.6)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.shield_moon_rounded,
                  color: cs.onTertiaryContainer,
                  size: 20,
                ),
                kOpenHandHGap10,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        openHandLocalizedText(
                          context,
                          zh: '检测到反爬指纹',
                          zhHant: '偵測到反爬指紋',
                          en: 'Anti-bot signals detected',
                          fr: 'Signaux anti-bot détectés',
                          de: 'Anti-Bot-Signale erkannt',
                          ja: 'ボット対策シグナルを検出しました',
                        ),
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: cs.onTertiaryContainer,
                        ),
                      ),
                      kOpenHandGap2,
                      Text(
                        antiBot.join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onTertiaryContainer,
                          fontFamily: kOpenHandMonospaceFontFamily,
                        ),
                      ),
                      kOpenHandGap4,
                      Text(
                        openHandLocalizedText(
                          context,
                          zh: '此站点使用反爬服务，纯 curl/fetch 复现可能失败。建议保留浏览器流程，或为请求脚本叠加 cookie / TLS 指纹工具。',
                          zhHant:
                              '此站點使用反爬服務，純 curl/fetch 重現可能失敗。建議保留瀏覽器流程，或為請求腳本疊加 cookie / TLS 指紋工具。',
                          en: 'This site uses anti-bot services. Bare curl/fetch may fail; keep the browser flow or add cookie / TLS fingerprint tooling.',
                          fr: 'Ce site utilise une protection anti-bot. Un simple curl/fetch peut échouer ; conservez le flux navigateur ou ajoutez des cookies / empreintes TLS au script.',
                          de: 'Diese Site nutzt Anti-Bot-Schutz. Reines curl/fetch kann fehlschlagen; behalten Sie den Browserfluss bei oder ergänzen Sie Cookies / TLS-Fingerprints.',
                          ja: 'このサイトはボット対策サービスを使用しています。単純な curl/fetch では失敗する可能性があります。ブラウザフローを維持するか、リクエストスクリプトに cookie / TLS フィンガープリントを追加してください。',
                        ),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onTertiaryContainer,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 2.4,
          children: [
            for (final (label, value) in stats)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: webReverseSurfaceCardDecoration(cs, radius: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    kOpenHandGap4,
                    Text(
                      value,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        kOpenHandGap16,
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: webReverseSurfaceCardDecoration(cs, radius: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.bookmarks_rounded,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                  kOpenHandHGap8,
                  Text(
                    openHandLocalizedText(
                      context,
                      zh: '会话快照',
                      zhHant: '會話快照',
                      en: 'Session snapshot',
                      fr: 'Instantané de session',
                      de: 'Sitzungs-Snapshot',
                      ja: 'セッションスナップショット',
                    ),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              kOpenHandGap6,
              Text(
                openHandLocalizedText(
                  context,
                  zh: '把当前 target 的网络/控制台/WebSocket 帧导出为 JSON，便于离线重放、Issue 复现、跨机器协作。导入会覆盖现有缓冲。',
                  zhHant:
                      '將目前 target 的網路 / 主控台 / WebSocket 幀匯出為 JSON，便於離線重放、Issue 重現、跨機器協作。匯入會覆蓋現有緩衝。',
                  en: 'Export current target network / console / WebSocket frames to JSON for offline replay, issue reproduction or hand-off. Import overwrites the current buffer.',
                  fr: 'Exportez les trames réseau / console / WebSocket de la cible en JSON pour rejouer hors ligne, reproduire un ticket ou collaborer. L’import remplace le tampon actuel.',
                  de: 'Exportiert Netzwerk-, Konsolen- und WebSocket-Frames des aktuellen Targets als JSON für Offline-Replay, Fehlerreproduktion oder Übergabe. Import überschreibt den aktuellen Puffer.',
                  ja: '現在の target のネットワーク / コンソール / WebSocket フレームを JSON にエクスポートし、オフライン再生、Issue 再現、引き継ぎに使えます。インポートすると現在のバッファを上書きします。',
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              kOpenHandGap10,
              Row(
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _exportSnapshot,
                    icon: const Icon(Icons.file_download_outlined, size: 18),
                    label: Text(
                      openHandLocalizedText(
                        context,
                        zh: '导出快照',
                        zhHant: '匯出快照',
                        en: 'Export snapshot',
                        fr: 'Exporter',
                        de: 'Snapshot exportieren',
                        ja: 'スナップショットをエクスポート',
                      ),
                    ),
                  ),
                  kOpenHandHGap8,
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _importSnapshot,
                    icon: const Icon(Icons.file_upload_outlined, size: 18),
                    label: Text(
                      openHandLocalizedText(
                        context,
                        zh: '导入快照',
                        zhHant: '匯入快照',
                        en: 'Import snapshot',
                        fr: 'Importer',
                        de: 'Snapshot importieren',
                        ja: 'スナップショットをインポート',
                      ),
                    ),
                  ),
                  OpenHandInlineRevealSwitcher(
                    presentKey: const ValueKey<String>('snapshot-busy'),
                    child: _busy
                        ? const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(width: 12),
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ],
                          )
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Dashboard 顶部的诊断 banner：当 [WebReverseSessionController.errorMessage]
/// 不为空时挂在 header 与 toolbar 之间，把 [WebReverseLaunchDiagnosis]
/// 的"现象 / 根因 / 建议"渲染成一张可操作卡片，提供：
///   · 清理冲突 profile（删 SingletonLock 等残留锁）
///   · 重置整个 profile（rm -rf user-data-dir，红字次要按钮）
///   · 复制完整原始报错
///   · 关闭 banner（清掉 errorMessage）
class _DiagnosisBanner extends StatefulWidget {
  const _DiagnosisBanner({
    super.key,
    required this.controller,
    required this.reduceMotion,
  });

  final WebReverseSessionController controller;
  final bool reduceMotion;

  @override
  State<_DiagnosisBanner> createState() => _DiagnosisBannerState();
}

class _DiagnosisBannerState extends State<_DiagnosisBanner>
    with WebReverseProfileResetCooldown {
  bool _expanded = true;
  bool _busy = false;
  // 自动关闭定时器：诊断 banner 在 12 秒后自动隐藏，避免长期占顶。
  // didUpdateWidget 检测 errorMessage 变化后重新起表；手动点击「关闭」
  // 或任意代理按钮会立刻提前结束（通过 clearErrorMessage 触发）。
  Timer? _autoDismissTimer;
  static const Duration _kAutoDismissAfter = Duration(seconds: 12);
  String? _lastSeenError;

  @override
  void initState() {
    super.initState();
    _scheduleAutoDismiss();
  }

  @override
  void didUpdateWidget(covariant _DiagnosisBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    final cur = widget.controller.errorMessage ?? '';
    if (cur != _lastSeenError) {
      _scheduleAutoDismiss();
    }
  }

  void _scheduleAutoDismiss() {
    _autoDismissTimer?.cancel();
    final msg = widget.controller.errorMessage ?? '';
    _lastSeenError = msg;
    if (msg.trim().isEmpty) return;
    _autoDismissTimer = startSafeTimer(_kAutoDismissAfter, () {
      if (!mounted) return;
      widget.controller.clearErrorMessage();
    });
  }

  @override
  void dispose() {
    cancelProfileResetCooldown();
    _autoDismissTimer?.cancel();
    super.dispose();
  }

  Future<void> _runProgressive() async {
    setState(() => _busy = true);
    final outcome = await runProgressiveProfileResolve(
      context,
      userDataDir: widget.controller.config.userDataDir,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    switch (outcome) {
      case ProgressiveProfileOutcome.reset:
        widget.controller.clearErrorMessage();
        startProfileResetCooldown();
      case ProgressiveProfileOutcome.cleaned:
        // 清理已生效，diagnosis 仍保留以便用户复盘；不进冷却。
        break;
      case ProgressiveProfileOutcome.nothingToDo:
      case ProgressiveProfileOutcome.resetCancelled:
      case ProgressiveProfileOutcome.failed:
        break;
    }
  }

  Future<void> _copyRaw(WebReverseLaunchDiagnosis diagnosis) async {
    await copyWebReverseTextToClipboard(
      context: context,
      text: diagnosis.fullText,
      successBase: openHandLocalizedText(
        context,
        zh: '已复制原始报错',
        zhHant: '已複製原始錯誤',
        en: 'Raw error copied',
        fr: 'Erreur brute copiée',
        de: 'Rohfehler kopiert',
        ja: '原始エラーをコピーしました',
      ),
      logTag: 'web_reverse_dashboard_dialog',
      logAction: '复制诊断信息',
      successDuration: const Duration(seconds: 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final raw = widget.controller.errorMessage ?? '';
    final diagnosis = WebReverseLaunchDiagnosis.parse(
      raw,
      locale: Localizations.localeOf(context),
    );
    return AnimatedSize(
      duration: widget.reduceMotion ? Duration.zero : kOpenHandMotion240,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
        decoration: BoxDecoration(
          color: cs.errorContainer.withValues(alpha: 0.45),
          borderRadius: kOpenHandBorderRadius12,
          border: Border.all(color: cs.error.withValues(alpha: 0.65)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.report_gmailerrorred_rounded,
                  size: 18,
                  color: cs.error,
                ),
                kOpenHandHGap8,
                Expanded(
                  child: Text(
                    diagnosis.phenomenon,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: cs.onErrorContainer,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: _expanded
                      ? openHandLocalizedText(
                          context,
                          zh: '收起',
                          zhHant: '收合',
                          en: 'Collapse',
                          fr: 'Replier',
                          de: 'Einklappen',
                          ja: '折りたたむ',
                        )
                      : openHandExpandLabel(context),
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(
                    minWidth: 30,
                    minHeight: 30,
                  ),
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                  ),
                ),
                kOpenHandHGap4,
                IconButton(
                  tooltip: openHandLocalizedText(
                    context,
                    zh: '关闭诊断',
                    zhHant: '關閉診斷',
                    en: 'Dismiss',
                    fr: 'Fermer le diagnostic',
                    de: 'Diagnose schließen',
                    ja: '診断を閉じる',
                  ),
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(
                    minWidth: 30,
                    minHeight: 30,
                  ),
                  onPressed: widget.controller.clearErrorMessage,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            if (_expanded) ...[
              kOpenHandGap8,
              for (var i = 0; i < diagnosis.causes.length; i++) ...[
                _CauseEntry(cause: diagnosis.causes[i], index: i),
                if (i != diagnosis.causes.length - 1) kOpenHandGap8,
              ],
              kOpenHandGap12,
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  // 渐进式按钮：先清理 → 仍有锁则引导重置。重置成功后自动 60s 冷却。
                  FilledButton.tonalIcon(
                    onPressed: (_busy || onProfileResetCooldown)
                        ? null
                        : _runProgressive,
                    icon: Icon(
                      _busy
                          ? Icons.hourglass_top_rounded
                          : (onProfileResetCooldown
                                ? Icons.timer_rounded
                                : Icons.auto_fix_high_rounded),
                      size: 16,
                    ),
                    label: Text(
                      _busy
                          ? openHandLocalizedText(
                              context,
                              zh: '处理中…',
                              zhHant: '處理中…',
                              en: 'Working…',
                              fr: 'Traitement…',
                              de: 'Wird verarbeitet…',
                              ja: '処理中…',
                            )
                          : onProfileResetCooldown
                          ? openHandLocalizedText(
                              context,
                              zh: '冷却中（${profileResetCooldownLeftSec}s）',
                              zhHant: '冷卻中（${profileResetCooldownLeftSec}s）',
                              en: 'Cool-down ${profileResetCooldownLeftSec}s',
                              fr: 'Pause ${profileResetCooldownLeftSec}s',
                              de: 'Abklingzeit ${profileResetCooldownLeftSec}s',
                              ja: 'クールダウン ${profileResetCooldownLeftSec}s',
                            )
                          : openHandLocalizedText(
                              context,
                              zh: '解决 Profile 冲突',
                              zhHant: '解決 Profile 衝突',
                              en: 'Resolve profile lock',
                              fr: 'Résoudre le verrou du profil',
                              de: 'Profilsperre beheben',
                              ja: 'プロファイルロックを解消',
                            ),
                    ),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _copyRaw(diagnosis),
                    icon: const Icon(Icons.copy_all_rounded, size: 16),
                    label: Text(
                      openHandLocalizedText(
                        context,
                        zh: '复制原始报错',
                        zhHant: '複製原始錯誤',
                        en: 'Copy raw error',
                        fr: 'Copier l’erreur brute',
                        de: 'Rohfehler kopieren',
                        ja: '原始エラーをコピー',
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CauseEntry extends StatelessWidget {
  const _CauseEntry({required this.cause, required this.index});

  final WebReverseLaunchCause cause;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.7),
        borderRadius: kOpenHandBorderRadius8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: kOpenHandPillBorderRadius,
                ),
                child: Text(
                  openHandLocalizedText(
                    context,
                    zh: '可能根因 ${index + 1}',
                    zhHant: '可能根因 ${index + 1}',
                    en: 'Cause ${index + 1}',
                    fr: 'Cause ${index + 1}',
                    de: 'Ursache ${index + 1}',
                    ja: '原因 ${index + 1}',
                  ),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                    fontFamily: kOpenHandMonospaceFontFamily,
                  ),
                ),
              ),
              kOpenHandHGap8,
              Expanded(
                child: Text(
                  cause.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          kOpenHandGap4,
          Text(
            cause.suggestion,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// dashboard 全局快捷键速查面板：按 Shift+? 打开，分类列出所有热键。
/// macOS 上 Cmd 用 ⌘ 渲染；其它平台用 Ctrl。
class _ShortcutsHelpDialog extends StatelessWidget {
  const _ShortcutsHelpDialog();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cmd = Platform.isMacOS ? '⌘' : 'Ctrl';
    final groups = <({String title, List<({String keys, String desc})> rows})>[
      (
        title: openHandLocalizedText(
          context,
          zh: 'Dashboard',
          zhHant: 'Dashboard',
          en: 'Dashboard',
          fr: 'Dashboard',
          de: 'Dashboard',
          ja: 'Dashboard',
        ),
        rows: [
          (
            keys: 'Shift + ?',
            desc: openHandLocalizedText(
              context,
              zh: '打开本面板',
              zhHant: '開啟本面板',
              en: 'Open this panel',
              fr: 'Ouvrir ce panneau',
              de: 'Dieses Panel öffnen',
              ja: 'このパネルを開く',
            ),
          ),
          (
            keys: '$cmd + Shift + R',
            desc: openHandLocalizedText(
              context,
              zh: '启停 Recorder',
              zhHant: '啟停 Recorder',
              en: 'Toggle Recorder',
              fr: 'Basculer Recorder',
              de: 'Recorder umschalten',
              ja: 'Recorder を切り替え',
            ),
          ),
        ],
      ),
      (
        title: openHandLocalizedText(
          context,
          zh: '浏览器面板',
          zhHant: '瀏覽器面板',
          en: 'Browser surface',
          fr: 'Surface navigateur',
          de: 'Browserflache',
          ja: 'ブラウザ面',
        ),
        rows: [
          (keys: '$cmd + T', desc: _wrNewTabLabel(context)),
          (
            keys: '$cmd + W',
            desc: openHandLocalizedText(
              context,
              zh: '关闭当前标签页',
              zhHant: '關閉目前分頁',
              en: 'Close tab',
              fr: 'Fermer l’onglet',
              de: 'Tab schließen',
              ja: 'タブを閉じる',
            ),
          ),
          (keys: '$cmd + R', desc: _wrReloadLabel(context)),
          (
            keys: '$cmd + Shift + R',
            desc: openHandLocalizedText(
              context,
              zh: '强制刷新',
              zhHant: '強制重新整理',
              en: 'Hard reload',
              fr: 'Rechargement force',
              de: 'Hart neu laden',
              ja: '強制再読み込み',
            ),
          ),
          (
            keys: '$cmd + L',
            desc: openHandLocalizedText(
              context,
              zh: '聚焦地址栏',
              zhHant: '聚焦網址列',
              en: 'Focus address bar',
              fr: 'Focus barre d’adresse',
              de: 'Adressleiste fokussieren',
              ja: 'アドレスバーにフォーカス',
            ),
          ),
          (
            keys: '$cmd + F',
            desc: openHandLocalizedText(
              context,
              zh: '页面查找',
              zhHant: '頁面搜尋',
              en: 'Find in page',
              fr: 'Rechercher dans la page',
              de: 'Auf Seite suchen',
              ja: 'ページ内検索',
            ),
          ),
          (
            keys: 'Esc',
            desc: openHandLocalizedText(
              context,
              zh: '关闭查找条',
              zhHant: '關閉搜尋列',
              en: 'Close find bar',
              fr: 'Fermer la recherche',
              de: 'Suchleiste schließen',
              ja: '検索バーを閉じる',
            ),
          ),
          (
            keys: '$cmd + +',
            desc: openHandLocalizedText(
              context,
              zh: '放大',
              zhHant: '放大',
              en: 'Zoom in',
              fr: 'Zoom avant',
              de: 'Vergrossern',
              ja: '拡大',
            ),
          ),
          (
            keys: '$cmd + -',
            desc: openHandLocalizedText(
              context,
              zh: '缩小',
              zhHant: '縮小',
              en: 'Zoom out',
              fr: 'Zoom arrière',
              de: 'Verkleinern',
              ja: '縮小',
            ),
          ),
          (
            keys: '$cmd + 0',
            desc: openHandLocalizedText(
              context,
              zh: '复位 100%',
              zhHant: '重設 100%',
              en: 'Zoom 100%',
              fr: 'Zoom 100 %',
              de: 'Zoom 100 %',
              ja: 'ズーム 100%',
            ),
          ),
        ],
      ),
      (
        title: _wrConsoleLabel(context),
        rows: [
          (
            keys: '↑ / ↓',
            desc: openHandLocalizedText(
              context,
              zh: '浏览历史命令',
              zhHant: '瀏覽歷史命令',
              en: 'Browse history',
              fr: 'Parcourir l’historique',
              de: 'Verlauf durchsuchen',
              ja: '履歴を移動',
            ),
          ),
          (keys: 'Enter', desc: openHandRunLabel(context)),
        ],
      ),
      (
        title: openHandLocalizedText(
          context,
          zh: '通用',
          zhHant: '通用',
          en: 'General',
          fr: 'Général',
          de: 'Allgemein',
          ja: '全般',
        ),
        rows: [
          (
            keys: openHandLocalizedText(
              context,
              zh: '右键',
              zhHant: '右鍵',
              en: 'Right-click',
              fr: 'Clic droit',
              de: 'Rechtsklick',
              ja: '右クリック',
            ),
            desc: openHandLocalizedText(
              context,
              zh: '浏览器面板上下文菜单（复制 / 粘贴 / 检查 / 框选导出 …）',
              zhHant: '瀏覽器面板內容選單（複製 / 貼上 / 檢查 / 框選匯出 …）',
              en: 'Browser surface context menu',
              fr: 'Menu contextuel de la surface navigateur',
              de: 'Kontextmenu der Browserflache',
              ja: 'ブラウザ面のコンテキストメニュー',
            ),
          ),
        ],
      ),
    ];
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthCompact,
      maxHeight: kOpenHandDialogHeightStandard,
      backgroundColor: cs.surfaceContainer,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.keyboard_rounded,
            title: openHandLocalizedText(
              context,
              zh: '快捷键速查',
              zhHant: '快捷鍵速查',
              en: 'Keyboard shortcuts',
              fr: 'Raccourcis clavier',
              de: 'Tastenkurzel',
              ja: 'キーボードショートカット',
            ),
            onClose: () => Navigator.of(context).pop(),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Flexible(
            child: OpenHandSafeScrollbar(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                children: [
                  for (final g in groups) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
                      child: Text(
                        g.title,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: cs.primary,
                        ),
                      ),
                    ),
                    for (final r in g.rows)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Container(
                              constraints: const BoxConstraints(minWidth: 110),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest,
                                borderRadius: kOpenHandBorderRadius6,
                                border: Border.all(color: cs.outlineVariant),
                              ),
                              child: Text(
                                r.keys,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontFamily: kOpenHandMonospaceFontFamily,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            kOpenHandHGap12,
                            Expanded(
                              child: Text(
                                r.desc,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 本库内共用的文案
//
// 下列标签原先在同一个库的多个 part 里各写了一份多语言字面量，改一处措辞就
// 得同步改两到三处。
// ─────────────────────────────────────────────────────────────────────────────

String _wrConsoleLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '控制台',
    zhHant: '主控台',
    en: 'Console',
    fr: 'Console',
    de: 'Konsole',
    ja: 'コンソール',
  );
}



String _wrEditLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '编辑',
    zhHant: '編輯',
    en: 'Edit',
    fr: 'Modifier',
    de: 'Bearbeiten',
    ja: '編集',
  );
}

String _wrExportCsvLabel(BuildContext context) {
  return openHandExportCsvLabel(context);
}

String _wrNewTabLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '新标签页',
    zhHant: '新分頁',
    en: 'New tab',
    fr: 'Nouvel onglet',
    de: 'Neuer Tab',
    ja: '新しいタブ',
  );
}

String _wrReloadLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '刷新',
    zhHant: '重新整理',
    en: 'Reload',
    fr: 'Recharger',
    de: 'Neu laden',
    ja: '再読み込み',
  );
}

String _wrScreenshotFailedLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '截图失败',
    zhHant: '截圖失敗',
    en: 'Screenshot failed',
    fr: 'Échec de la capture',
    de: 'Screenshot fehlgeschlagen',
    ja: 'スクリーンショットに失敗しました',
  );
}
