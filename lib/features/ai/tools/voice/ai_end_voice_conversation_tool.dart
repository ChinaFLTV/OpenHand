import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';

const aiVoiceCallIdKey = 'voice_call_id';
const aiEndedVoiceCallIdKey = 'ended_voice_call_id';
const aiVoiceConversationReminder =
    '当前为语音沟通。用户明确结束交流（如“好了，就到这里吧”“挂了吧”）或要求回到文字输入时，先通过 ToolSearch 加载 EndVoiceConversation，再调用它结束本次通话。不要因普通告别、引用或讨论挂断操作而自行结束通话。';

class AiEndVoiceConversationTool extends AiTool {
  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.endVoiceConversation;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final callId = context.metadata[aiVoiceCallIdKey];
    if (callId is! String || callId.isEmpty) {
      return AiToolUtils.invalidResult('EndVoiceConversation', '当前请求不属于语音通话。');
    }
    return AiToolUtils.simpleSuccessResult(
      command: 'EndVoiceConversation',
      durationMs: 0,
      output: '已请求结束本次语音沟通并返回文字输入。',
      metadata: <String, Object?>{aiEndedVoiceCallIdKey: callId},
    );
  }
}
