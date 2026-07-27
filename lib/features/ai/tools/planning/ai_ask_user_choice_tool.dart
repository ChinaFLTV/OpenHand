import 'dart:async';

import '../../../../shared/util/input_value_parsing.dart';
import '../../service/bash/ai_bash_tool_service.dart';
import '../../service/runtime/ai_plan_approval_detector.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';

/// Request object passed from the [AiAskUserChoiceTool] to the UI presenter.
class AskUserChoiceRequest {
  const AskUserChoiceRequest({
    required this.title,
    required this.options,
    this.description,
    this.allowCustomInput = true,
    this.confirmLabel,
    this.cancelLabel,
    this.customOptionLabel,
    this.customInputHint,
    this.cancelSignal,
  });

  final String title;
  final String? description;
  final List<AskUserChoiceOption> options;
  final bool allowCustomInput;
  final String? confirmLabel;
  final String? cancelLabel;
  final String? customOptionLabel;
  final String? customInputHint;
  final Future<void>? cancelSignal;
}

class AskUserChoiceOption {
  const AskUserChoiceOption({
    required this.value,
    required this.label,
    this.description,
  });

  final String value;
  final String label;
  final String? description;
}

/// Response returned from the UI presenter to the tool.
///
/// A `null` response is treated as user dismissal / cancellation.
class AskUserChoiceResponse {
  const AskUserChoiceResponse({required this.value, required this.isCustom});

  final String value;
  final bool isCustom;
}

/// UI-side presenter contract used by [AiAskUserChoiceTool].
///
/// The UI layer registers an implementation via
/// [AiAskUserChoiceTool.registerPresenter]. The tool calls this presenter
/// whenever the model invokes the `AskUserChoice` tool, and awaits the
/// user's choice (or cancellation).
typedef AskUserChoicePresenter =
    Future<AskUserChoiceResponse?> Function(AskUserChoiceRequest request);

/// A built-in AI tool that lets the model ask the user to pick one answer
/// from a small, well-defined list of options — plus an optional free-form
/// "custom input" radio, rendered as a modal dialog that honors the global
/// dialog animation settings.
///
/// The UI layer must register a presenter via [registerPresenter] during app
/// startup. When no presenter is registered, the tool returns a structured
/// failure describing the missing UI bridge so the model can recover
/// gracefully (e.g. fall back to asking the question in chat text).
class AiAskUserChoiceTool extends AiTool {
  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.askUserChoice;

  @override
  bool get isDestructive => false;

  static AskUserChoicePresenter? _presenter;

  /// Registers the UI-side presenter. Returns a disposer that unregisters
  /// the presenter (useful when the hosting widget is disposed).
  static void Function() registerPresenter(AskUserChoicePresenter presenter) {
    _presenter = presenter;
    return () {
      if (_presenter == presenter) {
        _presenter = null;
      }
    };
  }

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final stopwatch = Stopwatch()..start();
    final commandName = _commandName(context);
    final normalized = _normalizeArguments(
      context.decodedArguments,
      commandName: commandName,
    );
    if (normalized.error != null) {
      return normalized.error!;
    }
    final normalizedValue = normalized.value!;
    final args = normalizedValue.arguments;
    final title = AiToolUtils.readString(args['title']);
    if (title.isEmpty) {
      return AiToolUtils.invalidResult(
        commandName,
        '$commandName requires a non-empty "title".',
      );
    }
    final description = args['description'] is String
        ? AiToolUtils.readString(args['description'])
        : null;
    final optionsRaw = AiToolUtils.readList(args['options']);
    if (optionsRaw == null || optionsRaw.isEmpty) {
      return AiToolUtils.invalidResult(
        commandName,
        '$commandName requires a non-empty "options" array.',
      );
    }
    final parsedOptions = <AskUserChoiceOption>[];
    final seenValues = <String>{};
    for (var i = 0; i < optionsRaw.length; i++) {
      final entry = optionsRaw[i];
      if (entry is! Map) {
        return AiToolUtils.invalidResult(
          commandName,
          '$commandName option #$i must be an object with {value, label}.',
        );
      }
      final entryMap = stringKeyedMapFromValue(entry);
      final value = '${entryMap['value'] ?? ''}'.trim();
      final label = '${entryMap['label'] ?? ''}'.trim();
      if (value.isEmpty || label.isEmpty) {
        return AiToolUtils.invalidResult(
          commandName,
          '$commandName option #$i is missing a non-empty "value" or "label".',
        );
      }
      if (!seenValues.add(value)) {
        return AiToolUtils.invalidResult(
          commandName,
          '$commandName option values must be unique; duplicate: "$value".',
        );
      }
      final optDescription = entryMap['description'] is String
          ? (entryMap['description'] as String).trim()
          : null;
      parsedOptions.add(
        AskUserChoiceOption(
          value: value,
          label: label,
          description: optDescription?.isEmpty == true ? null : optDescription,
        ),
      );
    }
    final allowCustomInput = boolFromValue(
      args['allow_custom_input'],
      defaultValue: true,
    );
    if (_looksLikePlanApprovalQuestion(
      metadata: context.metadata,
      title: title,
      description: description,
    )) {
      return AiToolUtils.withMergedMetadata(
        AiToolUtils.invalidResult(
          commandName,
          'Do not use $commandName to request plan approval in Plan mode. '
          'Clarify requirements with $commandName before finalizing the plan; '
          'when the plan is ready, use ExitPlanMode instead.',
        ),
        <String, Object?>{
          'ask_user_choice_blocked_plan_approval': true,
          'ask_user_choice_block_reason':
              'plan_approval_requires_exit_plan_mode',
          'plan_approval_tool': 'ExitPlanMode',
          'plan_mode_active': context.metadata['plan_mode_active'] == true,
          'awaiting_plan_approval':
              context.metadata['awaiting_plan_approval'] == true,
          'plan_mode_execution_approved_for_send':
              context.metadata['plan_mode_execution_approved_for_send'] == true,
        },
      );
    }

    final presenter = _presenter;
    if (presenter == null) {
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: commandName,
        workingDirectory: AiToolUtils.defaultWorkingDirectory(),
        stdout: '',
        stderr:
            '$commandName UI presenter is not registered. Fall back to asking the user in plain chat.',
        durationMs: stopwatch.elapsedMilliseconds,
        resultText:
            'status: failed\nerror: $commandName UI presenter is not registered.',
      );
    }

    AskUserChoiceResponse? response;
    var cancelledBySignal = false;
    context.cancelSignal?.then<void>(
      (_) => cancelledBySignal = true,
      onError: (Object _, StackTrace _) {
        cancelledBySignal = true;
      },
    );
    try {
      response =
          await AiToolUtils.awaitWithCancellation<AskUserChoiceResponse?>(
            presenter(
              AskUserChoiceRequest(
                title: title,
                description: (description?.isEmpty ?? true)
                    ? null
                    : description,
                options: parsedOptions,
                allowCustomInput: allowCustomInput,
                confirmLabel: _optionalString(args['confirm_label']),
                cancelLabel: _optionalString(args['cancel_label']),
                customOptionLabel: _optionalString(args['custom_option_label']),
                customInputHint: _optionalString(args['custom_input_hint']),
                cancelSignal: context.cancelSignal,
              ),
            ),
            cancelSignal: context.cancelSignal,
          );
    } on TimeoutException catch (error) {
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.timedOut,
        command: commandName,
        workingDirectory: AiToolUtils.defaultWorkingDirectory(),
        stdout: '',
        stderr: '$commandName timed out: $error',
        durationMs: stopwatch.elapsedMilliseconds,
        resultText: 'status: timed_out\nerror: $error',
      );
    } catch (error, stackTrace) {
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: commandName,
        workingDirectory: AiToolUtils.defaultWorkingDirectory(),
        stdout: '',
        stderr: '$commandName failed: $error\n$stackTrace',
        durationMs: stopwatch.elapsedMilliseconds,
        resultText: 'status: failed\nerror: $error',
      );
    }

    if (response == null) {
      if (cancelledBySignal) {
        return AiToolUtils.cancelledResult(
          command: commandName,
          durationMs: stopwatch.elapsedMilliseconds,
          metadata: const <String, Object?>{
            'ask_user_choice_cancelled_by_signal': true,
          },
        );
      }
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.cancelled,
        command: commandName,
        workingDirectory: AiToolUtils.defaultWorkingDirectory(),
        stdout: '',
        stderr: 'The user dismissed the $commandName dialog.',
        durationMs: stopwatch.elapsedMilliseconds,
        resultText:
            'status: cancelled\ndetail: user dismissed the choice dialog',
      );
    }

    final payload = normalizedValue.claudeQuestion == null
        ? <String, Object?>{
            'value': response.value,
            'is_custom': response.isCustom,
          }
        : <String, Object?>{
            'questions': <Map<String, Object?>>[
              normalizedValue.claudeQuestion!,
            ],
            'answers': <String, Object?>{title: response.value},
          };
    final encoded = prettyPrintJson(payload);
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.success,
      command: commandName,
      workingDirectory: AiToolUtils.defaultWorkingDirectory(),
      stdout: encoded,
      stderr: '',
      durationMs: stopwatch.elapsedMilliseconds,
      resultText: encoded,
      metadata: <String, Object?>{
        'ask_user_choice_value': response.value,
        'ask_user_choice_is_custom': response.isCustom,
      },
    );
  }

  static String? _optionalString(Object? raw) {
    if (raw is! String) return null;
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String _commandName(AiToolExecutionContext context) {
    final name = context.toolCall.name.trim();
    return name.isEmpty ? 'AskUserChoice' : name;
  }

  static _AskUserChoiceArgumentNormalization _normalizeArguments(
    Map<String, Object?> args, {
    required String commandName,
  }) {
    if (!args.containsKey('questions')) {
      return _AskUserChoiceArgumentNormalization.value(
        _AskUserChoiceNormalizedArguments(arguments: args),
      );
    }

    for (final key in const <String>['answers', 'annotations', 'metadata']) {
      if (args.containsKey(key)) {
        return _AskUserChoiceArgumentNormalization.error(
          AiToolUtils.invalidResult(
            commandName,
            'OpenHand supports AskUserQuestion only for new single-question prompts; "$key" is not supported.',
          ),
        );
      }
    }

    final questionsRaw = AiToolUtils.readList(args['questions']);
    if (questionsRaw == null) {
      return _AskUserChoiceArgumentNormalization.error(
        AiToolUtils.invalidResult(
          commandName,
          'AskUserQuestion requires "questions" to be an array.',
        ),
      );
    }
    if (questionsRaw.length != 1) {
      return _AskUserChoiceArgumentNormalization.error(
        AiToolUtils.invalidResult(
          commandName,
          'OpenHand supports AskUserQuestion only with exactly one question. Split multi-question prompts into separate AskUserChoice calls.',
        ),
      );
    }

    final questionRaw = questionsRaw.single;
    if (questionRaw is! Map) {
      return _AskUserChoiceArgumentNormalization.error(
        AiToolUtils.invalidResult(
          commandName,
          'AskUserQuestion question #0 must be an object.',
        ),
      );
    }
    final questionMap = stringKeyedMapFromValue(questionRaw);
    final multiSelect = _optionalBool(questionMap['multiSelect']);
    if (multiSelect == true) {
      return _AskUserChoiceArgumentNormalization.error(
        AiToolUtils.invalidResult(
          commandName,
          'OpenHand AskUserQuestion compatibility does not support multiSelect. Ask separate single-choice questions instead.',
        ),
      );
    }
    if (questionMap.containsKey('multiSelect') && multiSelect == null) {
      return _AskUserChoiceArgumentNormalization.error(
        AiToolUtils.invalidResult(
          commandName,
          'AskUserQuestion "multiSelect" must be a boolean when provided.',
        ),
      );
    }

    final questionText = _optionalString(questionMap['question']);
    if (questionText == null) {
      return _AskUserChoiceArgumentNormalization.error(
        AiToolUtils.invalidResult(
          commandName,
          'AskUserQuestion requires a non-empty question text.',
        ),
      );
    }
    final optionsRaw = AiToolUtils.readList(questionMap['options']);
    if (optionsRaw == null || optionsRaw.length < 2 || optionsRaw.length > 4) {
      return _AskUserChoiceArgumentNormalization.error(
        AiToolUtils.invalidResult(
          commandName,
          'AskUserQuestion requires 2-4 options for the single supported question.',
        ),
      );
    }

    final openHandOptions = <Map<String, Object?>>[];
    final claudeOptions = <Map<String, Object?>>[];
    for (var i = 0; i < optionsRaw.length; i++) {
      final optionRaw = optionsRaw[i];
      if (optionRaw is! Map) {
        return _AskUserChoiceArgumentNormalization.error(
          AiToolUtils.invalidResult(
            commandName,
            'AskUserQuestion option #$i must be an object.',
          ),
        );
      }
      final optionMap = stringKeyedMapFromValue(optionRaw);
      if (optionMap.containsKey('preview')) {
        return _AskUserChoiceArgumentNormalization.error(
          AiToolUtils.invalidResult(
            commandName,
            'OpenHand AskUserQuestion compatibility does not support option preview. Ask without preview or use plain chat for the preview content.',
          ),
        );
      }
      final label = _optionalString(optionMap['label']);
      if (label == null) {
        return _AskUserChoiceArgumentNormalization.error(
          AiToolUtils.invalidResult(
            commandName,
            'AskUserQuestion option #$i requires a non-empty label.',
          ),
        );
      }
      final description = _optionalString(optionMap['description']);
      openHandOptions.add(<String, Object?>{
        'value': label,
        'label': label,
        if (description != null) 'description': description,
      });
      claudeOptions.add(<String, Object?>{
        'label': label,
        if (description != null) 'description': description,
      });
    }

    final header = _optionalString(questionMap['header']);
    final claudeQuestion = <String, Object?>{
      'question': questionText,
      if (header != null) 'header': header,
      'options': claudeOptions,
      'multiSelect': false,
    };
    return _AskUserChoiceArgumentNormalization.value(
      _AskUserChoiceNormalizedArguments(
        arguments: <String, Object?>{
          'title': questionText,
          if (header != null) 'description': header,
          'options': openHandOptions,
          'allow_custom_input': false,
        },
        claudeQuestion: claudeQuestion,
      ),
    );
  }

  static bool? _optionalBool(Object? raw) {
    if (raw == null) return false;
    return AiToolUtils.readBool(raw);
  }

  static bool _looksLikePlanApprovalQuestion({
    required Map<String, Object?> metadata,
    required String title,
    required String? description,
  }) {
    final planModeActive = metadata['plan_mode_active'] == true;
    final executionApproved =
        metadata['plan_mode_execution_approved_for_send'] == true;
    if (!planModeActive || executionApproved) {
      return false;
    }
    final text = '${title.toLowerCase()} ${description?.toLowerCase() ?? ''}';
    return AiPlanApprovalDetector.looksLikePlanApprovalRequest(text);
  }
}

class _AskUserChoiceArgumentNormalization {
  const _AskUserChoiceArgumentNormalization.value(this.value) : error = null;

  const _AskUserChoiceArgumentNormalization.error(this.error) : value = null;

  final _AskUserChoiceNormalizedArguments? value;
  final AiToolExecutionResult? error;
}

class _AskUserChoiceNormalizedArguments {
  const _AskUserChoiceNormalizedArguments({
    required this.arguments,
    this.claudeQuestion,
  });

  final Map<String, Object?> arguments;
  final Map<String, Object?>? claudeQuestion;
}
