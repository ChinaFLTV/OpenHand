// Centralized「现象 / 原因 / 建议」三段式中英双语网络诊断文案。
//
// 此前 ai_chat_service.dart / ai_image_generation_service.dart 各有一份
// 几乎完全一样的 _ChatErrorMessages / _MediaErrorMessages 私有实现 (~280
// 行 × 2)。本文件抽出公共版本，由这些调用方共用，避免文案漂移与维护
// 双倍的负担。
//
// 设计取舍：
//   · 通过 `contextLabel` 可选参数允许调用方在每条文案标题尾缀 `[xxx]`
//     提示流水线归属 (e.g. `[image (image)]`)。Chat 路径传空串即可。
//   · `httpStatus` 接受 `extraReason` / `extraSuggest`，方便不同调用方
//     在通用 4xx/5xx 模板基础上追加自家上下文 (e.g. 媒体 prompt 调参)。
//   · `AiModelScanner._ScanErrorMessages` 暂时保留独立实现，因为它包含
//     扫描场景独有的建议（例如「在「手动添加模型 ID」处直接录入」），
//     与 Chat / Media 用户面对的操作不同。
//
// 输出统一为纯文本（不含 Markdown 标记），下游 SnackBar / banner /
// SelectableText 都能直接渲染。
//
// 注意：文案中刻意保留中英双语标题与建议，方便用户在多语种环境下都能
// 抓到关键词（例如英文社区的 Cloudflare JA3 知识、HTTP 数字含义等）。

import 'dart:io';

import 'package:http/http.dart' as http;

class AiTransportDiagnosticMessages {
  AiTransportDiagnosticMessages._();

  static String _suffix(String contextLabel) {
    final t = contextLabel.trim();
    return t.isEmpty ? '' : ' [$t]';
  }

  static String handshake(HandshakeException e, {String contextLabel = ''}) {
    final detail = e.message.trim();
    return _format(
      title: 'TLS handshake rejected · TLS 握手被拒绝${_suffix(contextLabel)}',
      reason:
          '请求未到达业务层，TLS 握手就被服务端 / 中间设备拒绝。常见原因：\n'
          '  · Cloudflare / WAF 通过 JA3 / JA4 指纹封锁了非浏览器 TLS 客户端\n'
          '  · 服务端要求强制 TLS 1.3，本地链路被中间盒降级\n'
          '  · 系统时间偏差过大导致证书被判定为未生效 / 已过期\n'
          '  · 客户端与服务端无可协商的加密套件',
      try_:
          '· 切换其他可访问的中转 / 直连官方 endpoint\n'
          '· 检查本机系统时间是否准确\n'
          '· 通过 curl 等工具复现，确认是否被 WAF 拦截',
      raw: detail.isEmpty ? null : detail,
    );
  }

  static String tls(TlsException e, {String contextLabel = ''}) {
    return _format(
      title: 'TLS error · TLS 协议错误${_suffix(contextLabel)}',
      reason:
          'TLS 通道异常：${e.message}\n'
          '常见诱因：\n'
          '  · 服务端证书过期、域名不匹配或未由可信 CA 签发\n'
          '  · 中间存在 HTTPS 拦截 (公司防火墙 / 抓包工具)\n'
          '  · 本机根证书库过旧未包含目标 CA',
      try_: '· 在浏览器打开同一 URL 检查证书是否报警\n· 关闭抓包工具 / 公司代理后再试\n· 联系中转方确认证书链',
    );
  }

  static String socket(SocketException e, {String contextLabel = ''}) {
    final msg = e.message.toLowerCase();
    String reason;
    String suggest;
    if (msg.contains('failed host lookup') || msg.contains('no address')) {
      reason =
          '主机名 DNS 解析失败。可能的原因：\n'
          '  · Base URL 写错或多/少了协议前缀\n'
          '  · 本机 DNS 配置异常或网络无外网\n'
          '  · 域名被运营商屏蔽 / 劫持';
      suggest = '· 复核 Base URL\n· 在终端执行 `ping`/`nslookup` 验证\n· 切换网络 / VPN';
    } else if (msg.contains('connection refused')) {
      reason = 'TCP 连接被服务端主动拒绝。可能服务未启动 / 端口写错 / 防火墙拦截。';
      suggest = '· 确认 Base URL 中端口与服务端实际端口一致\n· 暂停本机防火墙再试';
    } else if (msg.contains('network is unreachable') ||
        msg.contains('no route to host')) {
      reason = '本机当前无法到达目标网络 (network unreachable / no route to host)。';
      suggest = '· 检查 Wi-Fi / 蜂窝 / 有线连接\n· 内网目标请确认 VPN 已连通';
    } else if (msg.contains('timed out') || msg.contains('timeout')) {
      reason =
          'TCP 连接超时。常见诱因：\n'
          '  · 跨境弱网 / 中间链路丢包\n'
          '  · 服务端被防火墙静默丢包\n'
          '  · 端口被运营商屏蔽';
      suggest = '· 切换网络后重试\n· traceroute / mtr 定位卡点';
    } else {
      reason = '底层 socket 抛出错误：${e.message}';
      suggest = '· 重试或更换网络环境';
    }
    return _format(
      title: 'Network error · 网络层错误${_suffix(contextLabel)}',
      reason: reason,
      try_: suggest,
      raw: e.osError == null ? e.message : '${e.message} (${e.osError})',
    );
  }

  static String httpClient(http.ClientException e, {String contextLabel = ''}) {
    return _format(
      title: 'HTTP client error · HTTP 客户端错误${_suffix(contextLabel)}',
      reason: 'HTTP 客户端在处理请求 / 响应阶段失败：${e.message}\n通常意味着连接中断、响应被截断、或服务端关闭连接。',
      try_: '· 稍后重试\n· 检查网络稳定性\n· 联系中转方确认服务状态',
    );
  }

  static String timeout(
    Duration limit, {
    String contextLabel = '',
    String? customReasonExtras,
  }) {
    final extras = (customReasonExtras ?? '').trim();
    return _format(
      title: 'Request timed out · 请求超时${_suffix(contextLabel)}',
      reason:
          '本次调用在 ${limit.inSeconds} 秒内未能完成。常见诱因：\n'
          '  · 跨境网络延迟过高\n'
          '  · 服务端处理慢 / 队列拥塞\n'
          '  · 中间代理在传输中卡死'
          '${extras.isEmpty ? '' : '\n  · $extras'}',
      try_: '· 稍后重试\n· 切换网络或中转\n· 缩短上下文长度后再发送',
    );
  }

  static String httpStatus(
    int code, {
    String serverMessage = '',
    String contextLabel = '',
    String contextHint = '',
  }) {
    String title;
    String reason;
    String suggest;
    final trimmedServer = serverMessage.trim();
    final ctxHint = contextHint.trim();
    final hintSuffix = ctxHint.isEmpty ? '' : ' · $ctxHint';
    final labelSuffix = _suffix(contextLabel);
    final relayAvailabilityReason = relayModelAvailabilityReason(trimmedServer);
    if (relayAvailabilityReason != null) {
      return _format(
        title: 'Model unavailable in relay ($code) · 模型在当前中转不可用$hintSuffix$labelSuffix',
        reason: relayAvailabilityReason,
        try_:
            '· 改用该中转已上架的模型 ID\n'
            '· 在中转方控制台确认当前分组 / 渠道是否开通该模型\n'
            '· 若你预期可用，联系中转方检查 distributor / channel 配置',
        raw: trimmedServer.isEmpty ? null : trimmedServer,
      );
    }
    switch (code) {
      case 400:
        title = 'Bad request (400) · 请求被拒$hintSuffix$labelSuffix';
        reason = '服务端拒绝处理本次请求 (400)。请求体可能不符合该协议规范，或附件 / 参数超出允许范围。';
        suggest = '· 复核 Base URL 与协议是否匹配\n· 缩减消息长度 / 附件数量后重试';
        break;
      case 401:
        title = 'Authentication failed (401) · 鉴权失败$hintSuffix$labelSuffix';
        reason = '服务端返回 401 Unauthorized：身份令牌缺失或已失效。';
        suggest = '· 确认 API Key / Token 已正确粘贴，无前后空格\n· 在中转方控制台重新生成令牌';
        break;
      case 403:
        title = 'Forbidden (403) · 访问被拒$hintSuffix$labelSuffix';
        reason = '服务端返回 403 Forbidden：当前令牌无权访问该模型，或 IP 不在允许地区，或触发了 WAF / 风控。';
        suggest = '· 在中转方控制台确认账号余额与权限\n· 切换网络 / VPN 后重试';
        break;
      case 404:
        title = 'Endpoint not found (404) · 端点不存在$hintSuffix$labelSuffix';
        reason = '服务端返回 404 Not Found：Base URL 路径错误，或所选模型在该中转尚未上架。';
        suggest = '· 复核 Base URL 与模型 ID\n· 在中转方控制台查看可用模型列表';
        break;
      case 408:
        title = 'Server timeout (408) · 服务端超时$hintSuffix$labelSuffix';
        reason = '服务端在收到请求头后超时关闭连接 (408)。';
        suggest = '· 稍后重试\n· 切换网络后再试';
        break;
      case 413:
        title = 'Payload too large (413) · 请求体过大$hintSuffix$labelSuffix';
        reason = '请求体超过中转 / 上游允许的最大尺寸 (413)。多发生于附件较多或上下文过长的场景。';
        suggest = '· 删减附件数量 / 大小\n· 缩短上下文 / 摘要旧消息后再发送';
        break;
      case 429:
        title = 'Rate limited (429) · 触发限流$hintSuffix$labelSuffix';
        reason = '服务端返回 429 Too Many Requests：调用过于频繁或额度已用尽。';
        suggest = '· 稍等几分钟后重试\n· 在中转方控制台确认配额 / 余额';
        break;
      case 500:
        title = 'Server error (500) · 服务端内部错误$hintSuffix$labelSuffix';
        reason = '服务端返回 500 Internal Server Error：上游或中转方自身出现故障。';
        suggest = '· 稍后重试\n· 联系中转方查看服务状态';
        break;
      case 502:
        title = 'Bad gateway (502) · 网关异常$hintSuffix$labelSuffix';
        reason = '服务端返回 502 Bad Gateway：中转无法从上游 (Anthropic / OpenAI 等) 取得有效响应。';
        suggest = '· 稍后重试\n· 联系中转方确认上游通路';
        break;
      case 503:
        title = 'Service unavailable (503) · 服务不可用$hintSuffix$labelSuffix';
        reason = '服务端返回 503 Service Unavailable：服务在维护或被熔断。';
        suggest = '· 稍后重试\n· 关注中转方公告';
        break;
      case 504:
        title = 'Gateway timeout (504) · 网关超时$hintSuffix$labelSuffix';
        reason = '服务端返回 504 Gateway Timeout：中转访问上游 LLM 时超时。';
        suggest = '· 稍后重试\n· 切换中转或缩短上下文后再试';
        break;
      default:
        if (code >= 500) {
          title = 'Server error ($code) · 服务端错误$hintSuffix$labelSuffix';
          reason = '服务端返回 $code，多为中转 / 上游故障。';
          suggest = '· 稍后重试\n· 联系中转方排查';
        } else if (code >= 400) {
          title = 'Client error ($code) · 客户端请求被拒$hintSuffix$labelSuffix';
          reason = '服务端返回 $code，请求未通过协议或鉴权校验。';
          suggest = '· 复核 Base URL / token / 自定义 header';
        } else {
          title = 'Unexpected status ($code) · 非预期响应$hintSuffix$labelSuffix';
          reason = '服务端返回非 2xx 状态码 $code。';
          suggest = '· 联系中转方排查';
        }
    }
    return _format(
      title: title,
      reason: reason,
      try_: suggest,
      raw: trimmedServer.isEmpty ? null : trimmedServer,
    );
  }

  static String? relayModelAvailabilityReason(String serverMessage) {
    final raw = serverMessage.trim();
    if (raw.isEmpty) {
      return null;
    }
    if (raw.contains('无可用渠道') ||
        raw.toLowerCase().contains('distributor') ||
        raw.toLowerCase().contains('channel')) {
      return '中转站已收到请求，但当前账号所在分组/渠道没有这个模型的可用分发。通常不是 Base URL、协议或密钥格式错误，而是该模型在当前中转未上架、未分配到你的分组，或对应渠道暂时不可用。';
    }
    return null;
  }

  static String format({
    required String title,
    required String reason,
    required String try_,
    String? raw,
  }) => _format(title: title, reason: reason, try_: try_, raw: raw);

  static String _format({
    required String title,
    required String reason,
    required String try_,
    String? raw,
  }) {
    final buf = StringBuffer()
      ..writeln(title)
      ..writeln('原因 / Why:')
      ..writeln(reason)
      ..writeln('建议 / Try:')
      ..write(try_);
    if (raw != null && raw.isNotEmpty) {
      buf
        ..writeln()
        ..write('服务端原文 / Server says: $raw');
    }
    return buf.toString();
  }
}
