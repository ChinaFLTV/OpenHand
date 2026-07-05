import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/agents/model/agent_models.dart';

void main() {
  group('AgentScaleSettings', () {
    test('uses shared policy defaults', () {
      const settings = AgentScaleSettings();

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
