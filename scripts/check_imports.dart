import 'dart:io';

/// 扫描跨 feature 深路径 import。违规规则：
///   1. lib/features/<a>/**/*.dart 中 import 解析后落在 lib/features/<b>/<sub>
///      （b != a）且 sub 不是 'index.dart'、'<b>_module.dart' 或
///      '<b>_controller.dart' 三者之一，视为深路径跨 feature import。
///   2. clients/web/src/features/<a>/**/*.{ts,tsx} 中禁止深路径
///      '@/features/<b>/<sub>/...' 或 '../<b>/<sub>/...'（b != a，sub 非 index*）。
///   3. lib/ 业务代码禁止直接调用 Flutter 原生弹窗 API；统一通过
///      shared/ui/animated_dialog.dart 接入全局弹窗动效。
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
  violations += await _scanDialogApis(root);
  violations += await _scanWeb(Directory('$root/clients/web/src/features'));

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

Future<int> _scanDialogApis(String root) async {
  final libRoot = Directory('$root/lib');
  if (!libRoot.existsSync()) return 0;
  final allowedPath = _normalize(
    '$root${Platform.pathSeparator}lib${Platform.pathSeparator}shared'
    '${Platform.pathSeparator}ui${Platform.pathSeparator}animated_dialog.dart',
  );
  final forbiddenApi = RegExp(
    r'\b(showDialog|showGeneralDialog|showCupertinoDialog|showModalBottomSheet)'
    r'\s*(?:<[^>\n]+>)?\s*\('
    r'|\b(DialogRoute|RawDialogRoute)\s*(?:<[^>\n]+>)?\s*\(',
  );
  var violations = 0;

  await for (final entity in libRoot.list(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (_normalize(entity.path) == allowedPath) continue;
    var blockCommentDepth = 0;
    final lines = await entity.readAsLines();
    for (var i = 0; i < lines.length; i++) {
      final stripped = _stripDartComments(lines[i], blockCommentDepth);
      blockCommentDepth = stripped.blockCommentDepth;
      for (final match in forbiddenApi.allMatches(stripped.code)) {
        final api = match.group(1) ?? match.group(2) ?? '原生弹窗 API';
        stderr.writeln(
          '${entity.path}:${i + 1} 业务代码禁止直接调用 $api；'
          '请使用 animated_dialog.dart 统一入口',
        );
        violations++;
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
