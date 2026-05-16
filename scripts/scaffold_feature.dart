import 'dart:io';

/// Generate a feature directory matching the OpenHand P0 standard template.
///
/// Usage: `dart run scripts/scaffold_feature.dart <feature_name>`
/// where `<feature_name>` must be snake_case.
void main(List<String> args) {
  if (args.length != 1 || args.first.isEmpty) {
    stderr.writeln(
        '[scaffold] usage: dart run scripts/scaffold_feature.dart <feature_name>');
    exit(2);
  }
  final name = args.first;
  if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)) {
    stderr.writeln(
        '[scaffold] feature name must be snake_case (got: $name)');
    exit(2);
  }

  final root = Directory('lib/features/$name');
  if (root.existsSync()) {
    stderr.writeln(
        '[scaffold] lib/features/$name already exists, refusing to overwrite');
    exit(1);
  }

  final pascal = _pascalCase(name);
  root.createSync(recursive: true);

  try {
    for (final sub in const ['model', 'data', 'service', 'widgets', 'state']) {
      final d = Directory('${root.path}/$sub');
      d.createSync(recursive: true);
      File('${d.path}/.gitkeep').writeAsStringSync('');
    }

    File('${root.path}/${name}_controller.dart')
        .writeAsStringSync(_controllerTemplate(pascal));
    File('${root.path}/${name}_module.dart')
        .writeAsStringSync(_moduleTemplate(pascal, name));
    File('${root.path}/index.dart').writeAsStringSync(_indexTemplate(name));
    File('${root.path}/README.md').writeAsStringSync(_readmeTemplate(name));
  } catch (e, st) {
    stderr.writeln('[scaffold] failed: $e');
    stderr.writeln(st);
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
    exit(1);
  }

  stdout.writeln('[scaffold] generated lib/features/$name');
}

String _pascalCase(String snake) {
  return snake
      .split('_')
      .where((p) => p.isNotEmpty)
      .map((p) => p[0].toUpperCase() + p.substring(1))
      .join();
}

String _controllerTemplate(String pascal) => '''
import 'package:flutter/foundation.dart';

/// $pascal feature controller.
///
/// TODO: 描述该 controller 的职责与生命周期。
class ${pascal}Controller extends ChangeNotifier {
  ${pascal}Controller._();

  static Future<${pascal}Controller> create() async {
    final controller = ${pascal}Controller._();
    // TODO: 异步初始化（加载持久化、订阅依赖等）。
    return controller;
  }
}
''';

String _moduleTemplate(String pascal, String snake) => '''
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '${snake}_controller.dart';

/// $pascal feature 模块装配入口。
class ${pascal}Module {
  ${pascal}Module._();

  /// 构造并初始化 controller。
  static Future<${pascal}Controller> bootstrap() {
    return ${pascal}Controller.create();
  }

  /// 暴露给上层 MultiProvider 的 provider 列表。
  static List<SingleChildWidget> providers(${pascal}Controller controller) {
    return [
      ChangeNotifierProvider<${pascal}Controller>.value(value: controller),
    ];
  }
}
''';

String _indexTemplate(String snake) => '''
export '${snake}_controller.dart';
export '${snake}_module.dart';
''';

String _readmeTemplate(String snake) => '''
# $snake

## 职责
TODO: 描述该 feature 在 OpenHand 中负责的领域。

## 对外 API
TODO: 列出 controller / module 暴露给其他 feature 的方法与事件。

## 依赖
TODO: 列出依赖的 service / repository / 其他 feature。

## 不变量
TODO: 描述该 feature 必须维持的不变量与禁忌。
''';
