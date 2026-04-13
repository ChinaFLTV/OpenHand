import 'dart:async';

import 'package:http/http.dart' as http;

import '../service/ai_bash_tool_service.dart';
import '../service/ai_chat_service.dart';
import '../service/ai_protocol_adapter.dart';
import '../service/ai_tool_runtime_service.dart';
import 'ai_tool.dart';
import 'ai_tool_execution_context.dart';
import 'ai_tool_utils.dart';

class AiWebSearchTool extends AiTool {
  AiWebSearchTool({
    required AiChatClient backgroundChatClient,
    required http.Client httpClient,
  })  : _backgroundChatClient = backgroundChatClient,
        _httpClient = httpClient;

  final AiChatClient _backgroundChatClient;
  final http.Client _httpClient;

  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.webSearch;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final startedAt = Stopwatch()..start();
    final query = '${args['query'] ?? ''}'.trim();
    if (query.length < 2) {
      return AiToolUtils.invalidResult(
          'WebSearch', 'WebSearch requires query with at least 2 characters.');
    }
    final allowedDomains = AiToolUtils.normalizeStringList(args['allowed_domains']);
    final blockedDomains = AiToolUtils.normalizeStringList(args['blocked_domains']);
    final command = 'WebSearch $query';
    final workingDirectory = AiToolUtils.defaultWorkingDirectory();
    final progressBuffer = StringBuffer()..writeln('query: $query');
    if (allowedDomains.isNotEmpty) {
      progressBuffer.writeln('allowed_domains: ${allowedDomains.join(', ')}');
    }
    if (blockedDomains.isNotEmpty) {
      progressBuffer.writeln('blocked_domains: ${blockedDomains.join(', ')}');
    }

    void emitProgress({
      required String stage,
      required String detail,
      List<_SearchResult> previewResults = const <_SearchResult>[],
    }) {
      if (progressBuffer.isNotEmpty) progressBuffer.writeln();
      progressBuffer.writeln('stage: $stage');
      if (previewResults.isNotEmpty) {
        progressBuffer
            .writeln('results_preview_count: ${previewResults.length.clamp(0, 3)}');
        for (final result in previewResults.take(3)) {
          final title =
              AiToolUtils.truncateContent(result.title.replaceAll(RegExp(r'\s+'), ' ').trim(), 120);
          final url = AiToolUtils.truncateContent(result.url.trim(), 160);
          progressBuffer
            ..writeln('- $title')
            ..writeln('  $url');
        }
      }
      progressBuffer.write('detail: $detail');
      context.onBashUpdate?.call(
        BashToolExecutionUpdate(
          phase: BashToolExecutionPhase.running,
          command: command,
          workingDirectory: workingDirectory,
          stdout: progressBuffer.toString().trimRight(),
          stderr: '',
          durationMs: startedAt.elapsedMilliseconds,
        ),
      );
    }

    Map<String, Object?> webSearchMetadata({int? resultCount}) {
      final metadata = <String, Object?>{
        'websearch_query': query,
        'websearch_allowed_domains': allowedDomains,
        'websearch_blocked_domains': blockedDomains,
      };
      if (resultCount != null) metadata['websearch_result_count'] = resultCount;
      return metadata;
    }

    AiToolExecutionResult timedOutResult(String message) => AiToolExecutionResult(
          status: BashToolExecutionStatus.timedOut,
          command: command,
          workingDirectory: workingDirectory,
          stdout: progressBuffer.toString().trimRight(),
          stderr: message,
          durationMs: startedAt.elapsedMilliseconds,
          resultText: 'status: timed_out\nerror: $message',
          metadata: webSearchMetadata(),
        );

    AiToolExecutionResult failedResult(String message) => AiToolExecutionResult(
          status: BashToolExecutionStatus.failed,
          command: command,
          workingDirectory: workingDirectory,
          stdout: progressBuffer.toString().trimRight(),
          stderr: message,
          durationMs: startedAt.elapsedMilliseconds,
          resultText: 'status: failed\nerror: $message',
          metadata: webSearchMetadata(),
        );

    emitProgress(stage: 'searching', detail: 'Requesting DuckDuckGo HTML search results.');
    final uri = Uri.https('duckduckgo.com', '/html/', <String, String>{'q': query});
    late final http.Response response;
    try {
      response = await _httpClient.get(uri).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      return timedOutResult('WebSearch timed out while retrieving search results.');
    } catch (error) {
      final errorMessage = '$error';
      return AiToolUtils.looksLikeTimeoutMessage(errorMessage)
          ? timedOutResult('WebSearch timed out while retrieving search results.')
          : failedResult(errorMessage);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errorDetails =
          AiToolUtils.truncateContent(AiToolUtils.htmlToText(response.body).trim(), 400);
      return failedResult(errorDetails.isEmpty
          ? 'WebSearch failed with HTTP ${response.statusCode}.'
          : 'WebSearch failed with HTTP ${response.statusCode}: $errorDetails');
    }
    final html = response.body;
    if (response.statusCode == 202 || _looksLikeDdgChallenge(html)) {
      return failedResult(
          'WebSearch could not retrieve results because DuckDuckGo returned an anti-bot challenge page.');
    }
    final results = _parseDdgResults(html)
        .where((item) {
          final host = Uri.tryParse(item.url)?.host.toLowerCase() ?? '';
          if (allowedDomains.isNotEmpty &&
              !allowedDomains.any(
                  (d) => host == d || host.endsWith('.$d'))) {
            return false;
          }
          if (blockedDomains
              .any((d) => host == d || host.endsWith('.$d'))) {
            return false;
          }
          return true;
        })
        .take(8)
        .toList(growable: false);
    if (results.isEmpty) {
      emitProgress(stage: 'completed', detail: 'No search results matched the current filters.');
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.success,
        command: command,
        workingDirectory: workingDirectory,
        stdout: progressBuffer.toString().trimRight(),
        stderr: '',
        durationMs: startedAt.elapsedMilliseconds,
        resultText: 'No search results found.',
        metadata: webSearchMetadata(resultCount: 0),
      );
    }
    emitProgress(
        stage: 'summarizing',
        detail: 'Summarizing the retrieved search results.',
        previewResults: results);
    final rawResults =
        results.map((item) => '- ${item.title}\n  ${item.url}\n  ${item.snippet}').join('\n');
    late final AiChatCompletion completion;
    try {
      final maybeCompletion =
          await AiToolUtils.awaitWithCancellation<AiChatCompletion>(
        _backgroundChatClient.sendMessage(
          model: context.model,
          messages: <AiChatTurn>[
            const AiChatTurn(
                role: AiChatRole.system,
                content:
                    'Summarize the search results faithfully. Do not invent results that were not provided.'),
            AiChatTurn(
                role: AiChatRole.user,
                content: 'Query: $query\n\nResults:\n$rawResults'),
          ],
        ),
        cancelSignal: context.cancelSignal,
      );
      if (maybeCompletion == null) {
        return AiToolUtils.cancelledResult(
            command: command,
            durationMs: startedAt.elapsedMilliseconds,
            metadata: webSearchMetadata(resultCount: results.length));
      }
      completion = maybeCompletion;
    } on TimeoutException {
      return timedOutResult('WebSearch timed out while summarizing the retrieved results.');
    } on AiChatException catch (error) {
      final errorMessage = error.message.trim();
      return AiToolUtils.looksLikeTimeoutMessage(errorMessage)
          ? timedOutResult('WebSearch timed out while summarizing the retrieved results.')
          : failedResult(
              'WebSearch failed while summarizing the retrieved results: $errorMessage');
    } catch (error) {
      final errorMessage = '$error';
      return AiToolUtils.looksLikeTimeoutMessage(errorMessage)
          ? timedOutResult('WebSearch timed out while summarizing the retrieved results.')
          : failedResult(
              'WebSearch failed while summarizing the retrieved results: $errorMessage');
    }
    final output = completion.reply.trim().isEmpty ? rawResults : completion.reply.trim();
    emitProgress(stage: 'completed', detail: 'Search summary is ready.', previewResults: results);
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.success,
      command: command,
      workingDirectory: workingDirectory,
      stdout: progressBuffer.toString().trimRight(),
      stderr: '',
      durationMs: startedAt.elapsedMilliseconds,
      resultText: output,
      metadata: webSearchMetadata(resultCount: results.length),
    );
  }

  List<_SearchResult> _parseDdgResults(String html) {
    final matches = RegExp(
      r'<a[^>]*class="[^"]*result__a[^"]*"[^>]*href="([^"]+)"[^>]*>(.*?)</a>[\s\S]*?<a[^>]*class="[^"]*result__snippet[^"]*"[^>]*>(.*?)</a>',
      caseSensitive: false,
    ).allMatches(html);
    final results = <_SearchResult>[];
    for (final match in matches) {
      final url = _resolveUrl(match.group(1) ?? '');
      final title = AiToolUtils.htmlToText(match.group(2) ?? '');
      final snippet = AiToolUtils.htmlToText(match.group(3) ?? '');
      if (url.isEmpty || title.isEmpty) continue;
      results.add(_SearchResult(title: title, url: url, snippet: snippet));
    }
    return results;
  }

  String _resolveUrl(String rawUrl) {
    final normalizedUrl = AiToolUtils.htmlToText(rawUrl).trim();
    if (normalizedUrl.isEmpty) return '';
    final resolvedUrl = normalizedUrl.startsWith('//')
        ? 'https:$normalizedUrl'
        : normalizedUrl;
    final parsedUri = Uri.tryParse(resolvedUrl);
    if (parsedUri == null) return resolvedUrl;
    final isDdgRedirect = (parsedUri.host == 'duckduckgo.com' ||
            parsedUri.host == 'www.duckduckgo.com') &&
        parsedUri.path.startsWith('/l/');
    if (!isDdgRedirect) return parsedUri.toString();
    final redirectTarget = parsedUri.queryParameters['uddg']?.trim() ?? '';
    if (redirectTarget.isEmpty) return parsedUri.toString();
    final normalizedRedirect =
        redirectTarget.startsWith('//') ? 'https:$redirectTarget' : redirectTarget;
    return Uri.tryParse(normalizedRedirect)?.toString() ?? normalizedRedirect;
  }

  bool _looksLikeDdgChallenge(String html) {
    final normalized = html.toLowerCase();
    return normalized.contains('challenge-form') ||
        normalized.contains('anomaly.js') ||
        normalized.contains('bot challenge') ||
        normalized.contains('unusual traffic');
  }
}

class _SearchResult {
  const _SearchResult({
    required this.title,
    required this.url,
    required this.snippet,
  });
  final String title;
  final String url;
  final String snippet;
}
