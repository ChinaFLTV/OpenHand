import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../app/support/url_validation.dart';
import '../service/ai_bash_tool_service.dart';
import '../service/ai_chat_service.dart';
import '../service/ai_protocol_adapter.dart';
import '../service/ai_tool_runtime_service.dart';
import 'ai_tool.dart';
import 'ai_tool_execution_context.dart';
import 'ai_tool_utils.dart';

class AiWebFetchTool extends AiTool {
  AiWebFetchTool({
    required AiChatClient backgroundChatClient,
    required http.Client httpClient,
    Future<List<InternetAddress>> Function(String host)? hostLookup,
  })  : _backgroundChatClient = backgroundChatClient,
        _httpClient = httpClient,
        _hostLookup = hostLookup ??
            ((host) =>
                InternetAddress.lookup(host));

  final AiChatClient _backgroundChatClient;
  final http.Client _httpClient;
  final Future<List<InternetAddress>> Function(String host) _hostLookup;

  // Per-instance cache (15-minute TTL)
  static const Duration _cacheTtl = Duration(minutes: 15);
  static const int _maxRedirects = 5;
  static const int _maxResponseBytes = 1024 * 1024;
  static const int _maxCacheEntries = 64;
  final Map<String, _CachedContent> _cache = {};

  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.webFetch;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final startedAt = Stopwatch()..start();
    final rawUrl = '${args['url'] ?? ''}'.trim();
    final prompt = '${args['prompt'] ?? ''}'.trim();
    if (rawUrl.isEmpty || prompt.isEmpty) {
      return AiToolUtils.invalidResult('WebFetch', 'WebFetch requires url and prompt.');
    }
    final uri = tryParseValidHttpUrl(rawUrl);
    if (uri == null) {
      return AiToolUtils.invalidResult('WebFetch', 'Invalid URL: $rawUrl');
    }
    final blockedReason = await _blockedReason(uri);
    if (blockedReason != null) {
      return AiToolUtils.invalidResult('WebFetch', blockedReason);
    }
    final fetchResult = await _fetch(uri, cancelSignal: context.cancelSignal);
    if (fetchResult.cancelled) {
      return AiToolUtils.cancelledResult(
          command: 'WebFetch $rawUrl', durationMs: startedAt.elapsedMilliseconds);
    }
    if (fetchResult.crossHostRedirectUrl != null) {
      final redirectUrl = fetchResult.crossHostRedirectUrl!;
      return AiToolUtils.simpleSuccessResult(
        command: 'WebFetch $rawUrl',
        output:
            'Cross-host redirect detected.\nredirect_url: $redirectUrl\nmessage: WebFetch encountered a redirect to a different host. Make a new WebFetch request with redirect_url to continue.',
        durationMs: startedAt.elapsedMilliseconds,
        metadata: <String, Object?>{
          'webfetch_redirect_cross_host': true,
          'webfetch_redirect_url': redirectUrl,
          'webfetch_source_url': rawUrl,
        },
      );
    }
    if (fetchResult.errorMessage != null) {
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: 'WebFetch $rawUrl',
        workingDirectory: AiToolUtils.defaultWorkingDirectory(),
        stdout: '',
        stderr: fetchResult.errorMessage!,
        durationMs: startedAt.elapsedMilliseconds,
        resultText: 'status: failed\nerror: ${fetchResult.errorMessage!}',
      );
    }
    final body = fetchResult.body ?? '';
    final contentType = fetchResult.contentType ?? '';
    final normalizedContent = AiToolUtils.truncateContent(
      AiToolUtils.htmlToText(contentType.contains('html') ? body : body),
      AiToolUtils.maxWebContentCharacters,
    );
    final completion = await AiToolUtils.awaitWithCancellation<AiChatCompletion>(
      _backgroundChatClient.sendMessage(
        model: context.model,
        messages: <AiChatTurn>[
          const AiChatTurn(
            role: AiChatRole.system,
            content:
                'Answer the prompt using only the fetched page content. If the page content is insufficient, say so briefly.',
          ),
          AiChatTurn(
            role: AiChatRole.user,
            content: 'URL: $rawUrl\nPrompt: $prompt\n\nFetched content:\n$normalizedContent',
          ),
        ],
      ),
      cancelSignal: context.cancelSignal,
    );
    if (completion == null) {
      return AiToolUtils.cancelledResult(
          command: 'WebFetch $rawUrl', durationMs: startedAt.elapsedMilliseconds);
    }
    final output = completion.reply.trim().isEmpty
        ? normalizedContent
        : completion.reply.trim();
    return AiToolUtils.simpleSuccessResult(
      command: 'WebFetch $rawUrl',
      output: output,
      durationMs: startedAt.elapsedMilliseconds,
      metadata: <String, Object?>{
        'webfetch_final_url': fetchResult.finalUrl ?? uri.toString(),
        'webfetch_cache_hit': fetchResult.fromCache,
        'webfetch_content_type': contentType,
      },
    );
  }

  Future<String?> _blockedReason(Uri uri) async {
    final directReason = agentFetchBlockReasonForUri(uri);
    if (directReason != null) return 'WebFetch blocks $directReason: ${uri.host}';
    if (InternetAddress.tryParse(uri.host) != null) return null;
    try {
      final resolvedAddresses =
          await _hostLookup(uri.host).timeout(const Duration(seconds: 2));
      for (final address in resolvedAddresses) {
        final addressReason = agentFetchBlockReasonForAddress(address);
        if (addressReason != null) {
          return 'WebFetch blocked ${uri.host} because it resolved to $addressReason (${address.address}).';
        }
      }
    } on SocketException {
      return null;
    } on TimeoutException {
      return 'WebFetch blocked ${uri.host} because DNS resolution timed out.';
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<_FetchResult> _fetch(Uri initialUri, {Future<void>? cancelSignal}) async {
    _pruneCache();
    final cached = _cache[initialUri.toString()];
    if (cached != null && !_isCacheExpired(cached)) {
      return _FetchResult(
          body: cached.body,
          contentType: cached.contentType,
          finalUrl: cached.finalUrl,
          fromCache: true);
    }
    var currentUri = initialUri;
    final visitedUrls = <String>{};
    for (var redirectCount = 0;
        redirectCount <= _maxRedirects;
        redirectCount++) {
      final visitKey = currentUri.toString();
      if (!visitedUrls.add(visitKey)) {
        return const _FetchResult(errorMessage: 'Redirect loop detected while fetching the URL.');
      }
      final request = http.Request('GET', currentUri)
        ..followRedirects = false
        ..maxRedirects = 0;
      late final http.StreamedResponse response;
      try {
        final maybeResponse =
            await AiToolUtils.awaitWithCancellation<http.StreamedResponse>(
          _httpClient.send(request).timeout(const Duration(seconds: 20)),
          cancelSignal: cancelSignal,
        );
        if (maybeResponse == null) return const _FetchResult(cancelled: true);
        response = maybeResponse;
      } on TimeoutException {
        return const _FetchResult(errorMessage: 'WebFetch timed out while retrieving the URL.');
      } catch (error) {
        return _FetchResult(errorMessage: '$error');
      }
      if (_isRedirect(response.statusCode)) {
        final location = (response.headers['location'] ?? '').trim();
        if (location.isEmpty) {
          _discard(response);
          return _FetchResult(
              errorMessage:
                  'Received redirect response without a location header from $currentUri.');
        }
        final nextUri = normalizeValidHttpUri(currentUri.resolve(location));
        if (nextUri == null) {
          _discard(response);
          return _FetchResult(errorMessage: 'Invalid redirect target: $location');
        }
        final blocked = await _blockedReason(nextUri);
        if (blocked != null) {
          _discard(response);
          return _FetchResult(errorMessage: blocked);
        }
        if (currentUri.host.toLowerCase() != nextUri.host.toLowerCase()) {
          _discard(response);
          return _FetchResult(
              crossHostRedirectUrl: nextUri.toString(),
              finalUrl: currentUri.toString());
        }
        _discard(response);
        currentUri = nextUri;
        continue;
      }
      if (response.statusCode < 200 || response.statusCode >= 400) {
        _discard(response);
        return _FetchResult(
            errorMessage:
                'WebFetch failed with HTTP ${response.statusCode} for $currentUri.');
      }
      final bodyBytes = await _readBody(response, cancelSignal: cancelSignal);
      if (bodyBytes.cancelled) return const _FetchResult(cancelled: true);
      if (bodyBytes.errorMessage != null) {
        return _FetchResult(errorMessage: bodyBytes.errorMessage);
      }
      final resolvedResponse = http.Response.bytes(
        bodyBytes.bytes!,
        response.statusCode,
        headers: response.headers,
      );
      final entry = _CachedContent(
        body: resolvedResponse.body,
        contentType: (response.headers['content-type'] ?? '').trim(),
        finalUrl: currentUri.toString(),
        fetchedAt: DateTime.now().toUtc(),
      );
      _cache[initialUri.toString()] = entry;
      _cache[currentUri.toString()] = entry;
      return _FetchResult(
          body: entry.body,
          contentType: entry.contentType,
          finalUrl: entry.finalUrl);
    }
    return const _FetchResult(errorMessage: 'WebFetch exceeded the maximum redirect limit.');
  }

  Future<_BodyReadResult> _readBody(http.StreamedResponse response,
      {Future<void>? cancelSignal}) async {
    final completer = Completer<_BodyReadResult>();
    final buffer = BytesBuilder(copy: false);

    void complete(_BodyReadResult result) {
      if (!completer.isCompleted) completer.complete(result);
    }

    late final StreamSubscription<List<int>> subscription;
    subscription = response.stream.listen(
      (chunk) {
        if (buffer.length + chunk.length > _maxResponseBytes) {
          subscription.cancel().ignore();
          complete(const _BodyReadResult(
              errorMessage:
                  'WebFetch refused to download the response because it exceeded the $_maxResponseBytes-byte safety limit.'));
          return;
        }
        buffer.add(chunk);
      },
      onError: (Object error) => complete(_BodyReadResult(errorMessage: '$error')),
      onDone: () {
        if (!completer.isCompleted) {
          completer.complete(_BodyReadResult(bytes: buffer.takeBytes()));
        }
      },
      cancelOnError: true,
    );
    cancelSignal?.then((_) {
      subscription.cancel().ignore();
      complete(const _BodyReadResult(cancelled: true));
    });
    // Cancel the subscription once the completer has a result (e.g. size
    // limit exceeded) so the underlying connection is released promptly.
    completer.future.whenComplete(() => subscription.cancel().ignore());
    return completer.future;
  }

  bool _isRedirect(int statusCode) =>
      statusCode == 301 ||
      statusCode == 302 ||
      statusCode == 303 ||
      statusCode == 307 ||
      statusCode == 308;

  void _discard(http.StreamedResponse response) {
    response.stream.drain<void>().catchError((Object e, StackTrace st) {
      // Redirect responses are consumed and discarded; drain errors are not
      // actionable here, but surface them in debug builds to aid diagnosis.
      assert(() {
        // ignore: avoid_print
        print('ai_web_fetch: response drain failed: $e');
        return true;
      }());
    });
  }

  void _pruneCache() {
    _cache.removeWhere((_, v) => _isCacheExpired(v));
    // Evict oldest entries when the cache exceeds the size limit.
    if (_cache.length > _maxCacheEntries) {
      final sorted = _cache.entries.toList()
        ..sort((a, b) => a.value.fetchedAt.compareTo(b.value.fetchedAt));
      final excess = sorted.length - _maxCacheEntries;
      for (var i = 0; i < excess; i++) {
        _cache.remove(sorted[i].key);
      }
    }
  }

  bool _isCacheExpired(_CachedContent entry) =>
      DateTime.now().toUtc().difference(entry.fetchedAt) > _cacheTtl;
}

class _CachedContent {
  const _CachedContent({
    required this.body,
    required this.contentType,
    required this.finalUrl,
    required this.fetchedAt,
  });
  final String body;
  final String contentType;
  final String finalUrl;
  final DateTime fetchedAt;
}

class _FetchResult {
  const _FetchResult({
    this.body,
    this.contentType,
    this.finalUrl,
    this.crossHostRedirectUrl,
    this.errorMessage,
    this.fromCache = false,
    this.cancelled = false,
  });
  final String? body;
  final String? contentType;
  final String? finalUrl;
  final String? crossHostRedirectUrl;
  final String? errorMessage;
  final bool fromCache;
  final bool cancelled;
}

class _BodyReadResult {
  const _BodyReadResult({this.bytes, this.errorMessage, this.cancelled = false});
  final List<int>? bytes;
  final String? errorMessage;
  final bool cancelled;
}
