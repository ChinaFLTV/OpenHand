// 统一聊天与媒体流程的中英双语网络诊断文案。
// 支持附加上下文标签和状态补充说明，输出为可直接展示的纯文本。

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../../shared/ui/structured_error_text.dart';

class AiTransportDiagnosticMessages {
  AiTransportDiagnosticMessages._();

  static const Set<int> defaultRetryableStatusCodes = <int>{
    408,
    409,
    425,
    429,
    500,
    502,
    503,
    504,
  };

  static const Set<String> _retryableTransportMessageMarkers = <String>{
    'request timed out',
    'timed out',
    'timeout',
    'rate limit',
    'too many requests',
    'resource_exhausted',
    'overloaded',
    'temporarily',
    'temporary',
    'try again later',
    'connection reset',
    'connection closed',
    'connection aborted',
    'connection refused',
    'network error',
    'http client error',
    'service unavailable',
    'bad gateway',
    'gateway timeout',
    '请求超时',
    '触发限流',
    '网络层错误',
    '服务不可用',
    '网关异常',
    '网关超时',
    '服务端内部错误',
  };

  static final RegExp _retryableStatusCodePattern = RegExp(
    r'(?:\b(?:http|status|status code|code)\s*[:=#-]?\s*)?\b(\d{3})\b',
    caseSensitive: false,
  );

  static String _text({required String zh, required String en}) {
    return StructuredErrorText.pick(zh: zh, en: en);
  }

  static bool isRetryableTransportError(
    Object error, {
    Set<int> statusCodes = defaultRetryableStatusCodes,
    Iterable<String> extraMessageMarkers = const <String>[],
  }) {
    if (error is TimeoutException ||
        error is SocketException ||
        error is http.ClientException) {
      return true;
    }
    final message = '$error'.trim().toLowerCase();
    if (message.isEmpty) return false;
    if (_containsRetryableStatusCode(message, statusCodes)) return true;
    return _retryableTransportMessageMarkers
        .followedBy(extraMessageMarkers)
        .map((marker) => marker.trim().toLowerCase())
        .where((marker) => marker.isNotEmpty)
        .any(message.contains);
  }

  static String friendlyTransportError(
    Object error, {
    String contextLabel = '',
  }) {
    if (error is HandshakeException) {
      return handshake(error, contextLabel: contextLabel);
    }
    if (error is TlsException) {
      return tls(error, contextLabel: contextLabel);
    }
    if (error is SocketException) {
      return socket(error, contextLabel: contextLabel);
    }
    if (error is http.ClientException) {
      return httpClient(error, contextLabel: contextLabel);
    }
    return '$error';
  }

  static bool _containsRetryableStatusCode(
    String message,
    Set<int> statusCodes,
  ) {
    if (statusCodes.isEmpty) return false;
    for (final match in _retryableStatusCodePattern.allMatches(message)) {
      final statusCode = int.tryParse(match.group(1) ?? '');
      if (statusCode != null && statusCodes.contains(statusCode)) {
        return true;
      }
    }
    return false;
  }

  static String _suffix(String contextLabel) {
    final t = contextLabel.trim();
    return t.isEmpty ? '' : ' [$t]';
  }

  static String handshake(HandshakeException e, {String contextLabel = ''}) {
    final detail = e.message.trim();
    return _format(
      title:
          '${_text(zh: 'TLS 握手被拒绝', en: 'TLS handshake rejected')}${_suffix(contextLabel)}',
      reason: _text(
        zh:
            '请求未到达业务层，TLS 握手就被服务端或中间设备拒绝。常见原因：\n'
            '  · Cloudflare / WAF 通过 JA3 / JA4 指纹封锁了非浏览器 TLS 客户端\n'
            '  · 服务端要求强制 TLS 1.3，本地链路被中间盒降级\n'
            '  · 系统时间偏差过大导致证书被判定为未生效或已过期\n'
            '  · 客户端与服务端无可协商的加密套件',
        en:
            'The request never reached the application layer because the server or a middlebox rejected the TLS handshake. Common causes:\n'
            '  · Cloudflare / WAF blocked a non-browser TLS fingerprint such as JA3 / JA4\n'
            '  · The server requires TLS 1.3 and a middlebox downgraded the connection\n'
            '  · System time is far enough off that the certificate appears not yet valid or expired\n'
            '  · The client and server could not negotiate a shared cipher suite',
      ),
      try_: _text(
        zh:
            '· 切换其他可访问的中转或直连官方 endpoint\n'
            '· 检查本机系统时间是否准确\n'
            '· 通过 curl 等工具复现，确认是否被 WAF 拦截',
        en:
            '· Try another relay or the direct official endpoint\n'
            '· Check that the local system time is correct\n'
            '· Reproduce with curl or a similar tool to confirm whether a WAF is blocking it',
      ),
      raw: detail.isEmpty ? null : detail,
    );
  }

  static String tls(TlsException e, {String contextLabel = ''}) {
    return _format(
      title:
          '${_text(zh: 'TLS 协议错误', en: 'TLS error')}${_suffix(contextLabel)}',
      reason: _text(
        zh:
            'TLS 通道异常：${e.message}\n'
            '常见诱因：\n'
            '  · 服务端证书过期、域名不匹配或未由可信 CA 签发\n'
            '  · 中间存在 HTTPS 拦截（公司防火墙 / 抓包工具）\n'
            '  · 本机根证书库过旧未包含目标 CA',
        en:
            'The TLS channel failed: ${e.message}\n'
            'Common causes:\n'
            '  · The server certificate expired, does not match the hostname, or was not issued by a trusted CA\n'
            '  · HTTPS interception is happening in the middle (corporate firewall / packet capture tool)\n'
            '  · The local root certificate store is too old to trust the target CA',
      ),
      try_: _text(
        zh: '· 在浏览器打开同一 URL 检查证书是否报警\n· 关闭抓包工具或公司代理后再试\n· 联系中转方确认证书链',
        en:
            '· Open the same URL in a browser and check whether the certificate is flagged\n'
            '· Disable packet capture tools or the corporate proxy and try again\n'
            '· Ask the relay provider to verify the certificate chain',
      ),
    );
  }

  static String socket(SocketException e, {String contextLabel = ''}) {
    final msg = e.message.toLowerCase();
    String reason;
    String suggest;
    if (msg.contains('failed host lookup') || msg.contains('no address')) {
      reason = _text(
        zh:
            '主机名 DNS 解析失败。可能的原因：\n'
            '  · Base URL 写错或多了/少了协议前缀\n'
            '  · 本机 DNS 配置异常或当前网络无法访问外网\n'
            '  · 域名被运营商屏蔽或劫持',
        en:
            'DNS resolution for the hostname failed. Possible causes:\n'
            '  · The Base URL is misspelled or has the wrong protocol prefix\n'
            '  · Local DNS is misconfigured or the current network has no Internet access\n'
            '  · The domain is blocked or hijacked by the ISP',
      );
      suggest = _text(
        zh: '· 复核 Base URL\n· 在终端执行 `ping` / `nslookup` 验证\n· 切换网络或 VPN',
        en:
            '· Recheck the Base URL\n'
            '· Verify resolution with `ping` or `nslookup` in a terminal\n'
            '· Try another network or VPN',
      );
    } else if (msg.contains('connection refused')) {
      reason = _text(
        zh: 'TCP 连接被服务端主动拒绝。可能是服务未启动、端口写错，或被防火墙拦截。',
        en: 'The server actively refused the TCP connection. The service may be down, the port may be wrong, or a firewall may be blocking it.',
      );
      suggest = _text(
        zh: '· 确认 Base URL 中端口与服务端实际端口一致\n· 暂停本机防火墙后再试',
        en:
            '· Confirm that the port in the Base URL matches the server\'s real listening port\n'
            '· Temporarily disable the local firewall and try again',
      );
    } else if (msg.contains('network is unreachable') ||
        msg.contains('no route to host')) {
      reason = _text(
        zh: '本机当前无法到达目标网络。',
        en: 'The local machine cannot currently reach the target network.',
      );
      suggest = _text(
        zh: '· 检查 Wi-Fi、蜂窝或有线连接\n· 若目标位于内网，请确认 VPN 已连通',
        en:
            '· Check the Wi-Fi, cellular, or wired connection\n'
            '· If the target is on an internal network, confirm that the VPN is connected',
      );
    } else if (msg.contains('timed out') || msg.contains('timeout')) {
      reason = _text(
        zh:
            'TCP 连接超时。常见诱因：\n'
            '  · 跨境弱网或中间链路丢包\n'
            '  · 服务端被防火墙静默丢包\n'
            '  · 端口被运营商屏蔽',
        en:
            'The TCP connection timed out. Common causes:\n'
            '  · High latency or packet loss on the route\n'
            '  · A firewall is silently dropping packets on the server side\n'
            '  · The ISP is blocking the port',
      );
      suggest = _text(
        zh: '· 切换网络后重试\n· 用 traceroute / mtr 定位卡点',
        en:
            '· Retry from another network\n'
            '· Use traceroute or mtr to identify where the route is stalling',
      );
    } else {
      reason = _text(
        zh: '底层 socket 抛出错误：${e.message}',
        en: 'The underlying socket layer returned an error: ${e.message}',
      );
      suggest = _text(
        zh: '· 重试或更换网络环境',
        en: '· Retry or switch to another network environment',
      );
    }
    return _format(
      title:
          '${_text(zh: '网络层错误', en: 'Network error')}${_suffix(contextLabel)}',
      reason: reason,
      try_: suggest,
      raw: e.osError == null ? e.message : '${e.message} (${e.osError})',
    );
  }

  static String httpClient(http.ClientException e, {String contextLabel = ''}) {
    return _format(
      title:
          '${_text(zh: 'HTTP 客户端错误', en: 'HTTP client error')}${_suffix(contextLabel)}',
      reason: _text(
        zh: 'HTTP 客户端在处理请求或响应阶段失败：${e.message}\n通常意味着连接中断、响应被截断，或服务端关闭了连接。',
        en:
            'The HTTP client failed while handling the request or response: ${e.message}\n'
            'This usually means the connection was interrupted, the response was truncated, or the server closed the connection.',
      ),
      try_: _text(
        zh: '· 稍后重试\n· 检查网络稳定性\n· 联系中转方确认服务状态',
        en:
            '· Retry later\n'
            '· Check network stability\n'
            '· Ask the relay provider to confirm service status',
      ),
    );
  }

  static String timeout(
    Duration limit, {
    String contextLabel = '',
    String? customReasonExtras,
  }) {
    final extras = (customReasonExtras ?? '').trim();
    final extraLine = extras.isEmpty ? '' : '\n  · $extras';
    return _format(
      title:
          '${_text(zh: '请求超时', en: 'Request timed out')}${_suffix(contextLabel)}',
      reason: _text(
        zh:
            '本次调用在 ${limit.inSeconds} 秒内未能完成。常见诱因：\n'
            '  · 跨境网络延迟过高\n'
            '  · 服务端处理较慢或队列拥塞\n'
            '  · 中间代理在传输中卡住'
            '$extraLine',
        en:
            'This request did not complete within ${limit.inSeconds} seconds. Common causes:\n'
            '  · Cross-region network latency is too high\n'
            '  · The server is slow or the queue is congested\n'
            '  · An intermediate proxy stalled during transfer'
            '$extraLine',
      ),
      try_: _text(
        zh: '· 稍后重试\n· 切换网络或中转\n· 缩短上下文后再发送',
        en:
            '· Retry later\n'
            '· Switch to another network or relay\n'
            '· Shorten the context before sending again',
      ),
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
        title:
            '${_text(zh: '模型在当前中转不可用 ($code)', en: 'Model unavailable in relay ($code)')}$hintSuffix$labelSuffix',
        reason: relayAvailabilityReason,
        try_: _text(
          zh:
              '· 改用该中转已上架的模型 ID\n'
              '· 在中转方控制台确认当前分组或渠道是否开通该模型\n'
              '· 若你预期可用，请联系中转方检查 distributor / channel 配置',
          en:
              '· Switch to a model ID that is already enabled on this relay\n'
              '· Check in the relay console whether the current group or channel can access this model\n'
              '· If you expect it to be available, ask the relay provider to inspect the distributor / channel configuration',
        ),
        raw: trimmedServer.isEmpty ? null : trimmedServer,
      );
    }
    final grpcDiagnosis = _grpcDiagnostic(trimmedServer, code);
    if (grpcDiagnosis != null) {
      return _format(
        title: '${grpcDiagnosis.title}$hintSuffix$labelSuffix',
        reason: grpcDiagnosis.reason,
        try_: grpcDiagnosis.suggest,
        raw: trimmedServer.isEmpty ? null : trimmedServer,
      );
    }
    switch (code) {
      case 400:
        title =
            '${_text(zh: '请求被拒 (400)', en: 'Bad request (400)')}$hintSuffix$labelSuffix';
        reason = _text(
          zh: '服务端拒绝处理本次请求（400）。请求体可能不符合该协议规范，或附件、参数超出允许范围。',
          en: 'The server refused to process the request (400). The payload may not match the expected protocol, or the attachments / parameters may be out of range.',
        );
        suggest = _text(
          zh: '· 复核 Base URL 与协议是否匹配\n· 缩减消息长度或附件数量后重试',
          en:
              '· Check that the Base URL matches the protocol\n'
              '· Reduce message length or attachment count and try again',
        );
      case 401:
        title =
            '${_text(zh: '鉴权失败 (401)', en: 'Authentication failed (401)')}$hintSuffix$labelSuffix';
        reason = _text(
          zh: '服务端返回 401 Unauthorized：身份令牌缺失或已失效。',
          en: 'The server returned 401 Unauthorized: the credential is missing or has expired.',
        );
        suggest = _text(
          zh: '· 确认 API Key / Token 已正确粘贴且无前后空格\n· 在中转方控制台重新生成令牌',
          en:
              '· Make sure the API key or token was pasted correctly with no surrounding spaces\n'
              '· Regenerate the credential in the relay console',
        );
      case 403:
        title =
            '${_text(zh: '访问被拒 (403)', en: 'Forbidden (403)')}$hintSuffix$labelSuffix';
        reason = _text(
          zh: '服务端返回 403 Forbidden：当前令牌无权访问该模型，或 IP 不在允许地区，或触发了 WAF / 风控。',
          en: 'The server returned 403 Forbidden: the current credential cannot access this model, the IP is outside the allowed region, or a WAF / risk-control rule was triggered.',
        );
        suggest = _text(
          zh: '· 在中转方控制台确认账号余额与权限\n· 切换网络或 VPN 后重试',
          en:
              '· Check account balance and permissions in the relay console\n'
              '· Retry from another network or through a VPN',
        );
      case 404:
        title =
            '${_text(zh: '端点不存在 (404)', en: 'Endpoint not found (404)')}$hintSuffix$labelSuffix';
        reason = _text(
          zh: '服务端返回 404 Not Found：Base URL 路径错误，或所选模型在该中转尚未上架。',
          en: 'The server returned 404 Not Found. The Base URL path may be wrong, or the selected model may not be available on this relay.',
        );
        suggest = _text(
          zh: '· 复核 Base URL 与模型 ID\n· 在中转方控制台查看可用模型列表',
          en:
              '· Recheck the Base URL and model ID\n'
              '· Open the relay console and inspect the list of available models',
        );
      case 408:
        title =
            '${_text(zh: '服务端超时 (408)', en: 'Server timeout (408)')}$hintSuffix$labelSuffix';
        reason = _text(
          zh: '服务端在收到请求头后超时关闭了连接。',
          en: 'The server closed the connection after timing out while handling the request headers.',
        );
        suggest = _text(
          zh: '· 稍后重试\n· 切换网络后再试',
          en: '· Retry later\n· Try again from another network',
        );
      case 413:
        title =
            '${_text(zh: '请求体过大 (413)', en: 'Payload too large (413)')}$hintSuffix$labelSuffix';
        reason = _text(
          zh: '请求体超过了中转或上游允许的最大尺寸。常见于附件较多或上下文过长的场景。',
          en: 'The request body exceeded the maximum size allowed by the relay or upstream service. This is common when too many attachments are included or the context is too long.',
        );
        suggest = _text(
          zh: '· 删减附件数量或大小\n· 缩短上下文，必要时先摘要旧消息',
          en:
              '· Reduce attachment count or size\n'
              '· Shorten the context and summarize older messages first if needed',
        );
      case 429:
        title =
            '${_text(zh: '触发限流 (429)', en: 'Rate limited (429)')}$hintSuffix$labelSuffix';
        reason = _text(
          zh: '服务端返回 429 Too Many Requests：调用过于频繁，或额度已用尽。',
          en: 'The server returned 429 Too Many Requests: requests are too frequent, or the quota has been exhausted.',
        );
        suggest = _text(
          zh: '· 稍等几分钟后重试\n· 在中转方控制台确认配额或余额',
          en:
              '· Wait a few minutes and try again\n'
              '· Check quota or balance in the relay console',
        );
      case 500:
        title =
            '${_text(zh: '服务端内部错误 (500)', en: 'Server error (500)')}$hintSuffix$labelSuffix';
        reason = _text(
          zh: '服务端返回 500 Internal Server Error：上游或中转方自身出现故障。',
          en: 'The server returned 500 Internal Server Error: the upstream provider or relay itself encountered a failure.',
        );
        suggest = _text(
          zh: '· 稍后重试\n· 联系中转方查看服务状态',
          en:
              '· Retry later\n'
              '· Ask the relay provider to check service status',
        );
      case 502:
        title =
            '${_text(zh: '网关异常 (502)', en: 'Bad gateway (502)')}$hintSuffix$labelSuffix';
        reason = _text(
          zh: '服务端返回 502 Bad Gateway：中转无法从上游（Anthropic / OpenAI 等）获得有效响应。',
          en: 'The server returned 502 Bad Gateway: the relay could not obtain a valid response from the upstream provider (Anthropic / OpenAI, etc.).',
        );
        suggest = _text(
          zh: '· 稍后重试\n· 联系中转方确认上游通路',
          en:
              '· Retry later\n'
              '· Ask the relay provider to verify the upstream connection',
        );
      case 503:
        title =
            '${_text(zh: '服务不可用 (503)', en: 'Service unavailable (503)')}$hintSuffix$labelSuffix';
        reason = _text(
          zh: '服务端返回 503 Service Unavailable：服务正在维护，或已被熔断。',
          en: 'The server returned 503 Service Unavailable: the service is under maintenance or has been circuit-broken.',
        );
        suggest = _text(
          zh: '· 稍后重试\n· 关注中转方公告',
          en:
              '· Retry later\n'
              '· Check announcements from the relay provider',
        );
      case 504:
        title =
            '${_text(zh: '网关超时 (504)', en: 'Gateway timeout (504)')}$hintSuffix$labelSuffix';
        reason = _text(
          zh: '服务端返回 504 Gateway Timeout：中转访问上游 LLM 时超时。',
          en: 'The server returned 504 Gateway Timeout: the relay timed out while talking to the upstream LLM.',
        );
        suggest = _text(
          zh: '· 稍后重试\n· 切换中转或缩短上下文后再试',
          en:
              '· Retry later\n'
              '· Switch to another relay or shorten the context before trying again',
        );
      default:
        if (code >= 500) {
          title =
              '${_text(zh: '服务端错误 ($code)', en: 'Server error ($code)')}$hintSuffix$labelSuffix';
          reason = _text(
            zh: '服务端返回 $code，多半是中转或上游故障。',
            en: 'The server returned $code, which usually indicates a relay or upstream failure.',
          );
          suggest = _text(
            zh: '· 稍后重试\n· 联系中转方排查',
            en: '· Retry later\n· Ask the relay provider to investigate',
          );
        } else if (code >= 400) {
          title =
              '${_text(zh: '客户端请求被拒 ($code)', en: 'Client error ($code)')}$hintSuffix$labelSuffix';
          reason = _text(
            zh: '服务端返回 $code，请求未通过协议或鉴权校验。',
            en: 'The server returned $code, and the request failed protocol or authentication validation.',
          );
          suggest = _text(
            zh: '· 复核 Base URL、token 与自定义 header',
            en: '· Recheck the Base URL, token, and custom headers',
          );
        } else {
          title =
              '${_text(zh: '非预期响应 ($code)', en: 'Unexpected status ($code)')}$hintSuffix$labelSuffix';
          reason = _text(
            zh: '服务端返回了非 2xx 状态码 $code。',
            en: 'The server returned a non-2xx status code: $code.',
          );
          suggest = _text(
            zh: '· 联系中转方排查',
            en: '· Ask the relay provider to investigate',
          );
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
    final normalized = raw.toLowerCase();
    if (raw.contains('无可用渠道') ||
        normalized.contains('no route available') ||
        normalized.contains('no available route') ||
        normalized.contains('distributor') ||
        normalized.contains('channel')) {
      return '中转站已收到请求，但当前账号所在分组/渠道没有这个模型的可用分发。通常不是 Base URL、协议或密钥格式错误，而是该模型在当前中转未上架、未分配到你的分组，或对应渠道暂时不可用。';
    }
    return null;
  }

  /// gRPC 状态码 -> 中英诊断。识别由 [extractApiErrorMessage] 标记的
  /// `"<NAME> (gRPC code N)"` 文本，给出语义准确的原因与建议，避免把
  /// gRPC NOT_FOUND（模型/资源在 API 层不存在）误判为「Base URL 路径错误」。
  static _GrpcDiagnosis? _grpcDiagnostic(String serverMessage, int httpCode) {
    final raw = serverMessage.trim();
    final match = _kGrpcCodePattern.firstMatch(raw);
    if (match == null) return null;
    final code = int.tryParse(match.group(1) ?? '');
    if (code == null) return null;
    switch (code) {
      case 5: // NOT_FOUND
        return _GrpcDiagnosis(
          title: _text(
            zh: '资源不存在 ($httpCode · gRPC NOT_FOUND)',
            en: 'Resource not found ($httpCode · gRPC NOT_FOUND)',
          ),
          reason: _text(
            zh: '服务端以 gRPC NOT_FOUND 响应，表示请求的模型或资源在 API 层面不存在，而非 Base URL 路径错误。',
            en: 'The server responded with gRPC NOT_FOUND, meaning the requested model or resource does not exist at the API level — not that the Base URL path is wrong.',
          ),
          suggest: _text(
            zh:
                '· 确认模型 ID 拼写正确\n'
                '· 在中转方控制台查看可用模型列表\n'
                '· 该模型可能在当前中转未上架或已下线',
            en:
                '· Verify the model ID is spelled correctly\n'
                '· Check the available model list in the relay console\n'
                '· The model may not be deployed on this relay or may have been retired',
          ),
        );
      case 7: // PERMISSION_DENIED
        return _GrpcDiagnosis(
          title: _text(
            zh: '权限不足 ($httpCode · gRPC PERMISSION_DENIED)',
            en: 'Permission denied ($httpCode · gRPC PERMISSION_DENIED)',
          ),
          reason: _text(
            zh: '服务端以 gRPC PERMISSION_DENIED 响应：当前令牌无权访问该模型或操作，或账号未开通相应权限。',
            en: 'The server responded with gRPC PERMISSION_DENIED: the current credential cannot access this model or operation, or the account does not have the required permission.',
          ),
          suggest: _text(
            zh:
                '· 在中转方控制台确认账号权限与余额\n'
                '· 确认 API Key 已开通该模型访问权限',
            en:
                '· Confirm account permissions and balance in the relay console\n'
                '· Make sure the API key is authorized to access this model',
          ),
        );
      case 16: // UNAUTHENTICATED
        return _GrpcDiagnosis(
          title: _text(
            zh: '鉴权失败 ($httpCode · gRPC UNAUTHENTICATED)',
            en: 'Authentication failed ($httpCode · gRPC UNAUTHENTICATED)',
          ),
          reason: _text(
            zh: '服务端以 gRPC UNAUTHENTICATED 响应：身份令牌缺失、格式错误或已失效。',
            en: 'The server responded with gRPC UNAUTHENTICATED: the credential is missing, malformed, or has expired.',
          ),
          suggest: _text(
            zh:
                '· 确认 API Key / Token 已正确粘贴且无前后空格\n'
                '· 在中转方控制台重新生成令牌',
            en:
                '· Make sure the API key or token was pasted correctly with no surrounding spaces\n'
                '· Regenerate the credential in the relay console',
          ),
        );
      case 8: // RESOURCE_EXHAUSTED
        return _GrpcDiagnosis(
          title: _text(
            zh: '触发限流 ($httpCode · gRPC RESOURCE_EXHAUSTED)',
            en: 'Rate limited ($httpCode · gRPC RESOURCE_EXHAUSTED)',
          ),
          reason: _text(
            zh: '服务端以 gRPC RESOURCE_EXHAUSTED 响应：调用频率超限或额度已用尽。',
            en: 'The server responded with gRPC RESOURCE_EXHAUSTED: the request rate exceeded the limit or the quota is exhausted.',
          ),
          suggest: _text(
            zh: '· 稍等几分钟后重试\n· 在中转方控制台确认配额或余额',
            en:
                '· Wait a few minutes and try again\n'
                '· Check quota or balance in the relay console',
          ),
        );
      case 3: // INVALID_ARGUMENT
        return _GrpcDiagnosis(
          title: _text(
            zh: '参数无效 ($httpCode · gRPC INVALID_ARGUMENT)',
            en: 'Invalid argument ($httpCode · gRPC INVALID_ARGUMENT)',
          ),
          reason: _text(
            zh: '服务端以 gRPC INVALID_ARGUMENT 响应：请求中的某个参数（如模型 ID、消息格式、附件）不符合该协议规范。',
            en: 'The server responded with gRPC INVALID_ARGUMENT: a request parameter (such as the model ID, message shape, or attachment) does not match the expected protocol.',
          ),
          suggest: _text(
            zh:
                '· 复核模型 ID 与请求体格式\n'
                '· 缩减附件数量或消息长度后重试',
            en:
                '· Recheck the model ID and request body format\n'
                '· Reduce attachment count or message length and try again',
          ),
        );
      case 13: // INTERNAL
      case 2: // UNKNOWN
        return _GrpcDiagnosis(
          title: _text(
            zh: '服务端内部错误 ($httpCode · gRPC $code)',
            en: 'Server error ($httpCode · gRPC $code)',
          ),
          reason: _text(
            zh: '服务端以 gRPC 错误码 $code 响应，通常是上游或中转方自身故障。',
            en: 'The server responded with gRPC code $code, which usually indicates an upstream or relay failure.',
          ),
          suggest: _text(
            zh: '· 稍后重试\n· 联系中转方查看服务状态',
            en: '· Retry later\n· Ask the relay provider to check service status',
          ),
        );
      case 14: // UNAVAILABLE
        return _GrpcDiagnosis(
          title: _text(
            zh: '服务不可用 ($httpCode · gRPC UNAVAILABLE)',
            en: 'Service unavailable ($httpCode · gRPC UNAVAILABLE)',
          ),
          reason: _text(
            zh: '服务端以 gRPC UNAVAILABLE 响应：服务正在维护或暂时不可用。',
            en: 'The server responded with gRPC UNAVAILABLE: the service is under maintenance or temporarily unavailable.',
          ),
          suggest: _text(
            zh: '· 稍后重试\n· 关注中转方公告',
            en: '· Retry later\n· Check announcements from the relay provider',
          ),
        );
      default:
        return _GrpcDiagnosis(
          title: _text(
            zh: 'gRPC 错误 ($httpCode · code $code)',
            en: 'gRPC error ($httpCode · code $code)',
          ),
          reason: _text(
            zh: '服务端以 gRPC 状态码 $code 响应。',
            en: 'The server responded with gRPC status code $code.',
          ),
          suggest: _text(
            zh: '· 复核模型 ID、令牌与请求参数\n· 联系中转方排查',
            en:
                '· Recheck the model ID, credential, and request parameters\n'
                '· Ask the relay provider to investigate',
          ),
        );
    }
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
    return StructuredErrorText.format(
      title: title,
      reason: reason,
      try_: try_,
      server: raw,
    );
  }
}

/// 识别 `extractApiErrorMessage` 标记的 gRPC 文本：`"NOT_FOUND (gRPC code 5)"`。
final RegExp _kGrpcCodePattern = RegExp(
  r'\(gRPC code\s*(\d+)\)',
  caseSensitive: false,
);

class _GrpcDiagnosis {
  const _GrpcDiagnosis({
    required this.title,
    required this.reason,
    required this.suggest,
  });

  final String title;
  final String reason;
  final String suggest;
}
