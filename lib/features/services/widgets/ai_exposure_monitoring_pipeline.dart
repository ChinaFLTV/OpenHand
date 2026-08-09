part of 'ai_exposure_monitoring_dialogs.dart';

class _PipelinePanel extends StatelessWidget {
  const _PipelinePanel({required this.controller});
  final ServicesController controller;

  @override
  Widget build(BuildContext context) {
    final history = controller.history;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => AiExposureTaskLedger(
            minHeight: constraints.maxWidth >= 760
                ? _kTaskLedgerPipelineMinHeight
                : null,
          ),
        ),
        const SizedBox(height: 12),
        _DependencyDataAccessPanel(controller: controller),
        const SizedBox(height: 12),
        _OpsPanelGrid(
          children: [
            _DistributionPanel(
              id: _DistributionInsightId.scanMode,
              icon: Icons.schema_outlined,
              title: '扫描模式分布',
              centerValue: '${history.length}',
              items: [
                _DistributionItem(
                  '全量扫描',
                  history
                      .where((item) => item.mode == AiExposureScanMode.full)
                      .length,
                  Theme.of(context).colorScheme.primary,
                ),
                _DistributionItem(
                  '增量扫描',
                  history
                      .where(
                        (item) => item.mode == AiExposureScanMode.incremental,
                      )
                      .length,
                  OpenHandStatusColors.info,
                ),
                _DistributionItem(
                  '主动验证',
                  history
                      .where((item) => item.authorizedScope.isNotEmpty)
                      .length,
                  OpenHandStatusColors.warning,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
