part of 'ai_exposure_monitoring_dialogs.dart';

class _PipelinePanel extends StatelessWidget {
  const _PipelinePanel({required this.controller});
  final ServicesController controller;

  @override
  Widget build(BuildContext context) {
    final history = controller.history;
    var fullScanCount = 0;
    var incrementalScanCount = 0;
    var activeValidationCount = 0;
    for (final item in history) {
      if (item.mode == AiExposureScanMode.full) {
        fullScanCount++;
      } else {
        incrementalScanCount++;
      }
      if (item.authorizedScope.isNotEmpty) activeValidationCount++;
    }
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
        kOpenHandGap12,
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
                  fullScanCount,
                  Theme.of(context).colorScheme.primary,
                ),
                _DistributionItem(
                  '增量扫描',
                  incrementalScanCount,
                  OpenHandStatusColors.info,
                ),
                _DistributionItem(
                  '主动验证',
                  activeValidationCount,
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
