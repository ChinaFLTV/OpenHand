import 'dart:io';

/// 扫描跨 feature 深路径 import。违规规则：
///   1. lib/features/<a>/**/*.dart 中 import 解析后落在 lib/features/<b>/<sub>
///      （b != a）且 sub 不是 'index.dart'、'<b>_module.dart' 或
///      '<b>_controller.dart' 三者之一，视为深路径跨 feature import。
///   2. clients/web/src/features/<a>/**/*.{ts,tsx} 中禁止深路径
///      '@/features/<b>/<sub>/...' 或 '../<b>/<sub>/...'（b != a，sub 非 index*）。
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
  violations += await _scanWeb(Directory('$root/clients/web/src/features'));

  if (violations > 0) {
    stderr.writeln(
      '[check_imports] $violations deep cross-feature import(s) found.',
    );
    exit(1);
  }
  stdout.writeln('[check_imports] OK');
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
        stderr.writeln(
          '${entity.path}:${i + 1} deep cross-feature import: $target/$sub',
        );
        n++;
      }
    }
  }
  return n;
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
  final tsRe = RegExp(
    r"""from\s+['"](?:@/features/|(?:\.\./)+features/)([\w-]+)/([\w./-]+)['"]""",
  );
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
      final target = m.group(1)!;
      final sub = m.group(2)!;
      if (target == owner) continue;
      if (sub == 'index' || sub == 'index.ts' || sub == 'index.tsx') continue;
      stderr.writeln(
        '${entity.path}:${i + 1} deep cross-feature import: $target/$sub',
      );
      n++;
    }
  }
  return n;
}
