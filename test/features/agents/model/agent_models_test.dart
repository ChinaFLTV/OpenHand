import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/agents/model/agent_models.dart';

void main() {
  group('AgentScaleSettings', () {
    test('uses shared policy defaults', () {
      const settings = AgentScaleSettings();

      expect(settings.minWorkers, agentScaleDefaultMinWorkers);
      expect(settings.maxWorkers, agentScaleDefaultMaxWorkers);
      expect(settings.maxRetries, agentScaleDefaultMaxRetries);
      expect(settings.scaleOutThreshold, agentScaleDefaultScaleOutThreshold);
      expect(settings.scaleInThreshold, agentScaleDefaultScaleInThreshold);
      expect(settings.schedulerPolicy, agentSchedulerPolicyLeastBusy);
      expect(settings.workerRemovalPolicy, agentWorkerRemovalPolicyLeastBusy);
      expect(settings.retryPolicy, agentRetryPolicyBoundedRetry);
    });

    test('exposes stable policy option order', () {
      expect(agentSchedulerPolicyOptions, <String>[
        agentSchedulerPolicyLeastBusy,
        agentSchedulerPolicyPriorityFirst,
        agentSchedulerPolicyRoundRobin,
      ]);
      expect(agentWorkerRemovalPolicyOptions, <String>[
        agentWorkerRemovalPolicyLeastBusy,
        agentWorkerRemovalPolicyNewestFirst,
      ]);
      expect(agentRetryPolicyOptions, <String>[
        agentRetryPolicyBoundedRetry,
        agentRetryPolicyNone,
      ]);
    });

    test('clamps worker and retry bounds from json', () {
      final settings = AgentScaleSettings.fromJson(<String, Object?>{
        'min_workers': -3,
        'max_workers': 2000,
        'max_retries': 100,
        'scale_out_threshold': 9,
        'scale_in_threshold': -1,
      });

      expect(settings.minWorkers, agentScaleMinWorkersMinimum);
      expect(settings.maxWorkers, agentScaleWorkersMaximum);
      expect(settings.maxRetries, agentScaleMaxRetriesMaximum);
      expect(settings.scaleOutThreshold, agentScaleRatioMaximum);
      expect(settings.scaleInThreshold, agentScaleRatioMinimum);
    });
  });

  group('AgentKpiItem', () {
    test('uses shared status defaults and rank order', () {
      const item = AgentKpiItem(id: 'kpi-1', name: 'Quality');

      expect(item.status, agentKpiStatusTracking);
      expect(agentKpiStatusOptions.first, agentKpiStatusTracking);
      expect(
        agentKpiStatusRank(agentKpiStatusAtRisk),
        lessThan(agentKpiStatusRank(agentKpiStatusTracking)),
      );
      expect(
        agentKpiStatusRank(agentKpiStatusDone),
        greaterThan(agentKpiStatusRank(agentKpiStatusPaused)),
      );
    });
  });
}
