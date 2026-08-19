import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/user_failure_message.dart';
import 'safe_subprocess.dart';
import 'silent_log.dart';

class InputRepairSentinelScope extends InheritedWidget {
  const InputRepairSentinelScope({
    required this.focusNode,
    required super.child,
    super.key,
  });

  final FocusNode focusNode;

  static FocusNode? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<InputRepairSentinelScope>()
        ?.focusNode;
  }

  @override
  bool updateShouldNotify(InputRepairSentinelScope oldWidget) =>
      oldWidget.focusNode != focusNode;
}

enum InputRepairResult { success, partialSuccess, failure }

enum InputRepairStage {
  resetParticipantsBefore,
  killTrackedChildren,
  killDirectChildren,
  clearTextInputClient,
  hideTextInput,
  finishAutofillContext,
  requestExistingInputState,
  focusSentinel,
  restoreSafeFocus,
  resetParticipantsAfter,
}

enum InputRepairParticipantPhase { beforeTextInputReset, afterTextInputReset }

enum InputRepairStepStatus { success, warning, failure }

class InputRepairParticipantResult {
  const InputRepairParticipantResult({required this.status, this.message});

  const InputRepairParticipantResult.success([this.message])
    : status = InputRepairStepStatus.success;

  const InputRepairParticipantResult.warning([this.message])
    : status = InputRepairStepStatus.warning;

  const InputRepairParticipantResult.failure([this.message])
    : status = InputRepairStepStatus.failure;

  final InputRepairStepStatus status;
  final String? message;
}

class InputRepairStepReport {
  const InputRepairStepReport({
    required this.stage,
    required this.status,
    this.message,
  });

  final InputRepairStage stage;
  final InputRepairStepStatus status;
  final String? message;
}

class InputRepairReport {
  const InputRepairReport({
    required this.result,
    required this.steps,
    required this.trackedChildrenBefore,
    required this.directChildrenKilled,
    this.primaryFocusBeforeLabel,
    this.primaryFocusAfterLabel,
    this.restoredFocusLabel,
  });

  final InputRepairResult result;
  final List<InputRepairStepReport> steps;
  final int trackedChildrenBefore;
  final int directChildrenKilled;
  final String? primaryFocusBeforeLabel;
  final String? primaryFocusAfterLabel;
  final String? restoredFocusLabel;
}

typedef InputRepairParticipantCallback =
    Future<InputRepairParticipantResult> Function(
      InputRepairParticipantPhase phase,
    );

class InputRepairParticipantToken {
  InputRepairParticipantToken(this._onDispose);

  final VoidCallback _onDispose;

  void dispose() => _onDispose();
}

class _InputRepairParticipant {
  const _InputRepairParticipant({
    required this.debugLabel,
    required this.onRepair,
  });

  final String debugLabel;
  final InputRepairParticipantCallback onRepair;
}

/// [SafeTextEditingController] 在 [TextEditingController] 之上做
/// 两层加固：
///   1. setter 阶段强制把 selection / composing 钳到 [0, text.length] 区间内，
///      避免外部误用（比如我们自己 `_replaceComposerText` 写入了带陈旧
///      selection 的值）把越界状态推给 framework 后再被
///      `TextEditingValue.fromJSON` 断言打回；
///
/// 与 framework 自身的 `Range start ... is out of text of length ...` 断言
/// 配合：本类负责把越界值拦在 app 层，framework 负责把平台 IME 反向
/// `updateEditingState` 里的越界值打回——两者互为补充。
class SafeTextEditingController extends TextEditingController {
  SafeTextEditingController({super.text});

  @override
  set value(TextEditingValue newValue) {
    super.value = _clampValue(newValue);
  }

  static TextEditingValue _clampValue(TextEditingValue raw) {
    final text = raw.text;
    final len = text.length;
    final selection = _clampSelection(raw.selection, len);
    final composing = _clampRange(raw.composing, len);
    if (selection == raw.selection &&
        composing.start == raw.composing.start &&
        composing.end == raw.composing.end) {
      return raw;
    }
    return TextEditingValue(
      text: text,
      selection: selection,
      composing: composing,
    );
  }

  static TextSelection _clampSelection(TextSelection s, int len) {
    if (!s.isValid) return s;
    final base = s.baseOffset.clamp(0, len).toInt();
    final extent = s.extentOffset.clamp(0, len).toInt();
    if (base == s.baseOffset && extent == s.extentOffset) {
      return s;
    }
    return TextSelection(
      baseOffset: base,
      extentOffset: extent,
      affinity: s.affinity,
      isDirectional: s.isDirectional,
    );
  }

  static TextRange _clampRange(TextRange r, int len) {
    if (!r.isValid) return r;
    final start = r.start.clamp(0, len).toInt();
    final end = r.end.clamp(0, len).toInt();
    if (start == r.start && end == r.end) {
      return r;
    }
    return TextRange(start: start, end: end);
  }
}

class InputRepairService {
  InputRepairService._();

  static final InputRepairService instance = InputRepairService._();
  static const Duration _focusSettleDelay = Duration(milliseconds: 60);
  static const Duration _participantTimeout = Duration(seconds: 2);
  static const Duration _platformChannelTimeout = Duration(seconds: 2);

  final Map<Object, _InputRepairParticipant> _participants =
      <Object, _InputRepairParticipant>{};

  // 软恢复钩子：用于在不重建 IME 连接的前提下，对 composer
  // 文本输入做一次轻量级"重置 + 复位"（典型做法：临时 unfocus 再
  // requestFocus），把可能已经脱钩的平台 IME 选区/组合态与 controller
  // 重新对齐。当 `FlutterError.onError` 捕获到
  // `TextInputClient.updateEditingState` 的 selection 越界断言时调用，
  // 比 `repair()` 走 clearClient/hide 全套流程更轻，也不会强行关闭键盘。
  VoidCallback? _softRecoveryHook;

  void registerSoftRecoveryHook(VoidCallback? hook) {
    _softRecoveryHook = hook;
  }

  /// 触发一次轻量级 IME 软恢复。返回 true 表示已有钩子处理。
  bool triggerSoftRecovery() {
    final hook = _softRecoveryHook;
    if (hook == null) return false;
    try {
      hook();
      return true;
    } catch (error, stack) {
      silentLog('input_repair', '执行软恢复', error, stack);
      return false;
    }
  }

  InputRepairParticipantToken registerParticipant({
    required String debugLabel,
    required InputRepairParticipantCallback onRepair,
  }) {
    final token = Object();
    _participants[token] = _InputRepairParticipant(
      debugLabel: debugLabel,
      onRepair: onRepair,
    );
    return InputRepairParticipantToken(() {
      _participants.remove(token);
    });
  }

  Future<InputRepairReport> repair({
    required FocusNode sentinelFocusNode,
    bool Function(FocusNode node)? isSafeRestoreTarget,
  }) async {
    final steps = <InputRepairStepReport>[];
    final trackedChildrenBefore = trackedChildPidsSnapshot().length;
    final savedFocus = FocusManager.instance.primaryFocus;
    final primaryFocusBeforeLabel = _focusLabel(savedFocus);
    FocusNode? restoredFocus;
    var directChildrenKilled = 0;

    Future<void> runParticipants(InputRepairParticipantPhase phase) async {
      var phaseStatus = InputRepairStepStatus.success;
      final details = <String>[];
      final participants = _participants.values.toList(growable: false);
      for (final participant in participants) {
        try {
          final result = await participant
              .onRepair(phase)
              .timeout(
                _participantTimeout,
                onTimeout: () =>
                    throw TimeoutException('输入修复参与者响应超时。', _participantTimeout),
              );
          if (result.status == InputRepairStepStatus.failure) {
            phaseStatus = InputRepairStepStatus.failure;
          } else if (result.status == InputRepairStepStatus.warning &&
              phaseStatus == InputRepairStepStatus.success) {
            phaseStatus = InputRepairStepStatus.warning;
          }
          final message = nullIfBlank(result.message);
          if (message != null) {
            details.add('${participant.debugLabel}: $message');
          }
        } catch (error, stack) {
          if (phaseStatus == InputRepairStepStatus.success) {
            phaseStatus = InputRepairStepStatus.warning;
          }
          silentLog(
            'input_repair',
            '修复参与者 ${participant.debugLabel}',
            error,
            stack,
          );
          details.add(
            '${participant.debugLabel}: ${userFailureMessage(error, fallback: '执行失败。')}',
          );
        }
      }
      steps.add(
        InputRepairStepReport(
          stage: phase == InputRepairParticipantPhase.beforeTextInputReset
              ? InputRepairStage.resetParticipantsBefore
              : InputRepairStage.resetParticipantsAfter,
          status: phaseStatus,
          message: details.isEmpty ? null : details.join('; '),
        ),
      );
    }

    Future<void> runPlatformStep({
      required InputRepairStage stage,
      required String action,
      required String failureMessage,
      required Future<void> Function() operation,
    }) async {
      try {
        await operation().timeout(
          _platformChannelTimeout,
          onTimeout: () =>
              throw TimeoutException('$action超时。', _platformChannelTimeout),
        );
        steps.add(
          InputRepairStepReport(
            stage: stage,
            status: InputRepairStepStatus.success,
          ),
        );
      } catch (error, stack) {
        silentLog('input_repair', action, error, stack);
        steps.add(
          InputRepairStepReport(
            stage: stage,
            status: InputRepairStepStatus.warning,
            message: userFailureMessage(error, fallback: failureMessage),
          ),
        );
      }
    }

    try {
      await runParticipants(InputRepairParticipantPhase.beforeTextInputReset);

      await killAllTrackedChildren();
      steps.add(
        const InputRepairStepReport(
          stage: InputRepairStage.killTrackedChildren,
          status: InputRepairStepStatus.success,
        ),
      );

      directChildrenKilled = await killAllDirectChildren();
      steps.add(
        InputRepairStepReport(
          stage: InputRepairStage.killDirectChildren,
          status: InputRepairStepStatus.success,
          message: '$directChildrenKilled',
        ),
      );

      savedFocus?.unfocus();
      await runPlatformStep(
        stage: InputRepairStage.clearTextInputClient,
        action: '清理文本输入客户端',
        failureMessage: '清理文本输入客户端失败。',
        operation: () => SystemChannels.textInput.invokeMethod<void>(
          'TextInput.clearClient',
        ),
      );
      await runPlatformStep(
        stage: InputRepairStage.hideTextInput,
        action: '隐藏文本输入',
        failureMessage: '隐藏文本输入失败。',
        operation: () =>
            SystemChannels.textInput.invokeMethod<void>('TextInput.hide'),
      );
      await runPlatformStep(
        stage: InputRepairStage.finishAutofillContext,
        action: '结束自动填充上下文',
        failureMessage: '结束自动填充失败。',
        operation: () => SystemChannels.textInput.invokeMethod<void>(
          'TextInput.finishAutofillContext',
          false,
        ),
      );
      await runPlatformStep(
        stage: InputRepairStage.requestExistingInputState,
        action: '请求现有输入状态',
        failureMessage: '恢复文本输入状态失败。',
        operation: () => SystemChannels.textInput.invokeMethod<void>(
          'TextInput.requestExistingInputState',
        ),
      );

      sentinelFocusNode.requestFocus();
      steps.add(
        const InputRepairStepReport(
          stage: InputRepairStage.focusSentinel,
          status: InputRepairStepStatus.success,
        ),
      );
      await Future<void>.delayed(_focusSettleDelay);

      await runParticipants(InputRepairParticipantPhase.afterTextInputReset);

      final canRestore =
          savedFocus != null &&
          savedFocus.context != null &&
          (isSafeRestoreTarget?.call(savedFocus) ?? false);
      if (canRestore) {
        savedFocus.requestFocus();
        restoredFocus = savedFocus;
        steps.add(
          InputRepairStepReport(
            stage: InputRepairStage.restoreSafeFocus,
            status: InputRepairStepStatus.success,
            message: _focusLabel(savedFocus),
          ),
        );
      } else {
        steps.add(
          const InputRepairStepReport(
            stage: InputRepairStage.restoreSafeFocus,
            status: InputRepairStepStatus.warning,
            message: '已跳过不安全的焦点恢复。',
          ),
        );
      }
    } catch (error, stack) {
      silentLog('input_repair', '修复文本输入', error, stack);
      steps.add(
        InputRepairStepReport(
          stage: InputRepairStage.restoreSafeFocus,
          status: InputRepairStepStatus.failure,
          message: userFailureMessage(error, fallback: '输入修复流程执行失败。'),
        ),
      );
    }

    final hasFailure = steps.any(
      (step) => step.status == InputRepairStepStatus.failure,
    );
    final hasWarning = steps.any(
      (step) => step.status == InputRepairStepStatus.warning,
    );
    final report = InputRepairReport(
      result: hasFailure
          ? InputRepairResult.failure
          : hasWarning
          ? InputRepairResult.partialSuccess
          : InputRepairResult.success,
      steps: List<InputRepairStepReport>.unmodifiable(steps),
      trackedChildrenBefore: trackedChildrenBefore,
      directChildrenKilled: directChildrenKilled,
      primaryFocusBeforeLabel: primaryFocusBeforeLabel,
      primaryFocusAfterLabel: _focusLabel(FocusManager.instance.primaryFocus),
      restoredFocusLabel: _focusLabel(restoredFocus),
    );
    return report;
  }

  String? _focusLabel(FocusNode? node) {
    if (node == null) return null;
    final label = nullIfBlank(node.debugLabel);
    if (label != null) return label;
    return node.runtimeType.toString();
  }
}
