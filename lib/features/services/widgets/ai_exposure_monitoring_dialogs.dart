import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/support/silent_log.dart';
import '../../../app/theme/openhand_status_colors.dart';
import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/animated_menu.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/openhand_clipboard.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_ops_charts.dart';
import '../../../shared/ui/openhand_safe_scrollbar.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/ui/openhand_trailing_toolbar.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/localized_text.dart';
import '../../../shared/util/timer_safety.dart';
import '../model/ai_exposure_models.dart';
import '../services_controller.dart';
import 'dependency_data_dialog.dart';
import 'service_dialog_controls.dart';

part 'ai_exposure_entity_insights.dart';
part 'ai_exposure_operations_insights.dart';
part 'ai_exposure_monitoring_shell.dart';
part 'ai_exposure_monitoring_overview.dart';
part 'ai_exposure_monitoring_pipeline.dart';
part 'ai_exposure_monitoring_sources.dart';
part 'ai_exposure_monitoring_network.dart';
part 'ai_exposure_monitoring_storage.dart';
part 'ai_exposure_monitoring_security.dart';
part 'ai_exposure_monitoring_components.dart';
part 'ai_exposure_monitoring_insight_framework.dart';
part 'ai_exposure_monitoring_insight_builders.dart';
part 'ai_exposure_monitoring_log.dart';

const Duration _kOperationsRefreshInterval = Duration(seconds: 8);
const Duration _kOperationsMetadataTimeout = Duration(seconds: 2);
const Duration _kOperationsCardMotionDuration = Duration(milliseconds: 150);

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
