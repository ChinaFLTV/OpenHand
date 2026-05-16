import 'dart:io';

/// 扫描跨 feature 深路径 import。违规规则：
///   1. lib/features/<a>/**/*.dart 中 import 形如 '../../<b>/<sub>/...' 或
///      'package:openhand/features/<b>/<sub>/...'（b != a 且 sub != 'index.dart' 且 sub != '<b>_module.dart'）。
///   2. lib/features/<a>/widgets/**/*.dart 中禁止 import '../service/...'。
///   3. clients/web/src/features/<a>/**/*.{ts,tsx} 中禁止深路径
///      '@/features/<b>/<sub>/...' 或 '../<b>/<sub>/...'。
///
/// 用法：dart run scripts/check_imports.dart [root]
///   root 默认为当前目录；测试时可传 fixture 根。
Future<void> main(List<String> args) async {
  final root = args.isEmpty ? Directory.current.path : args.first;
  var violations = 0;

  violations += await _scanDart(Directory('$root/lib/features'));
  violations += await _scanWeb(Directory('$root/clients/web/src/features'));

  if (violations > 0) {
    stderr.writeln(
      '[check_imports] $violations deep cross-feature import(s) found.',
    );
    exit(1);
  }
  stdout.writeln('[check_imports] OK');
}

Future<int> _scanDart(Directory featuresRoot) async {
  if (!featuresRoot.existsSync()) return 0;
  var n = 0;
  await for (final entity in featuresRoot.list(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final rel = entity.path.substring(featuresRoot.path.length + 1);
    final owner = rel.split(Platform.pathSeparator).first;
    final inWidgets = rel.contains(
      '${Platform.pathSeparator}widgets${Platform.pathSeparator}',
    );

    final lines = await entity.readAsLines();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('import')) continue;
      final m = RegExp(
        r"""import\s+['"]((?:package:openhand/features/|(?:\.\./)+)([\w_]+)/([\w_./]+))['"]""",
      ).firstMatch(line);
      if (m == null) continue;
      final target = m.group(2)!;
      final sub = m.group(3)!;
      if (target == owner) {
        if (inWidgets && sub.startsWith('service/')) {
          stderr.writeln('${entity.path}:${i + 1} widgets → service forbidden');
          n++;
        }
        continue;
      }
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
