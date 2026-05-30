import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

class InputRepairService {
  InputRepairService._();

  static final InputRepairService instance = InputRepairService._();

  final Map<Object, _InputRepairParticipant> _participants =
      <Object, _InputRepairParticipant>{};
  Future<void> Function()? debugKillTrackedChildrenOverride;
  Future<int> Function()? debugKillDirectChildrenOverride;
  Future<void> Function(String method, [Object? arguments])?
  debugTextInputMethodOverride;
  Duration debugFocusSettleDelay = const Duration(milliseconds: 60);

  InputRepairReport? _lastReport;
  InputRepairReport? get lastReport => _lastReport;

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

  @visibleForTesting
  void resetForTest() {
    _participants.clear();
    _lastReport = null;
    debugKillTrackedChildrenOverride = null;
    debugKillDirectChildrenOverride = null;
    debugTextInputMethodOverride = null;
    debugFocusSettleDelay = const Duration(milliseconds: 60);
  }

  Future<void> _invokeTextInputMethod(
    String method, [
    Object? arguments,
  ]) async {
    final override = debugTextInputMethodOverride;
    if (override != null) {
      await override(method, arguments);
      return;
    }
    await SystemChannels.textInput.invokeMethod<void>(method, arguments);
  }

  Future<InputRepairReport> repair({
    required FocusNode sentinelFocusNode,
    bool Function(FocusNode node)? isSafeRestoreTarget,
  }) async {
    final steps = <InputRepairStepReport>[];
    final trackedChildrenBefore = debugTrackedChildPids().length;
    final savedFocus = FocusManager.instance.primaryFocus;
    final primaryFocusBeforeLabel = _focusLabel(savedFocus);
    FocusNode? restoredFocus;
    var directChildrenKilled = 0;

    Future<void> runParticipants(InputRepairParticipantPhase phase) async {
      var sawWarning = false;
      for (final participant in _participants.values) {
        try {
          final result = await participant.onRepair(phase);
          if (result.status == InputRepairStepStatus.warning) {
            sawWarning = true;
          }
          if (result.status == InputRepairStepStatus.failure) {
            sawWarning = true;
          }
        } catch (error, stack) {
          sawWarning = true;
          silentLog(
            'input_repair',
            'participant ${participant.debugLabel}',
            error,
            stack,
          );
        }
      }
      steps.add(
        InputRepairStepReport(
          stage: phase == InputRepairParticipantPhase.beforeTextInputReset
              ? InputRepairStage.resetParticipantsBefore
              : InputRepairStage.resetParticipantsAfter,
          status: sawWarning
              ? InputRepairStepStatus.warning
              : InputRepairStepStatus.success,
        ),
      );
    }

    try {
      await runParticipants(InputRepairParticipantPhase.beforeTextInputReset);

      await (debugKillTrackedChildrenOverride?.call() ??
          killAllTrackedChildren());
      steps.add(
        const InputRepairStepReport(
          stage: InputRepairStage.killTrackedChildren,
          status: InputRepairStepStatus.success,
        ),
      );

      directChildrenKilled =
          await (debugKillDirectChildrenOverride?.call() ??
              killAllDirectChildren());
      steps.add(
        InputRepairStepReport(
          stage: InputRepairStage.killDirectChildren,
          status: InputRepairStepStatus.success,
          message: '$directChildrenKilled',
        ),
      );

      savedFocus?.unfocus();
      try {
        await _invokeTextInputMethod('TextInput.clearClient');
        steps.add(
          const InputRepairStepReport(
            stage: InputRepairStage.clearTextInputClient,
            status: InputRepairStepStatus.success,
          ),
        );
      } catch (error, stack) {
        silentLog('input_repair', 'clearClient', error, stack);
        steps.add(
          InputRepairStepReport(
            stage: InputRepairStage.clearTextInputClient,
            status: InputRepairStepStatus.warning,
            message: '$error',
          ),
        );
      }

      try {
        await _invokeTextInputMethod('TextInput.hide');
        steps.add(
          const InputRepairStepReport(
            stage: InputRepairStage.hideTextInput,
            status: InputRepairStepStatus.success,
          ),
        );
      } catch (error, stack) {
        silentLog('input_repair', 'hideTextInput', error, stack);
        steps.add(
          InputRepairStepReport(
            stage: InputRepairStage.hideTextInput,
            status: InputRepairStepStatus.warning,
            message: '$error',
          ),
        );
      }

      try {
        await _invokeTextInputMethod('TextInput.finishAutofillContext', false);
        steps.add(
          const InputRepairStepReport(
            stage: InputRepairStage.finishAutofillContext,
            status: InputRepairStepStatus.success,
          ),
        );
      } catch (error, stack) {
        silentLog('input_repair', 'finishAutofillContext', error, stack);
        steps.add(
          InputRepairStepReport(
            stage: InputRepairStage.finishAutofillContext,
            status: InputRepairStepStatus.warning,
            message: '$error',
          ),
        );
      }

      try {
        await _invokeTextInputMethod('TextInput.requestExistingInputState');
        steps.add(
          const InputRepairStepReport(
            stage: InputRepairStage.requestExistingInputState,
            status: InputRepairStepStatus.success,
          ),
        );
      } catch (error, stack) {
        silentLog('input_repair', 'requestExistingInputState', error, stack);
        steps.add(
          InputRepairStepReport(
            stage: InputRepairStage.requestExistingInputState,
            status: InputRepairStepStatus.warning,
            message: '$error',
          ),
        );
      }

      sentinelFocusNode.requestFocus();
      steps.add(
        const InputRepairStepReport(
          stage: InputRepairStage.focusSentinel,
          status: InputRepairStepStatus.success,
        ),
      );
      if (debugFocusSettleDelay > Duration.zero) {
        await Future<void>.delayed(debugFocusSettleDelay);
      }

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
          InputRepairStepReport(
            stage: InputRepairStage.restoreSafeFocus,
            status: InputRepairStepStatus.warning,
            message: canRestore ? null : 'skip_unsafe_restore',
          ),
        );
      }
    } catch (error, stack) {
      silentLog('input_repair', 'repair', error, stack);
      steps.add(
        InputRepairStepReport(
          stage: InputRepairStage.restoreSafeFocus,
          status: InputRepairStepStatus.failure,
          message: '$error',
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
    _lastReport = report;
    return report;
  }

  String? _focusLabel(FocusNode? node) {
    if (node == null) return null;
    final label = node.debugLabel;
    if (label != null && label.trim().isNotEmpty) {
      return label.trim();
    }
    return node.runtimeType.toString();
  }
}
