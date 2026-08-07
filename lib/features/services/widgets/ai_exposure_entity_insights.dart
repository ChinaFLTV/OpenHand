part of 'ai_exposure_monitoring_dialogs.dart';

void _showResultEntityInsight(BuildContext context, AiExposureResult result) {
  showAnimatedDialog<void>(
    context: context,
    builder: (_) => _OperationsInsightDialog(
      icon: Icons.fact_check_outlined,
      title: _resultDisplayName(result),
      subtitle: '结果身份、风险与完整证据',
      color: _resultEntityColor(result.category),
      entity: true,
      child: _ResultEntityInsightBody(resultId: result.id),
    ),
  );
}

void _showLogEntityInsight(BuildContext context, AiExposureLogEntry entry) {
  showAnimatedDialog<void>(
    context: context,
    builder: (_) => _OperationsInsightDialog(
      icon: Icons.terminal_rounded,
      title: '日志事件',
      subtitle: '原始消息与任务上下文',
      color: _logColor(entry.level),
      entity: true,
      child: _LogEntityInsightBody(entry: entry),
    ),
  );
}

void _showRuleEntityInsight(BuildContext context, AiExposureScanRule rule) {
  showAnimatedDialog<void>(
    context: context,
    builder: (_) => _OperationsInsightDialog(
      icon: Icons.rule_rounded,
      title: rule.vendor.trim().isEmpty ? rule.id : rule.vendor,
      subtitle: '规则身份、识别模式与验证端点',
      color: rule.enabled
          ? OpenHandStatusColors.success
          : Theme.of(context).colorScheme.outline,
      entity: true,
      child: _RuleEntityInsightBody(ruleId: rule.id),
    ),
  );
}

void _showProxyRequestEntityInsight(
  BuildContext context, {
  required AiExposureProxyEndpoint? endpoint,
  required String address,
  required AiExposureProxyRequestSample sample,
}) {
  showAnimatedDialog<void>(
    context: context,
    builder: (_) => _OperationsInsightDialog(
      icon: sample.succeeded
          ? Icons.check_circle_outline_rounded
          : sample.timedOut
          ? Icons.timer_off_outlined
          : Icons.error_outline_rounded,
      title: endpoint?.displayName ?? '代理请求样本',
      subtitle: '请求结果、时延与出口上下文',
      color: sample.succeeded
          ? OpenHandStatusColors.success
          : sample.timedOut
          ? OpenHandStatusColors.warning
          : OpenHandStatusColors.error,
      entity: true,
      child: _ProxyRequestEntityInsightBody(
        endpointId: endpoint?.runtimeId ?? sample.endpointId,
        address: address,
        sample: sample,
      ),
    ),
  );
}

void _showProxyProbeEntityInsight(
  BuildContext context, {
  required AiExposureProxyEndpoint endpoint,
  required AiExposureProxyProbeSample sample,
}) {
  showAnimatedDialog<void>(
    context: context,
    builder: (_) => _OperationsInsightDialog(
      icon: sample.reachable
          ? Icons.health_and_safety_outlined
          : Icons.report_problem_outlined,
      title: endpoint.displayName,
      subtitle: '代理巡检步骤与故障定位',
      color: sample.reachable
          ? OpenHandStatusColors.success
          : OpenHandStatusColors.error,
      entity: true,
      child: _ProxyProbeEntityInsightBody(
        endpointId: endpoint.runtimeId,
        sample: sample,
      ),
    ),
  );
}

void _showStageEntityInsight(
  BuildContext context, {
  required String stage,
  String? taskId,
}) {
  showAnimatedDialog<void>(
    context: context,
    builder: (_) => _OperationsInsightDialog(
      icon: Icons.route_rounded,
      title: _stageName(stage),
      subtitle: '阶段职责、输入输出与任务状态',
      entity: true,
      child: _StageEntityInsightBody(stage: stage, taskId: taskId),
    ),
  );
}

void _showDependencyEntityInsight(
  BuildContext context, {
  required String name,
  required bool? configured,
  required bool? connected,
  required String message,
}) {
  showAnimatedDialog<void>(
    context: context,
    builder: (_) => _OperationsInsightDialog(
      icon: Icons.account_tree_outlined,
      title: name,
      subtitle: '依赖配置、连接证据与影响',
      color: connected == true
          ? OpenHandStatusColors.success
          : configured == true
          ? OpenHandStatusColors.warning
          : Theme.of(context).colorScheme.outline,
      entity: true,
      child: _DependencyEntityInsightBody(
        name: name,
        configured: configured,
        connected: connected,
        message: message,
      ),
    ),
  );
}

class _ResultEntityInsightBody extends StatelessWidget {
  const _ResultEntityInsightBody({required this.resultId});

  final String resultId;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ServicesController>();
    final result = controller.results
        .where((entry) => entry.id == resultId)
        .firstOrNull;
    if (result == null) return const _InsightEmpty(label: '该结果已不在当前结果集合中。');
    final task = controller.history
        .where((entry) => entry.id == result.jobId)
        .firstOrNull;
    final category = _resultEntityCategory(result.category);
    return _metricInsightPage([
      _InsightKpiBand(
        title: '结果风险快照',
        icon: Icons.security_outlined,
        items: [
          _InsightKpi(
            icon: Icons.category_outlined,
            label: '结果类别',
            value: category,
            helper: '真实分类字段',
            color: _resultEntityColor(result.category),
          ),
          _InsightKpi(
            icon: Icons.key_outlined,
            label: '凭证状态',
            value: aiExposureCredentialStateName(result.credentialState),
            helper: result.maskedCredential?.trim().isNotEmpty == true
                ? result.maskedCredential!.trim()
                : '无可展示凭证',
            color: _credentialStateColor(
              result.credentialState,
              Theme.of(context).colorScheme,
            ),
          ),
          _InsightKpi(
            icon: Icons.model_training_outlined,
            label: '模型数',
            value: '${result.modelCount}',
            helper: '服务返回值',
            color: OpenHandStatusColors.info,
          ),
          _InsightKpi(
            icon: Icons.link_outlined,
            label: '证据数',
            value: '${result.evidence.length}',
            helper: result.evidence.isEmpty ? '未发生' : '完整证据见下方',
            color: OpenHandStatusColors.success,
          ),
        ],
      ),
      _entityFacts(
        title: '身份与来源',
        icon: Icons.badge_outlined,
        fields: [
          ('结果 ID', result.id),
          ('任务 ID', result.jobId.isEmpty ? '记录缺少关联任务' : result.jobId),
          ('创建时间', result.createdAt.toLocal().toIso8601String()),
          ('来源', _sourceName(result.source)),
          ('URL', result.url.isEmpty ? '记录字段缺失' : result.url),
          ('主机', result.host.isEmpty ? '记录字段缺失' : result.host),
          ('产品', result.product.isEmpty ? '未识别产品' : result.product),
          ('类别', category),
          ('凭证状态', aiExposureCredentialStateName(result.credentialState)),
          (
            '脱敏凭证',
            result.maskedCredential?.trim().isNotEmpty == true
                ? result.maskedCredential!.trim()
                : '无可展示凭证',
          ),
          (
            '余额摘要',
            result.balanceSummary?.trim().isNotEmpty == true
                ? result.balanceSummary!.trim()
                : '服务未返回余额信息',
          ),
        ],
      ),
      _entityFacts(
        title: '指纹与重复影响',
        icon: Icons.fingerprint_rounded,
        fields: [
          (
            '响应指纹',
            result.responseFingerprint.isEmpty
                ? '记录字段缺失'
                : result.responseFingerprint,
          ),
          ('重复响应主机', '${result.duplicateResponseHosts}'),
          ('重复凭证主机', '${result.duplicateKeyHosts}'),
          ('重复主机明细', '当前仅记录聚合数量'),
        ],
      ),
      _entityTextList(
        title: '完整证据链',
        icon: Icons.link_outlined,
        values: result.evidence,
        emptyLabel: '该结果没有证据记录。',
      ),
      _InsightRecordPanel(
        icon: Icons.radar_rounded,
        title: '关联任务',
        records: task == null
            ? const <_InsightRecord>[]
            : <_InsightRecord>[_taskInsightRecord(task)],
        emptyLabel: '关联任务不在当前任务历史中。',
        maxEntries: 1,
      ),
    ]);
  }
}

class _LogEntityInsightBody extends StatelessWidget {
  const _LogEntityInsightBody({required this.entry});

  final AiExposureLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ServicesController>();
    final task = controller.history
        .where((item) => item.id == entry.jobId)
        .firstOrNull;
    return _metricInsightPage([
      _entityCode(
        context,
        title: '原始完整消息',
        icon: Icons.terminal_rounded,
        value: entry.message.isEmpty ? '日志消息为空' : entry.message,
      ),
      _entityFacts(
        title: '事件字段',
        icon: Icons.receipt_long_outlined,
        fields: [
          ('时间', entry.at.toLocal().toIso8601String()),
          ('级别', _logLevelName(context, entry.level)),
          ('任务 ID', entry.jobId.isEmpty ? '系统日志' : entry.jobId),
          ('日志 ID', entry.id ?? '旧版日志未记录'),
          ('模块', entry.module ?? '旧版日志未记录'),
          ('事件码', entry.eventCode ?? '旧版日志未记录'),
          ('追踪 ID', entry.traceId ?? '未关联追踪'),
          (
            '异常类型',
            entry.exceptionType ?? (entry.level == 'error' ? '未分类异常' : '不适用'),
          ),
          (
            '堆栈摘要',
            entry.stackSummary ??
                (entry.level == 'error' ? '服务未返回堆栈摘要' : '不适用'),
          ),
        ],
      ),
      if (entry.metadata.isNotEmpty)
        _entityCode(
          context,
          title: '事件元数据',
          icon: Icons.data_object_rounded,
          value: const JsonEncoder.withIndent('  ').convert(entry.metadata),
        ),
      _InsightRecordPanel(
        icon: Icons.radar_rounded,
        title: '关联任务',
        records: task == null
            ? const <_InsightRecord>[]
            : <_InsightRecord>[_taskInsightRecord(task)],
        emptyLabel: entry.jobId.isEmpty ? '该日志没有关联任务。' : '关联任务不在当前历史中。',
        maxEntries: 1,
      ),
    ]);
  }
}

class _RuleEntityInsightBody extends StatelessWidget {
  const _RuleEntityInsightBody({required this.ruleId});

  final String ruleId;

  @override
  Widget build(BuildContext context) {
    final rule = context
        .watch<ServicesController>()
        .rules
        .where((entry) => entry.id == ruleId)
        .firstOrNull;
    if (rule == null) return const _InsightEmpty(label: '该规则已不在当前规则集合中。');
    return _metricInsightPage([
      _entityFacts(
        title: '规则身份',
        icon: Icons.badge_outlined,
        fields: [
          ('规则 ID', rule.id),
          ('供应商', rule.vendor.trim().isEmpty ? '规则字段缺失' : rule.vendor),
          ('协议', rule.protocol.trim().isEmpty ? '规则字段缺失' : rule.protocol),
          ('启用状态', rule.enabled ? '已启用' : '未启用'),
          ('版本', rule.version ?? '旧版规则未记录'),
          ('内容哈希', rule.contentHash ?? '旧版规则未记录'),
          ('创建时间', rule.createdAt?.toLocal().toIso8601String() ?? '旧版规则未记录'),
          ('更新时间', rule.updatedAt?.toLocal().toIso8601String() ?? '旧版规则未记录'),
          ('快照 ID', rule.snapshotId ?? '旧版规则未记录'),
          ('变更来源', rule.changeSource ?? '旧版规则未记录'),
        ],
      ),
      _entityTextList(
        title: '凭证识别模式',
        icon: Icons.key_outlined,
        values: rule.credentialPatterns,
        emptyLabel: '该规则未配置凭证模式。',
        monospace: true,
      ),
      _entityTextList(
        title: '上下文约束词',
        icon: Icons.manage_search_rounded,
        values: rule.contextTerms,
        emptyLabel: '该规则未配置上下文约束词。',
      ),
      _entityFacts(
        title: '编码覆盖',
        icon: Icons.code_rounded,
        fields: [
          (
            '编码类型',
            rule.contentEncodings.isEmpty
                ? '未配置'
                : rule.contentEncodings.map((entry) => entry.id).join(' / '),
          ),
        ],
      ),
      _entityTextList(
        title: '模型验证端点',
        icon: Icons.model_training_outlined,
        values: rule.modelPaths,
        emptyLabel: '该规则未配置模型验证端点。',
        monospace: true,
      ),
      _entityTextList(
        title: '余额验证端点',
        icon: Icons.account_balance_wallet_outlined,
        values: rule.balancePaths,
        emptyLabel: '该规则未配置余额验证端点。',
        monospace: true,
      ),
    ]);
  }
}

class _ProxyRequestEntityInsightBody extends StatelessWidget {
  const _ProxyRequestEntityInsightBody({
    required this.endpointId,
    required this.address,
    required this.sample,
  });

  final String? endpointId;
  final String address;
  final AiExposureProxyRequestSample sample;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ServicesController>();
    final endpoint = endpointId == null
        ? null
        : controller.proxyConfiguration.endpoints
              .where((entry) => entry.runtimeId == endpointId)
              .firstOrNull;
    final identity = endpoint?.identity;
    return _metricInsightPage([
      _InsightKpiBand(
        title: '请求样本',
        icon: Icons.swap_vert_rounded,
        items: [
          _InsightKpi(
            icon: sample.succeeded
                ? Icons.check_circle_outline_rounded
                : sample.timedOut
                ? Icons.timer_off_outlined
                : Icons.error_outline_rounded,
            label: '结果',
            value: sample.succeeded
                ? '成功'
                : sample.timedOut
                ? '超时'
                : '失败',
            helper: '近期保留样本',
            color: sample.succeeded
                ? OpenHandStatusColors.success
                : sample.timedOut
                ? OpenHandStatusColors.warning
                : OpenHandStatusColors.error,
          ),
          _InsightKpi(
            icon: Icons.speed_rounded,
            label: '响应耗时',
            value: '${sample.responseTimeMs} ms',
            helper: '服务返回值',
            color: Theme.of(context).colorScheme.primary,
          ),
          _InsightKpi(
            icon: Icons.http_rounded,
            label: 'HTTP 状态',
            value: sample.statusCode == null
                ? sample.succeeded
                      ? '响应未返回状态码'
                      : '无 HTTP 响应'
                : '${sample.statusCode}',
            helper: '具体状态码',
            color: Theme.of(context).colorScheme.tertiary,
          ),
        ],
      ),
      _entityFacts(
        title: '请求与选路上下文',
        icon: Icons.alt_route_rounded,
        fields: [
          ('请求时间', sample.at.toLocal().toIso8601String()),
          ('请求 ID', sample.id ?? '旧版请求样本未记录'),
          ('节点', endpoint?.displayName ?? '运行时节点'),
          ('代理地址', endpoint?.maskedUrl ?? _maskProxyAddress(address)),
          ('目标主机', sample.targetHost ?? '旧版请求样本未记录'),
          ('请求方法', sample.method ?? '旧版请求样本未记录'),
          (
            '超时阈值',
            sample.timeoutMs == null ? '客户端未设置显式阈值' : '${sample.timeoutMs} ms',
          ),
          ('选路模式', sample.routeMode ?? '旧版请求样本未记录'),
          ('选路原因', sample.selectionReason ?? '旧版请求样本未记录'),
          ('安全上下文', sample.context ?? '旧版请求样本未记录'),
          ('错误类型', sample.succeeded ? '未发生' : sample.errorType ?? '错误类型未分类'),
          ('错误消息', sample.succeeded ? '未发生' : sample.errorMessage ?? '错误详情未上报'),
        ],
      ),
      _entityFacts(
        title: '出口身份',
        icon: Icons.public_rounded,
        fields: [
          (
            '出口 IP',
            identity?.exitIp.trim().isNotEmpty == true
                ? identity!.exitIp
                : '尚未完成出口识别',
          ),
          (
            '国家',
            identity?.country.trim().isNotEmpty == true
                ? identity!.country
                : '尚未完成出口识别',
          ),
          (
            'ISP',
            identity?.isp.trim().isNotEmpty == true
                ? identity!.isp
                : '尚未完成出口识别',
          ),
          (
            'ASN',
            identity?.asn.trim().isNotEmpty == true
                ? identity!.asn
                : '尚未完成出口识别',
          ),
          (
            '身份采集时间',
            identity == null
                ? '尚未完成出口识别'
                : identity.observedAt.toLocal().toIso8601String(),
          ),
        ],
      ),
    ]);
  }
}

class _ProxyProbeEntityInsightBody extends StatelessWidget {
  const _ProxyProbeEntityInsightBody({
    required this.endpointId,
    required this.sample,
  });

  final String endpointId;
  final AiExposureProxyProbeSample sample;

  @override
  Widget build(BuildContext context) {
    final endpoint = context
        .watch<ServicesController>()
        .proxyConfiguration
        .endpoints
        .where((entry) => entry.runtimeId == endpointId)
        .firstOrNull;
    final inferredSteps = <(String, String)>[
      ('代理网关', sample.gatewayReachable ? '通过' : '失败'),
      (
        '身份认证',
        _probeStepState(sample, AiExposureProxyProbeFailure.authentication),
      ),
      ('访问控制', _probeStepState(sample, AiExposureProxyProbeFailure.access)),
      ('代理转发', _probeStepState(sample, AiExposureProxyProbeFailure.forwarding)),
      ('协议响应', _probeStepState(sample, AiExposureProxyProbeFailure.protocol)),
      ('最终结果', sample.reachable ? '通过' : '失败'),
    ];
    return _metricInsightPage([
      _entityFacts(
        title: '巡检身份',
        icon: Icons.badge_outlined,
        fields: [
          ('巡检时间', sample.checkedAt.toLocal().toIso8601String()),
          ('巡检 ID', sample.id ?? '旧版巡检样本未记录'),
          ('巡检轮次 ID', sample.inspectionRunId ?? '旧版巡检样本未记录'),
          (
            '计划时间',
            sample.scheduledAt?.toLocal().toIso8601String() ?? '旧版巡检样本未记录',
          ),
          (
            '开始时间',
            sample.startedAt?.toLocal().toIso8601String() ?? '旧版巡检样本未记录',
          ),
          (
            '结束时间',
            sample.finishedAt?.toLocal().toIso8601String() ?? '旧版巡检样本未记录',
          ),
          ('节点', endpoint?.displayName ?? endpointId),
          ('代理地址', endpoint?.maskedUrl ?? '节点已从当前配置移除'),
          ('最终结果', sample.reachable ? '通过' : '失败'),
          (
            '响应耗时',
            sample.latencyMs == null ? '未形成可计时响应' : '${sample.latencyMs} ms',
          ),
          (
            'HTTP 状态',
            sample.statusCode == null ? '未形成 HTTP 响应' : '${sample.statusCode}',
          ),
          (
            '失败阶段',
            sample.failure == null
                ? sample.reachable
                      ? '未发生'
                      : '故障阶段未分类'
                : _proxyProbeFailureName(sample.failure!),
          ),
          (
            '错误原文',
            sample.error?.trim().isNotEmpty == true
                ? sample.error!.trim()
                : sample.reachable
                ? '未发生'
                : '故障详情未上报',
          ),
        ],
      ),
      _Section(
        title: '诊断步骤',
        icon: Icons.route_rounded,
        child: Column(
          children:
              (sample.stepResults.isEmpty
                      ? inferredSteps
                            .map(
                              (step) => (
                                step.$1,
                                step.$2,
                                null as int?,
                                null as String?,
                              ),
                            )
                            .toList(growable: false)
                      : sample.stepResults
                            .map(
                              (step) => (
                                step.step,
                                step.succeeded ? '通过' : '失败',
                                step.durationMs,
                                step.message,
                              ),
                            )
                            .toList(growable: false))
                  .indexed
                  .map((entry) {
                    final state = entry.$2.$2;
                    final color = state == '通过'
                        ? OpenHandStatusColors.success
                        : state == '失败'
                        ? OpenHandStatusColors.error
                        : Theme.of(context).colorScheme.outline;
                    return _OpsKeyValue(
                      label: '${entry.$1 + 1}. ${entry.$2.$1}',
                      value: [
                        state,
                        if (entry.$2.$3 != null) '${entry.$2.$3} ms',
                        if (entry.$2.$4?.trim().isNotEmpty == true)
                          entry.$2.$4!.trim(),
                      ].join(' · '),
                      color: color,
                    );
                  })
                  .toList(growable: false),
        ),
      ),
    ]);
  }
}

class _StageEntityInsightBody extends StatelessWidget {
  const _StageEntityInsightBody({required this.stage, this.taskId});

  final String stage;
  final String? taskId;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ServicesController>();
    final task = taskId == null
        ? null
        : controller.history.where((entry) => entry.id == taskId).firstOrNull;
    final definition = _stageDefinition(stage);
    final timing = task?.stageTimings
        .where((entry) => entry.stage == stage)
        .firstOrNull;
    final mergedStage = stage == 'extracting' || stage == 'validating';
    final timingFallback = task == null
        ? '未关联任务'
        : mergedStage
        ? '并入目标指纹与验证流水线'
        : task.stageTimings.isEmpty
        ? '历史任务无阶段切片'
        : '阶段尚未开始';
    final taskState = task == null
        ? '未关联任务'
        : task.stage == stage
        ? '进行中'
        : _stageOrder(task.stage) > _stageOrder(stage)
        ? '已完成'
        : '等待中';
    return _metricInsightPage([
      _entityFacts(
        title: '阶段职责',
        icon: Icons.route_rounded,
        fields: [
          ('内部标识', stage),
          ('阶段名称', _stageName(stage)),
          ('业务职责', definition.$1),
          ('输入', definition.$2),
          ('输出', definition.$3),
          ('前置阶段', definition.$4),
          ('下一阶段', definition.$5),
        ],
      ),
      _entityFacts(
        title: '当前任务状态',
        icon: Icons.radar_rounded,
        fields: [
          ('关联任务', task == null ? '未关联' : task.name),
          ('任务 ID', task?.id ?? '未关联'),
          ('阶段状态', taskState),
          (
            '阶段消息',
            timing?.message?.trim().isNotEmpty == true
                ? timing!.message!.trim()
                : task?.stage == stage &&
                      task?.progress.message.trim().isNotEmpty == true
                ? task!.progress.message
                : timingFallback,
          ),
          (
            '阶段开始时间',
            timing?.startedAt?.toLocal().toIso8601String() ?? timingFallback,
          ),
          (
            '阶段结束时间',
            timing?.finishedAt?.toLocal().toIso8601String() ?? timingFallback,
          ),
          (
            '阶段耗时',
            timing?.durationMs == null
                ? timingFallback
                : '${timing!.durationMs} ms',
          ),
          (
            '输入数量',
            timing?.inputCount == null
                ? timingFallback
                : '${timing!.inputCount}',
          ),
          (
            '输出数量',
            timing?.outputCount == null
                ? timingFallback
                : '${timing!.outputCount}',
          ),
          ('已处理数量', task == null ? '未关联任务' : '${task.progress.processed}'),
        ],
      ),
      if (task != null)
        _InsightRecordPanel(
          icon: Icons.radar_rounded,
          title: '关联任务',
          records: <_InsightRecord>[_taskInsightRecord(task)],
          emptyLabel: '未关联任务。',
          maxEntries: 1,
        ),
    ]);
  }
}

class _DependencyEntityInsightBody extends StatelessWidget {
  const _DependencyEntityInsightBody({
    required this.name,
    required this.configured,
    required this.connected,
    required this.message,
  });

  final String name;
  final bool? configured;
  final bool? connected;
  final String message;

  @override
  Widget build(BuildContext context) {
    final status = context.watch<ServicesController>().dependencyStatus;
    final component = switch (name.toLowerCase()) {
      String value when value.contains('postgres') => status?.postgresql,
      String value when value.contains('redis') => status?.redis,
      String value when value.contains('playwright') => status?.playwright,
      _ => null,
    };
    final impact = switch (name.toLowerCase()) {
      String value when value.contains('postgres') => '结果镜像与跨端数据访问',
      String value when value.contains('redis') => '分布式协调与缓存',
      String value when value.contains('playwright') => '浏览器自动化与动态页面访问',
      String value when value.contains('gpt') => 'AI 辅助提取',
      String value when value.contains('sqlite') => '本地任务、结果、规则与日志归档',
      _ => '扫描服务运行链路',
    };
    return _metricInsightPage([
      _entityFacts(
        title: '组件状态证据',
        icon: Icons.account_tree_outlined,
        fields: [
          ('组件', name),
          (
            '配置状态',
            configured == null
                ? '状态源不可用'
                : configured!
                ? '已配置'
                : '未配置',
          ),
          (
            '连接状态',
            connected == true
                ? '已连接'
                : configured == false
                ? '未配置'
                : '未连接',
          ),
          ('状态消息', message.trim().isEmpty ? '服务未返回状态消息' : message.trim()),
          ('影响范围', impact),
          ('版本', component?.version ?? '组件未上报版本'),
          (
            '最近检查',
            component?.checkedAt?.toLocal().toIso8601String() ?? '等待首次检查',
          ),
          (
            '检查耗时',
            component?.latencyMs == null
                ? '等待首次检查'
                : '${component!.latencyMs} ms',
          ),
          ('脱敏端点', component?.endpointMasked ?? '未配置远程端点'),
          ('错误码', connected == true ? '未发生' : component?.errorCode ?? '未分类'),
        ],
      ),
      _entityFacts(
        title: '当前检查证据',
        icon: Icons.monitor_heart_outlined,
        fields: [
          (
            '检查结论',
            connected == true
                ? '通过'
                : configured == false
                ? '未配置'
                : '未通过',
          ),
          ('遥测字段', '${component?.telemetry.length ?? 0} 项'),
          (
            '专属遥测',
            component?.telemetry.isNotEmpty == true
                ? const JsonEncoder.withIndent(
                    '  ',
                  ).convert(component!.telemetry)
                : '组件未提供扩展遥测',
          ),
        ],
      ),
    ]);
  }
}

Widget _entityFacts({
  required String title,
  required IconData icon,
  required List<(String, String)> fields,
}) => _Section(
  title: title,
  icon: icon,
  child: Column(
    children: fields
        .map(
          (field) =>
              _OpsKeyValue(label: field.$1, value: field.$2, maxLines: 6),
        )
        .toList(growable: false),
  ),
);

Widget _entityTextList({
  required String title,
  required IconData icon,
  required List<String> values,
  required String emptyLabel,
  bool monospace = false,
}) => _Section(
  title: values.isEmpty ? title : '$title · ${values.length}',
  icon: icon,
  child: values.isEmpty
      ? _InsightEmpty(label: emptyLabel)
      : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: values.indexed
              .map(
                (entry) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: SelectableText(
                    '${entry.$1 + 1}. ${entry.$2}',
                    style: TextStyle(
                      fontFamily: monospace ? 'monospace' : null,
                      height: 1.45,
                    ),
                  ),
                ),
              )
              .toList(growable: false),
        ),
);

Widget _entityCode(
  BuildContext context, {
  required String title,
  required IconData icon,
  required String value,
}) {
  final colors = Theme.of(context).colorScheme;
  return _Section(
    title: title,
    icon: icon,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: SelectableText(
        value,
        style: TextStyle(
          color: colors.onSurface,
          fontFamily: 'monospace',
          fontSize: 12.5,
          height: 1.5,
        ),
      ),
    ),
  );
}

Color _resultEntityColor(AiExposureResultCategory category) =>
    switch (category) {
      AiExposureResultCategory.valid => OpenHandStatusColors.success,
      AiExposureResultCategory.highValue => const Color(0xffa855f7),
      AiExposureResultCategory.suspicious => OpenHandStatusColors.warning,
      AiExposureResultCategory.honeypot => OpenHandStatusColors.error,
    };

String _resultEntityCategory(AiExposureResultCategory category) =>
    switch (category) {
      AiExposureResultCategory.valid => '有效',
      AiExposureResultCategory.highValue => '高价值',
      AiExposureResultCategory.suspicious => '可疑',
      AiExposureResultCategory.honeypot => '蜜罐',
    };

String aiExposureCredentialStateName(String state) => switch (state) {
  'valid' => '有效',
  'candidate' => '候选',
  'rate_limited' => '受限',
  'invalid' => '无效',
  'unauthorized' => '未授权',
  'unreachable' => '不可达',
  'duplicate' => '重复',
  'not_found' => '未发现',
  _ => state.trim().isEmpty ? '状态未分类' : state,
};

String _probeStepState(
  AiExposureProxyProbeSample sample,
  AiExposureProxyProbeFailure failure,
) {
  if (sample.failure == failure) return '失败';
  return sample.reachable ? '通过' : '未执行';
}

(String, String, String, String, String) _stageDefinition(String stage) =>
    switch (stage) {
      'queued' => ('等待调度与资源分配', '扫描请求', '可执行任务', '无', '资产发现'),
      'discovering' => ('从已启用来源发现目标', '来源配置与查询', '原始目标集合', '排队', '目标规范化'),
      'normalizing' => ('统一目标格式并去除无效输入', '原始目标集合', '规范目标集合', '资产发现', '产品指纹'),
      'fingerprinting' => ('识别目标产品与协议特征', '规范目标集合', '产品指纹', '目标规范化', '凭证提取'),
      'extracting' => ('按规则提取候选凭证与上下文', '响应内容与规则', '候选结果', '产品指纹', '授权验证'),
      'validating' => ('在授权边界内验证候选结果', '候选结果与授权范围', '有效性结论', '凭证提取', '关联归档'),
      'persisting' => ('写入任务、结果、证据与日志', '验证结论与证据', '持久化记录', '授权验证', '完成'),
      'completed' => ('确认任务终态并汇总产出', '持久化结果', '完成任务', '关联归档', '无'),
      'cancelled' => ('记录取消终态与已完成进度', '取消请求与当前进度', '取消任务', '任意运行阶段', '无'),
      'failed' => ('记录失败终态与错误上下文', '运行错误与当前进度', '失败任务', '任意运行阶段', '无'),
      _ => ('未知阶段职责', '未知输入', '未知输出', '未知前置阶段', '未知后续阶段'),
    };

int _stageOrder(String stage) => const <String>[
  'queued',
  'discovering',
  'normalizing',
  'fingerprinting',
  'extracting',
  'validating',
  'persisting',
  'completed',
].indexOf(stage);
