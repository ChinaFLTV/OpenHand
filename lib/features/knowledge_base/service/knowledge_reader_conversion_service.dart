import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/reader_file_type.dart';
import '../../../shared/util/text_clip.dart';
import '../../ai/index.dart';

const int _kReaderDefaultMaxCharsPerSegment = 60000;
const int _kReaderMinMaxCharsPerSegment = 12000;
const int _kReaderMaxCharsPerSegment = 90000;
const int _kReaderMaxSegments = 8;
final RegExp _readerConvertedOutputFencePattern = RegExp(
  r'^```(?:markdown|md|json|text)?\s*([\s\S]*?)\s*```$',
  caseSensitive: false,
);

class KnowledgeReaderConversionRequest {
  const KnowledgeReaderConversionRequest({
    required this.model,
    required this.sourceType,
    required this.targetType,
    required this.content,
    required this.sourceTitle,
    this.cancelSignal,
  });

  final AiModelConfig model;
  final String sourceType;
  final String targetType;
  final String content;
  final String sourceTitle;
  final Future<void>? cancelSignal;
}

class KnowledgeReaderConversionResult {
  const KnowledgeReaderConversionResult({
    required this.text,
    required this.metadata,
  });

  final String text;
  final Map<String, Object?> metadata;
}

class KnowledgeReaderConversionService {
  KnowledgeReaderConversionService({AiChatClient? chatClient})
    : _chatClient = chatClient ?? AiChatService(),
      _ownsChatClient = chatClient == null;

  final AiChatClient _chatClient;
  final bool _ownsChatClient;

  Future<KnowledgeReaderConversionResult> convert(
    KnowledgeReaderConversionRequest request,
  ) {
    return AiUsageTraceContext.runDerived(
      source: AiUsageSource.knowledgeBase,
      operation: 'reader_conversion',
      metadata: <String, Object?>{
        'source_type': request.sourceType,
        'target_type': request.targetType,
      },
      body: () => _convert(request),
    );
  }

  Future<KnowledgeReaderConversionResult> _convert(
    KnowledgeReaderConversionRequest request,
  ) async {
    final sourceType = ReaderFileType.normalize(request.sourceType);
    final targetType = ReaderFileType.normalize(request.targetType);
    final profile = request.model.profileFor(request.model.modelId);
    if (!profile.supportsReaderConversionFor(
      sourceType: sourceType,
      targetType: targetType,
    )) {
      throw StateError(
        '模型 ${request.model.modelId} 不支持 $sourceType 到 $targetType 的读取转换。',
      );
    }
    final sourceText = request.content.trim();
    if (sourceText.isEmpty) {
      throw StateError('读取转换输入为空。');
    }
    final maxCharsPerSegment = _maxCharsPerSegment(profile);
    final maxChars = maxCharsPerSegment * _kReaderMaxSegments;
    if (sourceText.length > maxChars) {
      throw StateError('读取转换输入过大，已超过 ${maxChars ~/ kBytesPerKiB}KB 的安全上限。');
    }
    final segments = _splitSegments(sourceText, maxCharsPerSegment);
    final converted = <String>[];
    for (var index = 0; index < segments.length; index++) {
      final completion = await _chatClient.sendMessage(
        model: request.model,
        messages: <AiChatTurn>[
          const AiChatTurn(
            role: AiChatRole.system,
            content:
                '你是文档读取转换器。\n'
                '规则:\n'
                '- 只输出转换后的内容。\n'
                '- 保留标题、列表、表格、代码和可检索事实。\n'
                '- 目标为 JSON 时输出合法 JSON。\n'
                '- 不添加解释、寒暄或 Markdown 围栏。',
          ),
          AiChatTurn(
            role: AiChatRole.user,
            content:
                '源类型: $sourceType\n'
                '目标类型: $targetType\n'
                '文档标题: ${request.sourceTitle}\n'
                '分片: ${index + 1}/${segments.length}\n\n'
                '内容:\n${segments[index]}',
          ),
        ],
        creationRequest: AiCreationRequest.none,
        timeout: const Duration(seconds: 90),
        cancelSignal: request.cancelSignal,
      );
      final text = _cleanConvertedOutput(completion.reply);
      if (text.isNotEmpty) {
        converted.add(text);
      }
    }
    final output = converted.join('\n\n').trim();
    if (output.isEmpty) {
      throw StateError('读取转换模型返回了空内容。');
    }
    return KnowledgeReaderConversionResult(
      text: output,
      metadata: <String, Object?>{
        'reader_source_type': sourceType,
        'reader_target_type': targetType,
        'reader_model_id': request.model.modelId,
        'reader_provider_config_id': request.model.id,
        'reader_segment_count': segments.length,
        'reader_max_chars_per_segment': maxCharsPerSegment,
      },
    );
  }

  void dispose() {
    if (_ownsChatClient) {
      _chatClient.dispose();
    }
  }

  int _maxCharsPerSegment(AiModelProfile profile) {
    final byContext = (profile.maxContextLength ?? 0) > 0
        ? profile.maxContextLength! * 3
        : _kReaderDefaultMaxCharsPerSegment;
    return byContext.clamp(
      _kReaderMinMaxCharsPerSegment,
      _kReaderMaxCharsPerSegment,
    );
  }

  List<String> _splitSegments(String text, int maxChars) {
    if (text.length <= maxChars) return <String>[text];
    final segments = <String>[];
    var start = 0;
    while (start < text.length) {
      var end = (start + maxChars).clamp(0, text.length);
      if (end < text.length) {
        final boundary = text.lastIndexOf('\n\n', end);
        if (boundary > start + maxChars ~/ 2) {
          end = boundary;
        }
      }
      end = safeUtf16PrefixCodeUnits(text, end);
      segments.add(text.substring(start, end).trim());
      start = end;
      while (start < text.length && text.codeUnitAt(start) <= 32) {
        start++;
      }
    }
    return segments.where((item) => item.isNotEmpty).toList(growable: false);
  }

  String _cleanConvertedOutput(String value) {
    var text = value.trim();
    final fence = _readerConvertedOutputFencePattern.firstMatch(text);
    if (fence != null) {
      text = fence.group(1)?.trim() ?? text;
    }
    return text;
  }
}
