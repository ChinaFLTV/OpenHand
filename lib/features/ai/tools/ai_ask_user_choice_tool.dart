import 'dart:async';
import 'dart:convert';

import '../service/ai_bash_tool_service.dart';
import '../service/ai_tool_runtime_service.dart';
import 'ai_tool.dart';
import 'ai_tool_execution_context.dart';
import 'ai_tool_utils.dart';

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
  });

  final String title;
  final String? description;
  final List<AskUserChoiceOption> options;
  final bool allowCustomInput;
  final String? confirmLabel;
  final String? cancelLabel;
  final String? customOptionLabel;
  final String? customInputHint;
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
  const AskUserChoiceResponse({
    required this.value,
    required this.isCustom,
  });

  final String value;
  final bool isCustom;
}

/// UI-side presenter contract used by [AiAskUserChoiceTool].
///
/// The UI layer registers an implementation via
/// [AiAskUserChoiceTool.registerPresenter]. The tool calls this presenter
/// whenever the model invokes the `AskUserChoice` tool, and awaits the
/// user's choice (or cancellation).
typedef AskUserChoicePresenter = Future<AskUserChoiceResponse?> Function(
  AskUserChoiceRequest request,
);

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
  AiAskUserChoiceTool();

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
    final args = context.decodedArguments;
    final title = '${args['title'] ?? ''}'.trim();
    if (title.isEmpty) {
      return AiToolUtils.invalidResult(
        'AskUserChoice',
        'AskUserChoice requires a non-empty "title".',
      );
    }
    final description = args['description'] is String
        ? (args['description'] as String).trim()
        : null;
    final optionsRaw = args['options'];
    if (optionsRaw is! List || optionsRaw.isEmpty) {
      return AiToolUtils.invalidResult(
        'AskUserChoice',
        'AskUserChoice requires a non-empty "options" array.',
      );
    }
    final parsedOptions = <AskUserChoiceOption>[];
    final seenValues = <String>{};
    for (var i = 0; i < optionsRaw.length; i++) {
      final entry = optionsRaw[i];
      if (entry is! Map) {
        return AiToolUtils.invalidResult(
          'AskUserChoice',
          'AskUserChoice option #$i must be an object with {value, label}.',
        );
      }
      final value = '${entry['value'] ?? ''}'.trim();
      final label = '${entry['label'] ?? ''}'.trim();
      if (value.isEmpty || label.isEmpty) {
        return AiToolUtils.invalidResult(
          'AskUserChoice',
          'AskUserChoice option #$i is missing a non-empty "value" or "label".',
        );
      }
      if (!seenValues.add(value)) {
        return AiToolUtils.invalidResult(
          'AskUserChoice',
          'AskUserChoice option values must be unique; duplicate: "$value".',
        );
      }
      final optDescription = entry['description'] is String
          ? (entry['description'] as String).trim()
          : null;
      parsedOptions.add(AskUserChoiceOption(
        value: value,
        label: label,
        description: optDescription?.isEmpty == true ? null : optDescription,
      ));
    }
    final allowCustomInput = args['allow_custom_input'] is bool
        ? args['allow_custom_input'] as bool
        : true;

    final presenter = _presenter;
    if (presenter == null) {
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: 'AskUserChoice',
        workingDirectory: AiToolUtils.defaultWorkingDirectory(),
        stdout: '',
        stderr:
            'AskUserChoice UI presenter is not registered. Fall back to asking the user in plain chat.',
        durationMs: stopwatch.elapsedMilliseconds,
        resultText:
            'status: failed\nerror: AskUserChoice UI presenter is not registered.',
      );
    }

    AskUserChoiceResponse? response;
    try {
      response = await presenter(AskUserChoiceRequest(
        title: title,
        description: (description?.isEmpty ?? true) ? null : description,
        options: parsedOptions,
        allowCustomInput: allowCustomInput,
        confirmLabel: _optionalString(args['confirm_label']),
        cancelLabel: _optionalString(args['cancel_label']),
        customOptionLabel: _optionalString(args['custom_option_label']),
        customInputHint: _optionalString(args['custom_input_hint']),
      ));
    } on TimeoutException catch (error) {
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.timedOut,
        command: 'AskUserChoice',
        workingDirectory: AiToolUtils.defaultWorkingDirectory(),
        stdout: '',
        stderr: 'AskUserChoice timed out: $error',
        durationMs: stopwatch.elapsedMilliseconds,
        resultText: 'status: timed_out\nerror: $error',
      );
    } catch (error, stackTrace) {
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: 'AskUserChoice',
        workingDirectory: AiToolUtils.defaultWorkingDirectory(),
        stdout: '',
        stderr: 'AskUserChoice failed: $error\n$stackTrace',
        durationMs: stopwatch.elapsedMilliseconds,
        resultText: 'status: failed\nerror: $error',
      );
    }

    if (response == null) {
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.cancelled,
        command: 'AskUserChoice',
        workingDirectory: AiToolUtils.defaultWorkingDirectory(),
        stdout: '',
        stderr: 'The user dismissed the AskUserChoice dialog.',
        durationMs: stopwatch.elapsedMilliseconds,
        resultText:
            'status: cancelled\ndetail: user dismissed the choice dialog',
      );
    }

    final payload = <String, Object?>{
      'value': response.value,
      'is_custom': response.isCustom,
    };
    final encoded = const JsonEncoder.withIndent('  ').convert(payload);
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.success,
      command: 'AskUserChoice',
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
}
