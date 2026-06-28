import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:openhand/features/ai/service/operations/ai_stepfun_audio_policy.dart';

void main() {
  test('normalizeSpeechBody drops invalid StepFun numeric audio options', () {
    final normalized = AiStepFunAudioPolicy.normalizeSpeechBody(
      body: <String, Object?>{
        'voice': 'alloy',
        'response_format': 'bad',
        'speed': 'NaN',
        'volume': '3.5',
        'sample_rate': double.infinity,
        'bitrate': 128000,
        'pitch': 1.2,
      },
      protocol: AiProtocolType.stepfun,
      modelId: 'step-tts-mini',
    );

    expect(normalized['voice'], AiStepFunAudioPolicy.defaultVoice);
    expect(normalized['response_format'], 'mp3');
    expect(normalized.containsKey('speed'), isFalse);
    expect(normalized['volume'], 2.0);
    expect(normalized.containsKey('sample_rate'), isFalse);
    expect(normalized.containsKey('bitrate'), isFalse);
    expect(normalized.containsKey('pitch'), isFalse);
  });

  test('normalizeSpeechBody keeps supported StepFun sample rate', () {
    final normalized = AiStepFunAudioPolicy.normalizeSpeechBody(
      body: <String, Object?>{
        'voice': 'cixingnansheng',
        'response_format': 'wav',
        'speed': '0.2',
        'sample_rate': '24000',
      },
      protocol: AiProtocolType.stepfun,
      modelId: 'step-tts-mini',
    );

    expect(normalized['voice'], 'cixingnansheng');
    expect(normalized['response_format'], 'wav');
    expect(normalized['speed'], 0.5);
    expect(normalized['sample_rate'], 24000);
  });
}
