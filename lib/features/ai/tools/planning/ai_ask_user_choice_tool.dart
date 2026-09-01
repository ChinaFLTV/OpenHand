import 'dart:async';

import '../../../../app/support/silent_log.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../service/bash/ai_bash_tool_service.dart';
import '../../service/runtime/ai_plan_approval_detector.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';

/// [AiAskUserChoiceTool] 传给 UI 呈现器的请求。
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

/// UI 呈现器返回的响应；null 表示用户关闭或取消。
class AskUserChoiceResponse {
  const AskUserChoiceResponse({required this.value, required this.isCustom});

  final String value;
  final bool isCustom;
}

/// [AiAskUserChoiceTool] 使用的 UI 呈现器契约。
typedef AskUserChoicePresenter =
    Future<AskUserChoiceResponse?> Function(AskUserChoiceRequest request);

/// 通过遵循全局动画设置的弹窗，让用户从有限选项中选择或输入自定义内容。
/// UI 层须在启动时通过 [registerPresenter] 注册呈现器。
class AiAskUserChoiceTool extends AiTool {
  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.askUserChoice;

  @override
  bool get isDestructive => false;

  static AskUserChoicePresenter? _presenter;

  /// 注册 UI 呈现器，并返回对应的注销回调。
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
      return AiToolUtils.invalidResult(commandName, '$commandName 需要非空 title。');
    }
    final description = args['description'] is String
        ? AiToolUtils.readString(args['description'])
        : null;
    final optionsRaw = AiToolUtils.readList(args['options']);
    if (optionsRaw == null || optionsRaw.isEmpty) {
      return AiToolUtils.invalidResult(
        commandName,
        '$commandName 需要非空 options 数组。',
      );
    }
    final parsedOptions = <AskUserChoiceOption>[];
    final seenValues = <String>{};
    for (var i = 0; i < optionsRaw.length; i++) {
      final entry = optionsRaw[i];
      if (entry is! Map) {
        return AiToolUtils.invalidResult(
          commandName,
          '$commandName 的第 $i 个选项必须为包含 value 和 label 的对象。',
        );
      }
      final entryMap = stringKeyedMapFromValue(entry);
      final value = '${entryMap['value'] ?? ''}'.trim();
      final label = '${entryMap['label'] ?? ''}'.trim();
      if (value.isEmpty || label.isEmpty) {
        return AiToolUtils.invalidResult(
          commandName,
          '$commandName 的第 $i 个选项缺少非空 value 或 label。',
        );
      }
      if (!seenValues.add(value)) {
        return AiToolUtils.invalidResult(
          commandName,
          '$commandName 的选项 value 必须唯一，重复值：“$value”。',
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
          '计划模式中禁止使用 $commandName 请求计划审批。'
          '计划定稿前可用 $commandName 澄清需求；计划就绪后请使用 ExitPlanMode。',
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
        stderr: '$commandName 的 UI 呈现器未注册，请改用普通对话询问用户。',
        durationMs: stopwatch.elapsedMilliseconds,
        resultText: 'status: failed\nerror: $commandName 的 UI 呈现器未注册。',
      );
    }

    AskUserChoiceResponse? response;
    var cancelledBySignal = false;
    unawaited(
      context.cancelSignal?.then<void>(
        (_) => cancelledBySignal = true,
        onError: (Object _, StackTrace _) {
          cancelledBySignal = true;
        },
      ),
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
        stderr: '$commandName 超时：$error',
        durationMs: stopwatch.elapsedMilliseconds,
        resultText: 'status: timed_out\nerror: $error',
      );
    } catch (error, stackTrace) {
      silentLog('ai_ask_user_choice_tool', '执行用户选择弹窗', error, stackTrace);
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: commandName,
        workingDirectory: AiToolUtils.defaultWorkingDirectory(),
        stdout: '',
        stderr: '$commandName 执行失败：$error',
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
        stderr: '用户关闭了 $commandName 弹窗。',
        durationMs: stopwatch.elapsedMilliseconds,
        resultText: 'status: cancelled\ndetail: 用户关闭了选择弹窗',
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
            'OpenHand 仅支持新的单问题 AskUserQuestion，不支持字段“$key”。',
          ),
        );
      }
    }

    final questionsRaw = AiToolUtils.readList(args['questions']);
    if (questionsRaw == null) {
      return _AskUserChoiceArgumentNormalization.error(
        AiToolUtils.invalidResult(
          commandName,
          'AskUserQuestion 的 questions 必须为数组。',
        ),
      );
    }
    if (questionsRaw.length != 1) {
      return _AskUserChoiceArgumentNormalization.error(
        AiToolUtils.invalidResult(
          commandName,
          'OpenHand 的 AskUserQuestion 仅支持一个问题，请将多个问题拆为独立 AskUserChoice 调用。',
        ),
      );
    }

    final questionRaw = questionsRaw.single;
    if (questionRaw is! Map) {
      return _AskUserChoiceArgumentNormalization.error(
        AiToolUtils.invalidResult(
          commandName,
          'AskUserQuestion 的第 0 个问题必须为对象。',
        ),
      );
    }
    final questionMap = stringKeyedMapFromValue(questionRaw);
    final multiSelect = _optionalBool(questionMap['multiSelect']);
    if (multiSelect == true) {
      return _AskUserChoiceArgumentNormalization.error(
        AiToolUtils.invalidResult(
          commandName,
          'OpenHand 的 AskUserQuestion 兼容模式不支持 multiSelect，请拆为多个单选问题。',
        ),
      );
    }
    if (questionMap.containsKey('multiSelect') && multiSelect == null) {
      return _AskUserChoiceArgumentNormalization.error(
        AiToolUtils.invalidResult(
          commandName,
          'AskUserQuestion 的 multiSelect 必须为布尔值。',
        ),
      );
    }

    final questionText = _optionalString(questionMap['question']);
    if (questionText == null) {
      return _AskUserChoiceArgumentNormalization.error(
        AiToolUtils.invalidResult(commandName, 'AskUserQuestion 需要非空问题文本。'),
      );
    }
    final optionsRaw = AiToolUtils.readList(questionMap['options']);
    if (optionsRaw == null || optionsRaw.length < 2 || optionsRaw.length > 4) {
      return _AskUserChoiceArgumentNormalization.error(
        AiToolUtils.invalidResult(
          commandName,
          'AskUserQuestion 的单个问题需要 2 到 4 个选项。',
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
            'AskUserQuestion 的第 $i 个选项必须为对象。',
          ),
        );
      }
      final optionMap = stringKeyedMapFromValue(optionRaw);
      if (optionMap.containsKey('preview')) {
        return _AskUserChoiceArgumentNormalization.error(
          AiToolUtils.invalidResult(
            commandName,
            'OpenHand 的 AskUserQuestion 兼容模式不支持选项 preview，请移除 preview 或改用普通对话展示。',
          ),
        );
      }
      final label = _optionalString(optionMap['label']);
      if (label == null) {
        return _AskUserChoiceArgumentNormalization.error(
          AiToolUtils.invalidResult(
            commandName,
            'AskUserQuestion 的第 $i 个选项需要非空 label。',
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
