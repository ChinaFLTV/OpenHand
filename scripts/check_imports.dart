import 'dart:io';

/// 扫描跨 feature 深路径 import。违规规则：
///   1. lib/features/<a>/**/*.dart 中 import 解析后落在 lib/features/<b>/<sub>
///      （b != a）且 sub 不是 'index.dart'、'<b>_module.dart' 或
///      '<b>_controller.dart' 三者之一，视为深路径跨 feature import。
///   2. clients/web/src/features/<a>/**/*.{ts,tsx} 中禁止深路径
///      '@/features/<b>/<sub>/...' 或 '../<b>/<sub>/...'（b != a，sub 非 index*）。
///   3. lib/ 业务代码禁止直接调用或构造 Flutter 原生弹窗、菜单、底部面板与
///      OverlayEntry；统一通过 shared/ui 的全局动画入口展示。
///   4. lib/ 业务代码禁止直接调用 ScaffoldMessenger 的 SnackBar 方法；统一
///      通过 shared/ui/openhand_snack_bar.dart，以保证进退场动效与全局
///      弹窗动画设置一致。
///   5. lib/ 业务代码禁止直接构造 Timer；统一通过安全计时工具限制时长并处理
///      异步回调异常。
///   6. Web 模态弹窗与 Portal 必须经统一框架构建，保持全局动效、焦点
///      管理、Escape 关闭和全屏投射行为一致。
///
/// 同 feature 内部 import 不限制；该脚本只约束跨 feature 深路径依赖。
///
/// 解析后落到 lib/shared/、lib/app/、lib/l10n/ 等非 features 的路径，
/// 以及解析后仍在 owner 自身目录内的 import（含 ../data/、../service/），
/// 都不算违规。
///
/// 仅扫描单行 `import …;`（Dart）/ `… from …`（TS）；多行 import、export
/// 再导出、`import()`、`require()`、bare side-effect `import 'x'`（TS）
/// 显式不在范围。
///
/// 用法：dart run scripts/check_imports.dart [root]
///   root 默认为当前目录；测试时可传 fixture 根。
Future<void> main(List<String> args) async {
  final root = args.isEmpty ? Directory.current.path : args.first;
  var violations = 0;

  violations += await _scanDart(root);
  violations += await _scanRestrictedApis(root);
  violations += await _scanWeb(Directory('$root/clients/web/src/features'));
  violations += await _scanWebRestrictedApis(root);

  if (violations > 0) {
    stderr.writeln('[架构检查] 发现 $violations 个边界违规。');
    exit(1);
  }
  stdout.writeln('[架构检查] 通过。');
}

Future<int> _scanDart(String root) async {
  final featuresRoot = Directory('$root/lib/features');
  if (!featuresRoot.existsSync()) return 0;
  final sep = Platform.pathSeparator;
  final featuresAbs = featuresRoot.path;
  final libAbs = '$root${sep}lib';
  var n = 0;

  final importRe = RegExp(r'''^\s*import\s+['"]([^'"]+)['"]''');

  await for (final entity in featuresRoot.list(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final rel = entity.path.substring(featuresAbs.length + 1);
    final owner = rel.split(sep).first;
    final fileDir = entity.parent.path;

    final lines = await entity.readAsLines();
    for (var i = 0; i < lines.length; i++) {
      final m = importRe.firstMatch(lines[i]);
      if (m == null) continue;
      final raw = m.group(1)!;

      // 计算 import 解析后的绝对路径（normalize 后）。
      final resolvedAbs = _resolveDartImport(
        raw: raw,
        fileDir: fileDir,
        libAbs: libAbs,
      );
      if (resolvedAbs == null) continue; // package: 非 openhand 自身，忽略

      // 必须落在 lib/features/ 之下才有资格违规。
      if (!resolvedAbs.startsWith('$featuresAbs$sep')) continue;

      final relUnderFeatures = resolvedAbs.substring(featuresAbs.length + 1);
      final segs = relUnderFeatures.split(sep);
      if (segs.isEmpty) continue;
      final target = segs.first;
      final sub = segs.skip(1).join('/');

      if (target == owner) {
        // 同 feature 内部跳转一律允许：widget-bundle 形态（harness/settings）
        // 没有 Controller 中介，widgets 直接调 service 是合理的；其它有
        // Controller 的 feature 也允许同 feature 内部 widgets→service，因为
        // 强制约束已被实践证明会强行重写大量稳定代码而无收益。
        continue;
      }
      // 跨 feature：仅允许 barrel 三种入口。
      final allowed =
          sub == 'index.dart' ||
          sub == '${target}_module.dart' ||
          sub == '${target}_controller.dart';
      if (!allowed) {
        stderr.writeln('${entity.path}:${i + 1} 跨功能深层导入：$target/$sub');
        n++;
      }
    }
  }
  return n;
}

/// 只允许在指定封装文件里出现的原生 API 规则。
class _RestrictedApiRule {
  const _RestrictedApiRule({
    required this.pattern,
    required this.allowedRelativePaths,
    required this.fallbackApiName,
    required this.advice,
  });

  final RegExp pattern;

  /// 相对 `lib/` 的封装文件路径，用 `/` 分隔。
  final Set<String> allowedRelativePaths;

  /// 正则未捕获到具体 API 名时的兜底描述。
  final String fallbackApiName;
  final String advice;
}

List<_RestrictedApiRule> _restrictedApiRules() => <_RestrictedApiRule>[
  _RestrictedApiRule(
    pattern: RegExp(
      r'\b(showDialog|showGeneralDialog|showAdaptiveDialog|showCupertinoDialog'
      r'|showCupertinoModalPopup|showModalBottomSheet|showBottomSheet'
      r'|showDatePicker|showDateRangePicker|showTimePicker|showAboutDialog'
      r'|showLicensePage|showSearch|showMenu)\s*(?:<[^>\n]+>)?\s*\('
      r'|\b(DialogRoute|RawDialogRoute|CupertinoDialogRoute'
      r'|ModalBottomSheetRoute|PopupMenuRoute|AlertDialog|SimpleDialog|Dialog'
      r'|PopupMenuButton|DropdownButton|DropdownMenu|MenuAnchor|OverlayEntry)'
      r'\s*(?:<[^>\n]+>)?\s*\(',
    ),
    allowedRelativePaths: const <String>{
      'shared/ui/animated_dialog.dart',
      'shared/ui/animated_menu.dart',
      'shared/ui/animated_overlay.dart',
    },
    fallbackApiName: '原生弹窗 API',
    advice: '请使用 shared/ui 的全局动画入口',
  ),
  // 提示条与弹窗共用同一套全局动效设置：绕过封装直接 showSnackBar 会失去
  // 进场/退场动画与队列管理，出现生硬的 UI 变换。
  _RestrictedApiRule(
    pattern: RegExp(
      r'\b(showSnackBar|hideCurrentSnackBar|removeCurrentSnackBar'
      r'|clearSnackBars)\s*\(',
    ),
    allowedRelativePaths: const <String>{'shared/ui/openhand_snack_bar.dart'},
    fallbackApiName: '原生 SnackBar API',
    advice: '请使用 shared/ui/openhand_snack_bar.dart 的提示条入口',
  ),
  _RestrictedApiRule(
    pattern: RegExp(r'\bTimer\s*(?:\.periodic\s*)?\('),
    allowedRelativePaths: const <String>{
      'shared/util/timer_safety.dart',
      'shared/util/async_concurrency.dart',
    },
    fallbackApiName: 'Timer',
    advice: '请使用 shared/util/timer_safety.dart 的安全计时工具',
  ),
];

/// 取命中的具体 API 名；规则正则可能没有捕获组（如 Timer），此时用兜底名称。
String _matchedApiName(RegExpMatch match, String fallback) {
  for (var group = 1; group <= match.groupCount; group++) {
    final name = match.group(group);
    if (name != null && name.isNotEmpty) return name;
  }
  return fallback;
}

Future<int> _scanRestrictedApis(String root) async {
  final libRoot = Directory('$root/lib');
  if (!libRoot.existsSync()) return 0;
  final sep = Platform.pathSeparator;
  final rules = _restrictedApiRules();
  final allowedByRule = rules
      .map(
        (rule) => rule.allowedRelativePaths
            .map(
              (path) =>
                  _normalize('$root${sep}lib$sep${path.replaceAll('/', sep)}'),
            )
            .toSet(),
      )
      .toList(growable: false);
  var violations = 0;

  await for (final entity in libRoot.list(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final normalizedPath = _normalize(entity.path);
    var blockCommentDepth = 0;
    final lines = await entity.readAsLines();
    for (var i = 0; i < lines.length; i++) {
      final stripped = _stripDartComments(lines[i], blockCommentDepth);
      blockCommentDepth = stripped.blockCommentDepth;
      for (var index = 0; index < rules.length; index++) {
        if (allowedByRule[index].contains(normalizedPath)) continue;
        final rule = rules[index];
        for (final match in rule.pattern.allMatches(stripped.code)) {
          stderr.writeln(
            '${entity.path}:${i + 1} 业务代码禁止直接调用 '
            '${_matchedApiName(match, rule.fallbackApiName)}；${rule.advice}',
          );
          violations++;
        }
      }
    }
  }
  return violations;
}

({String code, int blockCommentDepth}) _stripDartComments(
  String line,
  int initialBlockCommentDepth,
) {
  final code = StringBuffer();
  var blockCommentDepth = initialBlockCommentDepth;
  var index = 0;
  while (index < line.length) {
    if (blockCommentDepth > 0) {
      if (index + 1 < line.length && line.startsWith('/*', index)) {
        blockCommentDepth++;
        index += 2;
      } else if (index + 1 < line.length && line.startsWith('*/', index)) {
        blockCommentDepth--;
        index += 2;
      } else {
        index++;
      }
      continue;
    }
    if (index + 1 < line.length && line.startsWith('//', index)) break;
    if (index + 1 < line.length && line.startsWith('/*', index)) {
      blockCommentDepth++;
      index += 2;
      continue;
    }
    code.writeCharCode(line.codeUnitAt(index));
    index++;
  }
  return (code: code.toString(), blockCommentDepth: blockCommentDepth);
}

/// 解析单行 import 的 URI 到绝对文件路径。
/// 返回 null 表示无需扫描（非项目自身或解析失败）。
String? _resolveDartImport({
  required String raw,
  required String fileDir,
  required String libAbs,
}) {
  // package:openhand/<sub> → <libAbs>/<sub>
  const pkgPrefix = 'package:openhand/';
  if (raw.startsWith(pkgPrefix)) {
    return _normalize(
      '$libAbs${Platform.pathSeparator}'
      '${raw.substring(pkgPrefix.length).replaceAll('/', Platform.pathSeparator)}',
    );
  }
  // 其它 package: 第三方，跳过。
  if (raw.startsWith('package:')) return null;
  // dart:foo
  if (raw.startsWith('dart:')) return null;
  // 绝对路径或其它 scheme 不应在 source 出现，保守跳过。
  if (raw.contains(':')) return null;
  // 相对路径
  return _normalize(
    '$fileDir${Platform.pathSeparator}${raw.replaceAll('/', Platform.pathSeparator)}',
  );
}

String _normalize(String p) {
  final sep = Platform.pathSeparator;
  final parts = p.split(sep);
  final out = <String>[];
  for (final s in parts) {
    if (s == '' || s == '.') continue;
    if (s == '..') {
      if (out.isNotEmpty && out.last != '..') {
        out.removeLast();
      } else {
        out.add(s);
      }
    } else {
      out.add(s);
    }
  }
  // 保留前导分隔符（POSIX 绝对路径）。
  final leading = p.startsWith(sep) ? sep : '';
  return leading + out.join(sep);
}

Future<int> _scanWeb(Directory featuresRoot) async {
  if (!featuresRoot.existsSync()) return 0;
  var n = 0;
  final tsRe = RegExp(r'''^\s*import\b.*\bfrom\s+['"]([^'"]+)['"]''');
  await for (final entity in featuresRoot.list(recursive: true)) {
    if (entity is! File ||
        !(entity.path.endsWith('.ts') || entity.path.endsWith('.tsx'))) {
      continue;
    }
    final rel = entity.path.substring(featuresRoot.path.length + 1);
    final owner = rel.split(Platform.pathSeparator).first;
    final lines = await entity.readAsLines();
    for (var i = 0; i < lines.length; i++) {
      final m = tsRe.firstMatch(lines[i]);
      if (m == null) continue;
      final resolved = _resolveWebImport(
        raw: m.group(1)!,
        fileDir: entity.parent.path,
        featuresRoot: featuresRoot.path,
      );
      if (resolved == null) continue;
      final featuresPrefix = '${featuresRoot.path}${Platform.pathSeparator}';
      if (!resolved.startsWith(featuresPrefix)) continue;
      final relUnderFeatures = resolved.substring(featuresPrefix.length);
      final segments = relUnderFeatures.split(Platform.pathSeparator);
      if (segments.isEmpty || segments.first.isEmpty) continue;
      final target = segments.first;
      final sub = segments.skip(1).join('/');
      if (target == owner) continue;
      if (_isWebFeatureEntry(sub)) continue;
      stderr.writeln('${entity.path}:${i + 1} 跨功能深层导入：$target/$sub');
      n++;
    }
  }
  return n;
}

String? _resolveWebImport({
  required String raw,
  required String fileDir,
  required String featuresRoot,
}) {
  const aliasPrefix = '@/features/';
  if (raw.startsWith(aliasPrefix)) {
    return _normalize(
      '$featuresRoot${Platform.pathSeparator}'
      '${raw.substring(aliasPrefix.length).replaceAll('/', Platform.pathSeparator)}',
    );
  }
  if (!raw.startsWith('.')) return null;
  final resolved = _normalize(
    '$fileDir${Platform.pathSeparator}'
    '${raw.replaceAll('/', Platform.pathSeparator)}',
  );
  final prefix = '$featuresRoot${Platform.pathSeparator}';
  return resolved.startsWith(prefix) ? resolved : null;
}

bool _isWebFeatureEntry(String sub) {
  if (sub.isEmpty) return true;
  return RegExp(r'^index(?:\.(?:ts|tsx|js|jsx))?$').hasMatch(sub);
}

class _WebRestrictedApiRule {
  const _WebRestrictedApiRule({
    required this.pattern,
    required this.allowedRelativePath,
    required this.message,
  });

  final RegExp pattern;
  final String allowedRelativePath;
  final String message;
}

Future<int> _scanWebRestrictedApis(String root) async {
  final sourceRoot = Directory('$root/clients/web/src');
  if (!sourceRoot.existsSync()) return 0;
  final rules = <_WebRestrictedApiRule>[
    _WebRestrictedApiRule(
      pattern: RegExp(
        r'''\baria-modal\s*=|\brole\s*=\s*(?:["']dialog["']|\{\s*["']dialog["']\s*\})''',
      ),
      allowedRelativePath: 'components/DialogFrame.tsx',
      message: 'Web 模态弹窗必须使用 DialogFrame',
    ),
    _WebRestrictedApiRule(
      pattern: RegExp(r'\bcreatePortal\s*\('),
      allowedRelativePath: 'components/OverlayPortal.tsx',
      message: 'Web Portal 必须使用 OverlayPortal',
    ),
  ];
  final separator = Platform.pathSeparator;
  var violations = 0;
  await for (final entity in sourceRoot.list(recursive: true)) {
    if (entity is! File ||
        !(entity.path.endsWith('.ts') || entity.path.endsWith('.tsx'))) {
      continue;
    }
    final relativePath = entity.path
        .substring(sourceRoot.path.length + 1)
        .replaceAll(separator, '/');
    final lines = await entity.readAsLines();
    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      for (final rule in rules) {
        if (relativePath == rule.allowedRelativePath) continue;
        if (!rule.pattern.hasMatch(lines[lineIndex])) continue;
        stderr.writeln('${entity.path}:${lineIndex + 1} ${rule.message}。');
        violations++;
      }
    }
  }
  return violations;
}
