import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:openhand/shared/util/text_normalization.dart';
import 'package:provider/provider.dart';

import '../../../app/support/silent_log.dart';
import '../../../app/theme/openhand_status_colors.dart';
import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/animated_menu.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/oh_pill.dart';
import '../../../shared/ui/openhand_clipboard.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_live_value.dart';
import '../../../shared/ui/openhand_ops_charts.dart';
import '../../../shared/ui/openhand_ops_press_scale.dart';
import '../../../shared/ui/openhand_safe_scrollbar.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/openhand_table_pagination.dart';
import '../../../shared/ui/openhand_trailing_toolbar.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/duration_bounds.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/localized_text.dart';
import '../../../shared/util/sensitive_data.dart';
import '../../../shared/util/timer_safety.dart';
import '../model/ai_exposure_models.dart';
import '../model/dependency_telemetry.dart';
import '../services_controller.dart';
import 'ai_exposure_dialogs.dart';
import 'dependency_data_dialog.dart';
import 'service_dialog_controls.dart';

part 'ai_exposure_entity_insights.dart';
part 'ai_exposure_operations_insights.dart';
part 'ai_exposure_monitoring_shell.dart';
part 'ai_exposure_monitoring_overview.dart';
part 'ai_exposure_monitoring_pipeline.dart';
part 'ai_exposure_monitoring_storage.dart';
part 'ai_exposure_monitoring_components.dart';
part 'ai_exposure_monitoring_insight_framework.dart';
part 'ai_exposure_monitoring_insight_builders.dart';
part 'ai_exposure_monitoring_log.dart';

const Duration _kOperationsRefreshInterval = Duration(seconds: 8);
const Duration _kOperationsMetadataTimeout = Duration(seconds: 2);

// AI 暴露监控分类语义色板（图表/标签/卡片统一引用）。
const Color _kAiExposureColorHighValue = Color(0xffa855f7);
const Color _kAiExposureColorTeal = Color(0xff0f766e);
const Color _kAiExposureColorCyan = Color(0xff0891b2);
const Color _kAiExposureDarkSurface = Color(0xff0b0e12);
const Color _kAiExposureColorSlate500 = Color(0xff64748b);
const Color _kAiExposureDarkOnSurface = Color(0xffd5dae3);
const Color _kAiExposureDarkMutedText = Color(0xff9aa4b2);
const Color _kAiExposureDarkTimestamp = Color(0xff7e8998);
const Color _kAiExposureDarkJobId = Color(0xff6fa8ed);
const Color _kAiExposureConsoleSuccess = Color(0xff28d17c);
const Color _kAiExposureConsoleWarning = Color(0xffffb14e);
const Color _kAiExposureLogRuntime = Color(0xff14b8a6);

// 数据源品牌色。各平台官方主色调，用于来源标识与图表区分。
const Color _kAiExposureSourceGithub = Color(0xff475569);
const Color _kAiExposureSourceGitcode = Color(0xff2563eb);
const Color _kAiExposureSourceNodeseek = Color(0xff7c3aed);
const Color _kAiExposureSourceLinuxDo = Color(0xff16a34a);

// 实体脱敏正则：提升为顶层 final，避免每次调用 _entityRedactText 时重新编译。
final RegExp _kRedactPrivateKey = RegExp(
  r'-----BEGIN(?: [A-Z0-9]+)? PRIVATE KEY-----[\s\S]*?-----END(?: [A-Z0-9]+)? PRIVATE KEY-----',
  caseSensitive: false,
);
final RegExp _kRedactAuthHeader = RegExp(
  r'((?:authorization|proxy-authorization)\s*[:=]\s*)([^\r\n,;]+)',
  caseSensitive: false,
);
final RegExp _kRedactSecretAssignment = RegExp(
  r'((?:api[_-]?key|token|secret|password|credential|cookie)\s*[:=]\s*)([^\s,;]+)',
  caseSensitive: false,
);
final RegExp _kRedactSecretJson = RegExp(
  r'((?:"?(?:api[_-]?key|token|secret|password|authorization|credential|cookie)"?\s*:\s*"?))([^",\s}]+)',
  caseSensitive: false,
);
final RegExp _kRedactUrlCredentials = RegExp(
  r'([a-z][a-z0-9+.-]*://[^/\s:@]+:)([^@/\s]+)(@)',
  caseSensitive: false,
);
final RegExp _kRedactSecretQuery = RegExp(
  r'([?&](?:api[_-]?key|token|secret|password|authorization|credential|cookie)=)([^&#\s]+)',
  caseSensitive: false,
);
final RegExp _kRedactBearerToken = RegExp(
  r'(bearer\s+)([A-Za-z0-9._~+/-]+)',
  caseSensitive: false,
);

Future<void> showAiExposureOperationsDialog(BuildContext context) =>
    showAnimatedDialog<void>(
      context: context,
      builder: (_) => buildOpenHandDialog(
        maxWidth: kOpenHandDialogWidthFull,
        maxHeight: kOpenHandDialogHeightFull,
        child: const ServiceDialogInteractionTheme(child: _OperationsDialog()),
      ),
    );

Future<void> showAiExposureLogMonitorDialog(BuildContext context) =>
    showAnimatedDialog<void>(
      context: context,
      builder: (_) => buildOpenHandDialog(
        maxWidth: kOpenHandDialogWidthPanel,
        maxHeight: kOpenHandDialogHeightTall,
        child: const ServiceDialogInteractionTheme(child: _LogMonitorDialog()),
      ),
    );
