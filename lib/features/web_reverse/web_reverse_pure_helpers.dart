/// 纯函数辅助库——Web 逆向面板内部使用的小工具，独立成顶层公开 API
/// 以便 `test/` 直接覆盖（避免拖入 Flutter widget 依赖）。
library;

import 'dart:convert';

import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/text_clip.dart';

const String _vlqAlphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
const int _maxJwtNumericDateSeconds = 253402300799; // 9999-12-31T23:59:59Z.
const int kWebReverseMaxPageTargets = 256;
const int kWebReverseMaxPageTargetIdChars = 256;
const int kWebReverseMaxPageUrlChars = 16 * 1024;
const int kWebReverseMaxPageTitleChars = 512;
const int kWebReverseMaxServiceWorkers = 512;
const int kWebReverseMaxServiceWorkerStatusChars = 128;
const int kWebReverseMaxCacheStorageNames = 1024;
const int kWebReverseMaxCacheStorageNameChars = 4 * 1024;
const int kWebReverseMaxCookies = 4096;
const int kWebReverseMaxCookieNameChars = 4096;
const int kWebReverseMaxCookieValueChars = 256 * 1024;
const int kWebReverseMaxCookieDomainChars = 1024;
const int kWebReverseMaxCookiePathChars = 4 * 1024;
const int kWebReverseMaxCookieCollectionChars = 4 * 1024 * 1024;
const int kWebReverseMaxDomStorageEntries = 4096;
const int kWebReverseMaxStorageKeyChars = 16 * 1024;
const int kWebReverseMaxStorageValueChars = 256 * 1024;
const int kWebReverseMaxStorageCollectionChars = 8 * 1024 * 1024;
const int kWebReverseMaxIndexedDbNames = 256;
const int kWebReverseMaxIndexedDbStores = 512;
const int kWebReverseMaxIndexedDbNameChars = 4 * 1024;
const int kWebReverseDefaultIndexedDbPageSize = 50;
const int kWebReverseMaxIndexedDbPageSize = 200;
const int kWebReverseMaxIndexedDbRetainedEntries = 200;
const int kWebReverseMaxIndexedDbRemoteTextChars = 16 * 1024;
final RegExp _consoleIsoTimestampPattern = RegExp(
  r'\b\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[^\s]*',
);
final RegExp _consoleHexPattern = RegExp(r'\b0x[0-9a-fA-F]+\b');
final RegExp _consoleLongNumberPattern = RegExp(r'\b\d{3,}\b');
final RegExp _consolePathHashPattern = RegExp(r'/[A-Fa-f0-9]{8,}');
final RegExp _consoleLocationTailPattern = RegExp(r':\d+:\d+\)');
final RegExp _consoleWhitespacePattern = RegExp(r'\s+');

typedef WebReversePageTargetData = ({String id, String url, String title});

String _boundedWebReverseText(
  Object? value,
  int maxChars, {
  bool trim = false,
}) {
  if (value == null) return '';
  final text = trim ? '$value'.trim() : '$value';
  return clipText(text, maxChars, suffix: '');
}

String _validatedWebReverseId(Object? value, int maxChars, {bool trim = true}) {
  if (value is! String) return '';
  final text = trim ? value.trim() : value;
  return text.isEmpty || text.length > maxChars ? '' : text;
}

void _validatePositiveWebReverseLimits(Iterable<int> limits) {
  if (limits.any((limit) => limit <= 0)) {
    throw ArgumentError('Web reverse collection limits must be positive.');
  }
}

/// Normalizes untrusted `Target.getTargets` payloads into the compact shape
/// consumed by the browser tab strip. Duplicate IDs are ignored and retained
/// strings and entries are bounded. If [preferredId] appears after the normal
/// capacity is reached, it replaces the first non-preferred entry so the
/// currently attached target remains visible.
List<WebReversePageTargetData> normalizeWebReversePageTargets(
  Object? rawInfos, {
  String? preferredId,
  int maxEntries = kWebReverseMaxPageTargets,
  int maxIdChars = kWebReverseMaxPageTargetIdChars,
  int maxUrlChars = kWebReverseMaxPageUrlChars,
  int maxTitleChars = kWebReverseMaxPageTitleChars,
}) {
  _validatePositiveWebReverseLimits([
    maxEntries,
    maxIdChars,
    maxUrlChars,
    maxTitleChars,
  ]);
  if (rawInfos is! Iterable) return const <WebReversePageTargetData>[];
  final preferred = _validatedWebReverseId(preferredId, maxIdChars);
  final result = <WebReversePageTargetData>[];
  final seen = <String>{};
  var inspected = 0;
  for (final raw in rawInfos) {
    if (inspected++ >= maxEntries * 4) break;
    if (raw is! Map || raw['type'] != 'page') continue;
    final id = _validatedWebReverseId(raw['targetId'], maxIdChars);
    if (id.isEmpty || seen.contains(id)) continue;
    final target = (
      id: id,
      url: _boundedWebReverseText(raw['url'], maxUrlChars),
      title: _boundedWebReverseText(raw['title'], maxTitleChars),
    );
    if (result.length < maxEntries) {
      result.add(target);
      seen.add(id);
      continue;
    }
    if (preferred.isEmpty || id != preferred || seen.contains(preferred)) {
      continue;
    }
    final replaceAt = result.indexWhere((entry) => entry.id != preferred);
    if (replaceAt < 0) continue;
    seen.remove(result[replaceAt].id);
    result[replaceAt] = target;
    seen.add(id);
  }
  return List<WebReversePageTargetData>.unmodifiable(result);
}

/// Keeps only Service Worker fields used by the UI, joins registration scopes,
/// deduplicates version updates and bounds all retained strings and entries.
List<Map<String, Object?>> compactWebReverseServiceWorkers(
  Object? rawVersions, {
  Object? rawRegistrations,
  int maxEntries = kWebReverseMaxServiceWorkers,
  int maxIdChars = kWebReverseMaxPageTargetIdChars,
  int maxUrlChars = kWebReverseMaxPageUrlChars,
  int maxStatusChars = kWebReverseMaxServiceWorkerStatusChars,
}) {
  _validatePositiveWebReverseLimits([
    maxEntries,
    maxIdChars,
    maxUrlChars,
    maxStatusChars,
  ]);
  final scopeByRegistrationId = <String, String>{};
  if (rawRegistrations is Iterable) {
    var inspected = 0;
    for (final raw in rawRegistrations) {
      if (inspected++ >= maxEntries * 4) break;
      if (raw is! Map) continue;
      final id = _validatedWebReverseId(raw['registrationId'], maxIdChars);
      if (id.isEmpty) continue;
      if (raw['isDeleted'] == true) {
        scopeByRegistrationId.remove(id);
        continue;
      }
      if (!scopeByRegistrationId.containsKey(id) &&
          scopeByRegistrationId.length >= maxEntries) {
        continue;
      }
      scopeByRegistrationId[id] = _boundedWebReverseText(
        raw['scopeURL'],
        maxUrlChars,
      );
    }
  }
  if (rawVersions is! Iterable) return const <Map<String, Object?>>[];

  final result = <Map<String, Object?>>[];
  final indexByVersionId = <String, int>{};
  var inspected = 0;
  for (final raw in rawVersions) {
    if (inspected++ >= maxEntries * 4) break;
    if (raw is! Map) continue;
    final versionId = _validatedWebReverseId(raw['versionId'], maxIdChars);
    final registrationId = _validatedWebReverseId(
      raw['registrationId'],
      maxIdChars,
    );
    final scriptUrl = _boundedWebReverseText(raw['scriptURL'], maxUrlChars);
    final runningStatus = _boundedWebReverseText(
      raw['runningStatus'],
      maxStatusChars,
    );
    final status = _boundedWebReverseText(raw['status'], maxStatusChars);
    final directScope = _boundedWebReverseText(raw['scopeURL'], maxUrlChars);
    final scopeUrl = directScope.isNotEmpty
        ? directScope
        : scopeByRegistrationId[registrationId] ?? '';
    if (versionId.isEmpty &&
        registrationId.isEmpty &&
        scriptUrl.isEmpty &&
        scopeUrl.isEmpty) {
      continue;
    }
    final compact = <String, Object?>{
      if (versionId.isNotEmpty) 'versionId': versionId,
      if (registrationId.isNotEmpty) 'registrationId': registrationId,
      if (scriptUrl.isNotEmpty) 'scriptURL': scriptUrl,
      if (runningStatus.isNotEmpty) 'runningStatus': runningStatus,
      if (status.isNotEmpty) 'status': status,
      if (scopeUrl.isNotEmpty) 'scopeURL': scopeUrl,
    };
    final existingIndex = versionId.isEmpty
        ? null
        : indexByVersionId[versionId];
    if (existingIndex != null) {
      result[existingIndex] = compact;
      continue;
    }
    if (result.length >= maxEntries) continue;
    if (versionId.isNotEmpty) indexByVersionId[versionId] = result.length;
    result.add(compact);
  }
  return List<Map<String, Object?>>.unmodifiable(result);
}

/// Extracts and deduplicates Cache Storage names without retaining arbitrary
/// fields from the CDP response.
List<String> normalizeWebReverseCacheStorageNames(
  Object? rawCaches, {
  int maxEntries = kWebReverseMaxCacheStorageNames,
  int maxNameChars = kWebReverseMaxCacheStorageNameChars,
}) {
  _validatePositiveWebReverseLimits([maxEntries, maxNameChars]);
  if (rawCaches is! Iterable) return const <String>[];
  final names = <String>[];
  final seen = <String>{};
  var inspected = 0;
  for (final raw in rawCaches) {
    if (inspected++ >= maxEntries * 4) break;
    if (raw is! Map) continue;
    final name = _boundedWebReverseText(raw['cacheName'], maxNameChars);
    if (name.isEmpty || !seen.add(name)) continue;
    names.add(name);
    if (names.length >= maxEntries) break;
  }
  return List<String>.unmodifiable(names);
}

/// Reads the persisted browser tab metadata in order while bounding IDs, URLs
/// and the number of tabs restored after a browser restart.
List<String> normalizeWebReverseTabRestoreUrls(
  Object? rawOrder,
  Object? rawUrls, {
  int maxEntries = kWebReverseMaxPageTargets,
  int maxIdChars = kWebReverseMaxPageTargetIdChars,
  int maxUrlChars = kWebReverseMaxPageUrlChars,
}) {
  _validatePositiveWebReverseLimits([maxEntries, maxIdChars, maxUrlChars]);
  if (rawOrder is! Iterable || rawUrls is! Map) return const <String>[];
  final urls = <String>[];
  final seenIds = <String>{};
  var inspected = 0;
  for (final rawId in rawOrder) {
    if (inspected++ >= maxEntries * 4) break;
    final id = _validatedWebReverseId(rawId, maxIdChars);
    if (id.isEmpty || !seenIds.add(id) || !rawUrls.containsKey(id)) continue;
    final url = _boundedWebReverseText(rawUrls[id], maxUrlChars, trim: true);
    if (url.isEmpty || url.startsWith('about:')) continue;
    urls.add(url);
    if (urls.length >= maxEntries) break;
  }
  return List<String>.unmodifiable(urls);
}

/// Retains only the cookie fields used by the application surfaces and
/// account snapshots. Identity fields are rejected rather than clipped so a
/// subsequent edit/delete command cannot target a different cookie.
List<Map<String, Object?>> compactWebReverseCookies(
  Object? rawCookies, {
  int maxEntries = kWebReverseMaxCookies,
  int maxNameChars = kWebReverseMaxCookieNameChars,
  int maxValueChars = kWebReverseMaxCookieValueChars,
  int maxDomainChars = kWebReverseMaxCookieDomainChars,
  int maxPathChars = kWebReverseMaxCookiePathChars,
  int maxTotalChars = kWebReverseMaxCookieCollectionChars,
}) {
  _validatePositiveWebReverseLimits([
    maxEntries,
    maxNameChars,
    maxValueChars,
    maxDomainChars,
    maxPathChars,
    maxTotalChars,
  ]);
  if (rawCookies is! Iterable) return const <Map<String, Object?>>[];
  final result = <Map<String, Object?>>[];
  var retainedChars = 0;
  var inspected = 0;
  for (final raw in rawCookies) {
    if (inspected++ >= maxEntries * 4 || result.length >= maxEntries) break;
    if (raw is! Map) continue;
    final name = _validatedWebReverseId(raw['name'], maxNameChars, trim: false);
    if (name.isEmpty) continue;
    if (raw['value'] != null && raw['value'] is! String) continue;
    if (raw['domain'] is! String || raw['path'] is! String) continue;
    final domain = _validatedWebReverseId(
      raw['domain'],
      maxDomainChars,
      trim: false,
    );
    final path = _validatedWebReverseId(raw['path'], maxPathChars, trim: false);
    if (domain.isEmpty || path.isEmpty) continue;
    final value = _boundedWebReverseText(raw['value'], maxValueChars);
    final sameSite = raw['sameSite'] is String
        ? _boundedWebReverseText(raw['sameSite'], 16)
        : '';
    final priority = raw['priority'] is String
        ? _boundedWebReverseText(raw['priority'], 16)
        : '';
    final sourceScheme = raw['sourceScheme'] is String
        ? _boundedWebReverseText(raw['sourceScheme'], 16)
        : '';
    final partitionKey = _compactWebReverseCookiePartitionKey(
      raw['partitionKey'],
      maxUrlChars: kWebReverseMaxPageUrlChars,
    );
    if (raw['partitionKey'] != null && partitionKey == null) continue;
    final cookie = <String, Object?>{
      'name': name,
      'value': value,
      if (domain.isNotEmpty) 'domain': domain,
      if (path.isNotEmpty) 'path': path,
      if (raw['expires'] is num && (raw['expires'] as num).isFinite)
        'expires': raw['expires'],
      if (raw['size'] is num && (raw['size'] as num).isFinite)
        'size': raw['size'],
      'httpOnly': raw['httpOnly'] == true,
      'secure': raw['secure'] == true,
      'session': raw['session'] == true,
      if (const <String>{'Strict', 'Lax', 'None'}.contains(sameSite))
        'sameSite': sameSite,
      if (priority.isNotEmpty) 'priority': priority,
      if (raw['sameParty'] == true) 'sameParty': true,
      if (sourceScheme.isNotEmpty) 'sourceScheme': sourceScheme,
      if (raw['sourcePort'] is int) 'sourcePort': raw['sourcePort'],
      if (partitionKey != null) 'partitionKey': partitionKey,
      if (raw['partitionKeyOpaque'] == true) 'partitionKeyOpaque': true,
    };
    final cost =
        name.length +
        value.length +
        domain.length +
        path.length +
        sameSite.length +
        priority.length +
        sourceScheme.length +
        (partitionKey?['topLevelSite'] as String? ?? '').length;
    if (retainedChars + cost > maxTotalChars) break;
    retainedChars += cost;
    result.add(Map<String, Object?>.unmodifiable(cookie));
  }
  return List<Map<String, Object?>>.unmodifiable(result);
}

Map<String, Object?>? _compactWebReverseCookiePartitionKey(
  Object? raw, {
  required int maxUrlChars,
}) {
  if (raw == null) return null;
  if (raw is! Map || raw['topLevelSite'] is! String) return null;
  final topLevelSite = (raw['topLevelSite'] as String).trim();
  if (topLevelSite.isEmpty || topLevelSite.length > maxUrlChars) return null;
  return Map<String, Object?>.unmodifiable(<String, Object?>{
    'topLevelSite': topLevelSite,
    'hasCrossSiteAncestor': raw['hasCrossSiteAncestor'] == true,
  });
}

List<({String key, String value})> normalizeWebReverseDomStorageEntries(
  Object? rawEntries, {
  int maxEntries = kWebReverseMaxDomStorageEntries,
  int maxKeyChars = kWebReverseMaxStorageKeyChars,
  int maxValueChars = kWebReverseMaxStorageValueChars,
  int maxTotalChars = kWebReverseMaxStorageCollectionChars,
}) {
  _validatePositiveWebReverseLimits([
    maxEntries,
    maxKeyChars,
    maxValueChars,
    maxTotalChars,
  ]);
  if (rawEntries is! Iterable) {
    return const <({String key, String value})>[];
  }
  final result = <({String key, String value})>[];
  var retainedChars = 0;
  var inspected = 0;
  for (final raw in rawEntries) {
    if (inspected++ >= maxEntries * 4 || result.length >= maxEntries) break;
    if (raw is! List || raw.length < 2 || raw[0] is! String) continue;
    if (raw[1] != null && raw[1] is! String) continue;
    final key = raw[0] as String;
    if (key.length > maxKeyChars) continue;
    final value = _boundedWebReverseText(raw[1], maxValueChars);
    final cost = key.length + value.length;
    if (retainedChars + cost > maxTotalChars) break;
    retainedChars += cost;
    result.add((key: key, value: value));
  }
  return List<({String key, String value})>.unmodifiable(result);
}

List<String> normalizeWebReverseIndexedDbNames(
  Object? rawNames, {
  int maxEntries = kWebReverseMaxIndexedDbNames,
  int maxNameChars = kWebReverseMaxIndexedDbNameChars,
}) => _normalizeWebReverseIdentityStrings(
  rawNames,
  maxEntries: maxEntries,
  maxChars: maxNameChars,
  allowEmpty: true,
  trim: false,
);

List<String> normalizeWebReverseIndexedDbStoreNames(
  Object? rawStores, {
  int maxEntries = kWebReverseMaxIndexedDbStores,
  int maxNameChars = kWebReverseMaxIndexedDbNameChars,
}) {
  if (rawStores is! Iterable) return const <String>[];
  final names = <Object?>[];
  var inspected = 0;
  for (final raw in rawStores) {
    if (inspected++ >= maxEntries * 4) break;
    names.add(raw is Map ? raw['name'] : null);
  }
  return _normalizeWebReverseIdentityStrings(
    names,
    maxEntries: maxEntries,
    maxChars: maxNameChars,
    allowEmpty: true,
    trim: false,
  );
}

List<String> _normalizeWebReverseIdentityStrings(
  Object? rawValues, {
  required int maxEntries,
  required int maxChars,
  bool allowEmpty = false,
  bool trim = true,
}) {
  _validatePositiveWebReverseLimits([maxEntries, maxChars]);
  if (rawValues is! Iterable) return const <String>[];
  final result = <String>[];
  final seen = <String>{};
  var inspected = 0;
  for (final raw in rawValues) {
    if (inspected++ >= maxEntries * 4 || result.length >= maxEntries) break;
    if (raw is! String) continue;
    final value = trim ? raw.trim() : raw;
    if (value.length > maxChars || (!allowEmpty && value.isEmpty)) continue;
    if (seen.add(value)) result.add(value);
  }
  return List<String>.unmodifiable(result);
}

Map<String, Object?>? _compactIndexedDbRemoteObject(
  Object? raw, {
  required int maxTextChars,
  required bool identity,
}) {
  if (raw is! Map) return null;
  if (raw['type'] is! String) return null;
  final type = _boundedWebReverseText(raw['type'], 32);
  if (type.isEmpty) return null;
  final value = raw['value'];
  if (identity && value is String && value.length > maxTextChars) return null;
  final compact = <String, Object?>{
    'type': type,
    if (raw['subtype'] is String)
      'subtype': _boundedWebReverseText(raw['subtype'], 32),
    if (raw['className'] is String)
      'className': _boundedWebReverseText(raw['className'], 256),
    if (value is String)
      'value': _boundedWebReverseText(value, maxTextChars)
    else if (value is num || value is bool || value == null)
      'value': value,
    if (raw['unserializableValue'] is String)
      'unserializableValue': _boundedWebReverseText(
        raw['unserializableValue'],
        512,
      ),
    if (raw['description'] is String)
      'description': _boundedWebReverseText(raw['description'], maxTextChars),
  };
  return Map<String, Object?>.unmodifiable(compact);
}

/// Compacts IndexedDB data entries to the three RemoteObjects consumed by the
/// UI. Protocol previews/object IDs and arbitrary nested extension fields are
/// discarded so pagination cannot retain complete remote object graphs.
List<Map<String, Object?>> compactWebReverseIndexedDbEntries(
  Object? rawEntries, {
  int maxEntries = kWebReverseMaxIndexedDbPageSize,
  int maxTextChars = kWebReverseMaxIndexedDbRemoteTextChars,
}) {
  _validatePositiveWebReverseLimits([maxEntries, maxTextChars]);
  if (rawEntries is! Iterable) return const <Map<String, Object?>>[];
  final result = <Map<String, Object?>>[];
  var inspected = 0;
  for (final raw in rawEntries) {
    if (inspected++ >= maxEntries * 4 || result.length >= maxEntries) break;
    if (raw is! Map) continue;
    final key = _compactIndexedDbRemoteObject(
      raw['key'],
      maxTextChars: maxTextChars,
      identity: true,
    );
    if (key == null) continue;
    final primaryKey = _compactIndexedDbRemoteObject(
      raw['primaryKey'],
      maxTextChars: maxTextChars,
      identity: true,
    );
    final value = _compactIndexedDbRemoteObject(
      raw['value'],
      maxTextChars: maxTextChars,
      identity: false,
    );
    result.add(
      Map<String, Object?>.unmodifiable(<String, Object?>{
        'key': key,
        if (primaryKey != null) 'primaryKey': primaryKey,
        if (value != null) 'value': value,
      }),
    );
  }
  return List<Map<String, Object?>>.unmodifiable(result);
}

class _SamplingStackPath {
  const _SamplingStackPath(this.entry, this.parent);

  final String entry;
  final _SamplingStackPath? parent;

  List<String> materialize() {
    final reversed = <String>[];
    _SamplingStackPath? current = this;
    while (current != null) {
      reversed.add(current.entry);
      current = current.parent;
    }
    return reversed.reversed.toList(growable: false);
  }
}

/// Iteratively summarizes a V8 SamplingHeapProfile head node.
///
/// Traversal, retained stack depth, aggregate buckets and frame text are all
/// bounded so a malformed or unusually deep profile cannot overflow the Dart
/// stack or retain an unbounded call tree.
({int totalSize, List<({String label, int size, List<String> stack})> top})?
summarizeSamplingHeapProfile(
  Object? rawHead, {
  int maxNodes = 100000,
  int maxStackDepth = 256,
  int maxFunctionBuckets = 20000,
  int maxTopEntries = 15,
  int maxFunctionNameChars = 512,
  int maxUrlChars = 16 * 1024,
}) {
  if (maxNodes <= 0 ||
      maxStackDepth <= 0 ||
      maxFunctionBuckets <= 0 ||
      maxTopEntries <= 0 ||
      maxFunctionNameChars <= 0 ||
      maxUrlChars <= 0) {
    throw ArgumentError('Sampling profile limits must be positive.');
  }
  final head = stringKeyedMapFromValue(rawHead);
  if (head.isEmpty) return null;
  final work =
      <({Map<String, Object?> node, _SamplingStackPath? parent, int depth})>[
        (node: head, parent: null, depth: 0),
      ];
  final tally = <String, ({int size, _SamplingStackPath path})>{};
  const overflowBucket = '(other)';
  var visited = 0;
  var total = 0;

  while (work.isNotEmpty && visited < maxNodes) {
    final current = work.removeLast();
    visited++;
    final callFrame = stringKeyedMapFromValue(current.node['callFrame']);
    final functionName = clipText(
      '${callFrame['functionName'] ?? '(anonymous)'}',
      maxFunctionNameChars,
      suffix: '',
    );
    final url = clipText('${callFrame['url'] ?? ''}', maxUrlChars, suffix: '');
    final line = intFromValue(callFrame['lineNumber'], fallback: 0);
    final column = intFromValue(callFrame['columnNumber'], fallback: 0);
    final frame = url.isEmpty
        ? (functionName.isEmpty ? '(anonymous)' : functionName)
        : '${functionName.isEmpty ? "(anonymous)" : functionName} @ $url:${line + 1}:${column + 1}';
    final path = current.depth < maxStackDepth
        ? _SamplingStackPath(frame, current.parent)
        : current.parent ?? const _SamplingStackPath('[stack truncated]', null);
    final selfSize = nonNegativeIntFromValue(
      current.node['selfSize'],
      fallback: 0,
    );
    total += selfSize;
    final rawBucket = functionName.isEmpty ? '(anonymous)' : functionName;
    final bucket =
        tally.containsKey(rawBucket) || tally.length < maxFunctionBuckets - 1
        ? rawBucket
        : overflowBucket;
    final previous = tally[bucket];
    tally[bucket] = (
      size: (previous?.size ?? 0) + selfSize,
      path: previous?.path ?? path,
    );

    final children = current.node['children'];
    if (children is! List) continue;
    var remainingSlots = maxNodes - visited - work.length;
    for (
      var index = children.length - 1;
      index >= 0 && remainingSlots > 0;
      index--
    ) {
      final child = children[index];
      if (child is! Map) continue;
      work.add((
        node: stringKeyedMapFromValue(child),
        parent: path,
        depth: current.depth + 1,
      ));
      remainingSlots--;
    }
  }

  final entries = tally.entries.toList()
    ..sort((left, right) => right.value.size.compareTo(left.value.size));
  final top = entries
      .take(maxTopEntries)
      .map(
        (entry) => (
          label: entry.key,
          size: entry.value.size,
          stack: entry.value.path.materialize(),
        ),
      )
      .toList(growable: false);
  return (totalSize: total, top: top);
}

/// 解码 source-map 中的 Base64 VLQ 段（不含 `,` 与 `;` 分隔符），
/// 返回该段内全部带符号整数。空串返回空列表，未知字符直接跳过。
List<int> vlqDecode(String s) {
  final result = <int>[];
  var value = 0;
  var shift = 0;
  for (final ch in s.codeUnits) {
    final digit = _vlqAlphabet.indexOf(String.fromCharCode(ch));
    if (digit < 0) continue;
    final cont = (digit & 32) != 0;
    final data = digit & 31;
    value |= data << shift;
    if (cont) {
      shift += 5;
    } else {
      final neg = (value & 1) != 0;
      var v = value >> 1;
      if (neg) v = -v;
      result.add(v);
      value = 0;
      shift = 0;
    }
  }
  return result;
}

/// 把 console 文本归一化为聚类签名：取首行，并把 ISO 时间戳、十六进制、
/// 长数字、URL 路径中的哈希摘要、行列尾 `:L:C)` 替换为占位符，
/// 再压缩连续空白。
String normalizeConsoleSignature(String text) {
  final firstLine = text.split('\n').first.trim();
  return firstLine
      .replaceAll(_consoleIsoTimestampPattern, '<ts>')
      .replaceAll(_consoleHexPattern, '<hex>')
      .replaceAll(_consoleLongNumberPattern, '<num>')
      .replaceAll(_consolePathHashPattern, '/<hash>')
      .replaceAll(_consoleLocationTailPattern, ':L:C)')
      .replaceAll(_consoleWhitespacePattern, ' ');
}

Object? cdpResultValue(Object? response) {
  if (response is! Map) return null;
  if (response['error'] != null) return null;
  final result = response['result'];
  if (result is! Map) return null;
  return result['value'];
}

String? cdpStringResultValue(Object? response) {
  final value = cdpResultValue(response);
  return value is String ? value : null;
}

Map<String, Object?>? decodeStringKeyedJsonMap(String raw) {
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map ? stringKeyedMapFromValue(decoded) : null;
  } catch (_) {
    return null;
  }
}

List<Object?>? decodeJsonList(String raw) {
  try {
    final decoded = jsonDecode(raw);
    return decoded is List ? List<Object?>.of(decoded, growable: false) : null;
  } catch (_) {
    return null;
  }
}

List<Map<String, Object?>>? decodeStringKeyedJsonMapList(String raw) {
  final decoded = decodeJsonList(raw);
  return decoded == null ? null : stringKeyedMapListFromValue(decoded);
}

DateTime? jwtNumericDateFromValue(Object? value) {
  final seconds = optionalIntegralIntFromValue(value);
  if (seconds == null || seconds < 0 || seconds > _maxJwtNumericDateSeconds) {
    return null;
  }
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
}

Map<String, Object?>? cdpJsonMapStringResultValue(Object? response) {
  final raw = cdpStringResultValue(response);
  return raw == null ? null : decodeStringKeyedJsonMap(raw);
}
