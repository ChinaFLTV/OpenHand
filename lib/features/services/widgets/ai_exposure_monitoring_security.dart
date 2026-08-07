part of 'ai_exposure_monitoring_dialogs.dart';

class _SecurityPanel extends StatelessWidget {
  const _SecurityPanel({required this.controller});
  final ServicesController controller;

  @override
  Widget build(BuildContext context) {
    final text = openHandTextResolver(context);
    final dependencies = controller.dependencyStatus;
    final proxy = controller.proxyStatus;
    final encodings = controller.rules
        .where((rule) => rule.enabled)
        .expand((rule) => rule.contentEncodings)
        .toSet();
    final enabledRules = controller.rules
        .where((rule) => rule.enabled)
        .toList();
    final patterns = enabledRules.fold<int>(
      0,
      (sum, rule) => sum + rule.credentialPatterns.length,
    );
    final contextTerms = enabledRules.fold<int>(
      0,
      (sum, rule) => sum + rule.contextTerms.length,
    );
    final modelPaths = enabledRules.fold<int>(
      0,
      (sum, rule) => sum + rule.modelPaths.length,
    );
    final balancePaths = enabledRules.fold<int>(
      0,
      (sum, rule) => sum + rule.balancePaths.length,
    );
    final vendorCounts = <String, int>{};
    for (final rule in enabledRules) {
      vendorCounts.update(rule.vendor, (value) => value + 1, ifAbsent: () => 1);
    }
    final dependencyReadyStates = <bool>[
      controller.isRunning,
      dependencies?.postgresql.connected == true,
      dependencies?.redis.connected == true,
      dependencies?.playwright.connected == true,
      controller.aiExtractorStatus?.configured == true,
    ];
    final dependencyReady = dependencyReadyStates.where((item) => item).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MetricGrid(
          title: '安全与依赖',
          metrics: [
            _Metric(
              _MetricInsightId.securityEnabledRules,
              Icons.rule_rounded,
              '启用规则',
              '${enabledRules.length}/${controller.rules.length}',
              '${vendorCounts.length} 个供应商',
              color: Theme.of(context).colorScheme.primary,
            ),
            _Metric(
              _MetricInsightId.securityCredentialPatterns,
              Icons.fingerprint_rounded,
              '凭证模式',
              '$patterns',
              '$contextTerms 个上下文词',
              color: const Color(0xff0f766e),
            ),
            _Metric(
              _MetricInsightId.securityModelEndpoints,
              Icons.api_rounded,
              '模型端点',
              '$modelPaths',
              '$balancePaths 个余额端点',
              color: OpenHandStatusColors.info,
            ),
            _Metric(
              _MetricInsightId.securityEncodings,
              Icons.code_rounded,
              '编码识别',
              '${encodings.length}/${AiExposureContentEncoding.values.length}',
              '多层内容解码',
              color: const Color(0xff0891b2),
            ),
            _Metric(
              _MetricInsightId.securityProxyRequests,
              Icons.lan_outlined,
              '代理请求',
              '${proxy?.totalSelections ?? 0}',
              serviceProxyRouteText(controller, text),
              color: Theme.of(context).colorScheme.secondary,
            ),
            _Metric(
              _MetricInsightId.securityProxySuccess,
              Icons.task_alt_rounded,
              '代理成功',
              '${proxy?.totalSuccesses ?? 0}',
              '${proxy?.averageResponseTimeMs ?? 0} ms 平均响应',
              color: OpenHandStatusColors.success,
            ),
            _Metric(
              _MetricInsightId.securityProxyAnomalies,
              Icons.report_gmailerrorred_rounded,
              '代理异常',
              '${(proxy?.totalFailures ?? 0) + (proxy?.totalTimeouts ?? 0)}',
              '失败 ${proxy?.totalFailures ?? 0} · 超时 ${proxy?.totalTimeouts ?? 0}',
              color: OpenHandStatusColors.error,
            ),
            _Metric(
              _MetricInsightId.securityDependencies,
              Icons.hub_outlined,
              '依赖就绪',
              '$dependencyReady/${dependencyReadyStates.length}',
              '核心 / PostgreSQL / Redis / Playwright / GPT',
              color: dependencyReady >= 1
                  ? OpenHandStatusColors.success
                  : OpenHandStatusColors.warning,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _OpsPanelGrid(
          children: [
            _DistributionPanel(
              id: _DistributionInsightId.proxyReliability,
              icon: Icons.security_rounded,
              title: '代理可靠性分布',
              centerValue: '${proxy?.totalSelections ?? 0}',
              items: [
                _DistributionItem(
                  '成功',
                  proxy?.totalSuccesses ?? 0,
                  OpenHandStatusColors.success,
                ),
                _DistributionItem(
                  '失败',
                  proxy?.totalFailures ?? 0,
                  OpenHandStatusColors.error,
                ),
                _DistributionItem(
                  '超时',
                  proxy?.totalTimeouts ?? 0,
                  OpenHandStatusColors.warning,
                ),
                _DistributionItem(
                  '执行中',
                  proxy?.inFlight ?? 0,
                  OpenHandStatusColors.info,
                ),
              ],
            ),
            _DistributionPanel(
              id: _DistributionInsightId.ruleVendor,
              icon: Icons.category_outlined,
              title: '启用规则供应商分布',
              centerValue: '${enabledRules.length}',
              items: vendorCounts.entries
                  .take(8)
                  .toList(growable: false)
                  .asMap()
                  .entries
                  .map(
                    (entry) => _DistributionItem(
                      entry.value.key,
                      entry.value.value,
                      _chartColor(entry.key, Theme.of(context).colorScheme),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Section(
          title: '扫描规则与编码识别',
          icon: Icons.rule_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '启用 ${controller.rules.where((rule) => rule.enabled).length}/${controller.rules.length} 条规则 · 凭证正则 ${controller.rules.expand((rule) => rule.credentialPatterns).length} 条',
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: AiExposureContentEncoding.values
                    .map((encoding) {
                      final enabled = encodings.contains(encoding);
                      return _StatusPill(
                        icon: enabled
                            ? Icons.check_rounded
                            : Icons.remove_rounded,
                        label: switch (encoding) {
                          AiExposureContentEncoding.base64 => 'Base64',
                          AiExposureContentEncoding.base64Url => 'Base64URL',
                          AiExposureContentEncoding.url => 'URL Encoding',
                          AiExposureContentEncoding.hex => 'Hex',
                        },
                        color: enabled
                            ? OpenHandStatusColors.success
                            : Theme.of(context).colorScheme.outline,
                        onTap: !enabled
                            ? null
                            : () => _showRulesForEncoding(
                                context,
                                encoding: encoding,
                                rules: enabledRules.where(
                                  (rule) =>
                                      rule.contentEncodings.contains(encoding),
                                ),
                              ),
                      );
                    })
                    .toList(growable: false),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Section(
          title: '网络与代理',
          icon: Icons.lan_outlined,
          child: Column(
            children: [
              _DependencyLine(
                id: _DependencyInsightId.proxyRouting,
                name: '请求出口',
                ready: true,
                detail: controller.proxyRoute == AiExposureProxyRoute.pool
                    ? '代理池 ${proxy?.endpoints.length ?? 0} 个节点，累计 ${proxy?.totalSelections ?? 0} 次，执行中 ${proxy?.inFlight ?? 0}'
                    : serviceProxyRouteText(controller, text),
              ),
              _DependencyLine(
                id: _DependencyInsightId.proxyReliability,
                name: '代理可靠性',
                ready:
                    controller.proxyRoute != AiExposureProxyRoute.pool ||
                    (proxy?.totalFailures ?? 0) + (proxy?.totalTimeouts ?? 0) ==
                        0,
                detail: controller.proxyRoute == AiExposureProxyRoute.pool
                    ? '成功 ${proxy?.totalSuccesses ?? 0} · 失败 ${proxy?.totalFailures ?? 0} · 超时 ${proxy?.totalTimeouts ?? 0} · 平均 ${proxy?.averageResponseTimeMs ?? 0}ms'
                    : '代理池当前未参与选路',
              ),
              _DependencyLine(
                id: _DependencyInsightId.localBypass,
                name: '本地旁路',
                ready: proxy?.bypassLocal ?? true,
                detail: proxy?.bypassLocal == true
                    ? '回环、私网和链路本地地址绕过代理池，再按系统代理规则选路'
                    : '所有目标均按代理策略选路',
              ),
              _DependencyLine(
                id: _DependencyInsightId.rotationPolicy,
                name: '轮询规则',
                ready: controller.proxyRoute == AiExposureProxyRoute.pool,
                detail:
                    controller.proxyRoute == AiExposureProxyRoute.pool &&
                        proxy != null
                    ? '${proxy.strategy.id} · 每 ${proxy.rotationEvery} 次请求轮换'
                    : '代理池当前未参与选路',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Section(
          title: '运行依赖与子服务',
          icon: Icons.hub_outlined,
          child: Column(
            children: [
              _DependencyLine(
                id: _DependencyInsightId.scannerCore,
                name: 'ai_jungler',
                ready: controller.isRunning,
                detail: controller.health?.databasePath ?? '自研 Rust 扫描引擎',
              ),
              _DependencyLine(
                id: _DependencyInsightId.sqlite,
                name: 'SQLite',
                ready: controller.isRunning,
                detail: '本地任务、规则、结果与日志存储',
              ),
              _DependencyLine(
                id: _DependencyInsightId.sourceAdapters,
                name: '资产发现适配器',
                ready: controller.sourceStatus.values.any((item) => item),
                detail:
                    '代码托管 / 测绘平台 / NodeSeek / LINUX DO / V2EX，已就绪 ${controller.sourceStatus.values.where((item) => item).length}/${controller.discoverySourceCount}',
              ),
              _DependencyLine(
                id: _DependencyInsightId.playwright,
                name: 'Playwright 浏览器通道',
                ready: dependencies?.playwright.connected == true,
                configured: dependencies?.playwright.configured,
                detail: dependencies?.playwright.message ?? '未接入浏览器降级通道',
              ),
              _DependencyLine(
                id: _DependencyInsightId.fingerprintRules,
                name: '指纹与规则引擎',
                ready: enabledRules.isNotEmpty,
                detail:
                    '${enabledRules.length} 条启用规则 · $patterns 条凭证模式 · ${encodings.length} 类编码',
              ),
              _DependencyLine(
                id: _DependencyInsightId.activeValidator,
                name: '主动验证器',
                ready: modelPaths > 0,
                detail: '$modelPaths 个模型端点 · $balancePaths 个余额端点',
              ),
              _DependencyLine(
                id: _DependencyInsightId.taskEventStream,
                name: '任务事件流',
                ready: controller.isRunning,
                detail: controller.hasActiveScan
                    ? '实时推送进度、日志与结果事件'
                    : '已就绪，当前无活动任务',
              ),
              _DependencyLine(
                id: _DependencyInsightId.postgresql,
                name: 'PostgreSQL',
                ready: dependencies?.postgresql.connected == true,
                configured: dependencies?.postgresql.configured,
                detail: dependencies?.postgresql.message ?? '未启用',
              ),
              _DependencyLine(
                id: _DependencyInsightId.redis,
                name: 'Redis',
                ready: dependencies?.redis.connected == true,
                configured: dependencies?.redis.configured,
                detail: dependencies?.redis.message ?? '未启用',
              ),
              _DependencyLine(
                id: _DependencyInsightId.gptExtractor,
                name: 'GPT 辅助提取',
                ready: controller.aiExtractorStatus?.configured == true,
                configured: controller.aiExtractorStatus?.configured,
                detail: controller.aiExtractorStatus?.model ?? '未启用',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
