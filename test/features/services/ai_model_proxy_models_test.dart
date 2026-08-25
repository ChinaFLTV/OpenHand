import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/services/model/ai_model_proxy_models.dart';

void main() {
  test('模型中转设置对非有限整数输入回退并保持范围', () {
    final settings = AiModelProxySettings.fromJson(<String, Object?>{
      'listen_port': double.nan,
      'limit_threshold': double.infinity,
      'retry_count': double.negativeInfinity,
      'request_count': double.nan,
    });

    expect(settings.listenPort, aiModelProxyDefaultListenPort);
    expect(settings.limitThreshold, 30);
    expect(settings.retryCount, 2);
    expect(settings.requestCount, 0);
  });

  test('模型中转统计对异常数值回退并限制上界', () {
    final component = AiModelProxyDailyComponent.fromJson(<String, Object?>{
      'requests': double.infinity,
      'successes': -1,
      'duration_ms': '${1 << 53}',
      'slow': double.nan,
    });

    expect(component.requests, 0);
    expect(component.successes, 0);
    expect(component.durationMs, 1 << 52);
    expect(component.slowCount, 0);
  });
}
