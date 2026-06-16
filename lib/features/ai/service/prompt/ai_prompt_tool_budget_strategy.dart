import '../../model/ai_attachment.dart';
import '../../model/ai_session.dart';
import '../../model/ai_session_message.dart';
import 'ai_prompt_template_assembly.dart';

enum AiPromptToolCatalogBudgetMode { full, directAnswerOnly }

class AiPromptToolCatalogDecision {
  const AiPromptToolCatalogDecision._({
    required this.mode,
    required this.reason,
  });

  static const AiPromptToolCatalogDecision full = AiPromptToolCatalogDecision._(
    mode: AiPromptToolCatalogBudgetMode.full,
    reason: '',
  );

  static const AiPromptToolCatalogDecision directAnswerOnly =
      AiPromptToolCatalogDecision._(
        mode: AiPromptToolCatalogBudgetMode.directAnswerOnly,
        reason: 'direct_answer_low_risk',
      );

  final AiPromptToolCatalogBudgetMode mode;
  final String reason;

  bool get omitsRuntimeTools =>
      mode == AiPromptToolCatalogBudgetMode.directAnswerOnly;

  String? get promptOmissionReason {
    if (!omitsRuntimeTools) return null;
    return reason;
  }
}

class AiPromptToolBudgetStrategy {
  const AiPromptToolBudgetStrategy();

  static const int maxDirectAnswerCharacters = 420;
  static const int maxDirectAnswerLines = 8;
  static const int _maxShortConversationCharacters = 80;
  static const Set<String> _continuationSignals = <String>{
    'continue',
    'goon',
    'keepgoing',
    '继续',
    '继续吧',
    '接着',
    '接着做',
  };
  static final RegExp _punctuationAndSpacePattern = RegExp(r'[\s。.!！?？,，、~～]+');
  static final RegExp _shortConversationCuePattern = RegExp(
    r'(想你|想我|喜欢你|爱你|分手|心上人|不好意思|对不起|抱歉|难过|伤心|开心|无聊|陪我|聊聊天|说点什么|有什么要对我说|你难道|早安|晚安|哈哈|呵呵|嘿嘿|呜呜|miss you|love you|break up|sorry|talk to me|chat with me|how are you)',
    caseSensitive: false,
  );

  AiPromptToolCatalogDecision decide({
    required AiSession session,
    required String? latestUserMessageId,
    required int toolRoundCount,
    required bool creationRequestActive,
  }) {
    final templatePolicy = AiPromptTemplatePolicies.resolve(session.templateId);
    if (!templatePolicy.directAnswerToolOmissionEnabled) {
      return AiPromptToolCatalogDecision.full;
    }
    if (creationRequestActive || toolRoundCount > 0) {
      return AiPromptToolCatalogDecision.full;
    }
    if (session.mode != AiSessionMode.chat ||
        session.awaitingPlanApproval ||
        session.todoItems.isNotEmpty ||
        session.pendingPlan?.trim().isNotEmpty == true ||
        session.latestActivePlanRecord != null) {
      return AiPromptToolCatalogDecision.full;
    }

    final latestUserMessage = _resolveLatestUserMessage(
      session,
      latestUserMessageId,
    );
    if (latestUserMessage == null || _hasAttachments(latestUserMessage)) {
      return AiPromptToolCatalogDecision.full;
    }

    final content = latestUserMessage.content.trim();
    if (content.isEmpty ||
        content.length > maxDirectAnswerCharacters ||
        '\n'.allMatches(content).length + 1 > maxDirectAnswerLines) {
      return AiPromptToolCatalogDecision.full;
    }
    if (_looksLikeToolOrWorkspaceIntent(content)) {
      return AiPromptToolCatalogDecision.full;
    }
    if (_isCasualDirectReply(content) ||
        _isShortConversationalTurn(content) ||
        _isIdentityQuestion(content) ||
        _isSimpleKnowledgeQuestion(content)) {
      return AiPromptToolCatalogDecision.directAnswerOnly;
    }
    return AiPromptToolCatalogDecision.full;
  }

  AiSessionMessage? _resolveLatestUserMessage(
    AiSession session,
    String? latestUserMessageId,
  ) {
    final requestedId = latestUserMessageId?.trim();
    if (requestedId != null && requestedId.isNotEmpty) {
      for (final message in session.messages) {
        if (message.id == requestedId &&
            !message.isDeleted &&
            message.kind == AiSessionMessageKind.user) {
          return message;
        }
      }
      return null;
    }
    for (var i = session.messages.length - 1; i >= 0; i--) {
      final message = session.messages[i];
      if (!message.isDeleted && message.kind == AiSessionMessageKind.user) {
        return message;
      }
    }
    return null;
  }

  bool _hasAttachments(AiSessionMessage message) {
    final raw = message.metadata[aiSessionMessageAttachmentsMetadataKey];
    return raw is List && raw.isNotEmpty;
  }

  bool _isCasualDirectReply(String content) {
    final normalized = _compactCasualText(content);
    const directReplies = <String>{
      '好',
      '好的',
      '好的谢谢',
      '好的谢谢你',
      '谢谢',
      '谢谢你',
      '谢谢啦',
      '谢谢哈',
      '多谢',
      '感谢',
      '收到',
      '了解',
      '明白',
      '你好',
      '您好',
      '早上好',
      '下午好',
      '晚上好',
      '泥嚎',
      '泥好',
      'ok',
      'okay',
      'hi',
      'hello',
      'hey',
      'thanks',
      'thankyou',
    };
    return directReplies.contains(normalized);
  }

  String _compactCasualText(String content) {
    return content.toLowerCase().replaceAll(_punctuationAndSpacePattern, '');
  }

  bool _isShortConversationalTurn(String content) {
    final compact = _compactCasualText(content);
    if (compact.isEmpty || compact.length > _maxShortConversationCharacters) {
      return false;
    }
    if (_continuationSignals.contains(compact)) {
      return false;
    }
    if (_shortConversationCuePattern.hasMatch(content)) {
      return true;
    }
    // Single short colloquial fragments are cheap to answer directly and do
    // not need the full native tool schema. Tool/workspace intents are filtered
    // before this method, so this only catches low-risk chatty turns.
    return compact.length <= 8 && !RegExp(r'[{}()[\]<>`=;:]').hasMatch(compact);
  }

  bool _isIdentityQuestion(String content) {
    final lower = content.toLowerCase();
    return lower.contains('你是谁') ||
        lower.contains('你叫什么') ||
        lower.contains('你是什么') ||
        lower.contains('who are you') ||
        lower.contains('what are you');
  }

  bool _isSimpleKnowledgeQuestion(String content) {
    final lower = content.toLowerCase();
    final markers = <String>[
      '如何',
      '怎么',
      '怎样',
      '是什么',
      '什么是',
      '为什么',
      '区别',
      '用法',
      '语法',
      '示例',
      '解释',
      '说明',
      'how to',
      'how do',
      'what is',
      'what are',
      'why',
      'difference',
      'explain',
      'usage',
      'example',
    ];
    return markers.any(lower.contains);
  }

  bool _looksLikeToolOrWorkspaceIntent(String content) {
    final lower = content.toLowerCase();
    if (RegExp(
      r'(/users/|~/|\./|\.\./|[a-z]:\\|[\w.-]+\.(dart|ts|tsx|js|py|go|rs|java|kt|swift|json|ya?ml|md|html|css|sh|sql|log|txt|csv|xlsx|docx|pdf)\b)',
      caseSensitive: false,
    ).hasMatch(lower)) {
      return true;
    }
    if (RegExp(
      r'(这个项目|本项目|仓库|代码库|源码|文件|目录|路径|报错|错误日志|终端|localhost|端口|构建|编译|测试失败|单元测试|flutter analyze|build_web)',
    ).hasMatch(content)) {
      return true;
    }
    if (RegExp(
      r'(最新|实时|价格|天气|新闻|汇率|股票|赛事|赛程|版本|today|latest|weather|news|stock|exchange rate|current price)',
      caseSensitive: false,
    ).hasMatch(content)) {
      return true;
    }
    if (RegExp(
      r'^\s*(执行|运行|跑|打开|读取|读一下|看一下|搜索|搜一下|查一下|查找|检索|联网|浏览|抓取|下载|安装|提交|构建|编译|测试|修复|修改|重构|创建|新建|删除|保存|截图|生成图片|生成照片|画图|画一张)',
    ).hasMatch(content)) {
      return true;
    }
    if (RegExp(
      r'(帮我|替我|给我|请你|麻烦).{0,12}(执行|运行|跑|打开|读取|读一下|看一下|搜索|搜一下|查一下|查找|检索|联网|浏览|抓取|下载|安装|提交|构建|编译|测试|修复|修改|重构|创建|新建|删除|保存|截图|画图|画一张|生成图片|生成照片)',
    ).hasMatch(content)) {
      return true;
    }
    if (RegExp(
      r'(搜索|搜一下|查一下|查找|检索|联网|浏览|抓取|下载|生成图片|生成照片|画图|画一张)',
    ).hasMatch(content)) {
      return true;
    }
    if (RegExp(
      r'\b(please|can you|could you)\s+(run|execute|open|read|search|browse|fetch|download|install|commit|push|build|test|fix|modify|refactor|create|delete)\b',
      caseSensitive: false,
    ).hasMatch(lower)) {
      return true;
    }
    if (RegExp(
      r'^(run|execute|open|read|search|browse|fetch|download|install|commit|push|build|test|fix|modify|refactor|create|delete)\b',
      caseSensitive: false,
    ).hasMatch(lower.trimLeft())) {
      return true;
    }
    return false;
  }
}
