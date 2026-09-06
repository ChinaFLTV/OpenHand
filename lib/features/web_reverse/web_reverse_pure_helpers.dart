/// Web 逆向面板共用的纯函数与数据边界处理。
library;

import 'dart:collection';
import 'dart:convert';

import 'package:openhand/shared/util/byte_size_format.dart';
import 'package:openhand/shared/util/text_normalization.dart';

import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/text_clip.dart';

const String _vlqAlphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
const int _maxJwtNumericDateSeconds = 253402300799; // 9999-12-31T23:59:59Z.
const int kWebReverseMaxPageTargets = 256;
const int kWebReverseMaxPageTargetIdChars = 256;
const int kWebReverseMaxPageUrlChars = 16 * kBytesPerKiB;
const int kWebReverseMaxPageTitleChars = 512;
const int kWebReverseMaxServiceWorkers = 512;
const int kWebReverseMaxServiceWorkerStatusChars = 128;
const int kWebReverseMaxCacheStorageNames = 1024;
const int kWebReverseMaxCacheStorageNameChars = 4 * kBytesPerKiB;
const int kWebReverseMaxCookies = 4 * kBytesPerKiB;
const int kWebReverseMaxCookieNameChars = 4 * kBytesPerKiB;
const int kWebReverseMaxCookieValueChars = 256 * kBytesPerKiB;
const int kWebReverseMaxCookieDomainChars = kBytesPerKiB;
const int kWebReverseMaxCookiePathChars = 4 * kBytesPerKiB;
const int kWebReverseMaxCookieCollectionChars = 4 * kBytesPerMiB;
const int kWebReverseMaxDomStorageEntries = 4 * kBytesPerKiB;
const int kWebReverseMaxStorageKeyChars = 16 * kBytesPerKiB;
const int kWebReverseMaxStorageValueChars = 256 * kBytesPerKiB;
const int kWebReverseMaxStorageCollectionChars = 8 * kBytesPerMiB;
const int kWebReverseMaxIndexedDbNames = 256;
const int kWebReverseMaxIndexedDbStores = 512;
const int kWebReverseMaxIndexedDbNameChars = 4 * kBytesPerKiB;
const int kWebReverseDefaultIndexedDbPageSize = 50;
const int kWebReverseMaxIndexedDbPageSize = 200;
const int kWebReverseMaxIndexedDbRetainedEntries = 200;
const int kWebReverseMaxIndexedDbRemoteTextChars = 16 * kBytesPerKiB;
const int kWebReverseMaxDomNodes = 4 * kBytesPerKiB;
const int kWebReverseMaxDomChildren = 512;
const int kWebReverseMaxDomDepth = 4;
const int kWebReverseMaxDomFieldChars = 16 * kBytesPerKiB;
const int kWebReverseMaxDomAttributes = 512;
const int kWebReverseMaxPerformanceMetrics = 256;
const int kWebReverseMaxPerformanceMetricNameChars = 128;
const int kWebReverseMaxComputedStyles = 512;
const int kWebReverseMaxComputedStyleNameChars = 256;
const int kWebReverseMaxComputedStyleValueChars = 16 * kBytesPerKiB;
const int kWebReverseMaxDomEventListeners = 512;
const int kWebReverseMaxRuntimeProperties = 512;
const int kWebReverseMaxWebRtcEvents = 800;
const int kWebReverseMaxWebRtcEventChars = 64 * kBytesPerKiB;
const int kWebReverseMaxWebRtcLogChars = 4 * kBytesPerMiB;
const int kWebReverseMaxWebRtcConnections = 128;
const int kWebReverseMaxLongTasks = 200;
const int kWebReverseMaxLongTaskAttributionChars = kBytesPerKiB;
const int kWebReverseMaxTraceEventChars = 256 * kBytesPerKiB;
const int kWebReverseMaxTraceEventFields = 128;
const int kWebReverseMaxScriptResourceFrames = 256;
const int kWebReverseMaxScriptResourceUrlChars = 16 * kBytesPerKiB;
const int kWebReverseMaxInspectedScriptResources = 4 * kBytesPerKiB;

// ── CDP 字段级字符上限 ──────────────────────────────────────────────────────
// 这些值对应 CDP 响应中单个字段的合理最大长度，统一命名以便检索与调整。
const int kWebReverseMaxCookieEnumFieldChars = 16;
const int kWebReverseMaxRemoteObjectTypeChars = 32;
const int kWebReverseMaxRemoteObjectSubtypeChars = 32;
const int kWebReverseMaxRemoteObjectClassNameChars = 256;
const int kWebReverseMaxRemoteObjectIdChars = kBytesPerKiB;
const int kWebReverseMaxRemoteObjectUnserializableChars = 512;
const int kWebReverseMaxRuntimePropertyNameChars = kBytesPerKiB;
const int kWebReverseMaxDomEventListenerTypeChars = 256;
const int kWebReverseMaxWebRtcEventKindChars = 128;
const int kWebReverseMaxJsonKeyChars = 256;
const int kWebReverseMaxJsonValueFallbackChars = 256;
const int kWebReverseMaxJsonCollectionItems = 64;
const int kWebReverseMaxJsonDepth = 4;
final RegExp _consoleIsoTimestampPattern = RegExp(
  r'\b\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[^\s]*',
);
final RegExp _consoleHexPattern = RegExp(r'\b0x[0-9a-fA-F]+\b');
final RegExp _consoleLongNumberPattern = RegExp(r'\b\d{3,}\b');
final RegExp _consolePathHashPattern = RegExp('/[A-Fa-f0-9]{8,}');
final RegExp _consoleLocationTailPattern = RegExp(r':\d+:\d+\)');

typedef WebReversePageTargetData = ({String id, String url, String title});
typedef WebReverseScriptResource = ({String frameId, String url});

/// 有界收集资源树中的脚本，统一限制帧、资源、URL 和重复项。
List<WebReverseScriptResource> collectWebReverseScriptResources(
  Object? rawTree, {
  required int maxEntries,
  int maxFrames = kWebReverseMaxScriptResourceFrames,
  int maxInspectedResources = kWebReverseMaxInspectedScriptResources,
}) {
  _validatePositiveWebReverseLimits([
    maxEntries,
    maxFrames,
    maxInspectedResources,
  ]);
  if (rawTree is! Map) return const <WebReverseScriptResource>[];
  final queue = ListQueue<Object?>()..add(rawTree);
  final result = <WebReverseScriptResource>[];
  final seen = <(String, String)>{};
  var inspectedFrames = 0;
  var inspectedResources = 0;
  while (queue.isNotEmpty &&
      result.length < maxEntries &&
      inspectedFrames < maxFrames) {
    final node = queue.removeFirst();
    if (node is! Map) continue;
    inspectedFrames++;
    final frame = node['frame'];
    final frameId = frame is Map ? frame['id'] : null;
    final resources = node['resources'];
    if (frameId is String &&
        frameId.isNotEmpty &&
        frameId.length <= kWebReverseMaxPageTargetIdChars &&
        resources is Iterable) {
      for (final resource in resources) {
        if (inspectedResources++ >= maxInspectedResources ||
            result.length >= maxEntries) {
          break;
        }
        if (resource is! Map ||
            resource['type']?.toString().toLowerCase() != 'script') {
          continue;
        }
        final url = resource['url'];
        if (url is! String ||
            url.isEmpty ||
            url.length > kWebReverseMaxScriptResourceUrlChars) {
          continue;
        }
        final key = (frameId, url);
        if (!seen.add(key)) continue;
        result.add((frameId: frameId, url: url));
      }
    }
    final children = node['childFrames'];
    if (children is Iterable && inspectedFrames < maxFrames) {
      for (final child in children) {
        if (inspectedFrames + queue.length >= maxFrames) break;
        if (child is Map) queue.addLast(child);
      }
    }
  }
  return List<WebReverseScriptResource>.unmodifiable(result);
}

String _boundedWebReverseText(
  Object? value,
  int maxChars, {
  bool trim = false,
}) {
  if (value == null) return '';
  final text = trim ? '$value'.trim() : '$value';
  return clipTextByCodeUnits(text, maxChars, suffix: '');
}

String _validatedWebReverseId(Object? value, int maxChars, {bool trim = true}) {
  if (value is! String) return '';
  final text = trim ? value.trim() : value;
  return text.isEmpty || text.length > maxChars ? '' : text;
}

void _validatePositiveWebReverseLimits(Iterable<int> limits) {
  if (limits.any((limit) => limit <= 0)) {
    throw ArgumentError('Web 逆向采集上限必须为正数。');
  }
}

/// 将不可信的 `Target.getTargets` 载荷归一化为浏览器标签栏需要的紧凑结构。
/// 忽略重复 ID，并限制保留的字符串与条目数量。若 [preferredId] 在达到常规容量后
/// 才出现，则替换首个非首选条目，确保当前附加目标仍然可见。
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

/// 仅保留界面使用的 Service Worker 字段，关联注册范围、合并重复版本更新，
/// 并限制所有字符串与条目数量。
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

/// 提取并去重 Cache Storage 名称，不保留 CDP 响应中的无关字段。
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

/// 按顺序读取持久化的浏览器标签元数据，并限制 ID、URL 及重启后恢复的标签数量。
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

/// 仅保留应用界面和账号快照使用的 Cookie 字段。身份字段超限时直接拒绝，
/// 不做截断，避免后续编辑或删除命令误操作其他 Cookie。
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
        ? _boundedWebReverseText(
            raw['sameSite'],
            kWebReverseMaxCookieEnumFieldChars,
          )
        : '';
    final priority = raw['priority'] is String
        ? _boundedWebReverseText(
            raw['priority'],
            kWebReverseMaxCookieEnumFieldChars,
          )
        : '';
    final sourceScheme = raw['sourceScheme'] is String
        ? _boundedWebReverseText(
            raw['sourceScheme'],
            kWebReverseMaxCookieEnumFieldChars,
          )
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
  final type = _boundedWebReverseText(
    raw['type'],
    kWebReverseMaxRemoteObjectTypeChars,
  );
  if (type.isEmpty) return null;
  final value = raw['value'];
  if (identity && value is String && value.length > maxTextChars) return null;
  final compact = <String, Object?>{
    'type': type,
    if (raw['subtype'] is String)
      'subtype': _boundedWebReverseText(
        raw['subtype'],
        kWebReverseMaxRemoteObjectSubtypeChars,
      ),
    if (raw['className'] is String)
      'className': _boundedWebReverseText(
        raw['className'],
        kWebReverseMaxRemoteObjectClassNameChars,
      ),
    if (value is String)
      'value': _boundedWebReverseText(value, maxTextChars)
    else if (value is num || value is bool || value == null)
      'value': value,
    if (raw['unserializableValue'] is String)
      'unserializableValue': _boundedWebReverseText(
        raw['unserializableValue'],
        kWebReverseMaxRemoteObjectUnserializableChars,
      ),
    if (raw['description'] is String)
      'description': _boundedWebReverseText(raw['description'], maxTextChars),
  };
  return Map<String, Object?>.unmodifiable(compact);
}

/// 将 IndexedDB 数据条目压缩为界面使用的三个 RemoteObject。丢弃协议预览、
/// 对象 ID 和任意嵌套扩展字段，避免分页保留完整远程对象图。
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

/// 压缩 CDP 返回的 DOM 节点树。DOM 响应可能包含完整页面、任意属性值和深层
/// 子节点列表；仅保留 Elements 面板渲染的字段，并限制深度、节点数和子节点数。
Map<String, dynamic>? compactWebReverseDomNode(
  Object? raw, {
  int maxDepth = kWebReverseMaxDomDepth,
  int maxNodes = kWebReverseMaxDomNodes,
  int maxChildren = kWebReverseMaxDomChildren,
  int maxFieldChars = kWebReverseMaxDomFieldChars,
  int maxAttributes = kWebReverseMaxDomAttributes,
}) {
  if (maxDepth < 0) throw ArgumentError.value(maxDepth, 'maxDepth');
  _validatePositiveWebReverseLimits([
    maxNodes,
    maxChildren,
    maxFieldChars,
    maxAttributes,
  ]);
  var remainingNodes = maxNodes;

  int? boundedInt(Object? value) {
    if (value is! num || !value.isFinite) return null;
    final integer = value.toInt();
    return integer < 0 ? null : integer;
  }

  String? boundedString(Object? value) {
    if (value is! String) return null;
    return _boundedWebReverseText(value, maxFieldChars);
  }

  Map<String, dynamic>? visit(Object? value, int depth) {
    if (remainingNodes <= 0 || value is! Map) return null;
    remainingNodes--;
    final out = <String, dynamic>{};
    for (final key in const <String>[
      'nodeId',
      'backendNodeId',
      'nodeType',
      'childNodeCount',
    ]) {
      final source = value[key];
      final integer = boundedInt(source);
      if (integer != null) out[key] = integer;
    }
    if (value['isSVG'] is bool) out['isSVG'] = value['isSVG'];
    for (final key in const <String>[
      'nodeName',
      'localName',
      'nodeValue',
      'documentURL',
      'baseURL',
      'publicId',
      'systemId',
      'internalSubset',
      'xmlVersion',
      'pseudoType',
      'shadowRootType',
      'frameId',
    ]) {
      final text = boundedString(value[key]);
      if (text != null && text.isNotEmpty) out[key] = text;
    }
    final rawAttributes = value['attributes'];
    if (rawAttributes is Iterable) {
      final attributes = <String>[];
      final candidates = rawAttributes.take(maxAttributes * 4).toList();
      for (
        var i = 0;
        i + 1 < candidates.length && attributes.length + 2 <= maxAttributes;
        i += 2
      ) {
        final name = boundedString(candidates[i]);
        final value = boundedString(candidates[i + 1]);
        if (name == null || value == null) continue;
        attributes
          ..add(name)
          ..add(value);
      }
      if (attributes.isNotEmpty) out['attributes'] = attributes;
    }
    if (depth >= maxDepth) return out;
    final rawChildren = value['children'];
    if (rawChildren is Iterable) {
      final children = <Map<String, dynamic>>[];
      var inspected = 0;
      for (final child in rawChildren) {
        if (inspected++ >= maxChildren || children.length >= maxChildren) {
          break;
        }
        final compact = visit(child, depth + 1);
        if (compact != null) children.add(compact);
      }
      if (children.isNotEmpty) out['children'] = children;
    }
    return out;
  }

  return visit(raw, 0);
}

/// 将 `Performance.getMetrics` 归一化为有限且名称唯一的采样项。
List<(String, double)> normalizeWebReversePerformanceMetrics(
  Object? rawMetrics, {
  int maxEntries = kWebReverseMaxPerformanceMetrics,
  int maxNameChars = kWebReverseMaxPerformanceMetricNameChars,
}) {
  _validatePositiveWebReverseLimits([maxEntries, maxNameChars]);
  if (rawMetrics is! Iterable) return const <(String, double)>[];
  final result = <(String, double)>[];
  final indexByName = <String, int>{};
  var inspected = 0;
  for (final raw in rawMetrics) {
    if (inspected++ >= maxEntries * 4) break;
    if (raw is! Map || raw['name'] is! String || raw['value'] is! num) {
      continue;
    }
    final name = (raw['name'] as String).trim();
    final value = (raw['value'] as num).toDouble();
    if (name.isEmpty || name.length > maxNameChars || !value.isFinite) {
      continue;
    }
    final existing = indexByName[name];
    final sample = (name, value);
    if (existing != null) {
      result[existing] = sample;
    } else if (result.length < maxEntries) {
      indexByName[name] = result.length;
      result.add(sample);
    }
  }
  return List<(String, double)>.unmodifiable(result);
}

/// 压缩 `CSS.getComputedStyleForNode` 返回的 `{name,value}` 记录。
List<Map<String, String>> compactWebReverseComputedStyles(
  Object? rawStyles, {
  int maxEntries = kWebReverseMaxComputedStyles,
  int maxNameChars = kWebReverseMaxComputedStyleNameChars,
  int maxValueChars = kWebReverseMaxComputedStyleValueChars,
}) {
  _validatePositiveWebReverseLimits([maxEntries, maxNameChars, maxValueChars]);
  if (rawStyles is! Iterable) return const <Map<String, String>>[];
  final result = <Map<String, String>>[];
  final seen = <String>{};
  var inspected = 0;
  for (final raw in rawStyles) {
    if (inspected++ >= maxEntries * 4 || result.length >= maxEntries) break;
    if (raw is! Map || raw['name'] is! String || raw['value'] is! String) {
      continue;
    }
    final name = (raw['name'] as String).trim();
    if (name.isEmpty || name.length > maxNameChars || !seen.add(name)) continue;
    result.add(<String, String>{
      'name': name,
      'value': _boundedWebReverseText(raw['value'], maxValueChars),
    });
  }
  return List<Map<String, String>>.unmodifiable(result);
}

Map<String, Object?>? _compactWebReverseRemoteObject(
  Object? raw, {
  required int maxTextChars,
}) {
  if (raw is! Map || raw['type'] is! String) return null;
  final type = _boundedWebReverseText(
    raw['type'],
    kWebReverseMaxRemoteObjectTypeChars,
    trim: true,
  );
  if (type.isEmpty) return null;
  final compact = <String, Object?>{'type': type};
  for (final key in const <String>['subtype', 'className', 'description']) {
    final value = raw[key];
    if (value is String && value.isNotEmpty) {
      compact[key] = _boundedWebReverseText(value, maxTextChars);
    }
  }
  final objectId = raw['objectId'];
  if (objectId is String &&
      objectId.isNotEmpty &&
      objectId.length <= kWebReverseMaxRemoteObjectIdChars) {
    compact['objectId'] = objectId;
  }
  final unserializable = raw['unserializableValue'];
  if (unserializable is String &&
      unserializable.length <= kWebReverseMaxRemoteObjectIdChars) {
    compact['unserializableValue'] = unserializable;
  }
  final value = raw['value'];
  if (value == null || value is num || value is bool) {
    compact['value'] = value;
  } else if (value is String) {
    compact['value'] = _boundedWebReverseText(value, maxTextChars);
  }
  return Map<String, Object?>.unmodifiable(compact);
}

/// 压缩 Scope/Watch 面板使用的 `Runtime.getProperties` 记录。
List<Map<String, Object?>> compactWebReverseRuntimeProperties(
  Object? rawProperties, {
  int maxEntries = kWebReverseMaxRuntimeProperties,
  int maxTextChars = kWebReverseMaxIndexedDbRemoteTextChars,
}) {
  _validatePositiveWebReverseLimits([maxEntries, maxTextChars]);
  if (rawProperties is! Iterable) return const <Map<String, Object?>>[];
  final result = <Map<String, Object?>>[];
  var inspected = 0;
  for (final raw in rawProperties) {
    if (inspected++ >= maxEntries * 4 || result.length >= maxEntries) break;
    if (raw is! Map || raw['name'] is! String) continue;
    final name = _boundedWebReverseText(
      raw['name'],
      kWebReverseMaxRuntimePropertyNameChars,
    );
    if (name.isEmpty) continue;
    final compact = <String, Object?>{'name': name};
    for (final key in const <String>[
      'isOwn',
      'configurable',
      'enumerable',
      'writable',
    ]) {
      if (raw[key] is bool) compact[key] = raw[key];
    }
    for (final key in const <String>['value', 'get', 'set']) {
      final value = _compactWebReverseRemoteObject(
        raw[key],
        maxTextChars: maxTextChars,
      );
      if (value != null) compact[key] = value;
    }
    result.add(Map<String, Object?>.unmodifiable(compact));
  }
  return List<Map<String, Object?>>.unmodifiable(result);
}

/// 压缩 `DOMDebugger.getEventListeners` 记录和处理器描述。
List<Map<String, Object?>> compactWebReverseDomEventListeners(
  Object? rawListeners, {
  int maxEntries = kWebReverseMaxDomEventListeners,
  int maxTextChars = kWebReverseMaxComputedStyleValueChars,
}) {
  _validatePositiveWebReverseLimits([maxEntries, maxTextChars]);
  if (rawListeners is! Iterable) return const <Map<String, Object?>>[];
  final result = <Map<String, Object?>>[];
  var inspected = 0;
  for (final raw in rawListeners) {
    if (inspected++ >= maxEntries * 4 || result.length >= maxEntries) break;
    if (raw is! Map) continue;
    final compact = <String, Object?>{};
    final type = raw['type'];
    if (type is! String ||
        type.isEmpty ||
        type.length > kWebReverseMaxDomEventListenerTypeChars) {
      continue;
    }
    compact['type'] = type;
    for (final key in const <String>[
      'useCapture',
      'passive',
      'once',
      'removed',
    ]) {
      if (raw[key] is bool) compact[key] = raw[key];
    }
    for (final key in const <String>['scriptId', 'backendNodeId']) {
      final value = raw[key];
      if (value is String &&
          value.length <= kWebReverseMaxRemoteObjectIdChars) {
        compact[key] = value;
      }
      if (value is num && value.isFinite) compact[key] = value.toInt();
    }
    for (final key in const <String>['lineNumber', 'columnNumber']) {
      final value = raw[key];
      if (value is num && value.isFinite) compact[key] = value.toInt();
    }
    final handler = _compactWebReverseRemoteObject(
      raw['handler'],
      maxTextChars: maxTextChars,
    );
    if (handler != null) compact['handler'] = handler;
    result.add(Map<String, Object?>.unmodifiable(compact));
  }
  return List<Map<String, Object?>>.unmodifiable(result);
}

/// 压缩浏览器端 `PerformanceObserver` 的长任务记录。
List<Map<String, Object?>> compactWebReverseLongTasks(
  Object? rawTasks, {
  int maxEntries = kWebReverseMaxLongTasks,
  int maxTextChars = kWebReverseMaxLongTaskAttributionChars,
}) {
  _validatePositiveWebReverseLimits([maxEntries, maxTextChars]);
  if (rawTasks is! Iterable) return const <Map<String, Object?>>[];
  final result = <Map<String, Object?>>[];
  var inspected = 0;
  for (final raw in rawTasks) {
    if (inspected++ >= maxEntries * 4 || result.length >= maxEntries) break;
    if (raw is! Map) continue;
    final compact = <String, Object?>{};
    for (final key in const <String>['startTime', 'duration']) {
      final value = key == 'startTime'
          ? raw['startTime'] ?? raw['start']
          : raw[key];
      if (value is num && value.isFinite && value >= 0) {
        compact[key] = value.toDouble();
      }
    }
    final name = raw['name'];
    if (name is String && name.isNotEmpty) {
      compact['name'] = _boundedWebReverseText(name, maxTextChars);
    }
    final attribution = raw['attribution'];
    if (attribution is Map) {
      final compactAttribution = <String, Object?>{};
      for (final key in const <String>[
        'name',
        'containerType',
        'containerSrc',
        'containerId',
        'containerName',
      ]) {
        final value = attribution[key];
        if (value is String && value.isNotEmpty) {
          compactAttribution[key] = _boundedWebReverseText(value, maxTextChars);
        }
      }
      if (compactAttribution.isNotEmpty) {
        compact['attribution'] = compactAttribution;
      }
    }
    if (compact.isNotEmpty) {
      result.add(Map<String, Object?>.unmodifiable(compact));
    }
  }
  return List<Map<String, Object?>>.unmodifiable(result);
}

Object? _compactWebReverseJsonValue(
  Object? value, {
  int depth = 0,
  int maxStringChars = kWebReverseMaxWebRtcEventChars ~/ 2,
}) {
  if (depth > kWebReverseMaxJsonDepth) return null;
  if (value == null || value is num || value is bool) return value;
  if (value is String) return _boundedWebReverseText(value, maxStringChars);
  if (value is List) {
    return [
      for (final item in value.take(kWebReverseMaxJsonCollectionItems))
        _compactWebReverseJsonValue(
          item,
          depth: depth + 1,
          maxStringChars: maxStringChars,
        ),
    ];
  }
  if (value is Map) {
    final result = <String, Object?>{};
    var count = 0;
    for (final entry in value.entries) {
      if (count++ >= kWebReverseMaxJsonCollectionItems ||
          entry.key is! String) {
        break;
      }
      result[_boundedWebReverseText(
        entry.key,
        kWebReverseMaxJsonKeyChars,
      )] = _compactWebReverseJsonValue(
        entry.value,
        depth: depth + 1,
        maxStringChars: maxStringChars,
      );
    }
    return result;
  }
  return _boundedWebReverseText(value, kWebReverseMaxJsonValueFallbackChars);
}

/// 压缩并限制从 `window.__oh_rtc_log` 提取的记录。
List<Map<String, Object?>> compactWebReverseWebRtcLog(
  Object? rawEvents, {
  int maxEntries = kWebReverseMaxWebRtcEvents,
  int maxEventChars = kWebReverseMaxWebRtcEventChars,
  int maxTotalChars = kWebReverseMaxWebRtcLogChars,
}) {
  _validatePositiveWebReverseLimits([maxEntries, maxEventChars, maxTotalChars]);
  if (rawEvents is! Iterable) return const <Map<String, Object?>>[];
  final result = <Map<String, Object?>>[];
  var retainedChars = 0;
  var inspected = 0;
  for (final raw in rawEvents) {
    if (inspected++ >= maxEntries * 4 || result.length >= maxEntries) break;
    if (raw is! Map || raw['kind'] is! String) continue;
    final kind = (raw['kind'] as String).trim();
    if (kind.isEmpty || kind.length > kWebReverseMaxWebRtcEventKindChars) {
      continue;
    }
    final event = <String, Object?>{'kind': kind};
    final ts = raw['ts'];
    if (ts is num && ts.isFinite && ts >= 0) event['ts'] = ts.toInt();
    final id = raw['id'];
    if (id is num && id.isFinite && id >= 0 && id <= 0x7fffffff) {
      event['id'] = id.toInt();
    }
    for (final key in const <String>[
      'config',
      'args',
      'sdp',
      'type',
      'error',
      'candidate',
      'sdpMid',
      'sdpMLineIndex',
      'trackKind',
      'readyState',
      'muted',
      'streamIds',
      'label',
      'protocol',
      'ordered',
      'state',
      'bytesSent',
      'bytesReceived',
      'packetsLost',
      'packetsSent',
      'packetsReceived',
      'rtt',
      'jitter',
    ]) {
      if (!raw.containsKey(key)) continue;
      final compact = _compactWebReverseJsonValue(
        raw[key],
        maxStringChars: maxEventChars ~/ 2,
      );
      if (compact != null) event[key] = compact;
    }
    try {
      final cost = jsonEncode(event).length;
      if (cost > maxEventChars || retainedChars + cost > maxTotalChars) break;
      retainedChars += cost;
      result.add(Map<String, Object?>.unmodifiable(event));
    } catch (_) {
      // 忽略单条异常事件并继续提取后续条目。
    }
  }
  return List<Map<String, Object?>>.unmodifiable(result);
}

/// 跟踪事件进入会话聚合缓冲区前先限制大小。Trace `args` 可能包含任意嵌套对象，
/// 因此调用方估算事件成本前先执行通用类 JSON 清理。
Map<String, Object?>? compactWebReverseTraceEvent(
  Object? raw, {
  int maxChars = kWebReverseMaxTraceEventChars,
  int maxFields = kWebReverseMaxTraceEventFields,
}) {
  _validatePositiveWebReverseLimits([maxChars, maxFields]);
  if (raw is! Map) return null;
  final compact = <String, Object?>{};
  var fields = 0;
  for (final entry in raw.entries) {
    if (fields++ >= maxFields || entry.key is! String) break;
    final key = _boundedWebReverseText(entry.key, kWebReverseMaxJsonKeyChars);
    if (key.isEmpty) continue;
    final value = _compactWebReverseJsonValue(
      entry.value,
      maxStringChars: maxChars ~/ 2,
    );
    if (value != null) compact[key] = value;
  }
  try {
    if (jsonEncode(compact).length > maxChars) return null;
  } catch (_) {
    return null;
  }
  return Map<String, Object?>.unmodifiable(compact);
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

/// 迭代汇总 V8 SamplingHeapProfile 根节点。
///
/// 遍历量、保留栈深、聚合桶和帧文本均有上限，避免异常或过深的采样数据导致
/// Dart 栈溢出或保留无界调用树。
({int totalSize, List<({String label, int size, List<String> stack})> top})?
summarizeSamplingHeapProfile(
  Object? rawHead, {
  int maxNodes = 100000,
  int maxStackDepth = 256,
  int maxFunctionBuckets = 20000,
  int maxTopEntries = 15,
  int maxFunctionNameChars = 512,
  int maxUrlChars = 16 * kBytesPerKiB,
}) {
  if (maxNodes <= 0 ||
      maxStackDepth <= 0 ||
      maxFunctionBuckets <= 0 ||
      maxTopEntries <= 0 ||
      maxFunctionNameChars <= 0 ||
      maxUrlChars <= 0) {
    throw ArgumentError('采样分析上限必须为正数。');
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
    final functionName = clipTextByCodeUnits(
      '${callFrame['functionName'] ?? '(anonymous)'}',
      maxFunctionNameChars,
      suffix: '',
    );
    final url = clipTextByCodeUnits(
      '${callFrame['url'] ?? ''}',
      maxUrlChars,
      suffix: '',
    );
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
      .replaceAll(kInlineWhitespacePattern, ' ');
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
