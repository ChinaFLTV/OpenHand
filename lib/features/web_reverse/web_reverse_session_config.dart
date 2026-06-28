import '../../shared/util/input_value_parsing.dart';
import 'web_reverse_browser_kind.dart';

/// Web 逆向会话的运行时配置，序列化进 session metadata。
///
/// 字段命名与 SessionDetailPage / openhand_home_page 中读取处保持一致，
/// 修改时务必同步更新两端。
class WebReverseSessionConfig {
  const WebReverseSessionConfig({
    required this.targetUrl,
    required this.objective,
    required this.cdpPort,
    required this.userDataDir,
    required this.browserKind,
    this.triggerActions,
    this.loginMode = WebReverseLoginMode.none,
    this.proxy,
    this.keywords = const <String>[],
    this.harPath,
    this.cdpMcpEnabled = false,
  });

  final String targetUrl;
  final String objective;
  final int cdpPort;
  final String userDataDir;
  final WebReverseBrowserKind browserKind;
  final String? triggerActions;
  final WebReverseLoginMode loginMode;
  final String? proxy;
  final List<String> keywords;
  final String? harPath;
  final bool cdpMcpEnabled;

  /// 浅拷贝；用于在 session.id 就绪后给 [userDataDir] 拼上 sessionId 后缀，
  /// 从源头规避"同一 user-data-dir 被多个会话复用导致 profile 锁占用"。
  WebReverseSessionConfig copyWith({
    String? targetUrl,
    String? objective,
    int? cdpPort,
    String? userDataDir,
    WebReverseBrowserKind? browserKind,
    String? triggerActions,
    WebReverseLoginMode? loginMode,
    String? proxy,
    List<String>? keywords,
    String? harPath,
    bool? cdpMcpEnabled,
  }) {
    return WebReverseSessionConfig(
      targetUrl: targetUrl ?? this.targetUrl,
      objective: objective ?? this.objective,
      cdpPort: cdpPort ?? this.cdpPort,
      userDataDir: userDataDir ?? this.userDataDir,
      browserKind: browserKind ?? this.browserKind,
      triggerActions: triggerActions ?? this.triggerActions,
      loginMode: loginMode ?? this.loginMode,
      proxy: proxy ?? this.proxy,
      keywords: keywords ?? this.keywords,
      harPath: harPath ?? this.harPath,
      cdpMcpEnabled: cdpMcpEnabled ?? this.cdpMcpEnabled,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'target_url': targetUrl,
    'objective': objective,
    'cdp_port': cdpPort,
    'user_data_dir': userDataDir,
    'browser_kind': browserKind.id,
    if (triggerActions != null) 'trigger_actions': triggerActions,
    'login_mode': loginMode.id,
    if (proxy != null) 'proxy': proxy,
    if (keywords.isNotEmpty) 'keywords': keywords,
    if (harPath != null) 'har_path': harPath,
    'cdp_mcp_enabled': cdpMcpEnabled,
  };

  static WebReverseSessionConfig? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, Object?>.from(raw);
    final targetUrl = '${map['target_url'] ?? ''}'.trim();
    final objective = '${map['objective'] ?? ''}'.trim();
    final cdpPort = optionalPositiveIntFromValue(map['cdp_port']) ?? 0;
    final userDataDir = '${map['user_data_dir'] ?? ''}'.trim();
    final browserKind = WebReverseBrowserKind.fromId(
      '${map['browser_kind'] ?? ''}',
    );
    if (targetUrl.isEmpty || cdpPort <= 0 || browserKind == null) return null;
    return WebReverseSessionConfig(
      targetUrl: targetUrl,
      objective: objective,
      cdpPort: cdpPort,
      userDataDir: userDataDir,
      browserKind: browserKind,
      triggerActions: nullIfBlank(map['trigger_actions']?.toString()),
      loginMode: WebReverseLoginMode.fromId('${map['login_mode'] ?? ''}'),
      proxy: nullIfBlank(map['proxy']?.toString()),
      keywords: stringListFromValue(map['keywords']),
      harPath: nullIfBlank(map['har_path']?.toString()),
      cdpMcpEnabled: boolFromValue(map['cdp_mcp_enabled']),
    );
  }

  /// 拼出会话首条 prompt 的内容块，模型据此进入工作流。
  ///
  /// 2026-05-17 — 直接用结构化 markdown bullet 列表，删除外层
  /// `<request_template>` XML 包裹：bullet 本身已经表达「这是一份请求模板」
  /// 的语义；XML tag 只对模型增加噪声，对用户可读性更是负担（用户在
  /// transcript 中能看到的「请求模板：…」就够了）。模板字段含义保持不变，
  /// 顺序保持不变，下游 prompt 解析逻辑只需读 bullet 即可。
  String toRequestTemplate() {
    final buf = StringBuffer()
      ..writeln('请求模板：')
      ..writeln('- 目标 URL：【$targetUrl】')
      ..writeln('- 逆向目标：【$objective】');
    if (triggerActions != null && triggerActions!.trim().isNotEmpty) {
      buf.writeln('- 触发动作：【${triggerActions!.trim()}】');
    }
    buf.writeln('- 登录态：【${loginMode.label}】');
    buf.writeln('- 浏览器：【${browserKind.displayName}】');
    buf.writeln('- CDP 端口：【$cdpPort】');
    buf.writeln(
      '- AI 侧 CDP MCP：【${cdpMcpEnabled ? '已启用，会按工具目录使用 chrome-devtools/js-reverse MCP' : '未启用；如需临时 chrome-devtools-mcp，请先在调试面板手动开启'}】',
    );
    if (proxy != null && proxy!.trim().isNotEmpty) {
      buf.writeln('- 代理：【${proxy!.trim()}】');
    }
    if (keywords.isNotEmpty) {
      buf.writeln('- 关键字：【${keywords.join(', ')}】');
    }
    buf.writeln(
      '- 取证纪律：【先确认 CDP / chrome-devtools / js-reverse MCP 工具名；先 Observe 请求、initiator、脚本；禁止 WebFetch/WebSearch/Bash/curl 直接抓目标源】',
    );
    buf.writeln(
      '- 任务产物：【目标请求、initiator、可疑脚本、关键 hook/断点、入参返回、first divergence、本地复现脚本】',
    );
    buf.write('- 验收标准：【可在 curl / Dart / Python 中独立复现，无需浏览器】');
    return buf.toString();
  }
}

enum WebReverseLoginMode {
  none('none', '无需登录'),
  manual('manual', '用户手动登录后继续'),
  storageState('storage_state', '使用已有 storageState');

  const WebReverseLoginMode(this.id, this.label);
  final String id;
  final String label;

  static WebReverseLoginMode fromId(String id) {
    for (final v in values) {
      if (v.id == id) return v;
    }
    return WebReverseLoginMode.none;
  }
}
