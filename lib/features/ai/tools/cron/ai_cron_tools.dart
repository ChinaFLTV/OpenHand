import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../../app/model/cron_config.dart';
import '../../../../app/support/silent_log.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../../crons/index.dart';
import '../../service/bash/ai_bash_tool_service.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';

typedef CronsControllerProvider = CronsController? Function();

enum AiCronToolAction {
  create(AiBuiltinToolKind.cronCreate, 'CronCreate', 'create'),
  edit(AiBuiltinToolKind.cronEdit, 'CronEdit', 'edit'),
  delete(AiBuiltinToolKind.cronDelete, 'CronDelete', 'delete'),
  enable(AiBuiltinToolKind.cronEnable, 'CronEnable', 'enable'),
  disable(AiBuiltinToolKind.cronDisable, 'CronDisable', 'disable');

  const AiCronToolAction(this.kind, this.toolName, this.storageValue);

  final AiBuiltinToolKind kind;
  final String toolName;
  final String storageValue;
}

/// 定时任务增删改和启停工具。
class AiCronTool extends AiTool {
  AiCronTool({required this.action, required this.cronsControllerProvider});

  static const Uuid _uuid = Uuid();
  static const String _mutationReason = '修改定时任务配置';
  static const Set<String> _reservedTags = <String>{
    CronsController.systemTag,
    CronsController.hermesTalkerTag,
    CronsController.mcpKeywordIndexTag,
  };
  static const Set<String> _editableFields = <String>{
    'name',
    'description',
    'script_type',
    'command',
    'script_path',
    'cron_expression',
    'retry_count',
    'timeout_seconds',
    'max_retry_delay_seconds',
    'run_as_user',
    'tags',
    'working_directory',
    'environment',
    'collect_app_metadata',
    'collect_host_metadata',
    'collect_environment_snapshot',
    'on_success_notify',
    'on_success_severity',
    'on_success_play_sound',
    'on_success_vibrate',
    'on_success_message',
    'on_failure_notify',
    'on_failure_severity',
    'on_failure_play_sound',
    'on_failure_vibrate',
    'on_failure_message',
    'on_timeout_notify',
    'on_timeout_severity',
    'on_timeout_play_sound',
    'on_timeout_vibrate',
    'on_timeout_message',
  };

  final AiCronToolAction action;
  final CronsControllerProvider cronsControllerProvider;

  @override
  AiBuiltinToolKind get kind => action.kind;

  @override
  List<String> get aliases => <String>[
    switch (action) {
      AiCronToolAction.create => 'create_cron',
      AiCronToolAction.edit => 'edit_cron',
      AiCronToolAction.delete => 'delete_cron',
      AiCronToolAction.enable => 'enable_cron',
      AiCronToolAction.disable => 'disable_cron',
    },
  ];

  @override
  bool get isDestructive => true;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final stopwatch = Stopwatch()..start();
    try {
      final controller = cronsControllerProvider();
      if (controller == null) {
        return _failed(stopwatch, '定时任务服务不可用。');
      }
      await controller.initialize();
      if (controller.errorMessage != null && controller.entries.isEmpty) {
        return _failed(stopwatch, controller.errorMessage!);
      }
      return switch (action) {
        AiCronToolAction.create => await _create(
          controller,
          context.decodedArguments,
          stopwatch,
        ),
        AiCronToolAction.edit => await _edit(
          controller,
          context.decodedArguments,
          stopwatch,
        ),
        AiCronToolAction.delete => await _delete(
          controller,
          context.decodedArguments,
          stopwatch,
        ),
        AiCronToolAction.enable => await _toggle(
          controller,
          context.decodedArguments,
          stopwatch,
          enabled: true,
        ),
        AiCronToolAction.disable => await _toggle(
          controller,
          context.decodedArguments,
          stopwatch,
          enabled: false,
        ),
      };
    } on _CronToolArgumentException catch (error) {
      return AiToolUtils.invalidResult(action.toolName, error.message);
    } catch (error, stackTrace) {
      silentLog(
        'ai_cron_tool',
        '执行${action.storageValue}定时任务工具',
        error,
        stackTrace,
      );
      return _failed(stopwatch, '定时任务操作失败。');
    }
  }

  Future<AiToolExecutionResult> _create(
    CronsController controller,
    Map<String, Object?> rawArguments,
    Stopwatch stopwatch,
  ) async {
    final arguments = _CronArguments(rawArguments);
    final entry = _buildEntry(
      arguments,
      base: CronEntry(id: _uuid.v4(), name: ''),
      isCreate: true,
    );
    _validateRunAsUser(controller, entry.runAsUser);
    if (!await controller.addCron(entry)) {
      return _failedFromController(controller, stopwatch, '无法新增定时任务。');
    }
    return _success(stopwatch, entry, changed: true);
  }

  Future<AiToolExecutionResult> _edit(
    CronsController controller,
    Map<String, Object?> rawArguments,
    Stopwatch stopwatch,
  ) async {
    final arguments = _CronArguments(rawArguments);
    if (!arguments.hasAny(_editableFields)) {
      throw const _CronToolArgumentException('至少提供一个需要修改的配置字段。');
    }
    final target = _resolveTarget(
      controller,
      arguments,
      nameKey: 'current_name',
    );
    if (target.tags.contains(CronsController.systemTag)) {
      throw const _CronToolArgumentException('系统定时任务不允许编辑。');
    }
    final updated = _buildEntry(arguments, base: target, isCreate: false);
    _validateRunAsUser(controller, updated.runAsUser);
    if (!await controller.updateCron(updated)) {
      return _failedFromController(controller, stopwatch, '无法编辑定时任务。');
    }
    final persisted = controller.entries.firstWhere(
      (entry) => entry.id == updated.id,
      orElse: () => updated,
    );
    return _success(stopwatch, persisted, changed: true);
  }

  Future<AiToolExecutionResult> _delete(
    CronsController controller,
    Map<String, Object?> rawArguments,
    Stopwatch stopwatch,
  ) async {
    final target = _resolveTarget(
      controller,
      _CronArguments(rawArguments),
      nameKey: 'name',
    );
    if (target.tags.contains(CronsController.systemTag)) {
      throw const _CronToolArgumentException('系统定时任务不允许删除。');
    }
    if (!await controller.deleteCron(target.id)) {
      return _failedFromController(controller, stopwatch, '无法删除定时任务。');
    }
    return _success(stopwatch, target, changed: true);
  }

  Future<AiToolExecutionResult> _toggle(
    CronsController controller,
    Map<String, Object?> rawArguments,
    Stopwatch stopwatch, {
    required bool enabled,
  }) async {
    final target = _resolveTarget(
      controller,
      _CronArguments(rawArguments),
      nameKey: 'name',
    );
    if (target.tags.contains(CronsController.mcpKeywordIndexTag)) {
      throw const _CronToolArgumentException('该系统定时任务的启停状态由系统策略管理。');
    }
    if (target.enabled == enabled) {
      return _success(stopwatch, target, changed: false);
    }
    if (!await controller.toggleCronEnabled(target.id, enabled: enabled)) {
      return _failedFromController(controller, stopwatch, '无法切换定时任务状态。');
    }
    final updated = controller.entries.firstWhere(
      (entry) => entry.id == target.id,
      orElse: () => target.copyWith(enabled: enabled),
    );
    return _success(stopwatch, updated, changed: true);
  }

  CronEntry _resolveTarget(
    CronsController controller,
    _CronArguments arguments, {
    required String nameKey,
  }) {
    final id = arguments.optionalText('cron_id');
    final name = arguments.optionalText(nameKey);
    if (id == null && name == null) {
      throw _CronToolArgumentException('cron_id 与 $nameKey 至少填写一个。');
    }
    if (id != null) {
      final matches = controller.entries.where((entry) => entry.id == id);
      if (matches.isEmpty) {
        throw _CronToolArgumentException('不存在 ID 为“$id”的定时任务。');
      }
      final target = matches.first;
      if (name != null && target.name != name) {
        throw const _CronToolArgumentException('cron_id 与任务名称未指向同一任务。');
      }
      return target;
    }
    final matches = controller.entries
        .where((entry) => entry.name == name)
        .toList(growable: false);
    if (matches.isEmpty) {
      throw _CronToolArgumentException('不存在名称为“$name”的定时任务。');
    }
    if (matches.length > 1) {
      final ids = matches.map((entry) => entry.id).join('、');
      throw _CronToolArgumentException('任务名称不唯一，请改用 cron_id：$ids。');
    }
    return matches.single;
  }

  CronEntry _buildEntry(
    _CronArguments arguments, {
    required CronEntry base,
    required bool isCreate,
  }) {
    final name = arguments.text('name', fallback: base.name);
    if (name.isEmpty) {
      throw const _CronToolArgumentException('name 不能为空。');
    }
    final scriptType = arguments.enumValue<CronScriptType>(
      'script_type',
      fallback: base.scriptType,
      values: const <CronScriptType>[
        CronScriptType.command,
        CronScriptType.script,
      ],
      storageValue: (value) => value.storageValue,
    );
    final command = arguments.nullableRawText(
      'command',
      fallback: base.scriptContent,
    );
    final scriptPath = arguments.optionalText(
      'script_path',
      fallback: base.scriptPath,
    );
    if (scriptType == CronScriptType.command && command == null) {
      throw const _CronToolArgumentException('command 类型必须提供非空 command。');
    }
    if (scriptType == CronScriptType.script && scriptPath == null) {
      throw const _CronToolArgumentException('script 类型必须提供非空 script_path。');
    }
    final cronExpression = arguments.text(
      'cron_expression',
      fallback: base.cronExpression,
    );
    if (!CronParser.isValid(cronExpression)) {
      throw const _CronToolArgumentException(
        'cron_expression 必须是有效的五段式分钟级 Cron 表达式。',
      );
    }
    final tags = arguments.stringList('tags', fallback: base.tags);
    if (tags.any(_reservedTags.contains)) {
      throw const _CronToolArgumentException('tags 不能包含系统保留标签。');
    }
    return CronEntry(
      id: base.id,
      name: name,
      description: arguments.text('description', fallback: base.description),
      scriptType: scriptType,
      scriptPath: scriptType == CronScriptType.script ? scriptPath : null,
      scriptContent: scriptType == CronScriptType.command ? command : null,
      cronExpression: cronExpression,
      retryCount: arguments.integer(
        'retry_count',
        fallback: base.retryCount,
        min: kCronMinRetryCount,
        max: kCronMaxRetryCount,
      ),
      timeoutSeconds: arguments.integer(
        'timeout_seconds',
        fallback: base.timeoutSeconds,
        min: kCronMinTimeoutSeconds,
        max: kCronMaxTimeoutSeconds,
      ),
      runAsUser: arguments.optionalText(
        'run_as_user',
        fallback: base.runAsUser,
      ),
      tags: tags,
      enabled: isCreate || base.enabled,
      status: isCreate ? CronJobStatus.idle : base.status,
      onSuccessNotify: arguments.enumValue<CronNotifyType>(
        'on_success_notify',
        fallback: base.onSuccessNotify,
        values: CronNotifyType.values,
        storageValue: (value) => value.storageValue,
      ),
      onFailureNotify: arguments.enumValue<CronNotifyType>(
        'on_failure_notify',
        fallback: base.onFailureNotify,
        values: CronNotifyType.values,
        storageValue: (value) => value.storageValue,
      ),
      onTimeoutNotify: arguments.enumValue<CronNotifyType>(
        'on_timeout_notify',
        fallback: base.onTimeoutNotify,
        values: CronNotifyType.values,
        storageValue: (value) => value.storageValue,
      ),
      onSuccessSeverity: arguments.enumValue<CronNotifySeverity>(
        'on_success_severity',
        fallback: base.onSuccessSeverity,
        values: CronNotifySeverity.values,
        storageValue: (value) => value.storageValue,
      ),
      onFailureSeverity: arguments.enumValue<CronNotifySeverity>(
        'on_failure_severity',
        fallback: base.onFailureSeverity,
        values: CronNotifySeverity.values,
        storageValue: (value) => value.storageValue,
      ),
      onTimeoutSeverity: arguments.enumValue<CronNotifySeverity>(
        'on_timeout_severity',
        fallback: base.onTimeoutSeverity,
        values: CronNotifySeverity.values,
        storageValue: (value) => value.storageValue,
      ),
      onSuccessPlaySound: arguments.boolean(
        'on_success_play_sound',
        fallback: base.onSuccessPlaySound,
      ),
      onFailurePlaySound: arguments.boolean(
        'on_failure_play_sound',
        fallback: base.onFailurePlaySound,
      ),
      onTimeoutPlaySound: arguments.boolean(
        'on_timeout_play_sound',
        fallback: base.onTimeoutPlaySound,
      ),
      onSuccessVibrate: arguments.boolean(
        'on_success_vibrate',
        fallback: base.onSuccessVibrate,
      ),
      onFailureVibrate: arguments.boolean(
        'on_failure_vibrate',
        fallback: base.onFailureVibrate,
      ),
      onTimeoutVibrate: arguments.boolean(
        'on_timeout_vibrate',
        fallback: base.onTimeoutVibrate,
      ),
      onSuccessMessage: arguments.optionalText(
        'on_success_message',
        fallback: base.onSuccessMessage,
      ),
      onFailureMessage: arguments.optionalText(
        'on_failure_message',
        fallback: base.onFailureMessage,
      ),
      onTimeoutMessage: arguments.optionalText(
        'on_timeout_message',
        fallback: base.onTimeoutMessage,
      ),
      collectAppMetadata: arguments.boolean(
        'collect_app_metadata',
        fallback: base.collectAppMetadata,
      ),
      collectHostMetadata: arguments.boolean(
        'collect_host_metadata',
        fallback: base.collectHostMetadata,
      ),
      collectEnvironmentSnapshot: arguments.boolean(
        'collect_environment_snapshot',
        fallback: base.collectEnvironmentSnapshot,
      ),
      workingDirectory: arguments.optionalText(
        'working_directory',
        fallback: base.workingDirectory,
      ),
      environment: arguments.environment(
        'environment',
        fallback: base.environment,
      ),
      maxRetryDelaySeconds: arguments.integer(
        'max_retry_delay_seconds',
        fallback: base.maxRetryDelaySeconds,
        min: kCronMinRetryDelaySeconds,
        max: kCronMaxRetryDelaySeconds,
      ),
      lastRunAt: base.lastRunAt,
      nextRunAt: base.nextRunAt,
      lastExitCode: base.lastExitCode,
      consecutiveFailures: base.consecutiveFailures,
      createdAt: base.createdAt,
      updatedAt: base.updatedAt,
    );
  }

  void _validateRunAsUser(CronsController controller, String? runAsUser) {
    if (runAsUser != null && !controller.systemUsers.contains(runAsUser)) {
      throw _CronToolArgumentException('run_as_user 不在可用执行用户列表中：$runAsUser。');
    }
  }

  AiToolExecutionResult _success(
    Stopwatch stopwatch,
    CronEntry entry, {
    required bool changed,
  }) {
    final snapshot = <String, Object?>{
      'id': entry.id,
      'name': entry.name,
      'script_type': entry.scriptType.storageValue,
      'cron_expression': entry.cronExpression,
      'enabled': entry.enabled,
      'status': entry.status.storageValue,
      'retry_count': entry.retryCount,
      'timeout_seconds': entry.timeoutSeconds,
      'max_retry_delay_seconds': entry.maxRetryDelaySeconds,
      if (entry.runAsUser != null) 'run_as_user': entry.runAsUser,
      if (entry.tags.isNotEmpty) 'tags': entry.tags,
    };
    final output = jsonEncode(<String, Object?>{
      'status': 'success',
      'action': action.storageValue,
      'changed': changed,
      'cron': snapshot,
    });
    return AiToolUtils.simpleSuccessResult(
      command: action.toolName,
      output: output,
      durationMs: stopwatch.elapsedMilliseconds,
      isWriteCommand: changed,
      writeAnalysisReason: _mutationReason,
      metadata: <String, Object?>{
        'tool_source': 'builtin',
        'action': action.storageValue,
        'cron_id': entry.id,
        'cron_name': entry.name,
        'enabled': entry.enabled,
        'changed': changed,
      },
    );
  }

  AiToolExecutionResult _failedFromController(
    CronsController controller,
    Stopwatch stopwatch,
    String fallback,
  ) {
    return _failed(stopwatch, controller.errorMessage ?? fallback);
  }

  AiToolExecutionResult _failed(Stopwatch stopwatch, String message) {
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.failed,
      command: action.toolName,
      workingDirectory: AiToolUtils.defaultWorkingDirectory(),
      stdout: '',
      stderr: message,
      durationMs: stopwatch.elapsedMilliseconds,
      resultText: 'status: failed\nerror: $message',
      metadata: <String, Object?>{'action': action.storageValue},
    );
  }
}

class _CronArguments {
  const _CronArguments(this.values);

  final Map<String, Object?> values;

  bool hasAny(Set<String> keys) => keys.any(values.containsKey);

  String text(String key, {required String fallback}) {
    if (!values.containsKey(key)) return fallback;
    final value = values[key];
    if (value is! String) {
      throw _CronToolArgumentException('$key 必须是字符串。');
    }
    return value.trim();
  }

  String? optionalText(String key, {String? fallback}) {
    if (!values.containsKey(key)) return fallback;
    final value = values[key];
    if (value == null) return null;
    if (value is! String) {
      throw _CronToolArgumentException('$key 必须是字符串。');
    }
    return nullIfBlank(value);
  }

  String? nullableRawText(String key, {String? fallback}) {
    if (!values.containsKey(key)) return fallback;
    final value = values[key];
    if (value == null) return null;
    if (value is! String) {
      throw _CronToolArgumentException('$key 必须是字符串。');
    }
    return value.trim().isEmpty ? null : value;
  }

  int integer(
    String key, {
    required int fallback,
    required int min,
    required int max,
  }) {
    if (!values.containsKey(key)) return fallback;
    final value = optionalIntegralIntFromValue(values[key]);
    if (value == null || value < min || value > max) {
      throw _CronToolArgumentException('$key 必须是 $min 至 $max 的整数。');
    }
    return value;
  }

  bool boolean(String key, {required bool fallback}) {
    if (!values.containsKey(key)) return fallback;
    final value = optionalBoolFromValue(values[key]);
    if (value == null) {
      throw _CronToolArgumentException('$key 必须是布尔值。');
    }
    return value;
  }

  T enumValue<T>(
    String key, {
    required T fallback,
    required Iterable<T> values,
    required String Function(T value) storageValue,
  }) {
    if (!this.values.containsKey(key)) return fallback;
    final raw = this.values[key];
    if (raw is! String) {
      throw _CronToolArgumentException('$key 必须是字符串。');
    }
    final normalized = raw.trim().toLowerCase();
    for (final value in values) {
      if (storageValue(value) == normalized) return value;
    }
    throw _CronToolArgumentException('$key 不受支持：$raw。');
  }

  List<String> stringList(String key, {required List<String> fallback}) {
    if (!values.containsKey(key)) return fallback;
    final raw = values[key];
    if (raw is! List || raw.any((item) => item is! String)) {
      throw _CronToolArgumentException('$key 必须是字符串数组。');
    }
    return <String>{
      for (final item in raw.cast<String>())
        if (item.trim().isNotEmpty) item.trim(),
    }.toList(growable: false);
  }

  Map<String, String> environment(
    String key, {
    required Map<String, String> fallback,
  }) {
    if (!values.containsKey(key)) return fallback;
    final raw = values[key];
    if (raw is! Map) {
      throw _CronToolArgumentException('$key 必须是字符串键值对象。');
    }
    final result = <String, String>{};
    for (final entry in raw.entries) {
      if (entry.key is! String || entry.value is! String) {
        throw _CronToolArgumentException('$key 必须是字符串键值对象。');
      }
      final name = (entry.key as String).trim();
      if (name.isEmpty ||
          name.contains('=') ||
          name.contains('\n') ||
          name.contains('\r') ||
          (entry.value as String).contains('\n') ||
          (entry.value as String).contains('\r')) {
        throw const _CronToolArgumentException(
          'environment 包含无效变量名或无法持久化的换行值。',
        );
      }
      result[name] = entry.value as String;
    }
    return result;
  }
}

class _CronToolArgumentException implements Exception {
  const _CronToolArgumentException(this.message);

  final String message;
}
