import '../../../shared/util/input_value_parsing.dart';
import 'ai_deny_command_rule.dart';

enum AiSandboxFileAccessMode {
  readOnly('ro'),
  readWrite('rw');

  const AiSandboxFileAccessMode(this.storageValue);

  final String storageValue;

  static AiSandboxFileAccessMode fromStorage(String value) {
    return enumByStorageValueOr(
      values,
      value,
      (mode) => mode.storageValue,
      fallback: AiSandboxFileAccessMode.readOnly,
    );
  }
}

class AiSandboxPatternRule {
  factory AiSandboxPatternRule.fromJson(Map<String, Object?> json) {
    return AiSandboxPatternRule(
      id: stringFromValue(json['id']),
      pattern: stringFromValue(json['pattern']),
      matchMode: AiDenyCommandMatchMode.fromStorage(
        stringFromValue(json['match_mode']),
      ),
      note: stringFromValue(json['note']),
    );
  }

  const AiSandboxPatternRule({
    required this.id,
    required this.pattern,
    required this.matchMode,
    this.note = '',
  });

  final String id;
  final String pattern;
  final AiDenyCommandMatchMode matchMode;
  final String note;

  AiSandboxPatternRule copyWith({
    String? id,
    String? pattern,
    AiDenyCommandMatchMode? matchMode,
    String? note,
  }) {
    return AiSandboxPatternRule(
      id: id ?? this.id,
      pattern: pattern ?? this.pattern,
      matchMode: matchMode ?? this.matchMode,
      note: note ?? this.note,
    );
  }

  bool matches(String value) {
    final normalizedPattern = nullIfBlank(pattern);
    final normalizedValue = nullIfBlank(value);
    if (normalizedPattern == null || normalizedValue == null) {
      return false;
    }
    try {
      final regex = matchMode == AiDenyCommandMatchMode.regex
          ? RegExp(normalizedPattern, multiLine: true)
          : RegExp(simplePatternToRegex(normalizedPattern), multiLine: true);
      return regex.hasMatch(normalizedValue);
    } catch (_) {
      return false;
    }
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'pattern': pattern,
      'match_mode': matchMode.storageValue,
      'note': note,
    };
  }
}

class AiSandboxFileRule {
  factory AiSandboxFileRule.fromJson(Map<String, Object?> json) {
    return AiSandboxFileRule(
      id: stringFromValue(json['id']),
      path: stringFromValue(json['path']),
      accessMode: AiSandboxFileAccessMode.fromStorage(
        stringFromValue(json['access_mode']),
      ),
      matchMode: AiDenyCommandMatchMode.fromStorage(
        stringFromValue(json['match_mode']),
      ),
      note: stringFromValue(json['note']),
    );
  }

  const AiSandboxFileRule({
    required this.id,
    required this.path,
    required this.accessMode,
    required this.matchMode,
    this.note = '',
  });

  final String id;
  final String path;
  final AiSandboxFileAccessMode accessMode;
  final AiDenyCommandMatchMode matchMode;
  final String note;

  AiSandboxFileRule copyWith({
    String? id,
    String? path,
    AiSandboxFileAccessMode? accessMode,
    AiDenyCommandMatchMode? matchMode,
    String? note,
  }) {
    return AiSandboxFileRule(
      id: id ?? this.id,
      path: path ?? this.path,
      accessMode: accessMode ?? this.accessMode,
      matchMode: matchMode ?? this.matchMode,
      note: note ?? this.note,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'path': path,
      'access_mode': accessMode.storageValue,
      'match_mode': matchMode.storageValue,
      'note': note,
    };
  }
}

class AiSandboxSettings {
  factory AiSandboxSettings.defaults() {
    return const AiSandboxSettings(
      enabled: false,
      failIfUnavailable: true,
      allowUnsandboxedCommands: false,
      autoAllowBashIfSandboxed: false,
      sandboxedBuiltinTools: <String>[],
      filesystemRules: <AiSandboxFileRule>[
        AiSandboxFileRule(
          id: 'default-openhand-ro',
          path: '.openhand',
          accessMode: AiSandboxFileAccessMode.readOnly,
          matchMode: AiDenyCommandMatchMode.simple,
          note: 'OpenHand workspace metadata is read-only by default.',
        ),
      ],
      excludedCommands: <AiSandboxPatternRule>[],
      allowedDomains: <AiSandboxPatternRule>[],
      deniedDomains: <AiSandboxPatternRule>[],
      httpProxyPort: 0,
      socksProxyPort: 0,
      allowNetworkWhenNoDomainRules: true,
    );
  }

  factory AiSandboxSettings.fromJson(Object? raw) {
    final json = optionalStringKeyedMapFromValueOrJsonText(raw);
    if (json == null) return AiSandboxSettings.defaults();
    return AiSandboxSettings(
      enabled: boolFromValue(json['enabled']),
      failIfUnavailable: boolFromValue(
        json['fail_if_unavailable'],
        defaultValue: true,
      ),
      allowUnsandboxedCommands: boolFromValue(
        json['allow_unsandboxed_commands'],
      ),
      autoAllowBashIfSandboxed: boolFromValue(
        json['auto_allow_bash_if_sandboxed'],
      ),
      sandboxedBuiltinTools: _readUniqueStringList(
        json['sandboxed_builtin_tools'],
      ),
      filesystemRules: _readFileRules(json['filesystem_rules']),
      excludedCommands: _readPatternRules(json['excluded_commands']),
      allowedDomains: _readPatternRules(json['allowed_domains']),
      deniedDomains: _readPatternRules(json['denied_domains']),
      httpProxyPort: _normalizePort(json['http_proxy_port']),
      socksProxyPort: _normalizePort(json['socks_proxy_port']),
      allowNetworkWhenNoDomainRules: boolFromValue(
        json['allow_network_when_no_domain_rules'],
        defaultValue: true,
      ),
    );
  }

  const AiSandboxSettings({
    required this.enabled,
    required this.failIfUnavailable,
    required this.allowUnsandboxedCommands,
    required this.autoAllowBashIfSandboxed,
    required this.sandboxedBuiltinTools,
    required this.filesystemRules,
    required this.excludedCommands,
    required this.allowedDomains,
    required this.deniedDomains,
    required this.httpProxyPort,
    required this.socksProxyPort,
    required this.allowNetworkWhenNoDomainRules,
  });

  final bool enabled;
  final bool failIfUnavailable;
  final bool allowUnsandboxedCommands;
  final bool autoAllowBashIfSandboxed;
  final List<String> sandboxedBuiltinTools;
  final List<AiSandboxFileRule> filesystemRules;
  final List<AiSandboxPatternRule> excludedCommands;
  final List<AiSandboxPatternRule> allowedDomains;
  final List<AiSandboxPatternRule> deniedDomains;
  final int httpProxyPort;
  final int socksProxyPort;
  final bool allowNetworkWhenNoDomainRules;

  bool get hasDomainRules =>
      allowedDomains.isNotEmpty || deniedDomains.isNotEmpty;

  bool shouldSandboxBuiltinTool(String toolName) {
    final normalized = _normalizeToolName(toolName);
    if (normalized.isEmpty) return false;
    return sandboxedBuiltinTools.any(
      (item) => _normalizeToolName(item) == normalized,
    );
  }

  AiSandboxPatternRule? matchingExcludedCommand(String command) {
    for (final rule in excludedCommands) {
      if (rule.matches(command)) return rule;
    }
    return null;
  }

  AiSandboxSettings copyWith({
    bool? enabled,
    bool? failIfUnavailable,
    bool? allowUnsandboxedCommands,
    bool? autoAllowBashIfSandboxed,
    List<String>? sandboxedBuiltinTools,
    List<AiSandboxFileRule>? filesystemRules,
    List<AiSandboxPatternRule>? excludedCommands,
    List<AiSandboxPatternRule>? allowedDomains,
    List<AiSandboxPatternRule>? deniedDomains,
    int? httpProxyPort,
    int? socksProxyPort,
    bool? allowNetworkWhenNoDomainRules,
  }) {
    return AiSandboxSettings(
      enabled: enabled ?? this.enabled,
      failIfUnavailable: failIfUnavailable ?? this.failIfUnavailable,
      allowUnsandboxedCommands:
          allowUnsandboxedCommands ?? this.allowUnsandboxedCommands,
      autoAllowBashIfSandboxed:
          autoAllowBashIfSandboxed ?? this.autoAllowBashIfSandboxed,
      sandboxedBuiltinTools:
          sandboxedBuiltinTools ?? this.sandboxedBuiltinTools,
      filesystemRules: filesystemRules ?? this.filesystemRules,
      excludedCommands: excludedCommands ?? this.excludedCommands,
      allowedDomains: allowedDomains ?? this.allowedDomains,
      deniedDomains: deniedDomains ?? this.deniedDomains,
      httpProxyPort: httpProxyPort ?? this.httpProxyPort,
      socksProxyPort: socksProxyPort ?? this.socksProxyPort,
      allowNetworkWhenNoDomainRules:
          allowNetworkWhenNoDomainRules ?? this.allowNetworkWhenNoDomainRules,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'enabled': enabled,
      'fail_if_unavailable': failIfUnavailable,
      'allow_unsandboxed_commands': allowUnsandboxedCommands,
      'auto_allow_bash_if_sandboxed': autoAllowBashIfSandboxed,
      'sandboxed_builtin_tools': sandboxedBuiltinTools,
      'filesystem_rules': filesystemRules
          .map((item) => item.toJson())
          .toList(growable: false),
      'excluded_commands': excludedCommands
          .map((item) => item.toJson())
          .toList(growable: false),
      'allowed_domains': allowedDomains
          .map((item) => item.toJson())
          .toList(growable: false),
      'denied_domains': deniedDomains
          .map((item) => item.toJson())
          .toList(growable: false),
      'http_proxy_port': httpProxyPort,
      'socks_proxy_port': socksProxyPort,
      'allow_network_when_no_domain_rules': allowNetworkWhenNoDomainRules,
    };
  }

  static List<String> _readUniqueStringList(Object? value) {
    return stringListFromValueOrJsonText(value).toSet().toList(growable: false);
  }

  static List<AiSandboxFileRule> _readFileRules(Object? value) {
    final items = stringKeyedMapListFromValueOrJsonText(value);
    if (items.isEmpty) return AiSandboxSettings.defaults().filesystemRules;
    final rules = <AiSandboxFileRule>[];
    for (final item in items) {
      final rule = AiSandboxFileRule.fromJson(item);
      if (nullIfBlank(rule.path) != null) rules.add(rule);
    }
    return rules.isEmpty ? AiSandboxSettings.defaults().filesystemRules : rules;
  }

  static List<AiSandboxPatternRule> _readPatternRules(Object? value) {
    final rules = <AiSandboxPatternRule>[];
    for (final item in stringKeyedMapListFromValueOrJsonText(value)) {
      final rule = AiSandboxPatternRule.fromJson(item);
      if (nullIfBlank(rule.pattern) != null) rules.add(rule);
    }
    return rules;
  }

  static int _normalizePort(Object? value) {
    final port = optionalIntFromValue(value);
    if (port == null || port <= 0 || port > 65535) return 0;
    return port;
  }

  static String _normalizeToolName(String value) {
    final buffer = StringBuffer();
    for (final code in value.codeUnits) {
      if ((code >= 0x30 && code <= 0x39) ||
          (code >= 0x41 && code <= 0x5A) ||
          (code >= 0x61 && code <= 0x7A)) {
        buffer.writeCharCode(code | 0x20);
      }
    }
    return buffer.toString();
  }
}
